// SSH Agent server for the LumenPass Linux runner.
//
// Mirrors the Windows implementation in apps/desktop/windows/runner/
// ssh_agent_server.{h,cpp}, but speaks the Unix flavour of the OpenSSH agent
// protocol (RFC 4254 / draft-miller-ssh-agent-04) over an AF_UNIX stream
// socket. The wire protocol is identical to Windows; only the transport and
// the host crypto provider (OpenSSL, not BCrypt) change.

#include "ssh_agent_server.h"

#include "ssh_agent_ed25519.h"

#include <flutter_linux/flutter_linux.h>
#include <glib.h>

#include <openssl/bn.h>
#include <openssl/ec.h>
#include <openssl/ecdsa.h>
#include <openssl/evp.h>
#include <openssl/obj_mac.h>
#include <openssl/sha.h>

#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <utility>

namespace lumenpass {

namespace {

constexpr uint8_t kReqIdentities = 11;
constexpr uint8_t kResIdentities = 12;
constexpr uint8_t kReqSign       = 13;
constexpr uint8_t kResSign       = 14;
constexpr uint8_t kFailure       = 5;

constexpr int64_t kApprovalCacheTtlMs = 15 * 60 * 1000;  // 15 minutes
constexpr int64_t kApprovalTimeoutMs  = 60 * 1000;       // 60 seconds
constexpr size_t  kMaxMessageBytes    = 256 * 1024;

constexpr const char kChannelName[] = "lumenpass/ssh_agent";
constexpr const char kSocketLeaf[]  = "lumenpass-ssh-agent.sock";

int64_t MonotonicMs() {
  return static_cast<int64_t>(g_get_monotonic_time() / 1000);
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

// Base64 decode (ignore whitespace, padding, and any other non-alphabet chars).
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
  // OpenSSL 3 marks EC_KEY/ECDSA_do_sign as deprecated in favour of the
  // EVP_PKEY/OSSL_PARAM API, but the legacy interface is still implemented
  // and is the only option that works the same way on the OpenSSL 1.1.1
  // builds we still ship to (libssl1.1 fallback in debian/control). Silence
  // the warning here so -Werror keeps protecting the rest of the codebase.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
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
  if (key.priv.size() != 32) return false;

  // Build an EC_KEY for nistp256 with the parsed scalar and point.
  EC_KEY* ec = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
  if (ec == nullptr) return false;

  bool ok = false;
  BIGNUM* d = nullptr;
  EC_POINT* q = nullptr;
  ECDSA_SIG* signature = nullptr;
  uint8_t digest[SHA256_DIGEST_LENGTH];
  std::vector<uint8_t> rs;

  do {
    d = BN_bin2bn(key.priv.data(), 32, nullptr);
    if (d == nullptr) break;
    if (EC_KEY_set_private_key(ec, d) != 1) break;

    const EC_GROUP* group = EC_KEY_get0_group(ec);
    if (group == nullptr) break;
    q = EC_POINT_new(group);
    if (q == nullptr) break;
    if (EC_POINT_oct2point(group, q, point.data(), point.size(), nullptr) != 1) {
      break;
    }
    if (EC_KEY_set_public_key(ec, q) != 1) break;
    if (EC_KEY_check_key(ec) != 1) break;

    // Hash the SSH sign payload with SHA-256.
    SHA256(payload.data(), payload.size(), digest);

    signature = ECDSA_do_sign(digest, sizeof(digest), ec);
    if (signature == nullptr) break;

    const BIGNUM* r = nullptr;
    const BIGNUM* s = nullptr;
    ECDSA_SIG_get0(signature, &r, &s);
    if (r == nullptr || s == nullptr) break;

    auto bn_to_bytes = [](const BIGNUM* bn) {
      std::vector<uint8_t> v(BN_num_bytes(bn));
      if (!v.empty()) BN_bn2bin(bn, v.data());
      return v;
    };
    auto rb = bn_to_bytes(r);
    auto sb = bn_to_bytes(s);
    WriteMpInt(rs, rb.data(), rb.size());
    WriteMpInt(rs, sb.data(), sb.size());

    ok = true;
  } while (false);

  if (signature) ECDSA_SIG_free(signature);
  if (q) EC_POINT_free(q);
  if (d) BN_clear_free(d);
  EC_KEY_free(ec);

  if (!ok) return false;

  // SSH ECDSA signature: string("ecdsa-sha2-nistp256") || string(rs)
  // where rs = mpint(r) || mpint(s).
  std::vector<uint8_t> inner;
  WriteString(inner, std::string("ecdsa-sha2-nistp256"));
  WriteBytes(inner, rs);
  *sig_blob = std::move(inner);
  return true;
#pragma GCC diagnostic pop
}

// Resolve the SO_PEERCRED PID/uid for an AF_UNIX peer. Falls back to {0, 0}.
struct PeerCred {
  pid_t pid = 0;
  uid_t uid = 0;
};

PeerCred GetPeerCred(int fd) {
  PeerCred pc;
  struct ucred uc{};
  socklen_t len = sizeof(uc);
  if (::getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &uc, &len) == 0) {
    pc.pid = uc.pid;
    pc.uid = uc.uid;
  }
  return pc;
}

std::string ResolveProcessImagePath(pid_t pid) {
  if (pid <= 0) return {};
  char link[64];
  std::snprintf(link, sizeof(link), "/proc/%d/exe", pid);
  char buf[PATH_MAX];
  ssize_t n = ::readlink(link, buf, sizeof(buf) - 1);
  if (n <= 0) return {};
  buf[n] = '\0';
  return std::string(buf);
}

std::string ResolveProcessLeafName(pid_t pid) {
  if (pid <= 0) return std::string("Requesting Process");
  std::string image = ResolveProcessImagePath(pid);
  if (!image.empty()) {
    size_t slash = image.find_last_of('/');
    return slash == std::string::npos ? image : image.substr(slash + 1);
  }
  // Fall back to /proc/<pid>/comm which is always readable for our own user.
  char path[64];
  std::snprintf(path, sizeof(path), "/proc/%d/comm", pid);
  FILE* fp = ::fopen(path, "re");
  if (fp == nullptr) return std::string("Process ") + std::to_string(pid);
  char buf[256];
  size_t got = ::fread(buf, 1, sizeof(buf) - 1, fp);
  ::fclose(fp);
  if (got == 0) return std::string("Process ") + std::to_string(pid);
  buf[got] = '\0';
  std::string out(buf);
  while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) {
    out.pop_back();
  }
  if (out.empty()) return std::string("Process ") + std::to_string(pid);
  return out;
}

