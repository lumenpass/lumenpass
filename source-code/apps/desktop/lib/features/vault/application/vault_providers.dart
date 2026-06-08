import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/entry_field.dart';
import '../../../core/models/kdbx_entry.dart';
import '../../../core/constants/kdbx_field_keys.dart';
import '../../../core/models/kdbx_group.dart';
import '../../../core/repository/kdbx_repository_provider.dart';
import 'vault_item_type.dart';
import 'vault_search_ranking.dart';

final vaultSearchQueryProvider = StateProvider<String>((ref) => '');
final vaultSearchDraftProvider = StateProvider<String>((ref) => '');

final vaultRefreshTriggerProvider = StateProvider<int>((ref) => 0);

const Duration kVaultSearchDebounce = Duration(milliseconds: 1000);
const Duration kVaultSearchLoadingFrame = Duration(milliseconds: 16);
const Duration kVaultSearchLoadingMinVisible = Duration(milliseconds: 250);
const int kVaultSearchSuggestionLimit = 6;

class VaultSearchSuggestionsState {
  const VaultSearchSuggestionsState({
    this.query = '',
    this.suggestions = const <KdbxEntry>[],
    this.isLoading = false,
  });

  final String query;
  final List<KdbxEntry> suggestions;
  final bool isLoading;

  VaultSearchSuggestionsState copyWith({
    String? query,
    List<KdbxEntry>? suggestions,
    bool? isLoading,
  }) {
    return VaultSearchSuggestionsState(
      query: query ?? this.query,
      suggestions: suggestions ?? this.suggestions,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final vaultSearchSuggestionsStateProvider = NotifierProvider<
    _VaultSearchSuggestionsController,
    VaultSearchSuggestionsState>(_VaultSearchSuggestionsController.new);

class _VaultSearchSuggestionsController
    extends Notifier<VaultSearchSuggestionsState> {
  Timer? _timer;
  int _searchSeq = 0;

  @override
  VaultSearchSuggestionsState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    ref.listen<String>(
      vaultSearchDraftProvider,
      (_, next) {
        _queueSearch(next);
      },
    );

    ref.listen<List<KdbxEntry>>(
      vaultScopedEntriesProvider,
      (_, __) {
        final query = state.query.trim();
        if (query.isEmpty || state.isLoading) {
          return;
        }
        state = state.copyWith(
          suggestions: _computeSuggestions(query),
        );
      },
    );

    final initialDraft = ref.read(vaultSearchDraftProvider);
    if (initialDraft.trim().isNotEmpty) {
      _queueSearch(initialDraft);
    }

    return const VaultSearchSuggestionsState();
  }

  void cancelPendingSearch({bool clearResults = false}) {
    _timer?.cancel();
    _searchSeq++;
    if (clearResults) {
      state = const VaultSearchSuggestionsState();
    }
  }

  void _queueSearch(String rawQuery) {
    final query = rawQuery.trim();
    _timer?.cancel();
    _searchSeq++;

    if (query.isEmpty) {
      state = const VaultSearchSuggestionsState();
      return;
    }

    final mySeq = _searchSeq;
    _timer = Timer(kVaultSearchDebounce, () {
      unawaited(_runSearch(query, mySeq));
    });
  }

  Future<void> _runSearch(String query, int seq) async {
    if (seq != _searchSeq) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    state = state.copyWith(isLoading: true);
    await Future<void>.delayed(kVaultSearchLoadingFrame);
    if (seq != _searchSeq) {
      return;
    }

    try {
      final suggestions = _computeSuggestions(query);
      final remaining = kVaultSearchLoadingMinVisible - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (seq != _searchSeq) {
        return;
      }
      state = VaultSearchSuggestionsState(
        query: query,
        suggestions: suggestions,
        isLoading: false,
      );
    } catch (_) {
      if (seq != _searchSeq) {
        return;
      }
      state = state.copyWith(isLoading: false);
    }
  }

  List<KdbxEntry> _computeSuggestions(String query) {
    final entries = ref.read(vaultScopedEntriesProvider);
    return topRankedSearchResults<KdbxEntry>(
      entries: entries,
      query: query,
      viewOf: kdbxEntrySearchView,
      titleOf: (e) => e.title,
      limit: kVaultSearchSuggestionLimit,
    );
  }
}

final vaultSelectedGroupProvider = StateProvider<String?>((ref) => null);
final vaultSelectedItemTypeIdProvider = StateProvider<String?>((ref) => null);
final vaultPasswordAuditSelectionProvider =
    StateProvider<PasswordAuditIssue?>((ref) => null);
final vaultPasswordAuditDuplicateGroupSelectionProvider =
    StateProvider<String?>((ref) => null);
final vaultSelectedTagProvider = StateProvider<String?>((ref) => null);

// Virtual filter IDs for Quick Access (not part of VaultItemType enum)
const String kQuickFilterTotp = 'quick_totp';
const String kQuickFilterPasskeys = 'quick_passkeys';
const String kCategoryFilterAll = 'category_all';
const String kCategoryFilterUncategorized = 'category_uncategorized';
const String kGroupFilterTrash = 'group_trash';

final vaultTotpCountProvider = Provider<int>((ref) {
  final entries = ref.watch(vaultDatabaseEntriesProvider);
  return entries
      .where((e) => e.otpAuthUrl != null && e.otpAuthUrl!.isNotEmpty)
      .length;
});

final vaultPasskeyCountProvider = Provider<int>((ref) {
  final entries = ref.watch(vaultDatabaseEntriesProvider);
  return entries
      .where(
        (e) => e.fields.any((f) => f.key.toLowerCase().contains('passkey')),
      )
      .length;
});

final vaultDatabaseEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final activeDatabase = ref.watch(activeDatabaseProvider);
  if (activeDatabase == null) {
    return const <KdbxEntry>[];
  }

  return _visibleEntriesForGroup(activeDatabase.rootGroup)
      .toList(growable: false);
});

