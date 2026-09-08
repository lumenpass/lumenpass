#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "quick_search_panel.h"
#include "ssh_agent_server.h"
#include "window_channel_handler.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  window_channel_handler_ = std::make_unique<WindowChannelHandler>(GetHandle());
  window_channel_handler_->Register(
      flutter_controller_->engine()->messenger());

  // Boot the isolated Quick Search engine + borderless popup up front so the
  // first hotkey press shows the panel with no cold-start delay. It brokers
  // vault-backed intents through the main engine's lumenpass/window channel.
  quick_search_panel_ = std::make_unique<QuickSearchPanel>(
      GetHandle(), project_, window_channel_handler_->channel());
  window_channel_handler_->SetQuickSearchPanel(quick_search_panel_.get());

  lumenpass::SshAgentServer::Instance().Register(
      flutter_controller_->engine()->messenger());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  lumenpass::SshAgentServer::Instance().Stop();
  if (window_channel_handler_) {
    window_channel_handler_->SetQuickSearchPanel(nullptr);
  }
  quick_search_panel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  window_channel_handler_ = nullptr;

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (window_channel_handler_ &&
      window_channel_handler_->HandleTrayMessage(message, wparam, lparam)) {
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_HOTKEY:
      if (window_channel_handler_ &&
          window_channel_handler_->HandleHotKeyMessage(wparam)) {
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
