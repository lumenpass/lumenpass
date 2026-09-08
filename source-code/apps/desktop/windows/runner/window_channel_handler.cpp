#include "window_channel_handler.h"

#include <flutter/encodable_value.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <winreg.h>
#include <appmodel.h>

#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>

#include <fstream>
#include <map>
#include <string>
#include <vector>

#include "quick_search_panel.h"

namespace {

std::string Utf8FromUtf16(const std::wstring& utf16) {
  if (utf16.empty()) {
    return std::string();
  }
  int size = ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                   utf16.data(),
                                   static_cast<int>(utf16.size()),
                                   nullptr, 0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string result(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                        utf16.data(), static_cast<int>(utf16.size()),
                        result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                   utf8.data(),
                                   static_cast<int>(utf8.size()),
                                   nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring result(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                        utf8.data(), static_cast<int>(utf8.size()),
                        result.data(), size);
  return result;
}

std::string GetExecutablePath() {
  wchar_t path[MAX_PATH];
  ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  return Utf8FromUtf16(path);
}

constexpr const wchar_t kAutostartRegKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr const wchar_t kAutostartRegValue[] = L"LumenPass";
constexpr const wchar_t kStartMinimizedRegKey[] =
    L"Software\\LumenPass";
constexpr const wchar_t kStartMinimizedRegValue[] = L"StartMinimized";

bool SetRegistryDword(HKEY root, const wchar_t* key, const wchar_t* value,
                      DWORD data) {
  HKEY hkey;
  if (::RegCreateKeyExW(root, key, 0, nullptr, 0, KEY_SET_VALUE, nullptr,
                        &hkey, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  bool ok = ::RegSetValueExW(hkey, value, 0, REG_DWORD,
                             reinterpret_cast<const BYTE*>(&data),
                             sizeof(data)) == ERROR_SUCCESS;
  ::RegCloseKey(hkey);
  return ok;
}

bool GetRegistryDword(HKEY root, const wchar_t* key, const wchar_t* value,
                      DWORD* out) {
  HKEY hkey;
  if (::RegOpenKeyExW(root, key, 0, KEY_QUERY_VALUE, &hkey) != ERROR_SUCCESS) {
    return false;
  }
  DWORD data = 0;
  DWORD size = sizeof(data);
  bool ok = ::RegQueryValueExW(hkey, value, nullptr, nullptr,
                               reinterpret_cast<BYTE*>(&data),
                               &size) == ERROR_SUCCESS;
  if (ok && out) *out = data;
  ::RegCloseKey(hkey);
  return ok;
}

bool IsRunningAsPackagedApp() {
  UINT32 length = 0;
  LONG result = ::GetCurrentPackageFamilyName(&length, nullptr);
  return result == ERROR_INSUFFICIENT_BUFFER;
}

constexpr const wchar_t kStartupTaskId[] = L"LumenPassStartup";

}  // namespace

WindowChannelHandler::WindowChannelHandler(HWND window_handle)
    : window_handle_(window_handle) {}

WindowChannelHandler::~WindowChannelHandler() {
  UnregisterAllHotKeys();
  if (system_tray_) {
    system_tray_->Destroy();
  }
}

void WindowChannelHandler::Register(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lumenpass/window",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HandleMethodCall(call, std::move(result));
      });

  InitSystemTray();
}

void WindowChannelHandler::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "bringToFront") {
    BringToFront();
    result->Success();

  } else if (method == "quit") {
    Quit();
    result->Success();

  } else if (method == "setSize") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map argument");
      return;
    }
    auto w_it = args->find(flutter::EncodableValue("width"));
    auto h_it = args->find(flutter::EncodableValue("height"));
    if (w_it == args->end() || h_it == args->end()) {
      result->Error("INVALID_ARGS", "Missing width or height");
      return;
    }
    double width = std::get<double>(w_it->second);
    double height = std::get<double>(h_it->second);
    SetSize(width, height);
    result->Success();

  } else if (method == "showNativeTitleBar") {
    std::string title = "LumenPass - Password Manager";
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("title"));
      if (it != args->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) {
          title = *s;
        }
      }
    }
    ShowNativeTitleBar(title);
    result->Success();

  } else if (method == "hideNativeTitleBar") {
    HideNativeTitleBar();
    result->Success();

  } else if (method == "setAutostart") {
    const auto* enabled = std::get_if<bool>(call.arguments());
    if (!enabled) {
      result->Error("INVALID_ARGS", "Expected boolean argument");
      return;
    }
    if (SetAutostart(*enabled)) {
      result->Success();
    } else {
      result->Error("AUTOSTART_FAILED", "Could not update startup state");
    }

  } else if (method == "getAutostart") {
    result->Success(flutter::EncodableValue(GetAutostart()));

  } else if (method == "setStartMinimized") {
    const auto* enabled = std::get_if<bool>(call.arguments());
    if (!enabled) {
      result->Error("INVALID_ARGS", "Expected boolean argument");
      return;
    }
    SetStartMinimized(*enabled);
    result->Success();

  } else if (method == "hideWindow") {
    HideWindow();
    result->Success();

  } else if (method == "showQuickSearchWindow") {
    ShowQuickSearchWindow();
    result->Success();

  } else if (method == "showQuickSearchPanel") {
    bool open_generator = false;
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments())) {
      auto it = args->find(flutter::EncodableValue("openGenerator"));
      if (it != args->end()) {
        if (const auto* b = std::get_if<bool>(&it->second)) {
          open_generator = *b;
        }
      }
    }
    ShowQuickSearchPanel(open_generator);
    result->Success();

  } else if (method == "hideQuickSearchPanel") {
    HideQuickSearchPanel();
    result->Success();

  } else if (method == "enterQuickSearchMode") {
    ShowQuickSearchWindow();
    result->Success();

  } else if (method == "exitQuickSearchMode") {
    BringToFront();
    result->Success();

  } else if (method == "setQuickSearchSize") {
    result->Success();

  } else if (method == "setHideDockIcon") {
    result->Success();

  } else if (method == "setTrayIconOpacity") {
    result->Success();

  } else if (method == "setTrayVaultLocked") {
    const auto* locked = std::get_if<bool>(call.arguments());
    if (locked && system_tray_) {
      system_tray_->SetVaultLocked(*locked);
    }
    result->Success();

  } else if (method == "updateQuickSearchHotKey") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map argument");
      return;
    }
    auto vk_it = args->find(flutter::EncodableValue("vkCode"));
    auto mod_it = args->find(flutter::EncodableValue("modifiers"));
    if (vk_it == args->end() || mod_it == args->end()) {
      result->Error("INVALID_ARGS", "Missing vkCode or modifiers");
      return;
    }
    int vk = std::get<int>(vk_it->second);
    int modifiers = std::get<int>(mod_it->second);
    UpdateQuickSearchHotKey(vk, static_cast<UINT>(modifiers));
    if (!quick_search_registered_) {
      DWORD err = last_error_;
      std::string msg = "RegisterHotKey failed for quickSearch (vk=" +
                        std::to_string(vk) + " mod=" +
                        std::to_string(modifiers) + " err=" +
                        std::to_string(err) + ")";
      result->Error("HOTKEY_REGISTRATION_FAILED", msg);
    } else {
      result->Success();
    }

  } else if (method == "clearQuickSearchHotKey") {
    ClearQuickSearchHotKey();
    result->Success();

  } else if (method == "updateLockVaultHotKey") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map argument");
      return;
    }
    auto vk_it = args->find(flutter::EncodableValue("vkCode"));
    auto mod_it = args->find(flutter::EncodableValue("modifiers"));
    if (vk_it == args->end() || mod_it == args->end()) {
      result->Error("INVALID_ARGS", "Missing vkCode or modifiers");
      return;
    }
    int vk = std::get<int>(vk_it->second);
    int modifiers = std::get<int>(mod_it->second);
    UpdateLockVaultHotKey(vk, static_cast<UINT>(modifiers));
    if (!lock_vault_registered_) {
      DWORD err = last_error_;
      std::string msg = "RegisterHotKey failed for lockVault (vk=" +
                        std::to_string(vk) + " mod=" +
                        std::to_string(modifiers) + " err=" +
                        std::to_string(err) + ")";
      result->Error("HOTKEY_REGISTRATION_FAILED", msg);
    } else {
      result->Success();
    }

  } else if (method == "clearLockVaultHotKey") {
    ClearLockVaultHotKey();
    result->Success();

  } else if (method == "showSshApprovalWindow") {
    // No native approval panel on Windows yet. Return null so the Dart side
    // falls back to the in-app Flutter modal (see _showApprovalDialog).
    // Returning `false` here would make the agent refuse the signing request
    // without ever prompting the user.
    BringToFront();
    result->Success();

  } else if (method == "decodeQRFromFile") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map argument");
      return;
    }
    auto it = args->find(flutter::EncodableValue("path"));
    if (it == args->end()) {
      result->Error("INVALID_ARGS", "Missing path");
      return;
    }
    const auto* path_str = std::get_if<std::string>(&it->second);
    if (!path_str) {
      result->Error("INVALID_ARGS", "Path must be a string");
      return;
    }
    DecodeQRFromFile(*path_str, std::move(result));

  } else if (method == "scanScreen") {
    result->Success();

  } else if (method == "pickFileWithBookmark") {
    IFileOpenDialog* dialog = nullptr;
    HRESULT hr = ::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) {
      result->Error("DIALOG_FAILED", "Could not create open dialog");
      return;
    }
    COMDLG_FILTERSPEC filters[] = {
        {L"KeePass Database", L"*.kdbx"},
        {L"All Files", L"*.*"},
    };
    dialog->SetFileTypes(ARRAYSIZE(filters), filters);
    dialog->SetTitle(L"Open KeePass Database");
    hr = dialog->Show(window_handle_);
    if (FAILED(hr)) {
      dialog->Release();
      result->Success();
      return;
    }
    IShellItem* item = nullptr;
    hr = dialog->GetResult(&item);
    if (FAILED(hr)) {
      dialog->Release();
      result->Success();
      return;
    }
    wchar_t* path_ptr = nullptr;
    item->GetDisplayName(SIGDN_FILESYSPATH, &path_ptr);
    std::string path = path_ptr ? Utf8FromUtf16(path_ptr) : std::string();
    if (path_ptr) ::CoTaskMemFree(path_ptr);
    item->Release();
    dialog->Release();
    if (path.empty()) {
      result->Success();
      return;
    }
    flutter::EncodableMap map;
    map[flutter::EncodableValue("path")] = flutter::EncodableValue(path);
    map[flutter::EncodableValue("bookmark")] = flutter::EncodableValue(path);
    result->Success(flutter::EncodableValue(map));

  } else if (method == "pickDirectoryWithBookmark") {
    IFileOpenDialog* dialog = nullptr;
    HRESULT hr = ::CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&dialog));
    if (FAILED(hr)) {
      result->Error("DIALOG_FAILED", "Could not create folder dialog");
      return;
    }
    DWORD options = 0;
    dialog->GetOptions(&options);
    dialog->SetOptions(options | FOS_PICKFOLDERS);
    dialog->SetTitle(L"Choose save location");
    hr = dialog->Show(window_handle_);
    if (FAILED(hr)) {
      dialog->Release();
      result->Success();
      return;
    }
    IShellItem* item = nullptr;
    hr = dialog->GetResult(&item);
    if (FAILED(hr)) {
      dialog->Release();
      result->Success();
      return;
    }
    wchar_t* path_ptr = nullptr;
    item->GetDisplayName(SIGDN_FILESYSPATH, &path_ptr);
    std::string path = path_ptr ? Utf8FromUtf16(path_ptr) : std::string();
    if (path_ptr) ::CoTaskMemFree(path_ptr);
    item->Release();
    dialog->Release();
    if (path.empty()) {
      result->Success();
      return;
    }
    flutter::EncodableMap map;
    map[flutter::EncodableValue("path")] = flutter::EncodableValue(path);
    map[flutter::EncodableValue("bookmark")] = flutter::EncodableValue(path);
    result->Success(flutter::EncodableValue(map));

  } else if (method == "createBookmarkForPath") {
    const auto* path_str = std::get_if<std::string>(call.arguments());
    if (!path_str || path_str->empty()) {
      result->Error("INVALID_ARGS", "Expected string path argument");
      return;
    }
    result->Success(flutter::EncodableValue(*path_str));

  } else if (method == "resolveBookmark") {
    const auto* bookmark = std::get_if<std::string>(call.arguments());
    if (!bookmark || bookmark->empty()) {
      result->Error("INVALID_ARGS", "Expected string bookmark argument");
      return;
    }
    result->Success(flutter::EncodableValue(*bookmark));

  } else if (method == "stopAccessingBookmark") {
    result->Success();

  } else {
    result->NotImplemented();
  }
}

