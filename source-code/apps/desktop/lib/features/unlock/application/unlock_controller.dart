import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/database_record.dart';
import '../../../core/repository/database_save_sync.dart';
import '../../../core/repository/kdbx_repository_provider.dart';
import '../../../core/repository/vault_write_scheduler_provider.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/biometric_auth_service.dart';
import '../../../core/services/cloud_sync_service.dart';

import '../../../core/services/tray_service.dart';
import '../../../core/services/vault_unlock_service.dart';
import 'database_registry.dart';

class UnlockState {
  const UnlockState({
    this.isLoading = false,
    this.isRestoring = false,
    this.rememberMe = false,
    this.databasePath,
    this.keyFilePath,
    this.errorMessage,
  });

  final bool isLoading;
  final bool isRestoring;
  final bool rememberMe;
  final String? databasePath;
  final String? keyFilePath;
  final String? errorMessage;

  UnlockState copyWith({
    bool? isLoading,
    bool? isRestoring,
    bool? rememberMe,
    String? databasePath,
    String? keyFilePath,
    String? errorMessage,
    bool clearDatabasePath = false,
    bool clearKeyFilePath = false,
    bool clearError = false,
  }) {
    return UnlockState(
      isLoading: isLoading ?? this.isLoading,
      isRestoring: isRestoring ?? this.isRestoring,
      rememberMe: rememberMe ?? this.rememberMe,
      databasePath:
          clearDatabasePath ? null : databasePath ?? this.databasePath,
      keyFilePath: clearKeyFilePath ? null : keyFilePath ?? this.keyFilePath,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final unlockControllerProvider =
    StateNotifierProvider<UnlockController, UnlockState>(
  (ref) => UnlockController(ref),
);

/// Orchestrates the unlock flow, including file selection and persistence.
class UnlockController extends StateNotifier<UnlockState> {
  UnlockController(this._ref) : super(const UnlockState());

  static const String _rememberMeKey = 'unlock_remember_me';
  static const String _databasePathKey = 'unlock_database_path';
  // Legacy global key — read once during migration, then cleared.
  static const String _legacyKeyFilePathKey = 'unlock_keyfile_path';
  static const String _keyFilePathPrefix = 'unlock_keyfile_path:';

  final Ref _ref;

  String _keyFileStorageKey(String databasePath) =>
      '$_keyFilePathPrefix$databasePath';

  Future<void> loadRememberedSession() async {
    state = state.copyWith(isRestoring: true, clearError: true);
    try {
      final storage = _ref.read(localStorageProvider);
      final rememberMe = await storage.read(key: _rememberMeKey) == 'true';
      if (!rememberMe) {
        state = state.copyWith(
          isRestoring: false,
          rememberMe: false,
          clearDatabasePath: true,
          clearKeyFilePath: true,
        );
        return;
      }

      final databasePath = await storage.read(key: _databasePathKey);
      String? keyFilePath;
      if (databasePath != null && databasePath.isNotEmpty) {
        keyFilePath = await storage.read(key: _keyFileStorageKey(databasePath));
        // One-time migration from the legacy global keyfile key. If the
        // current vault has no per-vault entry yet but the legacy global
        // key still holds a value, adopt it for this vault and then drop
        // the legacy key so it can never bleed into another vault.
        if (keyFilePath == null || keyFilePath.isEmpty) {
          final legacy = await storage.read(key: _legacyKeyFilePathKey);
          if (legacy != null && legacy.isNotEmpty) {
            await storage.write(
              key: _keyFileStorageKey(databasePath),
              value: legacy,
            );
            keyFilePath = legacy;
          }
        }
        await storage.delete(key: _legacyKeyFilePathKey);
      } else {
        await storage.delete(key: _legacyKeyFilePathKey);
      }

      state = state.copyWith(
        isRestoring: false,
        rememberMe: true,
        databasePath: databasePath,
        keyFilePath: keyFilePath,
      );
    } catch (error) {
      state = state.copyWith(
        isRestoring: false,
        errorMessage: 'Unable to restore the previous unlock state: $error',
      );
    }
  }

  Future<void> toggleRememberMe(bool value) async {
    state = state.copyWith(rememberMe: value, clearError: true);
    if (value) {
      await _persistRememberedState();
      return;
    }
    await _clearRememberedState();
  }

  void setDatabasePath(String path) {
    state = state.copyWith(databasePath: path, clearError: true);
  }

  /// Resets in-memory unlock state for a freshly chosen vault so no fields
  /// (keyfile, error) bleed in from a previously selected database, then
  /// reloads the per-vault remembered keyfile (if any) from secure storage.
  Future<void> resetForNewVault(String path) async {
    state = const UnlockState().copyWith(databasePath: path);
    try {
      final storage = _ref.read(localStorageProvider);
      final rememberMe = await storage.read(key: _rememberMeKey) == 'true';
      String? keyFilePath;
      if (rememberMe) {
        keyFilePath = await storage.read(key: _keyFileStorageKey(path));
      }
      state = state.copyWith(
        rememberMe: rememberMe,
        databasePath: path,
        keyFilePath: keyFilePath,
      );
    } catch (_) {}
  }

  Future<void> selectDatabaseFile() async {
    await _pickFile(
      title: 'Choose KeePass Database',
      allowedExtensions: const <String>['kdbx', 'kdb'],
      onSelected: (path) => state = state.copyWith(
        databasePath: path,
        clearError: true,
      ),
    );
  }

  Future<void> selectKeyFile() async {
    await _pickFile(
      title: 'Choose Key File',
      allowedExtensions: const <String>['key', 'keyx', 'xml', 'txt'],
      onSelected: (path) => state = state.copyWith(
        keyFilePath: path,
        clearError: true,
      ),
    );
  }

  void clearDatabaseFile() {
    state = state.copyWith(clearDatabasePath: true, clearError: true);
  }

  void clearKeyFile() {
    state = state.copyWith(clearKeyFilePath: true, clearError: true);
  }

  void clearError() {
    if (state.errorMessage == null) {
      return;
    }
    state = state.copyWith(clearError: true);
  }

  Future<bool> unlock(String password) async {
    // Password entry implies "master password" unlock, so clear the UX hint.
    return _unlockWithPassword(
      password,
      method: VaultLastUnlockMethod.none,
    );
  }

  Future<bool> _unlockWithPassword(
    String password, {
    required VaultLastUnlockMethod method,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    final databasePath = state.databasePath;
    if (databasePath == null || databasePath.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Select a KeePass database before unlocking.',
      );
      return false;
    }

    try {
      final keyFilePath = state.keyFilePath;
      final keyFileBytes = keyFilePath != null && keyFilePath.isNotEmpty
          ? await File(keyFilePath).readAsBytes()
          : null;

      await _refreshCloudDatabaseIfNeeded(databasePath);

      final database = await _ref.read(kdbxRepositoryProvider).openDatabase(
            databasePath: databasePath,
            password: password,
            keyFileBytes: keyFileBytes,
          );

      // Fresh in-memory database: drop any stale pending-write state left
      // over from the previous session.
      _ref.read(vaultWriteSchedulerProvider).reset();
      _ref.read(activeDatabaseProvider.notifier).state = database;
      _ref.read(cachedMasterPasswordProvider.notifier).state = password;
      BackupService.instance.resumeForUnlockedVault();
      // SshAgentService's listener on `activeDatabaseProvider` will push
      // the keys once — no need to call `syncKeys()` explicitly which
      // would duplicate the O(n) entry scan / setKeys IPC at unlock.

      // Persist the last unlock method as a UX hint for the next time.
      try {
        await _ref
            .read(vaultUnlockServiceProvider)
            .setLastUnlockMethod(databasePath, method);
      } catch (_) {}

      try {
        if (state.rememberMe) {
          await _persistRememberedState();
        } else {
          await _clearRememberedState();
        }
      } catch (error) {
        state = state.copyWith(
          errorMessage:
              'Vault unlocked, but remember-me could not save state: $error',
        );
      }

      state = state.copyWith(isLoading: false);
      unawaited(TrayService.instance.setVaultLocked(false));
      return true;
    } on MissingPluginException {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'This environment does not expose desktop plugins yet.',
      );
      return false;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  Future<void> _pickFile({
    required String title,
    required List<String> allowedExtensions,
    required void Function(String path) onSelected,
  }) async {
    try {
      final isMacOS = Platform.isMacOS;
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: title,
        lockParentWindow: true,
        // macOS file_picker relies on UTType-based filtering, which can be
        // unreliable for custom extensions such as `.kdbx`. We therefore allow
        // all files on macOS and validate the extension ourselves.
        type: isMacOS ? FileType.any : FileType.custom,
        allowedExtensions: isMacOS ? null : allowedExtensions,
        withData: false,
      );

      final path = result?.files.single.path;
      if (path != null && path.isNotEmpty) {
        final fileExtension = path.split('.').last.toLowerCase();
        if (!allowedExtensions.contains(fileExtension)) {
          state = state.copyWith(
            errorMessage:
                'Please choose a supported file type: ${allowedExtensions.join(', ')}',
          );
          return;
        }
        onSelected(path);
        if (state.rememberMe) {
          await _persistRememberedState();
        }
      }
    } on MissingPluginException {
      state = state.copyWith(
        errorMessage: '$title is unavailable in the current environment.',
      );
    } catch (error) {
      state = state.copyWith(errorMessage: 'Unable to pick a file: $error');
    }
  }

  /// Reconciles the local cache with the cloud copy for cloud-backed vaults.
  ///
  /// Delegates to [CloudSyncService.refreshFromCloud], which:
  ///   * awaits any in-flight upload (so a just-saved vault isn't overwritten
  ///     by a stale remote),
  ///   * retries a pending upload if the vault is still marked dirty from a
  ///     previous failed sync, preserving unsynced edits, and
  ///   * only pulls the remote copy when its `modifiedTime` is strictly
  ///     newer than the local cache's mtime.
  ///
  /// Never throws — falls back to the existing local cache on any error.
  Future<void> _refreshCloudDatabaseIfNeeded(String databasePath) async {
    final registry = _ref.read(databaseRegistryProvider);
    DatabaseRecord? record;
    for (final r in registry) {
      if (databasePathsReferToSameVault(r.databasePath, databasePath)) {
        record = r;
        break;
      }
    }
    if (record == null) {
      debugPrint(
          '[Unlock] no registry record for $databasePath — skip cloud refresh');
      return;
    }
    debugPrint(
      '[Unlock] cloud refresh check storage=${record.storageType} '
      'fileId=${record.cloudFileId == null || record.cloudFileId!.isEmpty ? '(none)' : '${record.cloudFileId!.substring(0, record.cloudFileId!.length.clamp(0, 4))}…'}',
    );
    await CloudSyncService.instance.refreshFromCloud(record);
  }

  Future<void> _persistRememberedState() async {
    try {
      final storage = _ref.read(localStorageProvider);
      final dbPath = state.databasePath;
      await storage.write(key: _rememberMeKey, value: '${state.rememberMe}');
      await storage.write(key: _databasePathKey, value: dbPath);

      if (dbPath == null || dbPath.isEmpty) {
        return;
      }
      final perVaultKey = _keyFileStorageKey(dbPath);
      if (state.keyFilePath == null || state.keyFilePath!.isEmpty) {
        await storage.delete(key: perVaultKey);
      } else {
        await storage.write(key: perVaultKey, value: state.keyFilePath);
      }
    } catch (_) {}
  }

  Future<void> _clearRememberedState() async {
    try {
      final storage = _ref.read(localStorageProvider);
      final dbPath = state.databasePath;
      await storage.delete(key: _rememberMeKey);
      await storage.delete(key: _databasePathKey);
      // Only drop the current vault's per-vault keyfile entry — never bulk-clear
      // every vault's stored keyfile path, which would punish other vaults.
      if (dbPath != null && dbPath.isNotEmpty) {
        await storage.delete(key: _keyFileStorageKey(dbPath));
      }
    } catch (_) {}
  }

  /// Authenticates via biometric, then retrieves the stored master password
  /// from the keychain and calls [unlock]. Returns true on success.
  Future<bool> unlockWithBiometric() async {
    final vaultPath = state.databasePath;
    if (vaultPath == null) return false;

    final bio = _ref.read(biometricAuthServiceProvider);
    final authenticated = await bio.authenticate(
      reason: Platform.isWindows
          ? 'Unlock your vault with Windows Hello'
          : 'Unlock your vault with biometrics',
    );
    if (!authenticated) return false;

    final unlockSvc = _ref.read(vaultUnlockServiceProvider);
    final password = await unlockSvc.getBiometricPassword(vaultPath);
    if (password == null) {
      state = state.copyWith(
        errorMessage: Platform.isWindows
            ? 'Windows Hello credentials not found. Please unlock with your master password.'
            : 'Biometric credentials not found. Please unlock with your master password.',
      );
      return false;
    }

    return _unlockWithPassword(
      password,
      method: VaultLastUnlockMethod.biometric,
    );
  }

  /// Verifies [pin] against the stored hash, then retrieves the master
  /// password and calls [unlock]. Returns true on success, false on wrong PIN
  /// or unlock error.
  Future<bool> unlockWithPin(String pin) async {
    final vaultPath = state.databasePath;
    if (vaultPath == null) return false;

    final unlockSvc = _ref.read(vaultUnlockServiceProvider);
    final password = await unlockSvc.getMasterPasswordForPin(vaultPath, pin);
    if (password == null) {
      return false;
    }

    return _unlockWithPassword(
      password,
      method: VaultLastUnlockMethod.pin,
    );
  }
}
