import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/repository/database_save_sync.dart';
import '../../../core/repository/providers.dart';
import '../../../core/ui/app_snack_bar.dart';
import '../../unlock/application/database_registry.dart';
import '../application/vault_entries_providers.dart';
import 'vault_create_item_models.dart';

/// Same prefix as desktop category notes encoding.
const String _kCategoryIconNotesPrefix = 'lumenpass-category-icon:';
const String _kManageCategoriesAction = '__manage_categories__';
const int _kTotalCategoryImages = 392;

/// Category dropdown on the left, search field on the right (single row).
class VaultCategorySearchRow extends StatelessWidget {
  const VaultCategorySearchRow({super.key, this.searchField});

  final Widget? searchField;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: VaultCategoryFilterDropdown()),
            const SizedBox(width: 10),
            const Expanded(child: VaultItemTypeFilterDropdown()),
          ],
        ),
        if (searchField != null) ...[
          const SizedBox(height: 10),
          searchField!,
        ],
      ],
    );
  }
}

class VaultItemTypeFilterDropdown extends ConsumerStatefulWidget {
  const VaultItemTypeFilterDropdown({super.key});

  @override
  ConsumerState<VaultItemTypeFilterDropdown> createState() =>
      _VaultItemTypeFilterDropdownState();
}

