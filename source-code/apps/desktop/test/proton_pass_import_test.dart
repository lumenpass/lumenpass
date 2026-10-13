import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/domain/import_parsed_item.dart';
import 'package:lumenpass/features/import/domain/import_provider.dart';
import 'package:lumenpass/features/import/infrastructure/import_parser_service.dart';
import 'package:lumenpass/features/import/infrastructure/proton_pass_parser.dart';

/// Resolves the example Proton Pass export shipped in the repo's
/// `testing/Data-Import/ProtonPass/` directory regardless of the cwd the test
/// runner is launched from.
String _protonFixtureDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/testing/Data-Import/ProtonPass');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate testing/Data-Import/ProtonPass fixtures.');
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
    fixtureDir = _protonFixtureDir();
    csvFixture = _firstWithExtension(fixtureDir, '.csv');
  });

  group('ProtonPassParser - CSV (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items = const ProtonPassParser().parseCsv(csvFixture.readAsStringSync());
    });

    test('parses a substantial number of items', () {
      expect(items.length, greaterThan(100));
    });

    test('maps a login item, using the email as username when none is set', () {
      final item = _itemNamed(items, 'Offcloud');
      expect(item.username, 'tranit1209@gmail.com');
      expect(item.password, '@vantuan212');
      expect(item.isReady, isTrue);
    });

    test('uses the explicit username column when present', () {
      final item = _itemNamed(items, 'BG Gaming Zone');
      // BG Gaming Zone uses the email column only.
      expect(item.username, 'tranit1209@gmail.com');
      expect(item.password, 'qmv*UEM1jgc-gfb7kmt');
    });

    test('splits a comma-joined multi-URI into a single primary URL', () {
      final item = _itemNamed(items, 'Offcloud');
      expect(
        item.url,
        'https://offcloud.com/login?tag=password_reset&email=tranit1209@gmail.com',
      );
    });

    test('passes an existing otpauth URI through unchanged', () {
      final item = _itemNamed(items, 'Dropbox');
      expect(item.otpAuthUrl, isNotNull);
      expect(item.otpAuthUrl!.startsWith('otpauth://totp/'), isTrue);
      expect(item.otpAuthUrl, contains('secret=EBS75J6CDNYQI26QQRIPBZXCYM'));
    });

    test('strips favorite/archived metadata from the note column', () {
      // Dropbox's note column only carries Proton's favorite/archived flags.
      final item = _itemNamed(items, 'Dropbox');
      expect(item.notes, isNull);
    });

    test('keeps a real multi-line note from a quoted CSV cell', () {
      final item = _itemNamed(items, 'Viscosity');
      expect(item.notes, contains('Nimasystems Ltd'));
      expect(item.notes, contains('VM1U-PTMJN1-7LUVEG-TI2WZ4-URDJS8-IL7YNE'));
    });

    test('maps a note item', () {
      final item = _itemNamed(items, 'Batender 4');
      expect(item.getSourceField('proton_type'), 'note');
      expect(item.isReady, isTrue);
    });

    test('maps a credit card with protected number and security code', () {
      final item = _itemNamed(items, 'HomeCredit Visa');
      expect(_field(item, 'Cardholder Name')?.value, 'TRAN VAN TUAN');
      expect(_field(item, 'Number')?.value, '4922 3600 1156 0872');
      expect(_field(item, 'Number')?.isProtected, isTrue);
      expect(_field(item, 'Security Code')?.value, '808');
      expect(_field(item, 'Security Code')?.isProtected, isTrue);
      expect(_field(item, 'Expiration')?.value, '2027-04');
    });

    test('maps an identity item into labeled custom fields', () {
      final item = _itemNamed(items, '11 Vo Thi Sau Street');
      expect(_field(item, 'Street Address')?.value, '11 Vo Thi Sau Street');
      expect(_field(item, 'City')?.value, 'District 3');
      expect(_field(item, 'Zip/Postal Code')?.value, '84000');
      expect(_field(item, 'Country/Region')?.value, 'vn');
    });

    test('maps the Proton vault name to a tag', () {
      final item = _itemNamed(items, 'Offcloud');
      expect(item.tags, contains('Personal'));
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

  group('ProtonPassParser - field mapping details', () {
    const header =
        'type,name,url,email,username,password,note,totp,createTime,modifyTime,vault';

    test('prefers username and keeps email as a custom field', () {
      const csv = '$header\n'
          'login,Both,https://x.test,me@x.test,realuser,pw,,,0,0,Personal\n';
      final item = const ProtonPassParser().parseCsv(csv).single;
      expect(item.username, 'realuser');
      expect(_field(item, 'Email')?.value, 'me@x.test');
    });

    test('wraps a raw TOTP secret into an otpauth URI', () {
      const csv = '$header\n'
          'login,Totp,https://x.test,,user,pw,,JBSWY3DPEHPK3PXP,0,0,Personal\n';
      final item = const ProtonPassParser().parseCsv(csv).single;
      expect(item.otpAuthUrl, isNotNull);
      expect(item.otpAuthUrl!.startsWith('otpauth://totp/'), isTrue);
      expect(item.otpAuthUrl, contains('secret=JBSWY3DPEHPK3PXP'));
    });

    test('skips unknown future item types rather than importing garbage', () {
      const csv = '$header\n'
          'mystery,Mystery,,,,,,,0,0,Personal\n'
          'login,Real Login,https://x.test,,user,pw,,,0,0,Personal\n';
      final items = const ProtonPassParser().parseCsv(csv);
      expect(items.length, 1);
      expect(items.single.title, 'Real Login');
    });
  });

  group('ProtonPassParser - duplicate prevention', () {
    const header =
        'type,name,url,email,username,password,note,totp,createTime,modifyTime,vault';

    test('collapses exact duplicate rows', () {
      const csv = '$header\n'
          'login,Same,https://x.test,,user,pw,,,0,0,Personal\n'
          'login,Same,https://x.test,,user,pw,,,0,0,Personal\n'
          'login,Same,https://x.test,,different,pw,,,0,0,Personal\n';
      final items = const ProtonPassParser().parseCsv(csv);
      expect(items.length, 2);
    });
  });

  group('ProtonPassParser - sanitization', () {
    const header =
        'type,name,url,email,username,password,note,totp,createTime,modifyTime,vault';

    test('strips control characters from values before storage', () {
      const csv = '$header\n'
          'login,Inject\u0000Test,,,ab\u0007cd,p\u001Fw,,,0,0,Personal\n';
      final item = const ProtonPassParser().parseCsv(csv).single;
      expect(item.title, 'InjectTest');
      expect(item.username, 'abcd');
      expect(item.password, 'pw');
    });

    test('preserves tabs and newlines in notes', () {
      const csv = '$header\n'
          'note,Note,,,,,"line1\nline2\tindented",,0,0,Personal\n';
      final item = const ProtonPassParser().parseCsv(csv).single;
      expect(item.notes, 'line1\nline2\tindented');
    });
  });

  group('ProtonPassParser - error handling', () {
    test('rejects a CSV that is not a Proton Pass export', () {
      const csv = 'col1,col2,col3\na,b,c\n';
      expect(
        () => const ProtonPassParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like a Proton Pass export'))),
      );
    });

    test('rejects an empty CSV', () {
      expect(
        () => const ProtonPassParser().parseCsv('   '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('rejects a header-only CSV with no importable rows', () {
      const csv =
          'type,name,url,email,username,password,note,totp,createTime,modifyTime,vault\n';
      expect(
        () => const ProtonPassParser().parseCsv(csv),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('No importable rows'))),
      );
    });
  });

  group('ImportParserService - routing & file-type validation', () {
    test('routes a Proton Pass CSV to the Proton Pass parser', () async {
      final items = await const ImportParserService().parseFile(
        csvFixture.path,
        provider: ImportProviderType.protonPass,
      );
      expect(items, isNotEmpty);
    });

    test('rejects a non-CSV file for Proton Pass', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/proton_invalid_${DateTime.now().microsecondsSinceEpoch}.txt');
      await tmp.writeAsString('not a real export');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ImportParserService()
            .parseFile(tmp.path, provider: ImportProviderType.protonPass),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('must be a .csv'))),
      );
    });

    test('Proton Pass provider advertises the CSV format', () {
      expect(
        ImportProviderDefinition.protonPass.acceptedExtensions,
        contains('.csv'),
      );
    });
  });
}
