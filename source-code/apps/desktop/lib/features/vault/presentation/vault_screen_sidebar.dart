part of 'vault_screen.dart';

const Set<String> _hiddenSidebarCategoryIds = <String>{
  'document',
  'api-credential',
  'server',
  'wifi-password',
  'passport',
};
const Color _sidebarBackgroundColor = Color(0xFF0A3B48);
const Color _sidebarBorderColor = Color(0xFF145163);
const Color _sidebarTextPrimary = Color(0xFFE3EEF3);
const Color _sidebarTextSecondary = Color(0xFFA7BBC6);
const Color _sidebarSelectedText = Color(0xFFF4FAFD);
const Color _sidebarSelectedItemBackground = Color(0x335E8A9D);

class _SidebarPane extends ConsumerWidget {
  const _SidebarPane({
    required this.onLockVault,
    required this.onOpenAddCategoryModal,
    required this.onEditCategory,
    required this.onDeleteCategory,
  });

  final VoidCallback onLockVault;
  final VoidCallback onOpenAddCategoryModal;
  final void Function(
          ({String uuid, String name, String notes, int count}) category)
      onEditCategory;
  final void Function(
          ({String uuid, String name, String notes, int count}) category)
      onDeleteCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = ref.watch(vaultDatabaseEntriesProvider).length;
    final uncategorizedCount = ref.watch(vaultUncategorizedCountProvider);
    final sidebarCounts = ref.watch(vaultSidebarItemCountsProvider);
    final categories = ref.watch(vaultSidebarCategoriesProvider);
    final tags = ref.watch(vaultSidebarTagsProvider);
    final selectedItemTypeId = ref.watch(vaultSelectedItemTypeIdProvider);
    final selectedGroupUuid = ref.watch(vaultSelectedGroupProvider);
    final selectedTag = ref.watch(vaultSelectedTagProvider);
    final trashCount = ref.watch(vaultTrashEntryCountProvider);
    final totpCount = ref.watch(vaultTotpCountProvider);
    final passkeyCount = ref.watch(vaultPasskeyCountProvider);
    final visibleItemTypes = _allNewItemTypes
        .where((item) => !_hiddenSidebarCategoryIds.contains(item.id))
        .toList(growable: false);

    final activeDatabase = ref.watch(activeDatabaseProvider);
    final registry = ref.watch(databaseRegistryProvider);
    DatabaseRecord? record;
    if (activeDatabase != null) {
      final path = activeDatabase.path;
      for (final r in registry) {
        if (r.databasePath == path) {
          record = r;
          break;
        }
      }
    }
    final String activeName = activeDatabase?.name.trim() ?? '';
    final String recordNickname = record?.nickname.trim() ?? '';
    final String databaseName = activeDatabase == null
        ? 'Vault'
        : activeName.isNotEmpty
            ? activeName
            : recordNickname.isNotEmpty
                ? recordNickname
                : 'Vault';

