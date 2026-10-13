import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumenpass/presentation/widgets/lumenpass_wordmark.dart';

void main() {
  testWidgets('renders the LumenPass signature colors and optional suffix',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LumenPassWordmark(suffix: ' vaults'),
      ),
    );

    expect(find.text('LumenPass vaults', findRichText: true), findsOneWidget);

    final text = tester.widget<Text>(find.byType(Text));
    final spans = (text.textSpan! as TextSpan).children!;
    expect((spans[0] as TextSpan).style?.color, lumenPassInk);
    expect((spans[1] as TextSpan).style?.color, lumenPassOrange);
    expect((spans[2] as TextSpan).style?.color, lumenPassInk);
  });
}
