#include "quick_search_panel.h"

#include <dwmapi.h>
#include <flutter/generated_plugin_registrant.h>

#include <algorithm>
#include <cmath>
#include <optional>

namespace {

constexpr const wchar_t kWindowClassName[] = L"LUMENPASS_QUICK_SEARCH_PANEL";
bool g_class_registered = false;

// Rounded-corner radius applied via DWM on Windows 11 (best-effort; ignored on
// older systems). Matches the 8px corner radius used by the macOS panel.
constexpr int kCornerRadius = 8;

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                                   static_cast<int>(utf8.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring result(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                        static_cast<int>(utf8.size()), result.data(), size);
  return result;
}

}  // namespace

QuickSearchPanel::QuickSearchPanel(
    HWND owner, const flutter::DartProject& project,
    flutter::MethodChannel<flutter::EncodableValue>* main_channel)
    : owner_(owner), project_(project), main_channel_(main_channel) {
  // Run the dedicated Dart entrypoint (see `quickSearchMain` in main.dart) in
  // this second engine. The Windows embedder supports custom entrypoints, so —
  // unlike Linux — no argument sentinel is required here.
  project_.set_dart_entrypoint("quickSearchMain");
}

QuickSearchPanel::~QuickSearchPanel() {
  if (qs_channel_) {
    qs_channel_->SetMethodCallHandler(nullptr);
  }
  flutter_controller_ = nullptr;
  if (hwnd_) {
    ::DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void QuickSearchPanel::RegisterWindowClass() {
  if (g_class_registered) {
    return;
  }
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(WNDCLASSEXW);
  // CS_DROPSHADOW gives the borderless popup a subtle shadow, echoing the
  // macOS panel's hasShadow = true.
  wc.style = CS_HREDRAW | CS_VREDRAW | CS_DROPSHADOW;
  wc.lpfnWndProc = QuickSearchPanel::WndProc;
  wc.hInstance = ::GetModuleHandle(nullptr);
  wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wc.lpszClassName = kWindowClassName;
  ::RegisterClassExW(&wc);
  g_class_registered = true;
}

bool QuickSearchPanel::EnsureCreated() {
  if (flutter_controller_) {
    return true;
  }
  RegisterWindowClass();

  const double scale = OwnerScale();
  const int w = static_cast<int>(std::lround(ResolvedLogicalWidth() * scale));
  const int h = static_cast<int>(std::lround(content_height_ * scale));

  // WS_POPUP: borderless. WS_EX_TOOLWINDOW keeps it out of the taskbar/alt-tab.
  // WS_EX_TOPMOST keeps it floating above the main window (mirrors NSPanel
  // .floating level). We deliberately do NOT use WS_EX_NOACTIVATE here: the
  // panel needs keyboard focus so the search field works immediately. Instead
  // we take focus without disturbing the main window's z-order (see Reveal()).
  hwnd_ = ::CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kWindowClassName, L"Quick Search",
      WS_POPUP, CW_USEDEFAULT, CW_USEDEFAULT, w, h,
      /*hWndParent=*/nullptr, nullptr, ::GetModuleHandle(nullptr), this);
  if (!hwnd_) {
    return false;
  }

  // Best-effort rounded corners on Windows 11.
  const DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
  ::DwmSetWindowAttribute(hwnd_, DWMWA_WINDOW_CORNER_PREFERENCE, &corner,
                          sizeof(corner));
  (void)kCornerRadius;

  RECT client{};
  ::GetClientRect(hwnd_, &client);
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      client.right - client.left, client.bottom - client.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    flutter_controller_ = nullptr;
    ::DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  qs_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "lumenpass/quick_search",
          &flutter::StandardMethodCodec::GetInstance());
  qs_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleQuickSearchCall(call, std::move(result)); });

  // Parent the Flutter child view into our popup.
  HWND child = flutter_controller_->view()->GetNativeWindow();
  ::SetParent(child, hwnd_);
  ::MoveWindow(child, 0, 0, client.right - client.left,
               client.bottom - client.top, TRUE);

  flutter_controller_->ForceRedraw();
  return true;
}

