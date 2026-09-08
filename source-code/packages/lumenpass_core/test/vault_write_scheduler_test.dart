import 'dart:async';

import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:test/test.dart';

/// Builds a [VaultWriteScheduler] whose save closure counts invocations and
/// can be made to fail or stall on demand.
class _Harness {
  _Harness({Duration debounce = const Duration(milliseconds: 50)}) {
    scheduler = VaultWriteScheduler(
      saveAndSync: _save,
      onSaveError: (error, _) => errors.add(error),
      debounce: debounce,
      failureRetryDelay: const Duration(milliseconds: 40),
    );
  }

  late final VaultWriteScheduler scheduler;
  final errors = <Object>[];
  int saveCount = 0;
  int failuresRemaining = 0;
  final _inFlight = <Completer<void>>[];

  Future<KdbxDatabase> _save() async {
    saveCount++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('simulated save failure');
    }
    if (_inFlight.isNotEmpty) {
      final completer = _inFlight.removeAt(0);
      await completer.future;
    }
    // A real save is never synchronous; yield so ordering is observable.
    await Future<void>.delayed(Duration.zero);
    return _fakeDatabase();
  }

  /// Makes the next save stall until the returned completer completes.
  Completer<void> stallNextSave() {
    final completer = Completer<void>();
    _inFlight.add(completer);
    return completer;
  }
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

void main() {
  group('VaultWriteScheduler', () {
    test('immediate lane coalesces a burst into one save', () async {
      final harness = _Harness();
      harness.scheduler.markDirtyImmediate();
      harness.scheduler.markDirtyImmediate();
      harness.scheduler.markDirtyImmediate();

      await harness.scheduler.flushNow();
      expect(harness.saveCount, 1);
      expect(harness.scheduler.hasPendingWrites, isFalse);
    });

    test('debounced lane waits for the debounce window', () async {
      final harness = _Harness(debounce: const Duration(milliseconds: 60));
      harness.scheduler.markDirtyDebounced();
      expect(harness.scheduler.hasPendingWrites, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(harness.saveCount, 0);

      await harness.scheduler.flushNow();
      expect(harness.saveCount, 1);
    });

    test('debounced lane saves on its own after the window', () async {
      final harness = _Harness(debounce: const Duration(milliseconds: 30));
      harness.scheduler.markDirtyDebounced();

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(harness.saveCount, 1);
      expect(harness.scheduler.hasPendingWrites, isFalse);
    });

    test('immediate request supersedes a pending debounced save', () async {
      final harness = _Harness(debounce: const Duration(seconds: 5));
      harness.scheduler.markDirtyDebounced();
      harness.scheduler.markDirtyImmediate();

      await harness.scheduler.flushNow();
      expect(harness.saveCount, 1);
    });

    test('mutations during an in-flight save trigger one follow-up save',
        () async {
      final harness = _Harness();
      final gate = harness.stallNextSave();
      harness.scheduler.markDirtyImmediate();

      // Let the first save start and stall.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(harness.saveCount, 1);

      harness.scheduler.markDirtyImmediate();
      gate.complete();

      await harness.scheduler.flushNow();
      expect(harness.saveCount, 2);
      expect(harness.scheduler.hasPendingWrites, isFalse);
    });

    test('flushNow is a no-op when clean', () async {
      final harness = _Harness();
      await harness.scheduler.flushNow();
      expect(harness.saveCount, 0);
    });

    test('save errors surface via onSaveError and keep the dirty flag',
        () async {
      final harness = _Harness();
      harness.failuresRemaining = 1;
      harness.scheduler.markDirtyImmediate();

      await harness.scheduler.flushNow();
      expect(harness.errors, hasLength(1));
      expect(harness.scheduler.hasPendingWrites, isTrue);

      // Next flush point retries and succeeds.
      await harness.scheduler.flushNow();
      expect(harness.saveCount, 2);
      expect(harness.scheduler.hasPendingWrites, isFalse);
    });

    test('failed saves retry automatically after the retry delay', () async {
      final harness = _Harness();
      harness.failuresRemaining = 1;
      harness.scheduler.markDirtyImmediate();

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(harness.saveCount, 2);
      expect(harness.errors, hasLength(1));
      expect(harness.scheduler.hasPendingWrites, isFalse);
    });

    test('reset clears pending state without saving', () async {
      final harness = _Harness(debounce: const Duration(seconds: 5));
      harness.scheduler.markDirtyDebounced();
      harness.scheduler.reset();

      expect(harness.scheduler.hasPendingWrites, isFalse);
      await harness.scheduler.flushNow();
      expect(harness.saveCount, 0);
    });

    test('dispose prevents further saves', () async {
      final harness = _Harness();
      harness.scheduler.dispose();
      harness.scheduler.markDirtyImmediate();
      await harness.scheduler.flushNow();
      expect(harness.saveCount, 0);
    });

    test('concurrent flushNow callers all observe a clean state', () async {
      final harness = _Harness();
      final gate = harness.stallNextSave();
      harness.scheduler.markDirtyImmediate();

      final f1 = harness.scheduler.flushNow();
      final f2 = harness.scheduler.flushNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      await Future.wait([f1, f2]);

      expect(harness.saveCount, 1);
      expect(harness.scheduler.hasPendingWrites, isFalse);
    });
  });
}
