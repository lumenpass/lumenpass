import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/repository/providers.dart';
import 'package:mobile/core/services/local_storage_service.dart';
import 'package:mobile/features/settings/application/vault_security_provider.dart';

void main() {
  group('VaultSecuritySettings', () {
    test('round-trips every auto-lock timeout through storage JSON', () {
      for (final timeout in AutoLockTimeout.values) {
        final hydrated = VaultSecuritySettings.fromJson(
          VaultSecuritySettings(autoLock: timeout).toJson(),
        );

        expect(hydrated.autoLock, timeout);
      }
    });

    test('round-trips every clipboard clear timeout through storage JSON', () {
      for (final timeout in ClipboardClearTimeout.values) {
        final hydrated = VaultSecuritySettings.fromJson(
          VaultSecuritySettings(clipboardClear: timeout).toJson(),
        );

        expect(hydrated.clipboardClear, timeout);
      }
    });

    test('fromStorage: unknown value falls back to fourHours', () {
      expect(AutoLockTimeout.fromStorage('garbage'), AutoLockTimeout.fourHours);
    });

    test('fromStorage: null falls back to fourHours (new install)', () {
      expect(AutoLockTimeout.fromStorage(null), AutoLockTimeout.fourHours);
    });

    test('accepts legacy numeric storage values', () {
      final hydrated = VaultSecuritySettings.fromJson(<String, dynamic>{
        'autoLockMinutes': 480,
        'clipboardClearSeconds': 120,
      });

      expect(hydrated.autoLock, AutoLockTimeout.eightHours);
      expect(hydrated.clipboardClear, ClipboardClearTimeout.twoMinutes);
    });
  });

  group('VaultSecuritySettingsNotifier', () {
    test('loaded future completes after storage read resolves '
        'and state reflects the persisted value', () async {
      final readCompleter = Completer<String?>();
      final storage = _FakeLocalStorage(readCompleter: readCompleter);

      final container = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(vaultSecuritySettingsProvider.notifier);

      // Before storage resolves the provider state is the default.
      expect(
        container.read(vaultSecuritySettingsProvider).autoLock,
        AutoLockTimeout.fourHours,
        reason: 'default before load',
      );
      expect(notifier.loaded, isA<Future<void>>());

      // Simulate storage returning a "Never" setting.
      readCompleter.complete(
        '{"autoLockMinutes":"never","clipboardClearSeconds":"30",'
        '"hidePasswordsByDefault":true,"blockScreenshots":false,'
        '"hideCreditCardNumber":true}',
      );

      await notifier.loaded;

      expect(
        container.read(vaultSecuritySettingsProvider).autoLock,
        AutoLockTimeout.never,
        reason: 'state must reflect persisted "Never" after load',
      );
    });

    test('loaded future completes even when storage returns null '
        '(new install — no saved settings)', () async {
      final readCompleter = Completer<String?>();
      final storage = _FakeLocalStorage(readCompleter: readCompleter);

      final container = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(vaultSecuritySettingsProvider.notifier);
      readCompleter.complete(null);

      await expectLater(notifier.loaded, completes);
      expect(
        container.read(vaultSecuritySettingsProvider).autoLock,
        AutoLockTimeout.fourHours,
        reason: 'new install should keep the default',
      );
    });

    test('loaded future completes even when storage throws', () async {
      final badCompleter = Completer<String?>();
      final storage = _FakeLocalStorage(readCompleter: badCompleter);

      final container = ProviderContainer(
        overrides: [localStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(vaultSecuritySettingsProvider.notifier);
      badCompleter.completeError(Exception('disk error'));

      await expectLater(notifier.loaded, completes);
      // State should remain at the safe default.
      expect(
        container.read(vaultSecuritySettingsProvider).autoLock,
        AutoLockTimeout.fourHours,
      );
    });
  });
}

class _FakeLocalStorage implements LocalStorageService {
  _FakeLocalStorage({required this.readCompleter});

  final Completer<String?> readCompleter;

  @override
  Future<String?> read(String key) => readCompleter.future;

  @override
  Future<void> write(String key, String? value) async {}

  @override
  Future<void> delete(String key) async {}
}
