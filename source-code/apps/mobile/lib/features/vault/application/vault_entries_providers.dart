import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/repository/providers.dart';

/// Shared with home and items tab (desktop vault search scope).
final vaultSearchQueryProvider = StateProvider<String>((ref) => '');
const Duration kVaultSearchDebounce = Duration(milliseconds: 1000);
const Duration kVaultSearchLoadingFrame = Duration(milliseconds: 16);
const Duration kVaultSearchLoadingMinVisible = Duration(milliseconds: 250);

class VaultSearchUiState {
  const VaultSearchUiState({this.draft = '', this.isLoading = false});

  final String draft;
  final bool isLoading;

  VaultSearchUiState copyWith({String? draft, bool? isLoading}) {
    return VaultSearchUiState(
      draft: draft ?? this.draft,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final vaultSearchUiStateProvider =
    NotifierProvider<_VaultSearchController, VaultSearchUiState>(
      _VaultSearchController.new,
    );

final vaultSearchDraftProvider = Provider<String>((ref) {
  return ref.watch(vaultSearchUiStateProvider).draft;
});

final vaultSearchLoadingProvider = Provider<bool>((ref) {
  return ref.watch(vaultSearchUiStateProvider).isLoading;
});

class _VaultSearchController extends Notifier<VaultSearchUiState> {
  Timer? _debounceTimer;
  int _searchSeq = 0;

  @override
  VaultSearchUiState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
      _debounceTimer = null;
    });

    return VaultSearchUiState(draft: ref.read(vaultSearchQueryProvider));
  }

  void setDraft(String value) {
    _debounceTimer?.cancel();
    _searchSeq++;

    if (value.trim().isEmpty) {
      ref.read(vaultSearchQueryProvider.notifier).state = '';
      state = const VaultSearchUiState();
      return;
    }

    state = state.copyWith(draft: value, isLoading: false);

    final mySeq = _searchSeq;
    _debounceTimer = Timer(kVaultSearchDebounce, () {
      unawaited(_applyQuery(value, mySeq));
    });
  }

  void clear() {
    _debounceTimer?.cancel();
    _searchSeq++;
    ref.read(vaultSearchQueryProvider.notifier).state = '';
    state = const VaultSearchUiState();
  }

  Future<void> _applyQuery(String value, int seq) async {
    if (seq != _searchSeq) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    state = state.copyWith(draft: value, isLoading: true);
    await Future<void>.delayed(kVaultSearchLoadingFrame);
    if (seq != _searchSeq) {
      return;
    }

    ref.read(vaultSearchQueryProvider.notifier).state = value;

    final remaining = kVaultSearchLoadingMinVisible - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (seq != _searchSeq) {
      return;
    }

    state = state.copyWith(isLoading: false);
  }
}

/// Same virtual IDs as desktop [vault_providers] category sidebar.
const String kCategoryFilterAll = 'category_all';
const String kCategoryFilterUncategorized = 'category_uncategorized';
const String kItemTypeFilterAll = 'item_type_all';

/// Selected KeePass group (folder) for list filtering: [kCategoryFilterAll],
/// [kCategoryFilterUncategorized], or a real group UUID.
final vaultSelectedGroupProvider = StateProvider<String>(
  (ref) => kCategoryFilterAll,
);

/// Selected item-type filter for list scoping.
final vaultSelectedItemTypeFilterProvider = StateProvider<String>(
  (ref) => kItemTypeFilterAll,
);

/// Shared with home and items tab (desktop vault search scope).
final vaultVisibleEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final db = ref.watch(activeDatabaseProvider);
  if (db == null) {
    return const <KdbxEntry>[];
  }
  return db.rootGroup.subtreeEntriesExcludingRecycleBin().toList(
    growable: false,
  );
});

/// Top-level groups under the vault root (desktop “Categories”), with entry counts.
final vaultSidebarCategoriesProvider =
    Provider<List<({String uuid, String name, String notes, int count})>>((
      ref,
    ) {
      final db = ref.watch(activeDatabaseProvider);
      if (db == null) {
        return const <({String uuid, String name, String notes, int count})>[];
      }

      return db.rootGroup.groups
          .where((group) => !group.isRecycleBin)
          .map(
            (group) => (
              uuid: group.uuid,
              name: group.name,
              notes: group.notes,
              count: group.subtreeEntriesExcludingRecycleBin().length,
            ),
          )
          .toList(growable: false);
    });

final vaultUncategorizedCountProvider = Provider<int>((ref) {
  final db = ref.watch(activeDatabaseProvider);
  if (db == null) {
    return 0;
  }
  final rootUuid = db.rootGroup.uuid;
  return ref
      .watch(vaultVisibleEntriesProvider)
      .where((entry) => entry.groupUuid == rootUuid)
      .length;
});

