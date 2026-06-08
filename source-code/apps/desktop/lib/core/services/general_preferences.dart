import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/kdbx_repository_provider.dart';

// ── Storage keys ───────────────────────────────────────────────────────────
const String generalHideDockIconKey = 'general.hideDockIcon';
const String generalAutostartWithSystemKey = 'general.autostartWithSystem';
const String generalStartMinimizedKey = 'general.startMinimized';

// ── State providers ────────────────────────────────────────────────────────
final hideDockIconProvider = StateProvider<bool>((ref) => false);
final autostartWithSystemProvider = StateProvider<bool>((ref) => false);

/// When `true`, the main window stays hidden if the app is launched at login.
/// Has no effect when the user opens the app manually.
final startMinimizedProvider = StateProvider<bool>((ref) => false);

const MethodChannel _windowChannel = MethodChannel('lumenpass/window');

bool get _supportsAutostart => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> loadGeneralPreferences(ProviderContainer container) async {
  final storage = container.read(localStorageProvider);

  final hideRaw = await storage.read(key: generalHideDockIconKey);
  if (hideRaw != null) {
    container.read(hideDockIconProvider.notifier).state = hideRaw == 'true';
  }

  final autostartRaw =
      await storage.read(key: generalAutostartWithSystemKey);
  if (autostartRaw != null) {
    container.read(autostartWithSystemProvider.notifier).state =
        autostartRaw == 'true';
  }

  final startMinRaw = await storage.read(key: generalStartMinimizedKey);
  if (startMinRaw != null) {
    container.read(startMinimizedProvider.notifier).state =
        startMinRaw == 'true';
  }

  // Reconcile native login-item / Run-key status with the stored preference.
  if (_supportsAutostart) {
    await _syncAutostartWithOS(container);
    await _pushStartMinimizedToOS(container);
  }
}

/// Applies [hideDockIconProvider] via macOS `NSApplication` activation policy.
Future<void> applyMacOSDockVisibilityPreference(
    ProviderContainer container) async {
  if (!Platform.isMacOS) return;
  final hide = container.read(hideDockIconProvider);
  try {
    await _windowChannel.invokeMethod<void>('setHideDockIcon', hide);
  } catch (_) {}
}

/// Registers / unregisters the app as an OS login item so it launches on
/// user sign-in. On macOS this uses `SMAppService.mainApp`; on Windows this
/// writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
///
/// Returns the effective (post-call) state, which may differ from the
/// requested value if the OS rejected the change.
Future<bool> applyAutostartPreference(ProviderContainer container) async {
  final requested = container.read(autostartWithSystemProvider);
  if (!_supportsAutostart) return requested;

  try {
    await _windowChannel.invokeMethod<void>('setAutostart', requested);
    return requested;
  } on PlatformException {
    bool? actual;
    try {
      actual = await _windowChannel.invokeMethod<bool>('getAutostart');
    } catch (_) {
      actual = false;
    }
    final effective = actual ?? false;
    if (effective != requested) {
      container.read(autostartWithSystemProvider.notifier).state = effective;
      final storage = container.read(localStorageProvider);
      await storage.write(
        key: generalAutostartWithSystemKey,
        value: effective.toString(),
      );
    }
    return effective;
  }
}

/// Mirrors [startMinimizedProvider] into the native layer so it can be read
/// during launch (before the Flutter engine is running). On macOS this writes
/// `NSUserDefaults`; on Windows this writes a DWORD in
/// `HKCU\Software\LumenPass\StartMinimized`.
Future<void> applyStartMinimizedPreference(ProviderContainer container) async {
  if (!_supportsAutostart) return;
  final value = container.read(startMinimizedProvider);
  try {
    await _windowChannel.invokeMethod<void>('setStartMinimized', value);
  } catch (_) {}
}

/// Backwards-compatible aliases. Older call sites referenced the macOS-named
/// helpers; both platforms now go through the same channel.
Future<bool> applyMacOSAutostartPreference(ProviderContainer container) =>
    applyAutostartPreference(container);

Future<void> applyMacOSStartMinimizedPreference(ProviderContainer container) =>
    applyStartMinimizedPreference(container);

// ── Internal helpers ───────────────────────────────────────────────────────

Future<void> _syncAutostartWithOS(ProviderContainer container) async {
  bool? nativeEnabled;
  try {
    final result = await _windowChannel.invokeMethod<bool>('getAutostart');
    nativeEnabled = result;
  } catch (_) {
    nativeEnabled = null;
  }

  final stored = container.read(autostartWithSystemProvider);

  // Prefer the OS' truth when we can read it; otherwise push the stored value.
  if (nativeEnabled != null && nativeEnabled != stored) {
    container.read(autostartWithSystemProvider.notifier).state = nativeEnabled;
    final storage = container.read(localStorageProvider);
    await storage.write(
      key: generalAutostartWithSystemKey,
      value: nativeEnabled.toString(),
    );
  } else if (nativeEnabled == null) {
    await applyAutostartPreference(container);
  } else if (Platform.isWindows && stored && nativeEnabled == true) {
    // Refresh the Windows Run-key value so the executable path stays in
    // sync with the current install location and the launch arguments
    // (e.g. --autostart) reflect the latest format.
    await applyAutostartPreference(container);
  }
}

Future<void> _pushStartMinimizedToOS(ProviderContainer container) async {
  await applyStartMinimizedPreference(container);
}