void WindowChannelHandler::BringToFront() {
  if (!window_handle_) return;
  ::ShowWindow(window_handle_, SW_RESTORE);
  ::SetForegroundWindow(window_handle_);
  ::BringWindowToTop(window_handle_);
}

void WindowChannelHandler::Quit() {
  if (system_tray_) {
    system_tray_->Destroy();
  }
  if (window_handle_) {
    ::DestroyWindow(window_handle_);
  }
}

void WindowChannelHandler::SetSize(double width, double height) {
  if (!window_handle_) return;
  UINT dpi = ::GetDpiForWindow(window_handle_);
  if (dpi == 0) dpi = 96;
  double scale = static_cast<double>(dpi) / 96.0;

  int w = static_cast<int>(width * scale);
  int h = static_cast<int>(height * scale);

  RECT rect;
  ::GetWindowRect(window_handle_, &rect);
  HMONITOR monitor = ::MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  ::GetMonitorInfoW(monitor, &info);

  int cx = (info.rcWork.left + info.rcWork.right) / 2;
  int cy = (info.rcWork.top + info.rcWork.bottom) / 2;
  int left = cx - w / 2;
  int top = cy - h / 2;

  RECT clientRect;
  ::GetClientRect(window_handle_, &clientRect);
  RECT windowRect;
  ::GetWindowRect(window_handle_, &windowRect);
  int frameW = (windowRect.right - windowRect.left) - (clientRect.right - clientRect.left);
  int frameH = (windowRect.bottom - windowRect.top) - (clientRect.bottom - clientRect.top);

  ::SetWindowPos(window_handle_, nullptr, left, top,
                 w + frameW, h + frameH,
                 SWP_NOZORDER | SWP_NOACTIVATE);
}

