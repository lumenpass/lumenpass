import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const Map<int, int> _hidToWindowsVk = {
  0x04: 0x41, // A
  0x05: 0x42, // B
  0x06: 0x43, // C
  0x07: 0x44, // D
  0x08: 0x45, // E
  0x09: 0x46, // F
  0x0A: 0x47, // G
  0x0B: 0x48, // H
  0x0C: 0x49, // I
  0x0D: 0x4A, // J
  0x0E: 0x4B, // K
  0x0F: 0x4C, // L
  0x10: 0x4D, // M
  0x11: 0x4E, // N
  0x12: 0x4F, // O
  0x13: 0x50, // P
  0x14: 0x51, // Q
  0x15: 0x52, // R
  0x16: 0x53, // S
  0x17: 0x54, // T
  0x18: 0x55, // U
  0x19: 0x56, // V
  0x1A: 0x57, // W
  0x1B: 0x58, // X
  0x1C: 0x59, // Y
  0x1D: 0x5A, // Z
  0x1E: 0x31, // 1
  0x1F: 0x32, // 2
  0x20: 0x33, // 3
  0x21: 0x34, // 4
  0x22: 0x35, // 5
  0x23: 0x36, // 6
  0x24: 0x37, // 7
  0x25: 0x38, // 8
  0x26: 0x39, // 9
  0x27: 0x30, // 0
  0x28: 0x0D, // Return (VK_RETURN)
  0x29: 0x1B, // Escape (VK_ESCAPE)
  0x2A: 0x08, // Backspace (VK_BACK)
  0x2B: 0x09, // Tab (VK_TAB)
  0x2C: 0x20, // Space (VK_SPACE)
  0x2D: 0xBD, // - _ (VK_OEM_MINUS)
  0x2E: 0xBB, // = + (VK_OEM_PLUS)
  0x2F: 0xDB, // [ { (VK_OEM_4)
  0x30: 0xDD, // ] } (VK_OEM_6)
  0x31: 0xDC, // \ | (VK_OEM_5)
  0x33: 0xBA, // ; : (VK_OEM_1)
  0x34: 0xDE, // ' " (VK_OEM_7)
  0x35: 0xC0, // ` ~ (VK_OEM_3)
  0x36: 0xBC, // , < (VK_OEM_COMMA)
  0x37: 0xBE, // . > (VK_OEM_PERIOD)
  0x38: 0xBF, // / ? (VK_OEM_2)
  0x39: 0x14, // Caps Lock (VK_CAPITAL)
  0x3A: 0x70, // F1 (VK_F1)
  0x3B: 0x71, // F2
  0x3C: 0x72, // F3
  0x3D: 0x73, // F4
  0x3E: 0x74, // F5
  0x3F: 0x75, // F6
  0x40: 0x76, // F7
  0x41: 0x77, // F8
  0x42: 0x78, // F9
  0x43: 0x79, // F10
  0x44: 0x7A, // F11
  0x45: 0x7B, // F12
  0x4C: 0x2E, // Delete Forward (VK_DELETE)
  0x4F: 0x27, // Right Arrow (VK_RIGHT)
  0x50: 0x25, // Left Arrow (VK_LEFT)
  0x51: 0x28, // Down Arrow (VK_DOWN)
  0x52: 0x26, // Up Arrow (VK_UP)
};

/// USB HID keyboard usage code → macOS virtual keyCode
/// Ref: https://developer.apple.com/library/archive/technotes/tn2450/_index.html
const Map<int, int> _hidToMacKeyCode = {
  0x04: 0,   // A
  0x05: 11,  // B
  0x06: 8,   // C
  0x07: 2,   // D
  0x08: 14,  // E
  0x09: 3,   // F
  0x0A: 5,   // G
  0x0B: 4,   // H
  0x0C: 34,  // I
  0x0D: 38,  // J
  0x0E: 40,  // K
  0x0F: 37,  // L
  0x10: 46,  // M
  0x11: 45,  // N
  0x12: 31,  // O
  0x13: 35,  // P
  0x14: 12,  // Q
  0x15: 15,  // R
  0x16: 1,   // S
  0x17: 17,  // T
  0x18: 32,  // U
  0x19: 9,   // V
  0x1A: 13,  // W
  0x1B: 7,   // X
  0x1C: 16,  // Y
  0x1D: 6,   // Z
  0x1E: 18,  // 1
  0x1F: 19,  // 2
  0x20: 20,  // 3
  0x21: 21,  // 4
  0x22: 23,  // 5
  0x23: 22,  // 6
  0x24: 26,  // 7
  0x25: 28,  // 8
  0x26: 25,  // 9
  0x27: 29,  // 0
  0x28: 36,  // Return
  0x29: 53,  // Escape
  0x2A: 51,  // Backspace (Delete ⌫)
  0x2B: 48,  // Tab
  0x2C: 49,  // Space
  0x2D: 27,  // - _
  0x2E: 24,  // = +
  0x2F: 33,  // [ {
  0x30: 30,  // ] }
  0x31: 42,  // \ |
  0x33: 41,  // ; :
  0x34: 39,  // ' "
  0x35: 50,  // ` ~
  0x36: 43,  // , <
  0x37: 47,  // . >
  0x38: 44,  // / ?
  0x39: 57,  // Caps Lock
  0x3A: 122, // F1
  0x3B: 120, // F2
  0x3C: 99,  // F3
  0x3D: 118, // F4
  0x3E: 96,  // F5
  0x3F: 97,  // F6
  0x40: 98,  // F7
  0x41: 100, // F8
  0x42: 101, // F9
  0x43: 109, // F10
  0x44: 103, // F11
  0x45: 111, // F12
  0x4C: 117, // Delete Forward
  0x4F: 124, // Right Arrow
  0x50: 123, // Left Arrow
  0x51: 125, // Down Arrow
  0x52: 126, // Up Arrow
};

