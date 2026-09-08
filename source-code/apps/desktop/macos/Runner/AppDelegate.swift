import Cocoa
import FlutterMacOS

// NOTE: @main is intentionally absent — entry point is main.swift,
// which handles the single-instance guard before NSApplicationMain runs.
class AppDelegate: FlutterAppDelegate {
  private var extensionServerActivity: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    extensionServerActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .idleSystemSleepDisabled],
      reason: "Keep the LumenPass browser extension bridge responsive"
    )
    applyStartMinimizedIfLaunchedAtLogin(notification: notification)
  }

  override func applicationWillTerminate(_ notification: Notification) {
    if let activity = extensionServerActivity {
      ProcessInfo.processInfo.endActivity(activity)
      extensionServerActivity = nil
    }
    super.applicationWillTerminate(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    NSApp.unhide(nil)
    if let window = mainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
    } else {
      for window in sender.windows where window.canBecomeMain {
        window.makeKeyAndOrderFront(nil)
      }
    }
    sender.activate(ignoringOtherApps: true)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // MARK: - Menu actions

  @IBAction func checkForUpdates(_ sender: Any) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    let channel = FlutterMethodChannel(
      name: "lumenpass/window",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("checkForUpdate", arguments: nil)
  }

  @IBAction func openSettings(_ sender: Any) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    let channel = FlutterMethodChannel(
      name: "lumenpass/window",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("openSettings", arguments: nil)
  }

  // MARK: - Start minimized at login
  //
  // When the OS auto-launches LumenPass at sign-in, honor the "Start
  // minimized" preference by keeping windows hidden. Manual launches (user
  // double-clicking the dock / app) always show the UI.
  private func applyStartMinimizedIfLaunchedAtLogin(notification: Notification) {
    let launchIsDefault = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
    guard !launchIsDefault else { return }

    let shouldStartMinimized = UserDefaults.standard.bool(forKey: "general.startMinimized")
    guard shouldStartMinimized else { return }

    DispatchQueue.main.async {
      for window in NSApp.windows {
        window.orderOut(nil)
      }
      NSApp.hide(nil)
    }
  }
}