void WindowChannelHandler::ShowNativeTitleBar(const std::string& title) {
  if (!window_handle_) return;
  std::wstring wtitle = Utf16FromUtf8(title);
  ::SetWindowTextW(window_handle_, wtitle.c_str());
}

void WindowChannelHandler::HideNativeTitleBar() {
}

bool WindowChannelHandler::SetAutostart(bool enabled) {
  if (IsRunningAsPackagedApp()) {
    try {
      using namespace winrt::Windows::ApplicationModel;
      auto task = StartupTask::GetAsync(kStartupTaskId).get();
      if (enabled) {
        auto state = task.RequestEnableAsync().get();
        return state == StartupTaskState::Enabled ||
               state == StartupTaskState::EnabledByPolicy;
      } else {
        task.Disable();
        return true;
      }
    } catch (...) {
      return false;
    }
  }

  std::string exe_path = GetExecutablePath();
  std::wstring wexe = Utf16FromUtf8(exe_path);
  std::wstring command;
  command.reserve(wexe.size() + 16);
  command.push_back(L'"');
  command.append(wexe);
  command.append(L"\" --autostart");

  HKEY hkey;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kAutostartRegKey, 0,
                      KEY_SET_VALUE | KEY_QUERY_VALUE,
                      &hkey) != ERROR_SUCCESS) {
    return false;
  }
  bool ok = false;
  if (enabled) {
    ok = ::RegSetValueExW(
             hkey, kAutostartRegValue, 0, REG_SZ,
             reinterpret_cast<const BYTE*>(command.c_str()),
             static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
  } else {
    LSTATUS status = ::RegDeleteValueW(hkey, kAutostartRegValue);
    ok = (status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND);
  }
  ::RegCloseKey(hkey);
  return ok;
}

