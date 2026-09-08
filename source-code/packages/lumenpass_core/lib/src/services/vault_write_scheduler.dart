import 'dart:async';

import '../models/kdbx_database.dart';

/// Signature of the app-supplied closure that persists the vault to disk and
/// (for cloud-backed vaults) schedules the upload. Must resolve to the fresh
/// database snapshot, mirroring the existing `saveAndSyncDatabase` helpers.
typedef VaultSaveAndSync = Future<KdbxDatabase> Function();

/// Serializes vault persistence so the UI never blocks on encrypting and
/// writing the KDBX file.
///
/// Mutations are applied to the in-memory [KdbxFile] by the repository and
/// then reported here via [markDirtyImmediate] (user edits) or
/// [markDirtyDebounced] (low-priority writes such as last-used timestamps and
/// favicon caching). The scheduler coalesces requests and runs at most one
/// save at a time; the in-memory database remains the source of truth while
/// the file on disk catches up in the background.
///
/// Call [flushNow] at hard synchronization points (vault lock, app
/// backgrounded, quit, import finalize, browser-extension writes) to await
/// persistence of everything currently in memory.
class VaultWriteScheduler {
  VaultWriteScheduler({
    required VaultSaveAndSync saveAndSync,
    void Function(Object error, StackTrace stackTrace)? onSaveError,
    Duration debounce = const Duration(milliseconds: 2500),
    Duration failureRetryDelay = const Duration(seconds: 5),
  })  : _saveAndSync = saveAndSync,
        _onSaveError = onSaveError,
        _debounce = debounce,
        _failureRetryDelay = failureRetryDelay;

  final VaultSaveAndSync _saveAndSync;
  final void Function(Object error, StackTrace stackTrace)? _onSaveError;
  final Duration _debounce;
  final Duration _failureRetryDelay;

  Timer? _delayedPumpTimer;
  bool _immediateQueued = false;
  bool _dirty = false;
  bool _lastSaveFailed = false;
  bool _disposed = false;
  Future<void>? _activeSave;

  /// True when the in-memory database is ahead of disk, either because a
  /// save is pending/running or writes are waiting on the debounce timer.
  bool get hasPendingWrites => _dirty || _activeSave != null;

  /// Reports a user-visible mutation (create/edit/delete). A save starts on
  /// the next event-loop turn; further mutations in the same burst coalesce
  /// into that single save.
  void markDirtyImmediate() {
    if (_disposed) return;
    _dirty = true;
    _delayedPumpTimer?.cancel();
    _delayedPumpTimer = null;
    _queueImmediatePump();
  }

  /// Reports a low-priority mutation (last-used timestamp, favicon cache).
  /// Saves coalesce for [_debounce]; an immediate request supersedes a
  /// pending debounced one.
  void markDirtyDebounced() {
    if (_disposed) return;
    _dirty = true;
    // A save is already queued or running; its follow-up pass picks this up.
    if (_immediateQueued || _activeSave != null) return;
    _delayedPumpTimer?.cancel();
    _delayedPumpTimer = Timer(_debounce, () {
      _delayedPumpTimer = null;
      _queueImmediatePump();
    });
  }

  /// Awaits persistence of everything currently in memory. No-op when clean.
  ///
  /// Returns after the disk file matches the in-memory database, except when
  /// a save fails: the dirty flag then stays set so the next flush point
  /// retries, and the error has already been reported via `onSaveError`.
  Future<void> flushNow() async {
    if (_disposed) return;
    _delayedPumpTimer?.cancel();
    _delayedPumpTimer = null;
    _immediateQueued = false;

    while (!_disposed) {
      final active = _activeSave;
      if (active != null) {
        await active;
        continue;
      }
      if (!_dirty) return;
      final save = _runSave();
      _activeSave = save;
      try {
        await save;
      } finally {
        _activeSave = null;
      }
      if (_lastSaveFailed) {
        // Persistent failure: stop flushing; the dirty flag survives so the
        // next flush point (lock/background/next edit) retries.
        return;
      }
    }
  }

  /// Drops all pending-write state. Called when the in-memory database is
  /// replaced wholesale (vault close, auto-sync reopen, vault switch) so a
  /// stale pending save never lands on the wrong file.
  void reset() {
    _delayedPumpTimer?.cancel();
    _delayedPumpTimer = null;
    _immediateQueued = false;
    _dirty = false;
    _lastSaveFailed = false;
  }

  void dispose() {
    _disposed = true;
    reset();
  }

  void _queueImmediatePump() {
    if (_immediateQueued || _disposed) return;
    _immediateQueued = true;
    scheduleMicrotask(() {
      _immediateQueued = false;
      _pump();
    });
  }

  void _pump() {
    if (_disposed || _activeSave != null || !_dirty) return;
    final save = _runSave();
    _activeSave = save;
    save.whenComplete(() {
      _activeSave = null;
      if (_disposed || !_dirty) return;
      if (_lastSaveFailed) {
        // Retry a failed save after a delay instead of hammering a broken
        // disk in a tight loop.
        _delayedPumpTimer?.cancel();
        _delayedPumpTimer = Timer(_failureRetryDelay, () {
          _delayedPumpTimer = null;
          _queueImmediatePump();
        });
      } else {
        // New mutations arrived while the save was in flight.
        _queueImmediatePump();
      }
    });
  }

  Future<void> _runSave() async {
    _dirty = false;
    try {
      await _saveAndSync();
      _lastSaveFailed = false;
    } catch (error, stackTrace) {
      _lastSaveFailed = true;
      _dirty = true;
      _onSaveError?.call(error, stackTrace);
    }
  }
}
