import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/domain/import_parsed_item.dart';
import 'package:lumenpass/features/import/domain/import_provider.dart';
import 'package:lumenpass/features/import/infrastructure/import_parser_service.dart';
import 'package:lumenpass/features/import/infrastructure/nordpass_parser.dart';

/// Resolves the example NordPass export shipped in the repo's
/// `testing/Data-Import/Nordpass/` directory regardless of the cwd the test
/// runner is launched from.
String _nordpassFixtureDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/testing/Data-Import/Nordpass');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate testing/Data-Import/Nordpass fixtures.');
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
  const header =
      'name,url,additional_urls,username,password,note,cardholdername,'
      'cardnumber,cvc,pin,expirydate,zipcode,folder,shared_folder,full_name,'
      'phone_number,email,address1,address2,city,country,state,type,custom_fields';

  late String fixtureDir;
  late File csvFixture;

  setUpAll(() {
    fixtureDir = _nordpassFixtureDir();
    csvFixture = _firstWithExtension(fixtureDir, '.csv');
  });

  group('NordPassParser - CSV (example export)', () {
    late List<ImportParsedItem> items;

    setUpAll(() {
      items = const NordPassParser().parseCsv(csvFixture.readAsStringSync());
    });

    test('parses a substantial number of items', () {
      expect(items.length, greaterThan(100));
    });

    test('skips folder definition rows', () {
      // "Starter Kit", "Softwares" etc. are folder rows (type=folder) and must
      // never appear as importable items.
      for (final folderName in <String>[
        'Starter Kit',
        'Softwares',
        'Server Logins',
        'TranIT',
      ]) {
        expect(
          items.any((i) => i.title == folderName),
          isFalse,
          reason: '"$folderName" is a folder and should be skipped',
        );
      }
      expect(
        items.every((i) => i.getSourceField('nordpass_type') != 'folder'),
        isTrue,
      );
    });

    test('maps a login with username + password and no URL', () {
      final item = _itemNamed(items, 'Acb');
      expect(item.getSourceField('nordpass_type'), 'password');
      expect(item.username, 'tvt1989');
      expect(item.password, '@vantuan21212');
      expect(item.isReady, isTrue);
    });

    test('maps a login carrying URL + username + password', () {
      final item = _itemNamed(items, 'AAPanel WebHorizon SG');
      expect(item.url, 'http://27.0.234.120:7899/tran-login');
      expect(item.username, 'tranit');
      expect(item.password, 'tBsCy5xwzPwExwUdD34s');
    });

    test('splits a comma-joined multi-URI into a primary URL + extras', () {
      // The "2c2p.inginim.com" row stores three URLs in the quoted url column.
      final item = _itemNamed(items, '2c2p.inginim.com');
      expect(item.url, 'http://2c2p.inginim.com/admin/login');
    });

    test('keeps a real multi-line note from a quoted CSV cell', () {
      final item = _itemNamed(items, 'Nordpass Backup Code');
      expect(item.getSourceField('nordpass_type'), 'note');
      expect(item.notes, isNotNull);
      expect(item.notes, contains('MWPE6RW9'));
      expect(item.notes, contains('BK92CKDG'));
      expect(item.isReady, isTrue);
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

  group('NordPassParser - type mapping (synthetic rows)', () {
    test('prefers username and keeps email as a custom field', () {
      const csv = '$header\n'
          'Both,https://x.test,,realuser,pw,,,,,,,,,,,,me@x.test,,,,,,password,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.username, 'realuser');
      expect(item.password, 'pw');
      expect(item.url, 'https://x.test');
      expect(_field(item, 'Email')?.value, 'me@x.test');
    });

    test('falls back to email as username when username is empty', () {
      const csv = '$header\n'
          'EmailOnly,https://x.test,,,pw,,,,,,,,,,,,me@x.test,,,,,,password,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.username, 'me@x.test');
    });

    test('maps additional_urls to numbered custom fields', () {
      const csv = '$header\n'
          'Multi,https://a.test,"https://a.test,https://b.test,https://c.test",'
          'u,pw,,,,,,,,,,,,,,,,,,password,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.url, 'https://a.test');
      // The primary (https://a.test) is skipped; b/c become URL 1/URL 2.
      expect(_field(item, 'URL 1')?.value, 'https://b.test');
      expect(_field(item, 'URL 2')?.value, 'https://c.test');
    });

    test('maps a credit_card with protected number, cvc, and pin', () {
      const csv = '$header\n'
          'My Visa,,,,,,TRAN VAN TUAN,4922360011560872,808,1234,04/2027,12345,'
          ',,,,,,,,,,credit_card,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.getSourceField('nordpass_type'), 'credit_card');
      expect(_field(item, 'Cardholder Name')?.value, 'TRAN VAN TUAN');
      expect(_field(item, 'Number')?.value, '4922360011560872');
      expect(_field(item, 'Number')?.isProtected, isTrue);
      expect(_field(item, 'Security Code')?.value, '808');
      expect(_field(item, 'Security Code')?.isProtected, isTrue);
      expect(_field(item, 'PIN')?.value, '1234');
      expect(_field(item, 'PIN')?.isProtected, isTrue);
      expect(_field(item, 'Expiration')?.value, '04/2027');
      expect(_field(item, 'Zip Code')?.value, '12345');
    });

    test('maps an identity into labeled custom fields', () {
      const csv = '$header\n'
          'My Identity,,,,,,,,,,,90210,,,Tran Van Tuan,+84123,me@x.test,'
          '11 Vo Thi Sau,Apt 2,District 3,VN,HCMC,identity,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.getSourceField('nordpass_type'), 'identity');
      expect(_field(item, 'Full Name')?.value, 'Tran Van Tuan');
      expect(_field(item, 'Phone')?.value, '+84123');
      expect(_field(item, 'Email')?.value, 'me@x.test');
      expect(_field(item, 'Address 1')?.value, '11 Vo Thi Sau');
      expect(_field(item, 'Address 2')?.value, 'Apt 2');
      expect(_field(item, 'City')?.value, 'District 3');
      expect(_field(item, 'Country')?.value, 'VN');
      expect(_field(item, 'State')?.value, 'HCMC');
      expect(_field(item, 'Zip Code')?.value, '90210');
    });

    test('maps the folder column to a tag', () {
      const csv = '$header\n'
          'Tagged,https://x.test,,u,pw,,,,,,,,Server Logins,,,,,,,,,,password,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.tags, contains('Server Logins'));
    });

    test('flattens the custom_fields JSON array onto the item', () {
      final csv = '$header\n'
          'WithCustom,https://x.test,,u,pw,,,,,,,,,,,,,,,,,,password,'
          '"[{""label"":""API Key"",""value"":""abc123"",""type"":""hidden""},'
          '{""label"":""Note Field"",""value"":""plain""}]"\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(_field(item, 'API Key')?.value, 'abc123');
      expect(_field(item, 'API Key')?.isProtected, isTrue);
      expect(_field(item, 'Note Field')?.value, 'plain');
      expect(_field(item, 'Note Field')?.isProtected, isFalse);
    });

    test('skips folder rows even with synthetic input', () {
      const csv = '$header\n'
          'A Folder,,,,,,,,,,,,,,,,,,,,,,folder,\n'
          'Real Login,https://x.test,,u,pw,,,,,,,,,,,,,,,,,,password,\n';
      final items = const NordPassParser().parseCsv(csv);
      expect(items.length, 1);
      expect(items.single.title, 'Real Login');
    });

    test('best-effort maps an unknown future type instead of dropping it', () {
      const csv = '$header\n'
          'Mystery,https://x.test,,u,pw,,,,,,,,,,,,,,,,,,quantum_vault,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.title, 'Mystery');
      expect(item.username, 'u');
      expect(item.password, 'pw');
      expect(item.url, 'https://x.test');
    });
  });

  group('NordPassParser - duplicate prevention', () {
    test('collapses exact duplicate rows', () {
      const csv = '$header\n'
          'Same,https://x.test,,user,pw,,,,,,,,,,,,,,,,,,password,\n'
          'Same,https://x.test,,user,pw,,,,,,,,,,,,,,,,,,password,\n'
          'Same,https://x.test,,different,pw,,,,,,,,,,,,,,,,,,password,\n';
      final items = const NordPassParser().parseCsv(csv);
      expect(items.length, 2);
    });
  });

  group('NordPassParser - sanitization', () {
    test('strips control characters from values before storage', () {
      const csv = '$header\n'
          'Inject\u0000Test,,,ab\u0007cd,p\u001Fw,,,,,,,,,,,,,,,,,,password,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.title, 'InjectTest');
      expect(item.username, 'abcd');
      expect(item.password, 'pw');
    });

    test('preserves tabs and newlines in notes', () {
      const csv = '$header\n'
          'Note,,,,,"line1\nline2\tindented",,,,,,,,,,,,,,,,,note,\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.notes, 'line1\nline2\tindented');
    });
  });

  group('NordPassParser - error handling', () {
    test('rejects a CSV that is not a NordPass export', () {
      const csv = 'col1,col2,col3\na,b,c\n';
      expect(
        () => const NordPassParser().parseCsv(csv),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('does not look like a NordPass export'))),
      );
    });

    test('rejects an empty CSV', () {
      expect(
        () => const NordPassParser().parseCsv('   '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('rejects a header-only CSV with no importable rows', () {
      const csv = '$header\n';
      expect(
        () => const NordPassParser().parseCsv(csv),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('No importable rows'))),
      );
    });

    test('tolerates a row with fewer columns than the header', () {
      const csv = '$header\n'
          'Short,https://x.test,,u,pw\n';
      final item = const NordPassParser().parseCsv(csv).single;
      expect(item.title, 'Short');
      expect(item.username, 'u');
      expect(item.password, 'pw');
    });
  });

  group('ImportParserService - routing & file-type validation', () {
    test('routes a NordPass CSV to the NordPass parser', () async {
      final items = await const ImportParserService().parseFile(
        csvFixture.path,
        provider: ImportProviderType.nordPass,
      );
      expect(items, isNotEmpty);
    });

    test('rejects a non-CSV file for NordPass', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/nordpass_invalid_${DateTime.now().microsecondsSinceEpoch}.txt');
      await tmp.writeAsString('not a real export');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ImportParserService()
            .parseFile(tmp.path, provider: ImportProviderType.nordPass),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('must be a .csv'))),
      );
    });

    test('NordPass provider advertises the CSV format', () {
      expect(
        ImportProviderDefinition.nordPass.acceptedExtensions,
        contains('.csv'),
      );
    });
  });
}
