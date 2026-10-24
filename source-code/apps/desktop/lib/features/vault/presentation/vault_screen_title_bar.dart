part of 'vault_screen.dart';

/// Kept in sync with the tagline on the desktop splash screen.
const String _kAppTagline = 'Private by default. Yours to control.';

/// DriveClue-style 46 px header: app name and tagline on the left (the vault
/// name already lives in the sidebar), icon-only actions on the right.
class _VaultTitleBar extends StatelessWidget {
  const _VaultTitleBar({
    required this.onImportPressed,
    required this.onSettingsPressed,
  });

  final VoidCallback onImportPressed;
  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DcMetrics.headerHeight,
      decoration: const BoxDecoration(
        color: DcColors.background,
        border: Border(
          bottom: BorderSide(color: DcColors.line),
        ),
      ),
      padding: const EdgeInsets.only(left: 18, right: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Two-tone brand wordmark, same colors as the dark splash screen.
          LumenPassWordmark(
            fontSize: (15 + currentTextSizeDelta).toDouble(),
            lumenColor: DcColors.text,
            passColor: DcColors.cyan,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _kAppTagline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(12, DcColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          DcBorderedButton(
            icon: TablerIcons.wand,
            tooltip: 'Generate password',
            height: 28,
            onPressed: () => _showPasswordGeneratorDialog(context),
          ),
          const SizedBox(width: 6),
          DcBorderedButton(
            icon: TablerIcons.download,
            tooltip: 'Import items',
            height: 28,
            onPressed: onImportPressed,
          ),
          const SizedBox(width: 6),
          DcBorderedButton(
            icon: TablerIcons.settings,
            tooltip: 'Settings',
            height: 28,
            onPressed: onSettingsPressed,
          ),
        ],
      ),
    );
  }
}

class _VaultFloatingActions extends ConsumerStatefulWidget {
  const _VaultFloatingActions({
    super.key,
    required this.onNewItemPressed,
    required this.onEntryRequested,
  });

  final VoidCallback onNewItemPressed;
  final ValueChanged<String> onEntryRequested;

  @override
  ConsumerState<_VaultFloatingActions> createState() =>
      _VaultFloatingActionsState();
}