// static
LRESULT CALLBACK QuickSearchPanel::WndProc(HWND window, UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
    ::SetWindowLongPtr(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  } else if (QuickSearchPanel* self = reinterpret_cast<QuickSearchPanel*>(
                 ::GetWindowLongPtr(window, GWLP_USERDATA))) {
    return self->HandleMessage(window, message, wparam, lparam);
  }
  return ::DefWindowProc(window, message, wparam, lparam);
}

LRESULT QuickSearchPanel::HandleMessage(HWND window, UINT message,
                                        WPARAM wparam,
                                        LPARAM lparam) noexcept {
  // Let Flutter (and its plugins) process window messages first.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(window, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_SIZE: {
      if (flutter_controller_ && flutter_controller_->view()) {
        RECT client{};
        ::GetClientRect(window, &client);
        ::MoveWindow(flutter_controller_->view()->GetNativeWindow(), 0, 0,
                     client.right - client.left, client.bottom - client.top,
                     TRUE);
      }
      return 0;
    }
    case WM_ACTIVATE:
      // When the panel loses activation (user clicked elsewhere), dismiss it —
      // mirrors the macOS NSPanel onResignKey behaviour.
      if (LOWORD(wparam) == WA_INACTIVE && visible_) {
        Hide();
      }
      return 0;
    case WM_KILLFOCUS:
      // Belt-and-suspenders: some focus transitions arrive as KILLFOCUS without
      // a WM_ACTIVATE (e.g. focus moving to a child of another top-level).
      if (visible_) {
        // Only dismiss if focus left our window tree entirely.
        HWND next = ::GetFocus();
        if (next == nullptr || (next != window && ::GetParent(next) != window &&
                                !::IsChild(window, next))) {
          Hide();
        }
      }
      return 0;
  }
  return ::DefWindowProc(window, message, wparam, lparam);
}

void QuickSearchPanel::HandleQuickSearchCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "ready") {
    // Engine booted; snapshot is pulled fresh on each open. Nothing to do.
    result->Success();

  } else if (method == "close") {
    Hide();
    result->Success();

  } else if (method == "openEntry") {
    Hide();
    if (main_channel_) {
      const auto* uuid = std::get_if<std::string>(call.arguments());
      main_channel_->InvokeMethod(
          "quickSearchOpenEntry",
          std::make_unique<flutter::EncodableValue>(
              uuid ? flutter::EncodableValue(*uuid)
                   : flutter::EncodableValue()));
    }
    result->Success();

  } else if (method == "editEntry") {
    Hide();
    if (main_channel_) {
      const auto* uuid = std::get_if<std::string>(call.arguments());
      main_channel_->InvokeMethod(
          "quickSearchEditEntry",
          std::make_unique<flutter::EncodableValue>(
              uuid ? flutter::EncodableValue(*uuid)
                   : flutter::EncodableValue()));
    }
    result->Success();

  } else if (method == "createItem") {
    Hide();
    if (main_channel_) {
      main_channel_->InvokeMethod("quickSearchCreateItem", nullptr);
    }
    result->Success();

  } else if (method == "heightChanged") {
    double height = content_height_;
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("height"));
      if (it != args->end()) {
        if (const auto* d = std::get_if<double>(&it->second)) {
          height = *d;
        }
      }
    }
    SetContentHeight(height);
    result->Success();

  } else {
    result->NotImplemented();
  }
}

void QuickSearchPanel::Toggle() {
  if (visible_) {
    Hide();
  } else {
    Show(false);
  }
}