bool WindowChannelHandler::GetAutostart() {
  if (IsRunningAsPackagedApp()) {
    try {
      using namespace winrt::Windows::ApplicationModel;
      auto task = StartupTask::GetAsync(kStartupTaskId).get();
      auto state = task.State();
      return state == StartupTaskState::Enabled ||
             state == StartupTaskState::EnabledByPolicy;
    } catch (...) {
      return false;
    }
  }

  HKEY hkey;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kAutostartRegKey, 0,
                      KEY_QUERY_VALUE, &hkey) != ERROR_SUCCESS) {
    return false;
  }
  bool present = ::RegQueryValueExW(hkey, kAutostartRegValue, nullptr, nullptr,
                                    nullptr, nullptr) == ERROR_SUCCESS;
  ::RegCloseKey(hkey);
  return present;
}

void WindowChannelHandler::SetStartMinimized(bool enabled) {
  SetRegistryDword(HKEY_CURRENT_USER, kStartMinimizedRegKey,
                   kStartMinimizedRegValue, enabled ? 1 : 0);
}

void WindowChannelHandler::HideWindow() {
  if (!window_handle_) return;
  ::ShowWindow(window_handle_, SW_HIDE);
}

void WindowChannelHandler::ShowQuickSearchWindow() {
  BringToFront();
}

