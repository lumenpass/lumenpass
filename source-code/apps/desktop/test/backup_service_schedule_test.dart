import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/services/backup_service.dart';

void main() {
  group('fixed local backup schedule', () {
    final service = BackupService.instance;

    test('aligns to the next four-hour local wall-clock boundary', () {
      expect(
        service.nextFixedBackupTime(DateTime(2026, 4, 30, 3, 55)),
        DateTime(2026, 4, 30, 4),
      );
      expect(
        service.nextFixedBackupTime(DateTime(2026, 4, 30, 4)),
        DateTime(2026, 4, 30, 8),
      );
      expect(
        service.nextFixedBackupTime(DateTime(2026, 4, 30, 23, 59)),
        DateTime(2026, 5, 1),
      );
    });

    test('produces exactly six fixed backup boundaries per local day', () {
      var current = DateTime(2026, 4, 30);
      final boundaries = <DateTime>[];
      for (var i = 0; i < 6; i++) {
        final next = service.nextFixedBackupTime(current);
        boundaries.add(next);
        current = next;
      }

      expect(boundaries.map((date) => date.hour), <int>[4, 8, 12, 16, 20, 0]);
      expect(boundaries.last.day, 1);
    });

    test('survives clock changes by recalculating from current local time', () {
      expect(
        service.nextFixedBackupTime(DateTime(2026, 4, 30, 10, 15)),
        DateTime(2026, 4, 30, 12),
      );
      expect(
        service.nextFixedBackupTime(DateTime(2026, 4, 30, 7, 15)),
        DateTime(2026, 4, 30, 8),
      );
    });

    test('uses valid local boundaries across DST-style dates', () {
      final spring = service.nextFixedBackupTime(DateTime(2026, 3, 8, 1, 59));
      final fall = service.nextFixedBackupTime(DateTime(2026, 11, 1, 1, 59));

      expect(BackupService.fixedLocalBackupHours, contains(spring.hour));
      expect(BackupService.fixedLocalBackupHours, contains(fall.hour));
      expect(spring.minute, 0);
      expect(fall.minute, 0);
    });
  });

  group('open local backup folder process selection', () {
    test('invokes the macOS file manager on macOS', () async {
      if (!Platform.isMacOS) return;
      final calls = <String>[];
      BackupService.instance.configureForTests(
        backupRootDirectory:
            Directory.systemTemp.createTempSync('lp-backup-test').path,
        processRunner: (executable, arguments) async {
          calls.add('$executable ${arguments.join(' ')}');
          return ProcessResult(0, 0, '', '');
        },
      );

      await BackupService.instance.openLocalBackupFolder();

      expect(calls.single, startsWith('open '));
    });
  });
}
