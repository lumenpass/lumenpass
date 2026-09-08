#ifndef RUNNER_QUICK_SEARCH_PANEL_H_
#define RUNNER_QUICK_SEARCH_PANEL_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

// Isolated Quick Search panel (Option A: a *second* Flutter engine hosted in a
// borderless popup window). This mirrors the macOS `QuickSearchPanel`
// (NSPanel + FlutterEngine running the `quickSearchMain` entrypoint) so the
// main application window is never transformed, hidden or resized when the
// hotkey is pressed.
//
// The panel engine has its own Dart isolate and therefore no access to the
// decrypted vault. It talks to the main engine exclusively over two method
// channels, brokered here in native code:
//
//   lumenpass/quick_search   (panel engine <-> this native panel)
//     native -> panel : setSnapshot (String jsonPayload)
//     panel  -> native: ready | close | openEntry | editEntry | createItem |
//                       heightChanged
//
//   lumenpass/window         (main engine <-> WindowChannelHandler)
//     native -> main : quickSearchRequestSnapshot | quickSearchOpenEntry |
//                      quickSearchEditEntry | quickSearchCreateItem |
//                      quickSearchPanelClosed
//
// The main channel pointer is owned by WindowChannelHandler and passed in; we
// never take ownership of it.
class QuickSearchPanel {
 public:
  // |owner| is the main application window (used for DPI/width heuristics and
  // as the popup's owner). |project| is the same DartProject used by the main
  // engine; we clone it and override the entrypoint to `quickSearchMain`.
  // |main_channel| is the main engine's lumenpass/window channel used to broker
  // vault-backed intents; not owned.
  QuickSearchPanel(
      HWND owner, const flutter::DartProject& project,
      flutter::MethodChannel<flutter::EncodableValue>* main_channel);
  ~QuickSearchPanel();

  QuickSearchPanel(const QuickSearchPanel&) = delete;
  QuickSearchPanel& operator=(const QuickSearchPanel&) = delete;

  // Shows the panel if hidden, hides it if visible.
  void Toggle();

  // Pulls a fresh snapshot from the main engine and reveals the panel on the
  // monitor currently containing the mouse cursor.
  void Show(bool open_generator);

  // Hides the panel and notifies the main engine (quickSearchPanelClosed).
  void Hide();

  bool IsVisible() const { return visible_; }

 private:
  // Lazily boots the second Flutter engine + popup window. Returns false if
  // setup failed. The first call happens up front (see WindowChannelHandler)
  // so the first hotkey press is instant.
  bool EnsureCreated();

  // Registers the popup window class exactly once per process.
  static void RegisterWindowClass();

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  LRESULT HandleMessage(HWND window, UINT message, WPARAM wparam,
                        LPARAM lparam) noexcept;

  // Method-call handler for the lumenpass/quick_search channel.
  void HandleQuickSearchCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Positions + sizes the popup on the cursor monitor and shows it.
  void Reveal();

  // Positions the popup (physical pixels) on the monitor under the cursor.
  void PositionOnCursorMonitor();

  // Applies a new content height (logical px) reported by Dart.
  void SetContentHeight(double logical_height);

  // Owner-window DPI scale factor (physical / logical).
  double OwnerScale() const;

  // Resolved logical panel width, based on the owner window width, clamped to a
  // sensible spotlight range (mirrors macOS frameWidthForPanel/resolved width).
  double ResolvedLogicalWidth() const;

  HWND owner_ = nullptr;
  HWND hwnd_ = nullptr;
  flutter::DartProject project_;
  flutter::MethodChannel<flutter::EncodableValue>* main_channel_ = nullptr;

  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> qs_channel_;

  bool visible_ = false;
  // Content height reported by Dart (logical px). Default mirrors macOS.
  double content_height_ = 178.0;

  static constexpr double kDefaultLogicalWidth = 640.0;
  static constexpr double kMinLogicalWidth = 560.0;
  static constexpr double kMaxLogicalWidth = 900.0;
  static constexpr double kMinLogicalHeight = 80.0;
};

#endif  // RUNNER_QUICK_SEARCH_PANEL_H_
