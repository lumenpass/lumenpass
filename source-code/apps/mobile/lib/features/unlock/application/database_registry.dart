import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/repository/providers.dart';

/// Manages the persisted list of registered KeePass databases on mobile.
/// Mirrors the desktop DatabaseRegistryNotifier (without macOS bookmark support).
class DatabaseRegistryNotifier extends StateNotifier<List<DatabaseRecord>> {
  DatabaseRegistryNotifier(this._ref) : super(const []) {
    _load();
  }

  static const _kStorageKey = 'lumenpass_database_registry_v1';
  static const _uuid = Uuid();

  final Ref _ref;
  final _readyCompleter = Completer<void>();

  /// Resolves when the registry has finished loading from storage.
  Future<void> get ready => _readyCompleter.future;

  Future<void> _load() async {
    try {
      final storage = _ref.read(localStorageProvider);
      final raw = await storage.read(_kStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final records = DatabaseRecord.listFromJson(raw);
        final seen = <String>{};
        final deduped = records.where((r) => seen.add(r.databasePath)).toList();
        state = _normalizeDefault(deduped);
      }
    } catch (_) {
    } finally {
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    }
  }

  Future<DatabaseRecord> addDatabase({
    required String nickname,
    required String databasePath,
    String storageType = 'local',
    String? cloudFileId,
    String? cloudFileName,
  }) async {
    final existing = state.where((r) => r.databasePath == databasePath);
    if (existing.isNotEmpty) return existing.first;

    final isFirst = state.isEmpty || !state.any((r) => r.isDefaultStartup);
    final record = DatabaseRecord(
      id: _uuid.v4(),
      nickname: nickname,
      databasePath: databasePath,
      addedAt: DateTime.now(),
      storageType: storageType,
      isDefaultStartup: isFirst,
      cloudFileId: cloudFileId,
      cloudFileName: cloudFileName,
    );
    state = _normalizeDefault([...state, record]);
    await _persist();
    return record;
  }

  Future<void> removeDatabase(String id) async {
    state = _normalizeDefault(state.where((r) => r.id != id).toList());
    await _persist();
  }

  /// Removes every vault registered under [storageType] (used when a cloud
  /// provider is disconnected). Returns the removed records so callers can
  /// reconcile any local selection state. Only local references are dropped —
  /// the underlying cloud files are never touched.
  Future<List<DatabaseRecord>> removeByStorageType(String storageType) async {
    final removed =
        state.where((r) => r.storageType == storageType).toList();
    if (removed.isEmpty) return const [];
    state = _normalizeDefault(
      state.where((r) => r.storageType != storageType).toList(),
    );
    await _persist();
    return removed;
  }

  Future<void> setDefaultStartup(String id) async {
    state = state.map((r) => r.copyWith(isDefaultStartup: r.id == id)).toList();
    await _persist();
  }

  /// Records the last time the vault identified by [id] was successfully
  /// opened. Used to sort vaults by recency on the picker screen.
  Future<void> setLastOpenedAt(String id) async {
    state = [
      for (final r in state)
        if (r.id == id)
          r.copyWith(lastOpenedAt: DateTime.now())
        else
          r,
    ];
    await _persist();
  }

  /// Copies the database file to a new path and registers it (always as local).
  Future<DatabaseRecord?> duplicateDatabase(String id) async {
    DatabaseRecord? record;
    for (final r in state) {
      if (r.id == id) {
        record = r;
        break;
      }
    }
    if (record == null) return null;

    final source = File(record.databasePath);
    if (!await source.exists()) return null;

    final dupPath = await _nextDuplicatePath(record.databasePath);
    await source.copy(dupPath);
    final nickname = _nextDuplicateNickname(record.nickname, state);
    return addDatabase(
      nickname: nickname,
      databasePath: dupPath,
      storageType: 'local',
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  List<DatabaseRecord> _normalizeDefault(List<DatabaseRecord> records) {
    if (records.isEmpty) return const [];
    final defaultIndex = records.indexWhere((r) => r.isDefaultStartup);
    final resolved = defaultIndex >= 0 ? defaultIndex : 0;
    return List.generate(
      records.length,
      (i) => records[i].copyWith(isDefaultStartup: i == resolved),
    );
  }

  Future<void> _persist() async {
    try {
      await _ref
          .read(localStorageProvider)
          .write(_kStorageKey, DatabaseRecord.listToJson(state));
    } catch (_) {}
  }

  Future<String> _nextDuplicatePath(String sourcePath) async {
    final directory = p.dirname(sourcePath);
    final extension = p.extension(sourcePath);
    final basename = p.basenameWithoutExtension(sourcePath);

    var candidate = p.join(directory, '$basename copy$extension');
    var index = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(directory, '$basename copy $index$extension');
      index += 1;
    }
    return candidate;
  }

  String _nextDuplicateNickname(
    String nickname,
    List<DatabaseRecord> existingRecords,
  ) {
    final existingNames =
        existingRecords.map((record) => record.nickname).toSet();
    var candidate = '$nickname Copy';
    var index = 2;
    while (existingNames.contains(candidate)) {
      candidate = '$nickname Copy $index';
      index += 1;
    }
    return candidate;
  }
}

final databaseRegistryProvider =
    StateNotifierProvider<DatabaseRegistryNotifier, List<DatabaseRecord>>(
      (ref) => DatabaseRegistryNotifier(ref),
    );
