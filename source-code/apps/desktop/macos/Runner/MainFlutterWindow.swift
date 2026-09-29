import Carbon.HIToolbox
import Cocoa
import FlutterMacOS
import ServiceManagement
import Vision

class MainFlutterWindow: NSWindow {
    private var windowChannel: FlutterMethodChannel?
    private var embedsWindowControls = false
    private var quickSearchHotKeyRef: EventHotKeyRef?
    private var lockVaultHotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?

    // ── Isolated Quick Search panel (Option A: second Flutter engine) ───────
    // The standalone Quick Search UI lives in its own borderless, non-
    // activating NSPanel backed by a *separate* FlutterEngine running the
    // `quickSearchMain` Dart entrypoint. This keeps the main application
    // window completely untouched when the hotkey is pressed — it is never
    // hidden, resized or restyled.
    private var quickSearchEngine: FlutterEngine?
    private var quickSearchChannel: FlutterMethodChannel?
    private var quickSearchViewController: FlutterViewController?
    private var quickSearchPanel: QuickSearchPanel?
    private var quickSearchPanelVisible = false
    private var quickSearchEngineReady = false
    private var pendingQuickSearchOpenGenerator: Bool?
    private var quickSearchIdleShutdown: DispatchWorkItem?
    private var quickSearchRequestGeneration = 0
    private static let quickSearchIdleTimeout: TimeInterval = 60

    // Legacy in-window transform state (no longer used on macOS now that the
    // panel is isolated, but retained as a defensive fallback).
    private var isInQuickSearchMode = false
    private var savedStyleMask: NSWindow.StyleMask?
    private var savedTitlebarAppearsTransparent = false
    private var savedTitleVisibility: NSWindow.TitleVisibility = .visible
    private var savedMovableByWindowBackground = false
    private var savedLevel: NSWindow.Level = .normal
    private var savedIsOpaque = true
    private var savedBackgroundColor: NSColor = .windowBackgroundColor
    private var savedHasShadow = true
    private var savedFrame: NSRect?
    private var savedMinSize: NSSize?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    deinit {
        quickSearchIdleShutdown?.cancel()
        NotificationCenter.default.removeObserver(self)
        if let ref = quickSearchHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = lockVaultHotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = hotKeyEventHandler { RemoveEventHandler(handler) }
    }

    override func resignKey() {
        super.resignKey()
        // When the standalone quick search window loses focus (user clicked
        // somewhere outside of it), ask Flutter to dismiss the overlay so the
        // window is restored to its normal state.
        if isInQuickSearchMode {
            DispatchQueue.main.async { [weak self] in
                self?.windowChannel?.invokeMethod(
                    "quickSearchDismissedByOutsideTap",
                    arguments: nil
                )
            }
        }
    }

    @objc private func repositionEmbeddedWindowControls() {
        guard embedsWindowControls, styleMask.contains(.fullSizeContentView) else {
            return
        }
        guard
            let closeButton = standardWindowButton(.closeButton),
            let minimizeButton = standardWindowButton(.miniaturizeButton),
            let zoomButton = standardWindowButton(.zoomButton),
            let buttonContainer = closeButton.superview,
            minimizeButton.superview === buttonContainer,
            zoomButton.superview === buttonContainer
        else {
            return
        }

        buttonContainer.layoutSubtreeIfNeeded()
        let buttons = [closeButton, minimizeButton, zoomButton]
        let currentMinX = buttons.map(\.frame.minX).min() ?? 0
        let targetMinXInWindow: CGFloat = 14
        let targetPointInContainer = buttonContainer.convert(
            NSPoint(x: targetMinXInWindow, y: 0),
            from: nil
        )
        let offsetX = targetPointInContainer.x - currentMinX

        for button in buttons {
            button.isHidden = false
            button.autoresizingMask = [.maxXMargin]
            button.setFrameOrigin(
                NSPoint(x: button.frame.origin.x + offsetX, y: button.frame.origin.y)
            )
        }
    }

