import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/vault/presentation/vault_empty_state_copy.dart';

void main() {
  test('only a genuinely empty unfiltered vault invites first item', () {
    final empty = vaultEmptyStateCopy(totalItemCount: 0);
    expect(empty.title, 'Your vault is empty');
    expect(empty.showSuggestions, isTrue);

    final passkeys = vaultEmptyStateCopy(
      totalItemCount: 6,
      itemTypeId: 'quick_passkeys',
    );
    expect(passkeys.title, 'No passkeys');
    expect(passkeys.showSuggestions, isFalse);

    final category = vaultEmptyStateCopy(
      totalItemCount: 6,
      groupId: 'some-category-id',
    );
    expect(category.title, 'No items in this category');
  });

  test('empty trash and duplicate results do not claim the vault is empty', () {
    expect(
      vaultEmptyStateCopy(totalItemCount: 6, groupId: 'group_trash').title,
      'Trash is empty',
    );
    expect(
      vaultEmptyStateCopy(
        totalItemCount: 6,
        itemTypeId: 'quick_password_audits',
        passwordAuditIssue: 'duplicated',
      ).title,
      'No duplicate items',
    );
  });
}
