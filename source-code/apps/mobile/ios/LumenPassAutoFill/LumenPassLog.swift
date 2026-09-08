// LumenPassLog.swift
//
// iOS on real devices redacts `NSLog` string interpolations as `<private>` in
// the unified log (Console.app / `log stream`). For the passkey assertion
// diagnostics to be visible on physical hardware, we must emit logs via
// `os_log` with an explicit `%{public}@` format specifier.
//
// Usage: `lpLog("message \(value)")` — same ergonomics as `NSLog`.

import Foundation
import os.log

private let _lumenPassLog = OSLog(
    subsystem: "com.tranit.lumenpass.ios.autofill",
    category: "LumenPassAutoFill"
)

/// Logs `message` to the unified log so its contents remain visible on
/// real devices (not redacted as `<private>`).
@inline(__always)
func lpLog(_ message: @autoclosure () -> String) {
    // Build the string once, then hand it to os_log with a fully public
    // format. `%{public}@` bypasses the default <private> redaction that
    // Swift string interpolation triggers when funneled through `NSLog`.
    let rendered = message()
    os_log("%{public}@", log: _lumenPassLog, type: .default, rendered)
}