    private func embedNativeWindowControls() {
        embedsWindowControls = true
        title = ""
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        styleMask.insert(.fullSizeContentView)
        isMovableByWindowBackground = true
        if #available(macOS 11.0, *) {
            titlebarSeparatorStyle = .none
        }
        DispatchQueue.main.async { [weak self] in
            self?.repositionEmbeddedWindowControls()
        }
    }

    private func restoreNativeTitleBar(title: String) {
        embedsWindowControls = false
        styleMask.remove(.fullSizeContentView)
        titlebarAppearsTransparent = false
        titleVisibility = .visible
        isMovableByWindowBackground = false
        self.title = title
        if #available(macOS 11.0, *) {
            titlebarSeparatorStyle = .automatic
        }
    }

    private func applyOpacity(_ opacity: CGFloat, toStatusButtonsIn view: NSView?) {
        guard let view = view else { return }
        // NSStatusBarButton is a subclass of NSButton; tray_manager uses it
        // as the clickable button inside the menu bar status item window.
        if view is NSStatusBarButton {
            view.alphaValue = opacity
            return
        }
        for sub in view.subviews {
            applyOpacity(opacity, toStatusButtonsIn: sub)
        }
    }

    private func activeScreen() -> NSScreen? {
        if let screen = self.screen {
            return screen
        }
        if let mouseScreen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func centerOnActiveScreen() {
        guard let screen = activeScreen() else {
            self.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowSize = self.frame.size
        let origin = NSPoint(
            x: visibleFrame.origin.x + (visibleFrame.width - windowSize.width) / 2,
            y: visibleFrame.origin.y + (visibleFrame.height - windowSize.height) / 2
        )
        self.setFrameOrigin(origin)
    }

    private func showQuickSearchWindow() {
        NSApp.activate(ignoringOtherApps: true)
        self.centerOnActiveScreen()
        self.makeKeyAndOrderFront(nil)
    }

    // MARK: - Isolated Quick Search panel

    private static let kQuickSearchDefaultWidth: CGFloat = 640
    private static let kQuickSearchDefaultHeight: CGFloat = 178

    /// Boots the second engine only when Quick Search is first requested.
    private func setupQuickSearchEngine() {
        guard quickSearchEngine == nil else { return }

        let engine = FlutterEngine(
            name: "quick_search",
            project: nil,
            allowHeadlessExecution: true
        )
        // Run the dedicated Dart entrypoint (see `quickSearchMain` in main.dart).
        engine.run(withEntrypoint: "quickSearchMain")
        RegisterGeneratedPlugins(registry: engine)

        let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)

        let channel = FlutterMethodChannel(
            name: "lumenpass/quick_search",
            binaryMessenger: engine.binaryMessenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(nil)
                return
            }
            switch call.method {
            case "ready":
                self.quickSearchEngineReady = true
                if let openGenerator = self.pendingQuickSearchOpenGenerator {
                    self.requestQuickSearchSnapshot(openGenerator: openGenerator)
                }
                result(nil)
            case "close":
                DispatchQueue.main.async { self.hideQuickSearchPanel() }
                result(nil)
            case "openEntry":
                DispatchQueue.main.async {
                    self.hideQuickSearchPanel()
                    self.windowChannel?.invokeMethod(
                        "quickSearchOpenEntry", arguments: call.arguments)
                }
                result(nil)
            case "editEntry":
                DispatchQueue.main.async {
                    self.hideQuickSearchPanel()
                    self.windowChannel?.invokeMethod(
                        "quickSearchEditEntry", arguments: call.arguments)
                }
                result(nil)
            case "createItem":
                DispatchQueue.main.async {
                    self.hideQuickSearchPanel()
                    self.windowChannel?.invokeMethod("quickSearchCreateItem", arguments: nil)
                }
                result(nil)
            case "heightChanged":
                let args = call.arguments as? [String: Any]
                let height =
                    args?["height"] as? Double
                    ?? Double(MainFlutterWindow.kQuickSearchDefaultHeight)
                DispatchQueue.main.async { self.setQuickSearchPanelHeight(CGFloat(height)) }
                result(nil)
            case "getEntry":
                guard let uuid = call.arguments as? String,
                      let windowChannel = self.windowChannel else {
                    result(nil)
                    return
                }
                windowChannel.invokeMethod(
                    "quickSearchRequestEntry", arguments: uuid
                ) { entry in
                    result(entry as? String)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let panel = QuickSearchPanel(
            contentRect: NSRect(
                x: 0, y: 0,
                width: MainFlutterWindow.kQuickSearchDefaultWidth,
                height: MainFlutterWindow.kQuickSearchDefaultHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentViewController = controller
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 8
        panel.contentView?.layer?.masksToBounds = true
        // Dismiss when the user clicks/taps outside the panel.
        panel.onResignKey = { [weak self] in
            self?.hideQuickSearchPanel()
        }

        self.quickSearchEngine = engine
        self.quickSearchChannel = channel
        self.quickSearchViewController = controller
        self.quickSearchPanel = panel
    }

    private func centerQuickSearchPanel() {
        guard let panel = quickSearchPanel, let screen = quickSearchTargetScreen()
        else { return }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        // Position a little above vertical centre — matches typical spotlight UX.
        let origin = NSPoint(
            x: visibleFrame.origin.x + (visibleFrame.width - size.width) / 2,
            y: visibleFrame.origin.y + (visibleFrame.height - size.height) * 0.62
        )
        panel.setFrameOrigin(origin)
    }

    /// The monitor the Quick Search panel should appear on. Unlike
    /// `activeScreen()` (which favours the *main window's* screen), a
    /// spotlight-style launcher should follow the user, so we anchor to the
    /// screen currently containing the mouse cursor. Falls back to the key
    /// window's screen, then the primary screen.
    private func quickSearchTargetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) {
            return mouseScreen
        }
        return NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func setQuickSearchPanelHeight(_ height: CGFloat) {
        guard let panel = quickSearchPanel else { return }
        let clamped = max(80, height)
        let width = panel.frame.width
        panel.setContentSize(NSSize(width: width, height: clamped))
        if quickSearchPanelVisible {
            centerQuickSearchPanel()
        }
    }

    private func showQuickSearchPanel(openGenerator: Bool) {
        quickSearchIdleShutdown?.cancel()
        quickSearchIdleShutdown = nil
        pendingQuickSearchOpenGenerator = openGenerator
        setupQuickSearchEngine()
        if quickSearchEngineReady {
            requestQuickSearchSnapshot(openGenerator: openGenerator)
        }
    }

    private func requestQuickSearchSnapshot(openGenerator: Bool) {
        guard let panel = quickSearchPanel, let channel = quickSearchChannel else {
            return
        }
        quickSearchRequestGeneration += 1
        let requestGeneration = quickSearchRequestGeneration
        // Pull a fresh snapshot from the main engine, then reveal the panel.
        windowChannel?.invokeMethod(
            "quickSearchRequestSnapshot",
            arguments: ["openGenerator": openGenerator]
        ) { [weak self] snapshot in
            guard let self = self else { return }
            guard requestGeneration == self.quickSearchRequestGeneration else { return }
            if let json = snapshot as? String {
                channel.invokeMethod("setSnapshot", arguments: json)
            } else {
                self.shutDownQuickSearchEngine()
                return
            }
            DispatchQueue.main.async {
                guard requestGeneration == self.quickSearchRequestGeneration else { return }
                if let baseWidth = self.frameWidthForPanel() {
                    let target = max(560, min(floor(baseWidth * 0.70), 900))
                    panel.setContentSize(
                        NSSize(width: target, height: panel.frame.height)
                    )
                }
                self.centerQuickSearchPanel()
                // A .nonactivatingPanel can become key and take keyboard input
                // without activating the app — so we deliberately do NOT call
                // NSApp.activate here. That keeps the main window (and any
                // other frontmost app) completely undisturbed.
                panel.makeKeyAndOrderFront(nil)
                self.quickSearchPanelVisible = true
                self.pendingQuickSearchOpenGenerator = nil
            }
        }
    }

    private func frameWidthForPanel() -> CGFloat? {
        // Base the panel width on the main window's width for visual consistency.
        return self.frame.width > 0 ? self.frame.width : nil
    }

    private func hideQuickSearchPanel() {
        guard quickSearchPanelVisible || pendingQuickSearchOpenGenerator != nil else {
            return
        }
        quickSearchRequestGeneration += 1
        pendingQuickSearchOpenGenerator = nil
        guard let panel = quickSearchPanel else { return }
        let wasVisible = quickSearchPanelVisible
        quickSearchPanelVisible = false
        panel.orderOut(nil)
        quickSearchChannel?.invokeMethod("clearSnapshot", arguments: nil)
        if wasVisible {
            windowChannel?.invokeMethod("quickSearchPanelClosed", arguments: nil)
        }
        scheduleQuickSearchShutdown()
    }

    private func scheduleQuickSearchShutdown() {
        quickSearchIdleShutdown?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, !self.quickSearchPanelVisible else { return }
            self.shutDownQuickSearchEngine()
        }
        quickSearchIdleShutdown = task
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MainFlutterWindow.quickSearchIdleTimeout,
            execute: task
        )
    }

    private func shutDownQuickSearchEngine() {
        quickSearchIdleShutdown?.cancel()
        quickSearchIdleShutdown = nil
        quickSearchRequestGeneration += 1
        pendingQuickSearchOpenGenerator = nil
        quickSearchEngineReady = false
        quickSearchPanelVisible = false
        quickSearchPanel?.orderOut(nil)
        quickSearchChannel?.setMethodCallHandler(nil)
        quickSearchPanel?.contentViewController = nil
        quickSearchViewController = nil
        quickSearchPanel?.close()
        quickSearchPanel = nil
        quickSearchChannel = nil
        quickSearchEngine?.shutDownEngine()
        quickSearchEngine = nil
    }

    private func toggleQuickSearchPanel() {
        if quickSearchPanelVisible || pendingQuickSearchOpenGenerator != nil {
            hideQuickSearchPanel()
        } else {
            showQuickSearchPanel(openGenerator: false)
        }
    }

    private func resolvedQuickSearchWidth(_ requestedWidth: Double) -> Double {
        if requestedWidth > 0 {
            return requestedWidth
        }
        // Default to 70% of the app window width so quick search stays compact.
        let baseWidth = self.savedFrame?.width ?? self.frame.width
        let compactWidth = floor(baseWidth * 0.70)
        return max(560, min(compactWidth, 900))
    }

    private func enterQuickSearchMode(width: Double, height: Double) {
        DispatchQueue.main.async {
            if !self.isInQuickSearchMode {
                self.savedStyleMask = self.styleMask
                self.savedTitlebarAppearsTransparent = self.titlebarAppearsTransparent
                self.savedTitleVisibility = self.titleVisibility
                self.savedMovableByWindowBackground = self.isMovableByWindowBackground
                self.savedLevel = self.level
                self.savedIsOpaque = self.isOpaque
                self.savedBackgroundColor = self.backgroundColor
                self.savedHasShadow = self.hasShadow
                self.savedFrame = self.frame
                self.savedMinSize = self.minSize
                // Hide the window before transforming so the main app never flashes
                if self.isVisible {
                    self.orderOut(nil)
                }
            }

            self.styleMask = [.borderless, .fullSizeContentView]
            self.titlebarAppearsTransparent = true
            self.titleVisibility = .hidden
            self.isMovableByWindowBackground = true
            self.level = .floating
            self.isOpaque = false
            self.backgroundColor = .clear
            self.hasShadow = true
            self.collectionBehavior.insert(.moveToActiveSpace)
            self.contentView?.wantsLayer = true
            self.contentView?.layer?.cornerRadius = 8
            self.contentView?.layer?.masksToBounds = true
            self.setFrameAutosaveName("")
            let targetWidth = self.resolvedQuickSearchWidth(width)
            self.minSize = NSSize(width: targetWidth, height: height)
            self.setContentSize(NSSize(width: targetWidth, height: height))
            self.centerOnActiveScreen()
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
            self.isInQuickSearchMode = true
        }
    }

    private func exitQuickSearchMode() {
        DispatchQueue.main.async {
            guard self.isInQuickSearchMode else {
                return
            }
            if let savedStyleMask = self.savedStyleMask {
                self.styleMask = savedStyleMask
            }
            self.titlebarAppearsTransparent = self.savedTitlebarAppearsTransparent
            self.titleVisibility = self.savedTitleVisibility
            self.isMovableByWindowBackground = self.savedMovableByWindowBackground
            self.level = self.savedLevel
            self.isOpaque = self.savedIsOpaque
            self.backgroundColor = self.savedBackgroundColor
            self.hasShadow = self.savedHasShadow
            self.contentView?.layer?.cornerRadius = 0
            self.contentView?.layer?.masksToBounds = false
            if let savedMinSize = self.savedMinSize {
                self.minSize = savedMinSize
            }
            if let savedFrame = self.savedFrame {
                self.setFrame(savedFrame, display: true)
            }
            self.isInQuickSearchMode = false
        }
    }

    private func setQuickSearchSize(width: Double, height: Double) {
        DispatchQueue.main.async {
            guard self.isInQuickSearchMode else {
                return
            }
            let targetWidth = self.resolvedQuickSearchWidth(width)
            self.minSize = NSSize(width: targetWidth, height: height)
            self.setContentSize(NSSize(width: targetWidth, height: height))
            self.centerOnActiveScreen()
        }
    }

    private func handleHotKey(id: UInt32) {
        switch id {
        case 1:
            // Toggle the isolated Quick Search panel directly in native so the
            // hotkey works even when the main window isn't key. The panel pulls a
            // fresh vault snapshot from the main engine on open.
            DispatchQueue.main.async {
                self.toggleQuickSearchPanel()
            }
        case 2:
            DispatchQueue.main.async {
                self.windowChannel?.invokeMethod("lockVaultHotkeyPressed", arguments: nil)
            }
        default:
            break
        }
    }

    private func installHotKeyEventHandler() {
        guard hotKeyEventHandler == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                let window = Unmanaged<MainFlutterWindow>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                window.handleHotKey(id: hotKeyID.id)
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &hotKeyEventHandler
        )
    }

    private func updateQuickSearchHotKey(keyCode: UInt32, modifiers: UInt32) {
        if let ref = quickSearchHotKeyRef {
            UnregisterEventHotKey(ref)
            quickSearchHotKeyRef = nil
        }
        installHotKeyEventHandler()
        let id = EventHotKeyID(signature: OSType(0x4C50_4B48), id: 1)  // "LPKH"
        RegisterEventHotKey(
            keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &quickSearchHotKeyRef)
    }

    private func clearQuickSearchHotKey() {
        if let ref = quickSearchHotKeyRef {
            UnregisterEventHotKey(ref)
            quickSearchHotKeyRef = nil
        }
    }

    private func updateLockVaultHotKey(keyCode: UInt32, modifiers: UInt32) {
        if let ref = lockVaultHotKeyRef {
            UnregisterEventHotKey(ref)
            lockVaultHotKeyRef = nil
        }
        installHotKeyEventHandler()
        let id = EventHotKeyID(signature: OSType(0x4C50_4B48), id: 2)  // "LPKH"
        RegisterEventHotKey(
            keyCode, modifiers, id, GetEventDispatcherTarget(), 0, &lockVaultHotKeyRef)
    }

    private func clearLockVaultHotKey() {
        if let ref = lockVaultHotKeyRef {
            UnregisterEventHotKey(ref)
            lockVaultHotKeyRef = nil
        }
    }

    private func registerQuickSearchHotKey() {
        updateQuickSearchHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey) | UInt32(shiftKey)
        )
    }

    private func detectQRInImage(_ cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.compactMap { ($0 as? VNBarcodeObservation)?.payloadStringValue }
            .first
    }
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        self.contentViewController = flutterViewController

        // Render Flutter edge-to-edge from first paint while preserving the
        // native macOS traffic-light controls inside the application surface.
        self.embedNativeWindowControls()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionEmbeddedWindowControls),
            name: NSWindow.didResizeNotification,
            object: self
        )

        let channel = FlutterMethodChannel(
            name: "lumenpass/window",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        self.windowChannel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "setSize":
                if let args = call.arguments as? [String: Any],
                    let w = args["width"] as? Double,
                    let h = args["height"] as? Double
                {
                    DispatchQueue.main.async {
                        let requestedWidth = CGFloat(w)
                        let requestedHeight = CGFloat(h)
                        let visibleFrame = self.screen?.visibleFrame
                            ?? NSScreen.main?.visibleFrame
                        let maxWidth = max(
                            (visibleFrame?.width ?? requestedWidth) - 24, 480)
                        let maxHeight = max(
                            (visibleFrame?.height ?? requestedHeight) - 24, 320)
                        let targetWidth = min(requestedWidth, maxWidth)
                        let targetHeight = min(requestedHeight, maxHeight)
                        self.setFrameAutosaveName("")
                        self.setContentSize(
                            NSSize(width: targetWidth, height: targetHeight))
                        self.minSize = NSSize(
                            width: min(max(requestedWidth - 60, 480), targetWidth),
                            height: min(max(requestedHeight - 60, 320), targetHeight))
                        self.centerOnActiveScreen()
                        self.repositionEmbeddedWindowControls()
                    }
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                }
            case "showNativeTitleBar":
                let title =
                    (call.arguments as? [String: Any])?["title"] as? String
                    ?? "LumenPass - Password Manager"
                DispatchQueue.main.async {
                    self.restoreNativeTitleBar(title: title)
                }
                result(nil)
            case "hideNativeTitleBar":
                DispatchQueue.main.async {
                    self.embedNativeWindowControls()
                }
                result(nil)
            case "scanScreen":
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else {
                        DispatchQueue.main.async { result(nil) }
                        return
                    }
                    let displayID = CGMainDisplayID()
                    guard let cgImage = CGDisplayCreateImage(displayID) else {
                        DispatchQueue.main.async {
                            result(
                                FlutterError(
                                    code: "CAPTURE_FAILED", message: "Could not capture screen",
                                    details: nil))
                        }
                        return
                    }
                    let qrResult = self.detectQRInImage(cgImage)
                    DispatchQueue.main.async { result(qrResult) }
                }

            case "decodeQRFromFile":
                guard let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else {
                        DispatchQueue.main.async { result(nil) }
                        return
                    }
                    guard let nsImage = NSImage(contentsOfFile: path),
                        let tiff = nsImage.tiffRepresentation,
                        let bitmapRep = NSBitmapImageRep(data: tiff),
                        let cgImage = bitmapRep.cgImage
                    else {
                        DispatchQueue.main.async { result(nil) }
                        return
                    }
                    let qrResult = self.detectQRInImage(cgImage)
                    DispatchQueue.main.async { result(qrResult) }
                }

            // ── Security-scoped file picker (returns path + bookmark) ──────────────
            case "pickFileWithBookmark":
                DispatchQueue.main.async {
                    let panel = NSOpenPanel()
                    panel.title = "Open KeePass Database"
                    panel.allowsMultipleSelection = false
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else {
                            result(nil)
                            return
                        }
                        url.startAccessingSecurityScopedResource()
                        do {
                            let data = try url.bookmarkData(
                                options: [.withSecurityScope],
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil
                            )
                            result(["path": url.path, "bookmark": data.base64EncodedString()])
                        } catch {
                            result(["path": url.path, "bookmark": ""])
                        }
                    }
                }

            // ── Security-scoped directory picker (returns path + bookmark) ─────────
            case "pickDirectoryWithBookmark":
                DispatchQueue.main.async {
                    let panel = NSOpenPanel()
                    panel.title = "Choose save location"
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.begin { response in
                        guard response == .OK, let url = panel.url else {
                            result(nil)
                            return
                        }
                        url.startAccessingSecurityScopedResource()
                        do {
                            let data = try url.bookmarkData(
                                options: [.withSecurityScope],
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil
                            )
                            result(["path": url.path, "bookmark": data.base64EncodedString()])
                        } catch {
                            result(["path": url.path, "bookmark": ""])
                        }
                    }
                }

            // ── Create bookmark for an already-accessible path ─────────────────────
            case "createBookmarkForPath":
                guard let path = call.arguments as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                let url = URL(fileURLWithPath: path)
                do {
                    let data = try url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    result(data.base64EncodedString())
                } catch {
                    result(
                        FlutterError(
                            code: "BOOKMARK_ERROR", message: error.localizedDescription,
                            details: nil))
                }

            // ── Resolve a stored bookmark and start security-scoped access ─────────
            case "resolveBookmark":
                guard let base64 = call.arguments as? String,
                    let data = Data(base64Encoded: base64)
                else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                do {
                    var isStale = false
                    let url = try URL(
                        resolvingBookmarkData: data,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    url.startAccessingSecurityScopedResource()
                    result(url.path)
                } catch {
                    result(
                        FlutterError(
                            code: "BOOKMARK_ERROR", message: error.localizedDescription,
                            details: nil))
                }

            // ── Stop security-scoped access for a path ─────────────────────────────
            case "stopAccessingBookmark":
                if let path = call.arguments as? String {
                    URL(fileURLWithPath: path).stopAccessingSecurityScopedResource()
                }
                result(nil)

            case "bringToFront":
                DispatchQueue.main.async {
                    // Order the window front first (instant window-server op),
                    // then activate. Doing it in this order avoids the
                    // perceptible delay from waiting on the throttled
                    // `activate(ignoringOtherApps:)` before the window becomes
                    // visible, and un-occludes the Flutter view so its render
                    // loop resumes immediately rather than after activation.
                    NSApp.unhide(nil)
                    self.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                result(nil)

            case "setTrayIconOpacity":
                let opacity = call.arguments as? Double ?? 1.0
                DispatchQueue.main.async {
                    // Walk all NSWindow instances and find NSStatusBarButton views,
                    // which tray_manager attaches to a borderless status-bar window.
                    for window in NSApp.windows {
                        self.applyOpacity(CGFloat(opacity), toStatusButtonsIn: window.contentView)
                    }
                }
                result(nil)

            case "setHideDockIcon":
                if let hide = call.arguments as? Bool {
                    DispatchQueue.main.async {
                        if hide {
                            NSApp.setActivationPolicy(.accessory)
                        } else {
                            NSApp.setActivationPolicy(.regular)
                        }
                    }
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                }

            case "setAutostart":
                guard let enabled = call.arguments as? Bool else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    break
                }
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                    result(nil)
                } catch {
                    result(
                        FlutterError(
                            code: "AUTOSTART_FAILED",
                            message: error.localizedDescription,
                            details: nil
                        ))
                }

            case "getAutostart":
                result(LaunchAtLogin.isEnabled())

            case "setStartMinimized":
                if let enabled = call.arguments as? Bool {
                    UserDefaults.standard.set(enabled, forKey: "general.startMinimized")
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                }

            case "showQuickSearchWindow":
                DispatchQueue.main.async {
                    self.showQuickSearchWindow()
                }
                result(nil)

            case "showQuickSearchPanel":
                let args = call.arguments as? [String: Any]
                let openGenerator = args?["openGenerator"] as? Bool ?? false
                DispatchQueue.main.async {
                    self.showQuickSearchPanel(openGenerator: openGenerator)
                }
                result(nil)

            case "hideQuickSearchPanel":
                DispatchQueue.main.async {
                    self.hideQuickSearchPanel()
                }
                result(nil)

            case "clearQuickSearchData":
                DispatchQueue.main.async {
                    self.hideQuickSearchPanel()
                    self.shutDownQuickSearchEngine()
                    result(nil)
                }

            case "enterQuickSearchMode":
                let args = call.arguments as? [String: Any]
                let width = args?["width"] as? Double ?? 0
                let height = args?["height"] as? Double ?? 180
                self.enterQuickSearchMode(width: width, height: height)
                result(nil)

            case "exitQuickSearchMode":
                self.exitQuickSearchMode()
                result(nil)

            case "setQuickSearchSize":
                let args = call.arguments as? [String: Any]
                let width = args?["width"] as? Double ?? 0
                let height = args?["height"] as? Double ?? 180
                self.setQuickSearchSize(width: width, height: height)
                result(nil)

            case "hideWindow":
                DispatchQueue.main.async {
                    self.exitQuickSearchMode()
                    self.orderOut(nil)
                    NSApp.hide(nil)
                }
                result(nil)

            case "showSshApprovalWindow":
                let args = call.arguments as? [String: Any]
                let keyName = args?["keyName"] as? String ?? "Unknown Key"
                let requesterName = args?["requesterName"] as? String ?? "Requesting Process"
                let requesterExecutablePath = args?["requesterExecutablePath"] as? String
                let requesterPid = (args?["requesterPid"] as? NSNumber)?.int32Value
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    var requesterIcon: NSImage?
                    if let pid = requesterPid,
                        let app = NSRunningApplication(processIdentifier: pid_t(pid)),
                        let appIcon = app.icon
                    {
                        requesterIcon = appIcon
                    } else if let executablePath = requesterExecutablePath, !executablePath.isEmpty
                    {
                        requesterIcon = NSWorkspace.shared.icon(forFile: executablePath)
                    }

                    let approval = SshApprovalPanelController(
                        keyName: keyName,
                        requesterName: requesterName,
                        requesterIcon: requesterIcon
                    )
                    result(approval.runModal())
                }

            case "quit":
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
                result(nil)

            case "updateQuickSearchHotKey":
                if let args = call.arguments as? [String: Any],
                    let keyCode = args["keyCode"] as? Int,
                    let modifiers = args["modifiers"] as? Int
                {
                    self.updateQuickSearchHotKey(
                        keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
                }
                result(nil)

            case "clearQuickSearchHotKey":
                self.clearQuickSearchHotKey()
                result(nil)

            case "updateLockVaultHotKey":
                if let args = call.arguments as? [String: Any],
                    let keyCode = args["keyCode"] as? Int,
                    let modifiers = args["modifiers"] as? Int
                {
                    self.updateLockVaultHotKey(
                        keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
                }
                result(nil)

            case "clearLockVaultHotKey":
                self.clearLockVaultHotKey()
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // ── SSH Agent channel ──────────────────────────────────────────────────
        let sshChannel = FlutterMethodChannel(
            name: "lumenpass/ssh_agent",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        SshAgentServer.shared.channel = sshChannel
        sshChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "startAgent":
                let rawKeys =
                    (call.arguments as? [String: Any])?["keys"] as? [[String: String]] ?? []
                SshAgentServer.shared.setKeys(rawKeys)
                if let path = SshAgentServer.shared.start() {
                    NSLog("[SshAgent] channel startAgent → success, path=\(path)")
                    result(path)
                } else {
                    NSLog("[SshAgent] channel startAgent → FAILED")
                    result(
                        FlutterError(
                            code: "START_FAILED", message: "Could not start SSH agent socket",
                            details: nil))
                }
            case "stopAgent":
                SshAgentServer.shared.clearKeys()
                SshAgentServer.shared.stop()
                result(nil)
            case "setKeys":
                let rawKeys =
                    (call.arguments as? [String: Any])?["keys"] as? [[String: String]] ?? []
                SshAgentServer.shared.setKeys(rawKeys)
                result(nil)
            case "signResponse":
                guard let args = call.arguments as? [String: Any],
                    let requestId = args["requestId"] as? Int,
                    let approved = args["approved"] as? Bool
                else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                    return
                }
                SshAgentServer.shared.respond(requestId: requestId, approved: approved)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        RegisterGeneratedPlugins(registry: flutterViewController)

        super.awakeFromNib()
        registerQuickSearchHotKey()

        // Override any autosaved frame — compact size for unlock screen
        self.setFrameAutosaveName("")
        self.setContentSize(NSSize(width: 820, height: 380))
        self.minSize = NSSize(width: 720, height: 340)
        self.centerOnActiveScreen()
    }
}

