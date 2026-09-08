// Define WIN32_NO_STATUS up front so the windows.h chain pulled in via our
// own header skips its STATUS_* macros. We include the real STATUS_* macros
// from <ntstatus.h> below for BCrypt status checks.
#define WIN32_NO_STATUS
#include "ssh_agent_server.h"

#include "ssh_agent_ed25519.h"

#include <flutter/encodable_value.h>

#undef WIN32_NO_STATUS
#include <ntstatus.h>

#include <bcrypt.h>
#include <sddl.h>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <utility>

#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "advapi32.lib")

namespace lumenpass {

namespace {

constexpr uint8_t kReqIdentities = 11;
constexpr uint8_t kResIdentities = 12;
constexpr uint8_t kReqSign       = 13;
constexpr uint8_t kResSign       = 14;
constexpr uint8_t kFailure       = 5;

constexpr DWORD kApprovalCacheTtlMs = 15 * 60 * 1000;  // 15 minutes
constexpr DWORD kApprovalTimeoutMs  = 60 * 1000;       // 60 seconds
constexpr DWORD kPipeBuffer         = 64 * 1024;

constexpr wchar_t kPrimaryPipeName[]   = L"\\\\.\\pipe\\openssh-ssh-agent";
constexpr wchar_t kFallbackPipeName[]  = L"\\\\.\\pipe\\lumenpass-ssh-agent";

std::string Utf8FromUtf16(const std::wstring& s) {
  if (s.empty()) return {};
  int n = ::WideCharToMultiByte(CP_UTF8, 0, s.data(),
                                static_cast<int>(s.size()), nullptr, 0,
                                nullptr, nullptr);
  if (n <= 0) return {};
  std::string out(n, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        out.data(), n, nullptr, nullptr);
  return out;
}

uint32_t ReadU32(const uint8_t* p) {
  return (static_cast<uint32_t>(p[0]) << 24) |
         (static_cast<uint32_t>(p[1]) << 16) |
         (static_cast<uint32_t>(p[2]) << 8)  |
         static_cast<uint32_t>(p[3]);
}

void WriteU32(std::vector<uint8_t>& out, uint32_t v) {
  out.push_back(static_cast<uint8_t>((v >> 24) & 0xff));
  out.push_back(static_cast<uint8_t>((v >> 16) & 0xff));
  out.push_back(static_cast<uint8_t>((v >> 8)  & 0xff));
  out.push_back(static_cast<uint8_t>(v & 0xff));
}

void WriteString(std::vector<uint8_t>& out, const std::string& s) {
  WriteU32(out, static_cast<uint32_t>(s.size()));
  out.insert(out.end(), s.begin(), s.end());
}

void WriteBytes(std::vector<uint8_t>& out, const uint8_t* data, size_t len) {
  WriteU32(out, static_cast<uint32_t>(len));
  out.insert(out.end(), data, data + len);
}

void WriteBytes(std::vector<uint8_t>& out, const std::vector<uint8_t>& v) {
  WriteBytes(out, v.data(), v.size());
}

// Encode a big-endian unsigned integer as an SSH "mpint" (positive,
// minimally-encoded with a leading 0 byte if MSB is set).
void WriteMpInt(std::vector<uint8_t>& out, const uint8_t* data, size_t len) {
  size_t start = 0;
  while (start + 1 < len && data[start] == 0) ++start;
  bool prepend_zero = (start < len) && ((data[start] & 0x80) != 0);
  size_t mp_len = (len - start) + (prepend_zero ? 1 : 0);
  WriteU32(out, static_cast<uint32_t>(mp_len));
  if (prepend_zero) out.push_back(0);
  out.insert(out.end(), data + start, data + len);
}

class SshReader {
 public:
  SshReader(const uint8_t* data, size_t len) : data_(data), len_(len) {}

