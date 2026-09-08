import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/database_record.dart';
import '../../features/unlock/application/database_registry.dart';
import '../../features/vault/application/vault_providers.dart';
import '../repository/kdbx_repository_provider.dart';
import '../repository/vault_write_scheduler_provider.dart';
import 'cloud_sync_service.dart';

/// Phases of the vault auto-sync state machine.
///
/// These mirror [CloudSyncPhase] but are scoped to the *currently active
/// vault* and add an explicit [VaultSyncPhase.idle] state used by the UI
/// when no sync has run yet, plus an [VaultSyncPhase.error] terminal state
/// distinct from in-progress syncs.
enum VaultSyncPhase { idle, syncing, success, error }

/// Immutable view-model rendered by the sidebar sync row.
@immutable
class VaultSyncState {
  const VaultSyncState({
    required this.phase,
    this.lastSyncAt,
    this.error,
  });

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

/// Formats a [VaultSyncState.lastSyncAt] into a human-readable label
/// such as "Just now", "2 minutes ago" or "14:30:25".
///
/// Pure function so the same logic is exercised from widget code and unit
/// tests without pulling in `dart:ui`.
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

/// Drives a 30-second auto-sync interval against [CloudSyncService] and
/// exposes the most recent sync timestamp + spinning-state for the UI.
///
/// Rationale for the 30-second interval:
///   * Keeps remote changes fresh while reducing background polling frequency.
///   * `CloudSyncService.refreshFromCloud` short-circuits when the remote
///     `modifiedTime` has not advanced, so idle vaults perform a single
///     metadata HEAD per cycle — well within Drive/Dropbox quotas.
///   * Manual saves still trigger an immediate push via `scheduleUpload`;
///     the timer is purely a *pull* safety-net for changes made on other
///     devices.
/// Performs the actual cloud refresh for the controller. Defaults to
/// [CloudSyncService.refreshFromCloud] but is overridable from tests so
/// no real network/Riverpod plumbing is required.
typedef VaultRefreshCallback = Future<void> Function(DatabaseRecord record);

class VaultAutoSyncController extends StateNotifier<VaultSyncState> {
  VaultAutoSyncController(
    Ref? ref, {
    Duration interval = const Duration(seconds: 30),
    @visibleForTesting VaultRefreshCallback? refresh,
    @visibleForTesting DatabaseRecord? Function()? recordResolver,
    @visibleForTesting DateTime Function()? clock,
    bool autoStart = true,
  })  : _ref = ref,
        _interval = interval,
        _refresh = refresh ??
            ((record) => CloudSyncService.instance.refreshFromCloud(record)),
        _recordResolver = recordResolver,
        _clock = clock ?? DateTime.now,
        super(const VaultSyncState.initial()) {
    if (autoStart) _restart();
  }

  final Ref? _ref;
  final Duration _interval;
  final VaultRefreshCallback _refresh;
  final DatabaseRecord? Function()? _recordResolver;
  final DateTime Function() _clock;

  Timer? _timer;
  bool _running = false;

  /// Configured auto-sync cadence — exposed so UI/tests can read the value.
  Duration get interval => _interval;

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      // Fire-and-forget; errors are surfaced via [state.error].
      sync().ignore();
    });
  }

  /// Resolve the [DatabaseRecord] backing the currently open vault.
  /// Returns `null` if no vault is open or if the active vault is local-only.
  DatabaseRecord? _activeRecord() {
    final resolver = _recordResolver;
    if (resolver != null) return resolver();
    final ref = _ref;
    if (ref == null) return null;
    final active = ref.read(activeDatabaseProvider);
    if (active == null) return null;
    final registry = ref.read(databaseRegistryProvider);
    for (final record in registry) {
      if (record.databasePath == active.path) {
        if (record.storageType == 'googleDrive' ||
            record.storageType == 'dropbox' ||
            record.storageType == 'oneDrive' ||
            record.storageType == 'webdav' ||
            record.storageType == 'sftp' ||
            record.storageType == 's3') {
          return record;
        }
        return null;
      }
    }
    return null;
  }

  /// Triggers a sync immediately. Cancels any pending auto-sync timer tick
  /// so that pressing the refresh button doesn't double-fire moments later.
  Future<void> sync() async {
    if (_running) return;
    final record = _activeRecord();
    if (record == null) {
      // No cloud-backed vault open — nothing to do, but advance the clock so
      // the UI doesn't show a stale "syncing…" state forever.
      state = state.copyWith(phase: VaultSyncPhase.idle, clearError: true);
      return;
    }

    _running = true;
    _timer?.cancel();
    state = state.copyWith(phase: VaultSyncPhase.syncing, clearError: true);

    try {
      // Flush pending background writes BEFORE capturing the mtime. This
      // guarantees (a) no unflushed in-memory edit is discarded by a
      // cloud-pull reopen below, and (b) our own background save doesn't bump
      // the mtime mid-sync and trigger a false-positive reopen.
      await _ref?.read(vaultWriteSchedulerProvider).flushNow();

      final localFile = File(record.databasePath);
      DateTime? mtimeBefore;
      if (await localFile.exists()) {
        mtimeBefore = (await localFile.stat()).modified;
      }

      await _refresh(record).timeout(const Duration(seconds: 30));

      await _reopenIfFileChanged(record.databasePath, mtimeBefore);

      state = state.copyWith(
        phase: VaultSyncPhase.success,
        lastSyncAt: _clock(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(phase: VaultSyncPhase.error, error: e);
    } finally {
      _running = false;
      // Re-arm the periodic timer so the next tick lands one full interval
      // from the *end* of this sync, preventing back-to-back manual+auto
      // bursts.
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
      // The in-memory database was replaced wholesale; drop any pending-write
      // state so a stale scheduled save never lands on the new snapshot.
      ref.read(vaultWriteSchedulerProvider).reset();
      ref.read(activeDatabaseProvider.notifier).state = db;
      ref.invalidate(vaultEntriesProvider);
      debugPrint('[AutoSync] reopened DB after cloud pull');
    } catch (e) {
      debugPrint('[AutoSync] reopen after cloud pull failed: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Riverpod entry point for [VaultAutoSyncController]. Lives for the
/// lifetime of the [ProviderContainer]; the controller cleans up its timer
/// in [VaultAutoSyncController.dispose].
final vaultAutoSyncControllerProvider =
    StateNotifierProvider<VaultAutoSyncController, VaultSyncState>(
  (ref) => VaultAutoSyncController(ref),
);
