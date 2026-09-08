import Cocoa

// Single-instance guard — runs before NSApplicationMain, so the NIB is
// never loaded and Flutter never boots in a duplicate process.
let _bundleID = Bundle.main.bundleIdentifier ?? ""
let _currentPID = ProcessInfo.processInfo.processIdentifier
let _others = NSRunningApplication.runningApplications(withBundleIdentifier: _bundleID)
    .filter { $0.processIdentifier != _currentPID }

if let existing = _others.first {
    // Initialise only the bare NSApplication — no NIB, no delegate, no window.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    existing.activate(options: [.activateIgnoringOtherApps])

    let alert = NSAlert()
    alert.messageText = "LumenPass is already running"
    alert.informativeText = "The existing window has been brought to the front."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
    exit(0)
}

// Not a duplicate — proceed with normal full launch.
NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