  bool U32(uint32_t* out) {
    if (pos_ + 4 > len_) return false;
    *out = ReadU32(data_ + pos_);
    pos_ += 4;
    return true;
  }
  bool Bytes(size_t n, const uint8_t** out) {
    if (pos_ + n > len_) return false;
    *out = data_ + pos_;
    pos_ += n;
    return true;
  }
  bool SshString(std::string* out) {
    uint32_t n;
    if (!U32(&n)) return false;
    const uint8_t* p;
    if (!Bytes(n, &p)) return false;
    out->assign(reinterpret_cast<const char*>(p), n);
    return true;
  }
  bool SshBytes(std::vector<uint8_t>* out) {
    uint32_t n;
    if (!U32(&n)) return false;
    const uint8_t* p;
    if (!Bytes(n, &p)) return false;
    out->assign(p, p + n);
    return true;
  }
  size_t Remaining() const { return len_ - pos_; }
  size_t Pos() const { return pos_; }

 private:
  const uint8_t* data_;
  size_t len_;
  size_t pos_ = 0;
};

// Base64 decode (ignore whitespace and newlines).
std::vector<uint8_t> Base64Decode(const std::string& in) {
  static int8_t t[256];
  static bool init = false;
  if (!init) {
    for (int i = 0; i < 256; ++i) t[i] = -1;
    const char* alpha =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (int i = 0; i < 64; ++i) t[static_cast<uint8_t>(alpha[i])] =
        static_cast<int8_t>(i);
    init = true;
  }

  std::vector<uint8_t> out;
  out.reserve(in.size() * 3 / 4);
  uint32_t acc = 0;
  int bits = 0;
  for (char ch : in) {
    if (ch == '=' || ch == '\n' || ch == '\r' || ch == ' ' || ch == '\t') {
      continue;
    }
    int8_t v = t[static_cast<uint8_t>(ch)];
    if (v < 0) continue;
    acc = (acc << 6) | static_cast<uint32_t>(v);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push_back(static_cast<uint8_t>((acc >> bits) & 0xff));
    }
  }
  return out;
}

// Parse an OpenSSH new-format private key (-----BEGIN OPENSSH PRIVATE KEY-----)
// supporting unencrypted ssh-ed25519 and ecdsa-sha2-nistp256 entries. Returns
// false on any parse error or if the key is encrypted/unsupported.
bool ParseOpenSshPrivateKey(const std::string& pem, SshAgentKey* out) {
  // Strip headers/footers and base64-decode the body.
  std::string body;
  {
    size_t pos = 0;
    while (pos < pem.size()) {
      size_t nl = pem.find('\n', pos);
      std::string line = (nl == std::string::npos)
          ? pem.substr(pos)
          : pem.substr(pos, nl - pos);
      pos = (nl == std::string::npos) ? pem.size() : nl + 1;
      // Drop trailing CR.
      if (!line.empty() && line.back() == '\r') line.pop_back();
      if (line.empty()) continue;
      if (line.compare(0, 5, "-----") == 0) continue;
      body += line;
    }
  }
  std::vector<uint8_t> raw = Base64Decode(body);
  if (raw.empty()) return false;

  SshReader r(raw.data(), raw.size());
  static const char kMagic[] = "openssh-key-v1";
  const uint8_t* magic;
  if (!r.Bytes(sizeof(kMagic), &magic)) return false;
  if (std::memcmp(magic, kMagic, sizeof(kMagic)) != 0) return false;

  std::string cipher;
  if (!r.SshString(&cipher)) return false;
  if (cipher != "none") return false;
  std::string kdf_name;
  if (!r.SshString(&kdf_name)) return false;
  std::vector<uint8_t> kdf_options;
  if (!r.SshBytes(&kdf_options)) return false;

  uint32_t nkeys;
  if (!r.U32(&nkeys) || nkeys < 1) return false;

  std::vector<uint8_t> pub_blob;
  if (!r.SshBytes(&pub_blob)) return false;
  for (uint32_t i = 1; i < nkeys; ++i) {
    std::vector<uint8_t> dummy;
    if (!r.SshBytes(&dummy)) return false;
  }

  std::vector<uint8_t> priv_section;
  if (!r.SshBytes(&priv_section)) return false;

  SshReader pr(priv_section.data(), priv_section.size());
  uint32_t check1, check2;
  if (!pr.U32(&check1) || !pr.U32(&check2) || check1 != check2) return false;

  std::string key_type;
  if (!pr.SshString(&key_type)) return false;

  if (key_type == "ssh-ed25519") {
    std::vector<uint8_t> pk, full;
    if (!pr.SshBytes(&pk) || !pr.SshBytes(&full)) return false;
    if (full.size() < 32) return false;
    out->key_type = key_type;
    out->pub_blob = std::move(pub_blob);
    out->priv.assign(full.begin(), full.begin() + 32);
    return true;
  }
  if (key_type == "ecdsa-sha2-nistp256") {
    std::string curve_name;
    std::vector<uint8_t> point;
    std::vector<uint8_t> scalar;
    if (!pr.SshString(&curve_name) ||
        !pr.SshBytes(&point) ||
        !pr.SshBytes(&scalar)) {
      return false;
    }
    if (curve_name != "nistp256") return false;
    if (scalar.empty() || scalar.size() > 33) return false;
    // Strip optional leading 0x00 mpint byte and left-pad to exactly 32 bytes.
    while (scalar.size() > 32 && scalar.front() == 0) {
      scalar.erase(scalar.begin());
    }
    if (scalar.size() > 32) return false;
    if (scalar.size() < 32) {
      std::vector<uint8_t> padded(32 - scalar.size(), 0);
      padded.insert(padded.end(), scalar.begin(), scalar.end());
      scalar = std::move(padded);
    }
    out->key_type = key_type;
    out->pub_blob = std::move(pub_blob);
    out->priv = std::move(scalar);
    return true;
  }
  return false;
}

bool Ed25519Sign(const SshAgentKey& key,
                 const std::vector<uint8_t>& payload,
                 std::vector<uint8_t>* sig_blob) {
  uint8_t sig[64];
  if (!::lumenpass::Ed25519Sign(key.priv.data(), payload.data(),
                                payload.size(), sig)) {
    return false;
  }
  std::vector<uint8_t> inner;
  WriteString(inner, std::string("ssh-ed25519"));
  WriteBytes(inner, sig, sizeof(sig));
  *sig_blob = std::move(inner);
  return true;
}

bool EcdsaP256Sign(const SshAgentKey& key,
                   const std::vector<uint8_t>& payload,
                   std::vector<uint8_t>* sig_blob) {
  // Extract X/Y from the public blob: string("ecdsa-sha2-nistp256"),
  // string("nistp256"), then point Q encoded as 0x04 || X || Y (65 bytes).
  SshReader pr(key.pub_blob.data(), key.pub_blob.size());
  std::string ktype, curve;
  std::vector<uint8_t> point;
  if (!pr.SshString(&ktype) || !pr.SshString(&curve) ||
      !pr.SshBytes(&point)) {
    return false;
  }
  if (ktype != "ecdsa-sha2-nistp256" || curve != "nistp256") return false;
  if (point.size() != 65 || point[0] != 0x04) return false;

  // Build BCRYPT_ECCKEY_BLOB for BCRYPT_ECDSA_PRIVATE_P256_MAGIC.
  // Layout: BCRYPT_ECCKEY_BLOB header (8 bytes) || X(32) || Y(32) || d(32).
  struct EccKeyBlobHeader {
    ULONG magic;
    ULONG cb_key;
  };
  std::vector<uint8_t> blob(sizeof(EccKeyBlobHeader) + 32 + 32 + 32);
  EccKeyBlobHeader hdr{};
  hdr.magic  = 0x32534345;  // 'ECS2' BCRYPT_ECDSA_PRIVATE_P256_MAGIC
  hdr.cb_key = 32;
  std::memcpy(blob.data(), &hdr, sizeof(hdr));
  std::memcpy(blob.data() + sizeof(hdr),                  &point[1],   32);
  std::memcpy(blob.data() + sizeof(hdr) + 32,             &point[33],  32);
  std::memcpy(blob.data() + sizeof(hdr) + 64,             key.priv.data(), 32);

  BCRYPT_ALG_HANDLE alg = nullptr;
  if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_ECDSA_P256_ALGORITHM, nullptr,
                                  0) != STATUS_SUCCESS) {
    return false;
  }
  BCRYPT_KEY_HANDLE bkey = nullptr;
  NTSTATUS st = BCryptImportKeyPair(alg, nullptr, BCRYPT_ECCPRIVATE_BLOB, &bkey,
                                    blob.data(),
                                    static_cast<ULONG>(blob.size()), 0);
  if (st != STATUS_SUCCESS) {
    BCryptCloseAlgorithmProvider(alg, 0);
    return false;
  }

  // SHA-256 the payload.
  uint8_t digest[32];
  {
    BCRYPT_ALG_HANDLE halg = nullptr;
    BCryptOpenAlgorithmProvider(&halg, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
    BCRYPT_HASH_HANDLE h = nullptr;
    BCryptCreateHash(halg, &h, nullptr, 0, nullptr, 0, 0);
    BCryptHashData(h,
                   const_cast<UCHAR*>(reinterpret_cast<const UCHAR*>(payload.data())),
                   static_cast<ULONG>(payload.size()), 0);
    BCryptFinishHash(h, digest, sizeof(digest), 0);
    BCryptDestroyHash(h);
    BCryptCloseAlgorithmProvider(halg, 0);
  }

  uint8_t raw_sig[64] = {0};
  ULONG produced = 0;
  st = BCryptSignHash(bkey, nullptr, digest, sizeof(digest), raw_sig,
                      sizeof(raw_sig), &produced, 0);
  BCryptDestroyKey(bkey);
  BCryptCloseAlgorithmProvider(alg, 0);
  if (st != STATUS_SUCCESS || produced != 64) return false;

  // SSH ECDSA signature: string("ecdsa-sha2-nistp256") || string(rs)
  // where rs = mpint(r) || mpint(s).
  std::vector<uint8_t> rs;
  WriteMpInt(rs, raw_sig, 32);
  WriteMpInt(rs, raw_sig + 32, 32);

  std::vector<uint8_t> inner;
  WriteString(inner, std::string("ecdsa-sha2-nistp256"));
  WriteBytes(inner, rs);
  *sig_blob = std::move(inner);
  return true;
}

