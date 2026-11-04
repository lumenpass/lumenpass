import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass/core/models/database_record.dart';
import 'package:lumenpass/core/repository/kdbx_repository_provider.dart';
import 'package:lumenpass/core/services/local_storage_service.dart';
import 'package:lumenpass/features/unlock/application/database_connection_health.dart';
import 'package:lumenpass/features/unlock/application/vault_group_order.dart';
import 'package:lumenpass/features/unlock/presentation/unlock_screen.dart';

void main() {
  group('VaultGroupOrderNotifier', () {
    late _MemoryLocalStorageService storage;

    setUp(() => storage = _MemoryLocalStorageService());

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('persists the reordered provider list', () async {
      final c = container();
      await c.read(vaultGroupOrderProvider.notifier).ready;

      await c.read(vaultGroupOrderProvider.notifier).applyVisibleOrder(
        <String>['googleDrive', 'local'],
        knownOrder: <String>['local', 'googleDrive', 'dropbox'],
      );

      expect(c.read(vaultGroupOrderProvider), <String>[
        'googleDrive',
        'local',
        // `dropbox` was not visible but keeps its original slot.
        'dropbox',
      ]);
      expect(
        await storage.read(key: 'lumenpass_vault_group_order_v1'),
        'googleDrive,local,dropbox',
      );
    });

    test('restores the persisted order on next launch', () async {
      storage = _MemoryLocalStorageService(<String, String>{
        'lumenpass_vault_group_order_v1': 'dropbox,local,googleDrive',
      });

      final c = container();
      await c.read(vaultGroupOrderProvider.notifier).ready;

      expect(c.read(vaultGroupOrderProvider), <String>[
        'dropbox',
        'local',
        'googleDrive',
      ]);
    });

    test('keeps hidden providers in their original slots', () async {
      storage = _MemoryLocalStorageService(<String, String>{
        'lumenpass_vault_group_order_v1': 'local,googleDrive,dropbox',
      });

      final c = container();
      await c.read(vaultGroupOrderProvider.notifier).ready;

      // Only `local` + `googleDrive` are visible (e.g. behind a search) and the
      // user swaps them; `dropbox` must not move.
      await c.read(vaultGroupOrderProvider.notifier).applyVisibleOrder(
        <String>['googleDrive', 'local'],
        knownOrder: <String>['local', 'googleDrive', 'dropbox'],
      );

      expect(c.read(vaultGroupOrderProvider), <String>[
        'googleDrive',
        'local',
        'dropbox',
      ]);
    });

    test('appends providers that had no persisted slot yet', () async {
      storage = _MemoryLocalStorageService(<String, String>{
        'lumenpass_vault_group_order_v1': 'local',
      });

      final c = container();
      await c.read(vaultGroupOrderProvider.notifier).ready;

      await c.read(vaultGroupOrderProvider.notifier).applyVisibleOrder(
        <String>['local', 'webdav'],
        knownOrder: <String>['local', 'webdav'],
      );

      expect(c.read(vaultGroupOrderProvider), <String>['local', 'webdav']);
    });

    test('ignores an empty visible order', () async {
      final c = container();
      await c.read(vaultGroupOrderProvider.notifier).ready;

      await c.read(vaultGroupOrderProvider.notifier).applyVisibleOrder(
        const <String>[],
        knownOrder: const <String>['local'],
      );

      expect(c.read(vaultGroupOrderProvider), isEmpty);
    });
  });

  testWidgets('unlock screen renders one reorderable group per provider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final records = <DatabaseRecord>[
      _record('local-1', 'local', isDefault: true),
      _record('drive-1', 'googleDrive'),
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

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('THIS MAC'), findsOneWidget);
    expect(find.text('GOOGLE DRIVE'), findsOneWidget);

    // One drag handle per group, and the old trailing label is gone.
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.text('Vaults'), findsNothing);
    expect(find.text('Vault'), findsNothing);
    expect(find.text('Move'), findsNWidgets(2));
  });

  testWidgets('dragging a group handle persists the new provider order', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final records = <DatabaseRecord>[
      _record('local-1', 'local', isDefault: true),
      _record('drive-1', 'googleDrive'),
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

    double groupTop(String title) =>
        tester.getTopLeft(find.text(title)).dy;
    expect(groupTop('THIS MAC'), lessThan(groupTop('GOOGLE DRIVE')));

    // Grip the first group's handle and drop it below the second group.
    final firstHandle = find.byIcon(TablerIcons.grip_vertical).first;
    final gesture = await tester.startGesture(tester.getCenter(firstHandle));
    await tester.pump(const Duration(milliseconds: 20));
    // Incremental moves so the drag recognizer tracks the pointer.
    for (var i = 0; i < 24; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(groupTop('GOOGLE DRIVE'), lessThan(groupTop('THIS MAC')));
    expect(
      await storage.read(key: 'lumenpass_vault_group_order_v1'),
      allOf(contains('googleDrive'), contains('local')),
    );
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
