import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/settings/presentation/settings_window.dart';
import 'package:lumenpass/presentation/theme/drive_clue_tokens.dart';

void main() {
  testWidgets('detached Settings window renders all sections', (tester) async {
    await tester.pumpWidget(const SettingsWindow());
    // Let the post-frame `ready` + snapshot round-trip settle.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('General'), findsWidgets);
    expect(find.text('Appearance'), findsWidgets);
    expect(find.text('Security'), findsWidgets);
    expect(find.text('Advanced'), findsWidgets);
    expect(find.text('About'), findsWidgets);

    // The window's dark title bar names the active section
    // (`LumenPass: General`); the section label is not repeated in-content.
    expect(find.byType(DcSettingsTitleBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DcSettingsTitleBar),
        matching: find.text('General'),
      ),
      findsOneWidget,
    );

    // General pane toggles are present.
    expect(find.text('Start at login'), findsOneWidget);
    expect(find.text('Start minimized'), findsOneWidget);

    // Switch to Appearance.
    await tester.tap(find.text('Appearance').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('TEXT SIZE'), findsOneWidget);
    expect(find.text('Ubuntu Sans'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(DcSettingsTitleBar),
        matching: find.text('Appearance'),
      ),
      findsOneWidget,
    );

    // Switch to Security.
    await tester.tap(find.text('Security').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hide full credit card number'), findsOneWidget);
    expect(find.text('AUTO-LOCK'), findsOneWidget);
    expect(find.text('CLEAR CLIPBOARD AFTER'), findsOneWidget);
    expect(find.text('WEBSITE MATCHING'), findsOneWidget);

    // Switch to Advanced (SSH Agent).
    await tester.tap(find.text('Advanced').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Use the SSH Agent'), findsOneWidget);
    expect(find.text('Off'), findsWidgets);

    // Switch to About: the pane must show the release, link, license and
    // platform details rather than just a name and a sentence.
    await tester.tap(find.text('About').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('LumenPass'), findsWidgets);
    expect(find.text('Free forever'), findsOneWidget);
    expect(find.text('TranTech Studio'), findsOneWidget);
    expect(find.text('Apache License 2.0'), findsNWidgets(2));
    expect(find.text('GitHub repository'), findsOneWidget);
    expect(find.text('Running on'), findsOneWidget);
    expect(find.text('Browser extension'), findsOneWidget);
    expect(find.text('Read the full license'), findsOneWidget);
    expect(
      find.text('Get LumenPass for your platform'),
      findsOneWidget,
    );

    // The sidebar carries a brand header and a pinned build footer so the
    // column does not read as an empty panel with five floating rows.
    expect(find.text('Changes apply right away.'), findsOneWidget);
    expect(find.text('Free forever · Apache-2.0'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  // The window chrome is dark but the body is the main window's light
  // palette: white cards on the pale blue-gray sidebar tint.
  testWidgets('content is light while the title bar stays dark',
      (tester) async {
    await tester.pumpWidget(const SettingsWindow());
    await tester.pump(const Duration(milliseconds: 100));

    final titleBar = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(DcSettingsTitleBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (titleBar.decoration as BoxDecoration).color,
      DcColors.background,
    );

    final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, DcColors.sidebar);
    expect(
      theme.colorScheme.surface,
      DcColors.sidebar,
    );
  });

  // The native window is 720×520 and its minimum is 620×420. Every pane must
  // lay out at both extremes without a RenderFlex overflow, which would show
  // as a red/yellow error band in the real window.
  for (final size in const <Size>[
    Size(720, 520),
    Size(620, 420),
    Size(1100, 820),
  ]) {
    testWidgets('panes lay out at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const SettingsWindow());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      for (final section in <String>[
        'Appearance',
        'Security',
        'Advanced',
        'About',
      ]) {
        await tester.tap(find.text(section).last);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.takeException(),
          isNull,
          reason: '$section pane overflowed at $size',
        );
      }
    });
  }
}