std::string ResolveClientProcessName(HANDLE pipe) {
  ULONG pid = 0;
  if (!::GetNamedPipeClientProcessId(pipe, &pid)) return "Requesting Process";
  HANDLE proc =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!proc) {
    return "Process " + std::to_string(pid);
  }
  wchar_t path[MAX_PATH] = {0};
  DWORD size = MAX_PATH;
  std::string name;
  if (::QueryFullProcessImageNameW(proc, 0, path, &size)) {
    std::wstring wpath(path, size);
    size_t slash = wpath.find_last_of(L"\\/");
    std::wstring leaf = (slash == std::wstring::npos)
        ? wpath
        : wpath.substr(slash + 1);
    name = Utf8FromUtf16(leaf);
  }
  ::CloseHandle(proc);
  if (name.empty()) name = "Process " + std::to_string(pid);
  return name;
}

ULONG GetClientPid(HANDLE pipe) {
  ULONG pid = 0;
  ::GetNamedPipeClientProcessId(pipe, &pid);
  return pid;
}

std::string GetClientImagePath(HANDLE pipe) {
  ULONG pid = GetClientPid(pipe);
  if (pid == 0) return {};
  HANDLE proc = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!proc) return {};
  wchar_t path[MAX_PATH] = {0};
  DWORD size = MAX_PATH;
  std::string out;
  if (::QueryFullProcessImageNameW(proc, 0, path, &size)) {
    out = Utf8FromUtf16(std::wstring(path, size));
  }
  ::CloseHandle(proc);
  return out;
}

