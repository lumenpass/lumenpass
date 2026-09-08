import Foundation
import CryptoKit
import FlutterMacOS
import Darwin

// MARK: - SSH Agent Protocol Constants
private let kReqIdentities: UInt8 = 11
private let kResIdentities: UInt8 = 12
private let kReqSign:       UInt8 = 13
private let kResSign:       UInt8 = 14
private let kFailure:       UInt8 = 5

// MARK: - Internal types

private final class PendingRequest {
  let sem = DispatchSemaphore(value: 0)
  var approved = false
}

private struct AgentKey {
  let name: String
  let pem:  String
  let blob: Data  // SSH wire-format public key blob
}

private struct RequesterContext {
  let pid: Int32?
  let processName: String
  let executablePath: String?

  var displayName: String {
    if processName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Requesting Process"
    }
    return processName
  }
}

private struct ApprovalCacheEntry {
  let expiresAt: Date
}

private let kApprovalCacheTTL: TimeInterval = 15 * 60  // 15 minutes

// MARK: - SshAgentServer

@objc public class SshAgentServer: NSObject {

  @objc public static let shared = SshAgentServer()

  @objc public private(set) var isRunning = false
  @objc public private(set) var socketPath = ""

  private var keys: [AgentKey] = []
  private var serverFd: Int32 = -1
  private let acceptQ = DispatchQueue(label: "lp.sshagent.accept", qos: .default)
  private var pending = [Int: PendingRequest]()
  private let lock = NSLock()
  private var nextId = 0
  // Cache of approved (keyName, requesterName) pairs to avoid repeated prompts.
  private var approvalCache = [String: ApprovalCacheEntry]()

  var channel: FlutterMethodChannel?

  // MARK: Lifecycle

  @objc public func start() -> String? {
    guard !isRunning else { return socketPath }

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let path = "\(home)/lumenpass-agent.sock"
    NSLog("[SshAgent] start() home=\(home) path=\(path) pathLen=\(path.count)")
    try? FileManager.default.removeItem(atPath: path)

    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    NSLog("[SshAgent] socket() fd=\(fd) errno=\(errno)")
    guard fd >= 0 else { return nil }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len    = UInt8(MemoryLayout<sockaddr_un>.size)
    path.withCString { cptr in
      withUnsafeMutablePointer(to: &addr.sun_path) { sunPtr in
        sunPtr.withMemoryRebound(to: CChar.self, capacity: 104) {
          strncpy($0, cptr, 103)
        }
      }
    }

    let bound = withUnsafePointer(to: addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    let boundErrno = errno
    NSLog("[SshAgent] bind() result=\(bound) errno=\(boundErrno)")
    let listenResult = Darwin.listen(fd, 5)
    let listenErrno = errno
    NSLog("[SshAgent] listen() result=\(listenResult) errno=\(listenErrno)")
    guard bound == 0, listenResult == 0 else {
      NSLog("[SshAgent] start() FAILED — bind=\(bound)(errno=\(boundErrno)) listen=\(listenResult)(errno=\(listenErrno))")
      Darwin.close(fd); return nil
    }

    serverFd   = fd
    socketPath = path
    isRunning  = true
    NSLog("[SshAgent] start() SUCCESS socket at \(path)")
    acceptQ.async { [weak self] in self?.acceptLoop() }
    return path
  }

  @objc public func stop() {
    isRunning = false
    if serverFd >= 0 { Darwin.close(serverFd); serverFd = -1 }
    try? FileManager.default.removeItem(atPath: socketPath)
    socketPath = ""
    lock.lock(); approvalCache.removeAll(); lock.unlock()
  }

  @objc public func setKeys(_ rawKeys: [[String: String]]) {
    NSLog("[SshAgent] setKeys received \(rawKeys.count) key(s)")
    keys = rawKeys.compactMap { d in
      guard let name = d["name"], let pem = d["privateKey"] else {
        NSLog("[SshAgent] setKeys: skipping entry — missing name or pem")
        return nil
      }
      do {
        let blob = try makePublicBlob(pem: pem)
        let pubKeyB64 = blob.base64EncodedString()
        NSLog("[SshAgent] setKeys: parsed '\(name)' OK — pubkey: \(pubKeyB64)")
        return AgentKey(name: name, pem: pem, blob: blob)
      } catch {
        NSLog("[SshAgent] setKeys: FAILED to parse '\(name)': \(error)")
        return nil
      }
    }
    NSLog("[SshAgent] setKeys stored \(keys.count) valid key(s)")
  }

  @objc public func clearKeys() {
    keys = []
    lock.lock(); approvalCache.removeAll(); lock.unlock()
  }

  @objc public func respond(requestId: Int, approved: Bool) {
    lock.lock()
    let req = pending[requestId]
    lock.unlock()
    if let r = req { r.approved = approved; r.sem.signal() }
  }

  // MARK: Accept loop

  private func acceptLoop() {
    while isRunning {
      let fd = Darwin.accept(serverFd, nil, nil)
      if fd < 0 { break }
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        self?.handleClient(fd)
      }
    }
  }

