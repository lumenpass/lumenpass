import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../domain/import_parsed_item.dart';
import '../application/import_state.dart';
import '../application/import_executor.dart';
import '../../../core/repository/kdbx_repository_provider.dart';
import '../../vault/application/vault_providers.dart';

class ImportPreviewScreen extends ConsumerStatefulWidget {
  const ImportPreviewScreen({
    super.key,
    required this.onClose,
    required this.onStartImport,
  });

  final VoidCallback onClose;
  final VoidCallback onStartImport;

  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ImportMode? _importMode;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      ref.read(importStateProvider.notifier).setPreviewTab(
            _tabController.index == 0
                ? ImportPreviewTab.ready
                : ImportPreviewTab.errors,
          );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final importState = ref.watch(importStateProvider);
    final items = importState.parsedItems;
    final readyItems = items.where((item) => item.isReady).toList();
    final errorItems = items.where((item) => item.hasErrors).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 960,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFCEC7BB)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x295B4638),
              blurRadius: 32,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: const Color(0xFFFFFCF6),
            body: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _buildHeader(importState.fileName),
                const SizedBox(height: 16),
                const _SectionDivider(),
                const SizedBox(height: 16),
                _buildTabBar(errorItems.length),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: <Widget>[
                      _ReadyTab(
                        items: readyItems,
                        onItemChanged: (index, item) {
                          final globalIndex = items.indexOf(item);
                          if (globalIndex >= 0) {
                            ref
                                .read(importStateProvider.notifier)
                                .updateItem(globalIndex, item);
                          }
                        },
                      ),
                      _ErrorsTab(
                        items: errorItems,
                        onItemFixed: (item, corrected) {
                          final globalIndex = items.indexOf(item);
                          if (globalIndex >= 0) {
                            ref
                                .read(importStateProvider.notifier)
                                .fixItem(globalIndex, corrected);
                          }
                        },
                        onForceAllItems: () {
                          ref
                              .read(importStateProvider.notifier)
                              .forceAllItems();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const _SectionDivider(),
                _buildBottomBar(importState, readyItems.length),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader(String? fileName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFAEDE5),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              TablerIcons.eye,
              size: 20,
              color: Color(0xFFFF5B22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Preview Import',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E2021),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fileName != null
                      ? 'File: $fileName'
                      : 'Review and edit items before importing',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF74766F),
                  ),
                ),
              ],
            ),
          ),
          _IconButton(
            icon: TablerIcons.x,
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  // ── Tab Bar ───────────────────────────────────────────────────────────

  Widget _buildTabBar(int errorCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(child: _buildCategorySelector()),
          const SizedBox(width: 16),
          IntrinsicWidth(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF8F3EA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD8D2C7)),
              ),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFFFF5B22),
                  borderRadius: BorderRadius.circular(6),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF74766F),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(2),
                tabs: <Widget>[
                  const Tab(
                    child: Text('Ready to Import'),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('Errors'),
                        if (errorCount > 0) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$errorCount',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category Selector ─────────────────────────────────────────────────

  Widget _buildCategorySelector() {
    final categories = ref.watch(vaultSidebarCategoriesProvider);
    final rootGroupUuid = ref.watch(
      kdbxRepositoryProvider.select((r) => r.rootGroupUuid),
    );
    final selectedUuid = ref.watch(
      importStateProvider.select((s) => s.targetGroupUuid),
    );

    // The effective selection: an explicit category, otherwise Uncategorized
    // (represented by the root group / null).
    final effectiveUuid = selectedUuid ?? rootGroupUuid;
    final selectedName = categories
        .where((c) => c.uuid == effectiveUuid)
        .map((c) => c.name)
        .firstOrNull;
    final label = selectedName ?? 'Uncategorized';

    return Align(
      alignment: Alignment.centerLeft,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: PopupMenuButton<String>(
          tooltip: '',
          offset: const Offset(0, 38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFD8D2C7)),
          ),
          color: Colors.white,
          elevation: 4,
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
          onSelected: (uuid) {
            // The sentinel '__uncategorized__' maps back to the root group.
            ref.read(importStateProvider.notifier).setTargetGroup(
                  uuid == '__uncategorized__' ? rootGroupUuid : uuid,
                );
          },
          itemBuilder: (context) {
            final items = <PopupMenuEntry<String>>[
              _categoryMenuItem(
                value: '__uncategorized__',
                label: 'Uncategorized',
                selected: selectedName == null,
              ),
            ];
            for (final category in categories) {
              items.add(
                _categoryMenuItem(
                  value: category.uuid,
                  label: category.name,
                  selected: category.uuid == effectiveUuid,
                ),
              );
            }
            return items;
          },
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCEC7BB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(TablerIcons.folder,
                    size: 15, color: Color(0xFF5A78C5)),
                const SizedBox(width: 8),
                Text(
                  'Import to:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFA09D95),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E2021),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(TablerIcons.chevron_down,
                    size: 14, color: Color(0xFF74766F)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _categoryMenuItem({
    required String value,
    required String label,
    required bool selected,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: <Widget>[
          Icon(
            value == '__uncategorized__'
                ? TablerIcons.inbox
                : TablerIcons.folder,
            size: 16,
            color: const Color(0xFF5A78C5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? const Color(0xFFFF5B22)
                    : const Color(0xFF4F524E),
              ),
            ),
          ),
          if (selected) ...<Widget>[
            const SizedBox(width: 8),
            const Icon(TablerIcons.check, size: 14, color: Color(0xFFFF5B22)),
          ],
        ],
      ),
    );
  }

  // ── Bottom Bar ────────────────────────────────────────────────────────

  void _showImportModeInfo() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFFFFFCF6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Import Modes Explained',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E2021),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Replace',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E2021),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Clean Import. All existing items will be permanently removed and replaced by the imported items. Use this if you want to start fresh.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF686B67),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Append',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E2021),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Append Items. The imported items will be added alongside your existing items without affecting them. Recommended for merging data.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF686B67),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5B22),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(ImportState state, int readyCount) {
    final canImport = canStartImport(state) && _importMode != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          const Text(
            'Import Mode:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF686B67),
            ),
          ),
          const SizedBox(width: 8),
          Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
            child: PopupMenuButton<ImportMode>(
              tooltip: '',
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFD8D2C7)),
              ),
              color: Colors.white,
              elevation: 4,
              onSelected: (mode) {
                setState(() {
                  _importMode = mode;
                });
                ref.read(importStateProvider.notifier).setImportMode(mode);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: ImportMode.replace,
                  height: 40,
                  child: Row(
                    children: [
                      Icon(TablerIcons.replace,
                          size: 18,
                          color: _importMode == ImportMode.replace
                              ? const Color(0xFFFF5B22)
                              : const Color(0xFF74766F)),
                      const SizedBox(width: 8),
                      Text('Replace',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: _importMode == ImportMode.replace
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: _importMode == ImportMode.replace
                                  ? const Color(0xFFFF5B22)
                                  : const Color(0xFF4F524E))),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: ImportMode.append,
                  height: 40,
                  child: Row(
                    children: [
                      Icon(TablerIcons.row_insert_bottom,
                          size: 18,
                          color: _importMode == ImportMode.append
                              ? const Color(0xFFFF5B22)
                              : const Color(0xFF74766F)),
                      const SizedBox(width: 8),
                      Text('Append',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: _importMode == ImportMode.append
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: _importMode == ImportMode.append
                                  ? const Color(0xFFFF5B22)
                                  : const Color(0xFF4F524E))),
                    ],
                  ),
                ),
              ],
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _importMode != null
                        ? const Color(0xFFFF5B22)
                        : const Color(0xFFCEC7BB),
                    width: _importMode != null ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_importMode == ImportMode.replace)
                      const Icon(TablerIcons.replace,
                          size: 16, color: Color(0xFFFF5B22))
                    else if (_importMode == ImportMode.append)
                      const Icon(TablerIcons.row_insert_bottom,
                          size: 16, color: Color(0xFFFF5B22)),
                    if (_importMode != null) const SizedBox(width: 6),
                    Text(
                      _importMode == ImportMode.replace
                          ? 'Replace'
                          : _importMode == ImportMode.append
                              ? 'Append'
                              : 'Select mode',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _importMode != null
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: _importMode != null
                            ? const Color(0xFFFF5B22)
                            : const Color(0xFFA09D95),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      TablerIcons.chevron_down,
                      size: 16,
                      color: _importMode != null
                          ? const Color(0xFFFF5B22)
                          : const Color(0xFF74766F),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _showImportModeInfo,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(TablerIcons.info_circle,
                  size: 20, color: Color(0xFFA09D95)),
            ),
          ),
          const Spacer(),
          _FooterButton(
            label: 'Back',
            backgroundColor: Colors.transparent,
            textColor: const Color(0xFF74766F),
            borderColor: const Color(0xFFCEC7BB),
            onTap: () {
              ref
                  .read(importStateProvider.notifier)
                  .goBackToProviderSelection();
              widget.onClose();
            },
          ),
          const SizedBox(width: 10),
          _FooterButton(
            label: 'Next',
            backgroundColor:
                canImport ? const Color(0xFFFF5B22) : const Color(0xFFD8D2C7),
            textColor: canImport ? Colors.white : const Color(0xFFA09D95),
            onTap: canImport ? widget.onStartImport : null,
          ),
        ],
      ),
    );
  }

  bool canStartImport(ImportState state) => state.readyCount > 0;
}