/// Entries visible in the main vault list after category (group) selection.
final vaultCategoryScopedEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final db = ref.watch(activeDatabaseProvider);
  if (db == null) {
    return const <KdbxEntry>[];
  }

  final all = ref.watch(vaultVisibleEntriesProvider);
  final selected = ref.watch(vaultSelectedGroupProvider);

  if (selected == kCategoryFilterAll) {
    return all;
  }

  if (selected == kCategoryFilterUncategorized) {
    final rootUuid = db.rootGroup.uuid;
    return all
        .where((entry) => entry.groupUuid == rootUuid)
        .toList(growable: false);
  }

  final selectedGroup = _findGroupByUuid(db.rootGroup, selected);
  if (selectedGroup == null) {
    return all;
  }

  final allowedGroupUuids = selectedGroup
      .flattenedGroups()
      .map((group) => group.uuid)
      .toSet();

  return all
      .where((entry) => allowedGroupUuids.contains(entry.groupUuid))
      .toList(growable: false);
});

/// Entries visible after category + item-type filtering.
final vaultTypeScopedEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final entries = ref.watch(vaultCategoryScopedEntriesProvider);
  final selected = ref.watch(vaultSelectedItemTypeFilterProvider);
  if (selected == kItemTypeFilterAll) return entries;

  return entries
      .where((entry) {
        final type = classifyVaultItemType(entry);
        return switch (selected) {
          'login' => type == VaultItemType.login,
          'secure-note' => type == VaultItemType.secureNote,
          'credit-card' => type == VaultItemType.creditCard,
          'identity' => type == VaultItemType.identity,
          'ssh-key' => type == VaultItemType.sshKey,
          'bank-account' => type == VaultItemType.bankAccount,
          _ => true,
        };
      })
      .toList(growable: false);
});

/// Item type counts within current category scope.
final vaultItemTypeCountsProvider = Provider<Map<String, int>>((ref) {
  final entries = ref.watch(vaultCategoryScopedEntriesProvider);
  final counts = <String, int>{
    'login': 0,
    'secure-note': 0,
    'credit-card': 0,
    'identity': 0,
    'ssh-key': 0,
    'bank-account': 0,
  };
  for (final entry in entries) {
    final type = classifyVaultItemType(entry);
    switch (type) {
      case VaultItemType.login:
        counts['login'] = counts['login']! + 1;
        break;
      case VaultItemType.secureNote:
        counts['secure-note'] = counts['secure-note']! + 1;
        break;
      case VaultItemType.creditCard:
        counts['credit-card'] = counts['credit-card']! + 1;
        break;
      case VaultItemType.identity:
        counts['identity'] = counts['identity']! + 1;
        break;
      case VaultItemType.sshKey:
        counts['ssh-key'] = counts['ssh-key']! + 1;
        break;
      case VaultItemType.bankAccount:
        counts['bank-account'] = counts['bank-account']! + 1;
        break;
      default:
        break;
    }
  }
  return counts;
});

final vaultSearchFilteredEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final entries = ref.watch(vaultTypeScopedEntriesProvider);
  final query = ref.watch(vaultSearchQueryProvider);
  if (_normalizedSearchTerms(query).isNotEmpty) {
    return entries
        .where((e) => _matchesVaultSearch(e, query))
        .toList(growable: false);
  }
  return entries;
});

List<String> _normalizedSearchTerms(String query) {
  return query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
}

bool _matchesVaultSearch(KdbxEntry entry, String query) {
  final terms = _normalizedSearchTerms(query);
  if (terms.isEmpty) {
    return true;
  }
  final haystack = _searchableTextForEntry(entry);
  return terms.every(haystack.contains);
}

String _searchableTextForEntry(KdbxEntry entry) {
  final values = <String>[
    entry.title,
    entry.username ?? '',
    entry.url ?? '',
    entry.notes ?? '',
    entry.otpAuthUrl ?? '',
    ...entry.tags,
    ...entry.fields
        .where(
          (field) =>
              !field.isProtected &&
              !AppKdbxFieldKeys.isProtectedKey(field.key),
        )
        .map((field) => field.value),
  ];
  return values
      .where((value) => value.trim().isNotEmpty)
      .join(' ')
      .toLowerCase();
}

/// All unique tags across the vault, sorted by frequency then alphabetically.
final vaultAllTagsProvider = Provider<List<String>>((ref) {
  final entries = ref.watch(vaultVisibleEntriesProvider);
  final counts = <String, int>{};
  for (final entry in entries) {
    for (final tag in entry.tags) {
      final normalized = tag.trim();
      if (normalized.isEmpty) continue;
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
  }
  final tags = counts.keys.toList(growable: false);
  tags.sort((a, b) {
    final byCount = counts[b]!.compareTo(counts[a]!);
    if (byCount != 0) return byCount;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return tags;
});

KdbxGroup? _findGroupByUuid(KdbxGroup group, String uuid) {
  if (group.uuid == uuid) {
    return group;
  }
  for (final child in group.groups) {
    final match = _findGroupByUuid(child, uuid);
    if (match != null) {
      return match;
    }
  }
  return null;
}
