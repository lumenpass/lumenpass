import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/models/database_record.dart';
import 'package:lumenpass/core/models/kdbx_database.dart';
import 'package:lumenpass/core/models/kdbx_group.dart';
import 'package:lumenpass/core/repository/kdbx_repository_provider.dart';
import 'package:lumenpass/core/services/local_storage_service.dart';
import 'package:lumenpass/features/vault/presentation/vault_screen.dart';
import 'package:lumenpass/presentation/theme/drive_clue_tokens.dart';
import 'package:lumenpass/presentation/widgets/lumenpass_wordmark.dart';

void main() {
  testWidgets('vault actions menu uses the light sidebar menu treatment',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var switched = false;
    var imported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 256,
            child: VaultSidebarDropdown(
              record: null,
              databaseName: 'Test vault',
              onSwitchVault: () => switched = true,
              onImport: () => imported = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Current vault menu'));
    await tester.pumpAndSettle();

    final switchAction = find.text('Switch vault');
    expect(switchAction, findsOneWidget);
    expect(find.text('Import items'), findsOneWidget);

    final popupSurface = find
        .ancestor(
          of: switchAction,
          matching: find.byType(Material),
        )
        .first;
    expect(tester.widget<Material>(popupSurface).color, DcColors.lightSurface);
    expect(
        tester.widget<Text>(switchAction).style?.color, DcColors.sidebarText);

    await tester.tap(switchAction);
    await tester.pumpAndSettle();
    expect(switched, isTrue);
    expect(imported, isFalse);

    await tester.tap(find.byTooltip('Current vault menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import items'));
    await tester.pumpAndSettle();
    expect(imported, isTrue);
  });

  testWidgets(
      'switch vault dialog has branded dark title, light list, and active vault',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final records = <DatabaseRecord>[
      DatabaseRecord(
        id: 'active',
        nickname: 'Current vault',
        databasePath: '/tmp/current.kdbx',
        addedAt: DateTime.utc(2026, 10, 1),
        isDefaultStartup: true,
      ),
    ];
    final storage = _MemoryLocalStorageService(<String, String>{
      'lumenpass_database_registry_v1': DatabaseRecord.listToJson(records),
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(storage),
          activeDatabaseProvider.overrideWith((ref) => KdbxDatabase(
                name: 'Current vault',
                path: '/tmp/current.kdbx',
                rootGroup: const KdbxGroup(uuid: 'root', name: 'Root'),
                openedAt: DateTime.utc(2026, 10, 1),
              )),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: SwitchVaultModal())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialogPanel = find
        .descendant(
          of: find.byType(Dialog),
          matching: find.byType(Container),
        )
        .first;
    final panelDecoration =
        tester.widget<Container>(dialogPanel).decoration as BoxDecoration;
    expect(panelDecoration.color, DcColors.lightSurface);
    expect(panelDecoration.border, isNull);
    expect(find.byType(LumenPassWordmark), findsOneWidget);
    final title = find.text('Switch Vault');
    expect(tester.widget<Text>(title).style?.color, DcColors.text);
    final darkBar = find.ancestor(of: title, matching: find.byType(Container));
    expect(
        darkBar.evaluate().any((element) {
          final container = element.widget as Container;
          return container.constraints?.maxHeight == DcMetrics.headerHeight &&
              container.decoration is BoxDecoration &&
              (container.decoration as BoxDecoration).color ==
                  DcColors.background;
        }),
        isTrue);
    expect(tester.widget<Text>(find.text('Current vault')).style?.color,
        DcColors.sidebarText);
    expect(find.text('Current vault'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Select'), findsNothing);
    expect(tester.widget<InkWell>(find.byType(InkWell).last).onTap, isNull);

    await tester.tap(find.byTooltip('Close dialog'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchVaultModal), findsNothing);
  });
}

class _MemoryLocalStorageService extends LocalStorageService {
  _MemoryLocalStorageService(this._values);

  final Map<String, String> _values;

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, String? value}) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}
