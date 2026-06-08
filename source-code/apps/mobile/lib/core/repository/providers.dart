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
    format: native.KdbxFormat(),
    totpService: const TOTPService(),
  ),
);

final activeDatabaseProvider = StateProvider<KdbxDatabase?>((ref) => null);

final cachedMasterPasswordProvider = StateProvider<String?>((ref) => null);

final vaultUnlockServiceProvider = Provider<VaultUnlockService>((ref) {
  return VaultUnlockService(
    preferences: ref.read(localStorageProvider),
    secrets: ref.read(secureStorageProvider),
  );
});
