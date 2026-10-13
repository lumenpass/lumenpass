# Quick Search isolated panel — Windows & Linux draft (for on-device verification)

This is a **draft** implemented on macOS (which cannot compile Windows/Linux). It
mirrors the working macOS isolated-panel design (Option A: a second Flutter
engine on the `quickSearchMain` entrypoint hosted in a borderless native
window). Build + adjust on each target machine.

## What was added

### Shared Dart (already builds — verified via `flutter analyze` + macOS build)
- `lib/main.dart`: `main(List<String> args)` now delegates to `quickSearchMain()`
  when launched with the sentinel arg `--quick-search-panel` (Linux only — see
  below). macOS/Windows launch the entrypoint directly.
- `lib/features/vault/presentation/vault_screen.dart`: `_openQuickSearch` now
  takes the isolated-panel path (`showQuickSearchPanel`) on macOS **and**
  Windows **and** Linux (previously macOS only).
- `vault_screen_quick_search.dart`: the two macOS-only *layout* gates
  (`standalone && Platform.isMacOS`) were generalized to `standalone`, since all
  three desktops now render inside the borderless panel window. The Cmd-vs-Ctrl
  modifier gate (`_isPrimaryModifierDown`) was intentionally left as
  `Platform.isMacOS`.

### Windows (`windows/runner/`)
- NEW `quick_search_panel.{h,cpp}`: `QuickSearchPanel` — boots a 2nd
  `FlutterViewController` with `project.set_dart_entrypoint("quickSearchMain")`
  in a `WS_POPUP | WS_EX_TOOLWINDOW | WS_EX_TOPMOST` window. Wires the
  `lumenpass/quick_search` channel; positions on the monitor under the cursor
  (`GetCursorPos` + `MonitorFromPoint`); dismisses on `WM_ACTIVATE`(inactive) /
  `WM_KILLFOCUS` / snapshot-driven height changes. DWM rounded corners +
  `CS_DROPSHADOW`.
- `window_channel_handler.{h,cpp}`: exposes `channel()`, holds a
  `QuickSearchPanel*`, adds `showQuickSearchPanel`/`hideQuickSearchPanel` method
  cases, routes the **hotkey** (`WM_HOTKEY`) and the **tray** QuickSearch /
  GeneratePassword actions directly to the panel.
- `flutter_window.{h,cpp}`: creates the panel after the main engine, links it to
  the handler, tears it down first in `OnDestroy`.
- `CMakeLists.txt`: added `quick_search_panel.cpp`.

### Linux (`linux/runner/`)
- NEW `quick_search_panel.{h,cc}`: `QuickSearchPanel` — boots a 2nd `FlView`
  (via `fl_view_new`) in a borderless, keep-above, skip-taskbar `GtkWindow`.
  Positions on the monitor under the pointer
  (`gdk_display_get_monitor_at_point`); dismisses on `focus-out-event` and
  `Escape`.
- `window_channel_handler.{h,cc}`: exposes `channel()`, holds the panel, adds
  `showQuickSearchPanel`/`hideQuickSearchPanel`, routes the **tray** QuickSearch
  / GeneratePassword actions to the panel.
- `my_application.cc`: creates/disposes the panel alongside the handler.
- `runner/CMakeLists.txt`: added `quick_search_panel.cc`.

## Platform caveats to check on-device

1. **Linux entrypoint sentinel (most important).** The GTK embedder in this
   Flutter version has NO custom-entrypoint API (only
   `fl_dart_project_set_dart_entrypoint_arguments`). So the Linux panel passes
   `--quick-search-panel` as a Dart entrypoint arg and `main()` branches to
   `quickSearchMain()`. VERIFY the arg actually arrives in Dart's
   `main(List<String> args)` on your embedder build. If it does not, the
   fallback is to read it via `PlatformDispatcher`/an env var, or check whether
   your engine version exposes a newer entrypoint API.

2. **Linux has no global hotkey.** This codebase's Linux
   `updateQuickSearchHotKey` is a no-op (unlike Windows `RegisterHotKey` /
   macOS Carbon). So on Linux the panel is reachable via the **tray** action,
   not a global hotkey. If you want a true global hotkey on Linux it's a
   separate task (portal/X11 grab), out of scope here.

3. **Focus-without-activation.** macOS `.nonactivatingPanel` is purpose-built
   for this. Windows uses `SW_SHOWNOACTIVATE` + explicit `SetForegroundWindow`/
   `SetFocus`; Linux uses `gtk_window_present`. Both may need tuning so taking
   panel focus doesn't visibly raise/activate the main window. Watch the
   dismiss-on-focus-loss logic (Windows `WM_KILLFOCUS`, Linux `focus-out-event`)
   for false dismissals when a child/IME grabs focus.

4. **DPI / sizing.** Windows scales logical→physical via `GetDpiForWindow`.
   Linux GTK sizes are logical. Confirm panel width (~70% of main window,
   clamped 560–900) and the snapshot-driven height look right.

## Build commands
- Windows: `flutter build windows --debug` (needs VS/MSVC).
- Linux:   `flutter build linux --debug` (needs GTK3 + pkg-config dev headers).

## Channel contract (unchanged from macOS)
- native → panel engine: `setSnapshot(String json)`
- panel engine → native: `ready | close | openEntry(uuid) | editEntry(uuid) |
  createItem | heightChanged({height})`
- native → main engine (`lumenpass/window`): `quickSearchRequestSnapshot({openGenerator})`
  (returns snapshot JSON) `| quickSearchOpenEntry(uuid) | quickSearchEditEntry(uuid) |
  quickSearchCreateItem | quickSearchPanelClosed`
