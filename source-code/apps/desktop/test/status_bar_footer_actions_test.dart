import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumenpass/presentation/theme/drive_clue_tokens.dart';
import 'package:lumenpass/presentation/widgets/drive_clue/drive_clue_widgets.dart';

void main() {
  group('DcStatusBar with footer actions', () {
    Widget harness(List<Widget> leading, List<Widget> trailing) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: DcStatusBar(leading: leading, trailing: trailing),
          ),
        ),
      );
    }

    testWidgets('keeps actions inside the 28 px bar on a narrow window', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(980, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        harness(
          const <Widget>[Text('Last synced: never')],
          const <Widget>[
            DcStatusBarAction(
              icon: Icons.shield,
              label: 'Free license',
              bold: true,
              url: 'https://www.lumenpass.app/downloads',
            ),
            DcStatusBarAction(
              icon: Icons.download,
              label: 'Other platforms',
              url: 'https://www.lumenpass.app/downloads',
            ),
            DcStatusBarAction(
              icon: Icons.code,
              label: 'GitHub',
              url: 'https://github.com/lumenpass/lumenpass',
            ),
            DcStatusBarAction(
              icon: Icons.coffee,
              label: 'Buy me a coffee',
              url: 'https://donorbox.org/donate-to-tranit',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Nothing overflows, and the bar keeps its fixed height.
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(DcStatusBar)).height,
        DcMetrics.statusBarHeight,
      );
      // Narrow windows drop labels but keep every action reachable.
      expect(find.byIcon(Icons.coffee), findsOneWidget);
      expect(find.byIcon(Icons.code), findsOneWidget);
    });

    testWidgets('fits the real vault footer at the 1200 px window width', (
      WidgetTester tester,
    ) async {
      // The status bar spans the whole window; at 1200 px the content box is
      // 1200 - 2*14 padding = 1172, which is above [DcStatusBar.compactWidth]
      // so every label must still be visible.
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        harness(
          const <Widget>[
            SizedBox(width: 150, child: Text('Last synced: never')),
            Icon(Icons.refresh, size: 14),
          ],
          const <Widget>[
            DcStatusBarAction(
              icon: Icons.shield,
              label: 'Free license',
              bold: true,
              url: 'https://www.apache.org/licenses/LICENSE-2.0',
            ),
            DcStatusBarAction(
              icon: Icons.download,
              label: 'Other platforms & extensions',
              url: 'https://www.lumenpass.app/downloads',
            ),
            DcStatusBarAction(
              icon: Icons.code,
              label: 'GitHub',
              url: 'https://github.com/lumenpass/lumenpass',
            ),
            DcStatusBarAction(
              icon: Icons.coffee,
              label: 'Buy me a coffee',
              url: 'https://donorbox.org/donate-to-tranit',
            ),
            Text('3095 items'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in <String>[
        'Last synced: never',
        'Free license',
        'Other platforms & extensions',
        'GitHub',
        'Buy me a coffee',
        '3095 items',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing "$label"');
      }
    });

    testWidgets('shows full labels on a wide window', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        harness(
          const <Widget>[Text('Last synced: never')],
          const <Widget>[
            DcStatusBarAction(
              icon: Icons.shield,
              label: 'Free license',
              bold: true,
              url: 'https://www.apache.org/licenses/LICENSE-2.0',
            ),
            DcStatusBarAction(
              icon: Icons.download,
              label: 'Other platforms & extensions',
              url: 'https://www.lumenpass.app/downloads',
            ),
            DcStatusBarAction(
              icon: Icons.code,
              label: 'GitHub',
              url: 'https://github.com/lumenpass/lumenpass',
            ),
            DcStatusBarAction(
              icon: Icons.coffee,
              label: 'Buy me a coffee',
              url: 'https://donorbox.org/donate-to-tranit',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final barTop = tester.getTopLeft(find.byType(DcStatusBar)).dy;
      for (final label in <String>[
        'Free license',
        'Other platforms & extensions',
        'GitHub',
        'Buy me a coffee',
      ]) {
        final finder = find.text(label);
        expect(finder, findsOneWidget, reason: 'missing "$label"');
        final rect = tester.getRect(finder);
        expect(
          rect.bottom,
          lessThanOrEqualTo(barTop + DcMetrics.statusBarHeight + 1),
          reason: '"$label" is clipped vertically',
        );
        expect(
          rect.top,
          greaterThanOrEqualTo(barTop - 1),
          reason: '"$label" escapes the bar',
        );
      }
    });

    testWidgets('opens the configured url on tap', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? tapped;
      await tester.pumpWidget(
        harness(
          const <Widget>[],
          <Widget>[
            DcStatusBarAction(
              icon: Icons.coffee,
              label: 'Buy me a coffee',
              onTap: () => tapped = 'coffee',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Buy me a coffee'));
      await tester.pumpAndSettle();
      expect(tapped, 'coffee');
    });

    testWidgets('asserts when neither onTap nor url is given', (
      WidgetTester tester,
    ) async {
      expect(
        () => DcStatusBarAction(icon: Icons.abc, label: 'Broken'),
        throwsAssertionError,
      );
    });
  });
}
