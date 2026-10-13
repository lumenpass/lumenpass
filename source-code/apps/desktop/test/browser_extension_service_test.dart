import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart' as native;
import 'package:lumenpass/core/models/entry_attachment.dart';
import 'package:lumenpass/core/models/entry_binary_attachment.dart';
import 'package:lumenpass/core/models/entry_field.dart';
import 'package:lumenpass/core/models/kdbx_database.dart';
import 'package:lumenpass/core/models/kdbx_entry.dart';
import 'package:lumenpass/core/models/kdbx_group.dart';
import 'package:lumenpass/core/repository/kdbx_repository.dart';
import 'package:lumenpass/core/services/browser_extension_service.dart';

void main() {
  test('GET /entry preserves the credit-card kind for extension autofill',
      () async {
    final port = await _freeLoopbackPort();
    final repository = _FakeKdbxRepository(
      hasOpenDatabase: true,
      entries: const <KdbxEntry>[
        KdbxEntry(
          uuid: 'synthetic-card',
          groupUuid: 'g',
          title: 'Synthetic card',
          fields: <EntryField>[
            EntryField(key: 'Card Number', value: '4111111111111111'),
          ],
        ),
      ],
    );
    final service = BrowserExtensionService(
      repository: repository,
      port: port,
      watchdogInterval: Duration.zero,
    );
    addTearDown(service.stop);
    await service.start();

    final response = await _getJson(port, '/entry/synthetic-card');

    expect(response.statusCode, 200);
    expect(response.body['kind'], 'credit-card');
  });

  test('POST /entry/create saves a captured registration login', () async {
    final port = await _freeLoopbackPort();
    final repository = _SavingKdbxRepository();
    final service = BrowserExtensionService(
      repository: repository,
      port: port,
      watchdogInterval: Duration.zero,
    );
    addTearDown(service.stop);
    await service.start();

    final response = await _postJson(port, '/entry/create', {
      'title': 'Synthetic registration',
      'username': 'tester',
      'password': 'test-password',
      'url': 'http://localhost:3000/register',
      'categoryUuid': '',
    });

    expect(response.statusCode, 200);
    expect(response.body, containsPair('mode', 'created'));
    expect(repository.savedFields.map((field) => field.key),
        containsAll(<String>['Title', 'UserName', 'Password', 'URL']));
    expect(
        repository.savedFields
            .singleWhere((field) => field.key == 'Password')
            .isProtected,
        isTrue);
    expect(repository.saveCount, 1);
  });

  test('start serves ping on the configured loopback port', () async {
    final port = await _freeLoopbackPort();
    final repository = _FakeKdbxRepository(hasOpenDatabase: true);
    final service = BrowserExtensionService(
      repository: repository,
      port: port,
      watchdogInterval: Duration.zero,
    );

    addTearDown(service.stop);

    await service.start();

    final response = await _getJson(port, '/ping');
    expect(response.statusCode, 200);
    expect(response.body['status'], 'ok');
    expect(response.body['vaultOpen'], true);
  });

  test('stop closes the bridge listener', () async {
    final port = await _freeLoopbackPort();
    final service = BrowserExtensionService(
      repository: _FakeKdbxRepository(),
      port: port,
      watchdogInterval: Duration.zero,
    );

    await service.start();
    expect(service.isRunning, true);

    await service.stop();
    expect(service.isRunning, false);

    await expectLater(
      _getJson(port, '/ping', timeout: const Duration(milliseconds: 200)),
      throwsA(isA<Exception>()),
    );
  });

  test('ensureRunning restarts the bridge after it was stopped', () async {
    final port = await _freeLoopbackPort();
    final service = BrowserExtensionService(
      repository: _FakeKdbxRepository(),
      port: port,
      healthCheckTimeout: const Duration(milliseconds: 200),
      watchdogInterval: Duration.zero,
    );

    addTearDown(service.stop);

    await service.start();
    await service.stop();
    expect(service.isRunning, false);

    await service.ensureRunning();

    expect(service.isRunning, true);
    final response = await _getJson(port, '/ping');
    expect(response.statusCode, 200);
    expect(response.body['vaultOpen'], false);
  });

  test('watchdog continues to issue health checks while service is started',
      () async {
    final service = _CountingBrowserExtensionService(
      watchdogInterval: const Duration(milliseconds: 20),
    );

    addTearDown(service.stop);

    await service.start();
    final initialCalls = service.ensureRunningCalls;

    await Future<void>.delayed(const Duration(milliseconds: 75));

    expect(service.ensureRunningCalls, greaterThan(initialCalls));
  });

  test('POST /item/touch stamps last used and persists', () async {
    final port = await _freeLoopbackPort();
    final repository = _FakeKdbxRepository(
      hasOpenDatabase: true,
      entries: const <KdbxEntry>[
        KdbxEntry(uuid: 'entry-1', groupUuid: 'g', title: 'GitHub'),
      ],
    );
    final service = BrowserExtensionService(
      repository: repository,
      port: port,
      watchdogInterval: Duration.zero,
    );
    addTearDown(service.stop);
    await service.start();

    final response = await _postJson(port, '/item/touch', {'id': 'entry-1'});

    expect(response.statusCode, 200);
    expect(response.body['ok'], true);
    expect(response.body['id'], 'entry-1');
    expect(repository.touchedUuids, <String>['entry-1']);
    expect(repository.saveCount, 1);
  });

  test('POST /item/touch returns 404 for an unknown entry', () async {
    final port = await _freeLoopbackPort();
    final repository = _FakeKdbxRepository(
      hasOpenDatabase: true,
      entries: const <KdbxEntry>[],
    );
    final service = BrowserExtensionService(
      repository: repository,
      port: port,
      watchdogInterval: Duration.zero,
    );
    addTearDown(service.stop);
    await service.start();

    final response = await _postJson(port, '/item/touch', {'id': 'missing'});

    expect(response.statusCode, 404);
    expect(response.body['ok'], false);
    expect(repository.touchedUuids, isEmpty);
    expect(repository.saveCount, 0);
  });

  test('POST /item/touch returns 400 when id is missing', () async {
    final port = await _freeLoopbackPort();
    final repository = _FakeKdbxRepository(
      hasOpenDatabase: true,
      entries: const <KdbxEntry>[],
    );
    final service = BrowserExtensionService(
      repository: repository,
      port: port,
      watchdogInterval: Duration.zero,
    );
    addTearDown(service.stop);
    await service.start();

    final response = await _postJson(port, '/item/touch', const {});

    expect(response.statusCode, 400);
    expect(response.body['ok'], false);
  });
}

