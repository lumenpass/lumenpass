import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/presentation/theme/drive_clue_tokens.dart';
import 'package:lumenpass/presentation/widgets/drive_clue/dc_confirm_dialog.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Widget dialog,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: DcColors.sidebar,
          body: Center(child: dialog),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the light surface, heading and footer actions',
      (tester) async {
    await pumpDialog(
      tester,
      dialog: DcConfirmDialog(
        barTitle: 'Remove vault',
        heading: 'Remove "Primary Vault"?',
        message: 'This removes the database from LumenPass.',
        confirmLabel: 'Remove',
        isDestructive: true,
      ),
    );

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, DcColors.lightSurface);

    expect(find.text('Remove "Primary Vault"?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extra actions wrap instead of overflowing a narrow dialog',
      (tester) async {
    await pumpDialog(
      tester,
      size: const Size(560, 640),
      dialog: DcConfirmDialog(
        barTitle: 'Vault sync issue',
        heading: 'Pending changes did not sync',
        message: 'The last upload for this vault could not be confirmed.',
        confirmLabel: 'Reconnect Google Drive',
        width: 500,
        extraActions: <Widget>[
          TextButton(onPressed: () {}, child: const Text('Unlink Databases')),
          TextButton(onPressed: () {}, child: const Text('Check again')),
        ],
      ),
    );

    expect(find.text('Unlink Databases'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Reconnect Google Drive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmEnabled:false disables the primary action',
      (tester) async {
    await pumpDialog(
      tester,
      dialog: DcConfirmDialog(
        barTitle: 'Restore from backup',
        heading: 'Restore from backup',
        message: 'Acknowledge both checks before restoring.',
        confirmLabel: 'Restore',
        confirmEnabled: false,
        onConfirm: () {},
      ),
    );

    final confirm = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Restore'),
    );
    expect(confirm.onPressed, isNull);

    final cancel = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Cancel'),
    );
    expect(cancel.onPressed, isNotNull);
  });
}
