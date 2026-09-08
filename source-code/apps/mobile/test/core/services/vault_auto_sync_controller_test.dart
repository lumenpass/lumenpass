import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:mobile/core/repository/providers.dart';
import 'package:mobile/core/repository/vault_write_scheduler_provider.dart';
import 'package:mobile/core/services/vault_auto_sync_controller.dart';

/// Exposes the container's own [Ref] so a [VaultAutoSyncController] can be
/// constructed outside a widget tree while still resolving providers.
final _refProvider = Provider<Ref>((ref) => ref);

KdbxDatabase _fakeDatabase() {
  return KdbxDatabase(
    path: '/tmp/test.kdbx',
    name: 'Test',
    openedAt: DateTime(2026),
    rootGroup: KdbxGroup(
      uuid: 'root',
      name: 'Root',
      groups: const [],
      entries: const [],
    ),
  );
}

/// Repository stub that reports an open database and counts reopen attempts.
/// Unused members fall through to [noSuchMethod].
class _RecordingKdbxRepository implements KdbxRepository {
  _RecordingKdbxRepository(this._database);

  final KdbxDatabase _database;
  int openDatabaseCalls = 0;

  @override
  KdbxDatabase? get currentDatabase => _database;

  @override
  bool get hasOpenDatabase => true;

  @override
  String? get rootGroupUuid => 'root';

  @override
  Future<KdbxDatabase> openDatabase({
    required String databasePath,
    String? password,
    Uint8List? keyFileBytes,
  }) async {
    openDatabaseCalls++;
    return _database;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected repository call in test');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VaultAutoSyncController', () {
    test('syncs immediately when the app resumes', () async {
      final refreshed = <DatabaseRecord>[];
      final refreshCompleted = Completer<void>();
      final record = _cloudRecord();
      final now = DateTime.utc(2026, 5, 11, 4, 37, 30);

      final controller = VaultAutoSyncController(
        null,
        autoStart: false,
        observeLifecycle: false,
        recordResolver: () => record,
        clock: () => now,
        refresh: (record) async {
          refreshed.add(record);
          refreshCompleted.complete();
        },
      );
      addTearDown(controller.dispose);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

      await refreshCompleted.future;
      await Future<void>.delayed(Duration.zero);
      expect(refreshed, [record]);
      expect(controller.state.phase, VaultSyncPhase.success);
      expect(controller.state.lastSyncAt, now);
    });
  });

  group('auto-sync flush guard', () {
    test('flushes pending writes before capturing mtime / cloud refresh',
        () async {
      final events = <String>[];
      final tempDir = Directory.systemTemp.createTempSync('autosync_flush');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final vaultFile = File('${tempDir.path}/vault.kdbx');
      await vaultFile.writeAsBytes(List<int>.filled(16, 0), flush: true);
      // Backdate the initial mtime so the flush's own save produces a
      // strictly newer mtime — the exact condition that would trigger a
      // false-positive reopen if the flush ran after the mtime capture.
      await vaultFile.setLastModified(
        DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final repository = _RecordingKdbxRepository(_fakeDatabase());
      final container = ProviderContainer(
        overrides: [
          kdbxRepositoryProvider.overrideWith((ref) => repository),
          cachedMasterPasswordProvider.overrideWith((ref) => 'pw'),
          vaultWriteSchedulerProvider.overrideWith((ref) {
            return VaultWriteScheduler(
              saveAndSync: () async {
                events.add('save');
                // A real save rewrites the file, bumping its mtime.
                await vaultFile.writeAsBytes(
                  List<int>.filled(16, 1),
                  flush: true,
                );
                return _fakeDatabase();
              },
              // Long debounce so the pending write stays parked until flush.
              debounce: const Duration(seconds: 30),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final ref = container.read(_refProvider);
      final scheduler = container.read(vaultWriteSchedulerProvider);

      // Simulate a pending low-priority write (e.g. a last-used timestamp).
      scheduler.markDirtyDebounced();
      expect(scheduler.hasPendingWrites, isTrue);

      final controller = VaultAutoSyncController(
        ref,
        autoStart: false,
        observeLifecycle: false,
        recordResolver: () => _cloudRecord(databasePath: vaultFile.path),
        refresh: (_) async {
          events.add('refresh');
        },
      );
      addTearDown(controller.dispose);

      await controller.sync();

      expect(controller.state.phase, VaultSyncPhase.success);
      // The pending write must be flushed before the cloud refresh runs — and
      // therefore before the mtime snapshot that guards the reopen — so a
      // cloud-pull reopen can never discard an unflushed in-memory edit.
      expect(events, ['save', 'refresh']);
      expect(scheduler.hasPendingWrites, isFalse);
      // Because the flush landed before the mtime capture, the save's own
      // mtime bump must NOT be mistaken for a cloud-pull change: no reopen.
      expect(repository.openDatabaseCalls, 0);
    });

    test('cloud-pull reopen resets stale pending-write state', () async {
      final tempDir = Directory.systemTemp.createTempSync('autosync_reopen');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final vaultFile = File('${tempDir.path}/vault.kdbx');
      await vaultFile.writeAsBytes(List<int>.filled(16, 0), flush: true);
      await vaultFile.setLastModified(
        DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final repository = _RecordingKdbxRepository(_fakeDatabase());
      final container = ProviderContainer(
        overrides: [
          kdbxRepositoryProvider.overrideWith((ref) => repository),
          cachedMasterPasswordProvider.overrideWith((ref) => 'pw'),
          vaultWriteSchedulerProvider.overrideWith((ref) {
            return VaultWriteScheduler(
              saveAndSync: () async => _fakeDatabase(),
              debounce: const Duration(seconds: 30),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final ref = container.read(_refProvider);
      final scheduler = container.read(vaultWriteSchedulerProvider);

      final controller = VaultAutoSyncController(
        ref,
        autoStart: false,
        observeLifecycle: false,
        recordResolver: () => _cloudRecord(databasePath: vaultFile.path),
        refresh: (_) async {
          // A mutation lands while the cloud pull is in flight, and the pull
          // itself rewrites the local file (mtime bump).
          scheduler.markDirtyDebounced();
          await vaultFile.writeAsBytes(List<int>.filled(16, 2), flush: true);
        },
      );
      addTearDown(controller.dispose);

      await controller.sync();

      expect(controller.state.phase, VaultSyncPhase.success);
      // The mtime bump from the cloud pull triggers a reopen ...
      expect(repository.openDatabaseCalls, 1);
      // ... which must reset the scheduler so the in-flight dirty flag never
      // saves stale state over the freshly pulled snapshot.
      expect(scheduler.hasPendingWrites, isFalse);
      expect(container.read(activeDatabaseProvider), isNotNull);
    });
  });
}

DatabaseRecord _cloudRecord({String databasePath = '/tmp/shared.kdbx'}) {
  return DatabaseRecord(
    id: 'vault-1',
    nickname: 'Shared Vault',
    databasePath: databasePath,
    addedAt: DateTime.utc(2026, 5, 11),
    storageType: 'local',
  );
}