Future<int> _freeLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<_JsonResponse> _getJson(
  int port,
  String path, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client
        .get(BrowserExtensionService.defaultHost, port, path)
        .timeout(timeout);
    final response = await request.close().timeout(timeout);
    final raw = await utf8.decodeStream(response).timeout(timeout);
    return _JsonResponse(
      statusCode: response.statusCode,
      body: jsonDecode(raw) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

class _JsonResponse {
  const _JsonResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final Map<String, dynamic> body;
}

Future<_JsonResponse> _postJson(
  int port,
  String path,
  Map<String, dynamic> payload, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client
        .post(BrowserExtensionService.defaultHost, port, path)
        .timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close().timeout(timeout);
    final raw = await utf8.decodeStream(response).timeout(timeout);
    return _JsonResponse(
      statusCode: response.statusCode,
      body: jsonDecode(raw) as Map<String, dynamic>,
    );
  } finally {
    client.close(force: true);
  }
}

class _CountingBrowserExtensionService extends BrowserExtensionService {
  _CountingBrowserExtensionService({
    required super.watchdogInterval,
  }) : super(
          repository: _FakeKdbxRepository(),
        );

  int ensureRunningCalls = 0;
  bool _stopped = false;

  @override
  Future<void> ensureRunning() async {
    if (_stopped) return;
    ensureRunningCalls += 1;
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await super.stop();
  }
}

class _SavingKdbxRepository extends _FakeKdbxRepository {
  _SavingKdbxRepository()
      : super(hasOpenDatabase: true, entries: const <KdbxEntry>[]);

  List<EntryField> savedFields = const <EntryField>[];

  @override
  String? get rootGroupUuid => 'root';

  @override
  Future<KdbxEntry> createEntry({
    required String groupUuid,
    required List<EntryField> fields,
    String? notes,
    List<String> tags = const <String>[],
    List<EntryAttachment> attachments = const <EntryAttachment>[],
  }) async {
    savedFields = fields;
    return KdbxEntry(
      uuid: 'saved-login',
      groupUuid: groupUuid,
      title: fields.singleWhere((field) => field.key == 'Title').value,
      fields: fields,
    );
  }
}

class _FakeKdbxRepository implements KdbxRepository {
  _FakeKdbxRepository({this.hasOpenDatabase = false, this.entries});

  @override
  final bool hasOpenDatabase;

  /// Entries returned by [searchEntries] (used by touch/get endpoints). When
  /// null, [searchEntries] throws like the other unimplemented methods.
  final List<KdbxEntry>? entries;

  final List<String> touchedUuids = <String>[];
  int saveCount = 0;

  @override
  KdbxDatabase? get currentDatabase => null;

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
    if (entries == null) {
      throw UnimplementedError();
    }
    saveCount += 1;
    return Future<KdbxDatabase>.value(
      KdbxDatabase(
        name: 'Test Vault',
        path: '/tmp/test.kdbx',
        rootGroup: KdbxGroup(uuid: 'root', name: 'Root'),
        openedAt: DateTime.utc(2024, 1, 1),
      ),
    );
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
  Future<void> moveEntryToGroup({
    required String entryUuid,
    required String targetGroupUuid,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<KdbxEntry>> searchEntries({String query = ''}) {
    final available = entries;
    if (available == null) {
      throw UnimplementedError();
    }
    return Future<List<KdbxEntry>>.value(available);
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
    if (entries == null) {
      throw UnimplementedError();
    }
    touchedUuids.add(entryUuid);
    return Future<void>.value();
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
    return Future<String?>.value();
  }

  @override
  Future<List<EntryBinaryAttachment>> getEntryAttachments(String entryUuid) {
    throw UnimplementedError();
  }
}