String getControlModifierLabel() => Platform.isWindows ? 'Ctrl' : '⌃';
String getAltModifierLabel() => Platform.isWindows ? 'Alt' : '⌥';
String getShiftModifierLabel() => Platform.isWindows ? 'Shift' : '⇧';
String getMetaModifierLabel() => Platform.isWindows ? 'Win' : '⌘';

String formatShortcutForPlatform({
  required bool ctrl,
  required bool alt,
  required bool shift,
  required bool meta,
  required String keyLabel,
}) {
  if (Platform.isWindows) {
    final parts = <String>[
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Win',
    ];
    parts.add(keyLabel);
    return parts.join('+');
  } else {
    final parts = <String>[
      if (ctrl) '⌃',
      if (alt) '⌥',
      if (shift) '⇧',
      if (meta) '⌘',
    ];
    parts.add(keyLabel);
    return parts.join();
  }
}

enum ShortcutId {
  spotlight,
  lockVault;

  String get storageKey => switch (this) {
        ShortcutId.spotlight => 'shortcut_v1_spotlight',
        ShortcutId.lockVault => 'shortcut_v1_lock_vault',
      };

  String get updateMethod => switch (this) {
        ShortcutId.spotlight => 'updateQuickSearchHotKey',
        ShortcutId.lockVault => 'updateLockVaultHotKey',
      };

  String get clearMethod => switch (this) {
        ShortcutId.spotlight => 'clearQuickSearchHotKey',
        ShortcutId.lockVault => 'clearLockVaultHotKey',
      };
}

class ShortcutData {
  const ShortcutData({
    required this.display,
    required this.macKeyCode,
    required this.ctrl,
    required this.shift,
    required this.alt,
    required this.meta,
    this.windowsVkCode = 0,
  });

  final String display;
  final int macKeyCode;
  final int windowsVkCode;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  int get carbonModifiers {
    int m = 0;
    if (ctrl) m |= 4096;
    if (shift) m |= 512;
    if (alt) m |= 2048;
    if (meta) m |= 256;
    return m;
  }

  int get windowsModifiers {
    int m = 0;
    if (alt) m |= 0x0001;   // MOD_ALT
    if (ctrl) m |= 0x0002;  // MOD_CONTROL
    if (shift) m |= 0x0004; // MOD_SHIFT
    if (meta) m |= 0x0008;  // MOD_WIN
    return m;
  }

  Map<String, dynamic> toJson() => {
        'display': display,
        'macKeyCode': macKeyCode,
        'windowsVkCode': windowsVkCode,
        'ctrl': ctrl,
        'shift': shift,
        'alt': alt,
        'meta': meta,
      };

  factory ShortcutData.fromJson(Map<String, dynamic> json) => ShortcutData(
        display: json['display'] as String? ?? '',
        macKeyCode: json['macKeyCode'] as int? ?? 0,
        windowsVkCode: json['windowsVkCode'] as int? ?? 0,
        ctrl: json['ctrl'] as bool? ?? false,
        shift: json['shift'] as bool? ?? false,
        alt: json['alt'] as bool? ?? false,
        meta: json['meta'] as bool? ?? false,
      );

  static ShortcutData? fromKeyEvent(
    KeyEvent event,
    String display, {
    required bool ctrl,
    required bool shift,
    required bool alt,
    required bool meta,
  }) {
    final hidUsage = event.physicalKey.usbHidUsage & 0xFFFF;
    final macKeyCode = _hidToMacKeyCode[hidUsage];
    final windowsVk = _hidToWindowsVk[hidUsage];
    if (macKeyCode == null && windowsVk == null) return null;
    return ShortcutData(
      display: display,
      macKeyCode: macKeyCode ?? 0,
      windowsVkCode: windowsVk ?? 0,
      ctrl: ctrl,
      shift: shift,
      alt: alt,
      meta: meta,
    );
  }

  static ShortcutData get defaultSpotlight => ShortcutData(
        display: formatShortcutForPlatform(
          ctrl: true,
          alt: false,
          shift: true,
          meta: false,
          keyLabel: 'Space',
        ),
        macKeyCode: 49,
        windowsVkCode: 0x20,
        ctrl: true,
        shift: true,
        alt: false,
        meta: false,
      );

  static ShortcutData get defaultLockVault => ShortcutData(
        display: formatShortcutForPlatform(
          ctrl: true,
          alt: false,
          shift: true,
          meta: false,
          keyLabel: Platform.isWindows ? 'Backspace' : '⌫',
        ),
        macKeyCode: 51,
        windowsVkCode: 0x08,
        ctrl: true,
        shift: true,
        alt: false,
        meta: false,
      );
}

class ShortcutService {
  static final ShortcutService instance = ShortcutService._();
  ShortcutService._();

  final _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  Future<ShortcutData?> load(String key) async {
    try {
      final json = await _storage.read(key: key);
      if (json == null) return null;
      return ShortcutData.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String key, ShortcutData? data) async {
    try {
      if (data == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: jsonEncode(data.toJson()));
      }
    } catch (_) {}
  }
}

final spotlightShortcutProvider = StateProvider<ShortcutData?>((_) => null);
final lockVaultShortcutProvider = StateProvider<ShortcutData?>((_) => null);
