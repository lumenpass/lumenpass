import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/domain/import_parsed_item.dart';
import 'package:lumenpass/features/import/domain/import_provider.dart';
import 'package:lumenpass/features/import/infrastructure/enpass_parser.dart';
import 'package:lumenpass/features/import/infrastructure/import_parser_service.dart';

/// Resolves the example Enpass export files shipped in the repo's
/// `testing/Data-Import/Enpass/` directory regardless of the cwd the test
/// runner is launched from.
String _enpassFixtureDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/testing/Data-Import/Enpass');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate testing/Data-Import/Enpass fixtures.');
}

File _firstWithExtension(String dirPath, String ext) {
  final matches = Directory(dirPath)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith(ext))
      .toList();
  expect(matches, isNotEmpty,
      reason: 'Expected at least one $ext fixture in $dirPath');
  return matches.first;
}

ImportParsedItem _itemNamed(List<ImportParsedItem> items, String title) {
  return items.firstWhere(
    (i) => i.title == title,
    orElse: () => fail('No imported item titled "$title"'),
  );
}

CustomImportField? _field(ImportParsedItem item, String name) {
  for (final f in item.customFields) {
    if (f.name == name) return f;
  }
  return null;
}

void main() {
  late String fixtureDir;
  late File jsonFixture;
  late File csvFixture;
  late File txtFixture;

  setUpAll(() {
    fixtureDir = _enpassFixtureDir();
    jsonFixture = _firstWithExtension(fixtureDir, '.json');
    csvFixture = _firstWithExtension(fixtureDir, '.csv');
    txtFixture = _firstWithExtension(fixtureDir, '.txt');
  });

  // ── JSON ──────────────────────────────────────────────────────────────

  group('EnpassParser - JSON (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items = const EnpassParser().parseJson(jsonFixture.readAsStringSync());
    });

    test('parses a substantial number of items', () {
      expect(items.length, greaterThan(1000));
    });

    test('maps a simple login (username + password + URL)', () {
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(item.username, 'divand553@gmail.com');
      expect(item.password, 'WZsfLQTVYd!SufUhyG286oK!e3&');
      expect(item.url, startsWith('https://0vd37z6cvqay.kintone.com'));
      expect(item.isReady, isTrue);
      expect(item.getSourceField('enpass_category'), 'login');
    });

    test('promotes folder UUID references into tags', () {
      // Every item in the export belongs to at least one folder; the parser
      // must look the UUID up in `folders[]` and turn it into a human tag.
      final tagged = items.where((i) => i.tags.isNotEmpty);
      expect(tagged, isNotEmpty);
      // The example fixture's folders are all "Bitwarden Import …",
      // "Imported October 8 2024 …", "ASME SSH", or "Starter Kit".
      final allTagNames = tagged.expand((i) => i.tags).toSet();
      expect(
        allTagNames.any((t) =>
            t.contains('Bitwarden Import') ||
            t.contains('Imported October') ||
            t == 'ASME SSH' ||
            t == 'Starter Kit'),
        isTrue,
      );
    });

    test('promotes a TOTP otpauth URI through unchanged', () {
      // Find any item whose otpAuthUrl was populated.
      final withTotp = items.where((i) => i.otpAuthUrl != null).toList();
      expect(withTotp, isNotEmpty,
          reason:
              'Expected at least one item with a One-time code in the JSON.');
      // Every populated TOTP value in the fixture is already an otpauth URI.
      for (final i in withTotp) {
        expect(i.otpAuthUrl, startsWith('otpauth://'));
      }
    });

    test('section fields are not stored as custom fields', () {
      // The "ADDITIONAL DETAILS" section header should never appear as a
      // field on any item.
      for (final item in items) {
        expect(_field(item, 'ADDITIONAL DETAILS'), isNull);
      }
    });

    test('every parsed item has a non-empty title', () {
      for (final item in items) {
        expect(item.title.trim(), isNotEmpty,
            reason: 'Item parsed without a title.');
      }
    });
  });

  group('EnpassParser - JSON (field mapping details)', () {
    test('maps username/password/url/totp from the fields array', () {
      const json = '''
      {
        "folders": [
          {"uuid": "f1", "title": "Work"}
        ],
        "items": [
          {
            "title": "Example",
            "category": "login",
            "note": "A note",
            "folders": ["f1"],
            "fields": [
              {"label": "Username", "type": "username", "value": "alice",
                "sensitive": 0},
              {"label": "Password", "type": "password", "value": "secret",
                "sensitive": 1},
              {"label": "Website", "type": "url", "value": "https://x.test",
                "sensitive": 0},
              {"label": "One-time code", "type": "totp",
                "value": "otpauth://totp/x?secret=ABC", "sensitive": 0}
            ]
          }
        ]
      }
      ''';
      final items = const EnpassParser().parseJson(json);
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.title, 'Example');
      expect(item.username, 'alice');
      expect(item.password, 'secret');
      expect(item.url, 'https://x.test');
      expect(item.otpAuthUrl, 'otpauth://totp/x?secret=ABC');
      expect(item.tags, contains('Work'));
      expect(item.notes, 'A note');
    });

    test('falls back to email when no username field is present', () {
      const json = '''
      {
        "folders": [],
        "items": [{
          "title": "EmailOnly",
          "category": "login",
          "fields": [
            {"label": "E-mail", "type": "email", "value": "bob@x.test"},
            {"label": "Password", "type": "password", "value": "pw",
              "sensitive": 1}
          ]
        }]
      }
      ''';
      final item = const EnpassParser().parseJson(json).single;
      expect(item.username, 'bob@x.test');
      // Email shouldn't be duplicated as a custom field when it was promoted.
      expect(_field(item, 'Email'), isNull);
    });

    test('keeps email as a custom field when username is also present', () {
      const json = '''
      {
        "folders": [],
        "items": [{
          "title": "Both",
          "category": "login",
          "fields": [
            {"label": "Username", "type": "username", "value": "alice"},
            {"label": "E-mail", "type": "email", "value": "alice@x.test"}
          ]
        }]
      }
      ''';
      final item = const EnpassParser().parseJson(json).single;
      expect(item.username, 'alice');
      final email = _field(item, 'Email');
      expect(email, isNotNull);
      expect(email!.value, 'alice@x.test');
    });

    test('wraps a bare TOTP Base32 secret into an otpauth URI', () {
      const json = '''
      {
        "folders": [],
        "items": [{
          "title": "My App",
          "category": "login",
          "fields": [
            {"label": "One-time code", "type": "totp", "value": "ABCDEFGH"}
          ]
        }]
      }
      ''';
      final item = const EnpassParser().parseJson(json).single;
      expect(item.otpAuthUrl,
          'otpauth://totp/${Uri.encodeComponent('My App')}?secret=ABCDEFGH');
    });

    test('extra URL fields beyond the first are stored as custom URL N fields',
        () {
      const json = '''
      {
        "folders": [],
        "items": [{
          "title": "MultiUrl",
          "category": "login",
          "fields": [
            {"label": "Website", "type": "url", "value": "https://a.test"},
            {"label": "Website", "type": "url", "value": "https://b.test"},
            {"label": "Website", "type": "url", "value": "https://c.test"}
          ]
        }]
      }
      ''';
      final item = const EnpassParser().parseJson(json).single;
      expect(item.url, 'https://a.test');
      expect(_field(item, 'URL 2')?.value, 'https://b.test');
      expect(_field(item, 'URL 3')?.value, 'https://c.test');
    });

    test('sensitive custom fields are stored as protected', () {
      const json = '''
      {
        "folders": [],
        "items": [{
          "title": "Q&A",
          "category": "login",
          "fields": [
            {"label": "Security question", "type": "text",
              "value": "Mother", "sensitive": 0},
            {"label": "Security answer", "type": "text",
              "value": "Alice", "sensitive": 1}
          ]
        }]
      }
      ''';
      final item = const EnpassParser().parseJson(json).single;
      expect(_field(item, 'Security question')?.isProtected, isFalse);
      expect(_field(item, 'Security answer')?.isProtected, isTrue);
    });

    test('skips items flagged as trashed', () {
      const json = '''
      {
        "folders": [],
        "items": [
          {"title": "Alive", "category": "login", "trashed": 0,
            "fields": [
              {"label": "Username", "type": "username", "value": "a"}
            ]},
          {"title": "Dead", "category": "login", "trashed": 1,
            "fields": [
              {"label": "Username", "type": "username", "value": "b"}
            ]}
        ]
      }
      ''';
      final items = const EnpassParser().parseJson(json);
      expect(items, hasLength(1));
      expect(items.single.title, 'Alive');
    });

    test('favorite and archived flags become tags', () {
      const json = '''
      {
        "folders": [],
        "items": [{
          "title": "FavItem", "category": "login",
          "favorite": 1, "archived": 0,
          "fields": [
            {"label": "Username", "type": "username", "value": "x"}
          ]
        }]
      }
      ''';
      final item = const EnpassParser().parseJson(json).single;
      expect(item.tags, contains('Favorite'));
      expect(item.tags, isNot(contains('Archived')));
    });

    test('a note-only item with no fields still parses', () {
      const json = '''
      {
        "folders": [],
        "items": [{
          "title": "JustANote",
          "category": "note",
          "note": "Important reminder.",
          "fields": []
        }]
      }
      ''';
      final item = const EnpassParser().parseJson(json).single;
      expect(item.title, 'JustANote');
      expect(item.notes, 'Important reminder.');
      expect(item.username, isNull);
      expect(item.password, isNull);
    });
  });

  // ── CSV ───────────────────────────────────────────────────────────────

  group('EnpassParser - CSV (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items = const EnpassParser().parseCsv(csvFixture.readAsStringSync());
    });

    test('parses a substantial number of items', () {
      expect(items.length, greaterThan(1000));
    });

    test('maps a standard login row', () {
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(item.username, 'divand553@gmail.com');
      expect(item.password, 'WZsfLQTVYd!SufUhyG286oK!e3&');
      expect(item.url, startsWith('https://0vd37z6cvqay.kintone.com'));
    });

    test('handles a row whose final cell is a multi-line favorite/archived '
        'block (multi-physical-line CSV record)', () {
      // Row "103.21.128.217" is followed by an embedded `favorite:`/`archived:`
      // metadata block spanning two physical lines. The notes must be cleaned.
      final item = _itemNamed(items, '103.21.128.217');
      expect(item.username, 'goshopno');
      expect(item.password, 'bEIihHuYRE7mDBNo');
      // Either notes is null or it doesn't carry the metadata flags.
      final notes = item.notes ?? '';
      expect(notes, isNot(contains('favorite:')));
      expect(notes, isNot(contains('archived:')));
    });

    test('stores `*Password`-style sensitive markers without leaking the '
        'asterisk into custom field names', () {
      // No item should expose a custom field literally named "*Password" or
      // "*Security answer" — the leading * is the sensitivity marker.
      for (final item in items) {
        for (final f in item.customFields) {
          expect(f.name.startsWith('*'), isFalse,
              reason: 'Custom field name "${f.name}" still has the * prefix.');
        }
      }
    });

    test('"Key"-type non-login rows still parse and capture the key', () {
      final item = _itemNamed(items, '(Steam CN) Skyline 2');
      // The "Key" label is not a standard credential — it should land in
      // custom fields verbatim.
      expect(_field(item, 'Key')?.value, 'EFSC3-ZU8OG-NJUGW-F80FF-807FR');
    });
  });

  group('EnpassParser - CSV (parsing details)', () {
    test('strips leading * sensitivity marker from labels and marks the '
        'corresponding custom field as protected', () {
      const csv =
          '"My Site","Username","alice","*Password","secret","*Custom Secret","topsecret"\n';
      final item = const EnpassParser().parseCsv(csv).single;
      expect(item.username, 'alice');
      expect(item.password, 'secret');
      final cf = _field(item, 'Custom Secret');
      expect(cf, isNotNull);
      expect(cf!.value, 'topsecret');
      expect(cf.isProtected, isTrue);
    });

    test('skips the "ADDITIONAL DETAILS" section marker', () {
      const csv =
          '"S","Username","u","*Password","p","ADDITIONAL DETAILS","","Phone number","123"\n';
      final item = const EnpassParser().parseCsv(csv).single;
      expect(_field(item, 'ADDITIONAL DETAILS'), isNull);
      expect(_field(item, 'Phone number')?.value, '123');
    });

    test('treats a One-time code that is already an otpauth URI as TOTP', () {
      const csv =
          '"S","Username","u","One-time code","otpauth://totp/x?secret=Z"\n';
      final item = const EnpassParser().parseCsv(csv).single;
      expect(item.otpAuthUrl, 'otpauth://totp/x?secret=Z');
    });

    test('wraps a bare base32 One-time code value into an otpauth URI', () {
      const csv = '"My Site","Username","u","One-time code","ABCDEFGH"\n';
      final item = const EnpassParser().parseCsv(csv).single;
      expect(item.otpAuthUrl,
          'otpauth://totp/${Uri.encodeComponent('My Site')}?secret=ABCDEFGH');
    });

    test('an unpaired trailing free-text cell is appended to the note', () {
      // Pair count is odd by one: the trailing quoted string has no label.
      const csv =
          '"S","Username","u","*Password","p","You can use this to sign in."\n';
      final item = const EnpassParser().parseCsv(csv).single;
      expect(item.notes, 'You can use this to sign in.');
    });

    test('collapses exact duplicate rows', () {
      const csv = '"Dup","Username","u","*Password","p","Website","https://x"\n'
          '"Dup","Username","u","*Password","p","Website","https://x"\n'
          '"Dup","Username","u","*Password","other","Website","https://x"\n';
      final items = const EnpassParser().parseCsv(csv);
      expect(items, hasLength(2));
    });

    test('strips C0 control characters from values', () {
      // Embed BEL (\x07) in the username and password.
      final csv =
          '"S","Username","al\x07ice","*Password","pa\x07ss","Website","https://x"\n';
      final item = const EnpassParser().parseCsv(csv).single;
      expect(item.username, 'alice');
      expect(item.password, 'pass');
    });

    test('rejects an empty CSV', () {
      expect(
        () => const EnpassParser().parseCsv('   '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('rejects a CSV that does not look like Enpass', () {
      const csv = '"random","data","without","enpass","labels"\n';
      expect(
        () => const EnpassParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like an Enpass export'))),
      );
    });
  });

  // ── TXT ───────────────────────────────────────────────────────────────

  group('EnpassParser - TXT (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items = const EnpassParser().parseTxt(txtFixture.readAsStringSync());
    });

    test('parses a substantial number of blocks', () {
      expect(items.length, greaterThan(1000));
    });

    test('maps a standard login block', () {
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(item.username, 'divand553@gmail.com');
      expect(item.password, 'WZsfLQTVYd!SufUhyG286oK!e3&');
      expect(item.url, startsWith('https://0vd37z6cvqay.kintone.com'));
    });

    test('captures custom-label fields like "Key" or "Openclaw"', () {
      final item = _itemNamed(items, '(ChiaSeGPU) Tran Claude-Opus-4.6 Key');
      expect(_field(item, 'Key'), isNotNull);
      expect(_field(item, 'Openclaw'), isNotNull);
    });

    test('"Field N : password" placeholders are not stored as data', () {
      // Item "0vd37z6cvqay.kintone.com" has `Field 1 : password` in the TXT
      // — that's an Enpass template-type token, not real data.
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(_field(item, 'Field 1'), isNull);
    });
  });

  group('EnpassParser - TXT (parsing details)', () {
    test('a single block with the standard fields parses correctly', () {
      const txt = 'Title : Example\n'
          'Username : alice\n'
          'Password : secret\n'
          'Website : https://x.test\n'
          'Note : hello world\n';
      final item = const EnpassParser().parseTxt(txt).single;
      expect(item.title, 'Example');
      expect(item.username, 'alice');
      expect(item.password, 'secret');
      expect(item.url, 'https://x.test');
      expect(item.notes, 'hello world');
    });

    test('records are separated by blank lines', () {
      const txt = 'Title : A\n'
          'Username : ua\n'
          '\n\n'
          'Title : B\n'
          'Username : ub\n';
      final items = const EnpassParser().parseTxt(txt);
      expect(items.map((i) => i.title), <String>['A', 'B']);
    });

    test('lines without " : " separator continue the previous field value',
        () {
      const txt = 'Title : Doppler\n'
          'Note : Recovery codes:\n'
          'abc-123\n'
          'def-456\n';
      final item = const EnpassParser().parseTxt(txt).single;
      expect(item.notes, 'Recovery codes:\nabc-123\ndef-456');
    });

    test('an otpauth-prefixed One-time code value is preserved', () {
      const txt = 'Title : Site\n'
          'One-time code : otpauth://totp/site?secret=XYZ\n';
      final item = const EnpassParser().parseTxt(txt).single;
      expect(item.otpAuthUrl, 'otpauth://totp/site?secret=XYZ');
    });

    test('a bare base32 One-time code is wrapped into an otpauth URI', () {
      const txt = 'Title : Site\n'
          'One-time code : JBSWY3DPEHPK3PXP\n';
      final item = const EnpassParser().parseTxt(txt).single;
      expect(item.otpAuthUrl,
          'otpauth://totp/${Uri.encodeComponent('Site')}?secret=JBSWY3DPEHPK3PXP');
    });

    test('duplicate `Password :` lines store the second as Password 2', () {
      const txt = 'Title : Dup\n'
          'Password : first\n'
          'Password : second\n';
      final item = const EnpassParser().parseTxt(txt).single;
      expect(item.password, 'first');
      final p2 = _field(item, 'Password 2');
      expect(p2, isNotNull);
      expect(p2!.value, 'second');
      expect(p2.isProtected, isTrue);
    });

    test('"Field N : password" placeholder values are skipped', () {
      const txt = 'Title : Site\n'
          'Username : u\n'
          'Field 1 : password\n'
          'Field 2 : note\n'
          'Real Field : real value\n';
      final item = const EnpassParser().parseTxt(txt).single;
      expect(_field(item, 'Field 1'), isNull);
      expect(_field(item, 'Field 2'), isNull);
      expect(_field(item, 'Real Field')?.value, 'real value');
    });

    test('collapses exact duplicate blocks', () {
      const txt = 'Title : Dup\n'
          'Username : u\n'
          'Password : p\n'
          '\n\n'
          'Title : Dup\n'
          'Username : u\n'
          'Password : p\n';
      final items = const EnpassParser().parseTxt(txt);
      expect(items, hasLength(1));
    });

    test('rejects an empty TXT', () {
      expect(
        () => const EnpassParser().parseTxt('   '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('rejects content with no Title lines', () {
      const txt = 'something : random\nother : line\n';
      expect(
        () => const EnpassParser().parseTxt(txt),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like an Enpass export'))),
      );
    });
  });

  // ── JSON error handling ────────────────────────────────────────────────

  group('EnpassParser - JSON error handling', () {
    test('rejects an empty file', () {
      expect(
        () => const EnpassParser().parseJson(''),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('rejects invalid JSON', () {
      expect(
        () => const EnpassParser().parseJson('not json {'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('not valid JSON'))),
      );
    });

    test('rejects JSON without an "items" array', () {
      expect(
        () => const EnpassParser().parseJson('{"folders": []}'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like an Enpass export'))),
      );
    });

    test('rejects an items array with no importable items', () {
      expect(
        () => const EnpassParser()
            .parseJson('{"folders": [], "items": []}'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('No importable items'))),
      );
    });
  });

  // ── parseFile + service routing ────────────────────────────────────────

  group('EnpassParser - parseFile dispatch', () {
    test('parseFile rejects an unknown extension', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/enpass_bad_${DateTime.now().microsecondsSinceEpoch}.xml');
      await tmp.writeAsString('<root></root>');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const EnpassParser().parseFile(tmp.path),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('Enpass exports must be a .json, .csv, or .txt'))),
      );
    });

    test('parseFile rejects a missing file', () async {
      final missing =
          '${Directory.systemTemp.path}/enpass_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.json';
      expect(
        () => const EnpassParser().parseFile(missing),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('File not found'))),
      );
    });

    test('parseFile routes .json to parseJson', () async {
      final items =
          await const EnpassParser().parseFile(jsonFixture.path);
      expect(items, isNotEmpty);
      expect(items.first.getSourceField('enpass_category'), isNotNull);
    });

    test('parseFile routes .csv to parseCsv', () async {
      final items = await const EnpassParser().parseFile(csvFixture.path);
      expect(items, isNotEmpty);
      expect(items.first.getSourceField('enpass_source'), 'csv');
    });

    test('parseFile routes .txt to parseTxt', () async {
      final items = await const EnpassParser().parseFile(txtFixture.path);
      expect(items, isNotEmpty);
      expect(items.first.getSourceField('enpass_source'), 'txt');
    });
  });

  group('ImportParserService - routing & file-type validation', () {
    test('routes Enpass JSON via the service', () async {
      final items = await const ImportParserService().parseFile(
        jsonFixture.path,
        provider: ImportProviderType.enpass,
      );
      expect(items, isNotEmpty);
    });

    test('routes Enpass CSV via the service', () async {
      final items = await const ImportParserService().parseFile(
        csvFixture.path,
        provider: ImportProviderType.enpass,
      );
      expect(items, isNotEmpty);
    });

    test('routes Enpass TXT via the service', () async {
      final items = await const ImportParserService().parseFile(
        txtFixture.path,
        provider: ImportProviderType.enpass,
      );
      expect(items, isNotEmpty);
    });

    test('rejects an unsupported file extension for Enpass', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/enpass_routing_${DateTime.now().microsecondsSinceEpoch}.xml');
      await tmp.writeAsString('<root/>');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });
      expect(
        () => const ImportParserService()
            .parseFile(tmp.path, provider: ImportProviderType.enpass),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('Enpass exports must be a .json, .csv, or .txt'))),
      );
    });

    test('Enpass provider advertises .json, .csv, and .txt', () {
      expect(
        ImportProviderDefinition.enpass.acceptedExtensions,
        <String>['.json', '.csv', '.txt'],
      );
    });
  });
}
