part of 'vault_screen.dart';

const Set<String> _hiddenSidebarCategoryIds = <String>{
  'document',
  'api-credential',
  'server',
  'wifi-password',
  'passport',
};
const Color _sidebarBackgroundColor = _VaultColors.sidebar;
const Color _sidebarBorderColor = _VaultColors.borderPane;
const Color _sidebarTextPrimary = Color(0xFF292B2A);
const Color _sidebarTextSecondary = Color(0xFF74766F);
const Color _sidebarSelectedText = Color(0xFF1D1F1E);
const Color _sidebarSelectedItemBackground = Color(0xFFD4CEC6);
const Color _sidebarHoverItemBackground = Color(0xFFDDD7D0);

enum _SidebarVaultMenuAction { switchVault, import }

class _SidebarPane extends ConsumerWidget {
  const _SidebarPane({
    required this.width,
    required this.onLockVault,
    required this.onOpenImport,
    required this.onOpenAddCategoryModal,
    required this.onEditCategory,
    required this.onDeleteCategory,
  });

  final double width;
  final VoidCallback onLockVault;
  final VoidCallback onOpenImport;
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
      width: width,
      decoration: const BoxDecoration(
        color: _sidebarBackgroundColor,
        border: Border(
          right: BorderSide(color: _sidebarBorderColor),
        ),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              Platform.isMacOS ? 38 : 12,
              16,
              8,
            ),
            child: _SidebarVaultDropdown(
              record: record,
              databaseName: databaseName,
              onSwitchVault: () => _showSwitchVaultModal(context),
              onImport: onOpenImport,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color: _sidebarBorderColor,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: _SidebarItemTypeDropdown(
              totalCount: totalCount,
              itemTypes: visibleItemTypes,
              sidebarCounts: sidebarCounts,
            ),
          ),

          // ── Scrollable middle section ──────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
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
                  padding: const EdgeInsets.only(bottom: 1),
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
                  padding: const EdgeInsets.only(bottom: 1),
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
                      padding: const EdgeInsets.only(bottom: 1),
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
                const SizedBox(height: 10),

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