class _VaultFloatingActionsState extends ConsumerState<_VaultFloatingActions> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final OverlayPortalController _searchOverlayController =
      OverlayPortalController();
  final LayerLink _searchFieldLink = LayerLink();
  bool _searchIsOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyboardShortcut);
  }

  bool _handleKeyboardShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        (keyboard.isMetaPressed || keyboard.isControlPressed)) {
      _openSearch();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _searchIsOpen) {
      _closeSearch();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboardShortcut);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void focusSearch() {
    _openSearch();
  }

  void _openSearch() {
    if (!_searchIsOpen) {
      setState(() => _searchIsOpen = true);
    }
    _searchOverlayController.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_searchIsOpen) return;
    _searchFocusNode.unfocus();
    _searchOverlayController.hide();
    setState(() => _searchIsOpen = false);
  }

  void _onSearchChanged(String value) {
    ref.read(vaultSearchDraftProvider.notifier).state = value;
  }

  void _applySearch([String? value]) {
    final query = (value ?? _searchController.text).trim();
    ref
        .read(vaultSearchSuggestionsStateProvider.notifier)
        .cancelPendingSearch(clearResults: true);
    ref.read(vaultSearchDraftProvider.notifier).state = query;
    ref.read(vaultSearchQueryProvider.notifier).state = query;
    _closeSearch();
  }

  void _clearSearch() {
    _searchController.clear();
    ref
        .read(vaultSearchSuggestionsStateProvider.notifier)
        .cancelPendingSearch(clearResults: true);
    ref.read(vaultSearchDraftProvider.notifier).state = '';
    ref.read(vaultSearchQueryProvider.notifier).state = '';
    _searchFocusNode.requestFocus();
  }

  void _selectSuggestion(KdbxEntry entry) {
    _searchController.clear();
    ref
        .read(vaultSearchSuggestionsStateProvider.notifier)
        .cancelPendingSearch(clearResults: true);
    ref.read(vaultSearchDraftProvider.notifier).state = '';
    ref.read(vaultSearchQueryProvider.notifier).state = '';
    widget.onEntryRequested(entry.uuid);
    _closeSearch();
  }

  String? _suggestionSubtitle(KdbxEntry entry) {
    final username = entry.username?.trim() ?? '';
    if (username.isNotEmpty) {
      return username;
    }

    final email = entry.fieldByKey('email')?.value.trim() ??
        entry.fieldByKey('e-mail')?.value.trim() ??
        '';
    if (email.isNotEmpty) {
      return email;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final draftQuery = ref.watch(vaultSearchDraftProvider);
    final appliedQuery = ref.watch(vaultSearchQueryProvider);
    final suggestions = ref.watch(vaultSearchSuggestionsProvider);
    final isSearching = ref.watch(vaultSearchSuggestionsLoadingProvider);
    final trimmedDraftQuery = draftQuery.trim();
    final searchIsActive = appliedQuery.trim().isNotEmpty;

    if (_searchController.text != draftQuery) {
      _searchController.value = TextEditingValue(
        text: draftQuery,
        selection: TextSelection.collapsed(offset: draftQuery.length),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedSearchWidth = math.min(
          440.0,
          math.max(220.0, constraints.maxWidth - 52),
        );

        return Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OverlayPortal(
                controller: _searchOverlayController,
                overlayChildBuilder: (context) {
                  if (!_searchIsOpen || trimmedDraftQuery.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return CompositedTransformFollower(
                    link: _searchFieldLink,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.topRight,
                    followerAnchor: Alignment.bottomRight,
                    offset: const Offset(0, -8),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Material(
                        color: Colors.transparent,
                        child: TextFieldTapRegion(
                          child: SizedBox(
                            width: expandedSearchWidth,
                            child: _SearchSuggestionDropdown(
                              query: trimmedDraftQuery,
                              suggestions: suggestions,
                              isSearching: isSearching,
                              onSuggestionSelected: _selectSuggestion,
                              onSearchAll: () =>
                                  _applySearch(trimmedDraftQuery),
                              subtitleBuilder: _suggestionSubtitle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: CompositedTransformTarget(
                  link: _searchFieldLink,
                  child: TextFieldTapRegion(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: _searchIsOpen ? expandedSearchWidth : 38,
                      height: 38,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: DcColors.lightSurface,
                        borderRadius:
                            BorderRadius.circular(DcMetrics.panelRadius),
                        border: Border.all(
                          color: _searchIsOpen
                              ? _kPrimaryButtonColor
                              : DcColors.lightLineStrong,
                          width: _searchIsOpen ? 1.25 : 1,
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x1F263340),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: _searchIsOpen
                          ? Stack(
                              children: <Widget>[
                                const Positioned(
                                  left: 12,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: Icon(
                                      TablerIcons.search,
                                      size: 17,
                                      color: _kPrimaryButtonColor,
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 39,
                                      right: 39,
                                    ),
                                    child: Center(
                                      child: TextField(
                                        focusNode: _searchFocusNode,
                                        controller: _searchController,
                                        onChanged: _onSearchChanged,
                                        onSubmitted: _applySearch,
                                        onTapOutside: (_) => _closeSearch(),
                                        decoration: InputDecoration(
                                          hintText: 'Search credentials',
                                          hintStyle: _text(
                                            12,
                                            DcColors.sidebarMuted,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          isCollapsed: true,
                                          filled: false,
                                          fillColor: Colors.transparent,
                                          hoverColor: Colors.transparent,
                                          contentPadding: EdgeInsets.zero,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          disabledBorder: InputBorder.none,
                                          errorBorder: InputBorder.none,
                                          focusedErrorBorder: InputBorder.none,
                                        ),
                                        style: _text(
                                          12,
                                          DcColors.sidebarText,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        cursorColor: _kPrimaryButtonColor,
                                      ),
                                    ),
                                  ),
                                ),
                                if (isSearching)
                                  const Positioned(
                                    right: 32,
                                    top: 0,
                                    bottom: 0,
                                    child: Center(
                                      child: SizedBox(
                                        width: 13,
                                        height: 13,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: _kPrimaryButtonColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  right: 7,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: _AppTooltip(
                                      message: trimmedDraftQuery.isNotEmpty ||
                                              searchIsActive
                                          ? 'Clear search'
                                          : 'Close search',
                                      child: InkWell(
                                        onTap: trimmedDraftQuery.isNotEmpty ||
                                                searchIsActive
                                            ? _clearSearch
                                            : _closeSearch,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(
                                            TablerIcons.x,
                                            size: 14,
                                            color: DcColors.sidebarMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _AppTooltip(
                              message: 'Search credentials (⌘F)',
                              child: InkWell(
                                onTap: _openSearch,
                                borderRadius: BorderRadius.circular(
                                    DcMetrics.panelRadius),
                                child: Center(
                                  child: Icon(
                                    TablerIcons.search,
                                    size: 17,
                                    color: searchIsActive
                                        ? _kPrimaryButtonColor
                                        : DcColors.sidebarText,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              _NewItemButton(onPressed: widget.onNewItemPressed),
            ],
          ),
        );
      },
    );
  }
}

class _VaultStorageIcon extends StatelessWidget {
  const _VaultStorageIcon({
    required this.record,
    this.size = 16,
    this.iconSize = 12,
    this.borderRadius = 4,
  });

  final DatabaseRecord? record;
  final double size;
  final double iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final storageType = record?.storageType ?? 'local';

    final String asset;
    final Color bg;
    switch (storageType) {
      case 'googleDrive':
        asset = 'assets/images/google-drive.png';
        bg = DcColors.rowAlternate;
        break;
      case 'dropbox':
        asset = 'assets/images/dropbox.png';
        bg = DcColors.rowAlternate;
        break;
      case 'oneDrive':
        asset = 'assets/images/onedrive.png';
        bg = DcColors.rowAlternate;
        break;
      case 'webdav':
        asset = 'assets/images/webdav.png';
        bg = DcColors.rowAlternate;
        break;
      case 'sftp':
        asset = 'assets/images/sftp.png';
        bg = DcColors.rowAlternate;
        break;
      default:
        asset = 'assets/images/dir.png';
        bg = DcColors.rowAlternate;
        break;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: Image.asset(asset, width: iconSize, height: iconSize),
    );
  }
}

class _SearchSuggestionDropdown extends StatelessWidget {
  const _SearchSuggestionDropdown({
    required this.query,
    required this.suggestions,
    required this.isSearching,
    required this.onSuggestionSelected,
    required this.onSearchAll,
    required this.subtitleBuilder,
  });

  final String query;
  final List<KdbxEntry> suggestions;
  final bool isSearching;
  final ValueChanged<KdbxEntry> onSuggestionSelected;
  final VoidCallback onSearchAll;
  final String? Function(KdbxEntry entry) subtitleBuilder;

  @override
  Widget build(BuildContext context) {
    const maxVisibleSuggestions = 5;
    final visibleSuggestions =
        suggestions.take(maxVisibleSuggestions).toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: DcColors.lightSurface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: DcColors.sidebarLine),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x29263340),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    isSearching
                        ? 'Searching…'
                        : visibleSuggestions.isEmpty
                            ? 'No quick matches'
                            : '${visibleSuggestions.length} quick ${visibleSuggestions.length == 1 ? 'match' : 'matches'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      11,
                      DcColors.sidebarMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'Enter to search all',
                  style: _text(
                    10,
                    DcColors.sidebarMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: DcColors.sidebarLine),
          if (visibleSuggestions.isNotEmpty)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: visibleSuggestions.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                color: DcColors.sidebarLine,
              ),
              itemBuilder: (context, index) {
                final entry = visibleSuggestions[index];
                return _SearchSuggestionRow(
                  entry: _mockEntryFromKdbx(entry),
                  subtitle: subtitleBuilder(entry),
                  onTap: () => onSuggestionSelected(entry),
                );
              },
            ),
          if (visibleSuggestions.isNotEmpty)
            const Divider(height: 1, color: DcColors.sidebarLine),
          InkWell(
            onTap: onSearchAll,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(DcMetrics.panelRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  const Icon(
                    TablerIcons.search,
                    size: 16,
                    color: DcColors.sidebarMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: _text(
                          12,
                          DcColors.sidebarMuted,
                          fontWeight: FontWeight.w500,
                        ),
                        children: <InlineSpan>[
                          TextSpan(
                            text: 'Search for all matches ',
                            style: _text(
                              12,
                              DcColors.sidebarMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: '"$query"',
                            style: _text(
                              12,
                              DcColors.sidebarText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
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
}

class _SearchSuggestionRow extends StatefulWidget {
  const _SearchSuggestionRow({
    required this.entry,
    required this.onTap,
    this.subtitle,
  });

  final _MockEntry entry;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  State<_SearchSuggestionRow> createState() => _SearchSuggestionRowState();
}

class _SearchSuggestionRowState extends State<_SearchSuggestionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: _hovered ? DcColors.sidebarHover : Colors.transparent,
          child: Row(
            children: <Widget>[
              _FaviconTile(entry: widget.entry, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        12,
                        DcColors.sidebarText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.subtitle != null &&
                        widget.subtitle!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          11,
                          DcColors.sidebarMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (widget.entry.totpAuthUrl.isNotEmpty ||
                  widget.entry.hasPasskeyChip) ...<Widget>[
                if (widget.entry.totpAuthUrl.isNotEmpty)
                  ValueListenableBuilder<DateTime>(
                    valueListenable: _TimeScope.of(context),
                    builder: (context, currentTime, _) {
                      final totpCode =
                          _formattedTotpCode(widget.entry, currentTime);
                      final totpSecs =
                          _totpSecondsRemaining(widget.entry, currentTime);
                      final totpColor = _totpCountdownColor(totpSecs);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: totpColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(TablerIcons.clock, size: 11, color: totpColor),
                            const SizedBox(width: 3),
                            Text(
                              totpCode,
                              style: _text(10, totpColor,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                if (widget.entry.hasPasskeyChip) ...<Widget>[
                  if (widget.entry.totpAuthUrl.isNotEmpty)
                    const SizedBox(width: 4),
                  Image.asset(
                    'assets/images/passkey_icon.png',
                    width: 26,
                    height: 26,
                  ),
                ],
                const SizedBox(width: 10),
              ],
              const Icon(
                TablerIcons.arrow_up_left,
                size: 16,
                color: DcColors.sidebarMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────
class _VaultToolbarIconButton extends StatefulWidget {
  const _VaultToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool primary;

  @override
  State<_VaultToolbarIconButton> createState() =>
      _VaultToolbarIconButtonState();
}

class _VaultToolbarIconButtonState extends State<_VaultToolbarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fill = widget.primary
        ? (_hovered ? _kPrimaryButtonHoverColor : _kPrimaryButtonColor)
        : _hovered
            ? DcColors.lightInset
            : DcColors.lightSurface;
    final iconColor = widget.primary ? Colors.white : DcColors.sidebarText;

    return _AppTooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
                  border: Border.all(
                    color: widget.primary
                        ? _kPrimaryButtonHoverColor
                        : DcColors.lightLineStrong,
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1F263340),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(widget.icon, size: 17, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