final vaultSidebarItemCountsProvider = Provider<Map<String, int>>((ref) {
  final entries = ref.watch(vaultDatabaseEntriesProvider);
  final counts = <String, int>{
    for (final type in VaultItemType.values) type.id: 0,
  };

  for (final entry in entries) {
    final type = classifyVaultItemType(entry);
    counts[type.id] = (counts[type.id] ?? 0) + 1;
  }

  return Map<String, int>.unmodifiable(counts);
});

final vaultSidebarCategoriesProvider =
    Provider<List<({String uuid, String name, String notes, int count})>>(
        (ref) {
  final activeDatabase = ref.watch(activeDatabaseProvider);
  if (activeDatabase == null) {
    return const <({String uuid, String name, String notes, int count})>[];
  }

  return activeDatabase.rootGroup.groups
      .where((group) => !group.isRecycleBin)
      .map(
        (group) => (
          uuid: group.uuid,
          name: group.name,
          notes: group.notes,
          count: _visibleEntriesForGroup(group).length,
        ),
      )
      .toList(growable: false);
});

final vaultSidebarTagsProvider =
    Provider<List<({String tag, int count})>>((ref) {
  final entries = ref.watch(vaultDatabaseEntriesProvider);
  final counts = <String, int>{};

  for (final entry in entries) {
    for (final tag in entry.tags) {
      final normalized = tag.trim();
      if (normalized.isEmpty) {
        continue;
      }
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
  }

  final tags = counts.entries
      .map((entry) => (tag: entry.key, count: entry.value))
      .toList(growable: false);
  tags.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) {
      return byCount;
    }
    return a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
  });
  return tags;
});

final vaultUncategorizedCountProvider = Provider<int>((ref) {
  final activeDatabase = ref.watch(activeDatabaseProvider);
  if (activeDatabase == null) {
    return 0;
  }
  final rootUuid = activeDatabase.rootGroup.uuid;
  return ref
      .watch(vaultDatabaseEntriesProvider)
      .where((e) => e.groupUuid == rootUuid)
      .length;
});