private final class QuickSearchPanel: NSPanel {
    /// Invoked when the panel loses key focus (click/tap outside), used to
    /// dismiss the isolated Quick Search UI — mirrors the old `resignKey`
    /// outside-tap dismissal, but scoped to *this* panel so the main window is
    /// never involved.
    var onResignKey: (() -> Void)?

    // Borderless panels don't become key by default; opt in so the search
    // field is focusable and typing works immediately.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) {
        // Esc closes the panel.
        onResignKey?()
    }
}

private final class SshApprovalPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SshApprovalPanelController: NSObject {
    private let keyName: String
    private let requesterName: String
    private let requesterIcon: NSImage?
    private var approved = false
    private let panel: SshApprovalPanel

    init(
        keyName: String,
        requesterName: String,
        requesterIcon: NSImage?
    ) {
        self.keyName = keyName
        self.requesterName = requesterName
        self.requesterIcon = requesterIcon

        panel = SshApprovalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 396, height: 430),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = buildContentView()
    }

    func runModal() -> Bool {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        return approved
    }

    @objc private func allowTapped() {
        finish(approved: true)
    }

    @objc private func denyTapped() {
        finish(approved: false)
    }

    private func finish(approved: Bool) {
        self.approved = approved
        NSApp.stopModal()
        panel.orderOut(nil)
        panel.close()
    }

    private func buildContentView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 396, height: 430))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
        card.layer?.cornerRadius = 24

        root.addSubview(card)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            card.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])

        let title = NSTextField(labelWithString: "LumenPass Access Requested")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        title.alignment = .center
        title.textColor = NSColor(calibratedWhite: 0.11, alpha: 1.0)

        let subtitle = NSTextField(
            labelWithString: "Allow \(requesterName) to use SSH key"
        )
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitle.alignment = .center
        subtitle.textColor = NSColor(calibratedWhite: 0.24, alpha: 1.0)
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2

        let iconRow = buildIconRow()
        iconRow.translatesAutoresizingMaskIntoConstraints = false

        let keyCard = buildKeyCard()
        keyCard.translatesAutoresizingMaskIntoConstraints = false

        let denyButton = NSButton(title: "Deny", target: self, action: #selector(denyTapped))
        denyButton.translatesAutoresizingMaskIntoConstraints = false
        styleButton(
            denyButton,
            background: NSColor.systemRed,
            foreground: .white,
            iconSystemName: "xmark.circle.fill",
            iconColor: .white
        )

        let allowButton = NSButton(title: "Allow", target: self, action: #selector(allowTapped))
        allowButton.translatesAutoresizingMaskIntoConstraints = false
        styleButton(
            allowButton,
            background: NSColor(
                calibratedRed: 10.0 / 255.0,
                green: 59.0 / 255.0,
                blue: 72.0 / 255.0,
                alpha: 1.0
            ),
            foreground: .white,
            iconSystemName: "checkmark.circle.fill",
            iconColor: .white
        )

        let buttonRow = NSStackView(views: [denyButton, allowButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 12

        card.addSubview(title)
        card.addSubview(iconRow)
        card.addSubview(subtitle)
        card.addSubview(keyCard)
        card.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),

            iconRow.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            iconRow.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconRow.heightAnchor.constraint(equalToConstant: 52),
            iconRow.widthAnchor.constraint(equalToConstant: 176),

            subtitle.topAnchor.constraint(equalTo: iconRow.bottomAnchor, constant: 18),
            subtitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            subtitle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),

            keyCard.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            keyCard.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            keyCard.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            keyCard.heightAnchor.constraint(equalToConstant: 82),

            buttonRow.topAnchor.constraint(equalTo: keyCard.bottomAnchor, constant: 22),
            buttonRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            buttonRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            buttonRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
            buttonRow.heightAnchor.constraint(equalToConstant: 46),

            denyButton.heightAnchor.constraint(equalToConstant: 46),
            allowButton.heightAnchor.constraint(equalToConstant: 46),
        ])

        return root
    }

    private func buildIconRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let requester = NSView()
        requester.translatesAutoresizingMaskIntoConstraints = false
        requester.wantsLayer = true
        requester.layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        requester.layer?.cornerRadius = 14

        let requesterImage = NSImageView()
        requesterImage.translatesAutoresizingMaskIntoConstraints = false
        requesterImage.imageScaling = .scaleProportionallyUpOrDown
        requesterImage.image = requesterIcon ?? NSImage(named: NSImage.applicationIconName)
        requesterImage.contentTintColor = .white
        requester.addSubview(requesterImage)

        let leftLine = NSView()
        leftLine.translatesAutoresizingMaskIntoConstraints = false
        leftLine.wantsLayer = true
        leftLine.layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1).cgColor

        let check = NSView()
        check.translatesAutoresizingMaskIntoConstraints = false
        check.wantsLayer = true
        check.layer?.backgroundColor =
            NSColor(calibratedRed: 0.2, green: 0.78, blue: 0.35, alpha: 1).cgColor
        check.layer?.cornerRadius = 10
        if #available(macOS 11.0, *) {
            let checkImage = NSImageView()
            checkImage.translatesAutoresizingMaskIntoConstraints = false
            checkImage.imageScaling = .scaleProportionallyUpOrDown
            checkImage.image = NSImage(
                systemSymbolName: "checkmark",
                accessibilityDescription: "Approved flow"
            )
            checkImage.contentTintColor = .white
            check.addSubview(checkImage)
            NSLayoutConstraint.activate([
                checkImage.centerXAnchor.constraint(equalTo: check.centerXAnchor),
                checkImage.centerYAnchor.constraint(equalTo: check.centerYAnchor),
                checkImage.widthAnchor.constraint(equalToConstant: 12),
                checkImage.heightAnchor.constraint(equalToConstant: 12),
            ])
        }

        let rightLine = NSView()
        rightLine.translatesAutoresizingMaskIntoConstraints = false
        rightLine.wantsLayer = true
        rightLine.layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1).cgColor

        let shield = NSView()
        shield.translatesAutoresizingMaskIntoConstraints = false
        shield.wantsLayer = true
        shield.layer?.backgroundColor =
            NSColor(calibratedRed: 0.15, green: 0.39, blue: 0.92, alpha: 1).cgColor
        shield.layer?.cornerRadius = 14
        if #available(macOS 11.0, *) {
            let shieldImage = NSImageView()
            shieldImage.translatesAutoresizingMaskIntoConstraints = false
            shieldImage.imageScaling = .scaleProportionallyUpOrDown
            shieldImage.image = NSImage(
                systemSymbolName: "shield.fill",
                accessibilityDescription: "LumenPass"
            )
            shieldImage.contentTintColor = .white
            shield.addSubview(shieldImage)
            NSLayoutConstraint.activate([
                shieldImage.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
                shieldImage.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
                shieldImage.widthAnchor.constraint(equalToConstant: 26),
                shieldImage.heightAnchor.constraint(equalToConstant: 26),
            ])
        }

        row.addSubview(requester)
        row.addSubview(leftLine)
        row.addSubview(check)
        row.addSubview(rightLine)
        row.addSubview(shield)

        NSLayoutConstraint.activate([
            requester.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            requester.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            requester.widthAnchor.constraint(equalToConstant: 52),
            requester.heightAnchor.constraint(equalToConstant: 52),

            requesterImage.centerXAnchor.constraint(equalTo: requester.centerXAnchor),
            requesterImage.centerYAnchor.constraint(equalTo: requester.centerYAnchor),
            requesterImage.widthAnchor.constraint(equalToConstant: 28),
            requesterImage.heightAnchor.constraint(equalToConstant: 28),

            leftLine.leadingAnchor.constraint(equalTo: requester.trailingAnchor, constant: 10),
            leftLine.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            leftLine.widthAnchor.constraint(equalToConstant: 16),
            leftLine.heightAnchor.constraint(equalToConstant: 1.5),

            check.leadingAnchor.constraint(equalTo: leftLine.trailingAnchor),
            check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 20),
            check.heightAnchor.constraint(equalToConstant: 20),

            rightLine.leadingAnchor.constraint(equalTo: check.trailingAnchor),
            rightLine.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            rightLine.widthAnchor.constraint(equalToConstant: 16),
            rightLine.heightAnchor.constraint(equalToConstant: 1.5),

            shield.leadingAnchor.constraint(equalTo: rightLine.trailingAnchor, constant: 10),
            shield.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            shield.widthAnchor.constraint(equalToConstant: 52),
            shield.heightAnchor.constraint(equalToConstant: 52),
            shield.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])

        return row
    }

    private func buildKeyCard() -> NSView {
        let keyCard = NSView()
        keyCard.wantsLayer = true
        keyCard.layer?.backgroundColor = NSColor.white.cgColor
        keyCard.layer?.cornerRadius = 14

        let keyIconContainer = NSView()
        keyIconContainer.translatesAutoresizingMaskIntoConstraints = false
        keyIconContainer.wantsLayer = true
        keyIconContainer.layer?.backgroundColor =
            NSColor(
                calibratedRed: 0.94,
                green: 0.97,
                blue: 1.0,
                alpha: 1.0
            ).cgColor
        keyIconContainer.layer?.cornerRadius = 10

        if #available(macOS 11.0, *) {
            let keyIcon = NSImageView()
            keyIcon.translatesAutoresizingMaskIntoConstraints = false
            keyIcon.imageScaling = .scaleProportionallyUpOrDown
            keyIcon.image = NSImage(
                systemSymbolName: "key.fill",
                accessibilityDescription: "SSH key"
            )
            keyIcon.contentTintColor = NSColor(
                calibratedRed: 0.15, green: 0.39, blue: 0.92, alpha: 1)
            keyIconContainer.addSubview(keyIcon)
            NSLayoutConstraint.activate([
                keyIcon.centerXAnchor.constraint(equalTo: keyIconContainer.centerXAnchor),
                keyIcon.centerYAnchor.constraint(equalTo: keyIconContainer.centerYAnchor),
                keyIcon.widthAnchor.constraint(equalToConstant: 16),
                keyIcon.heightAnchor.constraint(equalToConstant: 16),
            ])
        }

        let keyType = NSTextField(labelWithString: "SSH KEY")
        keyType.translatesAutoresizingMaskIntoConstraints = false
        keyType.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        keyType.textColor = NSColor(calibratedWhite: 0.56, alpha: 1)

        let keyTitle = NSTextField(labelWithString: keyName)
        keyTitle.translatesAutoresizingMaskIntoConstraints = false
        keyTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        keyTitle.textColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        keyTitle.lineBreakMode = .byTruncatingTail
        keyTitle.maximumNumberOfLines = 1

        keyCard.addSubview(keyIconContainer)
        keyCard.addSubview(keyType)
        keyCard.addSubview(keyTitle)

        NSLayoutConstraint.activate([
            keyIconContainer.leadingAnchor.constraint(equalTo: keyCard.leadingAnchor, constant: 16),
            keyIconContainer.centerYAnchor.constraint(equalTo: keyCard.centerYAnchor),
            keyIconContainer.widthAnchor.constraint(equalToConstant: 36),
            keyIconContainer.heightAnchor.constraint(equalToConstant: 36),

            keyType.leadingAnchor.constraint(
                equalTo: keyIconContainer.trailingAnchor, constant: 12),
            keyType.topAnchor.constraint(equalTo: keyCard.topAnchor, constant: 18),

            keyTitle.leadingAnchor.constraint(
                equalTo: keyIconContainer.trailingAnchor, constant: 12),
            keyTitle.trailingAnchor.constraint(equalTo: keyCard.trailingAnchor, constant: -16),
            keyTitle.topAnchor.constraint(equalTo: keyType.bottomAnchor, constant: 4),
        ])

        return keyCard
    }

    private func styleButton(
        _ button: NSButton,
        background: NSColor,
        foreground: NSColor,
        iconSystemName: String? = nil,
        iconColor: NSColor? = nil
    ) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = background.cgColor
        button.layer?.cornerRadius = 12
        button.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: foreground,
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            ]
        )

        if #available(macOS 11.0, *), let iconSystemName {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            let image = NSImage(
                systemSymbolName: iconSystemName,
                accessibilityDescription: button.title
            )?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.contentTintColor = iconColor ?? foreground
        } else {
            button.image = nil
            button.contentTintColor = foreground
        }
    }
}

// MARK: - Launch at login helper

enum LaunchAtLoginError: LocalizedError {
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Launching at login requires macOS 13 or later."
        }
    }
}

enum LaunchAtLogin {
    static func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if enabled {
                if service.status == .enabled { return }
                try service.register()
            } else {
                if service.status == .notRegistered { return }
                try service.unregister()
            }
            return
        }
        throw LaunchAtLoginError.unsupportedOS
    }
}
