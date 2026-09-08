#ifndef RUNNER_SYSTEM_TRAY_H_
#define RUNNER_SYSTEM_TRAY_H_

#include <windows.h>
#include <shellapi.h>

#include <functional>
#include <string>

class SystemTray {
 public:
  enum class MenuAction {
    kShow,
    kQuickSearch,
    kGeneratePassword,
    kSwitchVaults,
    kLock,
    kSettings,
    kAbout,
    kQuit,
  };

  using MenuCallback = std::function<void(MenuAction)>;

  explicit SystemTray(HWND owner);
  ~SystemTray();

  void SetMenuCallback(MenuCallback callback);

  bool Create();
  void Destroy();

  void SetVaultLocked(bool locked);

  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  static constexpr UINT kTrayCallbackMessage = WM_APP + 1;
  static constexpr UINT kTrayIconUid = 1;

 private:
  void ShowContextMenu();
  void UpdateTooltip();

  HWND owner_ = nullptr;
  bool created_ = false;
  bool vault_locked_ = false;
  NOTIFYICONDATAW nid_{};
  MenuCallback callback_;
};

#endif  // RUNNER_SYSTEM_TRAY_H_
