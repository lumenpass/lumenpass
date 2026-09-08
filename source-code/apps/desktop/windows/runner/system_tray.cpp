#include "system_tray.h"

#include <strsafe.h>

#include "resource.h"

SystemTray::SystemTray(HWND owner) : owner_(owner) {}

SystemTray::~SystemTray() {
  Destroy();
}

void SystemTray::SetMenuCallback(MenuCallback callback) {
  callback_ = std::move(callback);
}

bool SystemTray::Create() {
  if (created_ || !owner_) {
    return created_;
  }

  ZeroMemory(&nid_, sizeof(nid_));
  nid_.cbSize = sizeof(NOTIFYICONDATAW);
  nid_.hWnd = owner_;
  nid_.uID = kTrayIconUid;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid_.uCallbackMessage = kTrayCallbackMessage;

  HINSTANCE instance = ::GetModuleHandle(nullptr);
  HICON icon = ::LoadIconW(instance, MAKEINTRESOURCEW(IDI_TRAY_ICON));
  if (!icon) {
    icon = ::LoadIconW(instance, MAKEINTRESOURCEW(IDI_APP_ICON));
  }
  if (!icon) {
    icon = ::LoadIconW(nullptr, IDI_APPLICATION);
  }
  nid_.hIcon = icon;

  StringCchCopyW(nid_.szTip, ARRAYSIZE(nid_.szTip), L"LumenPass");

  if (!::Shell_NotifyIconW(NIM_ADD, &nid_)) {
    return false;
  }

  nid_.uVersion = NOTIFYICON_VERSION_4;
  ::Shell_NotifyIconW(NIM_SETVERSION, &nid_);

  created_ = true;
  UpdateTooltip();
  return true;
}

void SystemTray::Destroy() {
  if (!created_) {
    return;
  }
  ::Shell_NotifyIconW(NIM_DELETE, &nid_);
  if (nid_.hIcon) {
    ::DestroyIcon(nid_.hIcon);
    nid_.hIcon = nullptr;
  }
  created_ = false;
}

void SystemTray::SetVaultLocked(bool locked) {
  vault_locked_ = locked;
  UpdateTooltip();
}

void SystemTray::UpdateTooltip() {
  if (!created_) {
    return;
  }
  const wchar_t* tip = vault_locked_
                           ? L"LumenPass (Locked)"
                           : L"LumenPass";
  StringCchCopyW(nid_.szTip, ARRAYSIZE(nid_.szTip), tip);
  nid_.uFlags = NIF_TIP;
  ::Shell_NotifyIconW(NIM_MODIFY, &nid_);
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
}

bool SystemTray::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message != kTrayCallbackMessage) {
    return false;
  }

  UINT event = LOWORD(lparam);

  switch (event) {
    case WM_LBUTTONUP:
    case NIN_SELECT:
    case NIN_KEYSELECT:
      if (callback_) {
        callback_(MenuAction::kShow);
      }
      return true;

    case WM_RBUTTONUP:
    case WM_CONTEXTMENU:
      ShowContextMenu();
      return true;

    default:
      return true;
  }
}

void SystemTray::ShowContextMenu() {
  if (!owner_) {
    return;
  }

  POINT pt;
  ::GetCursorPos(&pt);

  HMENU menu = ::CreatePopupMenu();
  if (!menu) {
    return;
  }

  ::AppendMenuW(menu, MF_STRING, IDM_TRAY_SHOW, L"Open LumenPass");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, IDM_TRAY_QUICK_SEARCH, L"Quick Search");
  ::AppendMenuW(menu, MF_STRING, IDM_TRAY_GENERATE_PASSWORD,
                L"Generate Password");
  ::AppendMenuW(menu, MF_STRING, IDM_TRAY_SWITCH_VAULTS, L"Switch Vaults");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu,
                MF_STRING | (vault_locked_ ? MF_GRAYED : MF_ENABLED),
                IDM_TRAY_LOCK, L"Lock Vault");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, IDM_TRAY_SETTINGS, L"Settings");
  ::AppendMenuW(menu, MF_STRING, IDM_TRAY_ABOUT, L"About");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, IDM_TRAY_QUIT, L"Quit");

  ::SetForegroundWindow(owner_);

  UINT flags = TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY;
  if (::GetSystemMetrics(SM_MENUDROPALIGNMENT) != 0) {
    flags |= TPM_RIGHTALIGN;
  } else {
    flags |= TPM_LEFTALIGN;
  }

  int command = ::TrackPopupMenuEx(menu, flags, pt.x, pt.y, owner_, nullptr);
  ::DestroyMenu(menu);

  if (command == 0 || !callback_) {
    return;
  }

  switch (command) {
    case IDM_TRAY_SHOW:
      callback_(MenuAction::kShow);
      break;
    case IDM_TRAY_QUICK_SEARCH:
      callback_(MenuAction::kQuickSearch);
      break;
    case IDM_TRAY_GENERATE_PASSWORD:
      callback_(MenuAction::kGeneratePassword);
      break;
    case IDM_TRAY_SWITCH_VAULTS:
      callback_(MenuAction::kSwitchVaults);
      break;
    case IDM_TRAY_LOCK:
      callback_(MenuAction::kLock);
      break;
    case IDM_TRAY_SETTINGS:
      callback_(MenuAction::kSettings);
      break;
    case IDM_TRAY_ABOUT:
      callback_(MenuAction::kAbout);
      break;
    case IDM_TRAY_QUIT:
      callback_(MenuAction::kQuit);
      break;
    default:
      break;
  }
}
