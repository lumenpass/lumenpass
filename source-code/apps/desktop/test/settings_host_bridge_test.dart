import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/repository/kdbx_repository_provider.dart';
import 'package:lumenpass/core/services/local_storage_service.dart';
import 'package:lumenpass/core/services/ssh_agent_service.dart';
import 'package:lumenpass/core/services/vault_preferences.dart';
import 'package:lumenpass/features/settings/application/settings_host_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryLocalStorageService storage;
  late ProviderContainer container;

  setUp(() {
    storage = _MemoryLocalStorageService();
    container = ProviderContainer(
      overrides: <Override>[
        localStorageProvider.overrideWithValue(storage),
      ],
    );
    SettingsHostBridge.register(container);
  });

  tearDown(() => container.dispose());

  /// Invokes `lumenpass/settings_host` as if the native host had called it.
  Future<Object?> hostCall(String method, [Object? arguments]) async {
    final completer = <String, Object?>{};
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      SettingsHostBridge.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (ByteData? reply) {
        if (reply == null) {
          completer['reply'] = null;
          return;
        }
        completer['reply'] = const StandardMethodCodec().decodeEnvelope(reply);
      },
    );
    return completer['reply'];
  }

  Map<String, dynamic> snapshotOf(Object? reply) =>
      jsonDecode(reply! as String) as Map<String, dynamic>;

  test('requestSettings returns preference snapshot', () async {
    final snapshot = snapshotOf(await hostCall('requestSettings'));

    expect(snapshot['hideDockIcon'], isFalse);
    expect(snapshot['startMinimized'], isFalse);
    expect(snapshot['hideCreditCardNumber'], isTrue);
    expect(snapshot['autoLockMinutes'], 30);
    expect(snapshot['clipboardClearSeconds'], 60);
    expect(snapshot['domainSetting'], 'default');
    expect(snapshot['autoFetchItemIcon'], isTrue);
    expect(snapshot['sshAgentEnabled'], isFalse);
    expect(snapshot['sshAgentConfigStatus'], 'unknown');
    expect(snapshot.containsKey('sshAgentSocketPath'), isTrue);
  });

  test('applySetting persists and updates the provider', () async {
    final snapshot = snapshotOf(await hostCall('applySetting', <String, Object?>{
      'key': 'hideCreditCardNumber',
      'value': false,
    }));

    expect(snapshot['hideCreditCardNumber'], isFalse);
    expect(storage.values[vaultHideCreditCardNumberKey], 'false');
    expect(container.read(vaultHideCreditCardNumberProvider), isFalse);
  });

  test('autoLockMinutes accepts null as "never"', () async {
    final snapshot = snapshotOf(await hostCall('applySetting', <String, Object?>{
      'key': 'autoLockMinutes',
      'value': null,
    }));

    expect(snapshot['autoLockMinutes'], isNull);
    expect(storage.values[vaultAutoLockMinutesKey], 'never');
    expect(container.read(vaultAutoLockMinutesProvider), isNull);
  });

  test('clipboardClearSeconds persists a concrete value', () async {
    final snapshot =
        snapshotOf(await hostCall('applySetting', <String, Object?>{
      'key': 'clipboardClearSeconds',
      'value': 90,
    }));

    expect(snapshot['clipboardClearSeconds'], 90);
    expect(storage.values[vaultClipboardClearSecondsKey], '90');
  });

  test('domainSetting rejects unknown values', () async {
    final snapshot = snapshotOf(await hostCall('applySetting', <String, Object?>{
      'key': 'domainSetting',
      'value': 'not-a-real-mode',
    }));

    expect(snapshot['domainSetting'], 'default');
    expect(storage.values.containsKey(vaultDomainSettingKey), isFalse);
  });

  test('autoFetchItemIcon round-trips', () async {
    final snapshot = snapshotOf(await hostCall('applySetting', <String, Object?>{
      'key': 'autoFetchItemIcon',
      'value': false,
    }));

    expect(snapshot['autoFetchItemIcon'], isFalse);
    expect(storage.values.containsKey(vaultAutoFetchItemIconKey), isTrue);
  });

  test('unknown keys are ignored', () async {
    final snapshot = snapshotOf(await hostCall('applySetting', <String, Object?>{
      'key': 'somethingElse',
      'value': true,
    }));

    expect(snapshot, isNotEmpty);
    expect(storage.values, isEmpty);
  });

  test('writable key set matches the applied switch cases', () {
    expect(
      SettingsHostBridge.writableKeys,
      containsAll(<String>[
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
      ]),
    );
  });
}

class _MemoryLocalStorageService extends LocalStorageService {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, String? value}) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}
