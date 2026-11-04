import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/repository/kdbx_repository_provider.dart';
import '../../../core/services/appearance_preferences.dart';
import '../../../core/services/general_preferences.dart';
import '../../../core/services/ssh_agent_service.dart';
import '../../../core/services/vault_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Settings host bridge (main engine side)
/// ─────────────────────────────────────────────────────────────────────────
///
/// The Settings window runs in a **second Flutter engine**, so it has its own
/// Dart isolate and its own Riverpod container. It cannot read this engine's
/// providers, and the decrypted vault never leaves this isolate.
///
/// Instead the detached window asks for a *snapshot* of the settings it is
/// allowed to see, and sends back *intents* to change them. Those intents are
/// applied here, against the real providers, exactly as if the user had
/// toggled them in the main window — which keeps the main window in sync via
/// normal Riverpod invalidation.
///
/// Channel (`lumenpass/settings_host`, native ⇄ main engine):
///   native → here:
///     • `requestSettings`  → returns the current snapshot as JSON
///     • `applySetting`     ({ 'key': String, 'value': Object? })
///                          → applies it, returns the new snapshot as JSON
///
/// Only preference-only keys live here. Anything that needs the decrypted
/// vault (master password, backup restore, biometrics, PIN) is deliberately
/// out of scope and is handed back to the main window instead.
class SettingsHostBridge {
  SettingsHostBridge._();

  static const MethodChannel channel = MethodChannel('lumenpass/settings_host');

  /// Keys the detached window is allowed to change. Exposed for tests.
  static const Set<String> writableKeys = <String>{
    'hideDockIcon',
    'autostartWithSystem',
    'startMinimized',
    'textSizeDelta',
    'fontFamily',
    'hideCreditCardNumber',
    'autoLockMinutes',
    'clipboardClearSeconds',
    'domainSetting',
    'autoFetchItemIcon',
    'sshAgentEnabled',
  };

  /// Registers the native call handler. Call once, from `main()`.
  ///
  /// `_nativeChannel` is the native → *this* engine channel created by
  /// `SettingsWindowController`; it is used to push updated snapshots when
  /// preferences change from somewhere other than the detached window.
  static void register(ProviderContainer container) {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'requestSettings':
          return jsonEncode(_snapshot(container));
        case 'applySetting':
          final args = call.arguments;
          if (args is! Map) return null;
          final key = args['key'];
          if (key is! String) return null;
          await _apply(container, key, args['value']);
          return jsonEncode(_snapshot(container));
        default:
          return null;
      }
    });
  }

  /// Everything the detached Settings window is allowed to render.
  static Map<String, Object?> _snapshot(ProviderContainer container) {
    final sshStatus = container.read(sshAgentConfigStatusProvider);
    return <String, Object?>{
      'hideDockIcon': container.read(hideDockIconProvider),
      'autostartWithSystem': container.read(autostartWithSystemProvider),
      'startMinimized': container.read(startMinimizedProvider),
      'textSizeDelta': container.read(appearanceTextSizeDeltaProvider),
      'fontFamily': container.read(appearanceFontFamilyProvider),
      'hideCreditCardNumber':
          container.read(vaultHideCreditCardNumberProvider),
      'autoLockMinutes': container.read(vaultAutoLockMinutesProvider),
      'clipboardClearSeconds':
          container.read(vaultClipboardClearSecondsProvider),
      'domainSetting': container.read(vaultDomainSettingProvider),
      'autoFetchItemIcon': container.read(vaultAutoFetchItemIconProvider),
      'sshAgentEnabled': container.read(sshAgentEnabledProvider),
      'sshAgentSocketPath': container.read(sshAgentSocketPathProvider),
      'sshAgentConfigStatus': sshStatus.name,
    };
  }

  /// Applies one setting to the live providers *and* persists it, so the
  /// main window and the next launch agree with the detached window.
  static Future<void> _apply(
    ProviderContainer container,
    String key,
    Object? value,
  ) async {
    final storage = container.read(localStorageProvider);

    switch (key) {
      case 'hideDockIcon':
        final enabled = value == true;
        container.read(hideDockIconProvider.notifier).state = enabled;
        await storage.write(
          key: generalHideDockIconKey,
          value: enabled.toString(),
        );
        await applyMacOSDockVisibilityPreference(container);
        return;

      case 'autostartWithSystem':
        final enabled = value == true;
        container.read(autostartWithSystemProvider.notifier).state = enabled;
        await storage.write(
          key: generalAutostartWithSystemKey,
          value: enabled.toString(),
        );
        // The OS may reject the change; applyAutostartPreference reconciles
        // the provider with the real system state when that happens.
        await applyAutostartPreference(container);
        return;

      case 'startMinimized':
        final enabled = value == true;
        container.read(startMinimizedProvider.notifier).state = enabled;
        await storage.write(
          key: generalStartMinimizedKey,
          value: enabled.toString(),
        );
        await applyStartMinimizedPreference(container);
        return;

      case 'textSizeDelta':
        final delta = ((value as num?)?.toInt() ?? 0).clamp(-2, 2);
        container.read(appearanceTextSizeDeltaProvider.notifier).state = delta;
        // Globals are read by the shared `_text` helpers on the next build.
        currentTextSizeDelta = delta;
        await storage.write(
          key: appearanceTextSizeDeltaKey,
          value: delta.toString(),
        );
        return;

      case 'fontFamily':
        final family = value as String?;
        if (family == null || family.isEmpty) return;
        container.read(appearanceFontFamilyProvider.notifier).state = family;
        currentFontFamily = family;
        await storage.write(
          key: appearanceFontFamilyKey,
          value: family,
        );
        return;

      case 'hideCreditCardNumber':
        final enabled = value == true;
        container.read(vaultHideCreditCardNumberProvider.notifier).state =
            enabled;
        await storage.write(
          key: vaultHideCreditCardNumberKey,
          value: enabled.toString(),
        );
        return;

      case 'autoLockMinutes':
        final minutes = (value as num?)?.toInt();
        container.read(vaultAutoLockMinutesProvider.notifier).state = minutes;
        await storage.write(
          key: vaultAutoLockMinutesKey,
          value: minutes == null ? 'never' : minutes.toString(),
        );
        return;

      case 'clipboardClearSeconds':
        final seconds = (value as num?)?.toInt();
        container.read(vaultClipboardClearSecondsProvider.notifier).state =
            seconds;
        await storage.write(
          key: vaultClipboardClearSecondsKey,
          value: seconds == null ? 'never' : seconds.toString(),
        );
        return;

      case 'domainSetting':
        final setting = value as String?;
        const valid = {'default', 'baseDomain', 'subdomain'};
        if (setting == null || !valid.contains(setting)) return;
        container.read(vaultDomainSettingProvider.notifier).state = setting;
        await storage.write(key: vaultDomainSettingKey, value: setting);
        return;

      case 'autoFetchItemIcon':
        final enabled = value == true;
        container.read(vaultAutoFetchItemIconProvider.notifier).state = enabled;
        await storage.write(
          key: vaultAutoFetchItemIconKey,
          value: enabled.toString(),
        );
        return;

      case 'sshAgentEnabled':
        // SshAgentService persists the value and drives the native agent, so
        // it stays the single owner of this preference.
        await SshAgentService.instance.setEnabled(value == true);
        return;

      default:
        return;
    }
  }
}
