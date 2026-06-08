import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/ui/app_loading_overlay.dart';
import '../application/vault_entries_providers.dart';
import '../application/vault_items_list_providers.dart';
import 'vault_category_filter_dropdown.dart';
import 'vault_create_item.dart';
import 'vault_entry_context_menu.dart';
import 'vault_entry_list_tile.dart';
import 'vault_item_details_modal.dart';
import 'vault_search_floating_toolbar.dart';

const _listBorder = kVaultListRowBorder;
const _headerIcon = Color(0xFF536987);

/// Outer inset so list rows line up with the 20px home top bar (tile adds 12px).
const _itemsListHorizontalInset = 8.0;

/// Matches [VaultEntryListTile] horizontal padding so the column header lines up.
const _itemsListCellPaddingH = 12.0;

class VaultItemsTab extends ConsumerStatefulWidget {
  const VaultItemsTab({super.key});

  @override
  ConsumerState<VaultItemsTab> createState() => _VaultItemsTabState();
}

class _VaultItemsTabState extends ConsumerState<VaultItemsTab> {
  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(vaultItemsSortedEntriesProvider);
    final query = ref.watch(vaultSearchQueryProvider);
    final selectedUuid = ref.watch(vaultItemsSelectedEntryUuidProvider);
    final sortField = ref.watch(vaultItemsSortFieldProvider);
    final sortDir = ref.watch(vaultItemsSortDirectionProvider);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: VaultCategorySearchRow(),
            ),
            _ItemsListHeader(
              sortField: sortField,
              sortDirection: sortDir,
              onSortTitle: () => _toggleSort(ref, VaultItemsSortField.title),
              onSortLastEdited: () =>
                  _toggleSort(ref, VaultItemsSortField.lastEdited),
              onRefresh: () => withGlobalLoading(
                context,
                () => refreshVaultSnapshot(
                  ref,
                  reloadDelay: const Duration(seconds: 1),
                ),
                loadingMessage: 'Refreshing vault…',
                successMessage: 'Vault refreshed',
                leadIn: Duration.zero,
              ),
            ),
            if (query.trim().isNotEmpty)
              _SearchResultBanner(
                query: query.trim(),
                count: entries.length,
                onClear: () {
                  ref.read(vaultSearchUiStateProvider.notifier).clear();
                },
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  _itemsListHorizontalInset,
                  0,
                  _itemsListHorizontalInset,
                  0,
                ),
                child: entries.isEmpty
                    ? const _ItemsEmptyState()
                    : _LazyVaultEntriesList(
                        entries: entries,
                        selectedUuid: selectedUuid,
                        isSearching: query.trim().isNotEmpty,
                        onTapEntry: (entry) async {
                          final categories = ref.read(
                            vaultSidebarCategoriesProvider,
                          );
                          String? categoryName;
                          for (final c in categories) {
                            if (c.uuid == entry.groupUuid) {
                              categoryName = c.name;
                              break;
                            }
                          }
                          ref
                              .read(
                                vaultItemsSelectedEntryUuidProvider.notifier,
                              )
                              .state = entry
                              .uuid;
                          await showItemDetailsModal(
                            context,
                            entry: entry,
                            categoryName: categoryName,
                          );
                        },
                        onLongPressEntry: (entry) =>
                            _showContextMenu(context, ref, entry),
                      ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 12,
          child: VaultSearchFloatingToolbar(
            hintText: 'Search items',
            onAdd: () => showAddNewItemOverlay(context),
            addSemanticLabel: 'Add item',
          ),
        ),
      ],
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref, KdbxEntry entry) {
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

void _toggleSort(WidgetRef ref, VaultItemsSortField field) {
  final cur = ref.read(vaultItemsSortFieldProvider);
  final dir = ref.read(vaultItemsSortDirectionProvider);
  if (cur == field) {
    ref
        .read(vaultItemsSortDirectionProvider.notifier)
        .state = dir == VaultItemsSortDirection.ascending
        ? VaultItemsSortDirection.descending
        : VaultItemsSortDirection.ascending;
  } else {
    ref.read(vaultItemsSortFieldProvider.notifier).state = field;
    ref
        .read(vaultItemsSortDirectionProvider.notifier)
        .state = field == VaultItemsSortField.title
        ? VaultItemsSortDirection.ascending
        : VaultItemsSortDirection.descending;
  }
}

class _ItemsListHeader extends ConsumerWidget {
  const _ItemsListHeader({
    required this.sortField,
    required this.sortDirection,
    required this.onSortTitle,
    required this.onSortLastEdited,
    required this.onRefresh,
  });

  final VaultItemsSortField sortField;
  final VaultItemsSortDirection sortDirection;
  final VoidCallback onSortTitle;
  final VoidCallback onSortLastEdited;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the provider directly so the spinner reacts immediately,
    // independent of the parent widget's rebuild cycle.
    final isRefreshing = ref.watch(vaultItemsIsRefreshingProvider);

    return Container(
      height: 40,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFEBF0F7)],
        ),
        border: Border(
          top: BorderSide(color: Color(0xFFFFFFFF)),
          bottom: BorderSide(color: Color(0xFFB8C5D6), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _itemsListHorizontalInset,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _itemsListCellPaddingH,
          ),
          child: Row(
            children: [
              _HeaderSortChip(
                label: 'Title',
                active: sortField == VaultItemsSortField.title,
                ascending: sortDirection == VaultItemsSortDirection.ascending,
                onTap: onSortTitle,
              ),
              const Spacer(),
              _HeaderSortChip(
                label: 'Last Edited',
                active: sortField == VaultItemsSortField.lastEdited,
                ascending: sortDirection == VaultItemsSortDirection.ascending,
                onTap: onSortLastEdited,
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: isRefreshing ? null : () => onRefresh(),
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
                  child: _RefreshSpinnerIcon(isRefreshing: isRefreshing),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefreshSpinnerIcon extends StatefulWidget {
  const _RefreshSpinnerIcon({required this.isRefreshing});

  final bool isRefreshing;

  @override
  State<_RefreshSpinnerIcon> createState() => _RefreshSpinnerIconState();
}

class _RefreshSpinnerIconState extends State<_RefreshSpinnerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isRefreshing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RefreshSpinnerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRefreshing && !oldWidget.isRefreshing) {
      _controller.repeat();
    } else if (!widget.isRefreshing && oldWidget.isRefreshing) {
      _controller
        ..stop()
        ..animateTo(
          1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ).whenComplete(_controller.reset);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(
        Icons.refresh_rounded,
        size: 18,
        color: widget.isRefreshing ? const Color(0xFF0A67FF) : _headerIcon,
      ),
    );
  }
}

class _HeaderSortChip extends StatelessWidget {
  const _HeaderSortChip({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: _headerIcon,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchResultBanner extends StatelessWidget {
  const _SearchResultBanner({
    required this.query,
    required this.count,
    required this.onClear,
  });

  final String query;
  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F3FF),
        border: Border(bottom: BorderSide(color: _listBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count results for "$query"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A4457),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: Color(0xFF7C8598),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stateful wrapper around the items `ListView` that paginates the source
/// entries so only a limited window is rendered initially. Mirrors the
/// desktop `_ListPane` behaviour: first paint shows [_initialVisibleCount]
/// rows; when the user scrolls near the tail the window grows by
/// [_loadMoreBatch]. Search results bypass the window entirely so every
/// match is rendered.
class _LazyVaultEntriesList extends StatefulWidget {
  const _LazyVaultEntriesList({
    required this.entries,
    required this.selectedUuid,
    required this.isSearching,
    required this.onTapEntry,
    required this.onLongPressEntry,
  });

  final List<KdbxEntry> entries;
  final String? selectedUuid;
  final bool isSearching;
  final Future<void> Function(KdbxEntry entry) onTapEntry;
  final void Function(KdbxEntry entry) onLongPressEntry;

  @override
  State<_LazyVaultEntriesList> createState() => _LazyVaultEntriesListState();
}

class _LazyVaultEntriesListState extends State<_LazyVaultEntriesList> {
  static const int _initialVisibleCount = 30;
  static const int _loadMoreBatch = 30;
  static const double _loadMoreThreshold = 200;

  late final ScrollController _scrollController;
  int _visibleCount = _initialVisibleCount;

  int get _effectiveItemCount {
    if (widget.isSearching) {
      return widget.entries.length;
    }
    return math.min(_visibleCount, widget.entries.length);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LazyVaultEntriesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final searchChanged = widget.isSearching != oldWidget.isSearching;
    final entriesChanged =
        !identical(widget.entries, oldWidget.entries) ||
        widget.entries.length != oldWidget.entries.length;
    if (searchChanged || entriesChanged) {
      _visibleCount = _initialVisibleCount;
      // Jump back to top after a scope/search change so the user isn't
      // stranded at an offset that no longer has content mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (_scrollController.position.pixels > 0) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  void _maybeLoadMore() {
    if (widget.isSearching || !_scrollController.hasClients) {
      return;
    }
    if (_visibleCount >= widget.entries.length) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      setState(() {
        _visibleCount = math.min(
          widget.entries.length,
          _visibleCount + _loadMoreBatch,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: _effectiveItemCount,
      // Rows are a fixed height (see [VaultEntryListTile]). Giving the
      // viewport an itemExtent lets it skip the per-row layout pass entirely
      // and keeps scrolling at 60 fps even for large vaults.
      itemExtent: kVaultListAttributeRowHeight,
      // The tiles already wrap their contents in a [RepaintBoundary], so the
      // viewport's automatic one is redundant. Removing it trims a layer per
      // row.
      addRepaintBoundaries: false,
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        return VaultEntryListTile(
          key: ValueKey(entry.uuid),
          entry: entry,
          selected: entry.uuid == widget.selectedUuid,
          showAttributeLines: true,
          onTap: () => widget.onTapEntry(entry),
          onLongPress: () => widget.onLongPressEntry(entry),
        );
      },
    );
  }
}

class _ItemsEmptyState extends StatelessWidget {
  const _ItemsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFFC7D6F6)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120A67FF),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.inbox_outlined,
                size: 24,
                color: Color(0xFF2E5ECC),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nothing here yet',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A4A5E),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Try another search or pull to refresh.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
