import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/vault/application/vault_entries_providers.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

void main() {
  test('mobile vault search debounces and applies only latest draft', () async {
    final entries = <KdbxEntry>[
      KdbxEntry(
        uuid: '1',
        groupUuid: 'root',
        title: 'Github',
        username: 'octocat',
        url: 'https://github.com',
      ),
      KdbxEntry(
        uuid: '2',
        groupUuid: 'root',
        title: 'Gitlab',
        username: 'tanuki',
        url: 'https://gitlab.com',
      ),
      KdbxEntry(
        uuid: '3',
        groupUuid: 'root',
        title: 'Zoho',
        username: 'staff',
        url: 'https://zoho.com',
      ),
    ];

    final container = ProviderContainer(
      overrides: <Override>[
        vaultTypeScopedEntriesProvider.overrideWithValue(entries),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(vaultSearchUiStateProvider.notifier);

    controller.setDraft('git');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.setDraft('github');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.setDraft('gitlab');

    expect(container.read(vaultSearchQueryProvider), isEmpty);
    expect(container.read(vaultSearchLoadingProvider), isFalse);
    expect(container.read(vaultSearchDraftProvider), 'gitlab');

    await Future<void>.delayed(
      kVaultSearchDebounce +
          kVaultSearchLoadingMinVisible +
          const Duration(milliseconds: 10),
    );

    expect(container.read(vaultSearchQueryProvider), 'gitlab');
    expect(container.read(vaultSearchLoadingProvider), isFalse);
    expect(container.read(vaultSearchFilteredEntriesProvider), hasLength(1));
    expect(
      container.read(vaultSearchFilteredEntriesProvider).single.title,
      'Gitlab',
    );
  });

  test('mobile vault search clear resets draft query and loading', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        vaultTypeScopedEntriesProvider.overrideWithValue(<KdbxEntry>[
          KdbxEntry(
            uuid: '1',
            groupUuid: 'root',
            title: 'Github',
            username: 'octocat',
          ),
        ]),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(vaultSearchUiStateProvider.notifier);

    controller.setDraft('github');
    await Future<void>.delayed(
      kVaultSearchDebounce +
          kVaultSearchLoadingMinVisible +
          const Duration(milliseconds: 10),
    );
    expect(container.read(vaultSearchQueryProvider), 'github');
    expect(container.read(vaultSearchFilteredEntriesProvider), hasLength(1));

    controller.clear();

    expect(container.read(vaultSearchDraftProvider), isEmpty);
    expect(container.read(vaultSearchQueryProvider), isEmpty);
    expect(container.read(vaultSearchLoadingProvider), isFalse);
  });
}