final vaultTrashEntryCountProvider = Provider<int>((ref) {
  final activeDatabase = ref.watch(activeDatabaseProvider);
  if (activeDatabase == null) {
    return 0;
  }

  return _recycleBinEntryCount(activeDatabase.rootGroup);
});

final vaultScopedEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final activeDatabase = ref.watch(activeDatabaseProvider);
  if (activeDatabase == null) {
    return const <KdbxEntry>[];
  }

  final selectedGroupUuid = ref.watch(vaultSelectedGroupProvider);
  final selectedItemTypeId = ref.watch(vaultSelectedItemTypeIdProvider);
  final selectedTag = ref.watch(vaultSelectedTagProvider);
  var filteredEntries = ref.watch(vaultDatabaseEntriesProvider);

  if (selectedGroupUuid == kGroupFilterTrash) {
    return _trashEntriesForGroup(activeDatabase.rootGroup)
        .toList(growable: false);
  }

  if (selectedGroupUuid != null && selectedGroupUuid != kCategoryFilterAll) {
    if (selectedGroupUuid == kCategoryFilterUncategorized) {
      final rootUuid = activeDatabase.rootGroup.uuid;
      filteredEntries = filteredEntries
          .where((entry) => entry.groupUuid == rootUuid)
          .toList(growable: false);
    } else {
      final selectedGroup =
          _findGroupByUuid(activeDatabase.rootGroup, selectedGroupUuid);
      if (selectedGroup != null) {
        final allowedGroupUuids =
            selectedGroup.flattenedGroups().map((group) => group.uuid).toSet();

        filteredEntries = filteredEntries
            .where((entry) => allowedGroupUuids.contains(entry.groupUuid))
            .toList(growable: false);
      }
    }
  }

  if (selectedTag != null) {
    filteredEntries = filteredEntries
        .where((entry) => entry.tags.contains(selectedTag))
        .toList(growable: false);
  }

  // Quick Access virtual filters
  if (selectedItemTypeId == kQuickFilterTotp) {
    return filteredEntries
        .where((e) => e.otpAuthUrl != null && e.otpAuthUrl!.isNotEmpty)
        .toList(growable: false);
  }
  if (selectedItemTypeId == kQuickFilterPasskeys) {
    return filteredEntries
        .where(
          (e) => e.fields.any((f) => f.key.toLowerCase().contains('passkey')),
        )
        .toList(growable: false);
  }
  if (selectedItemTypeId == kQuickFilterPasswordAudits) {
    final selectedAuditIssue = ref.watch(vaultPasswordAuditSelectionProvider);
    if (selectedAuditIssue == null) {
      return const <KdbxEntry>[];
    }
    if (selectedAuditIssue == PasswordAuditIssue.duplicated) {
      // Two-level drilldown for duplicates:
      //   level 1 (no group selected) ⇒ groups list view, no entries here
      //   level 2 (group selected)    ⇒ entries belonging to that group
      final selectedGroupKey =
          ref.watch(vaultPasswordAuditDuplicateGroupSelectionProvider);
      if (selectedGroupKey == null) {
        return const <KdbxEntry>[];
      }
      final groups = ref.watch(passwordAuditDuplicateGroupsProvider);
      final selectedGroup = groups.firstWhere(
        (group) => group.key == selectedGroupKey,
        orElse: () => const DuplicateItemGroup(
          key: '',
          title: '',
          username: '',
          entries: <KdbxEntry>[],
        ),
      );
      if (selectedGroup.entries.isEmpty) {
        return const <KdbxEntry>[];
      }
      final groupUuids =
          selectedGroup.entries.map((entry) => entry.uuid).toSet();
      return filteredEntries
          .where((entry) => groupUuids.contains(entry.uuid))
          .toList(growable: false);
    }
    final auditUuids = ref
        .watch(passwordAuditReportProvider)
        .where((audit) => audit.issues.contains(selectedAuditIssue))
        .map((audit) => audit.entry.uuid)
        .toSet();
    return filteredEntries
        .where((entry) => auditUuids.contains(entry.uuid))
        .toList(growable: false);
  }

  final selectedItemType = selectedItemTypeId == null
      ? null
      : VaultItemType.fromId(selectedItemTypeId);
  if (selectedItemType == null) {
    return filteredEntries;
  }

  return filteredEntries
      .where((entry) => classifyVaultItemType(entry) == selectedItemType)
      .toList(growable: false);
});

