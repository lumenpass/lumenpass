import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repository/providers.dart';

// ── Enums ────────────────────────────────────────────────────────────────────

enum AutoLockTimeout {
  fifteenMinutes,
  thirtyMinutes,
  oneHour,
  fourHours,
  eightHours,
  twentyFourHours,
  never;

  int? get minutes => switch (this) {
    AutoLockTimeout.fifteenMinutes => 15,
    AutoLockTimeout.thirtyMinutes => 30,
    AutoLockTimeout.oneHour => 60,
    AutoLockTimeout.fourHours => 240,
    AutoLockTimeout.eightHours => 480,
    AutoLockTimeout.twentyFourHours => 1440,
    AutoLockTimeout.never => null,
  };

  String get label => switch (this) {
    AutoLockTimeout.fifteenMinutes => '15 min',
    AutoLockTimeout.thirtyMinutes => '30 min',
    AutoLockTimeout.oneHour => '1 hour',
    AutoLockTimeout.fourHours => '4 hours',
    AutoLockTimeout.eightHours => '8 hours',
    AutoLockTimeout.twentyFourHours => '24 hours',
    AutoLockTimeout.never => 'Never',
  };

  static AutoLockTimeout fromMinutes(int? minutes) => switch (minutes) {
    15 => AutoLockTimeout.fifteenMinutes,
    30 => AutoLockTimeout.thirtyMinutes,
    60 => AutoLockTimeout.oneHour,
    240 => AutoLockTimeout.fourHours,
    480 => AutoLockTimeout.eightHours,
    1440 => AutoLockTimeout.twentyFourHours,
    _ => AutoLockTimeout.fourHours,
  };

  static AutoLockTimeout fromStorage(Object? raw) {
    // null means no preference has been saved yet (new install) → default.
    if (raw == null) return AutoLockTimeout.fourHours;
    final value = raw.toString();
    if (value == 'never') return AutoLockTimeout.never;
    // Unrecognized numeric values also fall back to fourHours via fromMinutes.
    return fromMinutes(int.tryParse(value));
  }
}

enum ClipboardClearTimeout {
  tenSeconds,
  thirtySeconds,
  oneMinute,
  twoMinutes,
  never;

  int? get seconds => switch (this) {
    ClipboardClearTimeout.tenSeconds => 10,
    ClipboardClearTimeout.thirtySeconds => 30,
    ClipboardClearTimeout.oneMinute => 60,
    ClipboardClearTimeout.twoMinutes => 120,
    ClipboardClearTimeout.never => null,
  };

  String get label => switch (this) {
    ClipboardClearTimeout.tenSeconds => '10 seconds',
    ClipboardClearTimeout.thirtySeconds => '30 seconds',
    ClipboardClearTimeout.oneMinute => '1 minute',
    ClipboardClearTimeout.twoMinutes => '2 minutes',
    ClipboardClearTimeout.never => 'Never',
  };

  static ClipboardClearTimeout fromSeconds(int? seconds) => switch (seconds) {
    10 => ClipboardClearTimeout.tenSeconds,
    30 => ClipboardClearTimeout.thirtySeconds,
    60 => ClipboardClearTimeout.oneMinute,
    120 => ClipboardClearTimeout.twoMinutes,
    _ => ClipboardClearTimeout.thirtySeconds,
  };

  static ClipboardClearTimeout fromStorage(Object? raw) {
    if (raw == null) return ClipboardClearTimeout.thirtySeconds;
    final value = raw.toString();
    if (value == 'never') return ClipboardClearTimeout.never;
    return fromSeconds(int.tryParse(value));
  }
}

// ── Model ────────────────────────────────────────────────────────────────────

@immutable
class VaultSecuritySettings {
  const VaultSecuritySettings({
    this.autoLock = AutoLockTimeout.fourHours,
    this.clipboardClear = ClipboardClearTimeout.thirtySeconds,
    this.hidePasswordsByDefault = true,
    this.blockScreenshots = false,
    this.hideCreditCardNumber = true,
  });