                const SizedBox(height: 10),

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
                const SizedBox(height: 8),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            decoration: const BoxDecoration(
              color: _sidebarBackgroundColor,
              border: Border(
                top: BorderSide(color: _sidebarBorderColor),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _SidebarFooterAction(
                  icon: TablerIcons.trash,
                  label: 'Trash ($trashCount)',
                  color: const Color(0xFFD84B45),
                  selected: selectedGroupUuid == kGroupFilterTrash,
                  onPressed: () {
                    ref.read(vaultSelectedGroupProvider.notifier).state =
                        kGroupFilterTrash;
                    ref.read(vaultSelectedItemTypeIdProvider.notifier).state =
                        null;
                    ref.read(vaultSelectedTagProvider.notifier).state = null;
                  },
                ),
                const SizedBox(height: 6),
                _SidebarFooterAction(
                  icon: TablerIcons.lock,
                  label: 'Lock vault',
                  color: const Color(0xFF0F766E),
                  filled: true,
                  onPressed: onLockVault,
                ),
                const SizedBox(height: 5),
                const _SidebarAutoLockCountdownLabel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarVaultDropdown extends StatelessWidget {
  const _SidebarVaultDropdown({
    required this.record,
    required this.databaseName,
    required this.onSwitchVault,
    required this.onImport,
  });

  final DatabaseRecord? record;
  final String databaseName;
  final VoidCallback onSwitchVault;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SidebarVaultMenuAction>(
      tooltip: 'Current vault menu',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 5),
      color: _VaultColors.surface,
      surfaceTintColor: Colors.transparent,
      menuPadding: const EdgeInsets.all(6),
      elevation: 10,
      shadowColor: const Color(0x245B4638),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _VaultColors.borderSoft),
      ),
      onSelected: (action) {
        switch (action) {
          case _SidebarVaultMenuAction.switchVault:
            onSwitchVault();
            break;
          case _SidebarVaultMenuAction.import:
            onImport();
            break;
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<_SidebarVaultMenuAction>>[
        const PopupMenuItem<_SidebarVaultMenuAction>(
          value: _SidebarVaultMenuAction.switchVault,
          height: 44,
          child: _SidebarVaultMenuRow(
            icon: TablerIcons.switch_horizontal,
            label: 'Switch vault',
          ),
        ),
        const PopupMenuItem<_SidebarVaultMenuAction>(
          value: _SidebarVaultMenuAction.import,
          height: 44,
          child: _SidebarVaultMenuRow(
            icon: TablerIcons.download,
            label: 'Import items',
          ),
        ),
      ],
      child: Semantics(
        button: true,
        label: 'Current vault: $databaseName',
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              _VaultStorageIcon(
                record: record,
                size: 38,
                iconSize: 27,
                borderRadius: 10,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  databaseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    16,
                    _sidebarTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                TablerIcons.chevron_down,
                size: 18,
                color: _sidebarTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarVaultMenuRow extends StatelessWidget {
  const _SidebarVaultMenuRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 206,
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _VaultColors.peachSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: _kPrimaryButtonColor),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: _text(
              13,
              _sidebarTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarFooterAction extends StatefulWidget {
  const _SidebarFooterAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.selected = false,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool selected;
  final bool filled;

  @override
  State<_SidebarFooterAction> createState() => _SidebarFooterActionState();
}

class _SidebarFooterActionState extends State<_SidebarFooterAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final useSolidFill = widget.filled;
    final foreground = useSolidFill ? Colors.white : widget.color;
    final background = useSolidFill
        ? (_hovered ? widget.color.withValues(alpha: 0.88) : widget.color)
        : widget.color.withValues(
            alpha: widget.selected ? 0.16 : (_hovered ? 0.12 : 0.07),
          );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.label,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: double.infinity,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: useSolidFill
                    ? widget.color
                    : widget.color.withValues(alpha: 0.24),
              ),
              boxShadow: useSolidFill
                  ? <BoxShadow>[
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.18),
                        blurRadius: 7,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Icon(widget.icon, size: 15, color: foreground),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    style: _text(
                      13,
                      foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  TablerIcons.chevron_right,
                  size: 14,
                  color: foreground.withValues(alpha: 0.72),
                ),
              ],
            ),
          ),
        ),
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
            11,
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
            11,
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
/// Lives in the detail footer beside the build information. Watches
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

  /// Drives only the relative-time label. The per-second tick updates this
  /// notifier so a [ValueListenableBuilder] scoped to the label rebuilds —
  /// instead of calling `setState` and rebuilding the whole row every second.
  final ValueNotifier<DateTime> _tick = ValueNotifier<DateTime>(
    DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Re-render the relative-time label every second so it stays fresh.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _tick.value = DateTime.now();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _tick.dispose();
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
    final labelColor =
        state.hasError ? _kDangerButtonColor : _sidebarTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ValueListenableBuilder<DateTime>(
              valueListenable: _tick,
              builder: (context, now, _) {
                final label = state.isSyncing
                    ? 'Syncing…'
                    : (state.hasError
                        ? 'Sync failed — tap to retry'
                        : formatLastSync(state.lastSyncAt, now: now));
                return Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    11,
                    labelColor,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                );
              },
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
                  hoverColor: _VaultColors.peachSoft,
                  highlightColor: _VaultColors.peach,
                  child: Center(
                    child: RotationTransition(
                      turns: _spin,
                      child: Icon(
                        TablerIcons.refresh,
                        size: 14,
                        color: disabled
                            ? const Color(0xFFA09D95)
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
  bool _hovered = false;

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
    final backgroundColor = isExpanded || _hovered
        ? _sidebarHoverItemBackground
        : Colors.transparent;
    const primaryTextColor = _VaultColors.title;
    const secondaryTextColor = _VaultColors.headerLabel;

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: _toggleMenu,
          borderRadius: BorderRadius.circular(10),
          overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                _SidebarItemTypeGlyph(
                  icon: isAllItemsSelected
                      ? TablerIcons.layout_grid
                      : resolvedItem.icon!,
                  iconColor: isAllItemsSelected
                      ? _kPrimaryButtonColor
                      : resolvedItem.iconColor,
                  backgroundColor: isAllItemsSelected
                      ? _VaultColors.peachSoft
                      : const Color(0x00000000),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          isAllItemsSelected ? 'All Items' : resolvedItem.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _text(
                            15,
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
                          15,
                          primaryTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  isExpanded
                      ? TablerIcons.chevron_up
                      : TablerIcons.chevron_down,
                  size: 17,
                  color: secondaryTextColor,
                ),
              ],
            ),
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
                  width: 264,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _VaultColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _VaultColors.borderSoft),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _SidebarItemTypeMenuOption(
                        label: 'All Items',
                        count: widget.totalCount,
                        icon: TablerIcons.layout_grid,
                        iconColor: _kPrimaryButtonColor,
                        selected: selectedItemTypeId == null,
                        onTap: () => _selectItemType(null),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: _VaultColors.borderSoft,
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
    final backgroundColor = widget.selected
        ? _sidebarSelectedItemBackground
        : (_hovered ? _sidebarHoverItemBackground : Colors.transparent);

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
                backgroundColor: widget.icon == TablerIcons.layout_grid
                    ? _VaultColors.peachSoft
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
                          15,
                          _VaultColors.title,
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
                        15,
                        _VaultColors.headerLabel,
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
                  color: _kPrimaryButtonColor,
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: _text(
                11,
                _sidebarTextSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ).copyWith(
                decoration: TextDecoration.underline,
                decorationColor: _sidebarTextSecondary,
                decorationThickness: 1.15,
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
            color: _hovered ? _VaultColors.peachSoft : Colors.transparent,
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
    final iconBoxSize = (hasBadge || hasImage) ? 24.0 : 20.0;
    final iconSize = hasBadge ? 15.0 : 14.0;

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
            constraints: const BoxConstraints(minHeight: 26),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? _sidebarSelectedItemBackground
                  : isHovered
                      ? _sidebarHoverItemBackground
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
                        hasBadge ? 14 : 13,
                        isSelected ? _sidebarSelectedText : _sidebarTextPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        height: 1.18,
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
    this.imageAsset,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? imageAsset;
  final bool selected;
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
    final hasImage = widget.imageAsset != null;
    final iconBoxSize = hasImage ? 24.0 : 20.0;
    const iconSize = 14.0;

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
            constraints: const BoxConstraints(minHeight: 26),
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 0,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? _sidebarSelectedItemBackground
                  : isHovered
                      ? _sidebarHoverItemBackground
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
                      : null,
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
                SizedBox(width: hasImage ? 12 : 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        13,
                        isSelected ? _sidebarSelectedText : _sidebarTextPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        height: 1.18,
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
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 420),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        decoration: BoxDecoration(
          color: _VaultColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _VaultColors.borderPane),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x295B4638),
              blurRadius: 36,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _VaultColors.peachSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(TablerIcons.switch_horizontal,
                      size: 21, color: _kPrimaryButtonColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Switch Vault',
                    style: _text(18, _VaultColors.title,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(TablerIcons.x, size: 20),
                  color: _VaultColors.icon,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Select a vault to switch to',
              style: _text(13, _VaultColors.headerLabel),
            ),
            const SizedBox(height: 18),
            const Divider(
                height: 1, thickness: 1, color: _VaultColors.borderSoft),
            Flexible(
              child: registry.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No other vaults available',
                          style: _text(13, _VaultColors.headerLabel),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
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
                            unawaited(
                                _performSwitchVault(context, ref, record));
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

Future<void> _performSwitchVault(
    BuildContext context, WidgetRef ref, DatabaseRecord record) async {
  // Persist pending background writes before swapping vaults so nothing is
  // discarded when the in-memory database is closed below.
  await ref.read(vaultWriteSchedulerProvider).flushNow();
  if (!context.mounted) return;
  BookmarkService.instance.stopAll();
  BackupService.instance.cancelForLockedVault();
  ref.read(vaultWriteSchedulerProvider).reset();
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
        ? _VaultColors.peachSoft
        : _hovered
            ? _VaultColors.surfaceMuted
            : _VaultColors.surface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: !widget.isActive,
        selected: widget.isActive,
        child: InkWell(
          onTap: widget.isActive ? null : widget.onSelect,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isActive
                    ? _kPrimaryButtonColor
                    : _VaultColors.borderSoft,
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
                        style: _text(13, _VaultColors.title,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _switchVaultLocationLabel(widget.record),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(11, _VaultColors.headerLabel),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kPrimaryButtonColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Active',
                      style:
                          _text(11, Colors.white, fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _VaultColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _VaultColors.borderSoft),
                    ),
                    child: Text(
                      'Select',
                      style: _text(11, _VaultColors.title,
                          fontWeight: FontWeight.w600),
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