// Read exactly len bytes from the pipe.
bool ReadAll(HANDLE pipe, void* buf, DWORD len) {
  DWORD got = 0;
  while (got < len) {
    DWORD n = 0;
    if (!::ReadFile(pipe, static_cast<uint8_t*>(buf) + got, len - got, &n,
                    nullptr) || n == 0) {
      return false;
    }
    got += n;
  }
  return true;
}

bool WriteAll(HANDLE pipe, const void* buf, DWORD len) {
  DWORD sent = 0;
  while (sent < len) {
    DWORD n = 0;
    if (!::WriteFile(pipe, static_cast<const uint8_t*>(buf) + sent,
                     len - sent, &n, nullptr) || n == 0) {
      return false;
    }
    sent += n;
  }
  return true;
}

}  // namespace

// ─────────────────────────────────────────────────────────────────────────────

SshAgentServer& SshAgentServer::Instance() {
  static SshAgentServer instance;
  return instance;
}

SshAgentServer::SshAgentServer() = default;

SshAgentServer::~SshAgentServer() { Stop(); }

void SshAgentServer::Register(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lumenpass/ssh_agent",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleMethodCall(call, std::move(result));
      });
  ui_thread_id_ = ::GetCurrentThreadId();
  EnsureMarshaller();
}

LRESULT CALLBACK SshAgentServer::MarshallerWndProc(HWND hwnd, UINT msg,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  static constexpr UINT WM_LP_RUN = WM_USER + 1;
  if (msg == WM_LP_RUN) {
    auto* fn = reinterpret_cast<std::function<void()>*>(lparam);
    if (fn) {
      (*fn)();
      delete fn;
    }
    return 0;
  }
  return ::DefWindowProcW(hwnd, msg, wparam, lparam);
}

