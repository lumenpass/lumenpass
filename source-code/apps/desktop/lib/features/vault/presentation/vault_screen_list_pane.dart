part of 'vault_screen.dart';

class _ListPane extends StatefulWidget {
  const _ListPane({
    required this.entries,
    required this.selectedIndex,
    required this.onEntrySelected,
    required this.onRefreshEntries,
    required this.isRefreshing,
    required this.sortField,
    required this.sortDirection,
    required this.onSortChanged,
    required this.searchQuery,
    required this.onClearSearch,
    required this.onOpenEntryWebsite,
    required this.onEditEntry,
    required this.onDuplicateEntry,
    required this.onCopyEntryTotp,
    required this.onDeleteEntry,
    required this.isPasswordAuditView,
    required this.passwordAuditReport,
    required this.passwordAuditDuplicatedCount,
    required this.passwordAuditWeakCount,
    required this.passwordAuditStaleCount,
    required this.passwordAuditSelection,
    required this.onPasswordAuditIssueSelected,
    required this.onPasswordAuditBack,
    this.passwordAuditDuplicateGroupLabel,
  });

  final List<_MockEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onEntrySelected;
  final Future<void> Function() onRefreshEntries;
  final bool isRefreshing;
  final _VaultSortField sortField;
  final _VaultSortDirection sortDirection;
  final ValueChanged<_VaultSortField> onSortChanged;
  final String searchQuery;
  final VoidCallback onClearSearch;
  final ValueChanged<int> onOpenEntryWebsite;
  final ValueChanged<int> onEditEntry;
  final ValueChanged<int> onDuplicateEntry;
  final ValueChanged<int> onCopyEntryTotp;
  final ValueChanged<int> onDeleteEntry;
  final bool isPasswordAuditView;
  final List<PasswordAuditEntry> passwordAuditReport;
  final int passwordAuditDuplicatedCount;
  final int passwordAuditWeakCount;
  final int passwordAuditStaleCount;
  final PasswordAuditIssue? passwordAuditSelection;
  final ValueChanged<PasswordAuditIssue> onPasswordAuditIssueSelected;
  final VoidCallback onPasswordAuditBack;

  /// When non-null, the list pane is rendering members of a specific
  /// duplicate group (level 3 of the duplicate-items audit flow). The
  /// label is forwarded to [_PasswordAuditDrilldownHeader] so the user
  /// can see which group they drilled into.
  final String? passwordAuditDuplicateGroupLabel;

  @override
  State<_ListPane> createState() => _ListPaneState();
}

class _ListPaneState extends State<_ListPane> {
  static const double _scrollbarThickness = 6;
  static const double _scrollbarGutter = 10;
  static const double _rowHeight = 80;

