import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/domain/import_parsed_item.dart';
import 'package:lumenpass/features/import/domain/import_provider.dart';
import 'package:lumenpass/features/import/infrastructure/import_parser_service.dart';
import 'package:lumenpass/features/import/infrastructure/roboform_parser.dart';

/// Resolves the example RoboForm export shipped in
/// `testing/Data-Import/Roboform/` regardless of where the test runner is
/// launched from.
String _roboformFixtureDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate =
        Directory('${dir.path}/testing/Data-Import/Roboform');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate testing/Data-Import/Roboform fixtures.');
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
  late File csvFixture;

  setUpAll(() {
    fixtureDir = _roboformFixtureDir();
    csvFixture = _firstWithExtension(fixtureDir, '.csv');
  });

  group('RoboFormParser - CSV (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items =
          const RoboFormParser().parseCsv(csvFixture.readAsStringSync());
    });

    test('parses a substantial number of items', () {
      // The export contains thousands of rows; we just need a healthy minimum
      // so a regression that drops most rows is loud.
      expect(items.length, greaterThan(1000));
    });

    test('maps a simple login row (username, password, URL)', () {
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(item.username, 'divand553@gmail.com');
      expect(item.password, 'WZsfLQTVYd!SufUhyG286oK!e3&');
      expect(item.url, startsWith('https://0vd37z6cvqay.kintone.com/login'));
      expect(item.isReady, isTrue);
    });

    test('de-escapes formula-guarded passwords (leading apostrophe + @)', () {
      // Row 122: password is stored as `'@Vantuan21212` in the CSV.
      final item = _itemNamed(items, '1Password Account (Tran IT)');
      expect(item.password, '@Vantuan21212');
    });

    test('promotes a TOTP KEY RfFieldsV2 entry to the otpauth URL', () {
      final item = _itemNamed(items, '1Password Account (Tran IT)');
      expect(item.otpAuthUrl, isNotNull);
      expect(item.otpAuthUrl, startsWith('otpauth://totp/'));
      expect(item.otpAuthUrl, contains('secret=R53ZZKLN4OBYZVYH'));
      // The TOTP value should not be duplicated as a custom field.
      expect(_field(item, 'TOTP KEY'), isNull);
    });

    test('promotes another TOTP from a second item independently', () {
      final item = _itemNamed(items, 'Bitwarden');
      expect(item.otpAuthUrl,
          contains('secret=I4CAHZ7XXSML4CJASDQLOERH5CIPVIXS'));
    });

    test('preserves CSV-quoted passwords that contain embedded commas', () {
      // Row 755: password is `O-HsRs,rsRG8` (with a literal comma).
      final item =
          _itemNamed(items, 'c1s1-3m-mel.hosting-services.net.au');
      expect(item.password, 'O-HsRs,rsRG8');
    });

    test('cleans favorite/archived flag lines out of multi-line notes', () {
      // Row 127 has notes:
      //   favorite: false
      //   archived: false
      //   Imported from 1Password.
      final item = _itemNamed(items, '206.189.71.137[2]');
      expect(item.notes, 'Imported from 1Password.');
      expect(item.notes, isNot(contains('favorite')));
      expect(item.notes, isNot(contains('archived')));
    });

    test('does not echo the primary login/password as custom fields', () {
      // The "User ID" / "Password" RfFieldsV2 entries that mirror the main
      // credentials should be skipped by the parser.
      final item = _itemNamed(items, '0vd37z6cvqay.kintone.com');
      expect(_field(item, 'User ID'), isNull);
      expect(_field(item, 'Password'), isNull);
    });

    test('every parsed item has a non-empty title and a recorded csv row',
        () {
      for (final item in items) {
        expect(item.title.trim(), isNotEmpty);
        expect(item.getSourceField('csv_row'), isNotNull);
      }
    });
  });

  group('RoboFormParser - field mapping details', () {
    test('parses a TOTP KEY value that contains commas without truncation',
        () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Site,https://x.test,https://x.test,u,p,,,'
          '"User ID\$,,,txt,u",'
          '"Password\$,,,pwd,p",'
          '"TOTP KEY\$,,,txt,otpauth://totp/?secret=ABC123&period=30&algorithm=SHA1&digits=6"\n';
      final items = const RoboFormParser().parseCsv(csv);
      expect(items, hasLength(1));
      expect(items.single.otpAuthUrl,
          'otpauth://totp/?secret=ABC123&period=30&algorithm=SHA1&digits=6');
    });

    test('wraps a bare TOTP secret in an otpauth URI labeled with the item',
        () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'My App,https://x.test,https://x.test,u,p,,,'
          '"TOTP\$,,,txt,ABCDEFGH"\n';
      final items = const RoboFormParser().parseCsv(csv);
      final item = items.single;
      expect(item.otpAuthUrl, isNotNull);
      expect(item.otpAuthUrl,
          'otpauth://totp/${Uri.encodeComponent('My App')}?secret=ABCDEFGH');
    });

    test('stores pwd-typed custom fields as protected and txt as plain', () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Site,https://x.test,https://x.test,u,p,,,'
          '"Recovery Code\$,,,pwd,SECRET-1",'
          '"Hint\$,,,txt,childhood pet"\n';
      final items = const RoboFormParser().parseCsv(csv);
      final item = items.single;
      final recovery = _field(item, 'Recovery Code');
      final hint = _field(item, 'Hint');
      expect(recovery, isNotNull);
      expect(recovery!.value, 'SECRET-1');
      expect(recovery.isProtected, isTrue);
      expect(hint, isNotNull);
      expect(hint!.value, 'childhood pet');
      expect(hint.isProtected, isFalse);
    });

    test('maps a non-empty Folder column into a tag', () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Site,https://x.test,https://x.test,u,p,,Work/Cloud,'
          '"User ID\$,,,txt,u"\n';
      final items = const RoboFormParser().parseCsv(csv);
      expect(items.single.tags, contains('Work/Cloud'));
    });

    test('uses only the first URL when the Url cell is comma-joined', () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Site,"https://primary.test,https://secondary.test",'
          'https://primary.test,u,p,,,\n';
      final items = const RoboFormParser().parseCsv(csv);
      expect(items.single.url, 'https://primary.test');
    });

    test('a row with no RfFieldsV2 entries still parses its main credentials',
        () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Bare,https://x.test,https://x.test,u,p,,,\n';
      final items = const RoboFormParser().parseCsv(csv);
      expect(items.single.username, 'u');
      expect(items.single.password, 'p');
      expect(items.single.customFields, isEmpty);
    });
  });

  group('RoboFormParser - duplicate prevention', () {
    test('collapses exact duplicate rows', () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Dup,https://x.test,https://x.test,user,pw,,,\n'
          'Dup,https://x.test,https://x.test,user,pw,,,\n'
          'Dup,https://x.test,https://x.test,other,pw,,,\n';
      final items = const RoboFormParser().parseCsv(csv);
      // First two collapse, the third is distinct.
      expect(items.length, 2);
    });
  });

  group('RoboFormParser - sanitization', () {
    test('strips C0/C1 control characters from values before storage', () {
      // Embed BEL (\x07) and US (\x1F) into a quoted CSV cell.
      final csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Ti\x07tle,https://x.test,https://x.test,'
          'ab\x07cd,p\x1Fw,,,\n';
      final items = const RoboFormParser().parseCsv(csv);
      final item = items.single;
      expect(item.title, 'Title');
      expect(item.username, 'abcd');
      expect(item.password, 'pw');
    });

    test('preserves tabs and newlines in notes', () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Note,https://x.test,https://x.test,u,p,'
          '"line1\nline2\tindented",,\n';
      final items = const RoboFormParser().parseCsv(csv);
      expect(items.single.notes, 'line1\nline2\tindented');
    });
  });

  group('RoboFormParser - error handling', () {
    test('rejects an empty CSV', () {
      expect(
        () => const RoboFormParser().parseCsv('   '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('rejects a CSV that is not a RoboForm export', () {
      const csv = 'col1,col2,col3\na,b,c\n';
      expect(
        () => const RoboFormParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like a RoboForm export'))),
      );
    });

    test('rejects a header-only RoboForm CSV with no rows', () {
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n';
      expect(
        () => const RoboFormParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('No importable rows'))),
      );
    });

    test('tolerates a malformed RfFieldsV2 entry without crashing', () {
      // The entry "garbage" lacks the `$` separator, so the parser should
      // ignore it instead of throwing.
      const csv = 'Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2\n'
          'Site,https://x.test,https://x.test,u,p,,,garbage\n';
      final items = const RoboFormParser().parseCsv(csv);
      expect(items, hasLength(1));
      expect(items.single.customFields, isEmpty);
    });

    test('parseFile rejects a non-CSV extension', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/rf_invalid_${DateTime.now().microsecondsSinceEpoch}.txt');
      await tmp.writeAsString('Name,Url,Login,Pwd,RfFieldsV2\n');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const RoboFormParser().parseFile(tmp.path),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('RoboForm exports must be a .csv file'))),
      );
    });

    test('parseFile rejects a missing file', () async {
      final missing =
          '${Directory.systemTemp.path}/rf_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.csv';
      expect(
        () => const RoboFormParser().parseFile(missing),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('File not found'))),
      );
    });
  });

  group('ImportParserService - routing & file-type validation', () {
    test('routes a RoboForm CSV to the RoboForm parser', () async {
      final items = await const ImportParserService().parseFile(
        csvFixture.path,
        provider: ImportProviderType.roboForm,
      );
      expect(items, isNotEmpty);
    });

    test('rejects a non-CSV file when the provider is RoboForm', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/rf_routing_${DateTime.now().microsecondsSinceEpoch}.json');
      await tmp.writeAsString('{"not": "a roboform export"}');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ImportParserService()
            .parseFile(tmp.path, provider: ImportProviderType.roboForm),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('RoboForm exports must be a .csv file'))),
      );
    });

    test('RoboForm provider advertises only .csv as the accepted format', () {
      expect(
        ImportProviderDefinition.roboForm.acceptedExtensions,
        <String>['.csv'],
      );
    });
  });
}
