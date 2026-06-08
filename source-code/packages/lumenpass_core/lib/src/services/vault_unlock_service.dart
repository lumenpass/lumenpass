import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../platform/key_value_store.dart';
import '../platform/secret_store.dart';

/// Manages per-vault biometric and PIN unlock settings.
///
/// Preferences (enabled / disabled) are stored in a [KeyValueStore].
/// Sensitive data (master passwords, PIN hashes) live in a [SecretStore].
class VaultUnlockService {
  VaultUnlockService({
    required KeyValueStore preferences,
    required SecretStore secrets,
  })  : _preferences = preferences,
        _secrets = secrets;

  final KeyValueStore _preferences;
  final SecretStore _secrets;

  // ── Key helpers ─────────────────────────────────────────────────────────────

  static String _vaultId(String vaultPath) =>
      sha256.convert(utf8.encode(vaultPath)).toString().substring(0, 20);

  static String _bioEnabledKey(String p) => 'lp_bio_on_${_vaultId(p)}';
  static String _pinEnabledKey(String p) => 'lp_pin_on_${_vaultId(p)}';
  static String _bioPassKey(String p) => 'lp_bio_pw_${_vaultId(p)}';
  static String _pinHashKey(String p) => 'lp_pin_hash_${_vaultId(p)}';
  static String _pinSaltKey(String p) => 'lp_pin_salt_${_vaultId(p)}';
  static String _pinPassKey(String p) => 'lp_pin_pw_${_vaultId(p)}';
  static String _lastUnlockMethodKey(String p) =>
      'lp_last_unlock_${_vaultId(p)}';

  // ── Last unlock method (UX hint) ────────────────────────────────────────────

  Future<void> setLastUnlockMethod(
    String vaultPath,
    VaultLastUnlockMethod method,
  ) =>
      _preferences.write(
        _lastUnlockMethodKey(vaultPath),
        method == VaultLastUnlockMethod.none ? null : method.name,
      );

  Future<VaultLastUnlockMethod> getLastUnlockMethod(String vaultPath) async {
    final raw = await _preferences.read(_lastUnlockMethodKey(vaultPath));
    return VaultLastUnlockMethod.fromStorage(raw);
  }

  // ── Biometric ────────────────────────────────────────────────────────────────

  Future<bool> isBiometricEnabled(String vaultPath) async =>
      await _preferences.read(_bioEnabledKey(vaultPath)) == 'true';

  Future<void> setBiometricEnabled(String vaultPath, bool enabled) =>
      _preferences.write(_bioEnabledKey(vaultPath), enabled ? 'true' : null);

  Future<void> saveBiometricPassword(String vaultPath, String password) =>
      _secrets.write(_bioPassKey(vaultPath), password);

  Future<String?> getBiometricPassword(String vaultPath) =>
      _secrets.read(_bioPassKey(vaultPath));

  Future<void> clearBiometricData(String vaultPath) async {
    await _secrets.delete(_bioPassKey(vaultPath));
    await setBiometricEnabled(vaultPath, false);

    final last = await getLastUnlockMethod(vaultPath);
    if (last == VaultLastUnlockMethod.biometric) {
      await setLastUnlockMethod(vaultPath, VaultLastUnlockMethod.none);
    }
  }

  // ── PIN ──────────────────────────────────────────────────────────────────────

  Future<bool> isPinEnabled(String vaultPath) async =>
      await _preferences.read(_pinEnabledKey(vaultPath)) == 'true';

  Future<void> setPinEnabled(String vaultPath, bool enabled) =>
      _preferences.write(_pinEnabledKey(vaultPath), enabled ? 'true' : null);

  /// Stores [pin] (hashed) and [masterPassword] (in secrets) for the vault.
  Future<void> setupPin(
    String vaultPath,
    String pin,
    String masterPassword,
  ) async {
    final salt = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final hash = _hashPin(pin, salt);
    await _secrets.write(_pinHashKey(vaultPath), hash);
    await _secrets.write(_pinSaltKey(vaultPath), salt);
    await _secrets.write(_pinPassKey(vaultPath), masterPassword);
  }

  Future<bool> verifyPin(String vaultPath, String pin) async {
    final hash = await _secrets.read(_pinHashKey(vaultPath));
    final salt = await _secrets.read(_pinSaltKey(vaultPath));
    if (hash == null || salt == null) return false;
    return _hashPin(pin, salt) == hash;
  }

  Future<String?> getMasterPasswordForPin(String vaultPath, String pin) async {
    if (!await verifyPin(vaultPath, pin)) return null;
    return _secrets.read(_pinPassKey(vaultPath));
  }

  Future<void> clearPinData(String vaultPath) async {
    await _secrets.delete(_pinHashKey(vaultPath));
    await _secrets.delete(_pinSaltKey(vaultPath));
    await _secrets.delete(_pinPassKey(vaultPath));
    await setPinEnabled(vaultPath, false);

    final last = await getLastUnlockMethod(vaultPath);
    if (last == VaultLastUnlockMethod.pin) {
      await setLastUnlockMethod(vaultPath, VaultLastUnlockMethod.none);
    }
  }

  static String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$pin:$salt')).toString();
}

enum VaultLastUnlockMethod {
  none,
  biometric,
  pin;

  static VaultLastUnlockMethod fromStorage(String? raw) {
    switch (raw) {
      case 'biometric':
        return VaultLastUnlockMethod.biometric;
      case 'pin':
        return VaultLastUnlockMethod.pin;
      default:
        return VaultLastUnlockMethod.none;
    }
  }
}
