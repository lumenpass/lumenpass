import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/unlock/application/database_registry.dart';
import '../../features/unlock/application/unlock_controller.dart';
import '../../features/vault/application/vault_providers.dart';
import '../../features/vault/presentation/vault_screen.dart';
import '../models/database_record.dart';
import '../repository/database_save_sync.dart';
import '../repository/kdbx_repository_provider.dart';
import 'biometric_auth_service.dart';
import 'browser_extension_service.dart';
import 'cloud_sync_service.dart';
import 'ssh_agent_service.dart' show navigatorKey;
import 'tray_action_provider.dart';
import 'vault_preferences.dart';
import 'vault_unlock_service.dart';

final browserExtensionServiceProvider =
    Provider<BrowserExtensionService>((ref) {
  final repository = ref.watch(kdbxRepositoryProvider);
  return BrowserExtensionService(
    repository: repository,
    getDomainSetting: () => ref.read(vaultDomainSettingProvider),
    getDisabledAutofillDomains: () =>
        ref.read(vaultDisabledAutofillDomainsProvider),
    setDisabledAutofillDomains: (domains) async {
      final pruned = pruneDisabledAutofillDomains(domains);
      ref.read(vaultDisabledAutofillDomainsProvider.notifier).state = pruned;
      final storage = ref.read(localStorageProvider);
      await storage.write(
        key: vaultDisabledAutofillDomainsKey,
        value: jsonEncode(pruned.map((e) => e.toJson()).toList()),
      );
    },
    onFocusRequest: () {
      const MethodChannel('lumenpass/window')
          .invokeMethod<void>('bringToFront')
          .catchError((_) {});
    },
    onOpenNewItemRequest: () {
      ref.read(pendingTrayActionProvider.notifier).state = TrayAction.newItem;
    },
    onOpenEditItemRequest: (entryUuid) {
      ref.read(pendingEditItemRequestProvider.notifier).state = entryUuid;
    },
    onAfterSave: () async {
      final latestDatabase = repository.currentDatabase;
      if (latestDatabase != null) {
        ref.invalidate(vaultDatabaseEntriesProvider);
        ref.invalidate(vaultScopedEntriesProvider);
        ref.invalidate(vaultEntriesProvider);
        ref.read(activeDatabaseProvider.notifier).state = latestDatabase;
        ref.read(vaultRefreshTriggerProvider.notifier).state++;
      }

      // Use the repository’s open path (same source as [saveDatabase]) so we
      // stay in sync even if [activeDatabaseProvider] is briefly null/stale.
      final vaultPath = repository.currentDatabase?.path;
      if (vaultPath == null || vaultPath.isEmpty) {
        debugPrint(
          '[Browser extension] onAfterSave: no currentDatabase.path — '
          'cloud upload skipped',
        );
        return;
      }

      await ref.read(databaseRegistryProvider.notifier).ready;

      final registry = ref.read(databaseRegistryProvider);
      DatabaseRecord? record;
      for (final r in registry) {
        if (databasePathsReferToSameVault(r.databasePath, vaultPath)) {
          record = r;
          break;
        }
      }

      if (record == null) {
        debugPrint(
          '[Browser extension] onAfterSave: no registry row for '
          '"$vaultPath" (${registry.length} registered) — cloud upload skipped',
        );
        return;
      }

      // Same path as [saveAndSyncDatabase]: coalesced upload + dirty flag.
      CloudSyncService.instance.scheduleUpload(record).ignore();
    },
    getUnlockOptions: () => _readUnlockOptions(ref),
    unlockWithPassword: (password) => _unlockWithPassword(ref, password),
    unlockWithPin: (pin) => _unlockWithPin(ref, pin),
    unlockWithBiometric: () => _unlockWithBiometric(ref),
  );
});

// ─── Extension-driven unlock helpers ──────────────────────────────────────────

