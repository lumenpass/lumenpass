import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/domain/import_provider.dart';
import 'package:lumenpass/features/import/infrastructure/chrome_parser.dart';
import 'package:lumenpass/features/import/infrastructure/import_parser_service.dart';

/// Resolves the Chrome export shipped under
/// `testing/Data-Import/Chrome/` regardless of where the test runner is
/// launched from.
String _chromeFixtureDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/testing/Data-Import/Chrome');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate testing/Data-Import/Chrome fixtures.');
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

void main() {
  late String fixtureDir;
  late File csvFixture;

  setUpAll(() {
    fixtureDir = _chromeFixtureDir();
    csvFixture = _firstWithExtension(fixtureDir, '.csv');
  });

  group('ChromeParser - example export', () {
    test('the bundled fixture has the canonical Chrome header', () {
      // Chrome's export header is exactly `name,url,username,password,note`.
      // The shipped fixture happens to be header-only (no rows), so we only
      // assert that the parser recognises the shape and surfaces the
      // expected error rather than misclassifying it.
      final content = csvFixture.readAsStringSync();
      expect(content.trim().toLowerCase(),
          startsWith('name,url,username,password,note'));
      expect(
        () => const ChromeParser().parseCsv(content),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('No importable rows'))),
      );
    });
  });

  group('ChromeParser - CSV parsing', () {
    test('parses a minimal CSV with all standard columns', () {
      const csv = 'name,url,username,password,note\n'
          'Site,https://x.test,alice,secret,a note\n';
      final items = const ChromeParser().parseCsv(csv);
      expect(items, hasLength(1));
      final item = items.single;
      expect(item.title, 'Site');
      expect(item.url, 'https://x.test');
      expect(item.username, 'alice');
      expect(item.password, 'secret');
      expect(item.notes, 'a note');
      expect(item.isReady, isTrue);
    });

    test('accepts a CSV without the optional note column', () {
      const csv = 'name,url,username,password\n'
          'Site,https://x.test,alice,secret\n';
      final item = const ChromeParser().parseCsv(csv).single;
      expect(item.title, 'Site');
      expect(item.password, 'secret');
      expect(item.notes, isNull);
    });

    test('parses multiple rows in order', () {
      const csv = 'name,url,username,password,note\n'
          'A,https://a.test,ua,pa,\n'
          'B,https://b.test,ub,pb,\n'
          'C,https://c.test,uc,pc,\n';
      final items = const ChromeParser().parseCsv(csv);
      expect(items.map((i) => i.title), <String>['A', 'B', 'C']);
    });

    test('collapses exact duplicate rows', () {
      const csv = 'name,url,username,password,note\n'
          'Dup,https://x.test,u,p,\n'
          'Dup,https://x.test,u,p,\n'
          'Dup,https://x.test,other,p,\n';
      final items = const ChromeParser().parseCsv(csv);
      expect(items, hasLength(2));
    });

    test('handles a quoted password that contains a comma', () {
      const csv = 'name,url,username,password,note\n'
          'Site,https://x.test,alice,"pa,ss",\n';
      final item = const ChromeParser().parseCsv(csv).single;
      expect(item.password, 'pa,ss');
    });

    test('strips C0 control characters from values', () {
      final csv = 'name,url,username,password,note\n'
          'Si\x07te,https://x.test,al\x07ice,pa\x1Fss,\n';
      final item = const ChromeParser().parseCsv(csv).single;
      expect(item.title, 'Site');
      expect(item.username, 'alice');
      expect(item.password, 'pass');
    });

    test('skips blank rows', () {
      const csv = 'name,url,username,password,note\n'
          'Site,https://x.test,u,p,\n'
          ',,,,\n'
          'Site2,https://y.test,u,p,\n';
      final items = const ChromeParser().parseCsv(csv);
      expect(items, hasLength(2));
    });

    test('rejects an empty CSV', () {
      expect(
        () => const ChromeParser().parseCsv('   '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('rejects a CSV with the wrong header', () {
      const csv = 'title,url,user,pass\n1,2,3,4\n';
      expect(
        () => const ChromeParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like a Chrome password export'))),
      );
    });

    test('rejects a header-only CSV with no rows', () {
      const csv = 'name,url,username,password,note\n';
      expect(
        () => const ChromeParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('No importable rows'))),
      );
    });
  });

  group('ChromeParser - parseFile dispatch', () {
    test('parseFile rejects a non-CSV file', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/chrome_bad_${DateTime.now().microsecondsSinceEpoch}.json');
      await tmp.writeAsString('name,url,username,password,note\n');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ChromeParser().parseFile(tmp.path),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('Chrome password exports must be a .csv file'))),
      );
    });

    test('parseFile rejects a missing file', () async {
      final missing =
          '${Directory.systemTemp.path}/chrome_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.csv';
      expect(
        () => const ChromeParser().parseFile(missing),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('File not found'))),
      );
    });
  });

  group('ImportParserService - routing & file-type validation', () {
    test('routes a Chrome CSV through the service', () async {
      // Write a small valid Chrome CSV to a temp file and route it via the
      // service. We don't use the shipped fixture here because it's
      // header-only.
      final tmp = File(
          '${Directory.systemTemp.path}/chrome_route_${DateTime.now().microsecondsSinceEpoch}.csv');
      await tmp.writeAsString(
          'name,url,username,password,note\nSite,https://x.test,u,p,\n');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final items = await const ImportParserService().parseFile(
        tmp.path,
        provider: ImportProviderType.chrome,
      );
      expect(items, hasLength(1));
      expect(items.single.title, 'Site');
    });

    test('rejects a non-CSV file for the Chrome provider', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/chrome_routing_${DateTime.now().microsecondsSinceEpoch}.txt');
      await tmp.writeAsString('not csv');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ImportParserService()
            .parseFile(tmp.path, provider: ImportProviderType.chrome),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('Chrome password exports must be a .csv file'))),
      );
    });

    test('Chrome provider advertises only .csv', () {
      expect(
        ImportProviderDefinition.chrome.acceptedExtensions,
        <String>['.csv'],
      );
    });
  });
}
