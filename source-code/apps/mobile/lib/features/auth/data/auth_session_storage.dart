import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'auth_models.dart';

class AuthSessionStorage {
  AuthSessionStorage();

  static const _kSessionKey = 'lp_session';
  static const _kDeviceIdKey = 'lp_device_id';

  static const _options = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _options,
    iOptions: _iOptions,
  );

  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _kSessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AuthSession.fromJson(decoded);
      }
    } catch (_) {
      await _storage.delete(key: _kSessionKey);
    }
    return null;
  }

  Future<void> write(AuthSession session) async {
    await _storage.write(
      key: _kSessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<void> clear() => _storage.delete(key: _kSessionKey);

  /// Returns a stable per-install device id, generating one on first use.
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _kDeviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = const Uuid().v4();
    await _storage.write(key: _kDeviceIdKey, value: fresh);
    return fresh;
  }
}
