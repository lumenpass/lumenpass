import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:test/test.dart';

KdbxEntry _entry({
  String title = 'Untitled',
  String? username,
  String? url,
  List<EntryField> fields = const <EntryField>[],
}) {
  return KdbxEntry(
    uuid: 'entry-1',
    groupUuid: 'group-1',
    title: title,
    username: username,
    url: url,
    fields: fields,
  );
}

void main() {
  group('classifyVaultItemType', () {
    test('classifies LumenPass identity entries even when UserName is set', () {
      final entry = _entry(
        title: 'Identity',
        username: 'Tran V Tuan',
        fields: const <EntryField>[
          EntryField(key: AppKdbxFieldKeys.title, value: 'Identity'),
          EntryField(key: AppKdbxFieldKeys.userName, value: 'Tran V Tuan'),
          EntryField(key: 'Full Name', value: 'Tran V Tuan'),
          EntryField(key: 'First Name', value: 'Tran'),
          EntryField(key: 'Initial', value: 'V'),
          EntryField(key: 'Last Name', value: 'Tuan'),
        ],
      );

      expect(classifyVaultItemType(entry), VaultItemType.identity);
    });

    test('keeps logins with profile-style custom fields as logins', () {
      final entry = _entry(
        title: 'Example Login',
        username: 'reviewer@example.com',
        url: 'https://example.com/login',
        fields: const <EntryField>[
          EntryField(key: AppKdbxFieldKeys.title, value: 'Example Login'),
          EntryField(
            key: AppKdbxFieldKeys.userName,
            value: 'reviewer@example.com',
          ),
          EntryField(key: AppKdbxFieldKeys.url, value: 'https://example.com'),
          EntryField(key: 'First Name', value: 'Reviewer'),
          EntryField(key: 'Phone', value: '+1 555 0100'),
        ],
      );

      expect(classifyVaultItemType(entry), VaultItemType.login);
    });

    test('does not treat phone-only custom fields as identity before login',
        () {
      final entry = _entry(
        title: 'Account',
        username: 'reviewer',
        fields: const <EntryField>[
          EntryField(key: AppKdbxFieldKeys.title, value: 'Account'),
          EntryField(key: AppKdbxFieldKeys.userName, value: 'reviewer'),
          EntryField(key: 'Phone', value: '+1 555 0100'),
        ],
      );

      expect(classifyVaultItemType(entry), VaultItemType.login);
    });
  });
}
