import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/repository/providers.dart';
import '../../../core/ui/floating_glass_search_bar.dart';
import '../application/vault_entries_providers.dart';
import '../application/vault_items_list_providers.dart';
import 'vault_create_item.dart';
import 'vault_entry_avatar.dart';
import 'vault_entry_context_menu.dart';
import 'vault_item_details_modal.dart';

const _screenBackground = Color(0xFFFDFDFE);
const _screenBorder = Color(0xFFE8E8ED);
const _sectionText = Color(0xFF7E7E84);
const _titleText = Color(0xFF202124);
const _subtitleText = Color(0xFF7A7B80);
const _sortAccent = Color(0xFF2F67E3);
const _headerDivider = Color(0xFFE9E9EE);
const _floatingSearchBottomInset = 8.0;
const _floatingContentBottomPadding = 108.0;

/// Shared month-header formatter. Constructed once instead of per build so
/// the (relatively expensive) intl pattern compilation doesn't run on every
/// keystroke-driven rebuild.
final DateFormat _monthHeaderFormat = DateFormat('MMMM yyyy');

Future<void> openVaultAllItemsScreen(
  BuildContext context, {
  String title = 'All items',
  String? categoryUuid,
  bool uncategorizedOnly = false,
  String? itemTypeId,
  String? tag,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VaultAllItemsScreen(
        title: title,
        categoryUuid: categoryUuid,
        uncategorizedOnly: uncategorizedOnly,
        itemTypeId: itemTypeId,
        tag: tag,
      ),
    ),
  );
}

class VaultAllItemsScreen extends ConsumerStatefulWidget {
  const VaultAllItemsScreen({
    super.key,
    this.title = 'All items',
    this.categoryUuid,
    this.uncategorizedOnly = false,
    this.itemTypeId,
    this.tag,
  });

  final String title;
  final String? categoryUuid;
  final bool uncategorizedOnly;
  final String? itemTypeId;
  final String? tag;

  @override
  ConsumerState<VaultAllItemsScreen> createState() =>
      _VaultAllItemsScreenState();
}

enum _VaultAllItemsSort { newestFirst, oldestFirst }

class _VaultAllItemsScreenState extends ConsumerState<VaultAllItemsScreen> {
  /// Debounce window for search input. Matches the desktop vault search so
  /// fast typing coalesces into one filter/sort pass instead of one per
  /// keystroke (which re-scanned the whole vault on every character).
  static const Duration _searchDebounce = Duration(milliseconds: 150);

  late final TextEditingController _searchController;
  String _query = '';
  _VaultAllItemsSort _sort = _VaultAllItemsSort.newestFirst;
  Timer? _searchDebounceTimer;
  int _searchSequence = 0;

