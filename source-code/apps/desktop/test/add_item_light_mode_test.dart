import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/vault/presentation/vault_screen.dart';
import 'package:lumenpass/presentation/theme/drive_clue_tokens.dart';
import 'package:lumenpass/presentation/widgets/lumenpass_wordmark.dart';

void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    Size windowSize = const Size(1200, 850),
  }) async {
    tester.view.physicalSize = windowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: AddNewItemOverlay(
            onClose: () {},
            onShowToast: (_) {},
            onItemCreated: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  void expectBrandedHeader(WidgetTester tester, String title) {
    final label = find.text(title);
    expect(label, findsOneWidget);
    expect(find.byType(LumenPassWordmark), findsWidgets);
    expect(tester.widget<Text>(label).style?.color, DcColors.text);
    final ancestors =
        find.ancestor(of: label, matching: find.byType(Container));
    expect(
        ancestors.evaluate().any((element) {
          final box = element.widget as Container;
          return box.constraints?.maxHeight == DcMetrics.headerHeight &&
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color == DcColors.background;
        }),
        isTrue);
  }

  testWidgets('type picker has a branded title and legible light choices',
      (tester) async {
    await pumpPicker(tester);
    expectBrandedHeader(tester, 'Add an item');
    final login = find.text('Login');
    expect(login, findsOneWidget);
    expect(tester.widget<Text>(login).style?.color, DcColors.sidebarText);
    final surface = find.ancestor(of: login, matching: find.byType(Container));
    expect(
        surface.evaluate().any((element) {
          final box = element.widget as Container;
          return box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color == DcColors.lightInset;
        }),
        isTrue);
  });

  testWidgets('picker fits six choices in a compact two-column panel',
      (tester) async {
    await pumpPicker(tester);
    final panel = find.ancestor(
      of: find.text('Add an item'),
      matching: find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == DcColors.lightSurface),
    );
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, lessThanOrEqualTo(570));
    expect(tester.getSize(panel).height, lessThanOrEqualTo(300));

    final loginCard = find
        .ancestor(
            of: find.text('Login'), matching: find.byType(AnimatedContainer))
        .first;
    final secureNoteCard = find
        .ancestor(
            of: find.text('Secure Note'),
            matching: find.byType(AnimatedContainer))
        .first;
    expect(tester.getSize(loginCard).height, lessThanOrEqualTo(54));
    expect(
        tester.getTopLeft(loginCard).dy, tester.getTopLeft(secureNoteCard).dy);
    for (final label in <String>[
      'Login',
      'Secure Note',
      'Credit Card',
      'Identity',
      'SSH Key',
      'Bank Account'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('narrow picker scrolls to the last choice', (tester) async {
    await pumpPicker(tester, windowSize: const Size(450, 520));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Bank Account'));
    await tester.pump();
    await tester.tap(find.text('Bank Account'));
    await tester.pump();
    expect(find.text('New Bank Account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (type, title) in <(String, String)>[
    ('Login', 'New Login'),
    ('Secure Note', 'New Secure Note'),
    ('Credit Card', 'New Credit Card'),
    ('Identity', 'New Identity'),
    ('SSH Key', 'New SSH Key'),
    ('Bank Account', 'New Bank Account'),
  ]) {
    testWidgets('$type editor has branded heading and light input surface',
        (tester) async {
      await pumpPicker(tester);
      await tester.tap(find.text(type));
      await tester.pump();
      expectBrandedHeader(tester, title);
      final inputs = find.byType(Container);
      expect(
          inputs.evaluate().any((element) {
            final box = element.widget as Container;
            return box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).color == DcColors.lightInset;
          }),
          isTrue);
      await tester.tap(find.byTooltip('Back to item types'));
      await tester.pump();
      expect(find.text('Add an item'), findsOneWidget);
    });
  }

  testWidgets('light controls retain readable text when fields contain values',
      (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Credit Card'));
    await tester.pump();
    final textFields = find.byType(TextField);
    expect(textFields, findsWidgets);
    final titledField = tester.widget<TextField>(textFields.first);
    expect(titledField.style?.color, DcColors.sidebarText);
    final lightInputs = find.byType(Container).evaluate().where((element) {
      final box = element.widget as Container;
      return box.decoration is BoxDecoration &&
          (box.decoration as BoxDecoration).color == DcColors.lightInset;
    });
    expect(lightInputs, isNotEmpty);
    final formPanel = find.ancestor(
      of: find.text('New Credit Card'),
      matching: find.byType(Container),
    );
    expect(
        formPanel.evaluate().any((element) {
          final box = element.widget as Container;
          return box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color ==
                  DcColors.lightSurface &&
              (box.decoration as BoxDecoration).border == null;
        }),
        isTrue);
  });

  testWidgets(
      'login editor keeps core fields and category visible in a calm compact panel',
      (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Login'));
    await tester.pump();

    final dialog = find
        .ancestor(
          of: find.text('New Login'),
          matching: find.byWidgetPredicate((widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  DcColors.lightSurface),
        )
        .first;
    expect(tester.getSize(dialog).width, lessThanOrEqualTo(620));
    expect(tester.getTopLeft(find.text('category')).dy,
        lessThan(tester.getTopLeft(find.text('notes')).dy));
    expect(tester.getTopLeft(find.text('category')).dy, lessThan(720));
    expect(
        tester
            .getSize(find
                .ancestor(
                  of: find.text('2FA / TOTP'),
                  matching: find.byType(Container),
                )
                .first)
            .height,
        lessThanOrEqualTo(50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login credentials share a detail-style card with divided rows',
      (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Login'));
    await tester.pump();

    final card = find.byKey(const Key('login-details-card'));
    expect(card, findsOneWidget);
    final scrollBackdrop = find.ancestor(
      of: card,
      matching: find.byWidgetPredicate((widget) =>
          widget is ColoredBox && widget.color == DcColors.lightInset),
    );
    expect(scrollBackdrop, findsOneWidget);
    final decoration =
        tester.widget<Container>(card).decoration as BoxDecoration;
    expect(decoration.color, DcColors.lightSurface);
    expect(decoration.borderRadius, BorderRadius.circular(10));
    expect(decoration.border, isNotNull);

    for (final label in <String>[
      'username',
      'password',
      'website',
      'category',
      'notes',
      '2FA / TOTP'
    ]) {
      expect(find.descendant(of: card, matching: find.text(label)),
          findsOneWidget);
    }
    final username = find.byKey(const Key('login-detail-row-username'));
    final password = find.byKey(const Key('login-detail-row-password'));
    expect(username, findsOneWidget);
    expect(password, findsOneWidget);
    final rowDecoration =
        tester.widget<Container>(username).decoration as BoxDecoration;
    expect(rowDecoration.border, isNotNull);
    expect(tester.getTopLeft(username).dy,
        lessThan(tester.getTopLeft(password).dy));
    expect(find.descendant(of: username, matching: find.byType(TextField)),
        findsOneWidget);
    await tester.enterText(
        find.descendant(of: username, matching: find.byType(TextField)),
        'me@example.com');
    expect(
        tester
            .widget<TextField>(
                find.descendant(of: username, matching: find.byType(TextField)))
            .controller
            ?.text,
        'me@example.com');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await tester.ensureVisible(find.text('Add 2FA'));
    await tester.tap(find.text('Add 2FA'));
    await tester.pump();
    expect(find.text('Add 2FA Code'), findsOneWidget);
  });

  testWidgets(
      'login row focuses without boxing every input and website row stays grouped',
      (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Login'));
    await tester.pump();
    final username = find.byKey(const Key('login-detail-row-username'));
    await tester
        .tap(find.descendant(of: username, matching: find.byType(TextField)));
    await tester.pump();
    final decoration =
        tester.widget<Container>(username).decoration as BoxDecoration;
    expect(decoration.color, DcColors.selectionSoft);
    expect(find.text('+ add another website / url'), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const Key('login-details-card')),
            matching: find.byKey(const Key('login-detail-row-website'))),
        findsOneWidget);
  });

  testWidgets('narrow login editor can scroll to optional fields and save',
      (tester) async {
    await pumpPicker(tester, windowSize: const Size(450, 520));
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('category'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('notes'));
    await tester.pump();
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SSH key generation dialog uses branded light layout',
      (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('SSH Key'));
    await tester.pump();
    await tester.tap(find.byTooltip('Private key actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate a New Key'));
    await tester.pumpAndSettle();
    expectBrandedHeader(tester, 'Generate SSH key');
    expect(find.text('Ed25519'), findsWidgets);
    await tester.tap(find.byTooltip('Close dialog').last);
    await tester.pumpAndSettle();
    expect(find.text('Generate SSH key'), findsNothing);
  });

  testWidgets('discard confirmation keeps the light body and branded title',
      (tester) async {
    await pumpPicker(tester);
    await tester.tap(find.text('Login'));
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'Draft login');
    await tester.tap(find.byTooltip('Close dialog'));
    await tester.pumpAndSettle();
    expectBrandedHeader(tester, 'Discard changes');
    expect(find.text('Keep Editing'), findsOneWidget);
    final keepText = tester.widget<Text>(find.text('Keep Editing'));
    expect(keepText.style?.color, DcColors.sidebarText);
    final dialogPanel = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Container))
        .first;
    final decoration =
        tester.widget<Container>(dialogPanel).decoration as BoxDecoration;
    expect(decoration.color, DcColors.lightSurface);
    expect(decoration.border, isNull);
    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes'), findsNothing);
    expect(find.text('New Login'), findsOneWidget);
  });
}
