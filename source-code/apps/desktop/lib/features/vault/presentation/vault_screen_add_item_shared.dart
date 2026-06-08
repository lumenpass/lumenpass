part of 'vault_screen.dart';

String? _resolveEffectiveCategoryUuid({
  required List<({String uuid, String name, String notes, int count})>
      categories,
  required String? rootGroupUuid,
  required String? selectedGroupUuid,
  String? selectedCategoryUuid,
}) {
  final categoryUuids = categories.map((category) => category.uuid).toSet();
  if (selectedCategoryUuid != null &&
      (selectedCategoryUuid == rootGroupUuid ||
          categoryUuids.contains(selectedCategoryUuid))) {
    return selectedCategoryUuid;
  }
  if (selectedGroupUuid != null &&
      (selectedGroupUuid == rootGroupUuid ||
          categoryUuids.contains(selectedGroupUuid))) {
    return selectedGroupUuid;
  }
  if (categories.isNotEmpty) {
    return categories.first.uuid;
  }
  return rootGroupUuid;
}

void _showDiscardDialog(BuildContext context, VoidCallback onDiscard) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x22172033),
              blurRadius: 40,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Discard your changes?',
              textAlign: TextAlign.center,
              style: _text(17, const Color(0xFF1A1D23),
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              "You'll lose your changes to this item. Keep editing to go back and save.",
              textAlign: TextAlign.center,
              style: _text(13, const Color(0xFF6B7280),
                  fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () {
                Navigator.of(ctx).pop();
                onDiscard();
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFCC2929),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Discard Changes',
                  style: _text(14, Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2F6BFF), width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Keep Editing',
                  style: _text(14, const Color(0xFF2F6BFF),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CategoryDropdownField extends StatelessWidget {
  const _CategoryDropdownField({
    required this.categories,
    required this.rootGroupUuid,
    required this.selectedCategoryUuid,
    required this.onChanged,
  });

  final List<({String uuid, String name, String notes, int count})> categories;
  final String? rootGroupUuid;
  final String? selectedCategoryUuid;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    const itemTextColor = Color(0xFF111827);
    const labelColor = Color(0xFF344054);
    const fieldBackgroundColor = Color(0xFFF7F9FB);
    const fieldBorderColor = Color(0xFFD0D8E2);
    const hintColor = Color(0xFF98A2B3);
    const dropdownBackgroundColor = Colors.white;
    final options = <DropdownMenuItem<String>>[];
    if (rootGroupUuid != null) {
      options.add(
        DropdownMenuItem<String>(
          value: rootGroupUuid,
          child: Text(
            'Uncategorized',
            style: _text(
              12,
              itemTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    options.addAll(
      categories.map(
        (category) => DropdownMenuItem<String>(
          value: category.uuid,
          child: Text(
            category.name,
            style: _text(
              12,
              itemTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              TablerIcons.folder,
              size: 14,
              color: Color(0xFF5A78C5),
            ),
            const SizedBox(width: 6),
            Text(
              'category',
              style: _text(
                11,
                labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: fieldBackgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: fieldBorderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedCategoryUuid,
              isExpanded: true,
              style: _text(
                12,
                itemTextColor,
                fontWeight: FontWeight.w500,
              ),
              dropdownColor: dropdownBackgroundColor,
              icon: const Icon(
                TablerIcons.chevron_down,
                size: 14,
                color: Color(0xFF6B7280),
              ),
              hint: Text(
                'Select category',
                style: _text(
                  12,
                  hintColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              items: options,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({
    required this.tags,
    required this.existingTags,
    required this.controller,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  final List<String> tags;
  final List<String> existingTags;
  final TextEditingController controller;
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onRemoveTag;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final FocusNode _focusNode = FocusNode();
  final LayerLink _fieldLink = LayerLink();
  final OverlayPortalController _suggestionsController =
      OverlayPortalController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncSuggestions);
    _focusNode.addListener(_syncSuggestions);
  }

  @override
  void didUpdateWidget(covariant _TagEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncSuggestions();
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSuggestions);
    _focusNode.removeListener(_syncSuggestions);
    _focusNode.dispose();
    super.dispose();
  }

  String get _activeQuery {
    final segments = widget.controller.text.split(',');
    return segments.isEmpty ? '' : segments.last.trim();
  }

  List<String> get _suggestedTags {
    final selectedTags = widget.tags
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final query = _activeQuery.toLowerCase();

    return widget.existingTags
        .where((tag) {
          final normalized = tag.trim();
          if (normalized.isEmpty) {
            return false;
          }
          if (selectedTags.contains(normalized.toLowerCase())) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return normalized.toLowerCase().contains(query);
        })
        .take(8)
        .toList(growable: false);
  }

  void _syncSuggestions() {
    final shouldShow = _focusNode.hasFocus && _suggestedTags.isNotEmpty;
    if (shouldShow) {
      _suggestionsController.show();
    } else {
      _suggestionsController.hide();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _commitTagInput({String? selectedSuggestion}) {
    final rawValue = widget.controller.text;
    if (selectedSuggestion == null) {
      final parts = rawValue
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty);
      for (final part in parts) {
        widget.onAddTag(part);
      }
    } else {
      final parts = rawValue.split(',');
      for (final part in parts.take(parts.length > 1 ? parts.length - 1 : 0)) {
        final normalized = part.trim();
        if (normalized.isNotEmpty) {
          widget.onAddTag(normalized);
        }
      }
      widget.onAddTag(selectedSuggestion);
    }

    widget.controller.clear();
    _focusNode.requestFocus();
    _syncSuggestions();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestedTags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.tags.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags
                .map(
                  (tag) => _TagChip(
                    label: tag,
                    onRemove: () => widget.onRemoveTag(tag),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
        ],
        TextFieldTapRegion(
          child: OverlayPortal(
            controller: _suggestionsController,
            overlayChildBuilder: (context) {
              if (!_focusNode.hasFocus || suggestions.isEmpty) {
                return const SizedBox.shrink();
              }

              return TextFieldTapRegion(
                child: CompositedTransformFollower(
                  link: _fieldLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 8),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: Colors.transparent,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFDDE3EC)),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x14172033),
                                blurRadius: 24,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                _activeQuery.isEmpty
                                    ? 'Reuse an existing tag'
                                    : 'Matching tags',
                                style: _text(
                                  11,
                                  const Color(0xFF667085),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: suggestions
                                    .map(
                                      (tag) => _TagSuggestionChip(
                                        label: tag,
                                        onTap: () => _commitTagInput(
                                          selectedSuggestion: tag,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: CompositedTransformTarget(
              link: _fieldLink,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? const Color(0xFF8BA9D8)
                        : const Color(0xFFD0D8E2),
                    width: _focusNode.hasFocus ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      TablerIcons.tag,
                      size: 14,
                      color: Color(0xFF6D63D6),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        focusNode: _focusNode,
                        controller: widget.controller,
                        onTap: _syncSuggestions,
                        onChanged: (_) => _syncSuggestions(),
                        onTapOutside: (_) => _focusNode.unfocus(),
                        onSubmitted: (_) => _commitTagInput(),
                        style: _text(
                          12,
                          const Color(0xFF111827),
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add a tag and press Enter',
                          hintStyle: _text(
                            12,
                            const Color(0xFF98A2B3),
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _commitTagInput(),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Add',
                          style: _text(
                            11,
                            const Color(0xFF3B6FD3),
                            fontWeight: FontWeight.w600,
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
      ],
    );
  }
}

class _TagSuggestionChip extends StatefulWidget {
  const _TagSuggestionChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_TagSuggestionChip> createState() => _TagSuggestionChipState();
}

class _TagSuggestionChipState extends State<_TagSuggestionChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFDDE8FF) : const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '#${widget.label}',
            style: _text(
              11,
              const Color(0xFF2E4D8B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: _text(
              11,
              const Color(0xFF2E4D8B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: const Icon(
              TablerIcons.x,
              size: 12,
              color: Color(0xFF5E6676),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewItemTypeRow extends StatefulWidget {
  const _NewItemTypeRow({
    required this.option,
    required this.onTap,
    required this.selected,
  });

  final _NewItemType option;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_NewItemTypeRow> createState() => _NewItemTypeRowState();
}

class _NewItemTypeRowState extends State<_NewItemTypeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          height: widget.option.id == 'migrate' ? 44 : 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0xFFF1F6FF)
                : (_hovered ? const Color(0xFFF8FAFF) : Colors.white),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected
                  ? const Color(0xFFCFE0FF)
                  : const Color(0xFFD8DEE9),
            ),
          ),
          child: Row(
            children: <Widget>[
              if (widget.option.imagePath != null) ...<Widget>[
                Image.asset(
                  widget.option.imagePath!,
                  width: 18,
                  height: 18,
                  errorBuilder: (_, __, ___) => Icon(
                    widget.option.icon ?? TablerIcons.file_description,
                    size: 16,
                    color: widget.option.iconColor,
                  ),
                ),
                const SizedBox(width: 10),
              ] else if (widget.option.icon != null) ...<Widget>[
                Icon(
                  widget.option.icon,
                  size: 16,
                  color: widget.option.iconColor,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  widget.option.label,
                  style: _text(
                    11,
                    widget.option.id == 'migrate'
                        ? const Color(0xFF3B404A)
                        : const Color(0xFF2E3138),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(
                TablerIcons.chevron_right,
                size: 16,
                color: Color(0xFF6A7282),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModalIconAction extends StatefulWidget {
  const _ModalIconAction({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ModalIconAction> createState() => _ModalIconActionState();
}

class _ModalIconActionState extends State<_ModalIconAction> {
  bool _hovered = false;
  final FocusNode _focusNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        focusNode: _focusNode,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFF1F4F8) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 18,
            color: const Color(0xFF5E6676),
          ),
        ),
      ),
    );
  }
}

class _LoginFormField extends StatefulWidget {
  const _LoginFormField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.hintText,
    this.maxLines = 1,
    this.minLines,
    this.obscureText = false,
    this.trailing,
    this.focusNode,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final String hintText;
  final int maxLines;
  final int? minLines;
  final bool obscureText;
  final Widget? trailing;
  final FocusNode? focusNode;

  @override
  State<_LoginFormField> createState() => _LoginFormFieldState();
}

class _LoginFormFieldState extends State<_LoginFormField> {
  bool _plainPasswordVisible = false;
  late final FocusNode _effectiveFocusNode;

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    if (widget.maxLines > 1) {
      _effectiveFocusNode.onKeyEvent = _handleMultilineTab;
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _effectiveFocusNode.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleMultilineTab(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      final shifted = HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.shiftLeft) ||
          HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.shiftRight);
      if (shifted) {
        node.previousFocus();
      } else {
        node.nextFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final canTogglePassword = widget.obscureText && widget.maxLines == 1;
    final fieldObscured = canTogglePassword && !_plainPasswordVisible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              widget.icon,
              size: 14,
              color: widget.iconColor,
            ),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: _text(
                11,
                const Color(0xFF344054),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          constraints: widget.maxLines > 1
              ? const BoxConstraints(minHeight: 104)
              : const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD0D8E2)),
          ),
          child: Row(
            crossAxisAlignment: widget.maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  focusNode: _effectiveFocusNode,
                  controller: widget.controller,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  obscureText: fieldObscured,
                  obscuringCharacter: '•',
                  style: _text(
                    12,
                    const Color(0xFF111827),
                    height: widget.minLines != null ? 1.4 : null,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: _text(
                      12,
                      const Color(0xFF98A2B3),
                      fontWeight: FontWeight.w500,
                      height: widget.minLines != null ? 1.4 : null,
                    ),
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (canTogglePassword) ...<Widget>[
                const SizedBox(width: 4),
                Tooltip(
                  message:
                      _plainPasswordVisible ? 'Hide password' : 'Show password',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(
                        () => _plainPasswordVisible = !_plainPasswordVisible,
                      ),
                      canRequestFocus: false,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _plainPasswordVisible
                              ? TablerIcons.eye_off
                              : TablerIcons.eye,
                          size: 18,
                          color: const Color(0xFF5E6676),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.trailing != null) ...<Widget>[
                const SizedBox(width: 10),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PasswordGeneratorIconButton extends StatefulWidget {
  const _PasswordGeneratorIconButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_PasswordGeneratorIconButton> createState() =>
      _PasswordGeneratorIconButtonState();
}

class _PasswordGeneratorIconButtonState
    extends State<_PasswordGeneratorIconButton> {
  bool _hovered = false;
  final FocusNode _focusNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Generate password',
      child: Semantics(
        button: true,
        label: 'Generate password',
        hint: 'Opens the password generator dialog',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              focusNode: _focusNode,
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      _hovered ? const Color(0xFFEAF1FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _hovered
                        ? const Color(0xFFB8CDF0)
                        : const Color(0xFFD8DEE8),
                  ),
                ),
                child: const Icon(
                  TablerIcons.wand,
                  size: 18,
                  color: Color(0xFF315EBA),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordGenerateSuggestion extends StatefulWidget {
  const _PasswordGenerateSuggestion({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  State<_PasswordGenerateSuggestion> createState() =>
      _PasswordGenerateSuggestionState();
}

class _PasswordGenerateSuggestionState
    extends State<_PasswordGenerateSuggestion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final background =
        _hovered ? const Color(0xFFE0ECFF) : const Color(0xFFEAF1FF);

    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFCADBFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  TablerIcons.lock_password,
                  size: 12,
                  color: Color(0xFF315EBA),
                ),
                const SizedBox(width: 6),
                Text(
                  'Suggest strong password',
                  style: _text(
                    11,
                    const Color(0xFF315EBA),
                    fontWeight: FontWeight.w600,
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

class _WebsiteRemoveButton extends StatefulWidget {
  const _WebsiteRemoveButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  State<_WebsiteRemoveButton> createState() => _WebsiteRemoveButtonState();
}

class _WebsiteRemoveButtonState extends State<_WebsiteRemoveButton> {
  bool _hovered = false;
  final FocusNode _focusNode = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        focusNode: _focusNode,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFFEE2E2) : const Color(0xFFFFF1F1),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFF4B8B8)),
          ),
          alignment: Alignment.center,
          child: const Icon(
            TablerIcons.minus,
            size: 12,
            color: Color(0xFFD94A4A),
          ),
        ),
      ),
    );
  }
}

class _AddMoreOptionsCard extends StatelessWidget {
  const _AddMoreOptionsCard({
    required this.options,
    required this.onSelected,
  });

  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8DEE9)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var index = 0; index < options.length; index++) ...<Widget>[
            InkWell(
              onTap: () => onSelected(options[index]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  options[index],
                  style: _text(
                    12,
                    const Color(0xFF2E3138),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (index != options.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE6EBF2),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CreditCardFieldDraft {
  _CreditCardFieldDraft({
    required String label,
    required this.valueHint,
    this.removable = false,
    this.isSecret = false,
    this.showsAdjustments = false,
    this.showsCalendarPicker = false,
    this.isLabelEditable = false,
    this.keyboardType,
    this.trailingIcon,
  })  : labelController = TextEditingController(text: label),
        valueController = TextEditingController();

  final TextEditingController labelController;
  final TextEditingController valueController;
  final String valueHint;
  final bool removable;
  final bool isSecret;
  final bool showsAdjustments;
  final bool showsCalendarPicker;
  final bool isLabelEditable;
  final TextInputType? keyboardType;
  final IconData? trailingIcon;

  void dispose() {
    labelController.dispose();
    valueController.dispose();
  }
}

class _CreditCardSectionCard extends StatelessWidget {
  const _CreditCardSectionCard({
    this.title,
    this.showHeaderAction = true,
    required this.fields,
    required this.onAddField,
    required this.onRemoveField,
  });

  final String? title;
  final bool showHeaderAction;
  final List<_CreditCardFieldDraft> fields;
  final VoidCallback onAddField;
  final ValueChanged<_CreditCardFieldDraft>? onRemoveField;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      ),
      child: Column(
        children: <Widget>[
          if (title != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F6F8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title!,
                      style: _text(
                        13,
                        const Color(0xFF2E3138),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (showHeaderAction) const _SectionMinusBadge(),
                ],
              ),
            ),
          for (var index = 0; index < fields.length; index++) ...<Widget>[
            _CreditCardFieldRow(
              field: fields[index],
              onRemove: onRemoveField == null
                  ? null
                  : () => onRemoveField!(fields[index]),
            ),
            if (index != fields.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFE8ECF3),
              ),
          ],
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFFE8ECF3),
          ),
          InkWell(
            onTap: onAddField,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: <Widget>[
                  Text(
                    '+ add another field',
                    style: _text(
                      12,
                      const Color(0xFF0B63E5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    TablerIcons.chevron_down,
                    size: 14,
                    color: Color(0xFF6A7282),
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

class _CreditCardFieldRow extends StatelessWidget {
  const _CreditCardFieldRow({
    required this.field,
    this.onRemove,
  });

  final _CreditCardFieldDraft field;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    if (field.showsCalendarPicker) {
      return _CalendarCreditCardFieldRow(
        field: field,
        onRemove: onRemove,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(
              TablerIcons.menu_2,
              size: 18,
              color: Color(0xFF3A3A3A),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                field.isLabelEditable
                    ? TextField(
                        controller: field.labelController,
                        maxLines: 1,
                        style: _text(
                          12,
                          const Color(0xFF5E56E8),
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'field name',
                          hintStyle: _text(
                            12,
                            const Color(0xFF98A2B3),
                            fontWeight: FontWeight.w500,
                          ),
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                      )
                    : Text(
                        field.labelController.text,
                        style: _text(
                          12,
                          const Color(0xFF5E56E8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                const SizedBox(height: 4),
                TextField(
                  controller: field.valueController,
                  maxLines: 1,
                  obscureText: field.isSecret,
                  obscuringCharacter: '•',
                  keyboardType: field.keyboardType ??
                      (field.showsAdjustments
                          ? TextInputType.number
                          : TextInputType.text),
                  inputFormatters: field.showsAdjustments
                      ? const <TextInputFormatter>[
                          _MonthYearTextInputFormatter(),
                        ]
                      : null,
                  style: _text(
                    16,
                    const Color(0xFF6B7280),
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: field.valueHint,
                    hintStyle: _text(
                      16,
                      const Color(0xFF8A8F98),
                      fontWeight: FontWeight.w400,
                    ),
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (field.showsAdjustments)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Icon(
                TablerIcons.adjustments_horizontal,
                size: 18,
                color: Color(0xFF4B4B4B),
              ),
            )
          else if (field.trailingIcon != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Icon(
                field.trailingIcon,
                size: 18,
                color: const Color(0xFF8A8F98),
              ),
            )
          else if (field.removable && onRemove != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _SectionMinusBadge(onTap: onRemove),
            ),
        ],
      ),
    );
  }
}

class _CalendarCreditCardFieldRow extends StatefulWidget {
  const _CalendarCreditCardFieldRow({
    required this.field,
    this.onRemove,
  });

  final _CreditCardFieldDraft field;
  final VoidCallback? onRemove;

  @override
  State<_CalendarCreditCardFieldRow> createState() =>
      _CalendarCreditCardFieldRowState();
}

class _CalendarCreditCardFieldRowState
    extends State<_CalendarCreditCardFieldRow> {
  final GlobalKey _calendarButtonKey = GlobalKey();
  OverlayEntry? _calendarOverlayEntry;

  DateTime get _selectedDate {
    final parsed = _parseMonthDayYear(widget.field.valueController.text);
    if (parsed != null) {
      return parsed;
    }
    final now = DateTime.now();
    return DateTime(now.year - 18, now.month, now.day);
  }

  bool get _showCalendar => _calendarOverlayEntry != null;

  @override
  void dispose() {
    _removeCalendarOverlay();
    super.dispose();
  }

  void _toggleCalendar() {
    if (_showCalendar) {
      _removeCalendarOverlay();
      return;
    }
    _showCalendarOverlay();
  }

  void _selectDate(DateTime date) {
    setState(() {
      widget.field.valueController.text = _formatMonthDayYear(date);
    });
    _removeCalendarOverlay();
  }

  void _showCalendarOverlay() {
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final buttonContext = _calendarButtonKey.currentContext;
    final buttonBox = buttonContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || buttonBox == null) {
      return;
    }

    final buttonTopLeft = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    const popupWidth = 288.0;
    const popupHeight = 276.0;
    final left = buttonTopLeft.dx + buttonBox.size.width - popupWidth;
    final top = buttonTopLeft.dy + buttonBox.size.height + 10;

    _calendarOverlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeCalendarOverlay,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: popupWidth,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE1E7F0)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x14172033),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: popupHeight - 18,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                                primary: const Color(0xFF2F6BFF),
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: const Color(0xFF2E3138),
                              ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: CalendarDatePicker(
                          initialDate: _selectedDate,
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                          onDateChanged: _selectDate,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_calendarOverlayEntry!);
    setState(() {});
  }

  void _removeCalendarOverlay() {
    _calendarOverlayEntry?.remove();
    _calendarOverlayEntry = null;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(
              TablerIcons.menu_2,
              size: 18,
              color: Color(0xFF3A3A3A),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: InkWell(
              onTap: _toggleCalendar,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.field.labelController.text,
                      style: _text(
                        12,
                        const Color(0xFF5E56E8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.field.valueController.text.isEmpty
                          ? widget.field.valueHint
                          : widget.field.valueController.text,
                      style: _text(
                        16,
                        widget.field.valueController.text.isEmpty
                            ? const Color(0xFF8A8F98)
                            : const Color(0xFF6B7280),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            key: _calendarButtonKey,
            onTap: _toggleCalendar,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _showCalendar
                    ? const Color(0xFFEAF1FF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.field.trailingIcon ?? Icons.calendar_today_outlined,
                size: 18,
                color: const Color(0xFF8A8F98),
              ),
            ),
          ),
          if (widget.field.removable && widget.onRemove != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: _SectionMinusBadge(onTap: widget.onRemove),
            ),
        ],
      ),
    );
  }
}

DateTime? _parseMonthDayYear(String rawValue) {
  final parts = rawValue.trim().split('/');
  if (parts.length != 3) {
    return null;
  }
  final month = int.tryParse(parts[0].trim());
  final day = int.tryParse(parts[1].trim());
  final year = int.tryParse(parts[2].trim());
  if (month == null || day == null || year == null) {
    return null;
  }
  if (month < 1 || month > 12) {
    return null;
  }

  final candidate = DateTime(year, month, day);
  if (candidate.year != year ||
      candidate.month != month ||
      candidate.day != day) {
    return null;
  }
  return candidate;
}

String _formatMonthDayYear(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return '$month/$day/$year';
}

class _MonthYearTextInputFormatter extends TextInputFormatter {
  const _MonthYearTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmedDigits = digits.length > 6 ? digits.substring(0, 6) : digits;
    final formatted = _formatMonthYear(trimmedDigits);

    final digitsBeforeCursor = newValue.selection.baseOffset <= 0
        ? 0
        : newValue.text
            .substring(0,
                math.min(newValue.selection.baseOffset, newValue.text.length))
            .replaceAll(RegExp(r'[^0-9]'), '')
            .length;
    final clampedDigitsBeforeCursor =
        digitsBeforeCursor.clamp(0, trimmedDigits.length);
    final selectionOffset =
        _selectionOffsetForDigits(clampedDigitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: TextRange.empty,
    );
  }

  String _formatMonthYear(String digits) {
    if (digits.isEmpty) {
      return '';
    }
    if (digits.length <= 2) {
      return digits;
    }
    return '${digits.substring(0, 2)} / ${digits.substring(2)}';
  }

  int _selectionOffsetForDigits(int digitsCount) {
    if (digitsCount <= 2) {
      return digitsCount;
    }
    return digitsCount + 3;
  }
}

class _SectionMinusBadge extends StatelessWidget {
  const _SectionMinusBadge({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      canRequestFocus: false,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color:
              onTap == null ? const Color(0xFFFFF5F3) : const Color(0xFFFFF1F1),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFF7A59)),
        ),
        alignment: Alignment.center,
        child: const Icon(
          TablerIcons.minus,
          size: 12,
          color: Color(0xFFFF5A36),
        ),
      ),
    );
  }
}

class _CustomAttributeList extends StatelessWidget {
  const _CustomAttributeList({
    required this.attributes,
    required this.onRemove,
    required this.onReorder,
  });

  final List<_LoginCustomAttribute> attributes;
  final ValueChanged<int> onRemove;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      primary: false,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        return Material(
          color: Colors.transparent,
          child: child,
        );
      },
      itemCount: attributes.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        return Padding(
          key: ObjectKey(attributes[index]),
          padding: EdgeInsets.only(
            bottom: index == attributes.length - 1 ? 0 : 10,
          ),
          child: _CustomAttributeCard(
            attribute: attributes[index],
            dragIndex: index,
            onRemove: () => onRemove(index),
          ),
        );
      },
    );
  }
}

class _CustomAttributeCard extends StatefulWidget {
  const _CustomAttributeCard({
    required this.attribute,
    required this.dragIndex,
    required this.onRemove,
  });

  final _LoginCustomAttribute attribute;
  final int dragIndex;
  final VoidCallback onRemove;

  @override
  State<_CustomAttributeCard> createState() => _CustomAttributeCardState();
}

class _CustomAttributeCardState extends State<_CustomAttributeCard> {
  bool _isSecretVisible = false;

  bool get _isSecretField {
    final label = widget.attribute.labelController.text.trim().toLowerCase();
    return widget.attribute.isSecret || AppKdbxFieldKeys.isProtectedKey(label);
  }

  @override
  void initState() {
    super.initState();
    widget.attribute.labelController.addListener(_handleLabelChanged);
  }

  @override
  void dispose() {
    widget.attribute.labelController.removeListener(_handleLabelChanged);
    super.dispose();
  }

  void _handleLabelChanged() {
    if (!mounted) {
      return;
    }
    if (!_isSecretField && _isSecretVisible) {
      setState(() {
        _isSecretVisible = false;
      });
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isSecretField = _isSecretField;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ReorderableDragStartListener(
              index: widget.dragIndex,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Tooltip(
                  message: 'Drag to reorder',
                  child: const Icon(
                    TablerIcons.menu_2,
                    size: 24,
                    color: Color(0xFF2E3138),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: widget.attribute.labelController,
                  maxLines: 1,
                  style: _text(
                    12,
                    const Color(0xFF2E3138),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: widget.attribute.valueController,
                  maxLines: 1,
                  obscureText: isSecretField && !_isSecretVisible,
                  autocorrect: !isSecretField,
                  enableSuggestions: !isSecretField,
                  style: _text(
                    10,
                    const Color(0xFF6B7280),
                    fontWeight: FontWeight.w400,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter value',
                    hintStyle: _text(
                      10,
                      const Color(0xFF98A2B3),
                      fontWeight: FontWeight.w400,
                    ),
                    filled: false,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (isSecretField) ...<Widget>[
                  InkWell(
                    onTap: () => setState(() {
                      _isSecretVisible = !_isSecretVisible;
                    }),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        _isSecretVisible
                            ? TablerIcons.eye_off
                            : TablerIcons.eye,
                        size: 16,
                        color: const Color(0xFF98A2B3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _WebsiteRemoveButton(onTap: widget.onRemove),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _appendAttachmentFields(
  List<EntryField> fields,
  List<_LoginAttachment> attachments,
) {
  for (var i = 0; i < attachments.length; i++) {
    final attachment = attachments[i];
    fields.add(EntryField(
      key: '${AppKdbxFieldKeys.attachmentNamePrefix}$i',
      value: attachment.name,
    ));
    fields.add(EntryField(
      key: '${AppKdbxFieldKeys.attachmentSizePrefix}$i',
      value: attachment.size.toString(),
    ));
    fields.add(EntryField(
      key: '${AppKdbxFieldKeys.attachmentImagePrefix}$i',
      value: attachment.isImage ? '1' : '0',
    ));
  }
}

List<EntryAttachment> _newEntryAttachmentsFrom(
  List<_LoginAttachment> attachments,
) {
  return attachments
      .where((attachment) => attachment.path != null)
      .map(
        (attachment) => EntryAttachment(
          fileName: attachment.name,
          filePath: attachment.path!,
        ),
      )
      .toList(growable: false);
}

Future<List<EntryAttachment>> _resolveEditAttachments(
  KdbxRepository repository,
  String entryUuid,
  List<_LoginAttachment> attachments,
) async {
  if (attachments.isEmpty) {
    return const <EntryAttachment>[];
  }

  final existingByName = <String, EntryBinaryAttachment>{
    for (final attachment in await repository.getEntryAttachments(entryUuid))
      attachment.name: attachment,
  };

  return attachments.map((attachment) {
    final path = attachment.path;
    if (path != null) {
      return EntryAttachment(fileName: attachment.name, filePath: path);
    }
    final bytes = attachment.bytes ?? existingByName[attachment.name]?.bytes;
    if (bytes == null) {
      throw StateError('Missing attachment bytes for ${attachment.name}');
    }
    return EntryAttachment(fileName: attachment.name, bytes: bytes);
  }).toList(growable: false);
}

List<_LoginAttachment> _mergeBinaryAttachments(
  List<_LoginAttachment> currentAttachments,
  List<EntryBinaryAttachment> binaryAttachments,
) {
  final currentByName = LinkedHashMap<String, _LoginAttachment>.fromEntries(
    currentAttachments.map(
      (attachment) => MapEntry<String, _LoginAttachment>(
        attachment.name,
        attachment,
      ),
    ),
  );
  final merged = <_LoginAttachment>[];

  for (final binaryAttachment in binaryAttachments) {
    final current = currentByName.remove(binaryAttachment.name);
    if (current?.path != null) {
      merged.add(current!);
      continue;
    }
    merged.add(
      _LoginAttachment(
        name: binaryAttachment.name,
        size: binaryAttachment.size,
        path: null,
        isImage: binaryAttachment.isImage,
        bytes: binaryAttachment.bytes,
      ),
    );
  }

  merged.addAll(currentByName.values);
  return merged;
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({
    required this.attachments,
    required this.onAddPressed,
    required this.onRemove,
  });

  final List<_LoginAttachment> attachments;
  final Future<void> Function() onAddPressed;
  final ValueChanged<_LoginAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              TablerIcons.paperclip,
              size: 14,
              color: Color(0xFF5A78C5),
            ),
            const SizedBox(width: 6),
            Text(
              'attachments',
              style: _text(
                11,
                const Color(0xFF344054),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onAddPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDDE3EC)),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    TablerIcons.upload,
                    size: 18,
                    color: Color(0xFF3B6FD3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Add files or images',
                        style: _text(
                          12,
                          const Color(0xFF2E3138),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Upload attachments for this item',
                        style: _text(
                          10,
                          const Color(0xFF7B8798),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  TablerIcons.plus,
                  size: 16,
                  color: Color(0xFF3B6FD3),
                ),
              ],
            ),
          ),
        ),
        if (attachments.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          for (var index = 0; index < attachments.length; index++) ...<Widget>[
            _LoginAttachmentTile(
              attachment: attachments[index],
              onRemove: () => onRemove(attachments[index]),
            ),
            if (index != attachments.length - 1) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _LoginAttachmentTile extends StatelessWidget {
  const _LoginAttachmentTile({
    required this.attachment,
    required this.onRemove,
  });

  final _LoginAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F2)),
      ),
      child: Row(
        children: <Widget>[
          _LoginAttachmentThumb(attachment: attachment),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    11,
                    const Color(0xFF2B3444),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAttachmentSize(attachment.size),
                  style: _text(
                    10,
                    const Color(0xFF7B8CA6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _WebsiteRemoveButton(onTap: onRemove),
        ],
      ),
    );
  }
}

class _LoginAttachmentThumb extends StatelessWidget {
  const _LoginAttachmentThumb({
    required this.attachment,
  });

  final _LoginAttachment attachment;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (attachment.isImage && attachment.bytes != null) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          attachment.bytes!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _fallbackAttachmentThumb(attachment),
        ),
      );
    } else if (attachment.isImage && attachment.path != null) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(attachment.path!),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _fallbackAttachmentThumb(attachment),
        ),
      );
    } else {
      child = _fallbackAttachmentThumb(attachment);
    }

    return SizedBox(width: 40, height: 40, child: child);
  }

  Widget _fallbackAttachmentThumb(_LoginAttachment attachment) {
    return Container(
      decoration: BoxDecoration(
        color: attachment.isImage
            ? const Color(0xFFDCE5FA)
            : const Color(0xFFEEF2F8),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(
        attachment.isImage ? TablerIcons.photo : TablerIcons.file_description,
        size: 18,
        color: const Color(0xFF6B7A92),
      ),
    );
  }
}

class _LoginFooterButton extends StatefulWidget {
  const _LoginFooterButton({
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
  State<_LoginFooterButton> createState() => _LoginFooterButtonState();
}

class _LoginFooterButtonState extends State<_LoginFooterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;

    return MouseRegion(
      onEnter: (_) {
        if (isEnabled) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && isEnabled ? 1.02 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isEnabled
                  ? widget.backgroundColor
                  : widget.backgroundColor.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              border: widget.borderColor != null
                  ? Border.all(color: widget.borderColor!)
                  : null,
              boxShadow:
                  widget.backgroundColor == _kPrimaryButtonColor && isEnabled
                      ? <BoxShadow>[
                          BoxShadow(
                            color: _hovered
                                ? _kPrimaryButtonColor.withValues(alpha: 0.24)
                                : _kPrimaryButtonColor.withValues(alpha: 0.14),
                            blurRadius: _hovered ? 12 : 6,
                            offset: Offset(0, _hovered ? 4 : 2),
                          ),
                        ]
                      : null,
            ),
            child: Text(
              widget.label,
              style: _text(
                12,
                isEnabled
                    ? widget.textColor
                    : widget.textColor.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
