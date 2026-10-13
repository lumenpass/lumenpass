import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lumenpass/features/cloud/application/cloud_service_provider.dart';
import 'package:lumenpass/features/cloud/presentation/cloud_services_screen.dart';

void main() {
  const subject = ProviderScope(
    child: MaterialApp(home: CloudServicesScreen()),
  );

  testWidgets('shows every cloud provider without subscription badges',
      (tester) async {
    await tester.pumpWidget(subject);
    await tester.pump();

    for (final provider in CloudServiceProvider.values) {
      expect(find.text(provider.label), findsOneWidget);
    }
    expect(find.text('Premium'), findsNothing);
    expect(find.text('Upgrade'), findsNothing);
  });

  testWidgets('defaults to grid layout and can switch to list layout',
      (tester) async {
    await tester.pumpWidget(subject);
    await tester.pump();

    final gridGoogleTop =
        tester.getTopLeft(find.text('Google Drive')).dy.round();
    final gridDropboxTop = tester.getTopLeft(find.text('Dropbox')).dy.round();
    expect(gridGoogleTop, gridDropboxTop);

    await tester.tap(find.byKey(const ValueKey<String>(
      'cloud-services-layout-list',
    )));
    await tester.pumpAndSettle();

    final listGoogleTop =
        tester.getTopLeft(find.text('Google Drive')).dy.round();
    final listDropboxTop = tester.getTopLeft(find.text('Dropbox')).dy.round();
    expect(listDropboxTop, greaterThan(listGoogleTop));
  });
}