Future<BridgeUnlockOptions> _readUnlockOptions(Ref ref) async {
  final unlockState = ref.read(unlockControllerProvider);
  final vaultPath = unlockState.databasePath;
  if (vaultPath == null || vaultPath.isEmpty) {
    return const BridgeUnlockOptions(vaultReady: false);
  }

  // Ensure the registry has finished loading from disk before we decide
  // whether the `databasePath` still references a valid vault. Without this
  // we might incorrectly report `vaultReady: false` during app startup, or
  // `vaultReady: true` for a vault that the user already removed.
  try {
    await ref.read(databaseRegistryProvider.notifier).ready;
  } catch (_) {
    // Ignore — fall through and treat as unknown registry state.
  }

  final registry = ref.read(databaseRegistryProvider);
  DatabaseRecord? record;
  for (final r in registry) {
    if (databasePathsReferToSameVault(r.databasePath, vaultPath)) {
      record = r;
      break;
    }
  }

  // If the registry is loaded but the vault is no longer registered, don't
  // surface stale metadata (name/PIN/biometric) to the extension. The user
  // needs to pick or import a vault on desktop first.
  if (record == null) {
    return const BridgeUnlockOptions(vaultReady: false);
  }

  // For local vaults (or locally-cached cloud vaults), the file on disk
  // must still exist — otherwise the extension cannot actually unlock it.
  try {
    if (!await File(vaultPath).exists()) {
      final hasCloudBackup = record.storageType != 'local' &&
          (record.cloudFileId?.isNotEmpty ?? false);
      if (!hasCloudBackup) {
        return const BridgeUnlockOptions(vaultReady: false);
      }
    }
  } catch (_) {
    return const BridgeUnlockOptions(vaultReady: false);
  }

  final unlockSvc = ref.read(vaultUnlockServiceProvider);
  final bio = ref.read(biometricAuthServiceProvider);

  final results = await Future.wait<bool>([
    unlockSvc.isPinEnabled(vaultPath),
    unlockSvc.isBiometricEnabled(vaultPath),
    bio.isAvailable(),
  ]);

  final vaultName =
      record.nickname.isNotEmpty ? record.nickname : _fileBasename(vaultPath);

  final last = await unlockSvc.getLastUnlockMethod(vaultPath);
  return BridgeUnlockOptions(
    vaultReady: true,
    vaultName: vaultName,
    hasPin: results[0],
    hasBiometric: results[1],
    biometricAvailable: results[1] && results[2],
    lastMethod: last.name,
  );
}

Future<BridgeUnlockResult> _unlockWithPassword(Ref ref, String password) async {
  try {
    final ok =
        await ref.read(unlockControllerProvider.notifier).unlock(password);
    if (ok) {
      _navigateToVaultScreen();
      return const BridgeUnlockResult(ok: true);
    }
    final err = ref.read(unlockControllerProvider).errorMessage;
    return BridgeUnlockResult(
      ok: false,
      error: err ?? 'Incorrect password.',
    );
  } catch (e) {
    return BridgeUnlockResult(ok: false, error: e.toString());
  }
}

Future<BridgeUnlockResult> _unlockWithPin(Ref ref, String pin) async {
  try {
    final ok =
        await ref.read(unlockControllerProvider.notifier).unlockWithPin(pin);
    if (ok) {
      _navigateToVaultScreen();
      return const BridgeUnlockResult(ok: true);
    }
    final err = ref.read(unlockControllerProvider).errorMessage;
    return BridgeUnlockResult(
      ok: false,
      error: err ?? 'Incorrect PIN.',
    );
  } catch (e) {
    return BridgeUnlockResult(ok: false, error: e.toString());
  }
}

Future<BridgeUnlockResult> _unlockWithBiometric(Ref ref) async {
  try {
    final ok =
        await ref.read(unlockControllerProvider.notifier).unlockWithBiometric();
    if (ok) {
      _navigateToVaultScreen();
      return const BridgeUnlockResult(ok: true);
    }
    final err = ref.read(unlockControllerProvider).errorMessage;
    return BridgeUnlockResult(
      ok: false,
      error: err ??
          (Platform.isWindows
              ? 'Windows Hello unlock was cancelled or failed.'
              : 'Biometric unlock was cancelled or failed.'),
    );
  } catch (e) {
    return BridgeUnlockResult(ok: false, error: e.toString());
  }
}

/// Push [VaultScreen] and clear any modal dialogs left over from a concurrent
/// unlock prompt. Safe to call multiple times.
void _navigateToVaultScreen() {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  try {
    nav.pushNamedAndRemoveUntil(VaultScreen.routeName, (_) => false);
  } catch (e) {
    debugPrint('[Browser extension] navigate to vault failed: $e');
  }
}

String _fileBasename(String path) {
  final separator = Platform.pathSeparator;
  final idx = path.lastIndexOf(separator);
  final raw = idx >= 0 ? path.substring(idx + 1) : path;
  final dot = raw.lastIndexOf('.');
  return dot > 0 ? raw.substring(0, dot) : raw;
}