class _VaultItemTypeFilterDropdownState
    extends ConsumerState<VaultItemTypeFilterDropdown> {
  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(vaultItemTypeCountsProvider);
    final selected = ref.watch(vaultSelectedItemTypeFilterProvider);
    final allCount = counts.values.fold<int>(0, (a, b) => a + b);

    final options = <_ItemTypeOption>[
      _ItemTypeOption(
        id: kItemTypeFilterAll,
        label: 'All Items',
        count: allCount,
        icon: Icons.grid_view_rounded,
        iconColor: const Color(0xFF5E6C7E),
      ),
      ...kAllNewItemTypes.map(
        (t) => _ItemTypeOption(
          id: t.id,
          label: t.label,
          count: counts[t.id] ?? 0,
          icon: t.icon ?? Icons.label_outline_rounded,
          iconColor: t.iconColor,
          imagePath: t.imagePath,
        ),
      ),
    ];

    final current = options.firstWhere(
      (o) => o.id == selected,
      orElse: () => options.first,
    );

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E4EA), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0A3B48),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final next = await _showItemTypePickerModal(
            context: context,
            options: options,
            selectedId: selected,
          );
          if (next == null || !mounted) return;
          ref.read(vaultSelectedItemTypeFilterProvider.notifier).state = next;
        },
        child: Row(
          children: [
            _ItemTypeLeadingVisual(option: current, compact: true),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${current.label} (${current.count})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF243047),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF6E8A93),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showItemTypePickerModal({
    required BuildContext context,
    required List<_ItemTypeOption> options,
    required String selectedId,
  }) {
    final controller = ScrollController();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    final width = MediaQuery.sizeOf(context).width * 0.86;

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width.clamp(280.0, 420.0),
                maxHeight: maxHeight,
              ),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Select item type',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF213247),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: const Color(0xFF6F8090),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE9EEF3)),
                    Flexible(
                      child: Scrollbar(
                        controller: controller,
                        thumbVisibility: true,
                        child: ListView.separated(
                          controller: controller,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          itemCount: options.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final selected = option.id == selectedId;
                            return Material(
                              color: selected
                                  ? const Color(0xFFEAF3FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.of(ctx).pop(option.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      _ItemTypeLeadingVisual(option: option),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${option.label} (${option.count})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: const Color(0xFF243047),
                                          ),
                                        ),
                                      ),
                                      if (selected)
                                        const Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: Color(0xFF0A67FF),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Category (KeePass group) filter — same scope as desktop vault sidebar categories.
class VaultCategoryFilterDropdown extends ConsumerStatefulWidget {
  const VaultCategoryFilterDropdown({super.key});

  @override
  ConsumerState<VaultCategoryFilterDropdown> createState() =>
      _VaultCategoryFilterDropdownState();
}

class _VaultCategoryFilterDropdownState
    extends ConsumerState<VaultCategoryFilterDropdown> {
  @override
  Widget build(BuildContext context) {
    final total = ref.watch(vaultVisibleEntriesProvider).length;
    final uncCount = ref.watch(vaultUncategorizedCountProvider);
    final categories = ref.watch(vaultSidebarCategoriesProvider);
    var selected = ref.watch(vaultSelectedGroupProvider);

    final valid = <String>{
      kCategoryFilterAll,
      kCategoryFilterUncategorized,
      ...categories.map((c) => c.uuid),
    };

    if (!valid.contains(selected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(vaultSelectedGroupProvider.notifier).state =
            kCategoryFilterAll;
      });
      selected = kCategoryFilterAll;
    }

    const textStyle = TextStyle(
      color: Color(0xFF243047),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    final options = <_CategoryOption>[
      _CategoryOption(id: kCategoryFilterAll, label: 'All', count: total),
      _CategoryOption(
        id: kCategoryFilterUncategorized,
        label: 'Uncategorized',
        count: uncCount,
      ),
      ...categories.map(
        (c) => _CategoryOption(
          id: c.uuid,
          label: c.name,
          count: c.count,
          notes: c.notes,
        ),
      ),
    ];

    final current = options.firstWhere(
      (o) => o.id == selected,
      orElse: () => options.first,
    );

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E4EA), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C0A3B48),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final next = await _showCategoryPickerModal(
            context: context,
            options: options,
            selectedId: selected,
          );
          if (next == null || !mounted) return;
          if (next == _kManageCategoriesAction) {
            if (!context.mounted) return;
            await _showManageCategoriesModal(context);
            return;
          }
          ref.read(vaultSelectedGroupProvider.notifier).state = next;
        },
        child: Row(
          children: [
            _CategoryLeadingVisual(
              categoryId: current.id,
              notes: current.notes,
              compact: true,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${current.label} (${current.count})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF6E8A93),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showCategoryPickerModal({
    required BuildContext context,
    required List<_CategoryOption> options,
    required String selectedId,
  }) {
    final controller = ScrollController();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    final width = MediaQuery.sizeOf(context).width * 0.86;

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width.clamp(280.0, 420.0),
                maxHeight: maxHeight,
              ),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Select category',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF213247),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: const Color(0xFF6F8090),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE9EEF3)),
                    Flexible(
                      child: Scrollbar(
                        controller: controller,
                        thumbVisibility: true,
                        child: ListView.separated(
                          controller: controller,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          itemCount: options.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final selected = option.id == selectedId;
                            return Material(
                              color: selected
                                  ? const Color(0xFFEAF3FF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.of(ctx).pop(option.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      _CategoryLeadingVisual(
                                        categoryId: option.id,
                                        notes: option.notes,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${option.label} (${option.count})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: const Color(0xFF243047),
                                          ),
                                        ),
                                      ),
                                      if (selected)
                                        const Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: Color(0xFF0A67FF),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE9EEF3)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(_kManageCategoriesAction),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0A3B48),
                            foregroundColor: const Color(0xFFEAF6F9),
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Manage Categories',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showManageCategoriesModal(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _ManageCategoriesDialog(),
    );
  }
}

class _CategoryOption {
  const _CategoryOption({
    required this.id,
    required this.label,
    required this.count,
    this.notes = '',
  });

  final String id;
  final String label;
  final int count;
  final String notes;
}

class _ManageCategoriesDialog extends ConsumerStatefulWidget {
  const _ManageCategoriesDialog();

  @override
  ConsumerState<_ManageCategoriesDialog> createState() =>
      _ManageCategoriesDialogState();
}

class _ManageCategoriesDialogState
    extends ConsumerState<_ManageCategoriesDialog> {
  late final TextEditingController _searchCtrl;
  String _search = '';
  String? _openedCategoryUuid;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vaultSidebarCategoriesProvider);
    final query = _search.trim().toLowerCase();
    final filtered = categories
        .where((c) {
          if (query.isEmpty) return true;
          return c.name.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.74;
    final width = MediaQuery.sizeOf(context).width * 0.9;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width.clamp(290.0, 440.0),
            maxHeight: maxHeight,
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Manage categories',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF213247),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF6F8090),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F8FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3EAF0)),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _search = v),
                      style: const TextStyle(
                        color: Color(0xFF243047),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search categories',
                        hintStyle: TextStyle(
                          color: Color(0xFF6E8A93),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: Color(0xFF6E8A93),
                        ),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 34,
                          minHeight: 36,
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      Text(
                        '${filtered.length} categories',
                        style: const TextStyle(
                          color: Color(0xFF6E8A93),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Swipe left for actions',
                        style: TextStyle(
                          color: Color(0xFF8A9AA3),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE9EEF3)),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No matching categories',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF7A8B96),
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE3EAF0),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final category = filtered[index];
                                  final isLast = index == filtered.length - 1;
                                  return _SwipeCategoryTile(
                                    key: ValueKey(category.uuid),
                                    category: category,
                                    showBottomBorder: !isLast,
                                    isOpen:
                                        _openedCategoryUuid == category.uuid,
                                    onRequestOpen: () {
                                      setState(() {
                                        _openedCategoryUuid = category.uuid;
                                      });
                                    },
                                    onRequestClose: () {
                                      if (_openedCategoryUuid ==
                                          category.uuid) {
                                        setState(() {
                                          _openedCategoryUuid = null;
                                        });
                                      }
                                    },
                                    onEdit: () =>
                                        _openCategoryEditor(existing: category),
                                    onDelete: () =>
                                        _confirmDeleteCategory(category),
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE9EEF3)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            side: const BorderSide(color: Color(0xFFD7E0E7)),
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _openCategoryEditor,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0A3B48),
                            minimumSize: const Size.fromHeight(42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Create',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCategoryEditor({
    ({String uuid, String name, String notes, int count})? existing,
  }) async {
    final result = await showDialog<_CategoryEditorResult>(
      context: context,
      builder: (_) => _CategoryEditorDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    if (result.created) {
      ref.read(vaultSelectedGroupProvider.notifier).state = result.groupUuid;
    }
    ref.invalidate(vaultSidebarCategoriesProvider);
    ref.invalidate(vaultVisibleEntriesProvider);
  }

  Future<void> _confirmDeleteCategory(
    ({String uuid, String name, String notes, int count}) category,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Delete "${category.name}" and its nested groups?\n'
          'All items in this category will be moved to Uncategorized.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final activeDb = ref.read(activeDatabaseProvider);
      if (activeDb == null) {
        throw StateError('Open a vault before deleting categories');
      }
      final selectedGroup = _findGroupByUuid(activeDb.rootGroup, category.uuid);
      if (selectedGroup != null) {
        final affectedGroupUuids = selectedGroup
            .flattenedGroups()
            .map((g) => g.uuid)
            .toSet();
        final entriesToMove = ref
            .read(vaultVisibleEntriesProvider)
            .where((e) => affectedGroupUuids.contains(e.groupUuid))
            .toList(growable: false);
        final uncategorizedGroupUuid = activeDb.rootGroup.uuid;
        for (final entry in entriesToMove) {
          await repository.moveEntryToGroup(
            entryUuid: entry.uuid,
            targetGroupUuid: uncategorizedGroupUuid,
          );
        }
      }
      await repository.deleteGroup(category.uuid);
      final registry = ref.read(databaseRegistryProvider);
      final database = await saveAndSyncDatabase(repository, registry);
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultSidebarCategoriesProvider);
      ref.invalidate(vaultVisibleEntriesProvider);
      final selected = ref.read(vaultSelectedGroupProvider);
      if (selected == category.uuid) {
        ref.read(vaultSelectedGroupProvider.notifier).state =
            kCategoryFilterAll;
      }
      if (!mounted) return;
      AppSnackBar.success(context, '${category.name} category deleted');
    } catch (error) {
      if (!mounted) return;
      AppSnackBar.error(context, 'Unable to delete category: $error');
    }
  }
}

class _SwipeCategoryTile extends StatefulWidget {
  const _SwipeCategoryTile({
    super.key,
    required this.category,
    required this.showBottomBorder,
    required this.isOpen,
    required this.onRequestOpen,
    required this.onRequestClose,
    required this.onEdit,
    required this.onDelete,
  });

  final ({String uuid, String name, String notes, int count}) category;
  final bool showBottomBorder;
  final bool isOpen;
  final VoidCallback onRequestOpen;
  final VoidCallback onRequestClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_SwipeCategoryTile> createState() => _SwipeCategoryTileState();
}

class _SwipeCategoryTileState extends State<_SwipeCategoryTile> {
  double _reveal = 0;
  static const double _maxReveal = 116;

  @override
  void didUpdateWidget(covariant _SwipeCategoryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isOpen && _reveal != 0) {
      setState(() => _reveal = 0);
    } else if (widget.isOpen && _reveal == 0) {
      setState(() => _reveal = _maxReveal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = (_reveal / _maxReveal).clamp(0.0, 1.0);
    return SizedBox(
      height: 58,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: const Color(0xFFEFF4F8),
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: _maxReveal,
                  child: Row(
                    children: [
                      Expanded(
                        child: Opacity(
                          opacity: t,
                          child: InkWell(
                            onTap: _reveal >= _maxReveal * 0.9
                                ? widget.onEdit
                                : null,
                            child: Container(
                              height: double.infinity,
                              color: const Color(0xFF2563EB),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Opacity(
                          opacity: t,
                          child: InkWell(
                            onTap: _reveal >= _maxReveal * 0.9
                                ? widget.onDelete
                                : null,
                            child: Container(
                              height: double.infinity,
                              color: const Color(0xFFDC2626),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                final next = (_reveal - details.delta.dx).clamp(
                  0.0,
                  _maxReveal,
                );
                setState(() => _reveal = next);
                if (next > 0) {
                  widget.onRequestOpen();
                }
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _reveal = _reveal > (_maxReveal * 0.45) ? _maxReveal : 0;
                });
                if (_reveal == 0) {
                  widget.onRequestClose();
                } else {
                  widget.onRequestOpen();
                }
              },
              onTapUp: (details) {
                if (_reveal <= 0) {
                  return;
                }

                final box = context.findRenderObject() as RenderBox?;
                if (box == null) {
                  return;
                }
                final tapX = details.localPosition.dx;
                final actionStartX = box.size.width - _reveal;
                final tappedActionArea = tapX >= actionStartX;

                if (tappedActionArea && _reveal >= _maxReveal * 0.9) {
                  final relativeX = tapX - actionStartX;
                  final firstHalf = _reveal / 2;
                  if (relativeX <= firstHalf) {
                    widget.onEdit();
                  } else {
                    widget.onDelete();
                  }
                  return;
                }

                setState(() => _reveal = 0);
                widget.onRequestClose();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(-_reveal, 0, 0),
                padding: EdgeInsets.fromLTRB(12 + (10 * t), 0, 12, 0),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: widget.showBottomBorder
                      ? const Border(
                          bottom: BorderSide(color: Color(0xFFE3EAF0)),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    _CategoryLeadingVisual(
                      categoryId: widget.category.uuid,
                      notes: widget.category.notes,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.category.name} (${widget.category.count})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF243047),
                        ),
                      ),
                    ),
                    if (_reveal == 0)
                      const Icon(
                        Icons.chevron_left_rounded,
                        size: 18,
                        color: Color(0xFFB5C0C8),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryEditorResult {
  const _CategoryEditorResult({required this.groupUuid, required this.created});

  final String groupUuid;
  final bool created;
}

class _CategoryEditorDialog extends ConsumerStatefulWidget {
  const _CategoryEditorDialog({this.existing});

  final ({String uuid, String name, String notes, int count})? existing;

  @override
  ConsumerState<_CategoryEditorDialog> createState() =>
      _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends ConsumerState<_CategoryEditorDialog> {
  late final TextEditingController _nameCtrl;
  late String _presetId;
  String _colorId = 'teal';
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    final decoded = _decodeCategoryVisualPayload(widget.existing?.notes);
    _presetId = decoded?.presetId ?? 'img:1';
    _colorId = decoded?.colorId ?? 'teal';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageId = _presetId.startsWith('img:') ? _presetId.substring(4) : '';
    final imagePath = imageId.isEmpty
        ? null
        : 'assets/images/categories/$imageId.png';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Stack(
          children: [
            AbsorbPointer(
              absorbing: _saving,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _editing ? 'Edit Category' : 'Create Category',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF213247),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _saving ? null : _pickCategoryImage,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 94,
                          height: 94,
                          color: const Color(0xFFE8EEF9),
                          child: imagePath == null
                              ? const Icon(
                                  Icons.folder_outlined,
                                  size: 38,
                                  color: Color(0xFF5A78C5),
                                )
                              : Image.asset(
                                  imagePath,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                        Icons.folder_outlined,
                                        size: 38,
                                        color: Color(0xFF5A78C5),
                                      ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _saving ? null : _pickCategoryImage,
                      child: const Text('Choose icon'),
                    ),
                    TextField(
                      controller: _nameCtrl,
                      enabled: !_saving,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Category name',
                        errorText: _error,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0A3B48),
                            ),
                            child: _saving
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _editing ? 'Saving...' : 'Creating...',
                                      ),
                                    ],
                                  )
                                : Text(_editing ? 'Save' : 'Create'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_saving)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCategoryImage() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryImagePickerDialog(selectedPresetId: _presetId),
    );
    if (picked == null || !mounted) return;
    setState(() => _presetId = picked);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Category name is required.');
      return;
    }

    final categories = ref.read(vaultSidebarCategoriesProvider);
    final duplicate = categories.any(
      (c) =>
          c.name.toLowerCase() == name.toLowerCase() &&
          c.uuid != widget.existing?.uuid,
    );
    if (duplicate) {
      setState(() => _error = 'That category already exists.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    // Ensure loading UI renders before filesystem work begins.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      final repository = ref.read(kdbxRepositoryProvider);
      late final String groupUuid;
      if (_editing) {
        groupUuid = widget.existing!.uuid;
        await repository.updateGroup(
          groupUuid: groupUuid,
          name: name,
          notes: '$_kCategoryIconNotesPrefix$_presetId|$_colorId',
        );
      } else {
        final rootUuid = repository.rootGroupUuid;
        if (rootUuid == null) {
          throw StateError('Open a vault before adding categories');
        }
        groupUuid = await repository.createGroup(
          parentGroupUuid: rootUuid,
          name: name,
          notes: '$_kCategoryIconNotesPrefix$_presetId|$_colorId',
        );
      }
      final registry = ref.read(databaseRegistryProvider);
      final database = await saveAndSyncDatabase(repository, registry);
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultSidebarCategoriesProvider);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(_CategoryEditorResult(groupUuid: groupUuid, created: !_editing));
      AppSnackBar.success(
        context,
        _editing ? '$name category updated' : '$name category created',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackBar.error(
        context,
        _editing
            ? 'Unable to update category: $error'
            : 'Unable to create category: $error',
      );
    }
  }
}

class _CategoryImagePickerDialog extends StatelessWidget {
  const _CategoryImagePickerDialog({required this.selectedPresetId});

  final String selectedPresetId;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 560),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose icon',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF213247),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _kTotalCategoryImages,
                itemBuilder: (context, index) {
                  final n = index + 1;
                  final presetId = 'img:$n';
                  final selected = presetId == selectedPresetId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).pop(presetId),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF2B7FFF)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/categories/$n.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTypeOption {
  const _ItemTypeOption({
    required this.id,
    required this.label,
    required this.count,
    required this.icon,
    required this.iconColor,
    this.imagePath,
  });

  final String id;
  final String label;
  final int count;
  final IconData icon;
  final Color iconColor;
  final String? imagePath;
}

class _ItemTypeLeadingVisual extends StatelessWidget {
  const _ItemTypeLeadingVisual({required this.option, this.compact = false});

  final _ItemTypeOption option;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 18.0 : 22.0;
    if (option.imagePath != null && option.imagePath!.isNotEmpty) {
      return Image.asset(
        option.imagePath!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Icon(option.icon, size: size, color: option.iconColor),
      );
    }
    return Icon(option.icon, size: size, color: option.iconColor);
  }
}

class _CategoryLeadingVisual extends StatelessWidget {
  const _CategoryLeadingVisual({
    required this.categoryId,
    required this.notes,
    this.compact = false,
  });

  final String categoryId;
  final String notes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 22.0 : 30.0;

    if (categoryId == kCategoryFilterAll) {
      return _RoundedIconBadge(
        size: size,
        icon: Icons.grid_view_rounded,
        iconColor: const Color(0xFF5E6C7E),
        backgroundColor: const Color(0xFFE8EEF9),
      );
    }

    if (categoryId == kCategoryFilterUncategorized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        child: Image.asset(
          'assets/images/categories/383.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              _DefaultCategoryBadge(size: size, compact: compact),
        ),
      );
    }

    final decoded = _decodeCategoryVisualPayload(notes);
    if (decoded == null) {
      return _DefaultCategoryBadge(size: size, compact: compact);
    }

    if (decoded.presetId.startsWith('img:')) {
      final id = decoded.presetId.substring(4).trim();
      if (id.isEmpty) {
        return _DefaultCategoryBadge(size: size, compact: compact);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        child: Image.asset(
          'assets/images/categories/$id.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              _DefaultCategoryBadge(size: size, compact: compact),
        ),
      );
    }

    final colors = _categoryColorForId(decoded.colorId);
    return _RoundedIconBadge(
      size: size,
      icon: _iconForCategoryPresetId(decoded.presetId),
      iconColor: colors.iconColor,
      backgroundColor: colors.fillColor,
    );
  }
}

class _RoundedIconBadge extends StatelessWidget {
  const _RoundedIconBadge({
    required this.size,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });

  final double size;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final compact = size <= 24;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: compact ? 14 : 18, color: iconColor),
    );
  }
}

class _DefaultCategoryBadge extends StatelessWidget {
  const _DefaultCategoryBadge({required this.size, required this.compact});

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _RoundedIconBadge(
      size: size,
      icon: Icons.folder_outlined,
      iconColor: const Color(0xFF5A78C5),
      backgroundColor: const Color(0xFFE8EEF9),
    );
  }
}

