import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../platform/key_value_store.dart';
import '../platform/secret_store.dart';

/// Manages per-vault biometric and PIN unlock settings.
///
/// Sensitive data (master passwords, PIN hashes) always live in a
/// [SecretStore]. The enabled/disabled flags are stored in the
/// [KeyValueStore] by default, but can be routed to the [SecretStore] instead
/// by setting [storeFlagsInSecrets]. On mobile the flags are kept in secrets
/// so the enabled state and the password survive together (e.g. across
/// reinstalls, where platform key-value storage is wiped but the keychain is
/// not).
///
/// Callers identify a vault with an opaque identifier string (`vaultPath`
/// below). This can be any stable value — on desktop it is the vault file
/// path; on mobile it should be the vault's stable id rather than its absolute
/// file path, because iOS rotates the app container path across updates which
/// would otherwise orphan the stored unlock data.
class VaultUnlockService {
  VaultUnlockService({
    required KeyValueStore preferences,
    required SecretStore secrets,
    bool storeFlagsInSecrets = false,
  })  : _preferences = preferences,
        _secrets = secrets,
        _storeFlagsInSecrets = storeFlagsInSecrets;

  final KeyValueStore _preferences;
  final SecretStore _secrets;
  final bool _storeFlagsInSecrets;

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
  static String _migratedKey(String p) => 'lp_unlock_migrated_${_vaultId(p)}';
  static String _persistPassKey(String p) => 'lp_persist_pw_${_vaultId(p)}';
  static String _persistAtKey(String p) => 'lp_persist_at_${_vaultId(p)}';

  // ── Flag storage (preferences or secrets) ───────────────────────────────────

  Future<String?> _readFlag(String key) =>
      _storeFlagsInSecrets ? _secrets.read(key) : _preferences.read(key);

  Future<void> _writeFlag(String key, String? value) => _storeFlagsInSecrets
      ? _secrets.write(key, value)
      : _preferences.write(key, value);

  // ── Last unlock method (UX hint) ────────────────────────────────────────────

  Future<void> setLastUnlockMethod(
    String vaultPath,
    VaultLastUnlockMethod method,
  ) =>
      _writeFlag(
        _lastUnlockMethodKey(vaultPath),
        method == VaultLastUnlockMethod.none ? null : method.name,
      );

  Future<VaultLastUnlockMethod> getLastUnlockMethod(String vaultPath) async {
    final raw = await _readFlag(_lastUnlockMethodKey(vaultPath));
    return VaultLastUnlockMethod.fromStorage(raw);
  }

  // ── Biometric ────────────────────────────────────────────────────────────────

  Future<bool> isBiometricEnabled(String vaultPath) async =>
      await _readFlag(_bioEnabledKey(vaultPath)) == 'true';

  Future<void> setBiometricEnabled(String vaultPath, bool enabled) =>
      _writeFlag(_bioEnabledKey(vaultPath), enabled ? 'true' : null);

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
      await _readFlag(_pinEnabledKey(vaultPath)) == 'true';

  Future<void> setPinEnabled(String vaultPath, bool enabled) =>
      _writeFlag(_pinEnabledKey(vaultPath), enabled ? 'true' : null);

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

  // ── Persistent auto-unlock ────────────────────────────────────────────────
  //
  // Always on: the master password is kept in the secret store so the vault can
  // auto-unlock on a cold start (after the app is fully quit), as long as the
  // last *manual* unlock is within [maxAge]. A real manual unlock refreshes the
  // timestamp (via [recordManualUnlock]); an auto-unlock must NOT, otherwise
  // the hard cap could never be reached.

  /// Records a manual unlock: refreshes the stored password and resets the
  /// last-manual-unlock timestamp that the [maxAge] hard cap is measured
  /// against.
  ///
  /// Call this ONLY from a genuine manual unlock (typed password, biometric or
  /// PIN), never from a persistent auto-unlock.
  Future<void> recordManualUnlock(
    String vaultPath,
    String masterPassword, {
    DateTime? now,
  }) async {
    await _secrets.write(_persistPassKey(vaultPath), masterPassword);
    await _writeFlag(
      _persistAtKey(vaultPath),
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch.toString(),
    );
  }

