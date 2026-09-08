import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:mobile/features/vault/application/vault_entries_providers.dart';
import 'package:mobile/features/vault/presentation/vault_items_tab.dart';

void main() {
  testWidgets('long press on a category shows edit and delete actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultVisibleEntriesProvider.overrideWith((ref) => <KdbxEntry>[]),
          vaultUncategorizedCountProvider.overrideWith((ref) => 0),
          vaultSidebarCategoriesProvider.overrideWith(
            (ref) => [
              (
                uuid: 'cat-1',
                name: 'Cate #2',
                notes: 'lumenpass-category-icon:img:1|teal',
                count: 0,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: VaultItemsTab())),
      ),
    );

    await tester.pumpAndSettle();

    await tester.longPress(find.text('Cate #2'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Category'), findsOneWidget);
    expect(find.text('Delete Category'), findsOneWidget);
  });

  testWidgets('delete action opens a confirmation dialog', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultVisibleEntriesProvider.overrideWith((ref) => <KdbxEntry>[]),
          vaultUncategorizedCountProvider.overrideWith((ref) => 0),
          vaultSidebarCategoriesProvider.overrideWith(
            (ref) => [
              (
                uuid: 'cat-1',
                name: 'Cate #2',
                notes: 'lumenpass-category-icon:img:1|teal',
                count: 0,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: VaultItemsTab())),
      ),
    );

    await tester.pumpAndSettle();

    await tester.longPress(find.text('Cate #2'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete Category'));
    await tester.pumpAndSettle();

    expect(find.text('Delete category?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
