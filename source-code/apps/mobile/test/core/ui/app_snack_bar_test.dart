import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ui/app_snack_bar.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => AppSnackBar.info(
                  context,
                  'A new version is available: v1.2.3',
                  onTap: onTap,
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  tearDown(AppSnackBar.dismissCurrent);

  testWidgets('tapping the toast message body fires onTap and dismisses toast', (
    WidgetTester tester,
  ) async {
    var tapped = 0;
    await pumpHost(tester, onTap: () => tapped++);

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('A new version is available: v1.2.3'), findsOneWidget);

    await tester.tap(find.text('A new version is available: v1.2.3'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(find.text('A new version is available: v1.2.3'), findsNothing);
  });

  testWidgets('tapping the dismiss button closes the toast without firing onTap',
      (WidgetTester tester) async {
    var tapped = 0;
    await pumpHost(tester, onTap: () => tapped++);

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('A new version is available: v1.2.3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(tapped, 0);
    expect(find.text('A new version is available: v1.2.3'), findsNothing);
  });
}