final vaultEntriesProvider = Provider<List<KdbxEntry>>((ref) {
  final query = ref.watch(vaultSearchQueryProvider).trim();
  final entries = ref.watch(vaultScopedEntriesProvider);
  if (query.isEmpty) {
    return entries;
  }

  // The list view shows the *full* set of matches. We still rank it so
  // the ordering is consistent with the dropdown above it (URL hits at
  // the top, recently used next, etc.).
  return rankSearchResults<KdbxEntry>(
    entries: entries,
    query: query,
    viewOf: kdbxEntrySearchView,
    titleOf: (e) => e.title,
  );
});

final vaultSearchSuggestionsProvider = Provider<List<KdbxEntry>>((ref) {
  return ref.watch(vaultSearchSuggestionsStateProvider).suggestions;
});

final vaultSearchSuggestionsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(vaultSearchSuggestionsStateProvider).isLoading;
});

/// Adapts a [KdbxEntry] into the framework-free view the ranker expects.
/// Kept package-private (no underscore on the function itself, so the
/// provider can use it; the helper avoids re-allocating the haystack on
/// every keystroke because Riverpod memoizes the provider value).
SearchableEntryView kdbxEntrySearchView(KdbxEntry entry) {
  final extras = <MapEntry<String, String>>[];
  for (final EntryField f in entry.fields) {
    if (f.isProtected || AppKdbxFieldKeys.isProtectedKey(f.key)) continue;
    if (f.value.isEmpty) continue;
    extras.add(MapEntry(f.key, f.value));
  }
  return SearchableEntryView(
    title: entry.title,
    url: entry.url ?? '',
    username: entry.username ?? '',
    notes: entry.notes ?? '',
    otpAuthUrl: entry.otpAuthUrl ?? '',
    tags: entry.tags,
    extraFields: extras,
    lastTouchedAt: entry.updatedAt ??
        entry.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

Iterable<KdbxEntry> _trashEntriesForGroup(KdbxGroup group) sync* {
  if (group.isRecycleBin) {
    yield* group.flattenedEntries();
    return;
  }
  for (final child in group.groups) {
    yield* _trashEntriesForGroup(child);
  }
}

Iterable<KdbxEntry> _visibleEntriesForGroup(KdbxGroup group) sync* {
  if (group.isRecycleBin) {
    return;
  }

  yield* group.entries;
  for (final child in group.groups) {
    yield* _visibleEntriesForGroup(child);
  }
}

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

int _recycleBinEntryCount(KdbxGroup group) {
  if (group.isRecycleBin) {
    return group.flattenedEntries().length;
  }

  var count = 0;
  for (final child in group.groups) {
    count += _recycleBinEntryCount(child);
  }
  return count;
}

/// Password strength classification used by the audit report.
enum PasswordStrength { weak, fair, good, strong }

/// Audit issue types reported by the Watchtower.
enum PasswordAuditIssue {
  duplicated,
  weak,
  stale,
}

/// A single entry in the password audit report.
class PasswordAuditEntry {
  const PasswordAuditEntry({
    required this.entry,
    required this.issues,
    this.duplicateCount,
    this.strength,
    this.lastUsedDays,
  });

  final KdbxEntry entry;
  final Set<PasswordAuditIssue> issues;
  final int? duplicateCount;
  final PasswordStrength? strength;
  final int? lastUsedDays;

  bool get hasDuplicated => issues.contains(PasswordAuditIssue.duplicated);
  bool get hasWeak => issues.contains(PasswordAuditIssue.weak);
  bool get hasStale => issues.contains(PasswordAuditIssue.stale);
}

/// Virtual filter ID for the Password Audits Quick Access item.
const String kQuickFilterPasswordAudits = 'quick_password_audits';

/// Evaluates password strength using the same algorithm as the detail pane.
PasswordStrength evaluatePasswordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.weak;
  int score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(password)) score++;
  if (RegExp(r'[a-z]').hasMatch(password)) score++;
  if (RegExp(r'[0-9]').hasMatch(password)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
  if (score <= 2) return PasswordStrength.weak;
  if (score == 3) return PasswordStrength.fair;
  if (score == 4) return PasswordStrength.good;
  return PasswordStrength.strong;
}

/// Extracts the password field from a KdbxEntry.
String _extractPassword(KdbxEntry entry) {
  return entry.fieldByKey(AppKdbxFieldKeys.password)?.value ?? '';
}

/// Normalizes the username/email field used by duplicate detection.
String _normalizeUsername(String? username) {
  return (username ?? '').trim().toLowerCase();
}

/// Normalizes the entry title (item name) for duplicate detection.
/// Trims surrounding whitespace and lowercases so casing/spacing
/// differences don't split otherwise-identical items.
String _normalizeTitle(String? title) {
  return (title ?? '').trim().toLowerCase();
}

/// Builds the composite key used to identify duplicate items. Three
/// dimensions must match exactly (after normalization): item name
/// (title), username/email, and the raw password value.
String _duplicateItemKey(KdbxEntry entry) {
  final title = _normalizeTitle(entry.title);
  final username = _normalizeUsername(entry.username);
  final password = _extractPassword(entry);
  return '$title\u0000$username\u0000$password';
}

/// A group of two or more entries that share the same title (item
/// name), username/email, and password — i.e. true duplicates
/// ("twins" or larger sets).
class DuplicateItemGroup {
  const DuplicateItemGroup({
    required this.key,
    required this.title,
    required this.username,
    required this.entries,
  });

  /// Stable composite key (title\u0000username\u0000password). Used as
  /// the selection identifier — never displayed to the user because it
  /// contains the raw password value.
  final String key;

  /// Original title (item name) taken from the first entry in the group.
  final String title;

  /// Original username/email value taken from the first entry in the
  /// group.
  final String username;

  /// All entries that share the three matching credentials. Always has
  /// length >= 2.
  final List<KdbxEntry> entries;

  int get count => entries.length;

  /// Convenience label shown on the duplicate-group card. Falls back to
  /// the first entry's title when both title and username are empty.
  String get displayLabel {
    if (title.isNotEmpty && username.isNotEmpty) {
      return '$title · $username';
    }
    if (title.isNotEmpty) return title;
    if (username.isNotEmpty) return username;
    return entries.first.title;
  }
}

/// Computes groups of duplicate entries that share the exact same
/// title (item name), username/email, and password. Singletons and
/// entries missing all three values are excluded.
List<DuplicateItemGroup> _findDuplicateItemGroups(List<KdbxEntry> entries) {
  final buckets = <String, List<KdbxEntry>>{};
  for (final entry in entries) {
    final title = _normalizeTitle(entry.title);
    final username = _normalizeUsername(entry.username);
    final password = _extractPassword(entry);
    // Skip empty-everywhere entries — they would all collapse into one
    // meaningless group.
    if (title.isEmpty && username.isEmpty && password.isEmpty) continue;
    // Require at least the password to be present; otherwise items with
    // no credentials at all would be flagged.
    if (password.isEmpty) continue;
    final key = _duplicateItemKey(entry);
    buckets.putIfAbsent(key, () => <KdbxEntry>[]).add(entry);
  }
  final groups = <DuplicateItemGroup>[];
  buckets.forEach((key, list) {
    if (list.length < 2) return;
    final first = list.first;
    groups.add(DuplicateItemGroup(
      key: key,
      title: first.title,
      username: first.username ?? '',
      entries: List<KdbxEntry>.unmodifiable(list),
    ));
  });
  // Sort by group size (desc) then by display label for stable display.
  groups.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return a.displayLabel.toLowerCase().compareTo(
          b.displayLabel.toLowerCase(),
        );
  });
  return List<DuplicateItemGroup>.unmodifiable(groups);
}