({String presetId, String colorId})? _decodeCategoryVisualPayload(
  String? notes,
) {
  final raw = notes?.trim() ?? '';
  if (!raw.startsWith(_kCategoryIconNotesPrefix)) {
    return null;
  }
  final payload = raw.substring(_kCategoryIconNotesPrefix.length);
  final parts = payload.split('|');
  if (parts.length != 2 || parts.any((part) => part.trim().isEmpty)) {
    return null;
  }
  return (presetId: parts[0], colorId: parts[1]);
}

({Color fillColor, Color iconColor}) _categoryColorForId(String colorId) {
  switch (colorId) {
    case 'blue':
      return (
        fillColor: const Color(0xFFE1EDFF),
        iconColor: const Color(0xFF2B7FFF),
      );
    case 'purple':
      return (
        fillColor: const Color(0xFFEEDDFB),
        iconColor: const Color(0xFF8D57B0),
      );
    case 'teal':
      return (
        fillColor: const Color(0xFFD8F3F4),
        iconColor: const Color(0xFF1D9AAF),
      );
    case 'gold':
      return (
        fillColor: const Color(0xFFFFE7B8),
        iconColor: const Color(0xFFDB8A11),
      );
    case 'pink':
      return (
        fillColor: const Color(0xFFF9D6E8),
        iconColor: const Color(0xFFE0539A),
      );
    default:
      return (
        fillColor: const Color(0xFFE8EEF9),
        iconColor: const Color(0xFF5A78C5),
      );
  }
}