bool ReadAll(int fd, void* buf, size_t len) {
  size_t got = 0;
  while (got < len) {
    ssize_t n = ::read(fd, static_cast<uint8_t*>(buf) + got, len - got);
    if (n == 0) return false;
    if (n < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    got += static_cast<size_t>(n);
  }
  return true;
}

bool WriteAll(int fd, const void* buf, size_t len) {
  size_t sent = 0;
  while (sent < len) {
    ssize_t n = ::write(fd, static_cast<const uint8_t*>(buf) + sent,
                        len - sent);
    if (n < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    sent += static_cast<size_t>(n);
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

void SshAgentServer::Shutdown() {
  Stop();
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }
}

void SshAgentServer::Register(FlView* view) {
  if (view == nullptr) return;
  if (channel_ != nullptr) return;
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger, kChannelName,
                                   FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, &OnMethodCall, this,
                                            nullptr);
}

// Marshal a worker-thread closure back onto the GMainContext owned by the
// Flutter engine. fl_method_channel_invoke_method must be called from there.
struct MainCtxCall {
  std::function<void()> fn;
};

gboolean SshAgentServer::MainContextDispatch(gpointer user_data) {
  auto* call = static_cast<MainCtxCall*>(user_data);
  if (call != nullptr) {
    if (call->fn) call->fn();
    delete call;
  }
  return G_SOURCE_REMOVE;
}

void SshAgentServer::PostToUiThread(std::function<void()> fn) {
  auto* call = new MainCtxCall{std::move(fn)};
  g_idle_add(&SshAgentServer::MainContextDispatch, call);
}

void SshAgentServer::OnMethodCall(FlMethodChannel* /*channel*/,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  auto* self = static_cast<SshAgentServer*>(user_data);
  FlMethodResponse* response = nullptr;
  self->HandleMethodCall(method_call, &response);
  if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond on lumenpass/ssh_agent: %s",
              error != nullptr ? error->message : "unknown");
  }
  g_object_unref(response);
}

