import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/services/backup_service.dart';

/// Builds a backup file name matching the format produced by
/// `BackupService.runBackup`: `<label>_backup_<iso-with-punctuation-dashed>.kdbx`.
String _backupFileName(String label, DateTime timestamp) {
  final safe =
      timestamp.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
  return '${label}_backup_$safe.kdbx';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = BackupService.instance;

  // Stub path_provider so any incidental lookups resolve to a writable temp
  // dir. Prune itself uses the injected backup-root override.
  late Directory pathProviderTempRoot;
  setUp(() {
    pathProviderTempRoot =
        Directory.systemTemp.createTempSync('lp-retention-pp');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return pathProviderTempRoot.path;
    });
  });
  tearDown(() {
    if (pathProviderTempRoot.existsSync()) {
      pathProviderTempRoot.deleteSync(recursive: true);
    }
  });

  group('retention prune', () {
    late Directory backupRoot;
    late Directory vaultBackupDir;
    late ProviderContainer container;
    // Sanitized label BackupService derives from the vault path basename.
    const vaultLabel = 'my-vault';
    const vaultPath = '/vaults/my-vault.kdbx';
    // Pinned "now" so file-name timestamps have a deterministic age.
    final now = DateTime(2026, 7, 19, 12);

    setUp(() {
      backupRoot = Directory.systemTemp.createTempSync('lp-retention-root');
      vaultBackupDir = Directory('${backupRoot.path}/$vaultLabel')
        ..createSync(recursive: true);
      container = ProviderContainer();
      container.read(backupRetentionDaysProvider.notifier).state = 7;
      service.configureForTests(
        clock: () => now,
        backupRootDirectory: backupRoot.path,
        container: container,
      );
    });

    tearDown(() {
      container.dispose();
      if (backupRoot.existsSync()) {
        backupRoot.deleteSync(recursive: true);
      }
    });

    File writeBackup(DateTime timestamp) {
      final file = File(
        '${vaultBackupDir.path}/${_backupFileName(vaultLabel, timestamp)}',
      )..writeAsBytesSync(<int>[0]);
      return file;
    }

    test('deletes backups older than the retention window', () async {
      final fresh = writeBackup(now.subtract(const Duration(days: 1)));
      final borderline = writeBackup(now.subtract(const Duration(days: 6)));
      final expired = writeBackup(now.subtract(const Duration(days: 10)));
      final ancient = writeBackup(now.subtract(const Duration(days: 40)));

      await service.pruneOldBackupsForTesting(vaultPath);

      expect(fresh.existsSync(), isTrue, reason: '1-day-old backup kept');
      expect(borderline.existsSync(), isTrue, reason: '6-day-old backup kept');
      expect(expired.existsSync(), isFalse, reason: '10-day-old backup pruned');
      expect(ancient.existsSync(), isFalse, reason: '40-day-old backup pruned');
    });

    test('respects a shortened retention window', () async {
      container.read(backupRetentionDaysProvider.notifier).state = 3;

      final fresh = writeBackup(now.subtract(const Duration(days: 2)));
      final expired = writeBackup(now.subtract(const Duration(days: 5)));

      await service.pruneOldBackupsForTesting(vaultPath);

      expect(fresh.existsSync(), isTrue);
      expect(expired.existsSync(), isFalse);
    });

    test('keeps everything when all backups are within the window', () async {
      final a = writeBackup(now.subtract(const Duration(days: 1)));
      final b = writeBackup(now.subtract(const Duration(hours: 5)));

      await service.pruneOldBackupsForTesting(vaultPath);

      expect(a.existsSync(), isTrue);
      expect(b.existsSync(), isTrue);
    });
  });
}
