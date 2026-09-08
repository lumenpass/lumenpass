import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for cloud-provider credentials (OAuth tokens, passwords,
/// API keys) on desktop platforms.
///
/// Desktop apps previously stored these credentials in [LocalStorageProvider]
/// (a plain key-value store on disk). This class migrates them to the OS
/// keychain (macOS Keychain / Windows Credential Manager / Linux Secret
/// Service) via `flutter_secure_storage`, matching the protection mobile
/// apps already have.
///
/// ## Migration
///
/// Call [migrateFrom] once during app startup with the legacy
/// [LocalStorageProvider] reference. It:
///  1. Reads each known sensitive key from the legacy store.
///  2. If a value exists and is not already in the secure store, writes it.
///  3. Deletes the legacy copy so the migration only runs once.
class CloudTokenStore {
  CloudTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? _createDefault();

  static FlutterSecureStorage _createDefault() {
    return const FlutterSecureStorage(
      mOptions: MacOsOptions(useDataProtectionKeyChain: false),
    );
  }

  final FlutterSecureStorage _storage;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Reads a value previously stored under [key], or `null` if absent.
  Future<String?> read(String key) => _storage.read(key: key);

  /// Persists [value] under [key]. Pass `null` to delete.
  Future<void> write(String key, String? value) {
    if (value == null) {
      return _storage.delete(key: key);
    }
    return _storage.write(key: key, value: value);
  }

  /// Deletes a single key.
  Future<void> delete(String key) => _storage.delete(key: key);

  /// Migrates credentials from the legacy [LocalStorageProvider] to the
  /// secure store, for all known sensitive keys. Call once during app init.
  ///
  /// [legacyRead] should delegate to `localStorageProvider.read(key: …)` and
  /// [legacyDelete] to `localStorageProvider.delete(key: …)`.
  Future<void> migrateFrom({
    required Future<String?> Function(String key) legacyRead,
    required Future<void> Function(String key) legacyDelete,
    required List<String> sensitiveKeys,
  }) async {
    for (final key in sensitiveKeys) {
      try {
        final legacyValue = await legacyRead(key);
        if (legacyValue == null) continue;

        final alreadySecure = await _storage.read(key: key);
        if (alreadySecure != null) {
          // Secure store already has a value — clean up the legacy copy so
          // it does not linger on disk.
          await legacyDelete(key);
          continue;
        }

        await _storage.write(key: key, value: legacyValue);
        await legacyDelete(key);
        debugPrint(
          '[CloudTokenStore] Migrated "$key" from legacy storage to keychain.',
        );
      } catch (e) {
        debugPrint('[CloudTokenStore] Migration error for "$key": $e');
      }
    }
  }
}
