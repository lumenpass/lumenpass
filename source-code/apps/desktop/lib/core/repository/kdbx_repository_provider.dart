import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kdbx/kdbx.dart' as native;

import '../models/kdbx_database.dart';
import '../services/local_storage_service.dart';
import '../services/password_generator_service.dart';
import '../services/totp_service.dart';
import 'kdbx_repository.dart';

final localStorageProvider = Provider<LocalStorageService>(
  (ref) => LocalStorageService(),
);

final totpServiceProvider = Provider<TOTPService>((ref) => const TOTPService());

final passwordGeneratorServiceProvider = Provider<PasswordGeneratorService>(
  (ref) => const PasswordGeneratorService(),
);

final kdbxRepositoryProvider = Provider<KdbxRepository>(
  (ref) => KdbxRepositoryImpl(
    format: native.KdbxFormat(),
    totpService: ref.watch(totpServiceProvider),
  ),
);

final activeDatabaseProvider = StateProvider<KdbxDatabase?>((ref) => null);

/// In-memory cache of the master password set after a successful vault unlock.
/// Cleared when the vault is locked or the app restarts.
/// Used by Settings to set up biometric / PIN unlock without re-prompting.
final cachedMasterPasswordProvider = StateProvider<String?>((ref) => null);
