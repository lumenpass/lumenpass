#ifndef RUNNER_SSH_AGENT_SERVER_H_
#define RUNNER_SSH_AGENT_SERVER_H_

#include <flutter_linux/flutter_linux.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace lumenpass {

struct SshAgentKey {
  std::string name;
  std::string key_type;          // "ssh-ed25519" or "ecdsa-sha2-nistp256"
  std::vector<uint8_t> pub_blob; // SSH wire-format public key blob
  std::vector<uint8_t> priv;     // raw private scalar / seed (32 bytes)
};

class SshAgentServer {
 public:
  static SshAgentServer& Instance();

  // Bind the lumenpass/ssh_agent method channel onto the Flutter engine
  // attached to `view`. Safe to call once after the engine is up.
  void Register(FlView* view);

  // Releases the FlMethodChannel and stops the agent. Call from the
  // GApplication shutdown path so we don't leak the listening socket.
  void Shutdown();

  // Returns the friendly socket-path string surfaced to Dart, or empty on
  // failure. On Linux that's an absolute filesystem path to the AF_UNIX
  // socket, e.g. /run/user/1000/lumenpass-ssh-agent.sock.
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

  static void OnMethodCall(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data);
  void HandleMethodCall(FlMethodCall* method_call,
                        FlMethodResponse** response);

  void AcceptLoop();
  void HandleClient(int client_fd);
  std::vector<uint8_t> Dispatch(const std::vector<uint8_t>& msg, int client_fd);
  std::vector<uint8_t> BuildIdentities();
  std::vector<uint8_t> BuildSign(const std::vector<uint8_t>& msg, int client_fd);

  bool RequestApproval(const SshAgentKey& key, int client_fd);

  // Marshal `fn` from a worker thread back onto the GMainContext so we can
  // safely invoke FlMethodChannel calls (only touched on the main thread).
  void PostToUiThread(std::function<void()> fn);
  static gboolean MainContextDispatch(gpointer user_data);

  FlMethodChannel* channel_ = nullptr;

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

  // Approval cache: "<key_name>\0<requester>" -> monotonic expiry (ms).
  struct CacheEntry {
    int64_t expires_at_ms;
  };
  std::mutex cache_mutex_;
  std::map<std::string, CacheEntry> approval_cache_;

  // Listening socket + path on disk. Cleared on Stop().
  int listen_fd_ = -1;
  std::string socket_path_;

  // Wakeup pipe so the blocking accept() in AcceptLoop returns on Stop().
  int wake_pipe_[2] = {-1, -1};
};

}  // namespace lumenpass

#endif  // RUNNER_SSH_AGENT_SERVER_H_