    return Container(
      width: 230,
      decoration: const BoxDecoration(
        color: _sidebarBackgroundColor,
        border: Border(
          right: BorderSide(color: _sidebarBorderColor),
        ),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: _VaultStorageIcon(record: record),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    databaseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      12,
                      _sidebarTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _AppTooltip(
                  message: 'Switch Vault',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _showSwitchVaultModal(context),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        TablerIcons.switch_horizontal,
                        size: 16,
                        color: _sidebarTextSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: _SidebarItemTypeDropdown(
              totalCount: totalCount,
              itemTypes: visibleItemTypes,
              sidebarCounts: sidebarCounts,
            ),
          ),

          // ── Scrollable middle section ──────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 4),
              children: <Widget>[
                // — Categories header —
                _SidebarSectionHeader(
                  label: 'Categories',
                  action: _SidebarHeaderButton(
                    icon: TablerIcons.circle_plus,
                    onPressed: onOpenAddCategoryModal,
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _SidebarItem(
                    icon: TablerIcons.layout_grid,
                    iconColor: const Color(0xFF5E6C7E),
                    title: 'All ($totalCount)',
                    selected: selectedGroupUuid == kCategoryFilterAll,
                    onTap: () {
                      ref.read(vaultSelectedGroupProvider.notifier).state =
                          kCategoryFilterAll;
                      ref.read(vaultSelectedItemTypeIdProvider.notifier).state =
                          null;
                      ref.read(vaultSelectedTagProvider.notifier).state = null;
                    },
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _SidebarItem(
                    icon: TablerIcons.inbox,
                    iconColor: const Color(0xFF5E6C7E),
                    imageAsset: 'assets/images/categories/383.png',
                    title: 'Uncategorized ($uncategorizedCount)',
                    selected: selectedGroupUuid == kCategoryFilterUncategorized,
                    onTap: () {
                      ref.read(vaultSelectedGroupProvider.notifier).state =
                          kCategoryFilterUncategorized;
                      ref.read(vaultSelectedItemTypeIdProvider.notifier).state =
                          null;
                      ref.read(vaultSelectedTagProvider.notifier).state = null;
                    },
                  ),
                ),

                for (final category in categories)
                  () {
                    final visual = _categoryVisualForNotes(category.notes);
                    final imageAsset =
                        _categoryImagePathForNotes(category.notes);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SidebarCategoryItem(
                        icon: visual.icon,
                        iconColor: visual.iconColor,
                        iconBadgeColor:
                            imageAsset != null ? null : visual.badgeColor,
                        imageAsset: imageAsset,
                        title: '${category.name} (${category.count})',
                        selected: selectedGroupUuid == category.uuid,
                        onTap: () {
                          ref.read(vaultSelectedGroupProvider.notifier).state =
                              category.uuid;
                          ref
                              .read(vaultSelectedItemTypeIdProvider.notifier)
                              .state = null;
                          ref.read(vaultSelectedTagProvider.notifier).state =
                              null;
                        },
                        onEdit: () => onEditCategory(category),
                        onDelete: () => onDeleteCategory(category),
                      ),
                    );
                  }(),
                const SizedBox(height: 22),

                // — Quick Access header —
                const _SidebarSectionHeader(label: 'Quick Access'),

                // — TOTP —
                _SidebarItem(
                  icon: TablerIcons.clock,
                  iconColor: const Color(0xFFD97706),
                  title: 'TOTP ($totpCount)',
                  selected: selectedItemTypeId == kQuickFilterTotp,
                  onTap: () {
                    ref.read(vaultSelectedItemTypeIdProvider.notifier).state =
                        kQuickFilterTotp;
                    ref.read(vaultSelectedGroupProvider.notifier).state = null;
                    ref.read(vaultSelectedTagProvider.notifier).state = null;
                  },
                ),

                // — Passkeys —
                _SidebarItem(
                  icon: TablerIcons.fingerprint,
                  iconColor: const Color(0xFF0891B2),
                  title: 'Passkeys ($passkeyCount)',
                  selected: selectedItemTypeId == kQuickFilterPasskeys,
                  onTap: () {
                    ref.read(vaultSelectedItemTypeIdProvider.notifier).state =
                        kQuickFilterPasskeys;
                    ref.read(vaultSelectedGroupProvider.notifier).state = null;
                    ref.read(vaultSelectedTagProvider.notifier).state = null;
                  },
                ),

                _SidebarItem(
                  icon: TablerIcons.shield_check,
                  iconColor: const Color(0xFFDC2626),
                  title: 'Password Audits',
                  selected: selectedItemTypeId == kQuickFilterPasswordAudits,
                  onTap: () {
                    ref.read(vaultSelectedItemTypeIdProvider.notifier).state =
                        kQuickFilterPasswordAudits;
                    ref.read(vaultSelectedGroupProvider.notifier).state = null;
                    ref.read(vaultSelectedTagProvider.notifier).state = null;
                    ref
                        .read(vaultPasswordAuditSelectionProvider.notifier)
                        .state = null;
                    ref
                        .read(vaultPasswordAuditDuplicateGroupSelectionProvider
                            .notifier)
                        .state = null;
                  },
                ),

                const SizedBox(height: 22),

                const _SidebarSectionHeader(label: 'Tags'),

                for (final tag in tags)
                  _SidebarItem(
                    icon: TablerIcons.tag,
                    iconColor: const Color(0xFF8B5CF6),
                    title: '${tag.tag} (${tag.count})',
                    selected: selectedTag == tag.tag,
                    onTap: () {
                      ref.read(vaultSelectedTagProvider.notifier).state =
                          tag.tag;
                      ref.read(vaultSelectedGroupProvider.notifier).state =
                          null;
                      ref.read(vaultSelectedItemTypeIdProvider.notifier).state =
                          null;
                    },
                  ),
              ],
            ),
          ),

          // ── Bottom bar ─────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: _sidebarBorderColor),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(
              children: <Widget>[
                _SidebarItem(
                  icon: TablerIcons.trash,
                  iconColor: _VaultColors.icon,
                  title: 'Trash ($trashCount)',
                  dense: true,
                  danger: true,
                  selected: selectedGroupUuid == kGroupFilterTrash,
                  onTap: () {
                    ref.read(vaultSelectedGroupProvider.notifier).state =
                        kGroupFilterTrash;
                    ref.read(vaultSelectedItemTypeIdProvider.notifier).state =
                        null;
                    ref.read(vaultSelectedTagProvider.notifier).state = null;
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onLockVault,
                    icon: const Icon(TablerIcons.lock, size: 14),
                    label: const Text('Lock Vault'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFD94A4A),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFD94A4A)),
                      minimumSize: const Size.fromHeight(34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: _text(
                        13,
                        Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const _SidebarAutoLockCountdownLabel(),
                const SizedBox(height: 10),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: _sidebarBorderColor,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _SidebarBuildInfoLabel(),
                ),
                const SizedBox(height: 4),
                const _VaultSyncStatusRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarAutoLockCountdownLabel extends ConsumerWidget {
  const _SidebarAutoLockCountdownLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoLockMinutes = ref.watch(vaultAutoLockMinutesProvider);
    final unlockedAt = ref.watch(activeDatabaseProvider)?.openedAt;
    if (autoLockMinutes == null || unlockedAt == null) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<DateTime>(
      valueListenable: _TimeScope.of(context),
      builder: (context, now, _) {
        final remaining = computeVaultAutoLockRemaining(
          now: now,
          unlockedAt: unlockedAt,
          autoLockMinutes: autoLockMinutes,
        );
        if (remaining == null) {
          return const SizedBox.shrink();
        }

        return Text(
          formatVaultAutoLockCountdown(remaining),
          textAlign: TextAlign.center,
          style: _text(
            9,
            _sidebarTextSecondary,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        );
      },
    );
  }
}

class _SidebarBuildInfoLabel extends StatelessWidget {
  const _SidebarBuildInfoLabel();

  Future<({String version, String build, DateTime? buildDate})> _load() async {
    final info = await PackageInfo.fromPlatform();
    DateTime? buildDate;
    try {
      final exec = File(Platform.resolvedExecutable);
      if (await exec.exists()) {
        buildDate = await exec.lastModified();
      }
    } catch (_) {
      buildDate = null;
    }
    return (
      version: info.version,
      build: info.buildNumber,
      buildDate: buildDate,
    );
  }

  String _formatBuildDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({String version, String build, DateTime? buildDate})>(
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final version = data?.version ?? '—';
        final build = data?.build ?? '—';
        final dateLine = data?.buildDate != null
            ? 'Build date: ${_formatBuildDate(data!.buildDate!)}'
            : 'Build date: —';
        return Text(
          'LumenPass v$version (build $build)\n$dateLine',
          style: _text(
            9,
            _sidebarTextSecondary,
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
        );
      },
    );
  }
}

/// Compact "Last synced" line with a circular-arrow refresh button.
///
/// Lives in the sidebar directly below the Build date. Watches
/// [vaultAutoSyncControllerProvider] for state and re-renders the
/// human-readable timestamp every second so "X seconds ago" stays fresh.
class _VaultSyncStatusRow extends ConsumerStatefulWidget {
  const _VaultSyncStatusRow();

  @override
  ConsumerState<_VaultSyncStatusRow> createState() =>
      _VaultSyncStatusRowState();
}

class _VaultSyncStatusRowState extends ConsumerState<_VaultSyncStatusRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Re-render every second so the relative time label updates smoothly.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _spin.dispose();
    super.dispose();
  }

  void _syncSpinner(VaultSyncState state) {
    if (state.isSyncing) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      if (_spin.isAnimating) {
        _spin.stop();
        _spin.value = 0;
      }
    }
  }