void WindowChannelHandler::ShowQuickSearchPanel(bool open_generator) {
  if (quick_search_panel_) {
    quick_search_panel_->Show(open_generator);
    return;
  }
  // No isolated panel available — fall back to surfacing the main window.
  BringToFront();
}

void WindowChannelHandler::HideQuickSearchPanel() {
  if (quick_search_panel_) {
    quick_search_panel_->Hide();
  }
}

void WindowChannelHandler::DecodeQRFromFile(
    const std::string& path,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  result->Success();
}

void WindowChannelHandler::UpdateQuickSearchHotKey(int vk, UINT modifiers) {
  ClearQuickSearchHotKey();
  if (!window_handle_ || vk == 0) return;
  quick_search_vk_ = vk;
  quick_search_modifiers_ = modifiers;
  BOOL ok = ::RegisterHotKey(window_handle_, kQuickSearchHotKeyId, modifiers, vk);
  last_error_ = ok ? 0 : ::GetLastError();
  quick_search_registered_ = ok != 0;
}

void WindowChannelHandler::ClearQuickSearchHotKey() {
  if (quick_search_registered_ && window_handle_) {
    ::UnregisterHotKey(window_handle_, kQuickSearchHotKeyId);
  }
  quick_search_registered_ = false;
  quick_search_vk_ = 0;
  quick_search_modifiers_ = 0;
}

void WindowChannelHandler::UpdateLockVaultHotKey(int vk, UINT modifiers) {
  ClearLockVaultHotKey();
  if (!window_handle_ || vk == 0) return;
  lock_vault_vk_ = vk;
  lock_vault_modifiers_ = modifiers;
  BOOL ok = ::RegisterHotKey(window_handle_, kLockVaultHotKeyId, modifiers, vk);
  last_error_ = ok ? 0 : ::GetLastError();
  lock_vault_registered_ = ok != 0;
}

