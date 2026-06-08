import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/database_record.dart';
import '../models/kdbx_database.dart';
import '../services/cloud_sync_service.dart';
import 'kdbx_repository.dart';

/// True when [registeredPath] and [openVaultPath] refer to the same file.
///
/// The registry and the open [KdbxDatabase] must resolve to one vault; strict
/// string equality fails on some platforms when paths differ only by
/// normalization (e.g. symlinks, `/private` prefixes on macOS).
bool databasePathsReferToSameVault(
    String registeredPath, String openVaultPath) {
  if (registeredPath == openVaultPath) return true;
  try {
    final a = p.normalize(File(registeredPath).absolute.path);
    final b = p.normalize(File(openVaultPath).absolute.path);
    if (a == b) return true;
    return p.equals(a, b);
  } catch (_) {
    return false;
  }
}

/// Persists the vault locally and, when the active database is backed by
/// cloud storage, hands off the upload to [CloudSyncService].
///
/// The local save still happens inline and any write error propagates to the
/// caller. The cloud upload is coalesced by path: if one is already running
/// this call simply flags the vault dirty and returns — [CloudSyncService]
/// keeps retrying until either the dirty flag clears or the attempt fails
/// with a surfaced error. Callers that need to know when the upload is done
/// can `await CloudSyncService.instance.awaitPending(database.path)`.
///
/// Drop-in replacement for `repository.saveDatabase()`.
Future<KdbxDatabase> saveAndSyncDatabase(
  KdbxRepository repository,
  List<DatabaseRecord> registry,
) async {
  final sw = Stopwatch()..start();
  final database = await repository.saveDatabase();
  final localElapsedMs = sw.elapsedMilliseconds;

  int? sizeBytes;
  try {
    sizeBytes = await File(database.path).length();
  } catch (_) {}

  DatabaseRecord? record;
  for (final r in registry) {
    if (databasePathsReferToSameVault(r.databasePath, database.path)) {
      record = r;
      break;
    }
  }

  if (record == null) {
    debugPrint(
      '[Save] no registry match for "${database.path}" '
      '(${registry.length} vaults registered) — cloud sync skipped',
    );
  }

  final storageType = record?.storageType ?? 'local';
  final cloudFileId = record?.cloudFileId;
  debugPrint(
    '[Save] ✓ local save in ${localElapsedMs}ms '
    'size=${_formatBytes(sizeBytes)} '
    'storage=$storageType '
    'cloudFileId=${_maskId(cloudFileId)} '
    'path=${p.basename(database.path)}',
  );

  if (record != null) {
    if (storageType == 'googleDrive' ||
        storageType == 'dropbox' ||
        storageType == 'oneDrive' ||
        storageType == 'webdav' ||
        storageType == 'sftp' ||
        storageType == 's3') {
      debugPrint(
        '[Save] → scheduling cloud sync ($storageType) '
        'fileId=${_maskId(cloudFileId)}',
      );
      // Fire-and-forget at the call site, but internally tracked + persisted
      // as a dirty flag so lock/unlock can await it and failed uploads are
      // retried automatically.
      CloudSyncService.instance.scheduleUpload(record).ignore();
    } else {
      debugPrint('[Save] local-only vault — no cloud sync');
    }
  }

  return database;
}

String _formatBytes(int? bytes) {
  if (bytes == null) return '?';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
}

String _maskId(String? id) {
  if (id == null || id.isEmpty) return '(none)';
  if (id.length <= 8) return id;
  return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
}
