// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kdbx/kdbx.dart' as native;

import 'package:lumenpass/main.dart';
import 'package:lumenpass/core/repository/kdbx_repository_provider.dart';
import 'package:lumenpass/core/repository/kdbx_repository.dart';
import 'package:lumenpass/core/models/kdbx_database.dart';
import 'package:lumenpass/core/models/kdbx_entry.dart';
import 'package:lumenpass/core/models/entry_field.dart';
import 'package:lumenpass/core/models/entry_attachment.dart';
import 'package:lumenpass/core/models/entry_binary_attachment.dart';
import 'package:lumenpass/core/services/local_storage_service.dart';
import 'package:lumenpass/core/services/browser_extension_provider.dart';
import 'package:lumenpass/core/services/browser_extension_service.dart';
import 'package:lumenpass/features/unlock/presentation/unlocking_progress_screen.dart';

void main() {
  testWidgets('renders the unlock experience', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localStorageProvider.overrideWithValue(_MemoryLocalStorageService()),
          browserExtensionServiceProvider
              .overrideWithValue(_NoopBrowserExtensionService()),
        ],
        child: LumenPassApp(),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3200));
    await tester.pump();

    // Compact vault picker header; search is revealed on demand.
    expect(find.text('YOUR VAULTS'), findsOneWidget);
    expect(find.text('Your databases.'), findsNothing);
    expect(find.text('Unlock'), findsNothing);
    expect(find.text('Exit'), findsNothing);
    expect(find.text('Search databases'), findsNothing);

    await tester.tap(find.byTooltip('Search databases'));
    await tester.pump();
    expect(find.text('Search databases'), findsOneWidget);
    final searchPosition = tester.widget<Positioned>(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Positioned),
      ),
    );
    expect(searchPosition.top, isNull);
    expect(searchPosition.bottom, 74);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(find.text('Search databases'), findsNothing);

    await tester.tap(find.byTooltip('Search databases'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Search databases'), findsNothing);

    await tester.tap(find.byTooltip('Search databases'));
    await tester.pump();
    await tester.tap(find.text('YOUR VAULTS'));
    await tester.pump();
    expect(find.text('Search databases'), findsNothing);
  });

  testWidgets('renders the styled unlocking progress state',
      (WidgetTester tester) async {
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: UnlockingProgressScreen(
          vaultName: 'TranVaultLive',
          unlockTask: () async {},
          onSuccess: () => completed = true,
          onFailure: (_) {},
        ),
      ),
    );

    await tester.pump();
    expect(find.text('SECURE VAULT'), findsOneWidget);
    expect(find.text('Unlocking your vault'), findsOneWidget);
    expect(find.text('VERIFYING CREDENTIALS'), findsOneWidget);
    expect(
      find.text('Decrypting “TranVaultLive”. This takes just a moment.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(completed, isTrue);
  });
}

class _MemoryLocalStorageService extends LocalStorageService {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, String? value}) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}

class _NoopBrowserExtensionService extends BrowserExtensionService {
  _NoopBrowserExtensionService()
      : super(
          repository: _FakeKdbxRepository(),
          getDomainSetting: () => 'default',
        );

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _FakeKdbxRepository implements KdbxRepository {
  @override
  KdbxDatabase? get currentDatabase => null;

  @override
  bool get hasOpenDatabase => false;

  @override
  String? get rootGroupUuid => null;

  @override
  Future<KdbxDatabase> openDatabase({
    required String databasePath,
    String? password,
    Uint8List? keyFileBytes,
  }) {
    throw UnimplementedError();
  }

  @override
  void closeDatabase() {
    throw UnimplementedError();
  }

  @override
  Future<KdbxDatabase> createDatabase({
    required String databasePath,
    required String databaseName,
    String? password,
    Uint8List? keyFileBytes,
    native.KdbxVersion? version,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<KdbxDatabase> saveDatabase({String? outputPath}) {
    throw UnimplementedError();
  }

  @override
  Future<String> createGroup({
    required String parentGroupUuid,
    required String name,
    String? notes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateGroup({
    required String groupUuid,
    required String name,
    String? notes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteGroup(String groupUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<KdbxEntry>> searchEntries({String query = ''}) {
    throw UnimplementedError();
  }

  @override
  Future<KdbxEntry> createEntry({
    required String groupUuid,
    required List<EntryField> fields,
    String? notes,
    List<String> tags = const <String>[],
    List<EntryAttachment> attachments = const <EntryAttachment>[],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<KdbxEntry> updateEntry({
    required String entryUuid,
    required List<EntryField> fields,
    String? notes,
    List<String>? tags,
    List<EntryAttachment>? attachments,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteEntry(String entryUuid) {
    throw UnimplementedError();
  }

  @override
  Future<void> touchEntryLastUsedAt(String entryUuid) {
    throw UnimplementedError();
  }

  @override
  Future<bool> restoreEntry(String entryUuid) {
    throw UnimplementedError();
  }

  @override
  Future<void> permanentlyDeleteEntry(String entryUuid) {
    throw UnimplementedError();
  }

  @override
  Future<String?> getTOTP(String entryUuid) {
    throw UnimplementedError();
  }

  @override
  Future<List<EntryBinaryAttachment>> getEntryAttachments(String entryUuid) {
    throw UnimplementedError();
  }

  @override
  Future<void> moveEntryToGroup({
    required String entryUuid,
    required String targetGroupUuid,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> setEntryFaviconCache({
    required String entryUuid,
    required String payload,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<KdbxEntry>> entriesWithInvalidCreatedAt({required DateTime now}) {
    throw UnimplementedError();
  }

  @override
  Future<void> setEntryCreatedAt({
    required String entryUuid,
    required DateTime createdAt,
  }) {
    throw UnimplementedError();
  }
}