/// Maps desktop category icon preset ids to Material icons (desktop uses Tabler).
IconData _iconForCategoryPresetId(String id) {
  switch (id) {
    case 'plus':
      return Icons.add;
    case 'home':
      return Icons.home_outlined;
    case 'school':
      return Icons.school_outlined;
    case 'camping':
      return Icons.cabin;
    case 'shop':
      return Icons.storefront_outlined;
    case 'briefcase':
      return Icons.work_outline;
    case 'scale':
      return Icons.balance;
    case 'tools':
      return Icons.build_outlined;
    case 'pen':
      return Icons.edit_outlined;
    case 'notes':
      return Icons.note_outlined;
    case 'terminal':
      return Icons.terminal;
    case 'cards':
      return Icons.style_rounded;
    case 'key':
      return Icons.key_outlined;
    case 'crown':
      return Icons.emoji_events_outlined;
    case 'basket':
      return Icons.shopping_bag_outlined;
    case 'building':
      return Icons.account_balance;
    case 'settings':
      return Icons.settings_outlined;
    case 'chat':
      return Icons.chat_bubble_outline;
    case 'quote':
      return Icons.format_quote;
    case 'chart':
      return Icons.bar_chart;
    case 'flask':
      return Icons.science_outlined;
    case 'chip':
      return Icons.memory;
    case 'trees':
      return Icons.park_outlined;
    case 'dna':
      return Icons.biotech;
    case 'coin':
      return Icons.monetization_on_outlined;
    case 'gift':
      return Icons.card_giftcard;
    case 'inbox':
      return Icons.inbox_outlined;
    case 'music':
      return Icons.music_note;
    case 'pulse':
      return Icons.favorite_border;
    case 'palette':
      return Icons.palette_outlined;
    case 'globe':
      return Icons.public;
    case 'gem':
      return Icons.diamond_outlined;
    case 'rook':
      return Icons.castle_outlined;
    case 'scissors':
      return Icons.content_cut;
    case 'car':
      return Icons.directions_car_outlined;
    case 'flame':
      return Icons.local_fire_department_outlined;
    case 'dice':
      return Icons.casino;
    case 'sofa':
      return Icons.chair_outlined;
    case 'plane':
      return Icons.flight;
    case 'shield':
      return Icons.shield_outlined;
    case 'paw':
      return Icons.pets;
    case 'planet':
      return Icons.travel_explore_rounded;
    case 'plant':
      return Icons.local_florist_outlined;
    case 'vault':
      return Icons.inventory_2_rounded;
    case 'door':
      return Icons.door_front_door_outlined;
    case 'wave':
      return Icons.waves;
    case 'donut':
      return Icons.cookie_outlined;
    default:
      return Icons.folder_outlined;
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