  /// The stored master password for a cold-start auto-unlock, or null when no
  /// token is stored or the last manual unlock is older than [maxAge]. When
  /// expired, the stored token is purged so the next manual unlock re-arms it.
  Future<String?> getPersistentUnlockPassword(
    String vaultPath, {
    required Duration maxAge,
    DateTime? now,
  }) async {
    final atRaw = await _readFlag(_persistAtKey(vaultPath));
    final atMs = int.tryParse(atRaw ?? '');
    if (atMs == null) return null;
    final lastManual = DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true);
    final current = (now ?? DateTime.now()).toUtc();
    if (current.difference(lastManual) > maxAge) {
      // Hard cap exceeded — purge the at-rest token.
      await _secrets.delete(_persistPassKey(vaultPath));
      await _writeFlag(_persistAtKey(vaultPath), null);
      return null;
    }
    return _secrets.read(_persistPassKey(vaultPath));
  }

  /// The last manual-unlock instant, or null when unset. Exposed for UI that
  /// wants to show when the vault will require a manual unlock again.
  Future<DateTime?> getLastManualUnlockAt(String vaultPath) async {
    final atMs = int.tryParse(await _readFlag(_persistAtKey(vaultPath)) ?? '');
    if (atMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(atMs, isUtc: true);
  }

  /// Purges the stored password/timestamp for this vault (e.g. on removal).
  Future<void> clearPersistentUnlock(String vaultPath) async {
    await _secrets.delete(_persistPassKey(vaultPath));
    await _writeFlag(_persistAtKey(vaultPath), null);
  }

  // ── Migration ────────────────────────────────────────────────────────────────

  /// One-time migration of unlock data from a legacy [oldVaultPath]-derived
  /// identity to a stable [newVaultId]-derived identity.
  ///
  /// Historically the storage keys were derived from the vault's absolute file
  /// path. On iOS that path embeds the app container UUID, which rotates across
  /// updates, orphaning the stored biometric/PIN data. Vaults are now keyed by
  /// their stable record id instead. This copies any data still reachable under
  /// the old path-based keys over to the new id-based keys.
  ///
  /// Legacy enabled-flags always lived in [_preferences] (SharedPreferences),
  /// regardless of [_storeFlagsInSecrets], so the old flags are read from there
  /// directly while old secrets are read from the keychain.
  ///
  /// Safe to call on every launch: it does nothing once it has run for a vault
  /// (tracked by a per-id marker), and it never overwrites data already present
  /// under the new identity. Returns true if data was migrated.
  Future<bool> migrateVaultIdentity({
    required String oldVaultPath,
    required String newVaultId,
  }) async {
    if (oldVaultPath == newVaultId) return false;

    // Already migrated for this vault — nothing to do.
    if (await _readFlag(_migratedKey(newVaultId)) == 'true') return false;

    var migratedAny = false;

    // Biometric: only migrate when nothing is set under the new identity yet.
    final newBioEnabled = await _readFlag(_bioEnabledKey(newVaultId));
    if (newBioEnabled != 'true') {
      final oldBioEnabled =
          await _preferences.read(_bioEnabledKey(oldVaultPath));
      final oldBioPass = await _secrets.read(_bioPassKey(oldVaultPath));
      if (oldBioEnabled == 'true' && oldBioPass != null) {
        await _secrets.write(_bioPassKey(newVaultId), oldBioPass);
        await _writeFlag(_bioEnabledKey(newVaultId), 'true');
        migratedAny = true;
      }
    }

    // PIN: requires the hash, salt and stored password to all be present.
    final newPinEnabled = await _readFlag(_pinEnabledKey(newVaultId));
    if (newPinEnabled != 'true') {
      final oldPinEnabled =
          await _preferences.read(_pinEnabledKey(oldVaultPath));
      final oldHash = await _secrets.read(_pinHashKey(oldVaultPath));
      final oldSalt = await _secrets.read(_pinSaltKey(oldVaultPath));
      final oldPinPass = await _secrets.read(_pinPassKey(oldVaultPath));
      if (oldPinEnabled == 'true' &&
          oldHash != null &&
          oldSalt != null &&
          oldPinPass != null) {
        await _secrets.write(_pinHashKey(newVaultId), oldHash);
        await _secrets.write(_pinSaltKey(newVaultId), oldSalt);
        await _secrets.write(_pinPassKey(newVaultId), oldPinPass);
        await _writeFlag(_pinEnabledKey(newVaultId), 'true');
        migratedAny = true;
      }
    }

    // Carry over the last-used method hint when present and not already set.
    final newLast = await _readFlag(_lastUnlockMethodKey(newVaultId));
    if (newLast == null) {
      final oldLast =
          await _preferences.read(_lastUnlockMethodKey(oldVaultPath));
      if (oldLast != null) {
        await _writeFlag(_lastUnlockMethodKey(newVaultId), oldLast);
      }
    }

    await _writeFlag(_migratedKey(newVaultId), 'true');
    return migratedAny;
  }
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