  late final ScrollController _scrollController;
  bool _showsScrollbar = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_syncScrollbarVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScrollbarVisibility();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncScrollbarVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScrollbarVisibility();
    });
    if (widget.entries.isEmpty ||
        widget.selectedIndex == oldWidget.selectedIndex ||
        !_scrollController.hasClients) {
      return;
    }

    // Keep the selected entry visible after list resort/refresh.
    final rowTop = widget.selectedIndex * _rowHeight;
    final rowBottom = rowTop + _rowHeight;
    final viewportTop = _scrollController.offset;
    final viewportBottom =
        viewportTop + _scrollController.position.extentInside;
    double? targetOffset;
    if (rowTop < viewportTop) {
      targetOffset = rowTop;
    } else if (rowBottom > viewportBottom) {
      targetOffset = rowBottom - _scrollController.position.extentInside;
    }

    if (targetOffset != null) {
      final clamped = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        _scrollController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  void _syncScrollbarVisibility([ScrollMetrics? metrics]) {
    if (!mounted) {
      return;
    }
    final hasOverflow = metrics != null
        ? metrics.maxScrollExtent > 0
        : _scrollController.hasClients &&
            _scrollController.position.maxScrollExtent > 0;
    if (hasOverflow == _showsScrollbar) {
      return;
    }
    setState(() {
      _showsScrollbar = hasOverflow;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auditEntryByUuid = widget.isPasswordAuditView
        ? <String, PasswordAuditEntry>{
            for (final auditEntry in widget.passwordAuditReport)
              auditEntry.entry.uuid: auditEntry,
          }
        : const <String, PasswordAuditEntry>{};

    return Container(
      width: 330,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: _VaultColors.borderPane),
        ),
      ),
      child: Column(
        children: <Widget>[
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0xFFFFFFFF),
                  Color(0xFFEBF0F7),
                ],
              ),
              border: Border(
                top: BorderSide(color: Color(0xFFFFFFFF)),
                bottom: BorderSide(
                  color: Color(0xFFB8C5D6),
                  width: 1.5,
                ),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0x18000000),
                  offset: Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                _ListHeaderButton(
                  label: 'Title',
                  field: _VaultSortField.title,
                  activeField: widget.sortField,
                  direction: widget.sortDirection,
                  onTap: widget.onSortChanged,
                ),
                const Spacer(),
                _ListHeaderButton(
                  label: 'Last Edited',
                  field: _VaultSortField.lastEdited,
                  activeField: widget.sortField,
                  direction: widget.sortDirection,
                  onTap: widget.onSortChanged,
                ),
                const SizedBox(width: 8),
                _RefreshListButton(
                  isRefreshing: widget.isRefreshing,
                  onTap: widget.onRefreshEntries,
                ),
              ],
            ),
          ),
          if (widget.isPasswordAuditView)
            _PasswordAuditDrilldownHeader(
              issue: widget.passwordAuditSelection,
              resultCount: widget.entries.length,
              onBack: widget.onPasswordAuditBack,
              duplicateGroupLabel: widget.passwordAuditDuplicateGroupLabel,
            )
          else if (widget.searchQuery.trim().isNotEmpty)
            _ActiveSearchBanner(
              query: widget.searchQuery,
              resultCount: widget.entries.length,
              onClear: widget.onClearSearch,
            ),
          Expanded(
            child: widget.isPasswordAuditView && widget.entries.isEmpty
                ? const _PasswordAuditEmptyState()
                : widget.entries.isEmpty
                    ? const _ListEmptyState()
                    : ScrollbarTheme(
                        data: const ScrollbarThemeData(
                          thumbColor: WidgetStatePropertyAll<Color>(
                            Color(0xFFB7C0CE),
                          ),
                          trackColor: WidgetStatePropertyAll<Color>(
                            Color(0xFFF0F3F8),
                          ),
                          trackBorderColor: WidgetStatePropertyAll<Color>(
                            Color(0xFFDCE3EE),
                          ),
                        ),
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: _showsScrollbar,
                          trackVisibility: _showsScrollbar,
                          interactive: _showsScrollbar,
                          thickness: _scrollbarThickness,
                          radius: const Radius.circular(999),
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: _showsScrollbar
                                  ? _scrollbarThickness + _scrollbarGutter
                                  : 0,
                            ),
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(scrollbars: false),
                              child: NotificationListener<
                                  ScrollMetricsNotification>(
                                onNotification: (notification) {
                                  _syncScrollbarVisibility(
                                      notification.metrics);
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: _scrollController,
                                  itemExtent: _rowHeight,
                                  padding: EdgeInsets.zero,
                                  itemCount: widget.entries.length,
                                  itemBuilder: (context, index) =>
                                      RepaintBoundary(
                                    // Each row paints into its own raster layer so
                                    // hover/selection/favicon-load on one row does
                                    // not invalidate siblings.
                                    child: _ListRow(
                                      entry: widget.entries[index],
                                      selected: index == widget.selectedIndex,
                                      onTap: () =>
                                          widget.onEntrySelected(index),
                                      onOpenWebsite: () =>
                                          widget.onOpenEntryWebsite(index),
                                      onEdit: () => widget.onEditEntry(index),
                                      onDuplicate: () =>
                                          widget.onDuplicateEntry(index),
                                      onCopyTotp: widget.entries[index]
                                              .totpAuthUrl.isNotEmpty
                                          ? () => widget.onCopyEntryTotp(index)
                                          : null,
                                      onDelete: () =>
                                          widget.onDeleteEntry(index),
                                      auditEntry: widget.isPasswordAuditView
                                          ? auditEntryByUuid[
                                              widget.entries[index].uuid]
                                          : null,
                                    ),
                                  ),
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

class _ActiveSearchBanner extends StatelessWidget {
  const _ActiveSearchBanner({
    required this.query,
    required this.resultCount,
    required this.onClear,
  });

  final String query;
  final int resultCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F3FF),
        border: Border(
          bottom: BorderSide(color: _VaultColors.borderPane),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$resultCount results for "$query"',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(
                12,
                const Color(0xFF3A4457),
                fontWeight: FontWeight.w600,
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
              child: const Icon(
                TablerIcons.x,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListHeaderButton extends StatelessWidget {
  const _ListHeaderButton({
    required this.label,
    required this.field,
    required this.activeField,
    required this.direction,
    required this.onTap,
  });

  final String label;
  final _VaultSortField field;
  final _VaultSortField activeField;
  final _VaultSortDirection direction;
  final ValueChanged<_VaultSortField> onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = field == activeField;
    final icon = direction == _VaultSortDirection.ascending
        ? TablerIcons.arrow_narrow_up
        : TablerIcons.arrow_narrow_down;

    return InkWell(
      onTap: () => onTap(field),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: _text(
                11,
                isActive ? const Color(0xFF000000) : const Color(0xFF000000),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isActive) ...<Widget>[
              const SizedBox(width: 3),
              Icon(
                icon,
                size: 12,
                color: const Color(0xFF536987),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RefreshListButton extends StatelessWidget {
  const _RefreshListButton({
    required this.isRefreshing,
    required this.onTap,
  });

  final bool isRefreshing;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isRefreshing ? null : () => onTap(),
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedRotation(
          turns: isRefreshing ? 1 : 0,
          duration: const Duration(milliseconds: 700),
          child: Icon(
            TablerIcons.refresh,
            size: 14,
            color: isRefreshing ? const Color(0xFF0A67FF) : _VaultColors.icon,
          ),
        ),
      ),
    );
  }
}

class _ListEmptyState extends StatelessWidget {
  const _ListEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0xFFC7D6F6)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x120A67FF),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(
                TablerIcons.inbox,
                size: 24,
                color: Color(0xFF2E5ECC),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing here yet',
              style: _text(
                12,
                const Color(0xFF3A4A5E),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Use "+ New Item" to add\nyour first entry.',
              textAlign: TextAlign.center,
              style: _text(
                11,
                const Color(0xFF9AAABB),
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewItemButton extends StatefulWidget {
  const _NewItemButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  State<_NewItemButton> createState() => _NewItemButtonState();
}

class _NewItemButtonState extends State<_NewItemButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.015 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:
                  _hovered ? _kPrimaryButtonHoverColor : _kPrimaryButtonColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _hovered
                      ? _kPrimaryButtonColor.withValues(alpha: 0.24)
                      : _kPrimaryButtonColor.withValues(alpha: 0.14),
                  blurRadius: _hovered ? 12 : 4,
                  offset: Offset(0, _hovered ? 4 : 1),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                const Icon(TablerIcons.plus, size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'New Item',
                  style: _text(11, Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialIconTile extends StatelessWidget {
  const _SocialIconTile({required this.provider, required this.size});
  final String provider;
  final double size;

  String _providerDomain(String id) {
    switch (id.toLowerCase()) {
      case 'google':
        return 'google.com';
      case 'apple':
        return 'apple.com';
      case 'facebook':
        return 'facebook.com';
      case 'github':
        return 'github.com';
      case 'microsoft':
        return 'microsoft.com';
      case 'twitter':
        return 'x.com';
      case 'linkedin':
        return 'linkedin.com';
      default:
        return '$id.com';
    }
  }

  @override
  Widget build(BuildContext context) {
    final domain = _providerDomain(provider);
    final faviconUrl =
        'https://www.google.com/s2/favicons?sz=32&domain=$domain';
    final fallback = Icon(TablerIcons.link,
        size: size * 0.65, color: const Color(0xFF6D63D6));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      alignment: Alignment.center,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            faviconUrl,
            width: size * 0.65,
            height: size * 0.65,
            fit: BoxFit.cover,
            cacheWidth: (size * 0.65 * 2).ceil(),
            cacheHeight: (size * 0.65 * 2).ceil(),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => fallback,
          ),
        ),
      ),
    );
  }
}

class _ListRow extends StatefulWidget {
  const _ListRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onOpenWebsite,
    required this.onEdit,
    required this.onDuplicate,
    required this.onCopyTotp,
    required this.onDelete,
    this.auditEntry,
  });

  final _MockEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenWebsite;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onCopyTotp;
  final VoidCallback onDelete;
  final PasswordAuditEntry? auditEntry;

  @override
  State<_ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<_ListRow> {
  static final RegExp _emailPattern = RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    caseSensitive: false,
  );

  bool _hovered = false;

  static const Color _menuSurface = Color(0xFFFFFFFF);
  static const Color _menuText = Color(0xFF243247);
  static const Color _menuBorder = Color(0xFFDDE6F2);

  PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String label,
    required Color iconColor,
    bool isDestructive = false,
    bool showBottomDivider = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          border: showBottomDivider
              ? const Border(
                  bottom: BorderSide(color: Color(0xFFE6ECF4)),
                )
              : null,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: _text(
                11,
                isDestructive ? const Color(0xFFB42318) : _menuText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildContextMenuEntries({
    required bool hasWebsite,
    required bool hasTotp,
  }) {
    final actions = <({
      String value,
      IconData icon,
      String label,
      Color iconColor,
      bool isDestructive,
    })>[
      if (hasWebsite)
        (
          value: 'open',
          icon: TablerIcons.external_link,
          label: 'Open',
          iconColor: const Color(0xFF2563EB),
          isDestructive: false,
        ),
      (
        value: 'edit',
        icon: TablerIcons.edit,
        label: 'Edit',
        iconColor: const Color(0xFF0F766E),
        isDestructive: false,
      ),
      (
        value: 'duplicate',
        icon: TablerIcons.copy,
        label: 'Duplicate',
        iconColor: const Color(0xFF4F46E5),
        isDestructive: false,
      ),
      if (hasTotp)
        (
          value: 'copy_totp',
          icon: TablerIcons.clock,
          label: 'Copy TOTP',
          iconColor: const Color(0xFFD97706),
          isDestructive: false,
        ),
      (
        value: 'delete',
        icon: TablerIcons.trash,
        label: 'Delete',
        iconColor: const Color(0xFFDC2626),
        isDestructive: true,
      ),
    ];

    return <PopupMenuEntry<String>>[
      for (var index = 0; index < actions.length; index++)
        _menuItem(
          value: actions[index].value,
          icon: actions[index].icon,
          label: actions[index].label,
          iconColor: actions[index].iconColor,
          isDestructive: actions[index].isDestructive,
          showBottomDivider: index < actions.length - 1,
        ),
    ];
  }

  Future<String?> _showStyledContextMenu({
    required BuildContext menuContext,
    required RelativeRect position,
    required List<PopupMenuEntry<String>> items,
  }) {
    return showMenu<String>(
      context: menuContext,
      position: position,
      items: items,
      color: _menuSurface,
      surfaceTintColor: _menuSurface,
      shadowColor: const Color(0x22000000),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _menuBorder),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 2),
      constraints: const BoxConstraints(
        minWidth: 174,
        maxWidth: 214,
      ),
    );
  }

  void _handleMenuSelection(String choice) {
    switch (choice) {
      case 'open':
        widget.onOpenWebsite();
        break;
      case 'edit':
        widget.onEdit();
        break;
      case 'duplicate':
        widget.onDuplicate();
        break;
      case 'copy_totp':
        widget.onCopyTotp?.call();
        break;
      case 'delete':
        widget.onDelete();
        break;
    }
  }

  bool get _showsAccountInlineIcon {
    final subtitle = widget.entry.subtitle.trim();
    if (subtitle.isEmpty) {
      return false;
    }

    final username = widget.entry.username.trim();
    if (username.isNotEmpty &&
        subtitle == _truncateListPreview(_singleLinePreview(username), 56)) {
      return true;
    }

    return _emailPattern.hasMatch(subtitle);
  }

  Widget _buildInlineValueLine({
    required IconData icon,
    required String text,
    required TextStyle style,
  }) {
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                icon,
                size: 12,
                color: style.color,
              ),
            ),
          ),
          TextSpan(text: text),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Future<void> _showContextMenuAt(
    Offset globalPosition, {
    required BuildContext menuContext,
    required bool hasWebsite,
    required bool hasTotp,
  }) async {
    widget.onTap();
    final overlayContext = Overlay.maybeOf(context)?.context;
    final overlayBox = overlayContext?.findRenderObject();
    if (overlayBox is! RenderBox) {
      return;
    }

    final selection = await _showStyledContextMenu(
      menuContext: menuContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlayBox.size,
      ),
      items: _buildContextMenuEntries(hasWebsite: hasWebsite, hasTotp: hasTotp),
    );
    if (!mounted || selection == null) {
      return;
    }
    _handleMenuSelection(selection);
  }

  @override
  Widget build(BuildContext context) {
    final hasWebsite = widget.entry.website.trim().isNotEmpty;
    final hasTotp = widget.entry.totpAuthUrl.isNotEmpty;
    final website = widget.entry.website.trim();
    final subtitleStyle = _text(
      11,
      const Color(0xFF6E6E73),
      fontWeight: FontWeight.w400,
    );
    final websiteStyle = _text(
      10,
      const Color(0xFF8A96A8),
      fontWeight: FontWeight.w400,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: const Color(0xFFEAF1FC),
        highlightColor: const Color(0x144D79C7),
        splashColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      child: Builder(
        builder: (menuThemeContext) {
          return MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) {
                _showContextMenuAt(
                  details.globalPosition,
                  menuContext: menuThemeContext,
                  hasWebsite: hasWebsite,
                  hasTotp: hasTotp,
                );
              },
              child: AnimatedScale(
                scale: _hovered && !widget.selected ? 1.012 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: InkWell(
                  onTap: widget.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    height: _ListPaneState._rowHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? const Color(0xFFDCE8FF)
                          : (_hovered ? const Color(0xFFE8EFF9) : Colors.white),
                      border: const Border(
                        bottom: BorderSide(color: _VaultColors.borderPane),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        if (widget.entry.socialProvider.isNotEmpty)
                          _SocialIconTile(
                              provider: widget.entry.socialProvider, size: 28)
                        else
                          _FaviconTile(entry: widget.entry, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Text(
                                      widget.entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _text(
                                        12,
                                        const Color(0xFF2C3B56),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (widget.entry.hasPasskeyChip) ...<Widget>[
                                    const SizedBox(width: 6),
                                    Image.asset(
                                      'assets/images/passkey_icon.png',
                                      width: 18,
                                      height: 18,
                                    ),
                                  ],
                                  if (widget.entry.totpAuthUrl
                                      .isNotEmpty) ...<Widget>[
                                    const SizedBox(width: 6),
                                    Image.asset(
                                      'assets/images/totp_icon.png',
                                      width: 18,
                                      height: 18,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              _showsAccountInlineIcon
                                  ? _buildInlineValueLine(
                                      icon: TablerIcons.user,
                                      text: widget.entry.subtitle,
                                      style: subtitleStyle,
                                    )
                                  : Text(
                                      widget.entry.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: subtitleStyle,
                                    ),
                              if (website.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 1),
                                _buildInlineValueLine(
                                  icon: TablerIcons.link,
                                  text: website,
                                  style: websiteStyle,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (widget.auditEntry != null) ...<Widget>[
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              if (widget.auditEntry!.hasDuplicated)
                                _AuditBadge(
                                  label: 'Duplicated',
                                  color: const Color(0xFFDC2626),
                                ),
                              if (widget.auditEntry!.hasWeak)
                                _AuditBadge(
                                  label: 'Weak',
                                  color: const Color(0xFFF59E0B),
                                ),
                              if (widget.auditEntry!.hasStale)
                                _AuditBadge(
                                  label: 'Too old',
                                  color: const Color(0xFF6B7280),
                                ),
                            ],
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          widget.entry.dateLabel,
                          style: _text(
                            11,
                            const Color(0xFF74839A),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AuditBadge extends StatelessWidget {
  const _AuditBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: _text(
          9,
          color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PasswordAuditEmptyState extends StatelessWidget {
  const _PasswordAuditEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.2)),
              ),
              alignment: Alignment.center,
              child: const Icon(
                TablerIcons.shield_check,
                size: 24,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'All passwords are secure',
              style: _text(
                12,
                const Color(0xFF3A4A5E),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'No duplicated, weak, or\nstale passwords detected.',
              textAlign: TextAlign.center,
              style: _text(
                11,
                const Color(0xFF9AAABB),
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordAuditReportPane extends StatelessWidget {
  const _PasswordAuditReportPane({
    required this.report,
    required this.duplicatedCount,
    required this.weakCount,
    required this.staleCount,
    required this.onIssueSelected,
  });

  final List<PasswordAuditEntry> report;
  final int duplicatedCount;
  final int weakCount;
  final int staleCount;
  final ValueChanged<PasswordAuditIssue> onIssueSelected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(TablerIcons.shield_check,
                    size: 32, color: Color(0xFF374151)),
                const SizedBox(width: 12),
                Text(
                  'Security Checkup',
                  style: _text(32, const Color(0xFF111827),
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(
                'Review passwords that need attention across this vault. LumenPass groups duplicate, weak, and long-unchanged credentials so you can clean them up faster.',
                style: _text(14, const Color(0xFF4B5563), height: 1.5),
              ),
            ),
            const SizedBox(height: 40),
            Text('Overall Password Strength',
                style: _text(16, const Color(0xFF111827),
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Container(
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFEF4444),
                    Color(0xFFF59E0B),
                    Color(0xFF10B981)
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 24,
              crossAxisSpacing: 24,
              childAspectRatio: 1.8,
              children: <Widget>[
                _AuditReportCard(
                  count: duplicatedCount,
                  title: 'Duplicate items',
                  description:
                      'Items where the title, username/email and password all match. Review the matching groups so you can merge or remove the extras.',
                  icon: TablerIcons.copy,
                  iconColor: const Color(0xFFFCA5A5),
                  onTap: () => onIssueSelected(PasswordAuditIssue.duplicated),
                ),
                _AuditReportCard(
                  count: weakCount,
                  title: 'Weak passwords',
                  description:
                      'Weak passwords are easier to guess. Generate strong passwords to keep your accounts safe.',
                  icon: TablerIcons.lock_off,
                  iconColor: const Color(0xFFFED7AA),
                  onTap: () => onIssueSelected(PasswordAuditIssue.weak),
                ),
                _AuditReportCard(
                  count: staleCount,
                  title: 'Too old updated',
                  description:
                      'Passwords that haven’t been changed in a long time might be at risk. Consider rotating them.',
                  icon: TablerIcons.clock_off,
                  iconColor: const Color(0xFFD1D5DB),
                  onTap: () => onIssueSelected(PasswordAuditIssue.stale),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditReportCard extends StatelessWidget {
  const _AuditReportCard({
    required this.count,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final int count;
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('$count',
                    style: _text(32, const Color(0xFF111827),
                        fontWeight: FontWeight.w700)),
                Icon(icon, size: 32, color: iconColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(title,
                style: _text(14, const Color(0xFF111827),
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                description,
                style: _text(12, const Color(0xFF6B7280), height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('Show Items',
                    style: _text(12, const Color(0xFF2563EB),
                        fontWeight: FontWeight.w600)),
                const Icon(TablerIcons.arrow_right,
                    size: 14, color: Color(0xFF2563EB)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordAuditDrilldownHeader extends StatelessWidget {
  const _PasswordAuditDrilldownHeader({
    required this.issue,
    required this.resultCount,
    required this.onBack,
    this.duplicateGroupLabel,
    this.itemsLabel,
  });

  final PasswordAuditIssue? issue;
  final int resultCount;
  final VoidCallback onBack;

  /// When non-null, the drilldown is showing entries belonging to a
  /// specific duplicate group (level 3 of the duplicate flow). The label
  /// is shown as the header title in place of the generic issue title.
  final String? duplicateGroupLabel;

  /// Optional override for the subtitle suffix. Defaults to "items".
  final String? itemsLabel;

  @override
  Widget build(BuildContext context) {
    final String title;
    if (duplicateGroupLabel != null) {
      title = duplicateGroupLabel!;
    } else {
      title = switch (issue) {
        PasswordAuditIssue.duplicated => 'Duplicate items',
        PasswordAuditIssue.weak => 'Weak passwords',
        PasswordAuditIssue.stale => 'Too old updated',
        null => 'Password Audits',
      };
    }
    final subtitleSuffix = itemsLabel ?? 'items';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F3FF),
        border: Border(
          bottom: BorderSide(color: _VaultColors.borderPane),
        ),
      ),
      child: Row(
        children: <Widget>[
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(TablerIcons.arrow_left,
                  size: 16, color: Color(0xFF3A4457)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _text(12, const Color(0xFF3A4457),
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  '$resultCount $subtitleSuffix',
                  style: _text(10, const Color(0xFF6B7280),
                      fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Level-2 view of the duplicate-items audit flow: shows one card per
/// duplicate group (entries that share the exact same URL, username and
/// password). Tapping a group drills further into the matching entries.
class _PasswordAuditDuplicateGroupsPane extends StatelessWidget {
  const _PasswordAuditDuplicateGroupsPane({
    required this.groups,
    required this.onGroupSelected,
    required this.onBack,
  });

  final List<DuplicateItemGroup> groups;
  final ValueChanged<String> onGroupSelected;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PasswordAuditDrilldownHeader(
            issue: PasswordAuditIssue.duplicated,
            resultCount: groups.length,
            onBack: onBack,
            itemsLabel: groups.length == 1 ? 'group' : 'groups',
          ),
          Expanded(
            child: groups.isEmpty
                ? const _PasswordAuditEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return _DuplicateGroupCard(
                        group: group,
                        onTap: () => onGroupSelected(group.key),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({
    required this.group,
    required this.onTap,
  });

  final DuplicateItemGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = group.title.trim();
    final username = group.username.trim();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  TablerIcons.copy,
                  size: 18,
                  color: Color(0xFFB91C1C),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title.isNotEmpty
                          ? title
                          : (username.isNotEmpty
                              ? username
                              : group.entries.first.title),
                      style: _text(13, const Color(0xFF111827),
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (username.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        username,
                        style: _text(11, const Color(0xFF6B7280)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.count} items',
                  style: _text(10, const Color(0xFFB91C1C),
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(TablerIcons.chevron_right,
                  size: 16, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium-gate variant of the password audit landing screen. Shown when
/// a free or signed-out user navigates into Password Audits. Rendered as
/// inline content (no popup / modal overlay) so it sits in the same
/// visual rhythm as the real Security Checkup page.
class _PasswordAuditPremiumGate extends StatelessWidget {
  const _PasswordAuditPremiumGate({
    required this.isLoggedIn,
    required this.onUpgrade,
    required this.onSignIn,
  });

  final bool isLoggedIn;
  final VoidCallback onUpgrade;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        color: const Color(0xFFF9FAFB),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Decorative low-opacity preview of the real Security Checkup
            // page tucked behind the bottom-right corner and rotated about
            // 45° clockwise so it reads like a "mirror reflection" sitting
            // behind the upsell content rather than a popup overlay.
            Positioned(
              right: -260,
              bottom: -200,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.18,
                  child: Transform.rotate(
                    angle: 45 * math.pi / 180,
                    alignment: Alignment.bottomRight,
                    child: Image.asset(
                      'assets/images/password_audit_preview.png',
                      width: 900,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(TablerIcons.shield_check,
                        size: 32, color: Color(0xFF374151)),
                    const SizedBox(width: 12),
                    Text(
                      'Security Checkup',
                      style: _text(32, const Color(0xFF111827),
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFFFD58A)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(TablerIcons.crown,
                              size: 12, color: Color(0xFFB7791F)),
                          const SizedBox(width: 4),
                          Text(
                            'PREMIUM',
                            style: _text(10, const Color(0xFF92400E),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Text(
                    isLoggedIn
                        ? 'Password Audit is a Premium feature. Upgrade to scan your vault for duplicate, weak, and stale credentials.'
                        : 'Password Audit is a Premium feature. Sign in with your Premium account, or upgrade to start scanning your vault for duplicate, weak, and stale credentials.',
                    style: _text(14, const Color(0xFF4B5563), height: 1.5),
                  ),
                ),
                const SizedBox(height: 28),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Row(
                    children: <Widget>[
                      _PasswordAuditPremiumPrimaryButton(
                        label: isLoggedIn ? 'Upgrade to Premium' : 'See plans',
                        onTap: onUpgrade,
                      ),
                      if (!isLoggedIn) ...<Widget>[
                        const SizedBox(width: 10),
                        _PasswordAuditPremiumSecondaryButton(
                          label: 'Sign in',
                          onTap: onSignIn,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  'What you\'ll unlock',
                  style: _text(16, const Color(0xFF111827),
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 24,
                  childAspectRatio: 1.8,
                  children: const <Widget>[
                    _PasswordAuditPremiumCard(
                      title: 'Duplicate items',
                      description:
                          'Items where the title, username/email and password all match. Review the matching groups so you can merge or remove the extras.',
                      icon: TablerIcons.copy,
                      iconColor: Color(0xFFFCA5A5),
                    ),
                    _PasswordAuditPremiumCard(
                      title: 'Weak passwords',
                      description:
                          'Weak passwords are easier to guess. Generate strong passwords to keep your accounts safe.',
                      icon: TablerIcons.lock_off,
                      iconColor: Color(0xFFFED7AA),
                    ),
                    _PasswordAuditPremiumCard(
                      title: 'Too old updated',
                      description:
                          'Passwords that haven\'t been changed in a long time might be at risk. Consider rotating them.',
                      icon: TablerIcons.clock_off,
                      iconColor: Color(0xFFD1D5DB),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Locked-state preview card matching the geometry of [_AuditReportCard]
/// but with a lock indicator instead of a count, and no tap target.
class _PasswordAuditPremiumCard extends StatelessWidget {
  const _PasswordAuditPremiumCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(TablerIcons.lock,
                        size: 12, color: Color(0xFF6B7280)),
                    const SizedBox(width: 4),
                    Text(
                      'Locked',
                      style: _text(10, const Color(0xFF6B7280),
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Icon(icon, size: 32, color: iconColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(title,
              style: _text(14, const Color(0xFF111827),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              description,
              style: _text(12, const Color(0xFF6B7280), height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordAuditPremiumPrimaryButton extends StatelessWidget {
  const _PasswordAuditPremiumPrimaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFB7791F),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(TablerIcons.crown, size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: _text(13, Colors.white,
                    fontWeight: FontWeight.w700, letterSpacing: 0.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordAuditPremiumSecondaryButton extends StatelessWidget {
  const _PasswordAuditPremiumSecondaryButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: Text(
            label,
            style: _text(13, const Color(0xFF111827),
                fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