/// Provider that computes all duplicate item groups (URL+username+password).
final passwordAuditDuplicateGroupsProvider =
    Provider<List<DuplicateItemGroup>>((ref) {
  final entries = ref.watch(vaultDatabaseEntriesProvider);
  return _findDuplicateItemGroups(entries);
});

/// Computes the number of days since an entry was last modified/created.
int? _daysSinceLastTouched(KdbxEntry entry) {
  final touched = entry.updatedAt ?? entry.createdAt;
  if (touched == null) return null;
  return DateTime.now().difference(touched).inDays;
}

/// Provider that computes the full password audit report.
final passwordAuditReportProvider = Provider<List<PasswordAuditEntry>>((ref) {
  final entries = ref.watch(vaultDatabaseEntriesProvider);

  final duplicateGroups = _findDuplicateItemGroups(entries);
  final duplicateUuids = <String, int>{};
  for (final group in duplicateGroups) {
    for (final entry in group.entries) {
      duplicateUuids[entry.uuid] = group.count;
    }
  }

  final auditEntries = <PasswordAuditEntry>[];

  for (final entry in entries) {
    final issues = <PasswordAuditIssue>{};
    int? duplicateCount;
    PasswordStrength? strength;
    int? lastUsedDays;

    final password = _extractPassword(entry);

    // Check for duplicates
    if (duplicateUuids.containsKey(entry.uuid)) {
      issues.add(PasswordAuditIssue.duplicated);
      duplicateCount = duplicateUuids[entry.uuid];
    }

    // Check password strength (only for entries with passwords)
    if (password.isNotEmpty) {
      strength = evaluatePasswordStrength(password);
      if (strength == PasswordStrength.weak ||
          strength == PasswordStrength.fair) {
        issues.add(PasswordAuditIssue.weak);
      }
    }

    // Check for stale entries (not modified in over 6 months / 180 days)
    lastUsedDays = _daysSinceLastTouched(entry);
    if (lastUsedDays != null && lastUsedDays > 180) {
      issues.add(PasswordAuditIssue.stale);
    }

    // Only include entries with at least one issue
    if (issues.isNotEmpty) {
      auditEntries.add(PasswordAuditEntry(
        entry: entry,
        issues: issues,
        duplicateCount: duplicateCount,
        strength: strength,
        lastUsedDays: lastUsedDays,
      ));
    }
  }

  // Sort: duplicated first, then weak, then stale, then by title
  auditEntries.sort((a, b) {
    // Duplicated first
    if (a.hasDuplicated != b.hasDuplicated) {
      return a.hasDuplicated ? -1 : 1;
    }
    // Then weak
    if (a.hasWeak != b.hasWeak) {
      return a.hasWeak ? -1 : 1;
    }
    // Then stale
    if (a.hasStale != b.hasStale) {
      return a.hasStale ? -1 : 1;
    }
    // Then by title
    return a.entry.title.toLowerCase().compareTo(b.entry.title.toLowerCase());
  });

  return auditEntries;
});

/// Count of entries with audit issues for the sidebar badge.
final passwordAuditCountProvider = Provider<int>((ref) {
  return ref.watch(passwordAuditReportProvider).length;
});

/// Count of duplicate item groups (URL+username+password matches).
final passwordAuditDuplicatedCountProvider = Provider<int>((ref) {
  return ref.watch(passwordAuditDuplicateGroupsProvider).length;
});

/// Count of weak passwords.
final passwordAuditWeakCountProvider = Provider<int>((ref) {
  return ref.watch(passwordAuditReportProvider).where((e) => e.hasWeak).length;
});

/// Count of stale (unused) passwords.
final passwordAuditStaleCountProvider = Provider<int>((ref) {
  return ref.watch(passwordAuditReportProvider).where((e) => e.hasStale).length;
});