namespace {

std::vector<SshAgentKey> ParseKeysArg(FlValue* args) {
  std::vector<SshAgentKey> out;
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return out;
  }
  FlValue* keys_val = fl_value_lookup_string(args, "keys");
  if (keys_val == nullptr ||
      fl_value_get_type(keys_val) != FL_VALUE_TYPE_LIST) {
    return out;
  }
  size_t n = fl_value_get_length(keys_val);
  for (size_t i = 0; i < n; ++i) {
    FlValue* entry = fl_value_get_list_value(keys_val, i);
    if (entry == nullptr || fl_value_get_type(entry) != FL_VALUE_TYPE_MAP) {
      continue;
    }
    FlValue* name_v = fl_value_lookup_string(entry, "name");
    FlValue* pem_v = fl_value_lookup_string(entry, "privateKey");
    if (name_v == nullptr || pem_v == nullptr) continue;
    if (fl_value_get_type(name_v) != FL_VALUE_TYPE_STRING ||
        fl_value_get_type(pem_v) != FL_VALUE_TYPE_STRING) {
      continue;
    }
    SshAgentKey k;
    k.name = fl_value_get_string(name_v);
    if (!ParseOpenSshPrivateKey(fl_value_get_string(pem_v), &k)) continue;
    out.push_back(std::move(k));
  }
  return out;
}

}  // namespace

void SshAgentServer::HandleMethodCall(FlMethodCall* method_call,
                                      FlMethodResponse** response) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "startAgent") == 0) {
    auto keys = ParseKeysArg(args);
    std::string path = Start(keys);
    if (path.empty()) {
      *response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "AGENT_START_FAILED", "Could not bind SSH agent socket", nullptr));
      return;
    }
    g_autoptr(FlValue) ret = fl_value_new_string(path.c_str());
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(ret));
    return;
  }
  if (g_strcmp0(method, "stopAgent") == 0) {
    Stop();
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    return;
  }
  if (g_strcmp0(method, "setKeys") == 0) {
    auto keys = ParseKeysArg(args);
    SetKeys(keys);
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    return;
  }
  if (g_strcmp0(method, "signResponse") == 0) {
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      *response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "Expected map", nullptr));
      return;
    }
    FlValue* rid_v = fl_value_lookup_string(args, "requestId");
    FlValue* ok_v = fl_value_lookup_string(args, "approved");
    if (rid_v == nullptr || ok_v == nullptr ||
        fl_value_get_type(ok_v) != FL_VALUE_TYPE_BOOL) {
      *response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "Missing requestId or approved", nullptr));
      return;
    }
    int rid = 0;
    auto rid_type = fl_value_get_type(rid_v);
    if (rid_type == FL_VALUE_TYPE_INT) {
      rid = static_cast<int>(fl_value_get_int(rid_v));
    } else {
      *response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "requestId must be int", nullptr));
      return;
    }
    Respond(rid, fl_value_get_bool(ok_v));
    *response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    return;
  }
  *response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

// ── Lifecycle ────────────────────────────────────────────────────────────────

namespace {

// Pick a runtime directory for the AF_UNIX socket. Prefers $XDG_RUNTIME_DIR
// (typically /run/user/<uid>, mode 0700) which is the standard place for
// per-user sockets. Falls back to /tmp if unset.
std::string ResolveRuntimeDir() {
  const char* xdg = ::getenv("XDG_RUNTIME_DIR");
  if (xdg != nullptr && xdg[0] == '/') {
    struct stat st{};
    if (::stat(xdg, &st) == 0 && S_ISDIR(st.st_mode)) {
      return std::string(xdg);
    }
  }
  // Fallback. /tmp is world-writable but the socket itself will be
  // chmod 0600 owned by the current user.
  std::string fallback = "/tmp";
  std::string user_dir = fallback + "/lumenpass-" + std::to_string(::getuid());
  ::mkdir(user_dir.c_str(), 0700);
  return user_dir;
}

}  // namespace

