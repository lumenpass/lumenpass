import 'dart:io';
import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:kdbx/kdbx.dart' as native;
import 'package:kdbx/src/internal/pointycastle_argon2.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:test/test.dart';

void main() {
  group('IsolateArgon2', () {
    final args = Argon2Arguments(
      Uint8List.fromList(List<int>.generate(32, (i) => i)), // key
      Uint8List.fromList(List<int>.generate(32, (i) => 255 - i)), // salt
      1024, // memory (KiB) — small for test speed
      2, // iterations
      32, // desired key length
      1, // parallelism
      2, // Argon2id
      0x13, // version 1.3
    );

    test('sync output matches the kdbx default PointyCastle implementation',
        () {
      const reference = PointyCastleArgon2();
      const isolate = IsolateArgon2();

      final expected = reference.argon2(args);
      final actual = isolate.argon2(args);

      expect(actual, expected);
    });

    test('async output matches the sync output', () async {
      const isolate = IsolateArgon2();

      final sync = isolate.argon2(args);
      final async = await isolate.argon2Async(args);

      expect(async, sync);
      expect(async.length, 32);
    });

    test('async runs off the calling isolate (does not block the event loop)',
        () async {
      const isolate = IsolateArgon2();
      // Heavy parameters so the KDF takes a measurable amount of time.
      final heavy = Argon2Arguments(
        args.key,
        args.salt,
        8 * 1024,
        3,
        32,
        1,
        2,
        0x13,
      );

      var ticks = 0;
      final ticker = Stream<void>.periodic(const Duration(milliseconds: 10))
          .listen((_) => ticks++);

      final future = isolate.argon2Async(heavy);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final ticksWhileRunning = ticks;
      await future;
      await ticker.cancel();

      // If the KDF ran on this isolate, the periodic stream would have been
      // starved and produced (almost) no ticks while it computed.
      expect(ticksWhileRunning, greaterThanOrEqualTo(2));
    });

    test('KDBX4 round-trip: save and reopen with IsolateArgon2', () async {
      // End-to-end proof that files written with the isolate-backed KDF are
      // byte-compatible: create, save, reopen with the default implementation.
      final repository = KdbxRepositoryImpl(
        format: native.KdbxFormat(const IsolateArgon2()),
        totpService: const TOTPService(),
      );

      final tempDir = await Directory.systemTemp.createTemp('argon2_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final path = '${tempDir.path}/vault.kdbx';

      await repository.createDatabase(
        databasePath: path,
        databaseName: 'Argon2 Vault',
        password: 'hunter2',
      );
      await repository.createEntry(
        groupUuid: repository.rootGroupUuid!,
        fields: const <EntryField>[
          EntryField(key: AppKdbxFieldKeys.title, value: 'Example'),
        ],
      );
      await repository.saveDatabase();
      repository.closeDatabase();

      // Reopen with the stock kdbx implementation (no IsolateArgon2).
      final stockRepository = KdbxRepositoryImpl(
        format: native.KdbxFormat(),
        totpService: const TOTPService(),
      );
      final reopened = await stockRepository.openDatabase(
        databasePath: path,
        password: 'hunter2',
      );
      expect(reopened.entryCount, 1);
      stockRepository.closeDatabase();
    });
  });
}
