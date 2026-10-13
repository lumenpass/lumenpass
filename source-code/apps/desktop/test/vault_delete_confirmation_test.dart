import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/vault/presentation/vault_screen.dart';

void main() {
  testWidgets('permanent delete requires an explicit named confirmation',
      (tester) async {
    var confirmed = false;
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VaultDeleteConfirmationOverlay(
          entryTitle: 'QA item',
          isDeleting: false,
          isPermanent: true,
          onCancel: () => cancelled = true,
          onConfirm: () => confirmed = true,
        ),
      ),
    ));

    expect(find.textContaining('QA item'), findsOneWidget);
    expect(find.textContaining('cannot be recovered'), findsOneWidget);
    expect(find.text('Delete permanently'), findsOneWidget);
    expect(confirmed, isFalse);

    await tester.tap(find.text('Cancel'));
    expect(cancelled, isTrue);
    expect(confirmed, isFalse);
  });

  testWidgets('permanent delete runs only after the destructive action',
      (tester) async {
    var confirmations = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VaultDeleteConfirmationOverlay(
          entryTitle: 'QA item',
          isDeleting: false,
          isPermanent: true,
          onCancel: () {},
          onConfirm: () => confirmations++,
        ),
      ),
    ));

    expect(confirmations, 0);
    await tester.tap(find.text('Delete permanently'));
    expect(confirmations, 1);
  });
}
