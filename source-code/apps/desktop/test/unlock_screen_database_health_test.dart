import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumenpass/core/models/database_record.dart';
import 'package:lumenpass/core/repository/kdbx_repository_provider.dart';
import 'package:lumenpass/core/services/local_storage_service.dart';
import 'package:lumenpass/features/unlock/application/database_connection_health.dart';

import 'package:lumenpass/features/unlock/presentation/unlock_screen.dart';

void main() {
  testWidgets(
    'cloud vault health errors disable unlock and open the details dialog',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final record = DatabaseRecord(
        id: 'vault-1',
        nickname: 'Primary Vault',
        databasePath: '/tmp/primary-vault.kdbx',
        addedAt: DateTime.utc(2026, 6, 12),
        isDefaultStartup: true,
        storageType: 'googleDrive',
        cloudFileId: 'drive-file-id',
      );

      final storage = _MemoryLocalStorageService(
        <String, String>{
          'lumenpass_database_registry_v1': DatabaseRecord.listToJson(
            <DatabaseRecord>[record],
          ),
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            localStorageProvider.overrideWithValue(storage),
            databaseConnectionHealthProbeProvider.overrideWithValue(
              const _FakeDatabaseConnectionHealthProbe(
                DatabaseConnectionHealth.error(
                  code: 'pending_sync_failure',
                  providerLabel: 'Google Drive',
                  title: 'Pending changes did not sync',
                  details:
                      'The last upload for this vault could not be confirmed.',
                  recommendedActions: <String>[
                    'Reconnect Google Drive.',
                    'Check again before unlocking this vault.',
                  ],
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: UnlockScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pumpAndSettle();

      expect(find.text('Primary Vault'), findsOneWidget);
      expect(find.byTooltip('Show sync issue details'), findsOneWidget);

      final unlockButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Unlock'));
      expect(unlockButton.onPressed, isNull);

      await tester.tap(find.byTooltip('Show sync issue details'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Pending changes did not sync'),
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Reconnect Google Drive'),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Unlink Databases'), findsOneWidget);
    },
  );
}

class _FakeDatabaseConnectionHealthProbe extends DatabaseConnectionHealthProbe {
  const _FakeDatabaseConnectionHealthProbe(this.health);

  final DatabaseConnectionHealth health;

  @override
  Future<DatabaseConnectionHealth> check(DatabaseRecord record) async => health;
}

class _MemoryLocalStorageService extends LocalStorageService {
  _MemoryLocalStorageService([Map<String, String>? initialValues])
      : _values = <String, String>{...?initialValues};

  final Map<String, String> _values;

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, String? value}) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}