void SshAgentServer::EnsureMarshaller() {
  if (marshaller_) return;
  static const wchar_t* kClass = L"LumenPassSshAgentMarshaller";
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = &SshAgentServer::MarshallerWndProc;
  wc.hInstance = ::GetModuleHandleW(nullptr);
  wc.lpszClassName = kClass;
  ::RegisterClassExW(&wc);
  marshaller_ = ::CreateWindowExW(0, kClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                                  nullptr, wc.hInstance, nullptr);
}

void SshAgentServer::PostToUiThread(std::function<void()> fn) {
  if (!marshaller_) return;
  static constexpr UINT WM_LP_RUN = WM_USER + 1;
  auto* heap_fn = new std::function<void()>(std::move(fn));
  if (!::PostMessageW(marshaller_, WM_LP_RUN, 0,
                      reinterpret_cast<LPARAM>(heap_fn))) {
    delete heap_fn;
  }
}

void SshAgentServer::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  auto parse_keys = [](const flutter::EncodableValue* args) {
    std::vector<SshAgentKey> out;
    const auto* map = std::get_if<flutter::EncodableMap>(args);
    if (!map) return out;
    auto it = map->find(flutter::EncodableValue("keys"));
    if (it == map->end()) return out;
    const auto* list = std::get_if<flutter::EncodableList>(&it->second);
    if (!list) return out;
    for (const auto& entry : *list) {
      const auto* m = std::get_if<flutter::EncodableMap>(&entry);
      if (!m) continue;
      auto name_it = m->find(flutter::EncodableValue("name"));
      auto pem_it  = m->find(flutter::EncodableValue("privateKey"));
      if (name_it == m->end() || pem_it == m->end()) continue;
      const auto* name = std::get_if<std::string>(&name_it->second);
      const auto* pem  = std::get_if<std::string>(&pem_it->second);
      if (!name || !pem) continue;
      SshAgentKey k;
      k.name = *name;
      if (!ParseOpenSshPrivateKey(*pem, &k)) continue;
      out.push_back(std::move(k));
    }
    return out;
  };

  if (method == "startAgent") {
    auto keys = parse_keys(call.arguments());
    std::string path = Start(keys);
    if (path.empty()) {
      result->Error("AGENT_START_FAILED", "Could not start SSH agent pipe");
    } else {
      result->Success(flutter::EncodableValue(path));
    }
    return;
  }
  if (method == "stopAgent") {
    Stop();
    result->Success();
    return;
  }
  if (method == "setKeys") {
    auto keys = parse_keys(call.arguments());
    SetKeys(keys);
    result->Success();
    return;
  }
  if (method == "signResponse") {
    const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!map) {
      result->Error("INVALID_ARGS", "Expected map");
      return;
    }
    auto rid_it = map->find(flutter::EncodableValue("requestId"));
    auto ok_it  = map->find(flutter::EncodableValue("approved"));
    if (rid_it == map->end() || ok_it == map->end()) {
      result->Error("INVALID_ARGS", "Missing requestId or approved");
      return;
    }
    int rid = 0;
    if (const auto* i = std::get_if<int32_t>(&rid_it->second)) rid = *i;
    else if (const auto* l = std::get_if<int64_t>(&rid_it->second))
      rid = static_cast<int>(*l);
    const auto* ok = std::get_if<bool>(&ok_it->second);
    if (!ok) {
      result->Error("INVALID_ARGS", "approved must be bool");
      return;
    }
    Respond(rid, *ok);
    result->Success();
    return;
  }
  result->NotImplemented();
}

