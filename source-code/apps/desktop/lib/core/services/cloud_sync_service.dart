import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/database_record.dart';
import '../repository/kdbx_repository_provider.dart';
import '../../features/unlock/application/database_registry.dart';
import 'backup_service.dart';
import 'local_storage_service.dart';
import 'onedrive_service.dart';

import 'sftp_service.dart';
import 'webdav_service.dart';

/// Sync lifecycle for a single database path.
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

/// Coordinates cloud uploads/downloads for Google Drive– and Dropbox-backed
/// vaults. Ensures:
///
///  * Saves mark the vault "dirty" and schedule a single upload per path.
///    Back-to-back saves coalesce — the service keeps uploading until the
///    dirty flag clears.
///  * [awaitPending] lets callers (lock/unlock) block until any in-flight
///    upload finishes, avoiding the race where unlock clobbers a local cache
///    that hasn't been pushed yet.
///  * [refreshFromCloud] only overwrites the local cache when the remote is
///    strictly newer, and it first retries a pending upload if the vault is
///    still marked dirty from a previous failed sync.
///  * Upload failures persist (as the `dirty` flag) across app restarts, so a
///    subsequent save/unlock retries automatically.
///
/// The service is a singleton so that it can be awaited from any call site
/// (save, lock, unlock) without Riverpod plumbing.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  static const _dirtyKeyPrefix = 'cloud_sync_dirty_v1:';
  static const _remoteModifiedKeyPrefix = 'cloud_sync_remote_modified_v1:';
  static const _logTag = '[CloudSync]';

  LocalStorageService? _storage;
  ProviderContainer? _riverpodContainer;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};
  final Map<String, CloudSyncStatus> _statuses = <String, CloudSyncStatus>{};
  final StreamController<CloudSyncStatus> _statusController =
      StreamController<CloudSyncStatus>.broadcast();

  Stream<CloudSyncStatus> get statusStream => _statusController.stream;

  CloudSyncStatus statusFor(String path) =>
      _statuses[path] ?? CloudSyncStatus.idle(path);

  /// Verifies that [record] still points at a reachable remote vault copy.
  ///
  /// Throws a descriptive error when the provider session is present but the
  /// saved file reference is missing, revoked, or otherwise unusable.
  Future<void> verifyRemoteAccess(DatabaseRecord record) async {
    final resolved = await _ensureGoogleDriveRecordRepaired(record);
    if (!_isRecognizedCloudProvider(resolved.storageType)) {
      return;
    }

    final fileId = resolved.cloudFileId;
    if (fileId == null || fileId.isEmpty) {
      throw StateError(
        'This vault is no longer linked to its remote file reference. '
        'Remove it from the list and open it again from '
        '${_providerLabel(resolved.storageType)}.',
      );
    }

    switch (resolved.storageType) {
      case 'googleDrive':
        await BackupService.instance.getGoogleDriveFileModifiedTime(fileId);
        return;
      case 'dropbox':
        await BackupService.instance.getDropboxFileModifiedTime(fileId);
        return;
      case 'oneDrive':
        await OneDriveService.instance.getFileModifiedTime(fileId);
        return;
      case 'webdav':
        final modified =
            await WebDavService.instance.getFileModifiedTime(fileId);
        if (modified == null) {
          throw StateError(
            'The saved WebDAV file could not be found or inspected.',
          );
        }
        return;
      case 'sftp':
        final modified = await SftpService.instance.getFileModifiedTime(fileId);
        if (modified == null) {
          throw StateError(
            'The saved SFTP file could not be found or inspected.',
          );
        }
        return;
      case 's3':
        final modified =
            await BackupService.instance.getS3FileModifiedTime(fileId);
        if (modified == null) {
          throw StateError(
            'The saved Amazon S3 object could not be found or inspected.',
          );
        }
        return;
      default:
        return;
    }
  }

  /// Attach persistent storage. Safe to call repeatedly.
  void attach(LocalStorageService storage) {
    final firstAttach = _storage == null;
    _storage ??= storage;
    if (firstAttach) {
      _log('service attached — dirty-flag persistence ready');
    }
  }

  /// Needed to persist a recovered [DatabaseRecord.cloudFileId] when the
  /// registry row was missing it.
  void attachContainer(ProviderContainer container) {
    _riverpodContainer = container;
  }

  Future<DatabaseRecord> _ensureGoogleDriveRecordRepaired(
    DatabaseRecord record,
  ) async {
    if (record.storageType != 'googleDrive') return record;
    if (record.cloudFileId != null && record.cloudFileId!.isNotEmpty) {
      return record;
    }
    final repaired = await _tryRepairGoogleDriveRegistryRecord(record);
    return repaired ?? record;
  }

  Future<DatabaseRecord?> _tryRepairGoogleDriveRegistryRecord(
    DatabaseRecord record,
  ) async {
    final container = _riverpodContainer;
    if (container == null) {
      _log('Google Drive id repair skipped — container not attached');
      return null;
    }
    try {
      final meta =
          await BackupService.instance.resolveMissingGoogleDriveFileMetadata(
        databasePath: record.databasePath,
        cloudFileName: record.cloudFileName,
      );
      if (meta == null) {
        _log(
          'Google Drive id repair — no file on Drive matches '
          '${_shortPath(record.databasePath)}',
        );
        return null;
      }
      _log(
        'Google Drive id repair ✓ fileId=${_maskId(meta.id)} name="${meta.name}" '
        '→ ${_shortPath(record.databasePath)}',
      );
      await container.read(databaseRegistryProvider.notifier).updateCloudLink(
            recordId: record.id,
            cloudFileId: meta.id,
            cloudFileName: meta.name,
          );
      for (final r in container.read(databaseRegistryProvider)) {
        if (r.id == record.id) return r;
      }
      return null;
    } catch (e) {
      _log('Google Drive id repair failed: $e');
      return null;
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Marks [record] dirty and schedules (or coalesces) an upload. Resolves
  /// when the most recent pending state has been pushed successfully.
  ///
  /// Returns immediately with a future you can `await` or ignore. Local-only
  /// records resolve instantly.
  Future<void> scheduleUpload(DatabaseRecord record) async {
    final r = await _ensureGoogleDriveRecordRepaired(record);
    if (!_isCloudBacked(r)) {
      _log(
        'scheduleUpload skipped (storageType=${r.storageType}, '
        'cloudFileId=${_maskId(r.cloudFileId)}) for '
        '${_shortPath(r.databasePath)}',
      );
      return;
    }

    final sizeBytes = await _safeFileSize(r.databasePath);
    _log(
      'scheduleUpload ${r.storageType} '
      'path=${_shortPath(r.databasePath)} '
      'size=${_formatBytes(sizeBytes)} '
      'fileId=${_maskId(r.cloudFileId)} '
      'inFlight=${_inFlight.containsKey(r.databasePath)}',
    );

    await _setDirty(r.databasePath, true);
    return _ensureLoop(r);
  }

  /// Awaits any in-flight upload for [path]. Returns immediately if none.
  Future<void> awaitPending(String path) async {
    final future = _inFlight[path];
    if (future == null) {
      _log('awaitPending no-op — no in-flight for ${_shortPath(path)}');
      return;
    }
    final sw = Stopwatch()..start();
    _log('awaitPending waiting for in-flight upload ${_shortPath(path)}');
    try {
      await future;
      _log(
        'awaitPending resolved after ${sw.elapsedMilliseconds}ms '
        'for ${_shortPath(path)}',
      );
    } catch (e) {
      _log(
        'awaitPending resolved with error after ${sw.elapsedMilliseconds}ms '
        'for ${_shortPath(path)}: $e',
      );
    }
  }

  /// Pushes any pending changes, if the vault was marked dirty from a
  /// previous failed sync. Throws if the retry fails — callers decide how
  /// to react (e.g. abort a refresh to avoid clobbering local edits).
  Future<void> flush(DatabaseRecord record) async {
    final r = await _ensureGoogleDriveRecordRepaired(record);
    if (!_isCloudBacked(r)) return;
    _log('flush requested ${_shortPath(r.databasePath)}');
    await awaitPending(r.databasePath);
    if (await isDirty(r.databasePath)) {
      _log(
        'flush — still dirty after awaitPending, triggering retry '
        '${_shortPath(r.databasePath)}',
      );
      await _ensureLoop(r);
    } else {
      _log('flush — nothing dirty ${_shortPath(r.databasePath)}');
    }
  }

  /// Returns true if the local cache has unsynced changes.
  Future<bool> isDirty(String path) async {
    final storage = _storage;
    if (storage == null) return false;
    final v = await storage.read(key: _dirtyKey(path));
    return v == 'true';
  }

  /// Downloads the latest cloud copy over [record.databasePath] **only** when
  /// the remote is strictly newer than the local cache. If the vault is still
  /// dirty from a failed upload, the upload is retried first and the download
  /// is skipped if the retry succeeds (remote is now up-to-date with local).
  ///
  /// Never throws — falls back to the existing local cache on any error so
  /// that unlock can still proceed.
  Future<void> refreshFromCloud(DatabaseRecord record) async {
    final r = await _ensureGoogleDriveRecordRepaired(record);
    if (!_isCloudBacked(r)) {
      _log(
        'refreshFromCloud skipped (local-only or missing cloud id) '
        '${_shortPath(r.databasePath)}',
      );
      return;
    }

    _log(
      'refreshFromCloud start ${r.storageType} '
      '${_shortPath(r.databasePath)} '
      'fileId=${_maskId(r.cloudFileId)}',
    );

    await awaitPending(r.databasePath);

    if (await isDirty(r.databasePath)) {
      _log(
        'refreshFromCloud — vault still dirty, pushing before download '
        '${_shortPath(r.databasePath)}',
      );
      try {
        await _ensureLoop(r);
        _log(
          'refreshFromCloud — retry push succeeded, skipping download '
          '(local == remote) for ${_shortPath(r.databasePath)}',
        );
      } catch (e) {
        _log(
          'refreshFromCloud ABORTED — pending upload retry failed: $e. '
          'Keeping local cache (not overwriting with stale remote) for '
          '${_shortPath(r.databasePath)}',
        );
        return;
      }
    }

    final sw = Stopwatch()..start();
    try {
      _emit(CloudSyncStatus(
        path: r.databasePath,
        phase: CloudSyncPhase.downloading,
      ));
      final remoteModified = await _fetchRemoteModifiedTime(r);
      final localFile = File(r.databasePath);
      DateTime? localModified;
      int? localSize;
      if (await localFile.exists()) {
        final stat = await localFile.stat();
        localModified = stat.modified;
        localSize = stat.size;
      }
      final lastSyncedRemoteModified =
          await _readLastSyncedRemoteModified(r.databasePath);

      final shouldDownload = shouldDownloadRemoteVaultCopy(
        localModified: localModified,
        remoteModified: remoteModified,
        lastSyncedRemoteModified: lastSyncedRemoteModified,
      );

      _log(
        'refreshFromCloud compare '
        'remote=${remoteModified?.toIso8601String() ?? 'unknown'} '
        'local=${localModified?.toIso8601String() ?? 'missing'} '
        'lastSeenRemote=${lastSyncedRemoteModified?.toIso8601String() ?? 'unknown'} '
        'localSize=${_formatBytes(localSize)} '
        'decision=${shouldDownload ? 'download' : 'skip'}',
      );

      if (!shouldDownload) {
        _emit(CloudSyncStatus.idle(r.databasePath));
        return;
      }

      final Uint8List bytes;
      switch (r.storageType) {
        case 'googleDrive':
          bytes = await BackupService.instance
              .downloadGoogleDriveFile(r.cloudFileId!);
        case 'dropbox':
          bytes =
              await BackupService.instance.downloadDropboxFile(r.cloudFileId!);
        case 'oneDrive':
          bytes = await OneDriveService.instance.downloadFile(r.cloudFileId!);
        case 'webdav':
          bytes = await WebDavService.instance.downloadFile(r.cloudFileId!);
        case 'sftp':
          bytes = await SftpService.instance.downloadFile(r.cloudFileId!);
        case 's3':
          bytes = await BackupService.instance.downloadS3File(r.cloudFileId!);
        default:
          _emit(CloudSyncStatus.idle(r.databasePath));
          return;
      }

      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(bytes, flush: true);
      await _setDirty(r.databasePath, false);
      await _writeLastSyncedRemoteModified(r.databasePath, remoteModified);
      _log(
        'refreshFromCloud pulled ${_formatBytes(bytes.length)} '
        'in ${sw.elapsedMilliseconds}ms (${_throughput(bytes.length, sw.elapsed)}) '
        '→ ${_shortPath(r.databasePath)}',
      );
      _emit(CloudSyncStatus.idle(r.databasePath));
    } catch (e, stack) {
      _log(
        'refreshFromCloud FAILED after ${sw.elapsedMilliseconds}ms for '
        '${_shortPath(r.databasePath)}: $e\n$stack',
      );
      _emit(CloudSyncStatus(
        path: r.databasePath,
        phase: CloudSyncPhase.error,
        error: e,
        dirty: await isDirty(r.databasePath),
      ));
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<void> _ensureLoop(DatabaseRecord record) {
    final path = record.databasePath;
    final existing = _inFlight[path];
    if (existing != null) {
      _log(
        '_ensureLoop — upload already in flight, coalescing '
        '${_shortPath(path)}',
      );
      return existing;
    }

    _log('_ensureLoop — starting new upload loop ${_shortPath(path)}');
    final completer = Completer<void>();
    _inFlight[path] = completer.future;
    unawaited(_runLoop(record, completer));
    return completer.future;
  }

  /// Keeps uploading until the dirty flag clears or an attempt fails.
  Future<void> _runLoop(
      DatabaseRecord record, Completer<void> completer) async {
    final path = record.databasePath;
    Object? lastError;
    var iteration = 0;
    try {
      while (await isDirty(path)) {
        iteration++;
        _log('runLoop iter=$iteration ${_shortPath(path)}');
        try {
          await _performUpload(record);
          lastError = null;
        } catch (e) {
          lastError = e;
          _log(
            'runLoop iter=$iteration FAILED ${_shortPath(path)}: $e — '
            'will retry on next save/flush',
          );
          break;
        }
      }
    } finally {
      _inFlight.remove(path);
      final dirty = await isDirty(path);
      if (lastError != null) {
        _emit(CloudSyncStatus(
          path: path,
          phase: CloudSyncPhase.error,
          error: lastError,
          dirty: dirty,
        ));
        completer.completeError(lastError);
      } else {
        _log(
          'runLoop done (iterations=$iteration) clean ${_shortPath(path)}',
        );
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
    final sw = Stopwatch()..start();
    final bytes = await file.readAsBytes();
    final fileName = record.cloudFileName ?? p.basename(record.databasePath);
    final fileId = record.cloudFileId;
    if (fileId == null || fileId.isEmpty) {
      throw StateError(
        'Record for ${record.databasePath} has no cloudFileId — skipping upload',
      );
    }

    _log(
      'upload → ${record.storageType} name="$fileName" '
      'size=${_formatBytes(bytes.length)} fileId=${_maskId(fileId)} '
      '${_shortPath(record.databasePath)}',
    );

    switch (record.storageType) {
      case 'googleDrive':
        await BackupService.instance
            .updateGoogleDriveFile(fileId, bytes, fileName);
      case 'dropbox':
        await BackupService.instance.uploadBytesToDropbox(bytes, fileId);
      case 'oneDrive':
        await OneDriveService.instance.uploadBytes(bytes, fileId, fileName);
      case 'webdav':
        await WebDavService.instance.uploadBytes(bytes, fileId);
      case 'sftp':
        await SftpService.instance.uploadBytes(bytes, fileId);
      case 's3':
        await BackupService.instance.uploadBytesToS3(bytes, fileId);
      default:
        throw StateError(
          'Unsupported cloud storageType: ${record.storageType}',
        );
    }

    await _setDirty(record.databasePath, false);
    await _refreshStoredRemoteModified(record);
    _log(
      'upload ✓ ${record.storageType} name="$fileName" '
      'size=${_formatBytes(bytes.length)} in ${sw.elapsedMilliseconds}ms '
      '(${_throughput(bytes.length, sw.elapsed)}) '
      'fileId=${_maskId(fileId)}',
    );
  }

  Future<DateTime?> _fetchRemoteModifiedTime(DatabaseRecord record) async {
    try {
      switch (record.storageType) {
        case 'googleDrive':
          return await BackupService.instance
              .getGoogleDriveFileModifiedTime(record.cloudFileId!);
        case 'dropbox':
          return await BackupService.instance
              .getDropboxFileModifiedTime(record.cloudFileId!);
        case 'oneDrive':
          return await OneDriveService.instance
              .getFileModifiedTime(record.cloudFileId!);
        case 'webdav':
          return await WebDavService.instance
              .getFileModifiedTime(record.cloudFileId!);
        case 'sftp':
          return await SftpService.instance
              .getFileModifiedTime(record.cloudFileId!);
        case 's3':
          return await BackupService.instance
              .getS3FileModifiedTime(record.cloudFileId!);
      }
    } catch (e) {
      _log(
        'remote mtime lookup failed for ${_shortPath(record.databasePath)}: $e',
      );
    }
    return null;
  }

  bool _isCloudBacked(DatabaseRecord record) {
    if (!_isRecognizedCloudProvider(record.storageType)) {
      return false;
    }

    final fileId = record.cloudFileId;
    return fileId != null && fileId.isNotEmpty;
  }

  bool _isRecognizedCloudProvider(String storageType) {
    return storageType == 'googleDrive' ||
        storageType == 'dropbox' ||
        storageType == 'oneDrive' ||
        storageType == 'webdav' ||
        storageType == 'sftp' ||
        storageType == 's3';
  }

  Future<void> _setDirty(String path, bool dirty) async {
    final storage = _storage;
    if (storage == null) return;
    if (dirty) {
      await storage.write(key: _dirtyKey(path), value: 'true');
    } else {
      await storage.delete(key: _dirtyKey(path));
    }
    _log('dirty=${dirty ? '1' : '0'} ${_shortPath(path)}');

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

  Future<DateTime?> _readLastSyncedRemoteModified(String path) async {
    final storage = _storage;
    if (storage == null) return null;
    final raw = await storage.read(key: _remoteModifiedKey(path));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> _writeLastSyncedRemoteModified(
    String path,
    DateTime? modified,
  ) async {
    final storage = _storage;
    if (storage == null || modified == null) {
      return;
    }
    await storage.write(
      key: _remoteModifiedKey(path),
      value: modified.toUtc().toIso8601String(),
    );
  }

  Future<void> _refreshStoredRemoteModified(DatabaseRecord record) async {
    final remoteModified = await _fetchRemoteModifiedTime(record);
    await _writeLastSyncedRemoteModified(record.databasePath, remoteModified);
  }

  String _remoteModifiedKey(String path) {
    final hash = sha1.convert(utf8.encode(path)).toString();
    return '$_remoteModifiedKeyPrefix$hash';
  }

  void _emit(CloudSyncStatus status) {
    _statuses[status.path] = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    _log(
      'status ${status.phase.name} dirty=${status.dirty ? '1' : '0'}'
      '${status.error != null ? ' error=${status.error}' : ''} '
      '${_shortPath(status.path)}',
    );
  }

  // ── Logging helpers ────────────────────────────────────────────────────────

  void _log(String message) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('$_logTag $ts $message');
  }

  Future<int?> _safeFileSize(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return (await file.stat()).size;
    } catch (_) {
      return null;
    }
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return '?';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  String _throughput(int bytes, Duration elapsed) {
    if (elapsed.inMilliseconds <= 0 || bytes <= 0) return '—';
    final bytesPerSec = bytes / (elapsed.inMilliseconds / 1000.0);
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)}B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)}KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)}MB/s';
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

  String _providerLabel(String storageType) {
    switch (storageType) {
      case 'googleDrive':
        return 'Google Drive';
      case 'dropbox':
        return 'Dropbox';
      case 'oneDrive':
        return 'OneDrive';
      case 'webdav':
        return 'WebDAV';
      case 'sftp':
        return 'SFTP';
      case 's3':
        return 'Amazon S3';
      default:
        return storageType;
    }
  }
}

@visibleForTesting
bool shouldDownloadRemoteVaultCopy({
  required DateTime? localModified,
  required DateTime? remoteModified,
  required DateTime? lastSyncedRemoteModified,
}) {
  if (localModified == null) return true;
  if (remoteModified == null) return true;
  if (remoteModified.isAfter(localModified)) return true;
  if (lastSyncedRemoteModified == null) {
    // Older installs do not have a remembered remote revision yet. Pull once
    // so the cache can self-heal even when local mtimes are ahead of remote.
    return true;
  }
  return !_sameInstant(remoteModified, lastSyncedRemoteModified);
}

bool _sameInstant(DateTime a, DateTime b) {
  return a.toUtc().microsecondsSinceEpoch == b.toUtc().microsecondsSinceEpoch;
}

// ── Providers ────────────────────────────────────────────────────────────────

/// Live sync status for the active database path. Emits on every phase
/// change. Widgets can `ref.watch` to display a "Syncing…" indicator or
/// surface errors.
final cloudSyncStatusProvider =
    StreamProvider.family<CloudSyncStatus, String>((ref, path) async* {
  yield CloudSyncService.instance.statusFor(path);
  yield* CloudSyncService.instance.statusStream
      .where((status) => status.path == path);
});

/// Initialises [CloudSyncService] with the shared [LocalStorageService].
/// Call once on app startup.
void initCloudSyncService(ProviderContainer container) {
  CloudSyncService.instance.attach(container.read(localStorageProvider));
  CloudSyncService.instance.attachContainer(container);
}
