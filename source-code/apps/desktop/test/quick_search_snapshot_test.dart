import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/core/models/entry_field.dart';
import 'package:lumenpass/core/models/kdbx_entry.dart';
import 'package:lumenpass/features/vault/presentation/vault_screen.dart';

void main() {
  const channel = MethodChannel('lumenpass/quick_search');
  const codec = StandardMethodCodec();

  test('compact snapshot leaves password fields in the main isolate', () {
    const entry = KdbxEntry(
      uuid: 'entry-1',
      groupUuid: 'group-1',
      title: 'Alpha Login',
      username: 'alice',
      fields: <EntryField>[
        EntryField(key: 'Password', value: 'test-secret', isProtected: true),
      ],
    );
    final compact = compactQuickSearchEntry(entry);

    expect(compact.containsKey('fields'), isFalse);
    expect(jsonEncode(compact), isNot(contains('test-secret')));
    expect(jsonEncode(compact).length,
        lessThan(jsonEncode(entry.toJson()).length));
  });

  testWidgets('compact Quick Search loads details on demand and clears them',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var detailRequests = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'getEntry') {
          detailRequests++;
          expect(call.arguments, 'entry-1');
          return jsonEncode(<String, Object?>{
            'uuid': 'entry-1',
            'groupUuid': 'group-1',
            'title': 'Alpha Login',
            'username': 'alice',
            'fields': <Map<String, Object?>>[
              <String, Object?>{
                'key': 'Password',
                'value': 'test-secret',
                'isProtected': true,
              },
            ],
          });
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    Future<void> sendToPanel(String method, [Object? arguments]) async {
      final completed = Completer<void>();
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) => completed.complete(),
      );
      await completed.future;
      await tester.pump();
    }

    await tester.pumpWidget(const QuickSearchWindow());
    await tester.pump();
    await sendToPanel(
      'setSnapshot',
      jsonEncode(<String, Object?>{
        'compact': true,
        'entries': <Map<String, Object?>>[
          <String, Object?>{
            'uuid': 'entry-1',
            'groupUuid': 'group-1',
            'title': 'Alpha Login',
            'username': 'alice',
            'quickItemType': 'login',
          },
        ],
      }),
    );

    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Alpha Login'), findsWidgets);
    expect(detailRequests, 0);

    await tester.tap(find.textContaining('Alpha Login').last);
    await tester.pump();
    expect(detailRequests, 1);

    await sendToPanel('clearSnapshot');
    expect(find.textContaining('Alpha Login'), findsNothing);
  });
}