std::string SshAgentServer::Start(const std::vector<SshAgentKey>& keys) {
  if (running_.load()) {
    SetKeys(keys);
    return Utf8FromUtf16(pipe_name_);
  }

  // Probe whether the well-known pipe is already taken (typically by the
  // built-in OpenSSH Authentication Agent service). If it is, fall back to a
  // LumenPass-specific pipe so the user can switch via SSH_AUTH_SOCK.
  std::wstring chosen;
  HANDLE probe = ::CreateNamedPipeW(
      kPrimaryPipeName,
      PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
      PIPE_UNLIMITED_INSTANCES, kPipeBuffer, kPipeBuffer, 0, nullptr);
  if (probe != INVALID_HANDLE_VALUE) {
    ::CloseHandle(probe);
    chosen = kPrimaryPipeName;
  } else {
    chosen = kFallbackPipeName;
  }
  pipe_name_ = chosen;

  SetKeys(keys);
  running_.store(true);
  accept_thread_ = std::thread([this]() { AcceptLoop(); });
  return Utf8FromUtf16(pipe_name_);
}

void SshAgentServer::Stop() {
  if (!running_.exchange(false)) return;
  // Wake any blocked CreateNamedPipe / ConnectNamedPipe calls by connecting
  // a throwaway client to the same pipe.
  HANDLE waker = ::CreateFileW(pipe_name_.c_str(), GENERIC_READ | GENERIC_WRITE,
                               0, nullptr, OPEN_EXISTING, 0, nullptr);
  if (waker != INVALID_HANDLE_VALUE) ::CloseHandle(waker);
  if (accept_thread_.joinable()) accept_thread_.join();

  // Resolve any in-flight pending sign requests as denied so threads exit.
  {
    std::lock_guard<std::mutex> g(pending_mutex_);
    for (auto& kv : pending_) {
      std::lock_guard<std::mutex> g2(kv.second->m);
      kv.second->resolved = true;
      kv.second->approved = false;
      kv.second->cv.notify_all();
    }
    pending_.clear();
  }
  {
    std::lock_guard<std::mutex> g(cache_mutex_);
    approval_cache_.clear();
  }
  {
    std::lock_guard<std::mutex> g(keys_mutex_);
    keys_.clear();
  }
}

void SshAgentServer::SetKeys(const std::vector<SshAgentKey>& keys) {
  std::lock_guard<std::mutex> g(keys_mutex_);
  keys_ = keys;
}

