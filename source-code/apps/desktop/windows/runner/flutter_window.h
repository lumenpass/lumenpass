#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "window_channel_handler.h"

class QuickSearchPanel;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // When true, skips the initial Show() that fires after the first frame.
  // Used to honor the "Start minimized" preference on login launches; the
  // user can still surface the window via the tray icon.
  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Handler for the lumenpass/window MethodChannel.
  std::unique_ptr<WindowChannelHandler> window_channel_handler_;

  // Isolated Quick Search panel: a second Flutter engine hosted in a
  // borderless popup (Option A). Created after the main engine so the first
  // hotkey press is instant. Outlives window_channel_handler_ destruction
  // order-wise because it is declared after it (destroyed first).
  std::unique_ptr<QuickSearchPanel> quick_search_panel_;

  // When true the window is created but not shown after the first frame.
  bool start_hidden_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
