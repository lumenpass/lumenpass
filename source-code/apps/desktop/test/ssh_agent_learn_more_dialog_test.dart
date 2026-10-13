import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumenpass/features/vault/presentation/vault_screen.dart';

void main() {
  testWidgets('SSH Agent learn more dialog explains the signing flow',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              return TextButton(
                onPressed: () => showSshAgentLearnMoreDialog(context),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('About SSH Agent'), findsOneWidget);
    expect(find.text('Keeps private keys inside LumenPass'), findsOneWidget);
    expect(find.text('Asks before signing'), findsOneWidget);
    expect(find.text('Connects to SSH automatically'), findsOneWidget);
    expect(find.textContaining('IdentityAgent'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.text('About SSH Agent'), findsNothing);
  });
}
