import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumenpass/core/models/database_record.dart';
import 'package:lumenpass/core/repository/kdbx_repository_provider.dart';
import 'package:lumenpass/core/services/local_storage_service.dart';
import 'package:lumenpass/features/unlock/application/database_connection_health.dart';
import 'package:lumenpass/features/unlock/presentation/unlock_screen.dart';

void main() {
  testWidgets('shows vault counts and the requested supported platforms',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(820, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final records = <DatabaseRecord>[
      _record('local-1', 'local', isDefault: true),
      _record('local-2', 'local'),
      _record('drive-1', 'googleDrive'),
      _record('dropbox-1', 'dropbox'),
      _record('s3-1', 's3'),
      _record('webdav-1', 'webdav'),
    ];
    final storage = _MemoryLocalStorageService(<String, String>{
      'lumenpass_database_registry_v1': DatabaseRecord.listToJson(records),
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(storage),
          databaseConnectionHealthProbeProvider.overrideWithValue(
            const _HealthyDatabaseConnectionHealthProbe(),
          ),
        ],
        child: const MaterialApp(home: UnlockScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3500));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Total vaults: 6'), findsOneWidget);

    for (final entry in <String, String>{
      'local': 'Local vaults: 2',
      'googleDrive': 'Google Drive vaults: 1',
      'dropbox': 'Dropbox vaults: 1',
      's3': 'Amazon S3 vaults: 1',
      'webdav': 'WebDAV vaults: 1',
    }.entries) {
      expect(
        find.byKey(ValueKey<String>('supported-platform-${entry.key}')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(entry.value),
        findsOneWidget,
      );
    }
  });
}

DatabaseRecord _record(
  String id,
  String storageType, {
  bool isDefault = false,
}) {
  return DatabaseRecord(
    id: id,
    nickname: id,
    databasePath: '/tmp/$id.kdbx',
    addedAt: DateTime.utc(2026, 9, 23),
    isDefaultStartup: isDefault,
    storageType: storageType,
    cloudFileId: storageType == 'local' ? null : '$id-cloud-file',
  );
}

class _HealthyDatabaseConnectionHealthProbe
    extends DatabaseConnectionHealthProbe {
  const _HealthyDatabaseConnectionHealthProbe();

  @override
  Future<DatabaseConnectionHealth> check(DatabaseRecord record) async {
    return DatabaseConnectionHealth.healthy(
      providerLabel: providerLabelForStorageType(record.storageType),
    );
  }
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
