#ifndef RUNNER_WINDOW_CHANNEL_HANDLER_H_
#define RUNNER_WINDOW_CHANNEL_HANDLER_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

#include "system_tray.h"

class QuickSearchPanel;

class WindowChannelHandler {
 public:
  explicit WindowChannelHandler(HWND window_handle);
  ~WindowChannelHandler();

  void Register(flutter::BinaryMessenger* messenger);

  bool HandleHotKeyMessage(WPARAM wparam);

  bool HandleTrayMessage(UINT message, WPARAM wparam, LPARAM lparam);

  // The main engine's lumenpass/window channel. Used by the isolated Quick
  // Search panel to broker vault-backed intents. Not owned by the caller.
  flutter::MethodChannel<flutter::EncodableValue>* channel() {
    return channel_.get();
  }

  // Associates the isolated Quick Search panel so the hotkey and the
  // show/hideQuickSearchPanel method calls can drive it. Not owned.
  void SetQuickSearchPanel(QuickSearchPanel* panel) {
    quick_search_panel_ = panel;
  }

 private:
  static constexpr int kQuickSearchHotKeyId = 1;
  static constexpr int kLockVaultHotKeyId = 2;

  HWND window_handle_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<SystemTray> system_tray_;

  // Isolated Quick Search panel (second Flutter engine). Not owned; owned by
  // FlutterWindow which outlives this handler.
  QuickSearchPanel* quick_search_panel_ = nullptr;

  int quick_search_vk_ = 0;
  UINT quick_search_modifiers_ = 0;
  bool quick_search_registered_ = false;

  int lock_vault_vk_ = 0;
  UINT lock_vault_modifiers_ = 0;
  bool lock_vault_registered_ = false;

  DWORD last_error_ = 0;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void BringToFront();
  void Quit();
  void SetSize(double width, double height);
  void ShowNativeTitleBar(const std::string& title);
  void HideNativeTitleBar();
  bool SetAutostart(bool enabled);
  bool GetAutostart();
  void SetStartMinimized(bool enabled);
  void HideWindow();
  void ShowQuickSearchWindow();
  void ShowQuickSearchPanel(bool open_generator);
  void HideQuickSearchPanel();
  void DecodeQRFromFile(
      const std::string& path,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void UpdateQuickSearchHotKey(int vk, UINT modifiers);
  void ClearQuickSearchHotKey();
  void UpdateLockVaultHotKey(int vk, UINT modifiers);
  void ClearLockVaultHotKey();
  void UnregisterAllHotKeys();

  void InitSystemTray();
  void OnTrayAction(SystemTray::MenuAction action);
};

#endif  // RUNNER_WINDOW_CHANNEL_HANDLER_H_
