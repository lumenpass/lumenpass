import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

/// flutter_secure_storage-backed secret store for sensitive data (passwords, PINs).
class SecureStorageService implements SecretStore {
  SecureStorageService();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