std::string SshAgentServer::Start(const std::vector<SshAgentKey>& keys) {
  if (running_.load()) {
    SetKeys(keys);
    return socket_path_;
  }

  std::string runtime_dir = ResolveRuntimeDir();
  std::string path = runtime_dir + "/" + kSocketLeaf;

  // Remove any stale socket from a prior crash.
  ::unlink(path.c_str());

  int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) {
    g_warning("[SshAgent] socket() failed: %s", std::strerror(errno));
    return {};
  }

  struct sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (path.size() + 1 > sizeof(addr.sun_path)) {
    g_warning("[SshAgent] socket path too long: %s", path.c_str());
    ::close(fd);
    return {};
  }
  std::strncpy(addr.sun_path, path.c_str(), sizeof(addr.sun_path) - 1);

  // umask trick: the socket inherits 0600 so other users on the system
  // can't connect even if they can reach the directory.
  mode_t old_mask = ::umask(0177);
  int bind_rc = ::bind(fd, reinterpret_cast<struct sockaddr*>(&addr),
                       sizeof(addr));
  ::umask(old_mask);
  if (bind_rc != 0) {
    g_warning("[SshAgent] bind(%s) failed: %s", path.c_str(),
              std::strerror(errno));
    ::close(fd);
    return {};
  }
  // Tighten permissions explicitly in case the umask was overridden.
  ::chmod(path.c_str(), S_IRUSR | S_IWUSR);

  if (::listen(fd, 16) != 0) {
    g_warning("[SshAgent] listen() failed: %s", std::strerror(errno));
    ::close(fd);
    ::unlink(path.c_str());
    return {};
  }

  // Wakeup pipe used by Stop() to break out of accept().
  if (::pipe(wake_pipe_) != 0) {
    g_warning("[SshAgent] pipe() failed: %s", std::strerror(errno));
    ::close(fd);
    ::unlink(path.c_str());
    return {};
  }
  ::fcntl(wake_pipe_[0], F_SETFD, FD_CLOEXEC);
  ::fcntl(wake_pipe_[1], F_SETFD, FD_CLOEXEC);

  listen_fd_ = fd;
  socket_path_ = path;
  SetKeys(keys);
  running_.store(true);
  accept_thread_ = std::thread([this]() { AcceptLoop(); });
  return socket_path_;
}

