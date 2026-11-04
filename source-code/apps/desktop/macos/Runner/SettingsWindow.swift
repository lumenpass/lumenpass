import Cocoa
import FlutterMacOS

/// ─────────────────────────────────────────────────────────────────────────
/// Detached Settings window (native host)
/// ─────────────────────────────────────────────────────────────────────────
///
/// Hosts a **second FlutterEngine** running the `settingsMain` Dart entrypoint
/// in a real, independent macOS window. The main window is never resized,
/// hidden or otherwise disturbed while it is open — the two windows are
/// siblings and stay independently usable.
///
/// The settings engine has its own Dart isolate, so it cannot read the main
/// engine's providers. This controller therefore acts as a relay between two
/// method channels that share the name `lumenpass/settings_host`:
///
///   settings engine ──requestSettings/applySetting──▶ native
///        native ──requestSettings/applySetting──▶ main engine
///        native ◀───── JSON snapshot ───────────── main engine
///   settings engine ◀──── setSnapshot(JSON) ────── native
///
/// The main engine is the single source of truth. See `SettingsHostBridge`
/// on the Dart side.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Default content size — close to the reference "Settings" window.
    private static let kDefaultSize = NSSize(width: 720, height: 520)

    private let mainEngineMessenger: FlutterBinaryMessenger
    private var window: NSWindow?
    private var engine: FlutterEngine?
    private var settingsChannel: FlutterMethodChannel?
    private var hostChannel: FlutterMethodChannel?
    private var engineReady = false
    private var pendingSnapshot: String?

    /// Section name requested by the last deep link; pushed to the settings
    /// engine once it reports `ready`.
    private var selectedSection: String?

    init(mainEngineMessenger: FlutterBinaryMessenger) {
        self.mainEngineMessenger = mainEngineMessenger
        super.init()
    }

    /// Brings the Settings window to the front, creating it on first use.
    ///
    /// `section` is the Dart-side section name (`general`, `appearance`,
    /// `security`, `advanced`, `about`); it is forwarded to the settings
    /// engine so deep links open the relevant pane.
    func show(section: String? = nil) {
        if let section {
            selectedSection = section
        }
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            if engineReady {
                pushSection()
                requestSnapshotAndPush()
            }
            return
        }
        bootEngineAndWindow()
    }

    // MARK: - Engine + window setup

    private func bootEngineAndWindow() {
        let engine = FlutterEngine(
            name: "settings_window",
            project: nil,
            allowHeadlessExecution: true
        )
        // Run the dedicated Dart entrypoint (see `settingsMain` in main.dart).
        engine.run(withEntrypoint: "settingsMain")
        RegisterGeneratedPlugins(registry: engine)

        let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

        // Channel back into this controller, originating from the settings UI.
        let settingsChannel = FlutterMethodChannel(
            name: "lumenpass/settings_host",
            binaryMessenger: engine.binaryMessenger
        )
        settingsChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(nil)
                return
            }
            switch call.method {
            case "ready":
                self.engineReady = true
                self.pushSection()
                if let snapshot = self.pendingSnapshot {
                    self.pendingSnapshot = nil
                    settingsChannel.invokeMethod("setSnapshot", arguments: snapshot)
                }
                result(nil)
            case "requestSettings", "applySetting":
                // Relay to the main engine, then echo the snapshot back.
                self.relay(call: call) { snapshot in
                    result(snapshot as? String)
                    if let snapshot = snapshot as? String {
                        settingsChannel.invokeMethod("setSnapshot", arguments: snapshot)
                    }
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        // Channel towards the *main* engine, which owns the real providers.
        let hostChannel = FlutterMethodChannel(
            name: "lumenpass/settings_host",
            binaryMessenger: mainEngineMessenger
        )

        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: SettingsWindowController.kDefaultSize
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        // The Flutter UI is the main window's light palette with a dark
        // 46 px title bar. Pin the native chrome to light so scrollbars,
        // focus rings and the background behind rounded corners match it
        // even when the system is in dark mode.
        window.appearance = NSAppearance(named: .aqua)
        window.contentViewController = controller
        // Assigning `contentViewController` resizes the window to the view
        // controller's intrinsic size (1×1 for a freshly booted Flutter view),
        // so the content size must be applied *after* it is attached.
        window.setContentSize(SettingsWindowController.kDefaultSize)
        window.minSize = NSSize(width: 620, height: 420)
        window.delegate = self
        window.backgroundColor = NSColor(
            calibratedRed: 227 / 255,
            green: 235 / 255,
            blue: 242 / 255,
            alpha: 1
        )
        window.center()

        self.engine = engine
        self.settingsChannel = settingsChannel
        self.hostChannel = hostChannel
        self.window = window

        NSLog("[SettingsWindow] window created frame=\(window.frame) visible=\(window.isVisible)")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSLog("[SettingsWindow] after orderFront visible=\(window.isVisible) windows=\(NSApp.windows.count)")
    }

    // MARK: - Relay

    /// Pushes the pending deep-link section to the settings engine, if any.
    private func pushSection() {
        guard let section = selectedSection, let settingsChannel else { return }
        selectedSection = nil
        settingsChannel.invokeMethod("setSection", arguments: section)
    }

    /// Forwards a call from the settings engine to the main engine.
    private func relay(call: FlutterMethodCall, completion: @escaping (Any?) -> Void) {
        guard let hostChannel else {
            completion(nil)
            return
        }
        hostChannel.invokeMethod(call.method, arguments: call.arguments) { response in
            if let error = response as? FlutterError {
                NSLog("[SettingsWindow] host error: \(error.message ?? "")")
                completion(nil)
                return
            }
            completion(response)
        }
    }

    /// Pulls a fresh snapshot from the main engine and pushes it to the
    /// settings engine (used when re-showing an already-open window).
    private func requestSnapshotAndPush() {
        hostChannel?.invokeMethod("requestSettings", arguments: nil) { [weak self] response in
            guard let self, let snapshot = response as? String else { return }
            self.settingsChannel?.invokeMethod("setSnapshot", arguments: snapshot)
        }
    }

    // MARK: - Teardown

    /// The Settings *window* is cached while the app runs, but the engine is
    /// released with it so a closed window costs nothing.
    func windowWillClose(_ notification: Notification) {
        teardownEngine()
        window = nil
    }

    private func teardownEngine() {
        engineReady = false
        pendingSnapshot = nil
        selectedSection = nil
        settingsChannel?.setMethodCallHandler(nil)
        window?.contentViewController = nil
        settingsChannel = nil
        hostChannel = nil
        engine?.shutDownEngine()
        engine = nil
    }
}
