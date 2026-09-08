#ifndef RUNNER_WINDOW_CHANNEL_HANDLER_H_
#define RUNNER_WINDOW_CHANNEL_HANDLER_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <memory>
#include <string>

#include "system_tray.h"

class QuickSearchPanel;

class WindowChannelHandler {
 public:
  explicit WindowChannelHandler(FlView* view);
  ~WindowChannelHandler();

  void Register();

  static bool ReadStartMinimizedFlag();

  // The main engine's lumenpass/window channel, used by the isolated Quick
  // Search panel to broker vault-backed intents. Valid after Register().
  FlMethodChannel* channel() { return channel_; }

  // Associates the isolated Quick Search panel so tray actions and the
  // show/hideQuickSearchPanel method calls can drive it. Not owned.
  void SetQuickSearchPanel(QuickSearchPanel* panel) {
    quick_search_panel_ = panel;
  }

 private:
  static void OnMethodCall(FlMethodChannel* channel,
                          FlMethodCall* method_call,
                          gpointer user_data);

  void HandleMethodCall(FlMethodCall* method_call,
                       FlMethodResponse** response);

  void BringToFront();
  void Quit();
  void InitSystemTray();
  void OnTrayAction(SystemTray::MenuAction action);

  bool SetAutostart(bool enabled);
  bool GetAutostart();
  void SetStartMinimized(bool enabled);

  static std::string GetExecutablePath();
  static std::string GetConfigDir();
  static std::string GetAutostartDesktopPath();
  static std::string GetStartMinimizedPath();

  FlView* view_;
  FlMethodChannel* channel_;
  std::unique_ptr<SystemTray> system_tray_;

  // Isolated Quick Search panel (second Flutter engine). Not owned.
  QuickSearchPanel* quick_search_panel_ = nullptr;
};

#endif  // RUNNER_WINDOW_CHANNEL_HANDLER_H_
