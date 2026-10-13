import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass_core/lumenpass_core.dart'
    show KdbxDatabase, KdbxGroup, VaultWriteScheduler;

import 'package:lumenpass/core/models/database_record.dart';
import 'package:lumenpass/core/repository/kdbx_repository.dart';
import 'package:lumenpass/core/repository/kdbx_repository_provider.dart';
import 'package:lumenpass/core/repository/vault_write_scheduler_provider.dart';
import 'package:lumenpass/core/services/vault_auto_sync_controller.dart';

/// Exposes the container's own [Ref] so a [VaultAutoSyncController] can be
/// constructed outside a widget tree while still resolving providers.
final _refProvider = Provider<Ref>((ref) => ref);

DatabaseRecord _record({
  String storageType = 'googleDrive',
  String databasePath = '/tmp/vault.kdbx',
}) {
  return DatabaseRecord(
    id: 'rec-1',
    nickname: 'My Vault',
    databasePath: databasePath,
    addedAt: DateTime(2026, 4, 1),
    storageType: storageType,
    cloudFileId: 'fake-id',
  );
}

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
  group('formatLastSync', () {
    final reference = DateTime(2026, 4, 28, 14, 30, 25);

    test('null → never', () {
      expect(formatLastSync(null, now: reference), 'Last synced: never');
    });

    test('within 5s → just now', () {
      expect(
        formatLastSync(
          reference.subtract(const Duration(seconds: 2)),
          now: reference,
        ),
        'Last synced: just now',
      );
    });

    test('seconds ago', () {
      expect(
        formatLastSync(
          reference.subtract(const Duration(seconds: 30)),
          now: reference,
        ),
        'Last synced: 30s ago',
      );
    });

    test('1 minute (singular)', () {
      expect(
        formatLastSync(
          reference.subtract(const Duration(minutes: 1, seconds: 2)),
          now: reference,
        ),
        'Last synced: 1 minute ago',
      );
    });

    test('several minutes ago', () {
      expect(
        formatLastSync(
          reference.subtract(const Duration(minutes: 12)),
          now: reference,
        ),
        'Last synced: 12 minutes ago',
      );
    });

    test('hours ago', () {
      expect(
        formatLastSync(
          reference.subtract(const Duration(hours: 3, minutes: 4)),
          now: reference,
        ),
        'Last synced: 3 hours ago',
      );
    });

    test('older than a day → wall-clock', () {
      final past = DateTime(2026, 4, 26, 9, 5, 7);
      expect(
        formatLastSync(past, now: reference),
        'Last synced: 09:05:07',
      );
    });
  });

  group('VaultAutoSyncController', () {
    test('records last-sync timestamp on success', () async {
      final clock = DateTime(2026, 4, 28, 12, 0, 0);
      final controller = VaultAutoSyncController(
        null,
        autoStart: false,
        recordResolver: () => _record(),
        refresh: (_) async {},
        clock: () => clock,
      );

      expect(controller.state.phase, VaultSyncPhase.idle);
      expect(controller.state.lastSyncAt, isNull);

      await controller.sync();

      expect(controller.state.phase, VaultSyncPhase.success);
      expect(controller.state.lastSyncAt, clock);
      expect(controller.state.error, isNull);

      controller.dispose();
    });

    test('captures error and exits syncing state', () async {
      final controller = VaultAutoSyncController(
        null,
        autoStart: false,
        recordResolver: () => _record(),
        refresh: (_) async => throw StateError('network down'),
      );

      await controller.sync();

      expect(controller.state.phase, VaultSyncPhase.error);
      expect(controller.state.isSyncing, isFalse);
      expect(controller.state.error, isA<StateError>());

      controller.dispose();
    });

    test('skips when no cloud-backed record is active', () async {
      var refreshCalls = 0;
      final controller = VaultAutoSyncController(
        null,
        autoStart: false,
        recordResolver: () => null,
        refresh: (_) async => refreshCalls++,
      );

      await controller.sync();

      expect(refreshCalls, 0);
      expect(controller.state.phase, VaultSyncPhase.idle);
      expect(controller.state.lastSyncAt, isNull);

      controller.dispose();
    });

    test('coalesces concurrent sync calls', () async {
      var refreshCalls = 0;
      final completer = Completer<void>();
      final controller = VaultAutoSyncController(
        null,
        autoStart: false,
        recordResolver: () => _record(),
        refresh: (_) async {
          refreshCalls++;
          await completer.future;
        },
      );

      final first = controller.sync();
      // Second call while first is still pending — must early-return.
      final second = controller.sync();
      // Allow microtasks to drain so the second call hits the early return.
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.isSyncing, isTrue);

      completer.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(refreshCalls, 1);
      expect(controller.state.phase, VaultSyncPhase.success);

      controller.dispose();
    });

    test('default interval is 30 seconds', () {
      final controller = VaultAutoSyncController(
        null,
        autoStart: false,
        recordResolver: () => null,
        refresh: (_) async {},
      );
      expect(controller.interval, const Duration(seconds: 30));
      controller.dispose();
    });

    test('marks transient state during sync, success after', () async {
      final completer = Completer<void>();
      final controller = VaultAutoSyncController(
        null,
        autoStart: false,
        recordResolver: () => _record(),
        refresh: (_) async => completer.future,
      );

      final pending = controller.sync();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, VaultSyncPhase.syncing);
      expect(controller.state.isSyncing, isTrue);

      completer.complete();
      await pending;

      expect(controller.state.phase, VaultSyncPhase.success);
      expect(controller.state.isSyncing, isFalse);

      controller.dispose();
    });

    test('clears prior error on next successful sync', () async {
      var fail = true;
      final controller = VaultAutoSyncController(
        null,
        autoStart: false,
        recordResolver: () => _record(),
        refresh: (_) async {
          if (fail) {
            throw StateError('boom');
          }
        },
      );

      await controller.sync();
      expect(controller.state.hasError, isTrue);

      fail = false;
      await controller.sync();
      expect(controller.state.hasError, isFalse);
      expect(controller.state.phase, VaultSyncPhase.success);
      expect(controller.state.error, isNull);

      controller.dispose();
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
        recordResolver: () => _record(databasePath: vaultFile.path),
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

    test('sync is a no-op flush when there are no pending writes', () async {
      final events = <String>[];
      final container = ProviderContainer(
        overrides: [
          vaultWriteSchedulerProvider.overrideWith((ref) {
            return VaultWriteScheduler(
              saveAndSync: () async {
                events.add('save');
                return _fakeDatabase();
              },
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final ref = container.read(_refProvider);
      final controller = VaultAutoSyncController(
        ref,
        autoStart: false,
        recordResolver: () => _record(),
        refresh: (_) async {
          events.add('refresh');
        },
      );
      addTearDown(controller.dispose);

      await controller.sync();

      expect(controller.state.phase, VaultSyncPhase.success);
      // Clean scheduler: flush is a no-op, only the refresh runs.
      expect(events, ['refresh']);
    });
  });
}