void QuickSearchPanel::Show(bool open_generator) {
  if (!EnsureCreated()) {
    // Panel engine failed to boot — fall back to surfacing the main window so
    // the hotkey still does something.
    if (owner_) {
      ::ShowWindow(owner_, SW_RESTORE);
      ::SetForegroundWindow(owner_);
    }
    return;
  }
  if (!main_channel_) {
    Reveal();
    return;
  }

  // Pull a fresh snapshot from the main engine, then reveal the panel. The
  // reply is delivered on the platform thread, so it is safe to touch the
  // window / channel from the success handler.
  flutter::EncodableMap args;
  args[flutter::EncodableValue("openGenerator")] =
      flutter::EncodableValue(open_generator);

  auto handler = std::make_unique<
      flutter::MethodResultFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* snapshot) {
        if (snapshot && qs_channel_) {
          if (const auto* json = std::get_if<std::string>(snapshot)) {
            qs_channel_->InvokeMethod(
                "setSnapshot",
                std::make_unique<flutter::EncodableValue>(*json));
          }
        }
        Reveal();
      },
      [this](const std::string&, const std::string&,
             const flutter::EncodableValue*) { Reveal(); },
      [this]() { Reveal(); });

  main_channel_->InvokeMethod(
      "quickSearchRequestSnapshot",
      std::make_unique<flutter::EncodableValue>(args), std::move(handler));
}

void QuickSearchPanel::Reveal() {
  if (!hwnd_) {
    return;
  }
  PositionOnCursorMonitor();
  // SWP_NOACTIVATE would prevent us from taking keyboard focus. Instead show
  // then set focus explicitly. Because the popup is WS_EX_TOPMOST and not owned
  // by the main window, the main window's own z-order/visibility is untouched.
  ::ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  ::SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  ::SetForegroundWindow(hwnd_);
  ::SetFocus(hwnd_);
  if (flutter_controller_ && flutter_controller_->view()) {
    ::SetFocus(flutter_controller_->view()->GetNativeWindow());
  }
  visible_ = true;
}

void QuickSearchPanel::PositionOnCursorMonitor() {
  if (!hwnd_) {
    return;
  }
  POINT cursor{};
  ::GetCursorPos(&cursor);
  HMONITOR monitor = ::MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  ::GetMonitorInfo(monitor, &info);
  const RECT& work = info.rcWork;

  const double scale = OwnerScale();
  const int panel_w =
      static_cast<int>(std::lround(ResolvedLogicalWidth() * scale));
  const int panel_h = static_cast<int>(std::lround(content_height_ * scale));

  const int work_w = work.right - work.left;
  const int work_h = work.bottom - work.top;
  const int x = work.left + (work_w - panel_w) / 2;
  // A little above vertical centre (~38% from the top) to match spotlight UX
  // and the macOS panel's 0.62-from-bottom placement.
  const int y = work.top + static_cast<int>((work_h - panel_h) * 0.38);

  ::SetWindowPos(hwnd_, HWND_TOPMOST, x, y, panel_w, panel_h,
                 SWP_NOACTIVATE);
}

void QuickSearchPanel::SetContentHeight(double logical_height) {
  content_height_ = std::max(kMinLogicalHeight, logical_height);
  if (!hwnd_ || !visible_) {
    return;
  }
  // Re-centre on the current monitor with the new height.
  PositionOnCursorMonitor();
}

void QuickSearchPanel::Hide() {
  if (!visible_ || !hwnd_) {
    return;
  }
  visible_ = false;
  ::ShowWindow(hwnd_, SW_HIDE);
  if (qs_channel_) {
    qs_channel_->InvokeMethod("clearSnapshot", nullptr);
  }
  if (main_channel_) {
    main_channel_->InvokeMethod("quickSearchPanelClosed", nullptr);
  }
}

double QuickSearchPanel::OwnerScale() const {
  UINT dpi = owner_ ? ::GetDpiForWindow(owner_) : 96;
  if (dpi == 0) dpi = 96;
  return static_cast<double>(dpi) / 96.0;
}

double QuickSearchPanel::ResolvedLogicalWidth() const {
  if (!owner_) {
    return kDefaultLogicalWidth;
  }
  RECT rect{};
  ::GetWindowRect(owner_, &rect);
  const double scale = OwnerScale();
  const double owner_logical_w =
      scale > 0 ? (rect.right - rect.left) / scale : kDefaultLogicalWidth;
  // 70% of the main window width, clamped — matches macOS.
  const double target = std::floor(owner_logical_w * 0.70);
  return std::max(kMinLogicalWidth, std::min(target, kMaxLogicalWidth));
}
