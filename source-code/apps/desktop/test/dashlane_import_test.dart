import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/domain/import_provider.dart';
import 'package:lumenpass/features/import/infrastructure/dashlane_parser.dart';
import 'package:lumenpass/features/import/infrastructure/import_parser_service.dart';

/// Resolves the Dashlane export shipped under
/// `testing/Data-Import/Dashlane/` regardless of where the test runner is
/// launched from.
String _dashlaneFixtureDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/testing/Data-Import/Dashlane');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate testing/Data-Import/Dashlane fixtures.');
}

void main() {
  late String fixtureDir;

  setUpAll(() {
    fixtureDir = _dashlaneFixtureDir();
  });

  // ──────────────────────────────────────────────────────────────────────
  //  credentials.csv
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - credentials.csv', () {
    test('parses a minimal credentials row', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'alice@x.test,,,Example,secret,a note,https://x.test,Personal,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.title, 'Example');
      expect(item.username, 'alice@x.test');
      expect(item.password, 'secret');
      expect(item.url, 'https://x.test');
      expect(item.notes, 'a note');
      expect(item.tags, <String>['Personal']);
      expect(item.otpAuthUrl, isNull);
      expect(item.isReady, isTrue);
    });

    test('falls back to username2 / username3 when username is empty', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          ',backup@x.test,,Example,p,,https://x.test,,\n'
          ',,tertiary@x.test,Other,p,,https://y.test,,\n';
      final items = const DashlaneParser().parseCredentialsCsv(csv);
      expect(items[0].username, 'backup@x.test');
      expect(items[1].username, 'tertiary@x.test');
    });

    test('stores extra usernames as custom fields when primary exists', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'alice,bob,carol,Example,p,,https://x.test,,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.username, 'alice');
      final names = item.customFields.map((f) => f.name).toList();
      expect(names, containsAll(<String>['Username 2', 'Username 3']));
    });

    test('extracts fields: block from notes into custom fields', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Example,p,"fields: Account-Key: ABC123\nAccount Key: ABC123",https://x.test,,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      final names = item.customFields.map((f) => f.name).toList();
      expect(names, contains('Account-Key'));
      expect(names, contains('Account Key'));
      expect(item.notes, anyOf(isNull, isEmpty));
    });

    test('extracts Notes: prefixed body and trailing fields block', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Example,p,"Notes: real body text\n\nfields: Foo: Bar",https://x.test,,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.notes, 'real body text');
      expect(
          item.customFields
              .any((f) => f.name == 'Foo' && f.value == 'Bar'),
          isTrue);
    });

    test('skips Dashlane template placeholders like ": password"', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Example,p,"fields: : password",https://x.test,,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.customFields, isEmpty);
    });

    test('strips favorite: / archived: metadata from notes', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Example,p,"favorite: false\narchived: false",https://x.test,,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.notes, isNull);
    });

    test('passes otpauth:// URI through unchanged', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Example,p,,https://x.test,,otpauth://totp/Acct?secret=ABC\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.otpAuthUrl, 'otpauth://totp/Acct?secret=ABC');
    });

    test('wraps a bare Base32 secret into an otpauth:// URI', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,My Site,p,,https://x.test,,JBSWY3DPEHPK3PXP\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.otpAuthUrl,
          'otpauth://totp/My%20Site?secret=JBSWY3DPEHPK3PXP');
    });

    test('takes only the first URI when url is a comma-list', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Site,p,,"https://primary.test,https://alt.test",,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.url, 'https://primary.test');
    });

    test('maps the category column to a tag', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Example,p,,https://x.test,Finance,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.tags, <String>['Finance']);
    });

    test('records an error on rows with no title', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,,p,,https://x.test,,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.isReady, isFalse);
      expect(item.validationErrors, isNotEmpty);
    });

    test('deduplicates identical credential rows', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Dup,p,,https://x.test,,\n'
          'u,,,Dup,p,,https://x.test,,\n'
          'u,,,Other,p,,https://y.test,,\n';
      final items = const DashlaneParser().parseCredentialsCsv(csv);
      expect(items, hasLength(2));
    });

    test('strips C0 control characters from values', () {
      final csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Ex\x07ample,pa\x1Fss,,https://x.test,,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.title, 'Example');
      expect(item.password, 'pass');
    });

    test('skips blank rows', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          ',,,,,,,,\n'
          'u,,,A,p,,https://x.test,,\n';
      final items = const DashlaneParser().parseCredentialsCsv(csv);
      expect(items, hasLength(1));
    });

    test('returns empty list for header-only CSV', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n';
      final items = const DashlaneParser().parseCredentialsCsv(csv);
      expect(items, isEmpty);
    });

    test('rejects empty input', () {
      expect(
        () => const DashlaneParser().parseCredentialsCsv('  '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });

    test('stores source field dashlane_type = credential', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Example,p,,https://x.test,,\n';
      final item = const DashlaneParser().parseCredentialsCsv(csv).single;
      expect(item.getSourceField('dashlane_type'), 'credential');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  securenotes.csv
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - securenotes.csv', () {
    test('parses a simple secure note', () {
      const csv = 'title,note,category\n'
          'My Note,secret stuff,Personal\n';
      final item = const DashlaneParser().parseSecureNotesCsv(csv).single;
      expect(item.title, 'My Note');
      expect(item.notes, 'secret stuff');
      expect(item.tags, <String>['Personal']);
      expect(item.username, isNull);
      expect(item.password, isNull);
    });

    test('extracts fields: block from note', () {
      const csv = 'title,note,category\n'
          'API Key,"fields: Key: sk-abc123\nurl: https://api.test",\n';
      final item = const DashlaneParser().parseSecureNotesCsv(csv).single;
      expect(item.title, 'API Key');
      final keys = item.customFields.map((f) => f.name).toSet();
      expect(keys, contains('Key'));
      expect(keys, contains('url'));
    });

    test('extracts Notes: body followed by fields', () {
      const csv = 'title,note,category\n'
          'DB Creds,"Notes: host.rds.amazonaws.com\n\nPort: 5432\n\nfields: : password\n: note",\n';
      final item = const DashlaneParser().parseSecureNotesCsv(csv).single;
      expect(item.notes, contains('host.rds.amazonaws.com'));
    });

    test('strips favorite:/archived: lines', () {
      const csv = 'title,note,category\n'
          'Note,"favorite: false\narchived: false",\n';
      final item = const DashlaneParser().parseSecureNotesCsv(csv).single;
      expect(item.notes, isNull);
    });

    test('deduplicates identical secure notes', () {
      const csv = 'title,note,category\n'
          'Dup,same text,\n'
          'Dup,same text,\n';
      final items = const DashlaneParser().parseSecureNotesCsv(csv);
      expect(items, hasLength(1));
    });

    test('records an error on rows with no title', () {
      const csv = 'title,note,category\n'
          ',some text,\n';
      final item = const DashlaneParser().parseSecureNotesCsv(csv).single;
      expect(item.isReady, isFalse);
    });

    test('stores source field dashlane_type = securenote', () {
      const csv = 'title,note,category\nNote,text,\n';
      final item = const DashlaneParser().parseSecureNotesCsv(csv).single;
      expect(item.getSourceField('dashlane_type'), 'securenote');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  ids.csv
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - ids.csv', () {
    test('parses an ID document row', () {
      const csv =
          'type,number,name,issue_date,expiration_date,place_of_issue,state\n'
          'passport,X12345,Alice,2020-01-01,2030-01-01,Berlin,\n';
      final item = const DashlaneParser().parseIdsCsv(csv).single;
      expect(item.title, 'Alice');
      final fieldMap = {for (final f in item.customFields) f.name: f};
      expect(fieldMap['Type']!.value, 'passport');
      expect(fieldMap['Number']!.value, 'X12345');
      expect(fieldMap['Number']!.isProtected, isTrue);
      expect(fieldMap['Issue Date']!.value, '2020-01-01');
      expect(fieldMap['Expiration Date']!.value, '2030-01-01');
      expect(fieldMap['Place of Issue']!.value, 'Berlin');
    });

    test('uses type as fallback title when name is missing', () {
      const csv =
          'type,number,name,issue_date,expiration_date,place_of_issue,state\n'
          'driver_license,DL999,,,,California,CA\n';
      final item = const DashlaneParser().parseIdsCsv(csv).single;
      expect(item.title, 'driver_license Document');
    });

    test('returns empty list for header-only ids CSV', () {
      const csv =
          'type,number,name,issue_date,expiration_date,place_of_issue,state\n';
      final items = const DashlaneParser().parseIdsCsv(csv);
      expect(items, isEmpty);
    });

    test('stores source field dashlane_type = id', () {
      const csv =
          'type,number,name,issue_date,expiration_date,place_of_issue,state\n'
          'passport,X1,Alice,,,,\n';
      final item = const DashlaneParser().parseIdsCsv(csv).single;
      expect(item.getSourceField('dashlane_type'), 'id');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  payments.csv
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - payments.csv', () {
    test('parses a credit card payment row', () {
      const csv =
          'type,account_name,account_holder,cc_number,code,expiration_month,expiration_year,routing_number,account_number,country,issuing_bank,note,name\n'
          'credit_card,My Card,Alice,4111111111111111,123,12,2027,,,,Chase,,Visa Card\n';
      final item = const DashlaneParser().parsePaymentsCsv(csv).single;
      expect(item.title, 'Visa Card');
      final fieldMap = {for (final f in item.customFields) f.name: f};
      expect(fieldMap['Card Number']!.value, '4111111111111111');
      expect(fieldMap['Card Number']!.isProtected, isTrue);
      expect(fieldMap['Security Code']!.value, '123');
      expect(fieldMap['Security Code']!.isProtected, isTrue);
      expect(fieldMap['Expiration']!.value, '12/2027');
      expect(fieldMap['Issuing Bank']!.value, 'Chase');
    });

    test('falls back to account_name then type for title', () {
      const csv =
          'type,account_name,account_holder,cc_number,code,expiration_month,expiration_year,routing_number,account_number,country,issuing_bank,note,name\n'
          'bank,Savings,,,,,,12345,67890,,,,\n';
      final item = const DashlaneParser().parsePaymentsCsv(csv).single;
      expect(item.title, 'Savings');
    });

    test('marks routing_number and account_number as protected', () {
      const csv =
          'type,account_name,account_holder,cc_number,code,expiration_month,expiration_year,routing_number,account_number,country,issuing_bank,note,name\n'
          'bank,,,,,,,,67890,,,,\n';
      final item = const DashlaneParser().parsePaymentsCsv(csv).single;
      final fieldMap = {for (final f in item.customFields) f.name: f};
      expect(fieldMap['Account Number']!.isProtected, isTrue);
    });

    test('returns empty list for header-only payments CSV', () {
      const csv =
          'type,account_name,account_holder,cc_number,code,expiration_month,expiration_year,routing_number,account_number,country,issuing_bank,note,name\n';
      final items = const DashlaneParser().parsePaymentsCsv(csv);
      expect(items, isEmpty);
    });

    test('stores source field dashlane_type = payment', () {
      const csv =
          'type,account_name,account_holder,cc_number,code,expiration_month,expiration_year,routing_number,account_number,country,issuing_bank,note,name\n'
          'credit_card,My Card,,4111,,,,,,,,, \n';
      final item = const DashlaneParser().parsePaymentsCsv(csv).single;
      expect(item.getSourceField('dashlane_type'), 'payment');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  personalInfo.csv
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - personalInfo.csv', () {
    test('parses a personal info row and humanizes headers', () {
      const csv =
          'type,title,first_name,middle_name,last_name,login,date_of_birth,place_of_birth,email,email_type,item_name,phone_number,address,country,state,city,zip,address_recipient,address_building,address_apartment,address_floor,address_door_code,job_title,url\n'
          'email,,,,,,,,alice@x.test,personal,Email 1,,,,,,,,,,,,,\n';
      final item = const DashlaneParser().parsePersonalInfoCsv(csv).single;
      expect(item.title, 'Email 1');
      final names = item.customFields.map((f) => f.name).toSet();
      expect(names, contains('Email'));
      expect(names, contains('Email Type'));
    });

    test('uses type + Info as fallback title', () {
      const csv =
          'type,title,first_name,middle_name,last_name,login,date_of_birth,place_of_birth,email,email_type,item_name,phone_number,address,country,state,city,zip,address_recipient,address_building,address_apartment,address_floor,address_door_code,job_title,url\n'
          'identity,Mr,John,,Doe,,,,,,,,,US,,NYC,10001,,,,,Developer,\n';
      final item = const DashlaneParser().parsePersonalInfoCsv(csv).single;
      // title column is "Mr", so it should use that
      expect(item.title, 'Mr');
    });

    test('skips empty-valued columns', () {
      const csv =
          'type,title,first_name,middle_name,last_name,login,date_of_birth,place_of_birth,email,email_type,item_name,phone_number,address,country,state,city,zip,address_recipient,address_building,address_apartment,address_floor,address_door_code,job_title,url\n'
          'email,,,,,,,,alice@x.test,personal,Email 1,,,,,,,,,,,,,\n';
      final item = const DashlaneParser().parsePersonalInfoCsv(csv).single;
      // Only non-empty columns should appear as custom fields
      for (final field in item.customFields) {
        expect(field.value.trim(), isNotEmpty);
      }
    });

    test('returns empty list for header-only personalInfo CSV', () {
      const csv =
          'type,title,first_name,middle_name,last_name,login,date_of_birth,place_of_birth,email,email_type,item_name,phone_number,address,country,state,city,zip,address_recipient,address_building,address_apartment,address_floor,address_door_code,job_title,url\n';
      final items = const DashlaneParser().parsePersonalInfoCsv(csv);
      expect(items, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  Header sniffing (parseCsvSniffed)
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - header sniffing', () {
    test('sniffs credentials header', () {
      const csv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Site,p,,https://x.test,,\n';
      final items = const DashlaneParser().parseCsvSniffed(csv);
      expect(items, hasLength(1));
      expect(items.single.getSourceField('dashlane_type'), 'credential');
    });

    test('sniffs securenotes header', () {
      const csv = 'title,note,category\nMyNote,text,\n';
      final items = const DashlaneParser().parseCsvSniffed(csv);
      expect(items, hasLength(1));
      expect(items.single.getSourceField('dashlane_type'), 'securenote');
    });

    test('sniffs ids header', () {
      const csv =
          'type,number,name,issue_date,expiration_date,place_of_issue,state\n'
          'passport,X1,Alice,,,,\n';
      final items = const DashlaneParser().parseCsvSniffed(csv);
      expect(items, hasLength(1));
      expect(items.single.getSourceField('dashlane_type'), 'id');
    });

    test('sniffs payments header', () {
      const csv =
          'type,account_name,account_holder,cc_number,code,expiration_month,expiration_year,routing_number,account_number,country,issuing_bank,note,name\n'
          'credit_card,My Card,,4111,,,,,,,,, \n';
      final items = const DashlaneParser().parseCsvSniffed(csv);
      expect(items, hasLength(1));
      expect(items.single.getSourceField('dashlane_type'), 'payment');
    });

    test('sniffs personalInfo header', () {
      const csv =
          'type,title,first_name,middle_name,last_name,login,date_of_birth,place_of_birth,email,email_type,item_name,phone_number,address,country,state,city,zip,address_recipient,address_building,address_apartment,address_floor,address_door_code,job_title,url\n'
          'email,,,,,,,,alice@x.test,personal,Email 1,,,,,,,,,,,,,\n';
      final items = const DashlaneParser().parseCsvSniffed(csv);
      expect(items, hasLength(1));
    });

    test('rejects unrecognised header', () {
      const csv = 'foo,bar,baz\n1,2,3\n';
      expect(
        () => const DashlaneParser().parseCsvSniffed(csv),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('does not look like'))),
      );
    });

    test('rejects empty input', () {
      expect(
        () => const DashlaneParser().parseCsvSniffed('  '),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('empty'))),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  ZIP archive handling
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - ZIP archive', () {
    test('parses a ZIP containing credentials and securenotes', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      archive.addFile(ArchiveFile(
        'credentials.csv',
        0,
        ('username,username2,username3,title,password,note,url,category,otpUrl\n'
                'u,,,Site,p,,https://x.test,,\n')
            .codeUnits,
      ));
      archive.addFile(ArchiveFile(
        'securenotes.csv',
        0,
        ('title,note,category\nMy Note,text,\n').codeUnits,
      ));
      final zipBytes = encoder.encode(archive)!;

      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_zip_${DateTime.now().microsecondsSinceEpoch}.zip');
      await tmp.writeAsBytes(zipBytes);
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final items = await const DashlaneParser().parseFile(tmp.path);
      expect(items, hasLength(2));
      final titles = items.map((i) => i.title).toSet();
      expect(titles, containsAll(<String>['Site', 'My Note']));
    });

    test('skips __MACOSX/ entries in a ZIP', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      archive.addFile(ArchiveFile(
        '__MACOSX/._credentials.csv',
        0,
        'junk'.codeUnits,
      ));
      archive.addFile(ArchiveFile(
        'credentials.csv',
        0,
        ('username,username2,username3,title,password,note,url,category,otpUrl\n'
                'u,,,Site,p,,https://x.test,,\n')
            .codeUnits,
      ));
      final zipBytes = encoder.encode(archive)!;

      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_macosx_${DateTime.now().microsecondsSinceEpoch}.zip');
      await tmp.writeAsBytes(zipBytes);
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final items = await const DashlaneParser().parseFile(tmp.path);
      expect(items, hasLength(1));
      expect(items.single.title, 'Site');
    });

    test('deduplicates across CSV files in a ZIP', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      // Put the same credential row in two CSV files
      final credCsv =
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Dup,p,,https://x.test,,\n';
      archive.addFile(
          ArchiveFile('credentials.csv', 0, credCsv.codeUnits));
      // A securenotes file with a note that happens to have same title
      archive.addFile(ArchiveFile(
        'securenotes.csv',
        0,
        ('title,note,category\nDup,some text,\n').codeUnits,
      ));
      final zipBytes = encoder.encode(archive)!;

      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_dedup_${DateTime.now().microsecondsSinceEpoch}.zip');
      await tmp.writeAsBytes(zipBytes);
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final items = await const DashlaneParser().parseFile(tmp.path);
      // The credential and note have different dedup keys (password differs),
      // so both should be kept.
      expect(items, hasLength(2));
    });

    test('rejects a ZIP with no recognised Dashlane CSVs', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      archive.addFile(ArchiveFile('readme.txt', 0, 'hello'.codeUnits));
      final zipBytes = encoder.encode(archive)!;

      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_empty_${DateTime.now().microsecondsSinceEpoch}.zip');
      await tmp.writeAsBytes(zipBytes);
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const DashlaneParser().parseFile(tmp.path),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('does not contain'))),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  parseFile dispatch
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - parseFile dispatch', () {
    test('routes a CSV file by basename when name matches', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/credentials.csv');
      await tmp.writeAsString(
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Site,p,,https://x.test,,\n');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final items = await const DashlaneParser().parseFile(tmp.path);
      expect(items, hasLength(1));
      expect(items.single.title, 'Site');
    });

    test('falls back to header sniffing for non-standard CSV names', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_export_${DateTime.now().microsecondsSinceEpoch}.csv');
      await tmp.writeAsString(
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Sniffed,p,,https://x.test,,\n');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final items = await const DashlaneParser().parseFile(tmp.path);
      expect(items, hasLength(1));
      expect(items.single.title, 'Sniffed');
    });

    test('rejects unsupported file extension', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_bad_ext_${DateTime.now().microsecondsSinceEpoch}.json');
      await tmp.writeAsString('{}');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const DashlaneParser().parseFile(tmp.path),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('Invalid file type'))),
      );
    });

    test('rejects a missing file', () {
      expect(
        () => const DashlaneParser()
            .parseFile('/tmp/dashlane_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.csv'),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('File not found'))),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  Real fixture tests
  // ──────────────────────────────────────────────────────────────────────
  group('DashlaneParser - real fixtures', () {
    test('parses the bundled credentials.csv fixture', () {
      final file = File('$fixtureDir/dashlane-credential-export/credentials.csv');
      if (!file.existsSync()) {
        markTestSkipped('credentials.csv fixture not present');
        return;
      }
      final content = file.readAsStringSync();
      final items = const DashlaneParser().parseCredentialsCsv(content);
      expect(items, isNotEmpty);
      // Every item should have dashlane_type = credential
      for (final item in items) {
        expect(item.getSourceField('dashlane_type'), 'credential');
      }
    });

    test('parses the bundled securenotes.csv fixture', () {
      final file =
          File('$fixtureDir/dashlane-credential-export/securenotes.csv');
      if (!file.existsSync()) {
        markTestSkipped('securenotes.csv fixture not present');
        return;
      }
      final content = file.readAsStringSync();
      final items = const DashlaneParser().parseSecureNotesCsv(content);
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.getSourceField('dashlane_type'), 'securenote');
      }
    });

    test('parses the bundled personalInfo.csv fixture', () {
      final file =
          File('$fixtureDir/dashlane-credential-export/personalInfo.csv');
      if (!file.existsSync()) {
        markTestSkipped('personalInfo.csv fixture not present');
        return;
      }
      final content = file.readAsStringSync();
      final items = const DashlaneParser().parsePersonalInfoCsv(content);
      expect(items, isNotEmpty);
    });

    test('parses the bundled ZIP fixture', () async {
      final file = File('$fixtureDir/dashlane-credential-export.zip');
      if (!file.existsSync()) {
        markTestSkipped('dashlane-credential-export.zip fixture not present');
        return;
      }
      final items = await const DashlaneParser().parseFile(file.path);
      expect(items, isNotEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  //  ImportParserService routing
  // ──────────────────────────────────────────────────────────────────────
  group('ImportParserService - Dashlane routing', () {
    test('routes a Dashlane CSV through the service', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_route_${DateTime.now().microsecondsSinceEpoch}.csv');
      await tmp.writeAsString(
          'username,username2,username3,title,password,note,url,category,otpUrl\n'
          'u,,,Routed,p,,https://x.test,,\n');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final items = await const ImportParserService().parseFile(
        tmp.path,
        provider: ImportProviderType.dashlane,
      );
      expect(items, hasLength(1));
      expect(items.single.title, 'Routed');
    });

    test('routes a Dashlane ZIP through the service', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      archive.addFile(ArchiveFile(
        'credentials.csv',
        0,
        ('username,username2,username3,title,password,note,url,category,otpUrl\n'
                'u,,,ZipRouted,p,,https://x.test,,\n')
            .codeUnits,
      ));
      final zipBytes = encoder.encode(archive)!;

      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_route_${DateTime.now().microsecondsSinceEpoch}.zip');
      await tmp.writeAsBytes(zipBytes);
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      final items = await const ImportParserService().parseFile(
        tmp.path,
        provider: ImportProviderType.dashlane,
      );
      expect(items, hasLength(1));
      expect(items.single.title, 'ZipRouted');
    });

    test('rejects a .json file for the Dashlane provider', () async {
      final tmp = File(
          '${Directory.systemTemp.path}/dashlane_bad_${DateTime.now().microsecondsSinceEpoch}.json');
      await tmp.writeAsString('{}');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync();
      });

      expect(
        () => const ImportParserService()
            .parseFile(tmp.path, provider: ImportProviderType.dashlane),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('Dashlane exports'))),
      );
    });

    test('Dashlane provider advertises .zip and .csv', () {
      expect(
        ImportProviderDefinition.dashlane.acceptedExtensions,
        <String>['.zip', '.csv'],
      );
    });
  });
}
