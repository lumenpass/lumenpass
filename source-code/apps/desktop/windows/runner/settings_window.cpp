#include "settings_window.h"

#include <flutter/generated_plugin_registrant.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <optional>

namespace {

constexpr const char kSettingsHostChannel[] = "lumenpass/settings_host";
constexpr const wchar_t kWindowTitle[] = L"LumenPass Settings";

// Converts a logical client size into a physical *window* size (including the
// native frame) for |hwnd| at |dpi|.
SIZE WindowSizeForClient(HWND hwnd, int logical_width, int logical_height,
                         UINT dpi) {
  const double scale = static_cast<double>(dpi) / 96.0;
  RECT rect{0, 0, static_cast<LONG>(std::lround(logical_width * scale)),
            static_cast<LONG>(std::lround(logical_height * scale))};
  const DWORD style = static_cast<DWORD>(::GetWindowLongPtr(hwnd, GWL_STYLE));
  const DWORD ex_style =
      static_cast<DWORD>(::GetWindowLongPtr(hwnd, GWL_EXSTYLE));
  ::AdjustWindowRectExForDpi(&rect, style, FALSE, ex_style, dpi);
  return SIZE{rect.right - rect.left, rect.bottom - rect.top};
}

UINT DpiOrDefault(HWND hwnd) {
  const UINT dpi = hwnd ? ::GetDpiForWindow(hwnd) : 0;
  return dpi == 0 ? 96 : dpi;
}

}  // namespace

SettingsWindow::SettingsWindow(HWND owner, const flutter::DartProject& project,
                               flutter::BinaryMessenger* main_messenger)
    : owner_(owner), project_(project) {
  // Run the dedicated Dart entrypoint (see `settingsMain` in main.dart). The
  // Windows embedder supports custom entrypoints, so — unlike Linux — no
  // argument sentinel is required.
  project_.set_dart_entrypoint("settingsMain");
  host_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          main_messenger, kSettingsHostChannel,
          &flutter::StandardMethodCodec::GetInstance());
}

SettingsWindow::~SettingsWindow() {
  // Destroy here rather than relying on ~Win32Window so our OnDestroy override
  // (engine teardown) still runs while this object is fully alive.
  Destroy();
  host_channel_ = nullptr;
}

bool SettingsWindow::Open(const std::string& section) {
  if (GetHandle() != nullptr) {
    if (!section.empty()) {
      pending_section_ = section;
    }
    if (engine_ready_) {
      PushSection();
      RequestSnapshotAndPush();
    }
    Reveal();
    return true;
  }

  // Win32Window::Create() starts with Destroy() (and so OnDestroy(), which
  // resets per-window state), so record the deep link only once it returns.
  // The engine cannot report `ready` before the message loop runs again.
  if (!Create(kWindowTitle, Point(10, 10),
              Size(kDefaultWidth, kDefaultHeight))) {
    Destroy();
    return false;
  }
  pending_section_ = section;
  CenterOnOwnerMonitor();
  // The window is revealed by the engine's first-frame callback (see
  // OnCreate) so it never flashes an unpainted client area.
  return true;
}

bool SettingsWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    flutter_controller_ = nullptr;
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  settings_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kSettingsHostChannel,
          &flutter::StandardMethodCodec::GetInstance());
  settings_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleSettingsCall(call, std::move(result)); });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() { Reveal(); });
  // Ensure a frame is pending so the callback above fires even if the engine
  // already produced its first frame.
  flutter_controller_->ForceRedraw();
  return true;
}