// ════════════════════════════════════════════════════════════════════════════
// Ready Tab — DataTable
// ════════════════════════════════════════════════════════════════════════════

class _ReadyTab extends StatefulWidget {
  const _ReadyTab({
    required this.items,
    required this.onItemChanged,
  });

  final List<ImportParsedItem> items;
  final void Function(int index, ImportParsedItem item) onItemChanged;

  @override
  State<_ReadyTab> createState() => _ReadyTabState();
}

class _ReadyTabState extends State<_ReadyTab> {
  late List<ImportParsedItem> _items;
  int _currentPage = 0;
  int _pageSize = 50;
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _items = List<ImportParsedItem>.from(widget.items);
  }

  void _sort<T>(Comparable<T> Function(ImportParsedItem item) getField,
      int columnIndex, bool ascending) {
    _items.sort((a, b) {
      final aValue = getField(a);
      final bValue = getField(b);
      return ascending
          ? Comparable.compare(aValue, bValue)
          : Comparable.compare(bValue, aValue);
    });
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _currentPage = 0;
    });
  }

  @override
  void didUpdateWidget(covariant _ReadyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _items = List<ImportParsedItem>.from(widget.items);
      final maxPage = (_items.length - 1) ~/ _pageSize;
      if (_currentPage > maxPage) {
        _currentPage = maxPage >= 0 ? maxPage : 0;
      }
    }
  }

  Future<void> _editItemField(
      int index, String fieldName, String currentValue) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFFFFFCF6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit $fieldName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E2021),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1E2021),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8F3EA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: Color(0xFFFF5B22), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF74766F),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5B22),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null && mounted) {
      final item = _items[index];
      ImportParsedItem updated = item;
      if (fieldName == 'Title') {
        updated = item.copyWith(title: result);
      } else if (fieldName == 'Username') {
        updated = item.copyWith(username: result);
      } else if (fieldName == 'Password') {
        updated = item.copyWith(password: result);
      } else if (fieldName == 'URL') {
        updated = item.copyWith(url: result);
      }
      widget.onItemChanged(index, updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(TablerIcons.inbox, size: 40, color: const Color(0xFFCEC7BB)),
            const SizedBox(height: 12),
            Text(
              'No items ready for import',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFA09D95),
              ),
            ),
          ],
        ),
      );
    }

    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize < _items.length)
        ? startIndex + _pageSize
        : _items.length;
    final currentItems = _items.sublist(startIndex, endIndex);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Scrollbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minWidth: constraints.maxWidth),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            iconTheme:
                                const IconThemeData(color: Color(0xFF4F524E)),
                          ),
                          child: DataTable(
                            headingRowHeight: 40,
                            sortColumnIndex: _sortColumnIndex,
                            sortAscending: _sortAscending,
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFFE0E7FF),
                            ),
                            headingTextStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4F524E),
                            ),
                            dataTextStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF1E2021),
                            ),
                            horizontalMargin: 16,
                            columnSpacing: 24,
                            border: TableBorder(
                              horizontalInside: BorderSide(
                                  color: const Color(0xFFF0F0F2), width: 1),
                            ),
                            columns: <DataColumn>[
                              DataColumn(
                                label: const Text('#'),
                                onSort: (columnIndex, ascending) {
                                  setState(() {
                                    _sortColumnIndex = columnIndex;
                                    _sortAscending = ascending;
                                    _items = List.from(widget.items);
                                    if (!ascending) {
                                      _items = _items.reversed.toList();
                                    }
                                    _currentPage = 0;
                                  });
                                },
                              ),
                              DataColumn(
                                label: const Text('Item Type'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.itemType,
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Title'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>(
                                        (i) => i.title, columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Username'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.username ?? '',
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Password'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.password ?? '',
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('URL'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.url ?? '',
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Notes'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.notes ?? '',
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('OTP'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.otpAuthUrl ?? '',
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Tags'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.tags.join(', '),
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Custom Fields'),
                                onSort: (columnIndex, ascending) => _sort<num>(
                                    (i) => i.customFields.length,
                                    columnIndex,
                                    ascending),
                              ),
                            ],
                            rows: List<DataRow>.generate(
                              currentItems.length,
                              (index) {
                                final item = currentItems[index];
                                final globalIndex = startIndex + index;
                                return DataRow(
                                  color:
                                      WidgetStateProperty.resolveWith<Color?>(
                                    (states) {
                                      if (states
                                          .contains(WidgetState.hovered)) {
                                        return const Color(0xFFFFF3E8);
                                      }
                                      return globalIndex.isOdd
                                          ? const Color(0xFFF8F3EA)
                                          : Colors.white;
                                    },
                                  ),
                                  cells: <DataCell>[
                                    DataCell(Text(
                                      '${globalIndex + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFA09D95),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 170),
                                        child: _ItemTypeDropdown(
                                          value: item.itemType,
                                          onChanged: (typeId) {
                                            widget.onItemChanged(
                                              globalIndex,
                                              item.copyWith(itemType: typeId),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 200),
                                        child: _HoverEditableCell(
                                          text: item.title,
                                          isPlaceholder: false,
                                          textStyle: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1E2021),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex, 'Title', item.title),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 200),
                                        child: _HoverEditableCell(
                                          text: item.username ?? '—',
                                          isPlaceholder: !item.hasUsername,
                                          textStyle: TextStyle(
                                            color: item.hasUsername
                                                ? const Color(0xFF1E2021)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex,
                                              'Username',
                                              item.username ?? ''),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 140),
                                        child: _HoverEditableCell(
                                          text: item.hasPassword
                                              ? '••••••••'
                                              : '—',
                                          isPlaceholder: !item.hasPassword,
                                          textStyle: TextStyle(
                                            color: item.hasPassword
                                                ? const Color(0xFF1E2021)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex,
                                              'Password',
                                              item.password ?? ''),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 250),
                                        child: _HoverEditableCell(
                                          text: item.url ?? '—',
                                          isPlaceholder: !item.hasUrl,
                                          textStyle: TextStyle(
                                            color: item.hasUrl
                                                ? const Color(0xFF2563EB)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex,
                                              'URL',
                                              item.url ?? ''),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 200),
                                        child: _HoverEditableCell(
                                          text: item.notes != null &&
                                                  item.notes!.trim().isNotEmpty
                                              ? item.notes!
                                                  .replaceAll('\n', ' ')
                                              : '—',
                                          isPlaceholder: item.notes == null ||
                                              item.notes!.trim().isEmpty,
                                          textStyle: TextStyle(
                                            color: item.notes != null &&
                                                    item.notes!
                                                        .trim()
                                                        .isNotEmpty
                                                ? const Color(0xFF1E2021)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex,
                                              'Notes',
                                              item.notes ?? ''),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 180),
                                        child: Text(
                                          item.otpAuthUrl != null &&
                                                  item.otpAuthUrl!
                                                      .trim()
                                                      .isNotEmpty
                                              ? '✓ Configured'
                                              : '—',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: item.otpAuthUrl != null &&
                                                    item.otpAuthUrl!
                                                        .trim()
                                                        .isNotEmpty
                                                ? const Color(0xFF16A34A)
                                                : const Color(0xFFCEC7BB),
                                            fontWeight:
                                                item.otpAuthUrl != null &&
                                                        item.otpAuthUrl!
                                                            .trim()
                                                            .isNotEmpty
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 180),
                                        child: Text(
                                          item.tags.isNotEmpty
                                              ? item.tags.join(', ')
                                              : '—',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: item.tags.isNotEmpty
                                                ? const Color(0xFF1E2021)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 140),
                                        child: Text(
                                          item.customFields.isNotEmpty
                                              ? '${item.customFields.length} field${item.customFields.length > 1 ? 's' : ''}'
                                              : '—',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: item.customFields.isNotEmpty
                                                ? const Color(0xFF1E2021)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _buildPagination(),
      ],
    );
  }

  Widget _buildPagination() {
    final totalItems = _items.length;
    final totalPages = (totalItems / _pageSize).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: const Color(0xFFD8D2C7))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Total items: $totalItems',
            style: const TextStyle(fontSize: 13, color: Color(0xFF74766F)),
          ),
          const SizedBox(width: 24),
          const Text(
            'Items per page:',
            style: TextStyle(fontSize: 13, color: Color(0xFF74766F)),
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _pageSize,
            isDense: true,
            dropdownColor: const Color(0xFFFFFCF6),
            underline: const SizedBox(),
            items: [10, 20, 50, 100].map((size) {
              return DropdownMenuItem<int>(
                value: size,
                child: Text('$size',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF1E2021))),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _pageSize = value;
                  _currentPage = 0;
                });
              }
            },
          ),
          const SizedBox(width: 24),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: _currentPage > 0
                ? () {
                    setState(() {
                      _currentPage--;
                    });
                  }
                : null,
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Text(
            '${_currentPage + 1} of ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF74766F)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: _currentPage < totalPages - 1
                ? () {
                    setState(() {
                      _currentPage++;
                    });
                  }
                : null,
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Errors Tab — Expandable error cards with inline editing
// ════════════════════════════════════════════════════════════════════════════

class _ErrorsTab extends StatefulWidget {
  const _ErrorsTab({
    required this.items,
    required this.onItemFixed,
    required this.onForceAllItems,
  });

  final List<ImportParsedItem> items;
  final void Function(ImportParsedItem item, ImportParsedItem corrected)
      onItemFixed;
  final VoidCallback onForceAllItems;

  @override
  State<_ErrorsTab> createState() => _ErrorsTabState();
}

class _LocalErrorItem {
  final ImportParsedItem original;
  ImportParsedItem current;
  bool isResolved;

  _LocalErrorItem(this.original, this.current, {this.isResolved = false});
}

class _ErrorsTabState extends State<_ErrorsTab> {
  late List<_LocalErrorItem> _items;
  int _currentPage = 0;
  int _pageSize = 50;
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map((i) => _LocalErrorItem(i, i)).toList();
  }

  void _sort<T>(Comparable<T> Function(ImportParsedItem item) getField,
      int columnIndex, bool ascending) {
    _items.sort((a, b) {
      final aValue = getField(a.current);
      final bValue = getField(b.current);
      return ascending
          ? Comparable.compare(aValue, bValue)
          : Comparable.compare(bValue, aValue);
    });
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _currentPage = 0;
    });
  }

  @override
  void didUpdateWidget(covariant _ErrorsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _items = widget.items.map((i) => _LocalErrorItem(i, i)).toList();
      final maxPage = (_items.length - 1) ~/ _pageSize;
      if (_currentPage > maxPage) {
        _currentPage = maxPage >= 0 ? maxPage : 0;
      }
    }
  }

  Future<void> _editItemField(
      int index, String fieldName, String currentValue) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFFFFFCF6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit $fieldName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E2021),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1E2021),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8F3EA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: Color(0xFFFF5B22), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF74766F),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5B22),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null && mounted) {
      final localItem = _items[index];
      ImportParsedItem updated = localItem.current;
      if (fieldName == 'Title') {
        updated = updated.copyWith(title: result);
      } else if (fieldName == 'Username') {
        updated = updated.copyWith(username: result);
      } else if (fieldName == 'Password') {
        updated = updated.copyWith(password: result);
      } else if (fieldName == 'URL') {
        updated = updated.copyWith(url: result);
      } else if (fieldName == 'Notes') {
        updated = updated.copyWith(notes: result);
      }

      setState(() {
        localItem.current = updated;
      });
    }
  }

  void _resolveItem(int index) async {
    final localItem = _items[index];
    final corrected = localItem.current.copyWith();
    corrected.validate();

    if (corrected.hasErrors) {
      setState(() {
        localItem.current = corrected;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(corrected.validationErrors.join('\n')),
          backgroundColor: const Color(0xFFCC2929),
        ),
      );
    } else {
      setState(() {
        localItem.current = corrected;
        localItem.isResolved = true;
      });

      await Future.delayed(const Duration(milliseconds: 1000));

      if (mounted) {
        widget.onItemFixed(localItem.original, corrected);
      }
    }
  }

  void _forceItem(int index) async {
    final localItem = _items[index];
    final corrected = localItem.current.copyWith(isForced: true);

    setState(() {
      localItem.current = corrected;
      localItem.isResolved = true;
    });

    await Future.delayed(const Duration(milliseconds: 1000));

    if (mounted) {
      widget.onItemFixed(localItem.original, corrected);
    }
  }

  void _forceAllItems() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFFFFFCF6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(TablerIcons.shield_chevron,
                        color: Color(0xFFDC2626), size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Force Import All',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Color(0xFF1E2021),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to force import all unresolved items?\n\nItems with missing titles will use "Untitled", and items without credentials will be imported as-is. This action cannot be undone.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF686B67),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: Color(0xFF74766F),
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Force Import All',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true && mounted) {
      widget.onForceAllItems();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(TablerIcons.circle_check,
                size: 40, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text(
              'No errors found',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFA09D95),
              ),
            ),
          ],
        ),
      );
    }

    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize < _items.length)
        ? startIndex + _pageSize
        : _items.length;
    final currentItems = _items.sublist(startIndex, endIndex);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Scrollbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minWidth: constraints.maxWidth),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            iconTheme:
                                const IconThemeData(color: Color(0xFF991B1B)),
                          ),
                          child: DataTable(
                            headingRowHeight: 40,
                            dataRowMinHeight: 56,
                            dataRowMaxHeight: 80,
                            sortColumnIndex: _sortColumnIndex,
                            sortAscending: _sortAscending,
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFFFEE2E2),
                            ),
                            headingTextStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF991B1B),
                            ),
                            dataTextStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF1E2021),
                            ),
                            horizontalMargin: 16,
                            columnSpacing: 24,
                            border: TableBorder(
                              horizontalInside: BorderSide(
                                  color: const Color(0xFFF0F0F2), width: 1),
                            ),
                            columns: <DataColumn>[
                              DataColumn(
                                label: const Text('#'),
                                onSort: (columnIndex, ascending) {
                                  setState(() {
                                    _sortColumnIndex = columnIndex;
                                    _sortAscending = ascending;
                                    _items = widget.items
                                        .map((i) => _LocalErrorItem(i, i))
                                        .toList();
                                    if (!ascending) {
                                      _items = _items.reversed.toList();
                                    }
                                    _currentPage = 0;
                                  });
                                },
                              ),
                              const DataColumn(label: Text('Error')),
                              DataColumn(
                                label: const Text('Item Type'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.itemType,
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Title'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>(
                                        (i) => i.title, columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Username'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.username ?? '',
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Password'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.password ?? '',
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('URL'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.url ?? '',
                                        columnIndex, ascending),
                              ),
                              DataColumn(
                                label: const Text('Notes'),
                                onSort: (columnIndex, ascending) =>
                                    _sort<String>((i) => i.notes ?? '',
                                        columnIndex, ascending),
                              ),
                            ],
                            rows: List<DataRow>.generate(
                              currentItems.length,
                              (index) {
                                final localItem = currentItems[index];
                                final item = localItem.current;
                                final globalIndex = startIndex + index;
                                return DataRow(
                                  color:
                                      WidgetStateProperty.resolveWith<Color?>(
                                    (states) {
                                      if (localItem.isResolved) {
                                        return const Color(
                                            0xFFF0FDF4); // Light green background
                                      }
                                      if (states
                                          .contains(WidgetState.hovered)) {
                                        return const Color(0xFFFEF2F2);
                                      }
                                      return globalIndex.isOdd
                                          ? const Color(0xFFF8F3EA)
                                          : Colors.white;
                                    },
                                  ),
                                  cells: <DataCell>[
                                    DataCell(Text(
                                      '${globalIndex + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFA09D95),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 250),
                                        child: localItem.isResolved
                                            ? Row(
                                                children: [
                                                  const Icon(
                                                      TablerIcons.circle_check,
                                                      size: 16,
                                                      color: Color(0xFF16A34A)),
                                                  const SizedBox(width: 6),
                                                  const Text(
                                                    'Resolved',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Color(0xFF16A34A),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                                top: 2),
                                                        child: Icon(
                                                            TablerIcons
                                                                .alert_triangle,
                                                            size: 14,
                                                            color: Color(
                                                                0xFFDC2626)),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          item.validationErrors
                                                              .join('\n'),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 12,
                                                            color: Color(
                                                                0xFFDC2626),
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    children: [
                                                      InkWell(
                                                        onTap: () =>
                                                            _resolveItem(
                                                                globalIndex),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 4,
                                                                  horizontal:
                                                                      8),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                0xFFEFF6FF),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6),
                                                            border: Border.all(
                                                                color: const Color(
                                                                    0xFFBFDBFE)),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                  TablerIcons
                                                                      .wand,
                                                                  size: 12,
                                                                  color: Color(
                                                                      0xFF2563EB)),
                                                              const SizedBox(
                                                                  width: 4),
                                                              const Text(
                                                                'Resolve',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  color: Color(
                                                                      0xFF2563EB),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      InkWell(
                                                        onTap: () => _forceItem(
                                                            globalIndex),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 4,
                                                                  horizontal:
                                                                      8),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: const Color(
                                                                0xFFFEF2F2),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        6),
                                                            border: Border.all(
                                                                color: const Color(
                                                                    0xFFFECACA)),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                  TablerIcons
                                                                      .shield_chevron,
                                                                  size: 12,
                                                                  color: Color(
                                                                      0xFFDC2626)),
                                                              const SizedBox(
                                                                  width: 4),
                                                              const Text(
                                                                'Force',
                                                                style:
                                                                    TextStyle(
                                                                  fontSize: 11,
                                                                  color: Color(
                                                                      0xFFDC2626),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 170),
                                        child: _ItemTypeDropdown(
                                          value: item.itemType,
                                          onChanged: (typeId) {
                                            setState(() {
                                              localItem.current = localItem
                                                  .current
                                                  .copyWith(itemType: typeId);
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 200),
                                        child: _HoverEditableCell(
                                          text: item.title,
                                          isPlaceholder: false,
                                          textStyle: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1E2021),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex, 'Title', item.title),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 200),
                                        child: _HoverEditableCell(
                                          text: item.username ?? '—',
                                          isPlaceholder: !item.hasUsername,
                                          textStyle: TextStyle(
                                            color: item.hasUsername
                                                ? const Color(0xFF1E2021)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex,
                                              'Username',
                                              item.username ?? ''),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 140),
                                        child: _HoverEditableCell(
                                          text: item.hasPassword
                                              ? '••••••••'
                                              : '—',
                                          isPlaceholder: !item.hasPassword,
                                          textStyle: TextStyle(
                                            color: item.hasPassword
                                                ? const Color(0xFF1E2021)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex,
                                              'Password',
                                              item.password ?? ''),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 250),
                                        child: _HoverEditableCell(
                                          text: item.url ?? '—',
                                          isPlaceholder: !item.hasUrl,
                                          textStyle: TextStyle(
                                            color: item.hasUrl
                                                ? const Color(0xFF2563EB)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex,
                                              'URL',
                                              item.url ?? ''),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 200),
                                        child: _HoverEditableCell(
                                          text: item.notes != null &&
                                                  item.notes!.trim().isNotEmpty
                                              ? item.notes!
                                                  .replaceAll('\n', ' ')
                                              : '—',
                                          isPlaceholder: item.notes == null ||
                                              item.notes!.trim().isEmpty,
                                          textStyle: TextStyle(
                                            color: item.notes != null &&
                                                    item.notes!
                                                        .trim()
                                                        .isNotEmpty
                                                ? const Color(0xFF1E2021)
                                                : const Color(0xFFCEC7BB),
                                          ),
                                          onEdit: () => _editItemField(
                                              globalIndex,
                                              'Notes',
                                              item.notes ?? ''),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _buildPagination(),
      ],
    );
  }

  Widget _buildPagination() {
    final totalItems = _items.length;
    final totalPages = (totalItems / _pageSize).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: const Color(0xFFD8D2C7))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(TablerIcons.info_circle,
                    size: 14, color: Color(0xFF74766F)),
                const SizedBox(width: 6),
                const Text(
                  'Unresolved items will not be imported.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF74766F)),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _forceAllItems,
                  icon: const Icon(TablerIcons.shield_chevron, size: 14),
                  label: const Text('Force import all'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Total items: $totalItems',
            style: const TextStyle(fontSize: 13, color: Color(0xFF74766F)),
          ),
          const SizedBox(width: 24),
          const Text(
            'Items per page:',
            style: TextStyle(fontSize: 13, color: Color(0xFF74766F)),
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _pageSize,
            isDense: true,
            dropdownColor: const Color(0xFFFFFCF6),
            underline: const SizedBox(),
            items: [10, 20, 50, 100].map((size) {
              return DropdownMenuItem<int>(
                value: size,
                child: Text('$size',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF1E2021))),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _pageSize = value;
                  _currentPage = 0;
                });
              }
            },
          ),
          const SizedBox(width: 24),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: _currentPage > 0
                ? () {
                    setState(() {
                      _currentPage--;
                    });
                  }
                : null,
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Text(
            '${_currentPage + 1} of ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF74766F)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: _currentPage < totalPages - 1
                ? () {
                    setState(() {
                      _currentPage++;
                    });
                  }
                : null,
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ════════════════════════════════════════════════════════════════════════════

/// A thin full-bleed rule used to separate the modal's header, body, and
/// footer regions.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      color: Color(0xFFD8D2C7),
    );
  }
}

/// Item type options offered in the import preview. Ids and labels mirror the
/// platform's new-item taxonomy (`VaultItemType` / the add-item picker) so an
/// imported entry can be re-typed to any of the user-creatable kinds.
class _ImportItemType {
  const _ImportItemType({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

const List<_ImportItemType> _importItemTypes = <_ImportItemType>[
  _ImportItemType(
    id: 'login',
    label: 'Login',
    icon: TablerIcons.lock,
    color: Color(0xFF2DA8B6),
  ),
  _ImportItemType(
    id: 'secure-note',
    label: 'Secure Note',
    icon: TablerIcons.notes,
    color: Color(0xFFE0A433),
  ),
  _ImportItemType(
    id: 'credit-card',
    label: 'Credit Card',
    icon: TablerIcons.credit_card,
    color: Color(0xFF4A9EE8),
  ),
  _ImportItemType(
    id: 'identity',
    label: 'Identity',
    icon: TablerIcons.id,
    color: Color(0xFF56B676),
  ),
  _ImportItemType(
    id: 'ssh-key',
    label: 'SSH Key',
    icon: TablerIcons.key,
    color: Color(0xFF1D6570),
  ),
  _ImportItemType(
    id: 'bank-account',
    label: 'Bank Account',
    icon: TablerIcons.building_bank,
    color: Color(0xFF1F9A76),
  ),
];

_ImportItemType _importItemTypeById(String id) {
  for (final type in _importItemTypes) {
    if (type.id == id) return type;
  }
  return _importItemTypes.first;
}

class _ItemTypeDropdown extends StatelessWidget {
  const _ItemTypeDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = _importItemTypeById(value);
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: PopupMenuButton<String>(
        tooltip: '',
        offset: const Offset(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFD8D2C7)),
        ),
        color: Colors.white,
        elevation: 4,
        onSelected: onChanged,
        itemBuilder: (context) => _importItemTypes.map((type) {
          final selected = type.id == value;
          return PopupMenuItem<String>(
            value: type.id,
            height: 40,
            child: Row(
              children: <Widget>[
                Icon(type.icon, size: 16, color: type.color),
                const SizedBox(width: 8),
                Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? const Color(0xFFFF5B22)
                        : const Color(0xFF4F524E),
                  ),
                ),
                if (selected) ...<Widget>[
                  const Spacer(),
                  const Icon(TablerIcons.check,
                      size: 14, color: Color(0xFFFF5B22)),
                ],
              ],
            ),
          );
        }).toList(),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCEC7BB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(current.icon, size: 14, color: current.color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  current.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4F524E),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(TablerIcons.chevron_down,
                  size: 14, color: Color(0xFF74766F)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverEditableCell extends StatefulWidget {
  const _HoverEditableCell({
    required this.text,
    required this.onEdit,
    this.textStyle,
    this.isPlaceholder = false,
  });

  final String text;
  final VoidCallback onEdit;
  final TextStyle? textStyle;
  final bool isPlaceholder;

  @override
  State<_HoverEditableCell> createState() => _HoverEditableCellState();
}

class _HoverEditableCellState extends State<_HoverEditableCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Container(
            width: double.infinity,
            alignment: Alignment.centerLeft,
            child: Text(
              widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.textStyle,
            ),
          ),
          if (_hovered)
            Positioned(
              right: 0,
              child: Material(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: widget.onEdit,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(
                      TablerIcons.pencil,
                      size: 14,
                      color: Color(0xFFFF5B22),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.label,
    required this.controller,
    required this.icon,
    this.isRequired = false,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 100,
          child: Row(
            children: <Widget>[
              Icon(icon, size: 13, color: const Color(0xFFA09D95)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF74766F),
                ),
              ),
              if (isRequired)
                const Text(
                  ' *',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1E2021),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF8F3EA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFFF5B22), width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xFFF3EDE4) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: const Color(0xFFA09D95)),
          ),
        ),
      ),
    );
  }
}

class _FooterButton extends StatefulWidget {
  const _FooterButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  State<_FooterButton> createState() => _FooterButtonState();
}

class _FooterButtonState extends State<_FooterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? widget.onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
            decoration: BoxDecoration(
              color: _hovered && isEnabled
                  ? widget.backgroundColor.withValues(alpha: 0.85)
                  : widget.backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: widget.borderColor != null
                  ? Border.all(color: widget.borderColor!)
                  : null,
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: widget.textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
