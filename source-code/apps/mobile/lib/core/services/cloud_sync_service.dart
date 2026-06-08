import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;

import '../repository/providers.dart';
import 'cloud_database_service.dart';
import 'local_storage_service.dart';

enum CloudSyncPhase { idle, uploading, downloading, error }

class CloudSyncStatus {
  const CloudSyncStatus({
    required this.path,
    required this.phase,
    this.error,
    this.dirty = false,
  });

  const CloudSyncStatus.idle(String path)
      : this(path: path, phase: CloudSyncPhase.idle);

  final String path;
  final CloudSyncPhase phase;
  final Object? error;
  final bool dirty;

  bool get isBusy =>
      phase == CloudSyncPhase.uploading || phase == CloudSyncPhase.downloading;
}

class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  static const _dirtyKeyPrefix = 'cloud_sync_dirty_v1:';
  static const _logTag = '[CloudSync]';

  LocalStorageService? _storage;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Map<String, CloudSyncStatus> _statuses = <String, CloudSyncStatus>{};
  final StreamController<CloudSyncStatus> _statusController =
      StreamController<CloudSyncStatus>.broadcast();

  Stream<CloudSyncStatus> get statusStream => _statusController.stream;

  CloudSyncStatus statusFor(String path) =>
      _statuses[path] ?? CloudSyncStatus.idle(path);

  void attach(LocalStorageService storage) {
    _storage ??= storage;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> scheduleUpload(DatabaseRecord record) async {
    if (!_isCloudBacked(record)) return;

    _log(
      'scheduleUpload ${record.storageType} '
      'path=${_shortPath(record.databasePath)} '
      'fileId=${_maskId(record.cloudFileId)} '
      'inFlight=${_inFlight.containsKey(record.databasePath)}',
    );

    await _setDirty(record.databasePath, true);
    return _ensureLoop(record);
  }

  Future<void> awaitPending(String path) async {
    final future = _inFlight[path];
    if (future == null) return;
    try {
      await future;
    } catch (_) {}
  }

  Future<bool> isDirty(String path) async {
    final storage = _storage;
    if (storage == null) return false;
    final v = await storage.read(_dirtyKey(path));
    return v == 'true';
  }

  Future<void> refreshFromCloud(DatabaseRecord record) async {
    if (!_isCloudBacked(record)) return;

    _log(
      'refreshFromCloud start ${record.storageType} '
      '${_shortPath(record.databasePath)}',
    );

    await awaitPending(record.databasePath);

    if (await isDirty(record.databasePath)) {
      _log('refreshFromCloud — vault still dirty, pushing first');
      try {
        await _ensureLoop(record);
        _log('refreshFromCloud — retry push succeeded, skipping download');
      } catch (e) {
        final isPermError = e.toString().contains('403') ||
            e.toString().contains('has not granted the app') ||
            e.toString().contains('insufficientPermissions');
        if (isPermError) {
          _log(
            'refreshFromCloud — push failed with permission error, '
            'continuing with download anyway: $e',
          );
        } else {
          _log('refreshFromCloud ABORTED — pending upload retry failed: $e');
          return;
        }
      }
    }

    try {
      _emit(CloudSyncStatus(
        path: record.databasePath,
        phase: CloudSyncPhase.downloading,
      ));
      final remoteModified = await _fetchRemoteModifiedTime(record);
      final localFile = File(record.databasePath);
      DateTime? localModified;
      if (await localFile.exists()) {
        localModified = (await localFile.stat()).modified;
      }

      final shouldDownload = localModified == null ||
          remoteModified == null ||
          remoteModified.isAfter(localModified);

      if (!shouldDownload) {
        _emit(CloudSyncStatus.idle(record.databasePath));
        return;
      }

      final Uint8List bytes;
      switch (record.storageType) {
        case 'googleDrive':
          bytes = await CloudDatabaseService.instance
              .downloadGoogleDriveFile(record.cloudFileId!);
        case 'dropbox':
          bytes = await CloudDatabaseService.instance
              .downloadDropboxFile(record.cloudFileId!);
        case 'oneDrive':
          bytes = await CloudDatabaseService.instance
              .downloadOneDriveFile(record.cloudFileId!);
        case 'webdav':
          bytes = await CloudDatabaseService.instance
              .downloadWebDavFile(record.cloudFileId!);
        case 'sftp':
          bytes = await CloudDatabaseService.instance
              .downloadSftpFile(record.cloudFileId!);
        case 's3':
          bytes = await CloudDatabaseService.instance
              .downloadS3File(record.cloudFileId!);
        default:
          _emit(CloudSyncStatus.idle(record.databasePath));
          return;
      }

      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(bytes, flush: true);
      await _setDirty(record.databasePath, false);
      _log('refreshFromCloud pulled ${bytes.length} bytes');
      _emit(CloudSyncStatus.idle(record.databasePath));
    } catch (e, stack) {
      _log('refreshFromCloud FAILED: $e\n$stack');
      _emit(CloudSyncStatus(
        path: record.databasePath,
        phase: CloudSyncPhase.error,
        error: e,
        dirty: await isDirty(record.databasePath),
      ));
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<void> _ensureLoop(DatabaseRecord record) {
    final path = record.databasePath;
    final existing = _inFlight[path];
    if (existing != null) return existing;

    final completer = Completer<void>();
    _inFlight[path] = completer.future;
    unawaited(_runLoop(record, completer));
    return completer.future;
  }

  Future<void> _runLoop(
      DatabaseRecord record, Completer<void> completer) async {
    final path = record.databasePath;
    Object? lastError;
    try {
      while (await isDirty(path)) {
        try {
          await _performUpload(record);
          lastError = null;
        } catch (e) {
          lastError = e;
          _log('runLoop FAILED ${_shortPath(path)}: $e');
          break;
        }
      }
    } finally {
      _inFlight.remove(path);
      if (lastError != null) {
        _emit(CloudSyncStatus(
          path: path,
          phase: CloudSyncPhase.error,
          error: lastError,
          dirty: true,
        ));
        completer.completeError(lastError);
      } else {
        _emit(CloudSyncStatus.idle(path));
        completer.complete();
      }
    }
  }

  Future<void> _performUpload(DatabaseRecord record) async {
    _emit(CloudSyncStatus(
      path: record.databasePath,
      phase: CloudSyncPhase.uploading,
      dirty: true,
    ));

    final file = File(record.databasePath);
    if (!await file.exists()) {
      throw StateError('Local database missing at ${record.databasePath}');
    }
    final bytes = await file.readAsBytes();
    final fileName = record.cloudFileName ?? p.basename(record.databasePath);
    final fileId = record.cloudFileId;
    if (fileId == null || fileId.isEmpty) {
      throw StateError('Record has no cloudFileId');
    }

    switch (record.storageType) {
      case 'googleDrive':
        await CloudDatabaseService.instance
            .updateGoogleDriveFile(fileId, bytes, fileName);
      case 'dropbox':
        await CloudDatabaseService.instance.uploadToDropbox(bytes, fileId);
      case 'oneDrive':
        await CloudDatabaseService.instance
            .updateOneDriveFile(fileId, bytes, fileName);
      case 'webdav':
        await CloudDatabaseService.instance.updateWebDavFile(fileId, bytes);
      case 'sftp':
        await CloudDatabaseService.instance.updateSftpFile(fileId, bytes);
      case 's3':
        await CloudDatabaseService.instance.updateS3File(fileId, bytes);
      default:
        throw StateError(
          'Unsupported cloud storageType: ${record.storageType}',
        );
    }

    await _setDirty(record.databasePath, false);
    _log('upload ✓ ${record.storageType} size=${bytes.length}');
  }

  Future<DateTime?> _fetchRemoteModifiedTime(DatabaseRecord record) async {
    try {
      switch (record.storageType) {
        case 'googleDrive':
          return await CloudDatabaseService.instance
              .getGoogleDriveFileModifiedTime(record.cloudFileId!);
        case 'dropbox':
          return await CloudDatabaseService.instance
              .getDropboxFileModifiedTime(record.cloudFileId!);
        case 'oneDrive':
          return await CloudDatabaseService.instance
              .getOneDriveFileModifiedTime(record.cloudFileId!);
        case 'webdav':
          return await CloudDatabaseService.instance
              .getWebDavFileModifiedTime(record.cloudFileId!);
        case 'sftp':
          return await CloudDatabaseService.instance
              .getSftpFileModifiedTime(record.cloudFileId!);
        case 's3':
          return await CloudDatabaseService.instance
              .getS3FileModifiedTime(record.cloudFileId!);
      }
    } catch (e) {
      _log('remote mtime lookup failed: $e');
    }
    return null;
  }

  bool _isCloudBacked(DatabaseRecord record) {
    if (record.storageType != 'googleDrive' &&
        record.storageType != 'dropbox' &&
        record.storageType != 'oneDrive' &&
        record.storageType != 'webdav' &&
        record.storageType != 'sftp' &&
        record.storageType != 's3') {
      return false;
    }
    // Premium-only providers (OneDrive / WebDAV) stop syncing for non-Premium
    // or signed-out users — the in-process analog of a 401/403 from a gated
    // backend endpoint. Holds even if the vault was registered while Premium
    // and the plan later lapsed.
    if (!CloudDatabaseService.instance
        .isCloudProviderAccessible(record.storageType)) {
      _log(
        'sync blocked — ${record.storageType} requires Premium '
        '(${_shortPath(record.databasePath)})',
      );
      return false;
    }
    final fileId = record.cloudFileId;
    return fileId != null && fileId.isNotEmpty;
  }

  Future<void> _setDirty(String path, bool dirty) async {
    final storage = _storage;
    if (storage == null) return;
    if (dirty) {
      await storage.write(_dirtyKey(path), 'true');
    } else {
      await storage.delete(_dirtyKey(path));
    }

    final current = _statuses[path];
    if (current != null && current.dirty != dirty) {
      _emit(CloudSyncStatus(
        path: path,
        phase: current.phase,
        error: current.error,
        dirty: dirty,
      ));
    }
  }

  String _dirtyKey(String path) {
    final hash = sha1.convert(utf8.encode(path)).toString();
    return '$_dirtyKeyPrefix$hash';
  }

  void _emit(CloudSyncStatus status) {
    _statuses[status.path] = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _log(String message) {
    debugPrint('$_logTag $message');
  }

  String _shortPath(String path) {
    final parts = p.split(path);
    if (parts.length <= 3) return path;
    return p.joinAll(['…', ...parts.sublist(parts.length - 3)]);
  }

  String _maskId(String? id) {
    if (id == null || id.isEmpty) return '(none)';
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }
}

final cloudSyncStatusProvider =
    StreamProvider.family<CloudSyncStatus, String>((ref, path) async* {
  yield CloudSyncService.instance.statusFor(path);
  yield* CloudSyncService.instance.statusStream
      .where((status) => status.path == path);
});

void initCloudSyncService(ProviderContainer container) {
  CloudSyncService.instance
      .attach(container.read(localStorageProvider));
}