  Future<void> _onPressed() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final controller = ref.read(vaultAutoSyncControllerProvider.notifier);
    await controller.sync();
    if (!mounted) return;
    final state = ref.read(vaultAutoSyncControllerProvider);
    if (state.hasError && messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${state.error ?? 'unknown error'}'),
          backgroundColor: const Color(0xFFD94A4A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultAutoSyncControllerProvider);
    _syncSpinner(state);

    final disabled = state.isSyncing;
    final label = state.isSyncing
        ? 'Syncing…'
        : (state.hasError
            ? 'Sync failed — tap to retry'
            : formatLastSync(state.lastSyncAt));
    final labelColor =
        state.hasError ? const Color(0xFFFCA5A5) : _sidebarTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(
                9,
                labelColor,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: disabled ? 'Syncing…' : 'Sync now',
            child: SizedBox(
              width: 22,
              height: 22,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: disabled ? null : _onPressed,
                  hoverColor: const Color(0x335E8A9D),
                  highlightColor: const Color(0x225E8A9D),
                  child: Center(
                    child: RotationTransition(
                      turns: _spin,
                      child: Icon(
                        TablerIcons.refresh,
                        size: 14,
                        color: disabled
                            ? const Color(0xFF6B8390)
                            : _sidebarTextPrimary,
                      ),
                    ),
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

class _SidebarItemTypeDropdown extends ConsumerStatefulWidget {
  const _SidebarItemTypeDropdown({
    required this.totalCount,
    required this.itemTypes,
    required this.sidebarCounts,
  });

  final int totalCount;
  final List<_NewItemType> itemTypes;
  final Map<String, int> sidebarCounts;

  @override
  ConsumerState<_SidebarItemTypeDropdown> createState() =>
      _SidebarItemTypeDropdownState();
}

class _SidebarItemTypeDropdownState
    extends ConsumerState<_SidebarItemTypeDropdown> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedItemTypeId = ref.watch(vaultSelectedItemTypeIdProvider);
    _NewItemType? selectedItem;
    for (final item in widget.itemTypes) {
      if (item.id == selectedItemTypeId) {
        selectedItem = item;
        break;
      }
    }
    final isExpanded = _overlayEntry != null;
    final isAllItemsSelected = selectedItem == null;
    final resolvedItem = selectedItem ?? widget.itemTypes.first;
    final selectedCount = isAllItemsSelected
        ? widget.totalCount
        : (widget.sidebarCounts[resolvedItem.id] ?? 0);
    const backgroundColor = Colors.white;
    final borderColor =
        isExpanded ? const Color(0xFF9FB4C3) : const Color(0xFFD2DFE8);
    const primaryTextColor = Color(0xFF1E3341);
    const secondaryTextColor = Color(0xFF5E7382);

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleMenu,
        borderRadius: BorderRadius.circular(14),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
            ),
          ),
          child: Row(
            children: <Widget>[
              _SidebarItemTypeGlyph(
                icon: isAllItemsSelected
                    ? Icons.grid_view_rounded
                    : resolvedItem.icon!,
                iconColor: isAllItemsSelected
                    ? const Color(0xFF63BAF2)
                    : resolvedItem.iconColor,
                backgroundColor: isAllItemsSelected
                    ? const Color(0x1F63BAF2)
                    : const Color(0x00000000),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        isAllItemsSelected ? 'All Items' : resolvedItem.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          13,
                          primaryTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($selectedCount)',
                      maxLines: 1,
                      style: _text(
                        13,
                        primaryTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                isExpanded ? TablerIcons.chevron_up : TablerIcons.chevron_down,
                size: 17,
                color: secondaryTextColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    _showOverlay();
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final selectedItemTypeId = ref.watch(vaultSelectedItemTypeIdProvider);
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
                child: const SizedBox.expand(),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 8),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 224,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD9E2EF)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x16172033),
                        blurRadius: 30,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _SidebarItemTypeMenuOption(
                        label: 'All Items',
                        count: widget.totalCount,
                        icon: Icons.grid_view_rounded,
                        iconColor: const Color(0xFF63BAF2),
                        selected: selectedItemTypeId == null,
                        onTap: () => _selectItemType(null),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFE8EEF6),
                        ),
                      ),
                      for (final item in widget.itemTypes)
                        _SidebarItemTypeMenuOption(
                          label: item.label,
                          count: widget.sidebarCounts[item.id] ?? 0,
                          icon: item.icon!,
                          iconColor: item.iconColor,
                          selected: selectedItemTypeId == item.id,
                          onTap: () => _selectItemType(item.id),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlayEntry!);
    setState(() {});
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() {});
    }
  }

  void _selectItemType(String? itemTypeId) {
    ref.read(vaultSelectedItemTypeIdProvider.notifier).state = itemTypeId;
    ref.read(vaultSelectedGroupProvider.notifier).state = null;
    ref.read(vaultSelectedTagProvider.notifier).state = null;
    _removeOverlay();
  }
}

