#ifndef RUNNER_SSH_AGENT_SERVER_H_
#define RUNNER_SSH_AGENT_SERVER_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace lumenpass {

struct SshAgentKey {
  std::string name;
  std::string key_type;          // "ssh-ed25519" or "ecdsa-sha2-nistp256"
  std::vector<uint8_t> pub_blob; // SSH wire-format public key blob
  std::vector<uint8_t> priv;     // raw private scalar / seed
};

class SshAgentServer {
 public:
  static SshAgentServer& Instance();

  void Register(flutter::BinaryMessenger* messenger);

  // Returns the friendly socket-path string surfaced to Dart, or empty on
  // failure. On Windows that's the named pipe path.
  std::string Start(const std::vector<SshAgentKey>& keys);
  void Stop();

  void SetKeys(const std::vector<SshAgentKey>& keys);

  // Resolve a pending sign request raised via onSignRequest.
  void Respond(int request_id, bool approved);

 private:
  SshAgentServer();
  ~SshAgentServer();
  SshAgentServer(const SshAgentServer&) = delete;
  SshAgentServer& operator=(const SshAgentServer&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void AcceptLoop();
  void HandleClient(HANDLE pipe);
  std::vector<uint8_t> Dispatch(const std::vector<uint8_t>& msg, HANDLE pipe);
  std::vector<uint8_t> BuildIdentities();
  std::vector<uint8_t> BuildSign(const std::vector<uint8_t>& msg, HANDLE pipe);

  bool RequestApproval(const SshAgentKey& key, HANDLE pipe);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  std::mutex keys_mutex_;
  std::vector<SshAgentKey> keys_;

  std::atomic<bool> running_{false};
  std::thread accept_thread_;

  // Pending approval requests, keyed by request id.
  struct Pending {
    std::mutex m;
    std::condition_variable cv;
    bool resolved = false;
    bool approved = false;
  };
  std::mutex pending_mutex_;
  std::map<int, std::shared_ptr<Pending>> pending_;
  int next_request_id_ = 0;

  // Approval cache: key -> expiry tick.
  struct CacheEntry {
    DWORD expires_at;
  };
  std::mutex cache_mutex_;
  std::map<std::string, CacheEntry> approval_cache_;

  std::wstring pipe_name_;

  // Message-only window used to marshal calls from worker threads onto the
  // Flutter platform thread (the only thread allowed to call InvokeMethod).
  HWND marshaller_ = nullptr;
  DWORD ui_thread_id_ = 0;
  void EnsureMarshaller();
  void PostToUiThread(std::function<void()> fn);
  static LRESULT CALLBACK MarshallerWndProc(HWND, UINT, WPARAM, LPARAM);
};

}  // namespace lumenpass

#endif  // RUNNER_SSH_AGENT_SERVER_H_
