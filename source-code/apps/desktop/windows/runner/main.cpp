#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <winreg.h>

#include <algorithm>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kAutostartFlag[] = L"--autostart";
constexpr const wchar_t kStartMinimizedRegKey[] = L"Software\\LumenPass";
constexpr const wchar_t kStartMinimizedRegValue[] = L"StartMinimized";

bool HasAutostartFlag() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (!argv) return false;
  bool found = false;
  for (int i = 1; i < argc; ++i) {
    if (argv[i] && std::wstring(argv[i]) == kAutostartFlag) {
      found = true;
      break;
    }
  }
  ::LocalFree(argv);
  return found;
}

bool ReadStartMinimizedFlag() {
  HKEY hkey;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kStartMinimizedRegKey, 0,
                      KEY_QUERY_VALUE, &hkey) != ERROR_SUCCESS) {
    return false;
  }
  DWORD data = 0;
  DWORD size = sizeof(data);
  DWORD type = 0;
  bool ok = ::RegQueryValueExW(hkey, kStartMinimizedRegValue, nullptr, &type,
                               reinterpret_cast<BYTE*>(&data),
                               &size) == ERROR_SUCCESS;
  ::RegCloseKey(hkey);
  return ok && type == REG_DWORD && data != 0;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single-instance guard: create a session-scoped named mutex FIRST,
  // before attaching console or initializing COM. If another instance
  // already owns it, bring that window to the foreground, notify the
  // user, and exit immediately without starting any subsystems.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, /*bInitialOwner=*/TRUE,
                     L"Local\\LumenPassSingleInstance");
  if (single_instance_mutex == nullptr ||
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Best-effort: find the existing main window and restore it.
    HWND existing =
        ::FindWindowW(nullptr, L"LumenPass - Password Manager");
    if (existing) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
      ::BringWindowToTop(existing);
    }
    ::MessageBoxW(
        nullptr,
        L"LumenPass is already running.\n\n"
        L"The existing window has been brought to the front.",
        L"LumenPass", MB_OK | MB_ICONINFORMATION);
    if (single_instance_mutex) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_SUCCESS;
  }
  // The mutex handle is intentionally kept open. Windows releases it
  // automatically when the process exits (normal or crash).

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Strip the internal --autostart flag so it does not leak into Dart's
  // entrypoint arguments where plugins may try to parse it.
  command_line_arguments.erase(
      std::remove(command_line_arguments.begin(),
                  command_line_arguments.end(), std::string("--autostart")),
      command_line_arguments.end());

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // Honor "Start minimized" only when the OS auto-launched us at sign-in.
  // Manual launches (Start menu, Explorer) always show the UI.
  const bool launched_at_login = HasAutostartFlag();
  if (launched_at_login && ReadStartMinimizedFlag()) {
    window.SetStartHidden(true);
  }

  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"LumenPass - Password Manager", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