void SshAgentServer::Stop() {
  if (!running_.exchange(false)) return;

  // Wake the accept loop.
  if (wake_pipe_[1] >= 0) {
    char b = 1;
    ssize_t ignored = ::write(wake_pipe_[1], &b, 1);
    (void)ignored;
  }
  if (accept_thread_.joinable()) accept_thread_.join();

  if (listen_fd_ >= 0) {
    ::close(listen_fd_);
    listen_fd_ = -1;
  }
  if (!socket_path_.empty()) {
    ::unlink(socket_path_.c_str());
    socket_path_.clear();
  }
  if (wake_pipe_[0] >= 0) { ::close(wake_pipe_[0]); wake_pipe_[0] = -1; }
  if (wake_pipe_[1] >= 0) { ::close(wake_pipe_[1]); wake_pipe_[1] = -1; }

  // Resolve any in-flight pending sign requests as denied so worker threads
  // exit cleanly.
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

// ── Accept loop & client dispatcher ─────────────────────────────────────────

void SshAgentServer::AcceptLoop() {
  // Ignore SIGPIPE so writing to a client that disconnects mid-reply just
  // returns -EPIPE instead of killing the process.
  ::signal(SIGPIPE, SIG_IGN);

  while (running_.load()) {
    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(listen_fd_, &rfds);
    if (wake_pipe_[0] >= 0) FD_SET(wake_pipe_[0], &rfds);
    int maxfd = std::max(listen_fd_, wake_pipe_[0]);

    int rc = ::select(maxfd + 1, &rfds, nullptr, nullptr, nullptr);
    if (rc < 0) {
      if (errno == EINTR) continue;
      break;
    }
    if (!running_.load()) break;
    if (wake_pipe_[0] >= 0 && FD_ISSET(wake_pipe_[0], &rfds)) {
      char drain[16];
      while (::read(wake_pipe_[0], drain, sizeof(drain)) > 0) {
        // drain
      }
      if (!running_.load()) break;
    }
    if (!FD_ISSET(listen_fd_, &rfds)) continue;

    int client = ::accept4(listen_fd_, nullptr, nullptr, SOCK_CLOEXEC);
    if (client < 0) {
      if (errno == EINTR || errno == EAGAIN) continue;
      g_warning("[SshAgent] accept() failed: %s", std::strerror(errno));
      continue;
    }

    // Reject connections from other UIDs. SO_PEERCRED on Linux gives us a
    // reliable identity for AF_UNIX peers.
    PeerCred pc = GetPeerCred(client);
    if (pc.uid != ::getuid()) {
      g_warning("[SshAgent] rejecting connection from uid %u (expected %u)",
                static_cast<unsigned>(pc.uid),
                static_cast<unsigned>(::getuid()));
      ::close(client);
      continue;
    }

    std::thread([this, client]() { HandleClient(client); }).detach();
  }
}

void SshAgentServer::HandleClient(int client_fd) {
  while (running_.load()) {
    uint8_t hdr[4];
    if (!ReadAll(client_fd, hdr, 4)) break;
    uint32_t len = ReadU32(hdr);
    if (len == 0 || len > kMaxMessageBytes) break;
    std::vector<uint8_t> body(len);
    if (!ReadAll(client_fd, body.data(), len)) break;

    std::vector<uint8_t> reply = Dispatch(body, client_fd);
    uint8_t rhdr[4];
    rhdr[0] = static_cast<uint8_t>((reply.size() >> 24) & 0xff);
    rhdr[1] = static_cast<uint8_t>((reply.size() >> 16) & 0xff);
    rhdr[2] = static_cast<uint8_t>((reply.size() >> 8)  & 0xff);
    rhdr[3] = static_cast<uint8_t>(reply.size() & 0xff);
    if (!WriteAll(client_fd, rhdr, 4)) break;
    if (!reply.empty() && !WriteAll(client_fd, reply.data(), reply.size())) {
      break;
    }
  }
  ::shutdown(client_fd, SHUT_RDWR);
  ::close(client_fd);
}

std::vector<uint8_t> SshAgentServer::Dispatch(const std::vector<uint8_t>& msg,
                                              int client_fd) {
  if (msg.empty()) return {kFailure};
  switch (msg[0]) {
    case kReqIdentities: return BuildIdentities();
    case kReqSign:       return BuildSign(msg, client_fd);
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

std::vector<uint8_t> SshAgentServer::BuildSign(const std::vector<uint8_t>& msg,
                                               int client_fd) {
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

  if (!RequestApproval(selected, client_fd)) return {kFailure};

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

bool SshAgentServer::RequestApproval(const SshAgentKey& key, int client_fd) {
  PeerCred pc = GetPeerCred(client_fd);
  std::string requester = ResolveProcessLeafName(pc.pid);
  std::string image = ResolveProcessImagePath(pc.pid);
  std::string cache_key = key.name + std::string(1, '\0') + requester;

  // Cache check.
  {
    std::lock_guard<std::mutex> g(cache_mutex_);
    auto it = approval_cache_.find(cache_key);
    if (it != approval_cache_.end()) {
      int64_t now = MonotonicMs();
      if (now < it->second.expires_at_ms) return true;
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

  // Build the args map and post the InvokeMethod call onto the GMainContext.
  // The FlMethodChannel must only be touched from the UI thread.
  if (channel_ != nullptr) {
    std::string key_name = key.name;
    int64_t pid_val = static_cast<int64_t>(pc.pid);
    PostToUiThread([this, rid, key_name, requester, image, pid_val]() {
      if (channel_ == nullptr) return;
      g_autoptr(FlValue) args = fl_value_new_map();
      fl_value_set_string_take(args, "requestId", fl_value_new_int(rid));
      fl_value_set_string_take(args, "keyName",
                               fl_value_new_string(key_name.c_str()));
      fl_value_set_string_take(args, "requesterName",
                               fl_value_new_string(requester.c_str()));
      if (pid_val > 0) {
        fl_value_set_string_take(args, "requesterPid",
                                 fl_value_new_int(pid_val));
      }
      if (!image.empty()) {
        fl_value_set_string_take(args, "requesterExecutablePath",
                                 fl_value_new_string(image.c_str()));
      }
      fl_method_channel_invoke_method(channel_, "onSignRequest", args, nullptr,
                                      nullptr, nullptr);
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
        MonotonicMs() + kApprovalCacheTtlMs};
  }
  return approved;
}

}  // namespace lumenpass