  private func handleClient(_ fd: Int32) {
    var nosig: Int32 = 1
    Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
    defer { Darwin.close(fd) }
    while isRunning {
      guard let msg  = readMsg(fd)   else { break }
      guard let resp = dispatch(msg, clientFd: fd) else { break }
      guard writeMsg(fd, resp)       else { break }
    }
  }

  // MARK: Protocol dispatch

  private func dispatch(_ data: Data, clientFd: Int32) -> Data? {
    guard !data.isEmpty else { return Data([kFailure]) }
    switch data[0] {
    case kReqIdentities: return buildIdentities()
    case kReqSign:       return buildSign(data, clientFd: clientFd)
    default:             return Data([kFailure])
    }
  }

  private func buildIdentities() -> Data {
    NSLog("[SshAgent] buildIdentities serving \(keys.count) key(s)")
    var out = Data([kResIdentities]) + wu32(UInt32(keys.count))
    for k in keys {
      out += wu32(UInt32(k.blob.count)) + k.blob
      let comment = k.name.data(using: .utf8)!
      out += wu32(UInt32(comment.count)) + comment
    }
    return out
  }

  private func buildSign(_ data: Data, clientFd: Int32) -> Data {
    NSLog("[SshAgent] buildSign called — \(keys.count) key(s) loaded")
    var p = 1
    guard let (keyBlob, p1) = rstr(data, p) else { return Data([kFailure]) }
    guard let (payload,  p2) = rstr(data, p1) else { return Data([kFailure]) }
    p = p2
    guard p + 4 <= data.count else { return Data([kFailure]) }

    guard let key = keys.first(where: { $0.blob == keyBlob }) else {
      return Data([kFailure])
    }

    // Request approval from Flutter
    let req = PendingRequest()
    lock.lock(); nextId += 1; let rid = nextId; pending[rid] = req; lock.unlock()
    let requester = resolveRequesterContext(clientFd: clientFd)
    let requesterPidString = requester.pid.map { String($0) } ?? "unknown"
    NSLog(
      "[SshAgent] sign request requester='\(requester.displayName)' pid=\(requesterPidString) path=\(requester.executablePath ?? "unknown")"
    )

    // Check approval cache before prompting the user.
    let cacheKey = "\(key.name)\0\(requester.displayName)"
    lock.lock()
    let cachedEntry = approvalCache[cacheKey]
    lock.unlock()
    if let entry = cachedEntry, entry.expiresAt > Date() {
      NSLog("[SshAgent] buildSign: cache hit for '\(key.name)' requester='\(requester.displayName)' — skipping dialog")
      lock.lock(); pending.removeValue(forKey: rid); lock.unlock()
    } else {
      DispatchQueue.main.async { [weak self] in
        var args: [String: Any] = [
          "requestId": rid,
          "keyName":   key.name,
          "requesterName": requester.displayName,
        ]
        if let pid = requester.pid {
          args["requesterPid"] = Int(pid)
        }
        if let path = requester.executablePath, !path.isEmpty {
          args["requesterExecutablePath"] = path
        }
        self?.channel?.invokeMethod("onSignRequest", arguments: args)
      }

      let timedOut = req.sem.wait(timeout: .now() + 60) == .timedOut
      lock.lock(); pending.removeValue(forKey: rid); lock.unlock()
      NSLog("[SshAgent] buildSign: timedOut=\(timedOut) approved=\(req.approved)")
      guard !timedOut, req.approved else { return Data([kFailure]) }

      // Cache the approval so subsequent requests within the TTL are auto-approved.
      let expiry = Date().addingTimeInterval(kApprovalCacheTTL)
      lock.lock(); approvalCache[cacheKey] = ApprovalCacheEntry(expiresAt: expiry); lock.unlock()
      NSLog("[SshAgent] buildSign: cached approval for '\(key.name)' until \(expiry)")
    }

    guard let sig = sign(payload, key: key) else {
      NSLog("[SshAgent] buildSign: sign() returned nil")
      return Data([kFailure])
    }
    return Data([kResSign]) + wu32(UInt32(sig.count)) + sig
  }

  // MARK: Signing

