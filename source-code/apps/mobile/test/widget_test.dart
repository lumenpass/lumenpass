// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import 'package:mobile/app/routes.dart';
import 'package:mobile/core/repository/providers.dart';
import 'package:mobile/core/services/local_storage_service.dart';

import 'package:mobile/features/home/application/home_vault_providers.dart';
import 'package:mobile/features/home/presentation/home_screen.dart';
import 'package:mobile/features/unlock/presentation/unlock_vault_screen.dart';
import 'package:mobile/features/unlock/presentation/vault_picker_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

void main() {
  testWidgets('renders home screen content', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _TestApp(home: HomeScreen())),
    );
    expect(find.text('Recent Used'), findsOneWidget);
    expect(find.text('Recent Created'), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('renders redesigned items tab content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _TestApp(home: HomeScreen())),
    );

    await tester.tap(find.byIcon(Icons.grid_view_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('All Items'), findsOneWidget);
    expect(find.text('All Categories'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Item Types'), findsOneWidget);
  });

  testWidgets('renders vault picker content', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _TestApp(home: VaultPickerScreen(onUnlocked: () {})),
      ),
    );

    expect(find.text('Search vaults'), findsOneWidget);
    expect(find.bySemanticsLabel('Open actions'), findsOneWidget);
    expect(find.bySemanticsLabel('Search'), findsNothing);
    expect(find.bySemanticsLabel('Add vault'), findsNothing);
  });

  testWidgets('vault picker search filters as the query changes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStorageProvider.overrideWithValue(
            _FakeLocalStorageService(
              initial: <String, String>{
                'lumenpass_database_registry_v1': DatabaseRecord.listToJson([
                  _tranVaultRecord,
                  _hiddenPathOnlyRecord,
                ]),
              },
            ),
          ),
        ],
        child: _TestApp(home: VaultPickerScreen(onUnlocked: () {})),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('TranVault'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'T');
    await tester.pump();

    expect(find.text('TranVault'), findsOneWidget);
    expect(find.text('Work'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Tran');
    await tester.pump();

    expect(find.text('TranVault'), findsOneWidget);
    expect(find.text('Work'), findsNothing);
  });

  testWidgets('renders unlock vault content', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: _TestApp(home: UnlockVaultScreen(record: _testRecord)),
      ),
    );

    expect(find.text('Unlock Vault'), findsOneWidget);
    expect(find.text('Master Password'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });

  testWidgets('back from locked vault unlock returns to vault picker', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeVaultRecordProvider.overrideWithValue(_testRecord)],
        child: _TestApp(
          home: const HomeScreen(),
          routes: {Routes.vaults: (_) => VaultPickerScreen(onUnlocked: () {})},
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock Vault'));
    await tester.pumpAndSettle();

    expect(find.text('Lock vault?'), findsOneWidget);

    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Vault'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Search vaults'), findsOneWidget);
    expect(find.text('Last used items'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.home, this.routes});

  final Widget home;
  final Map<String, WidgetBuilder>? routes;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: home,
      routes: routes ?? const {},
    );
  }
}

final _testRecord = DatabaseRecord(
  id: 'test-id',
  nickname: 'Personal',
  databasePath: '/tmp/test.kdbx',
  addedAt: DateTime(2026, 4, 10),
  storageType: 'local',
);

final _tranVaultRecord = DatabaseRecord(
  id: 'tran-vault-id',
  nickname: 'TranVault',
  databasePath: '/tmp/tran-vault.kdbx',
  addedAt: DateTime(2026, 4, 12),
  storageType: 'local',
);

final _hiddenPathOnlyRecord = DatabaseRecord(
  id: 'hidden-path-only-id',
  nickname: 'Work',
  databasePath: '/Users/Tran/Cloud/Work.kdbx',
  addedAt: DateTime(2026, 4, 13),
  storageType: 'googleDrive',
  cloudFileName: 'work.kdbx',
);

class _FakeLocalStorageService extends LocalStorageService {
  _FakeLocalStorageService({Map<String, String>? initial})
    : _values = <String, String>{...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
