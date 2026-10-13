import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/services/backup_service.dart';

/// KDBX v4 magic-byte sequence used to forge "structurally valid" fixtures
/// in unit tests. The bytes match `_kdbxSignature1` + `_kdbxSignature2`
/// inside [BackupService] but we re-declare them here so a regression in
/// either place fails the tests rather than silently agreeing.
const List<int> _kdbxHeader = <int>[
  0x03, 0xD9, 0xA2, 0x9A, // signature 1
  0x67, 0xFB, 0x4B, 0xB5, // signature 2
];

List<int> _validKdbxBytes({int padding = 256}) =>
    <int>[..._kdbxHeader, ...List<int>.filled(padding, 0)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = BackupService.instance;

  // Stub `getTemporaryDirectory` so restoreLocalBackup can stage its
  // fallback + temp copies inside a writable directory during tests.
  late Directory pathProviderTempRoot;
  setUp(() {
    pathProviderTempRoot = Directory.systemTemp.createTempSync('lp-restore-pp');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory' ||
          call.method == 'getApplicationSupportDirectory') {
        return pathProviderTempRoot.path;
      }
      return null;
    });
  });
  tearDown(() {
    if (pathProviderTempRoot.existsSync()) {
      pathProviderTempRoot.deleteSync(recursive: true);
    }
  });

  group('validateBackupFile', () {
    test('rejects a missing file', () async {
      final issue = await service.validateBackupFile(
        backupPath:
            '/tmp/does-not-exist-${DateTime.now().microsecondsSinceEpoch}.kdbx',
      );
      expect(issue, isNotNull);
      expect(issue, contains('no longer exists'));
    });

    test('rejects a non-kdbx extension', () async {
      final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
      try {
        final f = File('${tempDir.path}/backup.txt');
        f.writeAsBytesSync(_validKdbxBytes());
        final issue = await service.validateBackupFile(backupPath: f.path);
        expect(issue, contains('Only .kdbx'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('rejects an empty / truncated file', () async {
      final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
      try {
        final f = File('${tempDir.path}/backup.kdbx');
        f.writeAsBytesSync(<int>[1, 2, 3]);
        final issue = await service.validateBackupFile(backupPath: f.path);
        expect(issue, contains('corrupt'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('rejects a file with a wrong magic-byte header', () async {
      final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
      try {
        final f = File('${tempDir.path}/backup.kdbx');
        f.writeAsBytesSync(List<int>.filled(64, 0));
        final issue = await service.validateBackupFile(backupPath: f.path);
        expect(issue, contains('not in KDBX format'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('rejects restoring the live vault onto itself', () async {
      final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
      try {
        final f = File('${tempDir.path}/vault.kdbx');
        f.writeAsBytesSync(_validKdbxBytes());
        final issue = await service.validateBackupFile(
          backupPath: f.path,
          targetVaultPath: f.path,
        );
        expect(issue, contains('onto itself'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('accepts a structurally valid kdbx file without a password', () async {
      final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
      try {
        final f = File('${tempDir.path}/snap.kdbx');
        f.writeAsBytesSync(_validKdbxBytes());
        final issue = await service.validateBackupFile(backupPath: f.path);
        expect(issue, isNull);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('restoreLocalBackup', () {
    test('throws when no target vault path can be resolved', () async {
      final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
      try {
        final backup = File('${tempDir.path}/snap.kdbx');
        backup.writeAsBytesSync(_validKdbxBytes());
        await expectLater(
          () => service.restoreLocalBackup(
            LocalBackupInfo(
              path: backup.path,
              fileName: 'snap.kdbx',
              sizeBytes: backup.lengthSync(),
              createdAt: DateTime.now(),
            ),
            targetVaultPath: null,
          ),
          throwsA(isA<StateError>()),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('recreates the vault when the live file is missing on disk', () async {
      final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
      try {
        final ghost = File('${tempDir.path}/missing.kdbx');
        final backup = File('${tempDir.path}/snap.kdbx');
        final backupBytes = _validKdbxBytes(padding: 128);
        backup.writeAsBytesSync(backupBytes);

        await service.restoreLocalBackup(
          LocalBackupInfo(
            path: backup.path,
            fileName: 'snap.kdbx',
            sizeBytes: backup.lengthSync(),
            createdAt: DateTime.now(),
          ),
          targetVaultPath: ghost.path,
        );

        expect(await ghost.exists(), isTrue);
        expect(await ghost.readAsBytes(), equals(backupBytes));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('replaces the live vault bytes with the backup bytes', () async {
      final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
      try {
        final live = File('${tempDir.path}/live.kdbx');
        final backup = File('${tempDir.path}/snap.kdbx');
        final liveBytes = _validKdbxBytes(padding: 32);
        final backupBytes = _validKdbxBytes(padding: 512);
        live.writeAsBytesSync(liveBytes);
        backup.writeAsBytesSync(backupBytes);

        await service.restoreLocalBackup(
          LocalBackupInfo(
            path: backup.path,
            fileName: 'snap.kdbx',
            sizeBytes: backup.lengthSync(),
            createdAt: DateTime.now(),
          ),
          targetVaultPath: live.path,
        );

        expect(await live.readAsBytes(), equals(backupBytes));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'rolls back to the original vault if the staged backup is invalid',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('lp-restore-test');
        try {
          final live = File('${tempDir.path}/live.kdbx');
          final corrupt = File('${tempDir.path}/snap.kdbx');
          final liveBytes = _validKdbxBytes(padding: 32);
          live.writeAsBytesSync(liveBytes);
          // Wrong magic — passes file existence + extension checks but
          // fails the structural validator.
          corrupt.writeAsBytesSync(List<int>.filled(64, 0));
          await expectLater(
            () => service.restoreLocalBackup(
              LocalBackupInfo(
                path: corrupt.path,
                fileName: 'snap.kdbx',
                sizeBytes: corrupt.lengthSync(),
                createdAt: DateTime.now(),
              ),
              targetVaultPath: live.path,
            ),
            throwsA(anything),
          );
          // Live vault should be untouched.
          expect(await live.readAsBytes(), equals(liveBytes));
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );
  });
}