  private func sign(_ payload: Data, key: AgentKey) -> Data? {
    guard let parsed = try? OpenSSHKeyParser.parse(key.pem) else {
      NSLog("[SshAgent] sign: parse FAILED for '\(key.name)'")
      return nil
    }
    NSLog("[SshAgent] sign: keyType=\(parsed.keyType) privBytes=\(parsed.privBytes.count)")
    switch parsed.keyType {
    case "ssh-ed25519":           return signEd25519(payload, parsed.privBytes)
    case "ecdsa-sha2-nistp256":   return signEcdsaP256(payload, parsed.privBytes)
    default:                      return nil
    }
  }

  private func signEd25519(_ data: Data, _ privBytes: Data) -> Data? {
    guard privBytes.count >= 32,
          let privKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privBytes.prefix(32))
    else { return nil }
    guard let sig = try? privKey.signature(for: data) else { return nil }
    let sigData = Data(sig)
    return wstr("ssh-ed25519") + wu32(UInt32(sigData.count)) + sigData
  }

  private func signEcdsaP256(_ data: Data, _ privBytes: Data) -> Data? {
    guard let privKey = try? P256.Signing.PrivateKey(rawRepresentation: privBytes) else { return nil }
    guard let sig = try? privKey.signature(for: data) else { return nil }
    let raw = sig.rawRepresentation
    let r   = Data(raw.prefix(32))
    let s   = Data(raw.suffix(32))
    let rs  = wmpint(r) + wmpint(s)
    return wstr("ecdsa-sha2-nistp256") + wu32(UInt32(rs.count)) + rs
  }

  // MARK: Public key blob extraction

  private func makePublicBlob(pem: String) throws -> Data {
    return try OpenSSHKeyParser.parse(pem).pubBlob
  }

  // MARK: Requester metadata

  private func resolveRequesterContext(clientFd: Int32) -> RequesterContext {
    guard let pid = peerPid(for: clientFd) else {
      return RequesterContext(
        pid: nil,
        processName: "Requesting Process",
        executablePath: nil
      )
    }

    let path = processExecutablePath(pid: pid)
    let processName = processName(pid: pid)
      ?? (path as NSString?)?.lastPathComponent
      ?? "Process \(pid)"

    return RequesterContext(
      pid: pid,
      processName: processName,
      executablePath: path
    )
  }

  private func peerPid(for fd: Int32) -> Int32? {
    var pid: Int32 = 0
    var len = socklen_t(MemoryLayout<Int32>.size)
    let rc = withUnsafeMutablePointer(to: &pid) { ptr in
      Darwin.getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, ptr, &len)
    }
    guard rc == 0, pid > 0 else { return nil }
    return pid
  }

  private func processName(pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 512)
    let copied = proc_name(pid_t(pid), &buffer, UInt32(buffer.count))
    guard copied > 0 else { return nil }
    return String(cString: buffer)
  }

  private func processExecutablePath(pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    let copied = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
    guard copied > 0 else { return nil }
    return String(cString: buffer)
  }

  // MARK: Socket I/O

  private func readMsg(_ fd: Int32) -> Data? {
    var hdr = [UInt8](repeating: 0, count: 4)
    guard readAll(fd, &hdr, 4) else { return nil }
    let len = Int(rru32(Data(hdr), 0))
    guard len > 0, len < 65_536 else { return nil }
    var body = [UInt8](repeating: 0, count: len)
    guard readAll(fd, &body, len) else { return nil }
    return Data(body)
  }

  private func writeMsg(_ fd: Int32, _ data: Data) -> Bool {
    var hdr = wu32(UInt32(data.count))
    let hdrOk = hdr.withUnsafeMutableBytes { p in Darwin.write(fd, p.baseAddress!, 4) == 4 }
    guard hdrOk else {
      NSLog("[SshAgent] writeMsg FAILED header: errno=\(errno)")
      return false
    }
    let ok = data.withUnsafeBytes { p -> Bool in
      var sent = 0; let n = data.count
      while sent < n {
        let r = Darwin.write(fd, p.baseAddress! + sent, n - sent)
        guard r > 0 else { return false }
        sent += r
      }
      return true
    }
    if !ok { NSLog("[SshAgent] writeMsg FAILED body: errno=\(errno)") }
    else   { NSLog("[SshAgent] writeMsg OK: \(4 + data.count) bytes") }
    return ok
  }

  @discardableResult
  private func readAll(_ fd: Int32, _ buf: inout [UInt8], _ n: Int) -> Bool {
    var ok = false
    buf.withUnsafeMutableBytes { p -> Void in
      var done = 0
      while done < n {
        let r = Darwin.read(fd, p.baseAddress! + done, n - done)
        guard r > 0 else { return }
        done += r
      }
      ok = true
    }
    return ok
  }

  // MARK: Wire helpers

  private func wu32(_ v: UInt32) -> Data {
    var be = v.bigEndian; return withUnsafeBytes(of: &be) { Data($0) }
  }
  private func rru32(_ d: Data, _ p: Int) -> UInt32 {
    guard p + 4 <= d.count else { return 0 }
    return (UInt32(d[p]) << 24) | (UInt32(d[p+1]) << 16) | (UInt32(d[p+2]) << 8) | UInt32(d[p+3])
  }
  private func rstr(_ d: Data, _ p: Int) -> (Data, Int)? {
    guard p + 4 <= d.count else { return nil }
    let len = Int(rru32(d, p))
    let end = p + 4 + len
    guard end <= d.count else { return nil }
    return (Data(d[p+4..<end]), end)
  }
  private func wstr(_ s: String) -> Data {
    let b = s.data(using: .utf8)!; return wu32(UInt32(b.count)) + b
  }
  private func wmpint(_ bytes: Data) -> Data {
    var b = bytes
    while b.count > 1, b[b.startIndex] == 0 { b = b.dropFirst() }
    if !b.isEmpty, b[b.startIndex] & 0x80 != 0 { b = Data([0]) + b }
    return wu32(UInt32(b.count)) + b
  }
}

