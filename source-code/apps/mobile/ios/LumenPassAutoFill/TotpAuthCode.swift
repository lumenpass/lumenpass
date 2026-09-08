// TotpAuthCode.swift
//
// TOTP from otpauth:// URIs — RFC 6238 compliant, defaults to SHA1.

import CryptoKit
import Foundation

enum TotpAuthCode {

    static func currentCode(otpAuthUrl: String?, date: Date = Date()) -> String? {
        guard let otpAuthUrl, !otpAuthUrl.isEmpty,
              let parts = parse(otpAuthUrl) else { return nil }

        let ms = Int64(date.timeIntervalSince1970 * 1000)
        let epochSec = ms / 1000
        let counter = epochSec / Int64(parts.period)
        let counterData = uint64BigEndianData(UInt64(counter))

        let digest: Data
        switch parts.algorithm {
        case .sha1:
            digest = Data(HMAC<Insecure.SHA1>.authenticationCode(
                for: counterData,
                using: SymmetricKey(data: parts.secretBytes)
            ))
        case .sha256:
            digest = Data(HMAC<SHA256>.authenticationCode(
                for: counterData,
                using: SymmetricKey(data: parts.secretBytes)
            ))
        case .sha512:
            digest = Data(HMAC<SHA512>.authenticationCode(
                for: counterData,
                using: SymmetricKey(data: parts.secretBytes)
            ))
        }

        let d = [UInt8](digest)
        guard !d.isEmpty else { return nil }
        let offset = Int(d[d.count - 1] & 0x0f)
        guard offset + 3 < d.count else { return nil }
        let binary = ((Int(d[offset]) & 0x7f) << 24)
            | ((Int(d[offset + 1]) & 0xff) << 16)
            | ((Int(d[offset + 2]) & 0xff) << 8)
            | (Int(d[offset + 3]) & 0xff)

        let mod = Int(pow(10.0, Double(parts.digits)))
        let v = binary % mod
        let positive = ((v % mod) + mod) % mod
        return String(format: "%0\(parts.digits)d", positive)
    }

    static func secondsRemaining(otpAuthUrl: String?, date: Date = Date()) -> Int? {
        guard let p = parse(otpAuthUrl ?? "") else { return nil }
        let now = Int64(date.timeIntervalSince1970)
        let remainder = now % Int64(p.period)
        return remainder == 0 ? p.period : p.period - Int(remainder)
    }

    private struct Parsed {
        let secretBytes: Data
        let period: Int
        let digits: Int
        let algorithm: HashAlgorithm
    }

    private enum HashAlgorithm { case sha1, sha256, sha512 }

    private static func parse(_ raw: String) -> Parsed? {
        guard let url = URL(string: raw),
              url.scheme == "otpauth",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return nil }

        guard let secretStr = items.first(where: { $0.name.lowercased() == "secret" })?.value,
              !secretStr.isEmpty,
              let secretBytes = base32Decode(secretStr) else { return nil }

        let period = Int(items.first(where: { $0.name.lowercased() == "period" })?.value ?? "") ?? 30
        let digits = Int(items.first(where: { $0.name.lowercased() == "digits" })?.value ?? "") ?? 6
        let algRaw = (items.first(where: { $0.name.lowercased() == "algorithm" })?.value ?? "SHA1").uppercased()
        let algorithm: HashAlgorithm
        switch algRaw {
        case "SHA256": algorithm = .sha256
        case "SHA512": algorithm = .sha512
        default: algorithm = .sha1
        }

        let p = max(1, period)
        let dig = max(6, min(10, digits))
        return Parsed(secretBytes: secretBytes, period: p, digits: dig, algorithm: algorithm)
    }

    private static func uint64BigEndianData(_ value: UInt64) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: 8)
    }

    private static func base32Decode(_ string: String) -> Data? {
        let map: [UInt8: UInt8] = [
            UInt8(ascii: "A"): 0, UInt8(ascii: "B"): 1, UInt8(ascii: "C"): 2, UInt8(ascii: "D"): 3,
            UInt8(ascii: "E"): 4, UInt8(ascii: "F"): 5, UInt8(ascii: "G"): 6, UInt8(ascii: "H"): 7,
            UInt8(ascii: "I"): 8, UInt8(ascii: "J"): 9, UInt8(ascii: "K"): 10, UInt8(ascii: "L"): 11,
            UInt8(ascii: "M"): 12, UInt8(ascii: "N"): 13, UInt8(ascii: "O"): 14, UInt8(ascii: "P"): 15,
            UInt8(ascii: "Q"): 16, UInt8(ascii: "R"): 17, UInt8(ascii: "S"): 18, UInt8(ascii: "T"): 19,
            UInt8(ascii: "U"): 20, UInt8(ascii: "V"): 21, UInt8(ascii: "W"): 22, UInt8(ascii: "X"): 23,
            UInt8(ascii: "Y"): 24, UInt8(ascii: "Z"): 25, UInt8(ascii: "2"): 26, UInt8(ascii: "3"): 27,
            UInt8(ascii: "4"): 28, UInt8(ascii: "5"): 29, UInt8(ascii: "6"): 30, UInt8(ascii: "7"): 31,
        ]
        var buffer: UInt64 = 0
        var bitsLeft = 0
        var out = [UInt8]()
        let cleaned = string.uppercased().filter { !$0.isWhitespace }
        for ch in cleaned {
            if ch == "=" { break }
            guard let ascii = ch.asciiValue, let v = map[ascii] else { return nil }
            buffer = (buffer << 5) | UInt64(v)
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                out.append(UInt8((buffer >> bitsLeft) & 0xFF))
            }
        }
        return out.isEmpty ? nil : Data(out)
    }
}
