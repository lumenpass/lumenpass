part of 'vault_screen.dart';

// ───────────────────────────────────────────────────────────────────────
// Layout note (independent scroll / decoupled headers):
//
//   Until v1.x the desktop window used a single full-width title strip
//   (height 104) that hosted BOTH the greeting block (left, 230 px) and
//   the search row (right). Because the strip's height was driven by the
//   tall greeting block, the right half ended up with ~46 px of unused
//   vertical space below the search row — visually "syncing" the right
//   header with the left greeting's bottom divider.
//
//   The two halves are now decoupled: the greeting block is rendered as
//   _VaultGreetingHeader sitting on top of _SidebarPane in the LEFT
//   column (content-sized), while _VaultTitleBar renders ONLY the search +
//   New Item row in the RIGHT column at its natural ~58 px height.
//   Both top strips paint their own bottom border, but each can grow /
//   shrink without affecting the other.
// ───────────────────────────────────────────────────────────────────────

class _VaultTitleBar extends ConsumerStatefulWidget {
  const _VaultTitleBar({
    super.key,
    required this.onNewItemPressed,
    required this.onImportPressed,
    required this.onEntryRequested,
  });

  final VoidCallback onNewItemPressed;
  final VoidCallback onImportPressed;
  final ValueChanged<String> onEntryRequested;

  @override
  ConsumerState<_VaultTitleBar> createState() => _VaultTitleBarState();
}

