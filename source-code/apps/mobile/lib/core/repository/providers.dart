import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kdbx/kdbx.dart' as native;
import 'package:lumenpass_core/lumenpass_core.dart';

import '../services/local_storage_service.dart';
import '../services/secure_storage_service.dart';

final localStorageProvider = Provider<LocalStorageService>(
  (ref) => LocalStorageService(),
);

final secureStorageProvider = Provider<SecureStorageService>(
  (ref) => SecureStorageService(),
);

final kdbxRepositoryProvider = Provider<KdbxRepository>(
  (ref) => KdbxRepositoryImpl(
    format: native.KdbxFormat(const IsolateArgon2()),
    totpService: const TOTPService(),
  ),
);

final activeDatabaseProvider = StateProvider<KdbxDatabase?>((ref) => null);

final cachedMasterPasswordProvider = StateProvider<String?>((ref) => null);

/// Hard ceiling for persistent ("stay unlocked") auto-unlock. Even with the
/// feature enabled, the vault force-locks and requires a manual unlock once
/// this long has elapsed since the last *manual* unlock. Independent of the
/// in-session auto-lock timeout, which measures inactivity while the app runs.
const persistentUnlockMaxAge = Duration(days: 14);

final vaultUnlockServiceProvider = Provider<VaultUnlockService>((ref) {
  return VaultUnlockService(
    preferences: ref.read(localStorageProvider),
    secrets: ref.read(secureStorageProvider),
    // Keep the enabled flags in the keychain alongside the password so both
    // survive together (platform key-value storage is wiped on reinstall while
    // the keychain persists).
    storeFlagsInSecrets: true,
  );
});