void SshAgentServer::Respond(int request_id, bool approved) {
  std::shared_ptr<Pending> p;
  {
    std::lock_guard<std::mutex> g(pending_mutex_);
    auto it = pending_.find(request_id);
    if (it == pending_.end()) return;
    p = it->second;
    pending_.erase(it);
  }
  std::lock_guard<std::mutex> g(p->m);
  p->resolved = true;
  p->approved = approved;
  p->cv.notify_all();
}

void SshAgentServer::AcceptLoop() {
  // Build a security descriptor that grants access only to the current user.
  // "D:P(A;;GA;;;OW)" - DACL, protected, allow GENERIC_ALL to the owner of the
  // securable object (i.e. the creator).
  SECURITY_ATTRIBUTES sa{};
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (::ConvertStringSecurityDescriptorToSecurityDescriptorW(
          L"D:P(A;;GA;;;OW)", SDDL_REVISION_1, &sd, nullptr)) {
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = sd;
    sa.bInheritHandle = FALSE;
  }

  while (running_.load()) {
    HANDLE pipe = ::CreateNamedPipeW(
        pipe_name_.c_str(),
        PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
        PIPE_UNLIMITED_INSTANCES,
        kPipeBuffer, kPipeBuffer, 0,
        sd ? &sa : nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
      ::Sleep(50);
      continue;
    }

    BOOL connected = ::ConnectNamedPipe(pipe, nullptr)
        ? TRUE
        : (::GetLastError() == ERROR_PIPE_CONNECTED);
    if (!running_.load()) {
      ::DisconnectNamedPipe(pipe);
      ::CloseHandle(pipe);
      break;
    }
    if (!connected) {
      ::CloseHandle(pipe);
      continue;
    }
    std::thread([this, pipe]() { HandleClient(pipe); }).detach();
  }

  if (sd) ::LocalFree(sd);
}

void SshAgentServer::HandleClient(HANDLE pipe) {
  while (running_.load()) {
    uint8_t hdr[4];
    if (!ReadAll(pipe, hdr, 4)) break;
    uint32_t len = ReadU32(hdr);
    if (len == 0 || len > 256 * 1024) break;
    std::vector<uint8_t> body(len);
    if (!ReadAll(pipe, body.data(), len)) break;
    std::vector<uint8_t> reply = Dispatch(body, pipe);
    uint8_t rhdr[4];
    rhdr[0] = static_cast<uint8_t>((reply.size() >> 24) & 0xff);
    rhdr[1] = static_cast<uint8_t>((reply.size() >> 16) & 0xff);
    rhdr[2] = static_cast<uint8_t>((reply.size() >> 8)  & 0xff);
    rhdr[3] = static_cast<uint8_t>(reply.size() & 0xff);
    if (!WriteAll(pipe, rhdr, 4)) break;
    if (!reply.empty() && !WriteAll(pipe, reply.data(),
                                    static_cast<DWORD>(reply.size()))) {
      break;
    }
  }
  ::FlushFileBuffers(pipe);
  ::DisconnectNamedPipe(pipe);
  ::CloseHandle(pipe);
}

std::vector<uint8_t> SshAgentServer::Dispatch(
    const std::vector<uint8_t>& msg, HANDLE pipe) {
  if (msg.empty()) return {kFailure};
  switch (msg[0]) {
    case kReqIdentities: return BuildIdentities();
    case kReqSign:       return BuildSign(msg, pipe);
    default:             return {kFailure};
  }
}

std::vector<uint8_t> SshAgentServer::BuildIdentities() {
  std::vector<uint8_t> out;
  out.push_back(kResIdentities);
  std::lock_guard<std::mutex> g(keys_mutex_);
  WriteU32(out, static_cast<uint32_t>(keys_.size()));
  for (const auto& k : keys_) {
    WriteBytes(out, k.pub_blob);
    WriteString(out, k.name);
  }
  return out;
}

