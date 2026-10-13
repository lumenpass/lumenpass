import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/domain/import_parsed_item.dart';
import 'package:lumenpass/features/import/domain/import_provider.dart';
import 'package:lumenpass/features/import/infrastructure/apple_passwords_parser.dart';
import 'package:lumenpass/features/import/infrastructure/import_parser_service.dart';

/// Resolves the Apple Passwords export shipped under
/// `testing/Data-Import/Apple/` regardless of where the test runner is
/// launched from.
String _appleFixtureDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/testing/Data-Import/Apple');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate testing/Data-Import/Apple fixtures.');
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

void main() {
  late String fixtureDir;
  late File csvFixture;

  setUpAll(() {
    fixtureDir = _appleFixtureDir();
    csvFixture = _firstWithExtension(fixtureDir, '.csv');
  });

  group('ApplePasswordsParser - CSV (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items = const ApplePasswordsParser()
          .parseCsv(csvFixture.readAsStringSync());
    });

    test('parses a substantial number of items', () {
      expect(items.length, greaterThan(1000));
    });

    test('maps a simple login row (title, url, username, password)', () {
      final item = _itemNamed(items, 'AAPanel 199.119.138.61');
      expect(item.username, 'tranit');
      expect(item.password, 'NGaXnJ4C*7k3DZU6%&vm');
      expect(item.url, 'https://199.119.138.61/');
      expect(item.isReady, isTrue);
    });

    test('handles rows whose Notes column spans multiple physical lines '
        'and contains favorite/archived metadata', () {
      // "Aapanel" row notes are split across two physical lines and contain
      // `favorite: false` / `archived: false` — both should be removed.
      final item = _itemNamed(items, 'Aapanel');
      expect(item.username, 'tranit1209@gmail.com');
      expect(item.password, 'vantuan212');
      final notes = item.notes ?? '';
      expect(notes, isNot(contains('favorite:')));
      expect(notes, isNot(contains('archived:')));
    });

    test('collapses exact duplicate rows', () {
      // "Acb" appears twice with identical username/password — only one
      // copy should survive after dedup.
      final acbItems = items.where((i) => i.title == 'Acb').toList();
      expect(acbItems, hasLength(1));
    });

    test('every parsed item has a non-empty title and a recorded csv row',
        () {
      for (final item in items) {
        expect(item.title.trim(), isNotEmpty);
        expect(item.getSourceField('csv_row'), isNotNull);
      }
    });
  });

  group('ApplePasswordsParser - CSV (parsing details)', () {
    test('parses a minimal CSV with all standard columns', () {
      const csv = 'Title,URL,Username,Password,Notes,OTPAuth\n'
          'Site,https://x.test,alice,secret,a note,\n';
      final items = const ApplePasswordsParser().parseCsv(csv);
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.title, 'Site');
      expect(item.url, 'https://x.test');
      expect(item.username, 'alice');
      expect(item.password, 'secret');
      expect(item.notes, 'a note');
    });

    test('passes an otpauth URI through unchanged', () {
      const csv = 'Title,URL,Username,Password,Notes,OTPAuth\n'
          'Site,https://x.test,a,p,,otpauth://totp/site?secret=Z\n';
      final item = const ApplePasswordsParser().parseCsv(csv).single;
      expect(item.otpAuthUrl, 'otpauth://totp/site?secret=Z');
    });

    test('wraps a bare base32 OTPAuth secret in an otpauth URI', () {
      const csv = 'Title,URL,Username,Password,Notes,OTPAuth\n'
          'My App,https://x.test,a,p,,ABCDEFGH\n';
      final item = const ApplePasswordsParser().parseCsv(csv).single;
      expect(item.otpAuthUrl,
          'otpauth://totp/${Uri.encodeComponent('My App')}?secret=ABCDEFGH');
    });

    test('cleans favorite/archived metadata out of multi-line notes', () {
      const csv = 'Title,URL,Username,Password,Notes,OTPAuth\n'
          'Site,https://x.test,u,p,"favorite: false\n'
          'archived: false\n'
          'real note",\n';
      final item = const ApplePasswordsParser().parseCsv(csv).single;
      expect(item.notes, 'real note');
    });

    test('strips C0/C1 control characters from values', () {
      final csv = 'Title,URL,Username,Password,Notes,OTPAuth\n'
          'Si\x07te,https://x.test,al\x07ice,pa\x1Fss,,\n';
      final item = const ApplePasswordsParser().parseCsv(csv).single;
      expect(item.title, 'Site');
      expect(item.username, 'alice');
      expect(item.password, 'pass');
    });

    test('rejects an empty CSV', () {
      expect(
        () => const ApplePasswordsParser().parseCsv('   '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('rejects a CSV with the wrong header', () {
      const csv = 'foo,bar,baz\n1,2,3\n';
      expect(
        () => const ApplePasswordsParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like an Apple Passwords export'))),
      );
    });

    test('rejects a header-only CSV with no rows', () {
      const csv = 'Title,URL,Username,Password,Notes,OTPAuth\n';
      expect(
        () => const ApplePasswordsParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('No importable rows'))),
      );
    });
  });

  group('ApplePasswordsParser - parseFile dispatch', () {
    test('parseFile rejects a non-CSV file', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/apple_bad_${DateTime.now().microsecondsSinceEpoch}.txt');
      await tmp.writeAsString('Title,URL,Username,Password,Notes,OTPAuth\n');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ApplePasswordsParser().parseFile(tmp.path),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('Apple Passwords exports must be a .csv file'))),
      );
    });

    test('parseFile rejects a missing file', () async {
      final missing =
          '${Directory.systemTemp.path}/apple_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.csv';
      expect(
        () => const ApplePasswordsParser().parseFile(missing),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('File not found'))),
      );
    });
  });

  group('ImportParserService - routing & file-type validation', () {
    test('routes an Apple Passwords CSV through the service', () async {
      final items = await const ImportParserService().parseFile(
        csvFixture.path,
        provider: ImportProviderType.applePasswords,
      );
      expect(items, isNotEmpty);
    });

    test('rejects a non-CSV file for the Apple Passwords provider', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/apple_routing_${DateTime.now().microsecondsSinceEpoch}.json');
      await tmp.writeAsString('{"not": "csv"}');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ImportParserService()
            .parseFile(tmp.path, provider: ImportProviderType.applePasswords),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('Apple Passwords exports must be a .csv file'))),
      );
    });

    test('Apple Passwords provider advertises only .csv', () {
      expect(
        ImportProviderDefinition.applePasswords.acceptedExtensions,
        <String>['.csv'],
      );
    });
  });
}