class _SidebarItemTypeMenuOption extends StatefulWidget {
  const _SidebarItemTypeMenuOption({
    required this.label,
    required this.count,
    required this.icon,
    required this.iconColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItemTypeMenuOption> createState() =>
      _SidebarItemTypeMenuOptionState();
}

class _SidebarItemTypeMenuOptionState
    extends State<_SidebarItemTypeMenuOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        widget.selected ? const Color(0xFFF2F7FF) : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              _SidebarItemTypeGlyph(
                icon: widget.icon,
                iconColor: widget.iconColor,
                backgroundColor: widget.icon == Icons.grid_view_rounded
                    ? const Color(0x1F63BAF2)
                    : const Color(0x00000000),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          13,
                          const Color(0xFF2A3445),
                          fontWeight: widget.selected || _hovered
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${widget.count})',
                      maxLines: 1,
                      style: _text(
                        13,
                        const Color(0xFF425269),
                        fontWeight: widget.selected || _hovered
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.selected) ...<Widget>[
                const SizedBox(width: 6),
                const Icon(
                  TablerIcons.check,
                  size: 18,
                  color: Color(0xFF2F80FF),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItemTypeGlyph extends StatelessWidget {
  const _SidebarItemTypeGlyph({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.size,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: size == 22 ? 15 : size * 0.68,
        color: iconColor,
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader({
    required this.label,
    this.action,
  });

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: _text(
                10,
                _sidebarTextSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ── Compact icon button used in section headers ───────────────────────────────

class _SidebarHeaderButton extends StatefulWidget {
  const _SidebarHeaderButton({
    required this.icon,
    this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_SidebarHeaderButton> createState() => _SidebarHeaderButtonState();
}

class _SidebarHeaderButtonState extends State<_SidebarHeaderButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x337FA7B8) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 14,
            color: _hovered ? _sidebarTextPrimary : _sidebarTextSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Category sidebar item with hover edit/delete actions ─────────────────────

class _SidebarCategoryItem extends StatefulWidget {
  const _SidebarCategoryItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onEdit,
    required this.onDelete,
    this.iconBadgeColor,
    this.imageAsset,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? iconBadgeColor;
  final String? imageAsset;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_SidebarCategoryItem> createState() => _SidebarCategoryItemState();
}

class _SidebarCategoryItemState extends State<_SidebarCategoryItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selected;
    final isHovered = _hovered && !isSelected;
    final hasBadge = widget.iconBadgeColor != null;
    final hasImage = widget.imageAsset != null;
    final iconBoxSize = (hasBadge || hasImage) ? 28.0 : 22.0;
    final iconSize = hasBadge ? 17.0 : 15.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 28),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            decoration: BoxDecoration(
              color: isSelected
                  ? _sidebarSelectedItemBackground
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: hasImage
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        )
                      : widget.iconBadgeColor == null
                          ? null
                          : BoxDecoration(
                              color: widget.iconBadgeColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                  alignment: Alignment.center,
                  child: hasImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            widget.imageAsset!,
                            width: iconBoxSize,
                            height: iconBoxSize,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          widget.icon,
                          size: iconSize,
                          color: widget.iconColor,
                        ),
                ),
                SizedBox(width: (hasBadge || hasImage) ? 12 : 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        hasBadge ? 13 : 12,
                        isSelected ? _sidebarSelectedText : _sidebarTextPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        height: 1.18,
                      ).copyWith(
                        decoration: isHovered
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationColor: isSelected
                            ? _sidebarSelectedText
                            : _sidebarTextPrimary,
                      ),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _hovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _SidebarCategoryActionButton(
                        icon: TablerIcons.pencil,
                        onPressed: widget.onEdit,
                      ),
                      const SizedBox(width: 2),
                      _SidebarCategoryActionButton(
                        icon: TablerIcons.trash,
                        danger: true,
                        onPressed: widget.onDelete,
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
}

class _SidebarCategoryActionButton extends StatefulWidget {
  const _SidebarCategoryActionButton({
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_SidebarCategoryActionButton> createState() =>
      _SidebarCategoryActionButtonState();
}

class _SidebarCategoryActionButtonState
    extends State<_SidebarCategoryActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dangerHover = widget.danger && _hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: dangerHover
                ? const Color(0x44D94A4A)
                : _hovered
                    ? const Color(0x337FA7B8)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 12,
            color:
                dangerHover ? const Color(0xFFFF7878) : _sidebarTextSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Regular sidebar item ───────────────────────────────────────────────────────

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.iconBadgeColor,
    this.imageAsset,
    this.selected = false,
    this.dense = false,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? iconBadgeColor;
  final String? imageAsset;
  final bool selected;
  final bool dense;
  final bool danger;
  final VoidCallback? onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selected;
    final isHovered = _hovered && !isSelected;
    final hasBadge = widget.iconBadgeColor != null;
    final hasImage = widget.imageAsset != null;
    final iconBoxSize = widget.dense
        ? 20.0
        : (hasBadge || hasImage)
            ? 28.0
            : 22.0;
    final iconSize = widget.dense
        ? 13.0
        : hasBadge
            ? 17.0
            : 15.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: isHovered ? 1.018 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              constraints: BoxConstraints(
                minHeight: widget.dense ? 18 : 28,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: widget.dense ? 0 : 1,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? _sidebarSelectedItemBackground
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: iconBoxSize,
                    height: iconBoxSize,
                    decoration: hasImage
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          )
                        : widget.iconBadgeColor == null
                            ? null
                            : BoxDecoration(
                                color: widget.iconBadgeColor,
                                borderRadius: BorderRadius.circular(999),
                              ),
                    alignment: Alignment.center,
                    child: hasImage
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              widget.imageAsset!,
                              width: iconBoxSize,
                              height: iconBoxSize,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            widget.icon,
                            size: iconSize,
                            color: widget.danger
                                ? const Color(0xFFD94A4A)
                                : widget.iconColor,
                          ),
                  ),
                  SizedBox(width: (hasBadge || hasImage) ? 12 : 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          hasBadge ? 13 : 12,
                          widget.danger
                              ? const Color(0xFFD94A4A)
                              : isSelected
                                  ? _sidebarSelectedText
                                  : _sidebarTextPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          height: 1.18,
                        ).copyWith(
                          decoration: isHovered
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: widget.danger
                              ? const Color(0xFFD94A4A)
                              : isSelected
                                  ? _sidebarSelectedText
                                  : _sidebarTextPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Switch Vault Modal ────────────────────────────────────────────────────────

void _showSwitchVaultModal(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _SwitchVaultModal(),
  );
}

class _SwitchVaultModal extends ConsumerWidget {
  const _SwitchVaultModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(databaseRegistryProvider);
    final activeDatabase = ref.watch(activeDatabaseProvider);
    final activePath = activeDatabase?.path;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: <Widget>[
                  const Icon(TablerIcons.switch_horizontal,
                      size: 20, color: Color(0xFF0F172A)),
                  const SizedBox(width: 10),
                  Text(
                    'Switch Vault',
                    style: _text(16, const Color(0xFF0F172A),
                        fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(TablerIcons.x,
                          size: 18, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Select a vault to switch to',
                style: _text(12, const Color(0xFF64748B)),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
            ),
            Flexible(
              child: registry.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No other vaults available',
                          style: _text(13, const Color(0xFF64748B)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      shrinkWrap: true,
                      itemCount: registry.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, index) {
                        final record = registry[index];
                        final isActive = activePath != null &&
                            databasePathsReferToSameVault(
                                record.databasePath, activePath);
                        return _SwitchVaultItem(
                          record: record,
                          isActive: isActive,
                          onSelect: () {
                            Navigator.of(context).pop();
                            _performSwitchVault(context, ref, record);
                          },
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

void _performSwitchVault(
    BuildContext context, WidgetRef ref, DatabaseRecord record) {
  BookmarkService.instance.stopAll();
  BackupService.instance.cancelForLockedVault();
  ref.read(kdbxRepositoryProvider).closeDatabase();
  ref.read(activeDatabaseProvider.notifier).state = null;
  ref.read(cachedMasterPasswordProvider.notifier).state = null;
  ref.read(vaultSelectedItemTypeIdProvider.notifier).state = null;
  unawaited(SshAgentService.instance.syncKeys());
  unawaited(TrayService.instance.setVaultLocked(true));
  Navigator.of(context).pushReplacementNamed(
    UnlockScreen.routeName,
    arguments: UnlockScreenArgs(
      lockedPath: record.databasePath,
      lockedReason: VaultLockedReason.manual,
    ),
  );
}

class _SwitchVaultItem extends StatefulWidget {
  const _SwitchVaultItem({
    required this.record,
    required this.isActive,
    required this.onSelect,
  });

  final DatabaseRecord record;
  final bool isActive;
  final VoidCallback onSelect;

  @override
  State<_SwitchVaultItem> createState() => _SwitchVaultItemState();
}

class _SwitchVaultItemState extends State<_SwitchVaultItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isActive
        ? const Color(0xFFEFF6FF)
        : _hovered
            ? const Color(0xFFF8FAFC)
            : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.isActive
                ? const Color(0xFF3B82F6)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 40,
              height: 40,
              child: _VaultStorageIcon(
                record: widget.record,
                size: 40,
                iconSize: 24,
                borderRadius: 8,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.record.nickname.isNotEmpty
                        ? widget.record.nickname
                        : p.basenameWithoutExtension(
                            widget.record.databasePath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(13, const Color(0xFF0F172A),
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _switchVaultLocationLabel(widget.record),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(11, const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Active',
                  style: _text(11, Colors.white, fontWeight: FontWeight.w600),
                ),
              )
            else
              GestureDetector(
                onTap: widget.onSelect,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Select',
                    style: _text(11, Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _switchVaultLocationLabel(DatabaseRecord record) {
  switch (record.storageType) {
    case 'googleDrive':
      return 'Google Drive${record.cloudFileName != null ? ' · ${record.cloudFileName}' : ''}';
    case 'dropbox':
      return 'Dropbox${record.cloudFileName != null ? ' · ${record.cloudFileName}' : ''}';
    case 'oneDrive':
      return 'OneDrive${record.cloudFileName != null ? ' · ${record.cloudFileName}' : ''}';
    case 'webdav':
      return 'WebDAV${record.cloudFileName != null ? ' · ${record.cloudFileName}' : ''}';
    case 'sftp':
      return 'SFTP${record.cloudFileName != null ? ' · ${record.cloudFileName}' : ''}';
    default:
      return p.basename(record.databasePath);
  }
}
