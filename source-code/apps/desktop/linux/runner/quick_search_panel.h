#ifndef RUNNER_QUICK_SEARCH_PANEL_H_
#define RUNNER_QUICK_SEARCH_PANEL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <string>

// Isolated Quick Search panel (Option A: a *second* Flutter engine hosted in a
// borderless, always-on-top GtkWindow). This mirrors the macOS
// `QuickSearchPanel` (NSPanel + FlutterEngine on `quickSearchMain`) and the
// Windows `QuickSearchPanel` (popup HWND + second FlutterViewController), so
// the main application window is never transformed, hidden or resized.
//
// IMPORTANT — Linux entrypoint difference:
// The GTK embedder in this Flutter version exposes
// `fl_dart_project_set_dart_entrypoint_arguments` but *no* API to launch a
// custom Dart entrypoint (unlike macOS `run(withEntrypoint:)` and Windows
// `DartProject::set_dart_entrypoint`). The second engine therefore runs the
// normal `main()`, which detects the sentinel argument `--quick-search-panel`
// and delegates to `quickSearchMain()`. See lib/main.dart.
//
// The panel engine has its own Dart isolate and no access to the decrypted
// vault. It talks over two method channels, brokered here in native code:
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
// The main channel is owned by WindowChannelHandler and passed in; this class
// never takes ownership of it.
class QuickSearchPanel {
 public:
  // |main_view| is the main engine's FlView (used to derive the toplevel
  // GtkWindow for width heuristics). |main_channel| is the main engine's
  // lumenpass/window channel used to broker vault-backed intents. Neither is
  // owned by this class.
  QuickSearchPanel(FlView* main_view, FlMethodChannel* main_channel);
  ~QuickSearchPanel();

  QuickSearchPanel(const QuickSearchPanel&) = delete;
  QuickSearchPanel& operator=(const QuickSearchPanel&) = delete;

  // Shows the panel if hidden, hides it if visible.
  void Toggle();

  // Pulls a fresh snapshot from the main engine and reveals the panel on the
  // monitor currently containing the pointer.
  void Show(bool open_generator);

  // Hides the panel and notifies the main engine (quickSearchPanelClosed).
  void Hide();

  bool IsVisible() const { return visible_; }

 private:
  // Lazily boots the second engine + GtkWindow. Returns false on failure.
  bool EnsureCreated();

  // Positions the panel on the monitor under the pointer and presents it.
  void Reveal();
  void PositionOnPointerMonitor();
  void SetContentHeight(double logical_height);
  int ResolvedLogicalWidth() const;

  // lumenpass/quick_search channel handler.
  static void OnQuickSearchCall(FlMethodChannel* channel,
                                FlMethodCall* method_call, gpointer user_data);
  void HandleQuickSearchCall(FlMethodCall* method_call,
                             FlMethodResponse** response);

  // Callback for the quickSearchRequestSnapshot reply from the main engine.
  static void OnSnapshotReply(GObject* source, GAsyncResult* result,
                              gpointer user_data);

  // "focus-out-event" on the panel window -> dismiss (mirrors macOS
  // onResignKey / Windows WM_ACTIVATE inactive).
  static gboolean OnFocusOut(GtkWidget* widget, GdkEvent* event,
                             gpointer user_data);
  // "key-press-event" -> Escape dismisses.
  static gboolean OnKeyPress(GtkWidget* widget, GdkEventKey* event,
                             gpointer user_data);

  FlView* main_view_ = nullptr;
  FlMethodChannel* main_channel_ = nullptr;

  GtkWidget* window_ = nullptr;  // borderless toplevel
  FlView* view_ = nullptr;       // second engine's view
  FlMethodChannel* channel_ = nullptr;

  bool visible_ = false;
  double content_height_ = 178.0;  // logical px; mirrors macOS default

  static constexpr int kDefaultLogicalWidth = 640;
  static constexpr int kMinLogicalWidth = 560;
  static constexpr int kMaxLogicalWidth = 900;
  static constexpr double kMinLogicalHeight = 80.0;
};

#endif  // RUNNER_QUICK_SEARCH_PANEL_H_
