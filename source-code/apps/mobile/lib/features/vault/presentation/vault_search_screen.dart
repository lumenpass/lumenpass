import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../application/vault_entries_providers.dart';
import '../application/vault_items_list_providers.dart';
import 'vault_entry_avatar.dart';
import 'vault_entry_context_menu.dart';
import 'vault_item_details_modal.dart';

const _searchBackground = Color(0xFFFDFDFE);
const _searchInk = Color(0xFF020204);
const _searchText = Color(0xFF202124);
const _searchMuted = Color(0xFF7A7B80);
const _searchDivider = Color(0xFFE8E8ED);
const _searchAccent = Color(0xFF2F67E3);
const _headerDivider = Color(0xFFE9E9EE);
const _sectionText = Color(0xFF7E7E84);
const _bottomBarHeight = 64.0;
const _bottomContentPadding = 108.0;
const _floatingSearchBottomInset = 8.0;

Future<void> openVaultSearchScreen(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const VaultSearchScreen()));
}

class VaultSearchScreen extends ConsumerStatefulWidget {
  const VaultSearchScreen({super.key});

  @override
  ConsumerState<VaultSearchScreen> createState() => _VaultSearchScreenState();
}

class _VaultSearchScreenState extends ConsumerState<VaultSearchScreen> {
  late final TextEditingController _searchController;
  Timer? _searchDebounceTimer;
  String _draftQuery = '';
  String _query = '';

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
    if (next == _draftQuery) {
      return;
    }

    _searchDebounceTimer?.cancel();
    _draftQuery = next;

    if (next.trim().isEmpty) {
      if (_query.isEmpty) {
        setState(() {});
        return;
      }
      setState(() {
        _query = '';
      });
      return;
    }

    _searchDebounceTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || _query == next) {
        return;
      }
      setState(() {
        _query = next;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final rawEntries = ref.watch(vaultVisibleEntriesProvider);
    final entries = _filterAndSortEntries(entries: rawEntries, query: _query);
    final items = _buildListItems(entries);

    return Scaffold(
      backgroundColor: _searchBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: _headerDivider)),
                  ),
                  child: _ScreenTopBar(
                    title: 'Search for items',
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: _searchAccent,
                    onRefresh: () => refreshVaultSnapshot(ref),
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              _query.trim().isEmpty
                                  ? 'Recent items'
                                  : 'Search results',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: _searchText,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                        if (items.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _SearchEmptyState(query: _query.trim()),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              20,
                              24,
                              MediaQuery.paddingOf(context).bottom +
                                  _bottomContentPadding,
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
                                  _VaultEntryRowItem() => _VaultSearchRow(
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
              child: _SearchBottomBar(controller: _searchController),
            ),
          ],
        ),
      ),
    );
  }

  List<KdbxEntry> _filterAndSortEntries({
    required List<KdbxEntry> entries,
    required String query,
  }) {
    final normalizedTerms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);

    final filtered = normalizedTerms.isEmpty
        ? List<KdbxEntry>.from(entries)
        : entries
              .where((entry) {
                final haystack = _searchableTextForEntry(entry);
                return normalizedTerms.every(haystack.contains);
              })
              .toList(growable: false);

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

      return timestampResult == 0 ? titleResult : -timestampResult;
    });

    return filtered;
  }

  List<_VaultListItem> _buildListItems(List<KdbxEntry> entries) {
    final formatter = DateFormat('MMMM yyyy');
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
          _VaultSectionHeaderItem(formatter.format(monthKey).toUpperCase()),
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
}

class _ScreenTopBar extends StatelessWidget {
  const _ScreenTopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

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
              color: _searchText,
            ),
          ),
        ),
        const SizedBox(width: 56, height: 56),
      ],
    );
  }
}

class _ActionCircleButton extends StatelessWidget {
  const _ActionCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
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
            child: Center(child: Icon(icon, size: 24, color: Colors.black87)),
          ),
        ),
      ),
    );
  }
}

class _VaultSearchRow extends StatelessWidget {
  const _VaultSearchRow({
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
                color: showDivider ? _searchDivider : Colors.transparent,
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
                        color: _searchText,
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
                          color: _searchMuted,
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

class _SearchBottomBar extends StatelessWidget {
  const _SearchBottomBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _bottomBarHeight,
      child: Align(
        alignment: Alignment.center,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            cursorColor: _searchInk,
            textInputAction: TextInputAction.search,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
              color: _searchText,
            ),
            decoration: InputDecoration(
              hintText: 'Search in vault',
              hintStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
                color: Color(0xFF797B80),
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 16, right: 8),
                child: Icon(Icons.search_rounded, size: 30, color: _searchInk),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 58,
                minHeight: 56,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 120, 34, _bottomContentPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.history_rounded,
              size: 44,
              color: const Color(0xFFB4B6BC),
            ),
            const SizedBox(height: 14),
            Text(
              hasQuery ? 'No results' : 'No recent items',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: _searchInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Try searching with a different item name, username, or tag.'
                  : 'Your saved items will appear here after you create them.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.35,
                letterSpacing: 0,
                color: _searchMuted,
              ),
            ),
          ],
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
