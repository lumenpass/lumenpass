import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;

import '../../features/unlock/application/database_registry.dart';
import '../../features/home/application/home_vault_providers.dart';
import '../../features/vault/application/vault_entries_providers.dart';
import '../repository/providers.dart';
import 'cloud_sync_service.dart';
import 'cloud_database_service.dart';
import 'cloud_vault_cache.dart';

enum VaultSyncPhase { idle, syncing, success, error }

@immutable
class VaultSyncState {
  const VaultSyncState({required this.phase, this.lastSyncAt, this.error});

  const VaultSyncState.initial() : this(phase: VaultSyncPhase.idle);

  final VaultSyncPhase phase;
  final DateTime? lastSyncAt;
  final Object? error;

  bool get isSyncing => phase == VaultSyncPhase.syncing;
  bool get hasError => phase == VaultSyncPhase.error;

  VaultSyncState copyWith({
    VaultSyncPhase? phase,
    DateTime? lastSyncAt,
    Object? error,
    bool clearError = false,
  }) {
    return VaultSyncState(
      phase: phase ?? this.phase,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

String formatLastSync(DateTime? lastSyncAt, {DateTime? now}) {
  if (lastSyncAt == null) return 'Last synced: never';
  final reference = now ?? DateTime.now();
  final diff = reference.difference(lastSyncAt);
  if (diff.isNegative || diff.inSeconds < 5) {
    return 'Last synced: just now';
  }
  if (diff.inSeconds < 60) {
    return 'Last synced: ${diff.inSeconds}s ago';
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'Last synced: $m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'Last synced: $h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  final hh = lastSyncAt.hour.toString().padLeft(2, '0');
  final mm = lastSyncAt.minute.toString().padLeft(2, '0');
  final ss = lastSyncAt.second.toString().padLeft(2, '0');
  return 'Last synced: $hh:$mm:$ss';
}

typedef VaultRefreshCallback = Future<void> Function(DatabaseRecord record);

class VaultAutoSyncController extends StateNotifier<VaultSyncState>
    with WidgetsBindingObserver {
  VaultAutoSyncController(
    Ref? ref, {
    Duration interval = const Duration(seconds: 30),
    @visibleForTesting VaultRefreshCallback? refresh,
    @visibleForTesting DatabaseRecord? Function()? recordResolver,
    @visibleForTesting DateTime Function()? clock,
    bool autoStart = true,
    bool observeLifecycle = true,
  }) : _ref = ref,
       _interval = interval,
       _refresh =
           refresh ??
           ((record) => CloudSyncService.instance.refreshFromCloud(record)),
       _recordResolver = recordResolver,
       _clock = clock ?? DateTime.now,
       _autoStart = autoStart,
       _observeLifecycle = observeLifecycle,
       super(const VaultSyncState.initial()) {
    if (_observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
    if (autoStart) _restart();
  }

  final Ref? _ref;
  final Duration _interval;
  final VaultRefreshCallback _refresh;
  final DatabaseRecord? Function()? _recordResolver;
  final DateTime Function() _clock;
  final bool _autoStart;
  final bool _observeLifecycle;

  Timer? _timer;
  bool _running = false;
  bool _foreground = true;

  Duration get interval => _interval;

  void _restart() {
    if (!_autoStart || !_foreground) return;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      sync().ignore();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        debugPrint('[AutoSync] app resumed; syncing active cloud vault');
        _restart();
        sync().ignore();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _foreground = false;
        debugPrint('[AutoSync] app left foreground; pausing sync timer');
        _timer?.cancel();
        _timer = null;
        break;
    }
  }

  Future<DatabaseRecord?> _activeRecord() async {
    final resolver = _recordResolver;
    if (resolver != null) return resolver();
    final ref = _ref;
    if (ref == null) return null;
    final homeRecord = ref.read(homeVaultRecordProvider);
    if (homeRecord != null) {
      if (homeRecord.storageType == 'googleDrive' ||
          homeRecord.storageType == 'dropbox' ||
          homeRecord.storageType == 'oneDrive' ||
          homeRecord.storageType == 'webdav' ||
          homeRecord.storageType == 'sftp' ||
          homeRecord.storageType == 's3') {
        if (!CloudDatabaseService.instance
            .isCloudProviderAccessible(homeRecord.storageType)) {
          return null;
        }
        return homeRecord;
      }
      return null;
    }

    final active = ref.read(activeDatabaseProvider);
    if (active == null) return null;
    final activePath = p.normalize(active.path);
    final registry = ref.read(databaseRegistryProvider);
    for (final record in registry) {
      final resolvedPath = p.normalize(await resolvedLocalDatabasePath(record));
      if (resolvedPath == activePath) {
        if (record.storageType == 'googleDrive' ||
            record.storageType == 'dropbox' ||
            record.storageType == 'oneDrive' ||
            record.storageType == 'webdav' ||
            record.storageType == 'sftp' ||
            record.storageType == 's3') {
          if (!CloudDatabaseService.instance
              .isCloudProviderAccessible(record.storageType)) {
            return null;
          }
          return record;
        }
        return null;
      }
    }
    return null;
  }

  Future<void> sync() async {
    if (_running) return;
    final record = await _activeRecord();
    if (record == null) {
      state = state.copyWith(phase: VaultSyncPhase.idle, clearError: true);
      return;
    }

    _running = true;
    _timer?.cancel();
    state = state.copyWith(phase: VaultSyncPhase.syncing, clearError: true);

    try {
      final localPath = await resolvedLocalDatabasePath(record);
      final localFile = File(localPath);
      DateTime? mtimeBefore;
      if (await localFile.exists()) {
        mtimeBefore = (await localFile.stat()).modified;
      }

      await _refresh(record).timeout(const Duration(seconds: 30));

      await _reopenIfFileChanged(localPath, mtimeBefore);

      state = state.copyWith(
        phase: VaultSyncPhase.success,
        lastSyncAt: _clock(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(phase: VaultSyncPhase.error, error: e);
    } finally {
      _running = false;
      _restart();
    }
  }

  Future<void> _reopenIfFileChanged(
    String databasePath,
    DateTime? mtimeBefore,
  ) async {
    final ref = _ref;
    if (ref == null) return;

    final localFile = File(databasePath);
    if (!await localFile.exists()) return;

    final mtimeAfter = (await localFile.stat()).modified;
    if (mtimeBefore != null && !mtimeAfter.isAfter(mtimeBefore)) return;

    final password = ref.read(cachedMasterPasswordProvider);
    if (password == null) return;

    final repo = ref.read(kdbxRepositoryProvider);
    if (!repo.hasOpenDatabase) return;

    try {
      final db = await repo.openDatabase(
        databasePath: databasePath,
        password: password.isEmpty ? null : password,
      );
      ref.read(activeDatabaseProvider.notifier).state = db;
      ref.invalidate(vaultVisibleEntriesProvider);
      ref.invalidate(homeRecentEntriesProvider);
      debugPrint('[AutoSync] reopened DB after cloud pull');
    } catch (e) {
      debugPrint('[AutoSync] reopen after cloud pull failed: $e');
    }
  }

  @override
  void dispose() {
    if (_observeLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

final vaultAutoSyncControllerProvider =
    StateNotifierProvider<VaultAutoSyncController, VaultSyncState>(
      (ref) => VaultAutoSyncController(ref),
    );
