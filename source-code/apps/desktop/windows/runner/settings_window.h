#ifndef RUNNER_SETTINGS_WINDOW_H_
#define RUNNER_SETTINGS_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

#include "win32_window.h"

// Detached Settings window (native host).
//
// Hosts a *second* Flutter engine running the `settingsMain` Dart entrypoint
// in a real, independent top-level window. This mirrors the macOS
// `SettingsWindowController` (macos/Runner/SettingsWindow.swift): the main
// window is never resized, hidden or overlaid while Settings is open, and the
// two windows stay independently usable.
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
// The window is created lazily on first open and its engine is torn down when
// the user closes it, so a closed Settings window costs nothing.
class SettingsWindow : public Win32Window {
 public:
  // |owner| is the main application window (used to pick the monitor to open
  // on). |project| is the main engine's DartProject; it is copied and its
  // entrypoint overridden to `settingsMain`. |main_messenger| is the main
  // engine's messenger and must outlive this object.
  SettingsWindow(HWND owner, const flutter::DartProject& project,
                 flutter::BinaryMessenger* main_messenger);
  ~SettingsWindow() override;

  SettingsWindow(const SettingsWindow&) = delete;
  SettingsWindow& operator=(const SettingsWindow&) = delete;

  // Brings the Settings window to the front, creating it on first use.
  // |section| is the Dart-side pane id (`general`, `appearance`, `security`,
  // `advanced`, `about`); an empty string keeps the current pane.
  bool Open(const std::string& section);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Handles calls coming from the settings engine.
  void HandleSettingsCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Forwards |call| to the main engine and answers |result| with its reply,
  // echoing the fresh snapshot to the settings engine as well.
  void RelayToMainEngine(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Pushes the pending deep-link section to the settings engine, if any.
  void PushSection();

  // Pulls a fresh snapshot from the main engine and pushes it to the settings
  // engine (used when re-showing an already-open window).
  void RequestSnapshotAndPush();

  // Sends a `setSnapshot` call carrying |snapshot| (a JSON string).
  void PushSnapshot(const flutter::EncodableValue& snapshot);

  // Centres the window on the monitor that currently shows the main window.
  void CenterOnOwnerMonitor();

  // Restores, shows and focuses the window.
  void Reveal();

  HWND owner_ = nullptr;
  flutter::DartProject project_;

  // Channel towards the *main* engine, which owns the real providers.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      host_channel_;

  // Settings engine + its channel; reset whenever the window closes.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      settings_channel_;

  bool engine_ready_ = false;
  std::string pending_section_;

  // Default and minimum *client* sizes in logical pixels — the same values as
  // the macOS window, which the Dart layout tests cover.
  static constexpr int kDefaultWidth = 720;
  static constexpr int kDefaultHeight = 520;
  static constexpr int kMinWidth = 620;
  static constexpr int kMinHeight = 420;
};

#endif  // RUNNER_SETTINGS_WINDOW_H_
