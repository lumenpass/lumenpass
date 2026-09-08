import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

import '../../../core/models/database_record.dart';
import '../../../core/repository/kdbx_repository_provider.dart';

/// Manages the persisted list of registered databases.
class DatabaseRegistryNotifier extends StateNotifier<List<DatabaseRecord>> {
  DatabaseRegistryNotifier(this._ref) : super(const []) {
    _load();
  }

  static const String _storageKey = 'lumenpass_database_registry_v1';
  final Ref _ref;
  static const _uuid = Uuid();
  final Completer<void> _readyCompleter = Completer<void>();

  Future<void> get ready => _readyCompleter.future;

  Future<void> _load() async {
    try {
      final storage = _ref.read(localStorageProvider);
      final raw = await storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final records = DatabaseRecord.listFromJson(raw);
        // Deduplicate by path, keeping the first occurrence of each path.
        final seen = <String>{};
        final deduped = records.where((r) => seen.add(r.databasePath)).toList();
        state = _normalizeDefault(deduped);
        await _persist();
      }
    } catch (_) {
    } finally {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    }
  }

  Future<void> addDatabase({
    required String nickname,
    required String databasePath,
    String? bookmark,
    String storageType = 'local',
    String? cloudFileId,
    String? cloudFileName,
  }) async {
    // Prevent duplicates: if this path is already registered, skip.
    if (state.any((r) => r.databasePath == databasePath)) return;

    final record = DatabaseRecord(
      id: _uuid.v4(),
      nickname: nickname,
      databasePath: databasePath,
      addedAt: DateTime.now(),
      bookmark: bookmark,
      storageType: storageType,
      cloudFileId: cloudFileId,
      cloudFileName: cloudFileName,
      isDefaultStartup:
          state.isEmpty || !state.any((record) => record.isDefaultStartup),
    );
    state = _normalizeDefault([...state, record]);
    await _persist();
  }

  Future<void> removeDatabase(String id) async {
    state = _normalizeDefault(state.where((r) => r.id != id).toList());
    await _persist();
  }

  /// Removes every registered database that was added through the given cloud
  /// [storageType] (e.g. `'googleDrive'`, `'dropbox'`, `'oneDrive'`,
  /// `'webdav'`). This only drops the local registry references / bookmarks —
  /// the underlying `.kdbx` files on the cloud disk are never touched.
  ///
  /// Returns the records that were removed so callers can react (e.g. clear a
  /// selection that pointed at one of them).
  Future<List<DatabaseRecord>> removeByStorageType(String storageType) async {
    final removed = state
        .where((r) => r.storageType == storageType)
        .toList(growable: false);
    if (removed.isEmpty) return const <DatabaseRecord>[];

    state = _normalizeDefault(
      state.where((r) => r.storageType != storageType).toList(),
    );
    await _persist();
    return removed;
  }

  Future<void> setDefaultStartupDatabase(String id) async {
    state = _normalizeDefault(
      state
          .map(
            (record) => record.copyWith(
              isDefaultStartup: record.id == id,
            ),
          )
          .toList(),
    );
    await _persist();
  }

  /// Persists a recovered Google Drive / Dropbox file reference when the
  /// registry row lost [DatabaseRecord.cloudFileId] (e.g. older storage).
  Future<void> updateCloudLink({
    required String recordId,
    required String cloudFileId,
    String? cloudFileName,
  }) async {
    state = [
      for (final r in state)
        if (r.id == recordId)
          r.copyWith(
            cloudFileId: cloudFileId,
            cloudFileName: cloudFileName ?? r.cloudFileName,
          )
        else
          r,
    ];
    await _persist();
  }

  /// Records the last time the vault identified by [id] was successfully
  /// opened. This is used to sort vaults by recency on the unlock screen.
  Future<void> setLastOpenedAt(String id) async {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(lastOpenedAt: DateTime.now()) else r,
    ];
    await _persist();
  }

  List<DatabaseRecord> _normalizeDefault(List<DatabaseRecord> records) {
    if (records.isEmpty) {
      return const <DatabaseRecord>[];
    }

    final defaultIndex =
        records.indexWhere((record) => record.isDefaultStartup);
    final resolvedDefaultIndex = defaultIndex >= 0 ? defaultIndex : 0;

    return List<DatabaseRecord>.generate(
      records.length,
      (index) => records[index].copyWith(
        isDefaultStartup: index == resolvedDefaultIndex,
      ),
      growable: false,
    );
  }

  Future<void> _persist() async {
    try {
      final storage = _ref.read(localStorageProvider);
      await storage.write(
        key: _storageKey,
        value: DatabaseRecord.listToJson(state),
      );
    } catch (_) {}
  }
}

final databaseRegistryProvider =
    StateNotifierProvider<DatabaseRegistryNotifier, List<DatabaseRecord>>(
  (ref) => DatabaseRegistryNotifier(ref),
);
