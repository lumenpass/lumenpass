import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/import/infrastructure/cxf_parser.dart';

void main() {
  const parser = CxfParser();

  // Helper that wraps a raw value into the CXF EditableField shape Apple emits.
  Map<String, dynamic> field(String value, {bool concealed = false}) => {
        'id': '',
        'label': '',
        'fieldType': concealed ? 'concealed-string' : 'string',
        'value': value,
      };

  test('parses a basic-auth credential with EditableField values', () {
    final payload = jsonEncode({
      'exporterDisplayName': '1Password',
      'formatVersion': '1.0',
      'accounts': [
        {
          'id': 'a1',
          'items': [
            {
              'id': 'i1',
              'title': 'GitHub',
              'subtitle': 'octocat',
              'scope': {
                'urls': ['https://github.com/login'],
                'androidApps': [],
              },
              'credentials': [
                {
                  'type': 'basic-auth',
                  'username': field('octocat'),
                  'password': field('hunter2', concealed: true),
                },
              ],
            },
          ],
        },
      ],
    });

    final result = parser.parse(payload);

    expect(result.exporterName, '1Password');
    expect(result.totalAccounts, 1);
    expect(result.items, hasLength(1));

    final item = result.items.single;
    expect(item.title, 'GitHub');
    expect(item.username, 'octocat');
    expect(item.password, 'hunter2');
    expect(item.url, 'https://github.com/login');
  });

  test('combines a basic-auth credential with a totp credential', () {
    final payload = jsonEncode({
      'exporterDisplayName': 'Apple Passwords',
      'formatVersion': '1.0',
      'accounts': [
        {
          'id': 'a1',
          'items': [
            {
              'id': 'i1',
              'title': 'Acme',
              'scope': {
                'urls': ['https://acme.example'],
              },
              'credentials': [
                {
                  'type': 'basic-auth',
                  'username': field('alice'),
                  'password': field('p@ss', concealed: true),
                },
                {
                  'type': 'totp',
                  'secret': 'JBSWY3DPEHPK3PXP',
                  'period': 30,
                  'digits': 6,
                  'algorithm': 'sha1',
                  'issuer': 'Acme',
                  'username': 'alice',
                },
              ],
            },
          ],
        },
      ],
    });

    final item = parser.parse(payload).items.single;
    expect(item.username, 'alice');
    expect(item.password, 'p@ss');
    expect(item.otpAuthUrl, startsWith('otpauth://totp/'));
    expect(item.otpAuthUrl, contains('JBSWY3DPEHPK3PXP'));
    expect(item.otpAuthUrl, contains('issuer=Acme'));
  });

  test('extracts a note credential into the notes field', () {
    final payload = jsonEncode({
      'exporterDisplayName': '1Password',
      'formatVersion': '1.0',
      'accounts': [
        {
          'id': 'a1',
          'items': [
            {
              'id': 'i1',
              'title': 'Wifi Cafe Louis',
              'credentials': [
                {
                  'type': 'note',
                  'content': field('favorite: false\narchived: false'),
                },
              ],
            },
          ],
        },
      ],
    });

    final item = parser.parse(payload).items.single;
    expect(item.title, 'Wifi Cafe Louis');
    expect(item.notes, 'favorite: false\narchived: false');
  });

  test('parses items under collections and inherits the collection tag', () {
    final payload = jsonEncode({
      'exporterDisplayName': '1Password',
      'formatVersion': '1.0',
      'accounts': [
        {
          'id': 'a1',
          'collections': [
            {
              'id': 'c1',
              'title': 'Work',
              'items': [
                {
                  'id': 'i1',
                  'title': 'Jira',
                  'credentials': [
                    {
                      'type': 'basic-auth',
                      'username': field('alice@corp.com'),
                      'password': field('p@ss', concealed: true),
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    });

    final item = parser.parse(payload).items.single;
    expect(item.title, 'Jira');
    expect(item.tags, contains('Work'));
  });

  test('exposes item-level tags from the imported payload', () {
    final payload = jsonEncode({
      'accounts': [
        {
          'items': [
            {
              'title': 'Tagged',
              'tags': ['Imported October 8 2024'],
              'credentials': [
                {
                  'type': 'basic-auth',
                  'username': field('u'),
                  'password': field('p', concealed: true),
                },
              ],
            },
          ],
        },
      ],
    });

    final item = parser.parse(payload).items.single;
    expect(item.tags, contains('Imported October 8 2024'));
  });

  test('extracts passkey custom fields', () {
    final payload = jsonEncode({
      'exporterDisplayName': '1Password',
      'formatVersion': '1.0',
      'accounts': [
        {
          'items': [
            {
              'title': 'Example Passkey',
              'credentials': [
                {
                  'type': 'passkey',
                  'credentialId': 'CRED_ID_B64URL',
                  'rpId': 'example.com',
                  'userHandle': 'USER_HANDLE_B64URL',
                  'key': '-----BEGIN PRIVATE KEY-----...',
                  'userName': 'jdoe',
                },
              ],
            },
          ],
        },
      ],
    });

    final item = parser.parse(payload).items.single;
    final names = item.customFields.map((f) => f.name).toList();
    expect(names, contains('KPEX_PASSKEY_CREDENTIAL_ID'));
    expect(names, contains('KPEX_PASSKEY_RELYING_PARTY'));
    expect(names, contains('KPEX_PASSKEY_USER_HANDLE'));
    expect(names, contains('KPEX_PASSKEY_PRIVATE_KEY_PEM'));
    expect(names, contains('KPEX_PASSKEY_USERNAME'));

    final pk = item.customFields
        .firstWhere((f) => f.name == 'KPEX_PASSKEY_PRIVATE_KEY_PEM');
    expect(pk.isProtected, isTrue);
  });

  test('returns empty result for empty accounts list', () {
    final payload = jsonEncode({
      'exporterDisplayName': 'X',
      'formatVersion': '1.0',
      'accounts': [],
    });

    final result = parser.parse(payload);
    expect(result.items, isEmpty);
    expect(result.totalAccounts, 0);
  });

  test('throws FormatException on invalid JSON', () {
    expect(
      () => parser.parse('not json'),
      throwsA(isA<FormatException>()),
    );
  });

  test('toEntryFields produces the standard KDBX field set', () {
    final payload = jsonEncode({
      'accounts': [
        {
          'items': [
            {
              'title': 'Stripe',
              'scope': {
                'urls': ['https://dashboard.stripe.com'],
              },
              'credentials': [
                {
                  'type': 'basic-auth',
                  'username': field('admin@acme.io'),
                  'password': field('sk_live_xxx', concealed: true),
                },
              ],
            },
          ],
        },
      ],
    });

    final item = parser.parse(payload).items.single;
    final fields = item.toEntryFields();
    final keys = fields.map((f) => f.key).toList();

    expect(keys, contains('Title'));
    expect(keys, contains('UserName'));
    expect(keys, contains('Password'));
    expect(keys, contains('URL'));

    final pw = fields.firstWhere((f) => f.key == 'Password');
    expect(pw.isProtected, isTrue);
  });
}
