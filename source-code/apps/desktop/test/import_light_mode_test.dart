import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/repository/kdbx_repository_provider.dart';
import 'package:lumenpass/core/services/local_storage_service.dart';
import 'package:lumenpass/features/import/application/import_executor.dart';
import 'package:lumenpass/features/import/presentation/import_confirmation_modal.dart';
import 'package:lumenpass/features/import/presentation/import_preview_screen.dart';
import 'package:lumenpass/features/import/presentation/clear_progress_modal.dart';
import 'package:lumenpass/features/import/presentation/import_progress_modal.dart';
import 'package:lumenpass/features/import/presentation/import_provider_modal.dart';
import 'package:lumenpass/presentation/theme/drive_clue_tokens.dart';
import 'package:lumenpass/presentation/widgets/lumenpass_wordmark.dart';

void main() {
  testWidgets('provider picker has a dark title band and readable light cards',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ImportProviderModal(onClose: () {}, onNext: () {}),
        ),
      ),
    ));
    final title = find.text('Import Passwords from providers');
    expect(title, findsOneWidget);
    expect(find.byType(LumenPassWordmark), findsOneWidget);
    expect(tester.widget<Text>(title).style?.color, DcColors.text);
    final darkBand = find.ancestor(of: title, matching: find.byType(Container));
    expect(
      darkBand.evaluate().any((element) {
        final container = element.widget as Container;
        final decoration = container.decoration;
        return container.constraints?.maxHeight == DcMetrics.headerHeight &&
            decoration is BoxDecoration &&
            decoration.color == DcColors.background;
      }),
      isTrue,
    );
    final panel = find
        .descendant(
          of: find.byType(Dialog),
          matching: find.byType(Container),
        )
        .first;
    final decoration =
        tester.widget<Container>(panel).decoration as BoxDecoration;
    expect(decoration.border, isNull);
    expect(tester.getSize(panel).width, lessThanOrEqualTo(540));
    expect(tester.getSize(panel).height, lessThan(600));
    final card = find.text('1Password');
    expect(card, findsOneWidget);
    expect(tester.widget<Text>(card).style?.color, DcColors.sidebarText);

    await tester.tap(find.text('RoboForm'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Upload RoboForm export'), findsOneWidget);
    expect(tester.getSize(panel).width, lessThanOrEqualTo(540));
    expect(tester.getSize(panel).height, lessThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview keeps its category control and tables on light surfaces',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ImportPreviewScreen(onClose: () {}, onStartImport: () {}),
        ),
      ),
    ));
    expect(find.text('Preview Import'), findsOneWidget);
    expect(find.byType(LumenPassWordmark), findsOneWidget);
    expect(tester.getSize(find.byType(LumenPassWordmark)).height, lessThan(25));
    final previewPanel = find
        .descendant(
          of: find.byType(Dialog),
          matching: find.byType(Container),
        )
        .first;
    expect(
        (tester.widget<Container>(previewPanel).decoration as BoxDecoration)
            .border,
        isNull);
    expect(tester.widget<Text>(find.text('Preview Import')).style?.color,
        DcColors.text);
    final scaffold = find
        .descendant(
          of: find.byType(ImportPreviewScreen),
          matching: find.byType(Scaffold),
        )
        .last;
    expect(tester.widget<Scaffold>(scaffold).backgroundColor,
        DcColors.lightSurface);
    expect(find.text('Ready to Import'), findsOneWidget);
  });

  testWidgets('confirmation has a dark heading and a light body',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStorageProvider.overrideWithValue(_EmptyStorage()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ImportConfirmationModal(onCancel: () {}, onConfirm: () {}),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Confirm Import'), findsOneWidget);
    expect(find.byType(LumenPassWordmark), findsOneWidget);
    expect(tester.widget<Text>(find.text('Confirm Import')).style?.color,
        DcColors.text);
    final panel = find
        .descendant(
          of: find.byType(Dialog),
          matching: find.byType(Container),
        )
        .first;
    final confirmDecoration =
        tester.widget<Container>(panel).decoration as BoxDecoration;
    expect(confirmDecoration.color, DcColors.lightSurface);
    expect(confirmDecoration.border, isNull);
  });

  for (final progressModal in <Widget>[
    ImportProgressModal(
      progress: ImportProgress.idle,
      onDone: () {},
      onCancelRequested: () {},
    ),
    ClearProgressModal(
      progress: ImportProgress.idle,
      onRetry: () {},
      onCancel: () {},
    ),
  ]) {
    testWidgets('${progressModal.runtimeType} has a light surface',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: progressModal)));
      expect(find.byType(LumenPassWordmark), findsOneWidget);
      final panel = find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Container),
          )
          .first;
      final progressDecoration =
          tester.widget<Container>(panel).decoration as BoxDecoration;
      expect(progressDecoration.color, DcColors.lightSurface);
      expect(progressDecoration.border, isNull);
    });
  }
}

class _EmptyStorage extends LocalStorageService {
  @override
  Future<String?> read({required String key}) async => null;

  @override
  Future<void> write({required String key, String? value}) async {}
}