class _VaultTitleBarState extends ConsumerState<_VaultTitleBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final OverlayPortalController _searchOverlayController =
      OverlayPortalController();
  final LayerLink _searchFieldLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_syncSearchOverlay);
  }

  @override
  void dispose() {
    _searchFocusNode
      ..removeListener(_syncSearchOverlay)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void focusSearch() {
    _searchFocusNode.requestFocus();
  }

  void _syncSearchOverlay() {
    final shouldShow = _searchFocusNode.hasFocus &&
        ref.read(vaultSearchDraftProvider).trim().isNotEmpty;
    if (shouldShow) {
      _searchOverlayController.show();
    } else {
      _searchOverlayController.hide();
    }
  }

  void _onSearchChanged(String value) {
    ref.read(vaultSearchDraftProvider.notifier).state = value;
    _syncSearchOverlay();
  }

  void _applySearch([String? value]) {
    final query = (value ?? _searchController.text).trim();
    ref
        .read(vaultSearchSuggestionsStateProvider.notifier)
        .cancelPendingSearch(clearResults: true);
    ref.read(vaultSearchDraftProvider.notifier).state = query;
    ref.read(vaultSearchQueryProvider.notifier).state = query;
    _searchFocusNode.unfocus();
    _syncSearchOverlay();
  }

  void _clearSearch() {
    _searchController.clear();
    ref
        .read(vaultSearchSuggestionsStateProvider.notifier)
        .cancelPendingSearch(clearResults: true);
    ref.read(vaultSearchDraftProvider.notifier).state = '';
    ref.read(vaultSearchQueryProvider.notifier).state = '';
    _searchFocusNode.unfocus();
    _syncSearchOverlay();
  }

  void _selectSuggestion(KdbxEntry entry) {
    _searchController.clear();
    ref
        .read(vaultSearchSuggestionsStateProvider.notifier)
        .cancelPendingSearch(clearResults: true);
    ref.read(vaultSearchDraftProvider.notifier).state = '';
    ref.read(vaultSearchQueryProvider.notifier).state = '';
    widget.onEntryRequested(entry.uuid);
    _searchFocusNode.unfocus();
    _syncSearchOverlay();
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
    final searchIsActive = _searchFocusNode.hasFocus ||
        trimmedDraftQuery.isNotEmpty ||
        appliedQuery.trim().isNotEmpty;

    if (_searchController.text != draftQuery) {
      _searchController.value = TextEditingValue(
        text: draftQuery,
        selection: TextSelection.collapsed(offset: draftQuery.length),
      );
    }

    // Sync overlay visibility after this frame. The title bar only
    // rebuilds when search draft/suggestions/active database etc. change
    // — so this post-frame callback is bound to real state changes, not
    // a clock tick.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncSearchOverlay();
    });

    // Right-only title strip (search + New Item). It hugs its content
    // height (~58 px = top 12 + 34 search field + bottom 12) so it stops
    // inheriting the taller greeting block's height. See the layout note
    // at the top of this file for context.
    return Container(
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(
        color: _VaultColors.sidebar,
        border: Border(
          bottom: BorderSide(color: _VaultColors.borderSoft),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const SizedBox(width: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final searchFieldWidth = constraints.maxWidth;
                  final dropdownWidth = math.min(searchFieldWidth, 650.0);
                  return TextFieldTapRegion(
                    child: OverlayPortal(
                      controller: _searchOverlayController,
                      overlayChildBuilder: (context) {
                        if (!_searchFocusNode.hasFocus ||
                            trimmedDraftQuery.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return TextFieldTapRegion(
                          child: CompositedTransformFollower(
                            link: _searchFieldLink,
                            showWhenUnlinked: false,
                            targetAnchor: Alignment.bottomLeft,
                            followerAnchor: Alignment.topLeft,
                            offset: const Offset(0, 8),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                color: Colors.transparent,
                                child: SizedBox(
                                  width: dropdownWidth,
                                  child: _SearchSuggestionDropdown(
                                    query: trimmedDraftQuery,
                                    suggestions: suggestions,
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
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isSearching
                                ? const Color(0xFFF8FAFC)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: searchIsActive
                                  ? const Color(0xFF0A67FF)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                TablerIcons.search,
                                size: 16,
                                color: searchIsActive
                                    ? const Color(0xFF0A67FF)
                                    : _VaultColors.icon,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  focusNode: _searchFocusNode,
                                  controller: _searchController,
                                  // Never make the field read-only: search is
                                  // live and runs in well under a frame, so
                                  // blocking keystrokes here is what made
                                  // typing feel janky.
                                  onChanged: _onSearchChanged,
                                  onSubmitted: _applySearch,
                                  onTapOutside: (_) =>
                                      _searchFocusNode.unfocus(),
                                  decoration: InputDecoration(
                                    hintText: 'Search credentials',
                                    hintStyle: _text(
                                      12,
                                      const Color(0xFF98A2B3),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    isCollapsed: true,
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  style: _text(
                                    12,
                                    _VaultColors.title,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  cursorColor: const Color(0xFF344054),
                                ),
                              ),
                              if (isSearching) ...<Widget>[
                                const SizedBox(width: 8),
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF0A67FF),
                                    ),
                                  ),
                                ),
                              ],
                              if (trimmedDraftQuery.isNotEmpty ||
                                  appliedQuery.trim().isNotEmpty)
                                GestureDetector(
                                  onTap: isSearching ? null : _clearSearch,
                                  child: const Icon(
                                    TablerIcons.x,
                                    size: 14,
                                    color: _VaultColors.icon,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            _PasswordGeneratorIconButton(
              onPressed: () => _showPasswordGeneratorDialog(context),
            ),
            const SizedBox(width: 8),
            _ImportButton(onPressed: widget.onImportPressed),
            const SizedBox(width: 8),
            _NewItemButton(onPressed: widget.onNewItemPressed),
            const SizedBox(width: 16),
          ],
        ),
      ),
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
        bg = const Color(0xFFF0F4FF);
        break;
      case 'dropbox':
        asset = 'assets/images/dropbox.png';
        bg = const Color(0xFFEFF6FF);
        break;
      case 'oneDrive':
        asset = 'assets/images/onedrive.png';
        bg = const Color(0xFFE8F4FD);
        break;
      case 'webdav':
        asset = 'assets/images/webdav.png';
        bg = const Color(0xFFEFF3F8);
        break;
      case 'sftp':
        asset = 'assets/images/sftp.png';
        bg = const Color(0xFFEFF3F8);
        break;
      default:
        asset = 'assets/images/dir.png';
        bg = const Color(0xFFF3F4F6);
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
    required this.onSuggestionSelected,
    required this.onSearchAll,
    required this.subtitleBuilder,
  });

  final String query;
  final List<KdbxEntry> suggestions;
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E2EF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 26,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (visibleSuggestions.isNotEmpty)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: visibleSuggestions.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFECF1F8)),
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
            const Divider(height: 1, color: Color(0xFFECF1F8)),
          InkWell(
            onTap: onSearchAll,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  const Icon(
                    TablerIcons.search,
                    size: 16,
                    color: Color(0xFF7C869B),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: _text(
                          12,
                          const Color(0xFF65748B),
                          fontWeight: FontWeight.w500,
                        ),
                        children: <InlineSpan>[
                          TextSpan(
                            text: 'Search for all matches ',
                            style: _text(
                              12,
                              const Color(0xFF65748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: '"$query"',
                            style: _text(
                              12,
                              const Color(0xFF2D3A4F),
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
          color: _hovered ? const Color(0xFFF4F8FF) : Colors.transparent,
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
                        const Color(0xFF243247),
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
                          const Color(0xFF7A869A),
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
                color: Color(0xFF9AA5B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────
// _VaultGreetingHeader
//
// The content-sized greeting block that used to live inside the left half of
// _VaultTitleBar. Now rendered as a standalone widget on top of _SidebarPane in
// the LEFT column of _VaultWindow, so its height no longer dictates the right
// column's search-row position. Its bottom border is the "left panel divider
// line" referenced by users.
//
// Hosts the local-vault session label and Settings gear.
// ───────────────────────────────────────────────────────────────────────

class _VaultGreetingHeader extends StatelessWidget {
  const _VaultGreetingHeader({required this.onSettingsPressed});

  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    final double topInset = Platform.isMacOS ? 30 : 8;
    return Container(
      width: 230,
      decoration: const BoxDecoration(
        color: _sidebarBackgroundColor,
        border: Border(
          right: BorderSide(color: _sidebarBorderColor),
          bottom: BorderSide(color: _VaultColors.borderSoft),
        ),
      ),
      padding: EdgeInsets.fromLTRB(12, topInset, 8, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'LumenPass',
                  style: _text(13, _VaultColors.title,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Local vault session',
                  style: _text(10, _VaultColors.headerLabel,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettingsPressed,
            icon: const Icon(TablerIcons.settings, size: 17),
            color: _VaultColors.headerLabel,
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _ImportButton extends StatefulWidget {
  const _ImportButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends State<_ImportButton> {
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
                const Icon(TablerIcons.download, size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Import',
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
