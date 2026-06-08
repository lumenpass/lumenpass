import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lumenpass_core/lumenpass_core.dart' as core;

import '../repository/kdbx_repository_provider.dart';
import 'local_storage_service.dart';

/// [MacOsOptions] override that disables the Data Protection Keychain so that
/// the plugin works in a sandboxed app without the `keychain-access-groups`
/// entitlement (which requires a development signing certificate).
class _SandboxMacOsOptions extends MacOsOptions {
  const _SandboxMacOsOptions();

  @override
  Map<String, String> toMap() {
    return <String, String>{
      ...super.toMap(),
      'useDataProtectionKeyChain': 'false',
    };
  }
}

class _PrefsStore implements core.KeyValueStore {
  _PrefsStore(this._prefs);

  final LocalStorageService _prefs;

  @override
  Future<void> delete(String key) => _prefs.delete(key: key);

  @override
  Future<String?> read(String key) => _prefs.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      _prefs.write(key: key, value: value);
}

class _SecureStore implements core.SecretStore {
  const _SecureStore();

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    mOptions: _SandboxMacOsOptions(),
  );

  @override
  Future<void> delete(String key) => _secure.delete(key: key);

  @override
  Future<String?> read(String key) => _secure.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _secure.delete(key: key) : _secure.write(key: key, value: value);
}

typedef VaultUnlockService = core.VaultUnlockService;
typedef VaultLastUnlockMethod = core.VaultLastUnlockMethod;

final vaultUnlockServiceProvider = Provider<VaultUnlockService>(
  (ref) => core.VaultUnlockService(
    preferences: _PrefsStore(ref.read(localStorageProvider)),
    secrets: const _SecureStore(),
  ),
);