std::vector<uint8_t> SshAgentServer::BuildSign(
    const std::vector<uint8_t>& msg, HANDLE pipe) {
  if (msg.size() < 5) return {kFailure};
  SshReader r(msg.data() + 1, msg.size() - 1);
  std::vector<uint8_t> key_blob, payload;
  uint32_t flags = 0;
  if (!r.SshBytes(&key_blob) || !r.SshBytes(&payload) || !r.U32(&flags)) {
    return {kFailure};
  }

  SshAgentKey selected;
  bool found = false;
  {
    std::lock_guard<std::mutex> g(keys_mutex_);
    for (const auto& k : keys_) {
      if (k.pub_blob == key_blob) {
        selected = k;
        found = true;
        break;
      }
    }
  }
  if (!found) return {kFailure};

  if (!RequestApproval(selected, pipe)) return {kFailure};

  std::vector<uint8_t> sig;
  bool signed_ok = false;
  if (selected.key_type == "ssh-ed25519") {
    signed_ok = Ed25519Sign(selected, payload, &sig);
  } else if (selected.key_type == "ecdsa-sha2-nistp256") {
    signed_ok = EcdsaP256Sign(selected, payload, &sig);
  }
  if (!signed_ok) return {kFailure};

  std::vector<uint8_t> out;
  out.push_back(kResSign);
  WriteBytes(out, sig);
  return out;
}

bool SshAgentServer::RequestApproval(const SshAgentKey& key, HANDLE pipe) {
  std::string requester = ResolveClientProcessName(pipe);
  std::string image     = GetClientImagePath(pipe);
  ULONG pid             = GetClientPid(pipe);
  std::string cache_key = key.name + std::string(1, '\0') + requester;

  // Cache check.
  {
    std::lock_guard<std::mutex> g(cache_mutex_);
    auto it = approval_cache_.find(cache_key);
    if (it != approval_cache_.end()) {
      DWORD now = ::GetTickCount();
      if (now < it->second.expires_at) return true;
      approval_cache_.erase(it);
    }
  }

  int rid;
  std::shared_ptr<Pending> pending = std::make_shared<Pending>();
  {
    std::lock_guard<std::mutex> g(pending_mutex_);
    rid = ++next_request_id_;
    pending_[rid] = pending;
  }

  if (channel_) {
    flutter::EncodableMap args;
    args[flutter::EncodableValue("requestId")] = flutter::EncodableValue(rid);
    args[flutter::EncodableValue("keyName")]   =
        flutter::EncodableValue(key.name);
    args[flutter::EncodableValue("requesterName")] =
        flutter::EncodableValue(requester);
    if (pid != 0) {
      args[flutter::EncodableValue("requesterPid")] =
          flutter::EncodableValue(static_cast<int64_t>(pid));
    }
    if (!image.empty()) {
      args[flutter::EncodableValue("requesterExecutablePath")] =
          flutter::EncodableValue(image);
    }
    auto args_value = std::make_shared<flutter::EncodableValue>(std::move(args));
    PostToUiThread([this, args_value]() {
      if (!channel_) return;
      channel_->InvokeMethod(
          "onSignRequest",
          std::make_unique<flutter::EncodableValue>(*args_value));
    });
  }

  bool approved = false;
  {
    std::unique_lock<std::mutex> lock(pending->m);
    bool resolved = pending->cv.wait_for(
        lock, std::chrono::milliseconds(kApprovalTimeoutMs),
        [&] { return pending->resolved; });
    approved = resolved && pending->approved;
  }
  {
    std::lock_guard<std::mutex> g(pending_mutex_);
    pending_.erase(rid);
  }

  if (approved) {
    std::lock_guard<std::mutex> g(cache_mutex_);
    approval_cache_[cache_key] = CacheEntry{
        ::GetTickCount() + kApprovalCacheTtlMs};
  }
  return approved;
}

}  // namespace lumenpass