// MARK: - OpenSSH Private Key Parser

private struct ParsedKey {
  let keyType:  String
  let pubBlob:  Data
  let privBytes: Data
}

private enum SSHKeyError: Error {
  case invalidPEM, badMagic, parseError, encrypted, unsupported(String)
}

private enum OpenSSHKeyParser {
  static func parse(_ pem: String) throws -> ParsedKey {
    let cleaned = pem.replacingOccurrences(of: "\r\n", with: "\n")
                      .replacingOccurrences(of: "\r", with: "\n")
    let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: true)
      .filter { !$0.hasPrefix("-----") }
    guard let raw = Data(base64Encoded: lines.joined(),
                         options: .ignoreUnknownCharacters) else {
      throw SSHKeyError.invalidPEM
    }

    var r = SSHReader(raw)

    let magic = "openssh-key-v1"
    guard r.bytes(magic.utf8.count) == magic.data(using: .utf8),
          r.byte() == 0
    else { throw SSHKeyError.badMagic }

    guard let cipher = r.sshStr() else { throw SSHKeyError.parseError }
    guard cipher == "none"        else { throw SSHKeyError.encrypted }
    guard r.sshStr() != nil, r.sshBytes() != nil else { throw SSHKeyError.parseError }

    guard let nkeys = r.u32(), nkeys >= 1 else { throw SSHKeyError.parseError }

    guard let pubBlob = r.sshBytes() else { throw SSHKeyError.parseError }
    for _ in 1..<nkeys { _ = r.sshBytes() }

    guard let privSection = r.sshBytes() else { throw SSHKeyError.parseError }
    var pr = SSHReader(privSection)

    guard let c1 = pr.u32(), let c2 = pr.u32(), c1 == c2 else {
      throw SSHKeyError.parseError
    }

    guard let keyType = pr.sshStr() else { throw SSHKeyError.parseError }

    let privBytes: Data
    switch keyType {
    case "ssh-ed25519":
      _ = pr.sshBytes()
      guard let full = pr.sshBytes(), full.count >= 32 else { throw SSHKeyError.parseError }
      privBytes = Data(full.prefix(32))

    case "ecdsa-sha2-nistp256":
      _ = pr.sshStr()
      _ = pr.sshBytes()
      guard let scalar = pr.sshBytes() else { throw SSHKeyError.parseError }
      privBytes = scalar

    default:
      throw SSHKeyError.unsupported(keyType)
    }

    return ParsedKey(keyType: keyType, pubBlob: pubBlob, privBytes: privBytes)
  }
}

private struct SSHReader {
  let data: Data
  var pos:  Int = 0

  init(_ d: Data) { data = d }

  mutating func byte() -> UInt8? {
    guard pos < data.count else { return nil }
    defer { pos += 1 }; return data[pos]
  }
  mutating func bytes(_ n: Int) -> Data? {
    guard pos + n <= data.count else { return nil }
    defer { pos += n }; return Data(data[pos..<pos+n])
  }
  mutating func u32() -> UInt32? {
    guard let d = bytes(4) else { return nil }
    return UInt32(bigEndian: d.withUnsafeBytes { $0.load(as: UInt32.self) })
  }
  mutating func sshBytes() -> Data? {
    guard let len = u32() else { return nil }; return bytes(Int(len))
  }
  mutating func sshStr() -> String? {
    guard let d = sshBytes() else { return nil }
    return String(data: d, encoding: .utf8)
  }
}