void WindowChannelHandler::ClearLockVaultHotKey() {
  if (lock_vault_registered_ && window_handle_) {
    ::UnregisterHotKey(window_handle_, kLockVaultHotKeyId);
  }
  lock_vault_registered_ = false;
  lock_vault_vk_ = 0;
  lock_vault_modifiers_ = 0;
}

void WindowChannelHandler::UnregisterAllHotKeys() {
  ClearQuickSearchHotKey();
  ClearLockVaultHotKey();
}

bool WindowChannelHandler::HandleHotKeyMessage(WPARAM wparam) {
  int id = static_cast<int>(wparam);
  if (id == kQuickSearchHotKeyId) {
    // Toggle the isolated Quick Search panel directly in native so the hotkey
    // works even when the main window isn't focused. The panel pulls a fresh
    // vault snapshot from the main engine on open. Falls back to the legacy
    // in-window overlay only if the panel could not be created.
    if (quick_search_panel_) {
      quick_search_panel_->Toggle();
      return true;
    }
    if (channel_) {
      channel_->InvokeMethod("quickSearchHotkeyPressed", nullptr);
      return true;
    }
  }
  if (id == kLockVaultHotKeyId && channel_) {
    channel_->InvokeMethod("lockVaultHotkeyPressed", nullptr);
    return true;
  }
  return false;
}

bool WindowChannelHandler::HandleTrayMessage(UINT message, WPARAM wparam,
                                             LPARAM lparam) {
  if (system_tray_) {
    return system_tray_->HandleMessage(message, wparam, lparam);
  }
  return false;
}

void WindowChannelHandler::InitSystemTray() {
  system_tray_ = std::make_unique<SystemTray>(window_handle_);
  system_tray_->SetMenuCallback(
      [this](SystemTray::MenuAction action) { OnTrayAction(action); });
  system_tray_->Create();
}

void WindowChannelHandler::OnTrayAction(SystemTray::MenuAction action) {
  using MA = SystemTray::MenuAction;

  switch (action) {
    case MA::kShow:
      BringToFront();
      if (channel_) {
        channel_->InvokeMethod(
            "trayActionTriggered",
            std::make_unique<flutter::EncodableValue>("openDashboard"));
      }
      break;
    case MA::kQuickSearch:
      // Prefer the isolated panel (second engine) so the main window is left
      // undisturbed. Fall back to surfacing the main window's in-window
      // overlay if the panel isn't available.
      if (quick_search_panel_) {
        quick_search_panel_->Show(false);
      } else {
        BringToFront();
        if (channel_) {
          channel_->InvokeMethod(
              "trayActionTriggered",
              std::make_unique<flutter::EncodableValue>("quickSearch"));
        }
      }
      break;
    case MA::kGeneratePassword:
      if (quick_search_panel_) {
        quick_search_panel_->Show(true);
      } else {
        BringToFront();
        if (channel_) {
          channel_->InvokeMethod(
              "trayActionTriggered",
              std::make_unique<flutter::EncodableValue>("generatePassword"));
        }
      }
      break;
    case MA::kSwitchVaults:
      BringToFront();
      if (channel_) {
        channel_->InvokeMethod(
            "trayActionTriggered",
            std::make_unique<flutter::EncodableValue>("switchVaults"));
      }
      break;
    case MA::kLock:
      if (channel_) {
        channel_->InvokeMethod(
            "trayActionTriggered",
            std::make_unique<flutter::EncodableValue>("lockVault"));
      }
      break;
    case MA::kSettings:
      BringToFront();
      break;
    case MA::kAbout:
      BringToFront();
      break;
    case MA::kQuit:
      if (system_tray_) {
        system_tray_->Destroy();
      }
      Quit();
      break;
  }
}
