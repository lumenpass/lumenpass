import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass/core/models/kdbx_entry.dart';
import 'package:lumenpass/features/vault/application/vault_providers.dart';

void main() {
  test(
      'search suggestions stay empty during rapid typing and resolve after debounce',
      () async {
    final entries = List<KdbxEntry>.generate(
      1500,
      (index) => KdbxEntry(
        uuid: 'entry-$index',
        groupUuid: 'root',
        title: 'Santa Fe Edu Account $index',
        username: 'user$index@example.com',
        url: 'https://example$index.test',
        notes: 'Performance search fixture $index',
        updatedAt: DateTime(2026, 1, 1).add(Duration(minutes: index)),
      ),
    );

    final container = ProviderContainer(
      overrides: <Override>[
        vaultScopedEntriesProvider.overrideWithValue(entries),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(vaultSearchSuggestionsProvider), isEmpty);

    const rapidInputs = <String>[
      's',
      'sa',
      'san',
      'sant',
      'santa',
      'santa ',
      'santa f',
      'santa fe',
    ];

    for (final input in rapidInputs) {
      container.read(vaultSearchDraftProvider.notifier).state = input;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(vaultSearchSuggestionsProvider), isEmpty);
      expect(container.read(vaultSearchSuggestionsLoadingProvider), isFalse);
    }

    await Future<void>.delayed(
      kVaultSearchDebounce +
          kVaultSearchLoadingMinVisible +
          const Duration(milliseconds: 10),
    );

    final suggestions = container.read(vaultSearchSuggestionsProvider);
    expect(suggestions, hasLength(kVaultSearchSuggestionLimit));
    expect(
        suggestions.every((entry) => entry.title.contains('Santa Fe')), isTrue);
    expect(container.read(vaultSearchSuggestionsLoadingProvider), isFalse);
  });

  test('suggestions cover empty, single, and maximum result counts', () async {
    final entries = List<KdbxEntry>.generate(
      12,
      (index) => KdbxEntry(
        uuid: 'entry-$index',
        groupUuid: 'root',
        title: index == 0 ? 'Solo Match' : 'Zoho Account $index',
        username: index == 0 ? 'solo@example.com' : 'zoho$index@example.com',
      ),
    );

    final container = ProviderContainer(
      overrides: <Override>[
        vaultScopedEntriesProvider.overrideWithValue(entries),
      ],
    );
    addTearDown(container.dispose);
    container.read(vaultSearchSuggestionsProvider);

    container.read(vaultSearchDraftProvider.notifier).state = 'missing';
    await Future<void>.delayed(
      kVaultSearchDebounce +
          kVaultSearchLoadingMinVisible +
          const Duration(milliseconds: 10),
    );
    expect(container.read(vaultSearchSuggestionsProvider), isEmpty);

    container.read(vaultSearchDraftProvider.notifier).state = 'solo';
    await Future<void>.delayed(
      kVaultSearchDebounce +
          kVaultSearchLoadingMinVisible +
          const Duration(milliseconds: 10),
    );
    expect(container.read(vaultSearchSuggestionsProvider), hasLength(1));

    container.read(vaultSearchDraftProvider.notifier).state = 'zoho';
    await Future<void>.delayed(
      kVaultSearchDebounce +
          kVaultSearchLoadingMinVisible +
          const Duration(milliseconds: 10),
    );
    expect(
      container.read(vaultSearchSuggestionsProvider),
      hasLength(kVaultSearchSuggestionLimit),
    );
  });

  test('clearing search draft immediately clears debounced suggestions',
      () async {
    final container = ProviderContainer(
      overrides: <Override>[
        vaultScopedEntriesProvider.overrideWithValue(<KdbxEntry>[
          KdbxEntry(
            uuid: 'entry-1',
            groupUuid: 'root',
            title: 'Santa Fe Edu Account',
            username: 'santa@example.com',
          ),
        ]),
      ],
    );
    addTearDown(container.dispose);
    container.read(vaultSearchSuggestionsProvider);

    container.read(vaultSearchDraftProvider.notifier).state = 'santa';
    await Future<void>.delayed(
      kVaultSearchDebounce +
          kVaultSearchLoadingMinVisible +
          const Duration(milliseconds: 10),
    );
    expect(container.read(vaultSearchSuggestionsProvider), hasLength(1));

    container.read(vaultSearchDraftProvider.notifier).state = '';
    expect(container.read(vaultSearchSuggestionsProvider), isEmpty);
    expect(container.read(vaultSearchSuggestionsLoadingProvider), isFalse);
  });
}
