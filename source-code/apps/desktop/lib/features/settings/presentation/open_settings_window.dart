import 'dart:io';

import 'package:flutter/services.dart';

/// Opens the **detached** Settings window (a real, separate OS window backed
/// by a second Flutter engine — see `SettingsWindowController.swift` and
/// `settingsMain()` in `main.dart`).
///
/// Returns `true` when the native window was opened, so callers can skip the
/// in-window settings overlay. Returns `false` on platforms that do not
/// implement the native host yet, letting the caller fall back to the existing
/// in-window settings UI.
///
/// Only preference-only sections are hosted here. Panes that need the
/// decrypted vault (master password, backup restore, biometrics, PIN) stay in
/// the main window by design — a second engine has no vault access.
///
/// [section] uses the same names as the main window's `_SettingsSectionId`:
/// `general`, `appearance`, `security`, `advanced`, `about`. Callers may also
/// pass `developer` (the SSH Agent pane), which maps to `advanced`.
Future<bool> openDetachedSettingsWindow({String section = 'general'}) async {
  if (!Platform.isMacOS) return false;
  try {
    await const MethodChannel('lumenpass/window').invokeMethod<void>(
      'openSettingsWindow',
      <String, Object?>{'section': _detachedSectionFor(section)},
    );
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Maps main-window section ids onto the panes the detached window hosts.
String _detachedSectionFor(String section) {
  return switch (section) {
    'developer' => 'advanced',
    'cardSecurity' => 'security',
    'general' || 'appearance' || 'security' || 'advanced' || 'about' =>
      section,
    // Everything else is vault-bound and belongs to the main window.
    _ => 'general',
  };
}
