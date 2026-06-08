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
    required this.onEntryRequested,
  });

  final VoidCallback onNewItemPressed;
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
                                  readOnly: isSearching,
                                  showCursor: !isSearching,
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

// ───────────────────────────────────────────────────────────────────────
// Greeting + plan section that replaces the old vault-name title-bar slot.
// Authenticated:   "Hi <Name>"  · logout button
//                  "<Plan> - Expires: MM/DD/YYYY"   (or just "Lifetime")
// Unauthenticated: "Hello Guest"  · login button
//                  "FREE"
// ───────────────────────────────────────────────────────────────────────

class _AccountGreetingSection extends StatelessWidget {
  const _AccountGreetingSection({
    required this.account,
    required this.onLoginPressed,
    required this.onLogoutPressed,
    required this.onSettingsPressed,
  });

  final AccountState account;
  final VoidCallback onLoginPressed;
  final VoidCallback onLogoutPressed;
  final VoidCallback onSettingsPressed;

  String _greetingName() {
    final display = account.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final email = account.email?.trim() ?? '';
    if (email.isNotEmpty) {
      final at = email.indexOf('@');
      return at > 0 ? email.substring(0, at) : email;
    }
    return 'there';
  }

  bool _isLifetime(SubscriptionInfo sub) {
    final code = (sub.planCode ?? '').toLowerCase();
    final name = (sub.planName ?? '').toLowerCase();
    final interval = (sub.interval ?? '').toLowerCase();
    if (code == 'lifetime' ||
        name.contains('lifetime') ||
        interval == 'lifetime') {
      return true;
    }
    // Active paid plan with no period end is treated as lifetime.
    if (sub.isActivePaid &&
        sub.currentPeriodEnd == null &&
        sub.trialEndsAt == null) {
      return true;
    }
    return false;
  }

  String _formatDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final yyyy = d.year.toString().padLeft(4, '0');
    return '$mm/$dd/$yyyy';
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = account.isLoggedIn;
    final sub = account.subscription;
    final String greetingName = _greetingName();

    void onPlanPressed() => _showAccountPlanStatusDialog(context, account);

    // Determine plan tag label and colors. Strip recurring suffixes like
    // "Monthly" / "Yearly" / "Annual" so the tag shows only the plan tier.
    final bool isLifetime = isLoggedIn && _isLifetime(sub);
    final bool isPremium = isLoggedIn && (sub.isActivePaid || isLifetime);

    String planLabel;
    if (!isLoggedIn) {
      planLabel = 'FREE';
    } else if (isLifetime) {
      planLabel = 'Lifetime';
    } else if (sub.isActivePaid) {
      final raw = (sub.planName?.trim().isNotEmpty ?? false)
          ? sub.planName!.trim()
          : 'Premium';
      planLabel = _stripPlanRecurringSuffix(raw);
    } else {
      planLabel = 'FREE';
    }