  final AutoLockTimeout autoLock;
  final ClipboardClearTimeout clipboardClear;
  final bool hidePasswordsByDefault;
  final bool blockScreenshots;
  final bool hideCreditCardNumber;

  VaultSecuritySettings copyWith({
    AutoLockTimeout? autoLock,
    ClipboardClearTimeout? clipboardClear,
    bool? hidePasswordsByDefault,
    bool? blockScreenshots,
    bool? hideCreditCardNumber,
  }) => VaultSecuritySettings(
    autoLock: autoLock ?? this.autoLock,
    clipboardClear: clipboardClear ?? this.clipboardClear,
    hidePasswordsByDefault:
        hidePasswordsByDefault ?? this.hidePasswordsByDefault,
    blockScreenshots: blockScreenshots ?? this.blockScreenshots,
    hideCreditCardNumber: hideCreditCardNumber ?? this.hideCreditCardNumber,
  );

  Map<String, dynamic> toJson() => {
    'autoLockMinutes': autoLock.minutes?.toString() ?? 'never',
    'clipboardClearSeconds': clipboardClear.seconds?.toString() ?? 'never',
    'hidePasswordsByDefault': hidePasswordsByDefault,
    'blockScreenshots': blockScreenshots,
    'hideCreditCardNumber': hideCreditCardNumber,
  };

  static VaultSecuritySettings fromJson(Map<String, dynamic> json) =>
      VaultSecuritySettings(
        autoLock: AutoLockTimeout.fromStorage(json['autoLockMinutes']),
        clipboardClear: ClipboardClearTimeout.fromStorage(
          json['clipboardClearSeconds'],
        ),
        hidePasswordsByDefault: json['hidePasswordsByDefault'] as bool? ?? true,
        blockScreenshots: json['blockScreenshots'] as bool? ?? false,
        hideCreditCardNumber: json['hideCreditCardNumber'] as bool? ?? true,
      );
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class VaultSecuritySettingsNotifier
    extends StateNotifier<VaultSecuritySettings> {
  VaultSecuritySettingsNotifier(this._ref)
    : super(const VaultSecuritySettings()) {
    _load();
  }

  static const _kKey = 'lumenpass_vault_security_v1';
  final Ref _ref;
  final Completer<void> _loadedCompleter = Completer<void>();

  /// Completes once persisted settings have been read from storage.
  /// Consumers that need the correct initial value (e.g. the auto-lock timer)
  /// should await this before reading the provider state.
  Future<void> get loaded => _loadedCompleter.future;

  Future<void> _load() async {
    try {
      final raw = await _ref.read(localStorageProvider).read(_kKey);
      if (raw != null && raw.isNotEmpty) {
        state = VaultSecuritySettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
    } finally {
      _loadedCompleter.complete();
    }
  }

  Future<void> _persist() async {
    try {
      await _ref
          .read(localStorageProvider)
          .write(_kKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  Future<void> setAutoLock(AutoLockTimeout value) async {
    state = state.copyWith(autoLock: value);
    await _persist();
  }

  Future<void> setClipboardClear(ClipboardClearTimeout value) async {
    state = state.copyWith(clipboardClear: value);
    await _persist();
  }

  Future<void> setHidePasswordsByDefault(bool value) async {
    state = state.copyWith(hidePasswordsByDefault: value);
    await _persist();
  }

  Future<void> setBlockScreenshots(bool value) async {
    state = state.copyWith(blockScreenshots: value);
    await _persist();
  }

  Future<void> setHideCreditCardNumber(bool value) async {
    state = state.copyWith(hideCreditCardNumber: value);
    await _persist();
  }
}

final vaultSecuritySettingsProvider =
    StateNotifierProvider<VaultSecuritySettingsNotifier, VaultSecuritySettings>(
      (ref) => VaultSecuritySettingsNotifier(ref),
    );
