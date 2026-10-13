import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/domain/import_parsed_item.dart';
import 'package:lumenpass/features/import/domain/import_provider.dart';
import 'package:lumenpass/features/import/infrastructure/bitwarden_parser.dart';
import 'package:lumenpass/features/import/infrastructure/import_parser_service.dart';

/// Resolves the example Bitwarden export files shipped in the repo's
/// `testing/Data-Import/bitwarden/` directory regardless of the cwd the test
/// runner is launched from.
String _bitwardenFixtureDir() {
  // Walk up from the current directory until we find the testing folder.
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate =
        Directory('${dir.path}/testing/Data-Import/bitwarden');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate testing/Data-Import/bitwarden fixtures.');
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

  setUpAll(() {
    fixtureDir = _bitwardenFixtureDir();
    jsonFixture = _firstWithExtension(fixtureDir, '.json');
    csvFixture = _firstWithExtension(fixtureDir, '.csv');
  });

  group('BitwardenParser - JSON (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items = const BitwardenParser().parseJson(jsonFixture.readAsStringSync());
    });

    test('parses a substantial number of items', () {
      expect(items.length, greaterThan(100));
    });

    test('maps a login item (username, password, URL)', () {
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(item.username, 'divand553@gmail.com');
      expect(item.password, 'WZsfLQTVYd!SufUhyG286oK!e3&');
      expect(item.url, 'https://0vd37z6cvqay.kintone.com/login'
          '?redirect=https%3A%2F%2F0vd37z6cvqay.kintone.com%2Fk%2F');
      expect(item.isReady, isTrue);
    });

    test('normalizes a login TOTP secret into an otpauth URI', () {
      final item = _itemNamed(items, '1Password Account (Tran IT)');
      expect(item.otpAuthUrl, isNotNull);
      expect(item.otpAuthUrl!.startsWith('otpauth://totp/'), isTrue);
      expect(item.otpAuthUrl, contains('secret=R53ZZKLN4OBYZVYH'));
    });

    test('splits a comma-joined multi-URI into a single primary URL', () {
      final item = _itemNamed(items, '2c2p.inginim.com');
      expect(item.url, 'http://2c2p.inginim.com/admin/login');
    });

    test('maps a secure note item via custom fields', () {
      final item = _itemNamed(items, '(ChiaSeGPU) Tran Claude-Opus-4.6 Key');
      expect(_field(item, 'Key')?.value,
          'sk-8dc7681669245a2a68fb1d2024098479890441c20616f89be2732c90ff3feafb');
      expect(_field(item, 'url')?.value, 'https://llm.chiasegpu.vn/v1');
      expect(item.isReady, isTrue);
    });

    test('maps a card item with protected number and security code', () {
      final item = _itemNamed(items, '(BIN) Master 29-12-25');
      expect(_field(item, 'Cardholder Name')?.value, 'Angelina Reichel');
      expect(_field(item, 'Number')?.value, '5518 2770 6824 3631');
      expect(_field(item, 'Number')?.isProtected, isTrue);
      expect(_field(item, 'Security Code')?.value, '936');
      expect(_field(item, 'Security Code')?.isProtected, isTrue);
      expect(_field(item, 'Expiration')?.value, '01/2032');
    });

    test('maps an identity item into labeled custom fields', () {
      final item = _itemNamed(items, '11 Vo Thi Sau Street');
      expect(_field(item, 'Address 1')?.value, '11 Vo Thi Sau Street');
      expect(_field(item, 'City')?.value, 'District 3');
      expect(_field(item, 'Postal Code')?.value, '84000');
      expect(_field(item, 'Country')?.value, 'VN');
    });

    test('maps an SSH key item with a protected private key', () {
      final item = _itemNamed(items, '160.191.29.59 -SSH Key');
      final privateKey = _field(item, 'Private Key');
      expect(privateKey, isNotNull);
      expect(privateKey!.isProtected, isTrue);
      expect(privateKey.value, contains('BEGIN OPENSSH PRIVATE KEY'));
      expect(_field(item, 'Public Key')?.value, startsWith('ssh-ed25519 '));
      expect(_field(item, 'Fingerprint')?.value, startsWith('SHA256:'));
    });

    test('resolves folder ids into tags', () {
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(item.tags, contains('Imported October 8 2024 14:01:04'));
    });

    test('every parsed item carries a title and validates', () {
      for (final item in items) {
        item.validate();
        expect(item.title.trim(), isNotEmpty);
        expect(item.isReady, isTrue,
            reason: 'Item "${item.title}" should be importable but had: '
                '${item.validationErrors}');
      }
    });
  });

  group('BitwardenParser - CSV (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items = const BitwardenParser().parseCsv(csvFixture.readAsStringSync());
    });

    test('parses items including multi-line quoted notes', () {
      expect(items.length, greaterThan(10));
    });

    test('maps a login row with username, password, and URL', () {
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(item.username, 'divand553@gmail.com');
      expect(item.password, 'WZsfLQTVYd!SufUhyG286oK!e3&');
      expect(item.url, startsWith('https://0vd37z6cvqay.kintone.com/login'));
    });

    test('preserves multi-line notes from quoted CSV cells', () {
      // In the Bitwarden CSV this item stores its data in the `fields`
      // column (newline-separated name: value pairs), which we parse into
      // structured custom fields.
      final item = _itemNamed(items, '(ChiaSeGPU) Tran Claude-Opus-4.6 Key');
      expect(_field(item, 'Key')?.value,
          'sk-8dc7681669245a2a68fb1d2024098479890441c20616f89be2732c90ff3feafb');
      expect(_field(item, 'url')?.value, 'https://llm.chiasegpu.vn/v1');
    });

    test('maps folder column to a tag', () {
      final item = _itemNamed(items, '1Password Account (Ổi)');
      expect(item.tags, contains('Starter Kit'));
    });
  });

  group('BitwardenParser - field mapping details', () {
    test('wraps an existing otpauth URI unchanged', () {
      const json = '''
      {
        "encrypted": false,
        "items": [
          {
            "type": 1,
            "name": "Has otpauth",
            "login": {
              "username": "u",
              "password": "p",
              "totp": "otpauth://totp/Example?secret=ABC123"
            }
          }
        ]
      }
      ''';
      final items = const BitwardenParser().parseJson(json);
      expect(items.single.otpAuthUrl, 'otpauth://totp/Example?secret=ABC123');
    });

    test('imports hidden generic fields as protected', () {
      const json = '''
      {
        "encrypted": false,
        "items": [
          {
            "type": 1,
            "name": "With hidden field",
            "fields": [
              {"type": 1, "name": "Recovery", "value": "secret-value"}
            ],
            "login": {"username": "u", "password": "p"}
          }
        ]
      }
      ''';
      final items = const BitwardenParser().parseJson(json);
      final field = _field(items.single, 'Recovery');
      expect(field, isNotNull);
      expect(field!.isProtected, isTrue);
      expect(field.value, 'secret-value');
    });

    test('skips unknown future item types rather than importing garbage', () {
      const json = '''
      {
        "encrypted": false,
        "items": [
          {"type": 99, "name": "Mystery"},
          {"type": 1, "name": "Real Login", "login": {"username": "u"}}
        ]
      }
      ''';
      final items = const BitwardenParser().parseJson(json);
      expect(items.length, 1);
      expect(items.single.title, 'Real Login');
    });
  });

  group('BitwardenParser - duplicate prevention', () {
    test('collapses exact duplicate JSON login items', () {
      const json = '''
      {
        "encrypted": false,
        "items": [
          {
            "type": 1,
            "name": "Dup",
            "login": {"username": "same", "password": "pw",
              "uris": [{"uri": "https://x.test"}]}
          },
          {
            "type": 1,
            "name": "Dup",
            "login": {"username": "same", "password": "pw",
              "uris": [{"uri": "https://x.test"}]}
          },
          {
            "type": 1,
            "name": "Dup",
            "login": {"username": "different", "password": "pw"}
          }
        ]
      }
      ''';
      final items = const BitwardenParser().parseJson(json);
      // Two unique entries: the first (deduped once) and the different one.
      expect(items.length, 2);
    });

    test('collapses exact duplicate CSV rows', () {
      const csv = 'folder,favorite,type,name,notes,fields,reprompt,'
          'login_uri,login_username,login_password,login_totp\n'
          ',,login,Same,,,0,https://x.test,user,pw,\n'
          ',,login,Same,,,0,https://x.test,user,pw,\n';
      final items = const BitwardenParser().parseCsv(csv);
      expect(items.length, 1);
    });
  });

  group('BitwardenParser - sanitization', () {
    test('strips control characters from values before storage', () {
      // The \\uXXXX escapes survive into the JSON document so that
      // jsonDecode produces real control characters inside the values.
      const json = '{'
          '"encrypted": false,'
          '"items": [{"type": 1, "name": "Inject\\u0000Test",'
          '"login": {"username": "ab\\u0007cd", "password": "p\\u001Fw"}}]'
          '}';
      final items = const BitwardenParser().parseJson(json);
      final item = items.single;
      expect(item.title, 'InjectTest');
      expect(item.username, 'abcd');
      expect(item.password, 'pw');
    });

    test('preserves tabs and newlines in notes', () {
      const json = '{'
          '"encrypted": false,'
          '"items": [{"type": 2, "name": "Note",'
          '"notes": "line1\\nline2\\tindented"}]'
          '}';
      final items = const BitwardenParser().parseJson(json);
      expect(items.single.notes, 'line1\nline2\tindented');
    });
  });

  group('BitwardenParser - error handling', () {
    test('rejects malformed JSON with a friendly message', () {
      expect(
        () => const BitwardenParser().parseJson('{ not valid json'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('not valid Bitwarden JSON'))),
      );
    });

    test('rejects encrypted exports', () {
      const json = '{"encrypted": true, "items": []}';
      expect(
        () => const BitwardenParser().parseJson(json),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('encrypted'))),
      );
    });

    test('rejects JSON missing the items list', () {
      const json = '{"encrypted": false, "folders": []}';
      expect(
        () => const BitwardenParser().parseJson(json),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('items'))),
      );
    });

    test('rejects JSON with no importable items', () {
      const json = '{"encrypted": false, "items": [{"type": 99}]}';
      expect(
        () => const BitwardenParser().parseJson(json),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('No importable items'))),
      );
    });

    test('rejects a CSV that is not a Bitwarden export', () {
      const csv = 'col1,col2,col3\na,b,c\n';
      expect(
        () => const BitwardenParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like a Bitwarden export'))),
      );
    });

    test('rejects an empty CSV', () {
      expect(
        () => const BitwardenParser().parseCsv('   '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });
  });

  group('ImportParserService - routing & file-type validation', () {
    test('routes Bitwarden JSON to the Bitwarden parser', () async {
      final items = await const ImportParserService().parseFile(
        jsonFixture.path,
        provider: ImportProviderType.bitwarden,
      );
      expect(items, isNotEmpty);
    });

    test('routes Bitwarden CSV to the Bitwarden parser', () async {
      final items = await const ImportParserService().parseFile(
        csvFixture.path,
        provider: ImportProviderType.bitwarden,
      );
      expect(items, isNotEmpty);
    });

    test('rejects a non-JSON/CSV file for Bitwarden', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/bw_invalid_${DateTime.now().microsecondsSinceEpoch}.txt');
      await tmp.writeAsString('not a real export');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ImportParserService()
            .parseFile(tmp.path, provider: ImportProviderType.bitwarden),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('must be a .json or .csv'))),
      );
    });

    test('Bitwarden provider advertises both accepted formats', () {
      expect(
        ImportProviderDefinition.bitwarden.acceptedExtensions,
        containsAll(<String>['.json', '.csv']),
      );
    });
  });
}
