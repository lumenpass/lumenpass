#ifndef RUNNER_SETTINGS_WINDOW_H_
#define RUNNER_SETTINGS_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <string>

// Detached Settings window (native host).
//
// Hosts a *second* Flutter engine running the Settings UI in a real,
// independent GtkWindow. This mirrors the macOS `SettingsWindowController`
// (macos/Runner/SettingsWindow.swift) and the Windows `SettingsWindow`: the
// main window is never resized, hidden or overlaid while Settings is open,
// and both windows stay independently usable.
//
// IMPORTANT — Linux entrypoint difference:
// The GTK embedder cannot launch a custom Dart entrypoint, so the second
// engine runs the normal `main()` with the sentinel argument
// `--settings-window`, which delegates to `settingsMain()`. See lib/main.dart.
//
// The settings engine has its own Dart isolate, so it cannot read the main
// engine's providers. This class relays between two method channels that
// share the name `lumenpass/settings_host`:
//
//   settings engine --ready/requestSettings/applySetting--> native
//            native --requestSettings/applySetting--------> main engine
//            native <------------- JSON snapshot ---------- main engine
//   settings engine <--- setSnapshot(JSON) / setSection --- native
//
// The main engine stays the single source of truth (see SettingsHostBridge in
// lib/features/settings/application/settings_host_bridge.dart).
//
// The window is created lazily on first open and destroyed (engine included)
// when the user closes it, so a closed Settings window costs nothing.
class SettingsWindow {
 public:
  // |main_view| is the main engine's FlView; its messenger is used to reach
  // the main engine. Not owned; must outlive this object.
  explicit SettingsWindow(FlView* main_view);
  ~SettingsWindow();

  SettingsWindow(const SettingsWindow&) = delete;
  SettingsWindow& operator=(const SettingsWindow&) = delete;

  // Brings the Settings window to the front, creating it on first use.
  // |section| is the Dart-side pane id (`general`, `appearance`, `security`,
  // `advanced`, `about`); empty keeps the current pane. Returns false if the
  // window could not be created.
  bool Open(const std::string& section);

 private:
  bool EnsureCreated();

  // Releases the settings engine and its channel. Called when the window is
  // destroyed (user closed it) and from the destructor.
  void Teardown();

  static void OnSettingsCall(FlMethodChannel* channel,
                             FlMethodCall* method_call, gpointer user_data);
  static void OnWindowDestroy(GtkWidget* widget, gpointer user_data);

  // Forwards |method_call| to the main engine and answers it asynchronously.
  void RelayToMainEngine(FlMethodCall* method_call);
  static void OnRelayReply(GObject* source, GAsyncResult* result,
                           gpointer user_data);
  static void OnSnapshotReply(GObject* source, GAsyncResult* result,
                              gpointer user_data);

  void PushSection();
  void RequestSnapshotAndPush();
  void PushSnapshot(FlValue* snapshot);

  FlMethodChannel* host_channel_ = nullptr;  // towards the main engine

  GtkWidget* window_ = nullptr;
  FlView* view_ = nullptr;
  FlMethodChannel* settings_channel_ = nullptr;  // towards the settings engine

  bool engine_ready_ = false;
  std::string pending_section_;

  // Same sizes as the macOS window; the Dart layout tests cover them.
  static constexpr int kDefaultWidth = 720;
  static constexpr int kDefaultHeight = 520;
  static constexpr int kMinWidth = 620;
  static constexpr int kMinHeight = 420;
};

#endif  // RUNNER_SETTINGS_WINDOW_H_
