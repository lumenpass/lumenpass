import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/repository/providers.dart';
import 'autofill_bridge.dart';
import 'autofill_credential.dart';

/// Singleton bridge used by the rest of the app.
final autoFillBridgeProvider = Provider<AutoFillBridge>(
  (ref) => AutoFillBridge.instance,
);

// ─── User preferences ────────────────────────────────────────────────────────

const _kPrefEnableAutoFill = 'autofill.enabled';
const _kPrefInlineSuggestions = 'autofill.inline';
const _kPrefSuggestPasskeys = 'autofill.passkeys';
const _kPrefAskBeforeFilling = 'autofill.confirm';
const _kPrefMatchMode = 'autofill.match';

/// Persisted user preferences for the AutoFill feature.
class AutoFillPreferences {
  const AutoFillPreferences({
    required this.enabled,
    required this.inlineSuggestions,
    required this.suggestPasskeys,
    required this.askBeforeFilling,
    required this.matchMode,
  });

  final bool enabled;
  final bool inlineSuggestions;
  final bool suggestPasskeys;
  final bool askBeforeFilling;
  final String matchMode;

  static const AutoFillPreferences defaults = AutoFillPreferences(
    enabled: true,
    inlineSuggestions: true,
    suggestPasskeys: true,
    askBeforeFilling: false,
    matchMode: 'Domain',
  );

  AutoFillPreferences copyWith({
    bool? enabled,
    bool? inlineSuggestions,
    bool? suggestPasskeys,
    bool? askBeforeFilling,
    String? matchMode,
  }) {
    return AutoFillPreferences(
      enabled: enabled ?? this.enabled,
      inlineSuggestions: inlineSuggestions ?? this.inlineSuggestions,
      suggestPasskeys: suggestPasskeys ?? this.suggestPasskeys,
      askBeforeFilling: askBeforeFilling ?? this.askBeforeFilling,
      matchMode: matchMode ?? this.matchMode,
    );
  }
}

class AutoFillPreferencesNotifier extends StateNotifier<AutoFillPreferences> {
  AutoFillPreferencesNotifier() : super(AutoFillPreferences.defaults) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AutoFillPreferences(
      enabled: prefs.getBool(_kPrefEnableAutoFill) ?? state.enabled,
      inlineSuggestions:
          prefs.getBool(_kPrefInlineSuggestions) ?? state.inlineSuggestions,
      suggestPasskeys:
          prefs.getBool(_kPrefSuggestPasskeys) ?? state.suggestPasskeys,
      askBeforeFilling:
          prefs.getBool(_kPrefAskBeforeFilling) ?? state.askBeforeFilling,
      matchMode: prefs.getString(_kPrefMatchMode) ?? state.matchMode,
    );
  }

  Future<void> setEnabled(bool value) =>
      _update(state.copyWith(enabled: value));
  Future<void> setInlineSuggestions(bool value) =>
      _update(state.copyWith(inlineSuggestions: value));
  Future<void> setSuggestPasskeys(bool value) =>
      _update(state.copyWith(suggestPasskeys: value));
  Future<void> setAskBeforeFilling(bool value) =>
      _update(state.copyWith(askBeforeFilling: value));
  Future<void> setMatchMode(String value) =>
      _update(state.copyWith(matchMode: value));

  Future<void> _update(AutoFillPreferences next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefEnableAutoFill, next.enabled);
    await prefs.setBool(_kPrefInlineSuggestions, next.inlineSuggestions);
    await prefs.setBool(_kPrefSuggestPasskeys, next.suggestPasskeys);
    await prefs.setBool(_kPrefAskBeforeFilling, next.askBeforeFilling);
    await prefs.setString(_kPrefMatchMode, next.matchMode);
  }
}

final autoFillPreferencesProvider =
    StateNotifierProvider<AutoFillPreferencesNotifier, AutoFillPreferences>(
      (ref) => AutoFillPreferencesNotifier(),
    );

// ─── System status (auto-refreshing) ─────────────────────────────────────────

final autoFillServiceStatusProvider = FutureProvider<AutoFillServiceStatus>((
  ref,
) async {
  final bridge = ref.watch(autoFillBridgeProvider);
  return bridge.getStatus();
});

// ─── Chrome third-party autofill mode (Android only) ─────────────────────────

final chromeThirdPartyModeProvider = FutureProvider<ChromeThirdPartyMode>((
  ref,
) async {
  final bridge = ref.watch(autoFillBridgeProvider);
  return bridge.getChromeThirdPartyMode();
});

// ─── Sync controller: wires active vault → native AutoFill provider ──────────

/// Pushes the current vault state to the native AutoFill store.
///
/// Exposed separately from the reactive provider so that callers (e.g. an
/// `AppLifecycleState.resumed` observer) can force a re-sync after the user
/// flipped the provider toggle in system Settings without re-opening the app.
Future<void> runAutoFillSync(ProviderContainer container) async {
  final bridge = container.read(autoFillBridgeProvider);
  if (!bridge.isPlatformSupported) return;

  final prefs = container.read(autoFillPreferencesProvider);
  final db = container.read(activeDatabaseProvider);

  try {
    if (db == null || !prefs.enabled) {
      await bridge.clearCredentials();
      return;
    }
    final credentials = db.entries
        .map(AutoFillCredential.fromEntry)
        .whereType<AutoFillCredential>()
        .toList(growable: false);
    await bridge.syncCredentials(credentials);
  } on MissingPluginException {
    // ignore – native not wired in (tests, desktop)
  }
}

/// Watches the currently-unlocked database and the user's AutoFill
/// preference. When both are present and the feature is enabled, it pushes
/// eligible credentials into the OS. When the vault locks or the user
/// disables the feature, it clears the cached credentials.
final autoFillSyncControllerProvider = Provider<void>(
  (ref) {
    final bridge = ref.watch(autoFillBridgeProvider);
    final prefs = ref.watch(autoFillPreferencesProvider);
    final db = ref.watch(activeDatabaseProvider);

    Future<void> run() async {
      if (!bridge.isPlatformSupported) return;
      try {
        if (db == null || !prefs.enabled) {
          await bridge.clearCredentials();
          return;
        }
        final credentials = db.entries
            .map(AutoFillCredential.fromEntry)
            .whereType<AutoFillCredential>()
            .toList(growable: false);
        await bridge.syncCredentials(credentials);
      } on MissingPluginException {
        // ignore – native not wired in (tests, desktop)
      }
    }

    unawaited(run());
    return;
  },
  dependencies: [
    autoFillBridgeProvider,
    autoFillPreferencesProvider,
    activeDatabaseProvider,
  ],
);

/// Ensures the sync controller is kept alive for the app's lifetime.
/// Call `ref.listen(autoFillSyncControllerProvider, (_, __) {})` from the
/// root widget, or read `ref.watch(autoFillSyncControllerProvider)` in a
/// top-level builder.
final keepAutoFillSyncAliveProvider = Provider<void>((ref) {
  ref.listen<void>(
    autoFillSyncControllerProvider,
    (_, _) {},
    fireImmediately: true,
  );
});