void SettingsWindow::OnDestroy() {
  engine_ready_ = false;
  pending_section_.clear();
  if (settings_channel_) {
    settings_channel_->SetMethodCallHandler(nullptr);
    settings_channel_ = nullptr;
  }
  flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

LRESULT SettingsWindow::MessageHandler(HWND hwnd, UINT const message,
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

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    case WM_GETMINMAXINFO: {
      // Same minimum as the macOS window; the Dart layout tests cover it.
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const SIZE min =
          WindowSizeForClient(hwnd, kMinWidth, kMinHeight, DpiOrDefault(hwnd));
      info->ptMinTrackSize.x = min.cx;
      info->ptMinTrackSize.y = min.cy;
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void SettingsWindow::HandleSettingsCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "ready") {
    engine_ready_ = true;
    PushSection();
    result->Success();
  } else if (method == "requestSettings" || method == "applySetting") {
    RelayToMainEngine(call, std::move(result));
  } else {
    result->NotImplemented();
  }
}

void SettingsWindow::RelayToMainEngine(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!host_channel_) {
    result->Success();
    return;
  }

  // std::function requires copyable captures, so share the pending result.
  std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> pending(
      std::move(result));
  auto handler = std::make_unique<
      flutter::MethodResultFunctions<flutter::EncodableValue>>(
      [pending](const flutter::EncodableValue* reply) {
        if (reply && std::get_if<std::string>(reply)) {
          pending->Success(*reply);
        } else {
          pending->Success();
        }
      },
      // Mirrors macOS: host errors surface as a null snapshot and the Dart
      // side keeps its optimistic state until the next poll reconciles it.
      [pending](const std::string&, const std::string&,
                const flutter::EncodableValue*) { pending->Success(); },
      [pending]() { pending->Success(); });

  std::unique_ptr<flutter::EncodableValue> args;
  if (call.arguments() && !call.arguments()->IsNull()) {
    args = std::make_unique<flutter::EncodableValue>(*call.arguments());
  }
  host_channel_->InvokeMethod(call.method_name(), std::move(args),
                              std::move(handler));
}

void SettingsWindow::PushSection() {
  if (pending_section_.empty() || !settings_channel_) {
    return;
  }
  auto section = std::make_unique<flutter::EncodableValue>(pending_section_);
  pending_section_.clear();
  settings_channel_->InvokeMethod("setSection", std::move(section));
}

void SettingsWindow::RequestSnapshotAndPush() {
  if (!host_channel_) {
    return;
  }
  auto handler = std::make_unique<
      flutter::MethodResultFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* reply) {
        if (reply && std::get_if<std::string>(reply)) {
          PushSnapshot(*reply);
        }
      },
      nullptr, nullptr);
  host_channel_->InvokeMethod("requestSettings", nullptr, std::move(handler));
}

void SettingsWindow::PushSnapshot(const flutter::EncodableValue& snapshot) {
  if (!settings_channel_) {
    return;
  }
  settings_channel_->InvokeMethod(
      "setSnapshot", std::make_unique<flutter::EncodableValue>(snapshot));
}

void SettingsWindow::CenterOnOwnerMonitor() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  // Open on the monitor showing the main window; if it is hidden (tray-only),
  // fall back to the monitor under the cursor.
  HMONITOR monitor = nullptr;
  if (owner_ && ::IsWindowVisible(owner_) && !::IsIconic(owner_)) {
    monitor = ::MonitorFromWindow(owner_, MONITOR_DEFAULTTONEAREST);
  } else {
    POINT cursor{};
    ::GetCursorPos(&cursor);
    monitor = ::MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  }
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!::GetMonitorInfo(monitor, &info)) {
    return;
  }
  const RECT& work = info.rcWork;

  // Hop onto the target monitor first so any WM_DPICHANGED rescale happens
  // before the final size is computed against that monitor's DPI.
  ::SetWindowPos(hwnd, nullptr, work.left, work.top, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);

  const SIZE size = WindowSizeForClient(hwnd, kDefaultWidth, kDefaultHeight,
                                        DpiOrDefault(hwnd));
  const LONG work_w = work.right - work.left;
  const LONG work_h = work.bottom - work.top;
  const LONG w = size.cx < work_w ? size.cx : work_w;
  const LONG h = size.cy < work_h ? size.cy : work_h;
  const LONG x = work.left + (work_w - w) / 2;
  const LONG y = work.top + (work_h - h) / 2;
  ::SetWindowPos(hwnd, nullptr, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
}

void SettingsWindow::Reveal() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  ::ShowWindow(hwnd, ::IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(hwnd);
  ::BringWindowToTop(hwnd);
}
