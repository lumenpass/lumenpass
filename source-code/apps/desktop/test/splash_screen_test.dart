import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumenpass/features/unlock/presentation/splash_screen.dart';

void main() {
  testWidgets('shows global loading and completes after three seconds',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(820, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopSplashScreen(onFinished: () => completed = true),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('splash-wordmark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('splash-loading-dots')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(find.text('LumenPass', findRichText: true), findsOneWidget);
    expect(
      find.text('Private by default. Yours to control.'),
      findsOneWidget,
    );
    expect(completed, isFalse);

    await tester.pump(const Duration(milliseconds: 2999));
    expect(completed, isFalse);

    await tester.pump(const Duration(milliseconds: 2));
    expect(completed, isTrue);
  });
}