    String? expiryLine;
    if (isLoggedIn && !isLifetime && sub.isActivePaid) {
      final expiry = sub.currentPeriodEnd ?? sub.trialEndsAt;
      if (expiry != null) {
        expiryLine = 'Expires: ${_formatDate(expiry)}';
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: isLoggedIn
                  ? Row(
                      children: <Widget>[
                        Text(
                          '🎉 Hi ',
                          style: _text(
                            10,
                            _sidebarTextPrimary,
                            fontWeight: FontWeight.w400,
                            height: 1.1,
                          ),
                        ),
                        Flexible(
                          child: _GreetingPlanLinkText(
                            label: greetingName,
                            onTap: onPlanPressed,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Hello Guest',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        10,
                        _sidebarTextPrimary,
                        fontWeight: FontWeight.w400,
                        height: 1.1,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            isLoggedIn
                ? _GreetingActionButton(
                    label: '',
                    icon: TablerIcons.logout,
                    onPressed: onLogoutPressed,
                    background: const Color(0xFFDC2626),
                    hoverBackground: const Color(0xFFB91C1C),
                    foreground: Colors.white,
                    borderColor: const Color(0xFFDC2626),
                    semanticsLabel: 'Logout',
                    tooltip: 'Logout',
                  )
                : _GreetingActionButton(
                    label: 'Login',
                    icon: TablerIcons.login_2,
                    onPressed: onLoginPressed,
                    background: Colors.white,
                    hoverBackground: const Color(0xFFE5E7EB),
                    foreground: const Color(0xFF0A3B48),
                    borderColor: Colors.white,
                  ),
            const SizedBox(width: 6),
            _GreetingActionButton(
              label: '',
              icon: TablerIcons.settings,
              onPressed: onSettingsPressed,
              background: Colors.white24,
              hoverBackground: Colors.white24,
              foreground: _sidebarTextSecondary,
              borderColor: Colors.transparent,
              semanticsLabel: 'Settings',
              tooltip: 'Settings',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _CurrentPlanBadgeButton(
              label: planLabel,
              isPremium: isPremium,
              onPressed: onPlanPressed,
            ),
            const SizedBox(width: 6),
            _PlanFeaturesPillButton(
              onPressed: () => _showPlansAndFeaturesDialog(context),
            ),
          ],
        ),
        if (expiryLine != null) ...<Widget>[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                TablerIcons.clock,
                size: 10,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  expiryLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    9,
                    _sidebarTextPrimary,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GreetingPlanLinkText extends StatefulWidget {
  const _GreetingPlanLinkText({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_GreetingPlanLinkText> createState() => _GreetingPlanLinkTextState();
}

class _GreetingPlanLinkTextState extends State<_GreetingPlanLinkText> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color color =
        _hovered ? Colors.white.withValues(alpha: 0.92) : _sidebarTextPrimary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          label: 'Open current plan status for ${widget.label}',
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _text(
              10,
              color,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ).copyWith(
              decoration:
                  _hovered ? TextDecoration.underline : TextDecoration.none,
              decorationColor: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentPlanBadgeButton extends StatefulWidget {
  const _CurrentPlanBadgeButton({
    required this.label,
    required this.isPremium,
    required this.onPressed,
  });

  final String label;
  final bool isPremium;
  final VoidCallback onPressed;

  @override
  State<_CurrentPlanBadgeButton> createState() =>
      _CurrentPlanBadgeButtonState();
}

class _CurrentPlanBadgeButtonState extends State<_CurrentPlanBadgeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color background = widget.isPremium
        ? const Color(0xFFF59E0B)
        : (_hovered ? const Color(0xFFF2F4F8) : Colors.white);
    final Color foreground =
        widget.isPremium ? Colors.white : const Color(0xFF0A3B48);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          label: 'Open current plan status',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 5),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(4),
              boxShadow: _hovered
                  ? <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.isPremium) ...<Widget>[
                  Icon(
                    TablerIcons.crown,
                    size: 7,
                    color: foreground,
                  ),
                  const SizedBox(width: 3),
                ],
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    7,
                    foreground,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    height: 1.1,
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

class _GreetingActionButton extends StatefulWidget {
  const _GreetingActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.background,
    required this.hoverBackground,
    required this.foreground,
    required this.borderColor,
    this.semanticsLabel,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color background;
  final Color hoverBackground;
  final Color foreground;
  final Color borderColor;
  final String? semanticsLabel;
  final String? tooltip;

  @override
  State<_GreetingActionButton> createState() => _GreetingActionButtonState();
}

class _GreetingActionButtonState extends State<_GreetingActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg = _hovered ? widget.hoverBackground : widget.background;
    final bool iconOnly = widget.label.isEmpty;
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          label: widget.semanticsLabel ?? widget.label,
          child: Container(
            constraints: iconOnly
                ? const BoxConstraints(minWidth: 26, minHeight: 22)
                : null,
            padding: iconOnly
                ? const EdgeInsets.symmetric(horizontal: 5, vertical: 3)
                : const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: widget.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  widget.icon,
                  size: iconOnly ? 14 : 10,
                  color: widget.foreground,
                ),
                if (widget.label.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 3),
                  Text(
                    widget.label,
                    style: _text(
                      9,
                      widget.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      return _AppTooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

// ───────────────────────────────────────────────────────────────────────
// Compact "Plan Features" pill — opens the shared Plans & Features modal
// (defined in vault_screen_settings.dart, accessible because both files
// are `part of` the same vault_screen library).
// ───────────────────────────────────────────────────────────────────────

class _PlanFeaturesPillButton extends StatefulWidget {
  const _PlanFeaturesPillButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_PlanFeaturesPillButton> createState() =>
      _PlanFeaturesPillButtonState();
}

class _PlanFeaturesPillButtonState extends State<_PlanFeaturesPillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg = _hovered
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.10);
    final Color border = Colors.white.withValues(alpha: 0.35);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          label: 'Plan Features',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  TablerIcons.list_details,
                  size: 9,
                  color: Colors.white,
                ),
                const SizedBox(width: 3),
                Text(
                  'Plan Features',
                  style: _text(
                    8,
                    Colors.white,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
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

// ───────────────────────────────────────────────────────────────────────
// Confirm-logout dialog.
// ───────────────────────────────────────────────────────────────────────

class _ConfirmLogoutDialog extends StatelessWidget {
  const _ConfirmLogoutDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Sign out of LumenPass?',
              style: _text(
                16,
                const Color(0xFF111827),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your local vault stays on this device. You can sign back in '
              'anytime to resume subscription sync.',
              style: _text(
                12,
                const Color(0xFF4B5563),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Cancel',
                    style: _text(
                      12,
                      const Color(0xFF374151),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Sign out',
                    style: _text(
                      12,
                      Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────
// Quick-login dialog. Sign-in itself is delegated to the website (so Google
// account chooser, password managers, 2FA challenges etc. all work in a
// real browser instead of an embedded webview). The dialog opens
// `${WEBSITE_URL}/login` in the user's default browser and closes itself
// once the launch is dispatched. Session pickup happens in a follow-up
// iteration via the desktop handoff flow that already exists server-side.
// ───────────────────────────────────────────────────────────────────────

class _QuickLoginDialog extends ConsumerStatefulWidget {
  const _QuickLoginDialog();

  @override
  ConsumerState<_QuickLoginDialog> createState() => _QuickLoginDialogState();
}

class _QuickLoginDialogState extends ConsumerState<_QuickLoginDialog> {
  // The dialog has three visual states:
  //   • idle      — initial copy + Login button
  //   • launching — transient: WebAuthService is opening the browser
  //   • waiting   — loopback HTTP server is up, browser is on the website,
  //                 we're awaiting the redirect-back. Cancel is supported.
  // On success the AccountController's state flips to logged-in and we
  // pop the dialog. On error we drop back to idle with the message shown.
  bool _launching = false;
  bool _waiting = false;
  String? _localError;
  WebAuthService? _webAuth;

  Future<void> _openWebsiteLogin() async {
    if (_launching || _waiting) return;
    setState(() {
      _launching = true;
      _waiting = false;
      _localError = null;
    });

    final svc = WebAuthService();
    _webAuth = svc;

    // Flip to waiting before awaiting — the launchUrl call inside
    // signInViaWeb returns quickly, but the await on the loopback callback
    // can take seconds. The user needs to see the spinner immediately.
    final future =
        ref.read(accountControllerProvider.notifier).signInViaWeb(webAuth: svc);
    if (mounted) {
      setState(() {
        _launching = false;
        _waiting = true;
      });
    }

    try {
      await future;
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      // `cancelled` is a deliberate user action — drop back to idle
      // silently rather than scaring them with a red error.
      setState(() {
        _launching = false;
        _waiting = false;
        _localError = e.code == 'cancelled' ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _waiting = false;
        _localError = 'Sign-in failed: $e';
      });
    } finally {
      _webAuth = null;
    }
  }

  Future<void> _cancelOrClose() async {
    if (_launching) return;
    final svc = _webAuth;
    if (svc != null && _waiting) {
      await svc.cancel();
      // Don't pop here — the awaiting future will throw AuthException
      // ('cancelled') and reset state via the catch block above.
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _cancelOrClose();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1A0F172A),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Sign in to LumenPass',
                                style: _text(
                                  16,
                                  const Color(0xFF111827),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _waiting
                                    ? 'Browser opened. Finish signing in '
                                        'there, then return to the app.'
                                    : 'Signing in opens the LumenPass '
                                        'website in your default browser. '
                                        'Finish signing in there, then '
                                        'return to the app.',
                                style: _text(
                                  11,
                                  const Color(0xFF6B7280),
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _launching ? null : _cancelOrClose,
                          icon: const Icon(TablerIcons.x,
                              size: 18, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                    if (_localError != null) ...<Widget>[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(
                              TablerIcons.alert_circle,
                              size: 14,
                              color: Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _localError!,
                                style: _text(
                                  11,
                                  const Color(0xFF991B1B),
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0xFFE2E7ED),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        if (_waiting) ...<Widget>[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF0A67FF)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Waiting for browser sign-in…',
                              style: _text(
                                11,
                                const Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        TextButton(
                          onPressed: _launching ? null : _cancelOrClose,
                          child: Text(
                            'Cancel',
                            style: _text(
                              12,
                              const Color(0xFF374151),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!_waiting) ...<Widget>[
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _launching ? null : _openWebsiteLogin,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0A67FF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _launching
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      const Icon(
                                        TablerIcons.external_link,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Login',
                                        style: _text(
                                          12,
                                          Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
// Hosts: macOS traffic-light top inset + greeting + Login/Logout pill +
// Premium/Free tag + Plan Features button + Expires line + the Settings
// gear (top-right).
// ───────────────────────────────────────────────────────────────────────

class _VaultGreetingHeader extends ConsumerStatefulWidget {
  const _VaultGreetingHeader({
    required this.onSettingsPressed,
  });

  final VoidCallback onSettingsPressed;

  @override
  ConsumerState<_VaultGreetingHeader> createState() =>
      _VaultGreetingHeaderState();
}

class _VaultGreetingHeaderState extends ConsumerState<_VaultGreetingHeader> {
  Future<void> _openQuickLoginDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Quick login',
      builder: (_) => const _QuickLoginDialog(),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Confirm logout',
      builder: (ctx) => const _ConfirmLogoutDialog(),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await ref.read(accountControllerProvider.notifier).signOut();
    } catch (_) {
      // signOut already handles transport failures by clearing local state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountControllerProvider);
    // Reserve room at the top so the macOS traffic-light buttons don't
    // collide with the greeting on the left. Windows has no traffic
    // lights and uses a custom title bar, so collapse the inset there.
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
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, topInset, 8, 6),
        child: _AccountGreetingSection(
          account: account,
          onLoginPressed: _openQuickLoginDialog,
          onLogoutPressed: _confirmLogout,
          onSettingsPressed: widget.onSettingsPressed,
        ),
      ),
    );
  }
}
