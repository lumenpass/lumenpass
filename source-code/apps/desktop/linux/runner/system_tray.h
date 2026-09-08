#ifndef RUNNER_SYSTEM_TRAY_H_
#define RUNNER_SYSTEM_TRAY_H_

#include <gtk/gtk.h>
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

  explicit SystemTray();
  ~SystemTray();

  void SetMenuCallback(MenuCallback callback);

  bool Create();
  void Destroy();

  void SetVaultLocked(bool locked);

 private:
  void UpdateMenu();
  void ShowContextMenu();

  static void OnMenuItemActivated(GtkMenuItem* item, gpointer user_data);

  bool created_ = false;
  bool vault_locked_ = false;
  MenuCallback callback_;

  GtkStatusIcon* status_icon_ = nullptr;
  GtkWidget* menu_ = nullptr;
};

#endif  // RUNNER_SYSTEM_TRAY_H_