  /// Memoized lowercase search haystacks, keyed by entry uuid. Rebuilt only
  /// when the underlying entry list changes (snapshot publish), so typing in
  /// the search field reuses the cached strings instead of re-joining every
  /// entry's fields on each keystroke.
  Map<String, String> _haystackCache = const {};
  List<KdbxEntry>? _haystackCacheSource;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text;
    if (next == _query) {
      return;
    }
    final sequence = ++_searchSequence;
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      if (!mounted || sequence != _searchSequence) return;
      setState(() {
        _query = next;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(activeDatabaseProvider);
    final allEntries = ref.watch(vaultVisibleEntriesProvider);
    final scopedEntries = _applyScreenScope(
      entries: allEntries,
      database: database,
    );
    final entries = _filterAndSortEntries(
      entries: scopedEntries,
      query: _query,
      sort: _sort,
    );
    final items = _buildListItems(entries);

    return Scaffold(
      backgroundColor: _screenBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _headerDivider)),
                  ),
                  child: _ScreenTopBar(
                    title: widget.title,
                    onBack: () => Navigator.of(context).maybePop(),
                    onFilter: _showSortSheet,
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: _sortAccent,
                    onRefresh: () => refreshVaultSnapshot(ref),
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        if (items.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(query: _query.trim()),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              24,
                              24,
                              MediaQuery.paddingOf(context).bottom +
                                  _floatingContentBottomPadding,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final item = items[index];
                                return switch (item) {
                                  _VaultSectionHeaderItem() => Padding(
                                    padding: EdgeInsets.only(
                                      top: index == 0 ? 0 : 18,
                                      bottom: 12,
                                    ),
                                    child: Text(
                                      item.label,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _sectionText,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                  _VaultEntryRowItem() => _VaultEntryRow(
                                    entry: item.entry,
                                    showDivider: item.showDivider,
                                    onTap: () => _openEntryDetails(item.entry),
                                    onLongPress: () =>
                                        _showContextMenu(item.entry),
                                  ),
                                };
                              }, childCount: items.length),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom:
                  MediaQuery.paddingOf(context).bottom +
                  _floatingSearchBottomInset,
              child: FloatingGlassSearchToolbar(
                controller: _searchController,
                hintText: widget.title == 'All items'
                    ? 'Find in All items'
                    : 'Search in ${widget.title}',
                onChanged: (_) {},
                onAdd: () => showAddNewItemOverlay(context),
                addSemanticLabel: 'Add item',
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<KdbxEntry> _applyScreenScope({
    required List<KdbxEntry> entries,
    required KdbxDatabase? database,
  }) {
    Iterable<KdbxEntry> scoped = entries;

    if (widget.uncategorizedOnly && database != null) {
      final rootUuid = database.rootGroup.uuid;
      scoped = scoped.where((entry) => entry.groupUuid == rootUuid);
    } else if (widget.categoryUuid != null && database != null) {
      final group = _findGroupByUuid(database.rootGroup, widget.categoryUuid!);
      if (group != null) {
        final allowedGroupUuids = group
            .flattenedGroups()
            .map((entry) => entry.uuid)
            .toSet();
        scoped = scoped.where(
          (entry) => allowedGroupUuids.contains(entry.groupUuid),
        );
      }
    }

    final normalizedTag = widget.tag?.trim().toLowerCase();
    if (normalizedTag != null && normalizedTag.isNotEmpty) {
      scoped = scoped.where(
        (entry) =>
            entry.tags.any((tag) => tag.trim().toLowerCase() == normalizedTag),
      );
    }

    if (widget.itemTypeId != null && widget.itemTypeId!.trim().isNotEmpty) {
      scoped = scoped.where(
        (entry) => _entryMatchesItemType(entry, widget.itemTypeId!),
      );
    }

    return scoped.toList(growable: false);
  }

  List<KdbxEntry> _filterAndSortEntries({
    required List<KdbxEntry> entries,
    required String query,
    required _VaultAllItemsSort sort,
  }) {
    final normalizedTerms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);

    List<KdbxEntry> filtered;
    if (normalizedTerms.isEmpty) {
      filtered = List<KdbxEntry>.from(entries);
    } else {
      _ensureHaystackCache(entries);
      filtered = entries
          .where((entry) {
            final haystack = _haystackCache[entry.uuid] ?? '';
            return normalizedTerms.every(haystack.contains);
          })
          .toList(growable: false);
    }

    filtered.sort((a, b) {
      final aTimestamp =
          latestEntryTimestamp(a.updatedAt, a.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTimestamp =
          latestEntryTimestamp(b.updatedAt, b.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final timestampResult = aTimestamp.compareTo(bTimestamp);
      final titleResult = a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      );

      return switch (sort) {
        _VaultAllItemsSort.newestFirst =>
          timestampResult == 0 ? titleResult : -timestampResult,
        _VaultAllItemsSort.oldestFirst =>
          timestampResult == 0 ? titleResult : timestampResult,
      };
    });

    return filtered;
  }

  /// Rebuilds [_haystackCache] only when the entry list identity changes.
  /// The list comes from a Riverpod provider, so a new snapshot publish
  /// yields a new list instance; typing in the search field keeps the same
  /// list and therefore reuses the cache.
  void _ensureHaystackCache(List<KdbxEntry> entries) {
    if (identical(entries, _haystackCacheSource)) return;
    _haystackCacheSource = entries;
    _haystackCache = {
      for (final entry in entries) entry.uuid: _searchableTextForEntry(entry),
    };
  }

  List<_VaultListItem> _buildListItems(List<KdbxEntry> entries) {
    final items = <_VaultListItem>[];
    DateTime? currentMonth;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final timestamp =
          latestEntryTimestamp(entry.updatedAt, entry.createdAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final monthKey = DateTime(timestamp.year, timestamp.month);

      if (currentMonth != monthKey) {
        currentMonth = monthKey;
        items.add(
          _VaultSectionHeaderItem(
            _monthHeaderFormat.format(monthKey).toUpperCase(),
          ),
        );
      }

      final nextEntry = i + 1 < entries.length ? entries[i + 1] : null;
      final nextTimestamp = nextEntry == null
          ? null
          : latestEntryTimestamp(nextEntry.updatedAt, nextEntry.createdAt) ??
                DateTime.fromMillisecondsSinceEpoch(0);
      final showDivider =
          nextTimestamp != null &&
          (nextTimestamp.year == timestamp.year &&
              nextTimestamp.month == timestamp.month);

      items.add(_VaultEntryRowItem(entry: entry, showDivider: showDivider));
    }

    return items;
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

  Future<void> _openEntryDetails(KdbxEntry entry) async {
    final categories = ref.read(vaultSidebarCategoriesProvider);
    String? categoryName;
    for (final category in categories) {
      if (category.uuid == entry.groupUuid) {
        categoryName = category.name;
        break;
      }
    }

    ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = entry.uuid;
    await showItemDetailsModal(
      context,
      entry: entry,
      categoryName: categoryName,
    );
  }

  void _showContextMenu(KdbxEntry entry) {
    ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = entry.uuid;
    showVaultEntryContextMenuDialog(
      context,
      entry: entry,
      onItemSaved: (uuid) {
        ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = uuid;
      },
    );
  }

  Future<void> _showSortSheet() {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _SortSheet(
          selected: _sort,
          onSelected: (next) {
            setState(() {
              _sort = next;
            });
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }
}

bool _entryMatchesItemType(KdbxEntry entry, String itemTypeId) {
  final itemType = classifyVaultItemType(entry);
  return switch (itemTypeId) {
    'login' => itemType == VaultItemType.login,
    'secure-note' => itemType == VaultItemType.secureNote,
    'credit-card' => itemType == VaultItemType.creditCard,
    'identity' => itemType == VaultItemType.identity,
    'ssh-key' => itemType == VaultItemType.sshKey,
    'bank-account' => itemType == VaultItemType.bankAccount,
    _ => true,
  };
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

class _ScreenTopBar extends StatelessWidget {
  const _ScreenTopBar({
    required this.title,
    required this.onBack,
    required this.onFilter,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionCircleButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: onBack,
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _titleText,
            ),
          ),
        ),
        _ActionCircleButton(
          icon: Icons.sort_rounded,
          onTap: onFilter,
          backgroundColor: const Color(0xFF2F3034),
          iconColor: Colors.white,
          iconSize: 22,
        ),
      ],
    );
  }
}

class _ActionCircleButton extends StatelessWidget {
  const _ActionCircleButton({
    required this.icon,
    required this.onTap,
    this.backgroundColor = Colors.white,
    this.iconColor = Colors.black87,
    this.iconSize = 24,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Icon(icon, size: iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultEntryRow extends StatelessWidget {
  const _VaultEntryRow({
    required this.entry,
    required this.showDivider,
    required this.onTap,
    required this.onLongPress,
  });

  final KdbxEntry entry;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final itemType = classifyVaultItemType(entry);
    final subtitle = vaultEntryListSubtitle(entry, itemType);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: showDivider ? _screenBorder : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              VaultEntryAvatar(entry: entry, size: 34, itemType: itemType),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: _titleText,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: _subtitleText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                size: 30,
                color: Color(0xFFD0D0D6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final title = query.isEmpty ? 'No items yet' : 'Nothing matched';
    final body = query.isEmpty
        ? 'Add your first item to see it here.'
        : 'Try a different search term.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 28,
                color: _sortAccent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _titleText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _subtitleText,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.selected, required this.onSelected});

  final _VaultAllItemsSort selected;
  final ValueChanged<_VaultAllItemsSort> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sort items',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _titleText,
                    ),
                  ),
                ),
              ),
              _SortOptionTile(
                label: 'Newest first',
                selected: selected == _VaultAllItemsSort.newestFirst,
                onTap: () => onSelected(_VaultAllItemsSort.newestFirst),
              ),
              _SortOptionTile(
                label: 'Oldest first',
                selected: selected == _VaultAllItemsSort.oldestFirst,
                onTap: () => onSelected(_VaultAllItemsSort.oldestFirst),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortOptionTile extends StatelessWidget {
  const _SortOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _titleText,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: _sortAccent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

sealed class _VaultListItem {
  const _VaultListItem();
}

class _VaultSectionHeaderItem extends _VaultListItem {
  const _VaultSectionHeaderItem(this.label);

  final String label;
}

class _VaultEntryRowItem extends _VaultListItem {
  const _VaultEntryRowItem({required this.entry, required this.showDivider});

  final KdbxEntry entry;
  final bool showDivider;
}
