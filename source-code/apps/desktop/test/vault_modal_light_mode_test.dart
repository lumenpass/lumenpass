import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/vault/presentation/vault_screen.dart';
import 'package:lumenpass/presentation/theme/drive_clue_tokens.dart';
import 'package:lumenpass/presentation/widgets/drive_clue/dc_dialog_title_bar.dart';
import 'package:lumenpass/presentation/widgets/lumenpass_wordmark.dart';

/// The vault modals that lived on the old dark slate surfaces — password
/// generator, add/edit category, and the 2FA/TOTP scanner — share one shell:
/// a dark branded title bar over a light body.
void main() {
  Future<void> setWindow(WidgetTester tester,
      {Size size = const Size(1200, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> pumpModal(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  /// Asserts the modal's outer panel is white and hosts the dark title bar.
  void expectLightShellWithDarkHeader(WidgetTester tester, String title) {
    final header = find.ancestor(
      of: find.text(title),
      matching: find.byType(DcDialogTitleBar),
    );
    expect(header, findsOneWidget);
    expect(
      tester.widget<DcDialogTitleBar>(header).title,
      title,
    );
    // The brand wordmark only appears when the dark header is rendered.
    expect(
      find.descendant(of: header, matching: find.byType(LumenPassWordmark)),
      findsOneWidget,
    );

    // The panel wrapping the header must be the light surface. No fallback: if
    // nothing matches, this test should fail rather than silently pass.
    final panels = find
        .ancestor(
          of: find.byType(DcDialogTitleBar),
          matching: find.byType(Container),
        )
        .evaluate()
        .map((e) => e.widget as Container)
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == DcColors.lightSurface,
        )
        .toList();
    expect(
      panels,
      isNotEmpty,
      reason: 'no light-surface panel wraps the dark title bar',
    );

    for (final panel in panels) {
      final decoration = panel.decoration as BoxDecoration;
      // No outline: a border insets the child by its width, so the white panel
      // would peek out as a ring around the dark title bar. Shadows alone
      // separate the panel from the page behind it.
      expect(
        decoration.border,
        isNull,
        reason: 'modal panels must not draw an outline over the dark header',
      );
    }
  }

  testWidgets('password generator uses the light body and dark title bar',
      (tester) async {
    await setWindow(tester);
    await pumpModal(tester, const PasswordGeneratorDialog());

    expectLightShellWithDarkHeader(tester, 'Generate Password');
    // Body copy must be readable dark text on the light panel.
    expect(find.text('Length'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Length')).style?.color,
      DcColors.sidebarMuted,
    );
    for (final label in <String>[
      'Letters',
      'Numbers',
      'Symbols',
      'Cancel',
      'Use Password',
      'Smart',
      'Memorable',
      'PIN',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('password generator switches presets and regenerates the value',
      (tester) async {
    await setWindow(tester);
    await pumpModal(tester, const PasswordGeneratorDialog());

    String currentValue() {
      final field = tester.widget<Semantics>(
        find
            .byWidgetPredicate((w) =>
                w is Semantics && w.properties.label == 'Generated password')
            .first,
      );
      return field.properties.value ?? '';
    }

    final initial = currentValue();
    await tester.tap(find.text('PIN'));
    await tester.pump();
    final pin = currentValue();
    expect(pin, isNot(initial));
    expect(RegExp(r'^[0-9]+$').hasMatch(pin), isTrue);
    expect(find.text('PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add category keeps a light body under the dark title bar',
      (tester) async {
    await setWindow(tester);
    await pumpModal(
      tester,
      ProviderScope(
        child: AddCategoryOverlay(
          onClose: () {},
          onShowToast: (_) {},
          onCategoryCreated: (_) async {},
        ),
      ),
    );

    expectLightShellWithDarkHeader(tester, 'Add Category');
    expect(find.text('Category name'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Category name')).style?.color,
      DcColors.sidebarMuted,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create Category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit category keeps a light body under the dark title bar',
      (tester) async {
    await setWindow(tester);
    await pumpModal(
      tester,
      ProviderScope(
        child: EditCategoryOverlay(
          category: (
            uuid: 'group-uuid',
            name: 'QA Recovery 20261001',
            notes: '',
            count: 3,
          ),
          onClose: () {},
          onShowToast: (_) {},
          onCategoryUpdated: (_) async {},
        ),
      ),
    );

    expectLightShellWithDarkHeader(tester, 'Edit Category');
    expect(find.text('QA Recovery 20261001'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2FA scanner opens on a light body with the dark title bar',
      (tester) async {
    await setWindow(tester);
    await pumpModal(
      tester,
      ProviderScope(
        child: AddNewItemOverlay(
          onClose: () {},
          onShowToast: (_) {},
          onItemCreated: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Login'));
    await tester.pump();
    await tester.ensureVisible(find.text('Add 2FA'));
    await tester.tap(find.text('Add 2FA'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expectLightShellWithDarkHeader(tester, 'Add 2FA Code');
    expect(find.text('Drop a QR code image here'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Drop a QR code image here')).style?.color,
      DcColors.sidebarMuted,
    );
  });

  testWidgets('category icon picker is a light popover, not a dark panel',
      (tester) async {
    await setWindow(tester);
    await pumpModal(
      tester,
      ProviderScope(
        child: AddCategoryOverlay(
          onClose: () {},
          onShowToast: (_) {},
          onCategoryCreated: (_) async {},
        ),
      ),
    );

    await tester.tap(find.byIcon(TablerIcons.chevron_down).first);
    await tester.pumpAndSettle();

    final title = find.text('Choose icon');
    expect(title, findsOneWidget);
    expect(
      tester.widget<Text>(title).style?.color,
      DcColors.sidebarText,
    );
    expect(tester.takeException(), isNull);
  });
}
