import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const Color kPrimaryButtonColor = Color(0xFF0A3B48);

// ── Text helper ───────────────────────────────────────────────────────────────

TextStyle itemText(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: fontWeight,
    height: height,
  );
}

// ── Models ────────────────────────────────────────────────────────────────────

class LoginCustomAttribute {
  LoginCustomAttribute({
    required String label,
    required String value,
    this.isSecret = false,
  })
      : labelController = TextEditingController(text: label),
        valueController = TextEditingController(text: value);

  final TextEditingController labelController;
  final TextEditingController valueController;
  final bool isSecret;

  bool get shouldProtect =>
      isSecret ||
      AppKdbxFieldKeys.isProtectedKey(labelController.text.trim());

  void dispose() {
    labelController.dispose();
    valueController.dispose();
  }
}

class LoginAttachment {
  const LoginAttachment({
    required this.name,
    required this.size,
    required this.path,
    required this.isImage,
  });

  final String name;
  final int size;
  final String? path;
  final bool isImage;
}

class CreditCardFieldDraft {
  CreditCardFieldDraft({
    required String label,
    required this.valueHint,
    this.removable = false,
    this.isSecret = false,
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
  final bool showsCalendarPicker;
  final bool isLabelEditable;
  final TextInputType? keyboardType;
  final IconData? trailingIcon;

  void dispose() {
    labelController.dispose();
    valueController.dispose();
  }
}

// ── Discard dialog ─────────────────────────────────────────────────────────────

void showDiscardDialog(BuildContext context, VoidCallback onDiscard) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Discard your changes?',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1D23),
        ),
      ),
      content: const Text(
        "You'll lose your changes to this item. Keep editing to go back and save.",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Color(0xFF6B7280),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onDiscard();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCC2929),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Discard Changes'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2F6BFF),
                side: const BorderSide(color: Color(0xFF2F6BFF), width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Keep Editing'),
            ),
          ],
        ),
      ],
    ),
  );
}

// ── Category dropdown ──────────────────────────────────────────────────────────

class CategoryDropdownField extends StatelessWidget {
  const CategoryDropdownField({
    super.key,
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

    final options = <DropdownMenuItem<String>>[];
    if (rootGroupUuid != null) {
      options.add(DropdownMenuItem<String>(
        value: rootGroupUuid,
        child: Text('Uncategorized',
            style: itemText(12, itemTextColor, fontWeight: FontWeight.w500)),
      ));
    }
    options.addAll(categories.map((c) => DropdownMenuItem<String>(
          value: c.uuid,
          child: Text(c.name,
              style: itemText(12, itemTextColor, fontWeight: FontWeight.w500)),
        )));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(TablerIcons.folder,
                size: 14, color: Color(0xFF5A78C5)),
            const SizedBox(width: 6),
            Text('category',
                style:
                    itemText(11, labelColor, fontWeight: FontWeight.w600)),
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
              style: itemText(12, itemTextColor, fontWeight: FontWeight.w500),
              dropdownColor: Colors.white,
              icon: const Icon(TablerIcons.chevron_down,
                  size: 14, color: Color(0xFF6B7280)),
              hint: Text('Select category',
                  style:
                      itemText(12, hintColor, fontWeight: FontWeight.w500)),
              items: options,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tag editor ────────────────────────────────────────────────────────────────

class TagEditor extends StatefulWidget {
  const TagEditor({
    super.key,
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
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  final FocusNode _focusNode = FocusNode();
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_syncSuggestions);
    widget.controller.addListener(_syncSuggestions);
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
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();
    final query = _activeQuery.toLowerCase();
    return widget.existingTags
        .where((tag) {
          final normalized = tag.trim();
          if (normalized.isEmpty) return false;
          if (selectedTags.contains(normalized.toLowerCase())) return false;
          if (query.isEmpty) return true;
          return normalized.toLowerCase().contains(query);
        })
        .take(8)
        .toList(growable: false);
  }

  void _syncSuggestions() {
    final shouldShow = _focusNode.hasFocus && _suggestedTags.isNotEmpty;
    if (_showSuggestions != shouldShow) {
      setState(() => _showSuggestions = shouldShow);
    }
  }

  void _commitTagInput({String? selectedSuggestion}) {
    final rawValue = widget.controller.text;
    if (selectedSuggestion == null) {
      final parts = rawValue
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty);
      for (final part in parts) {
        widget.onAddTag(part);
      }
    } else {
      final parts = rawValue.split(',');
      for (final part
          in parts.take(parts.length > 1 ? parts.length - 1 : 0)) {
        final normalized = part.trim();
        if (normalized.isNotEmpty) widget.onAddTag(normalized);
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
      children: [
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags
                .map((tag) => TagChip(
                    label: tag, onRemove: () => widget.onRemoveTag(tag)))
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD0D8E2)),
          ),
          child: Row(
            children: [
              const Icon(TablerIcons.tag,
                  size: 14, color: Color(0xFF6D63D6)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  focusNode: _focusNode,
                  controller: widget.controller,
                  onChanged: (_) => _syncSuggestions(),
                  onSubmitted: (_) => _commitTagInput(),
                  style: itemText(12, const Color(0xFF111827),
                      fontWeight: FontWeight.w500),
                  decoration: const InputDecoration(
                    hintText: 'Add a tag and press Enter',
                    hintStyle: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF98A2B3),
                        fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _commitTagInput(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Add',
                      style: itemText(11, const Color(0xFF3B6FD3),
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
        if (_showSuggestions && suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDDE3EC)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x14172033),
                    blurRadius: 24,
                    offset: Offset(0, 10))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _activeQuery.isEmpty ? 'Reuse an existing tag' : 'Matching tags',
                  style: itemText(11, const Color(0xFF667085),
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: suggestions
                      .map((tag) => InkWell(
                            onTap: () =>
                                _commitTagInput(selectedSuggestion: tag),
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF1FF),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text('#$tag',
                                  style: itemText(
                                      11, const Color(0xFF2E4D8B),
                                      fontWeight: FontWeight.w600)),
                            ),
                          ))
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.onRemove});

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
        children: [
          Text(label,
              style: itemText(11, const Color(0xFF2E4D8B),
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: const Icon(TablerIcons.x,
                size: 12, color: Color(0xFF5E6676)),
          ),
        ],
      ),
    );
  }
}

// ── Form field ────────────────────────────────────────────────────────────────

class LoginFormField extends StatelessWidget {
  const LoginFormField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.hintText,
    this.maxLines = 1,
    this.minLines,
    this.obscureText = false,
    this.trailing,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Text(label,
                style: itemText(11, const Color(0xFF344054),
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          constraints: maxLines > 1
              ? const BoxConstraints(minHeight: 104)
              : const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD0D8E2)),
          ),
          child: Row(
            crossAxisAlignment: maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: minLines,
                  maxLines: maxLines,
                  obscureText: obscureText && maxLines == 1,
                  obscuringCharacter: '•',
                  style: itemText(12, const Color(0xFF111827)),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: itemText(12, const Color(0xFF98A2B3),
                        fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Website remove button ─────────────────────────────────────────────────────

class WebsiteRemoveButton extends StatelessWidget {
  const WebsiteRemoveButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F1),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFF4B8B8)),
        ),
        alignment: Alignment.center,
        child: const Icon(TablerIcons.minus,
            size: 12, color: Color(0xFFD94A4A)),
      ),
    );
  }
}

// ── Section minus badge ───────────────────────────────────────────────────────

class SectionMinusBadge extends StatelessWidget {
  const SectionMinusBadge({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: onTap == null
              ? const Color(0xFFFFF5F3)
              : const Color(0xFFFFF1F1),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFF7A59)),
        ),
        alignment: Alignment.center,
        child: const Icon(TablerIcons.minus,
            size: 12, color: Color(0xFFFF5A36)),
      ),
    );
  }
}

// ── Add more options card ─────────────────────────────────────────────────────

class AddMoreOptionsCard extends StatelessWidget {
  const AddMoreOptionsCard({
    super.key,
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
        boxShadow: const [
          BoxShadow(
              color: Color(0x14172033),
              blurRadius: 16,
              offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < options.length; index++) ...[
            InkWell(
              onTap: () => onSelected(options[index]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Text(options[index],
                    style: itemText(13, const Color(0xFF2E3138),
                        fontWeight: FontWeight.w500)),
              ),
            ),
            if (index != options.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Divider(
                    height: 1, thickness: 1, color: Color(0xFFE6EBF2)),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Custom attribute card ─────────────────────────────────────────────────────

class CustomAttributeCard extends StatefulWidget {
  const CustomAttributeCard({
    super.key,
    required this.attribute,
    required this.onRemove,
  });

  final LoginCustomAttribute attribute;
  final VoidCallback onRemove;

  @override
  State<CustomAttributeCard> createState() => _CustomAttributeCardState();
}

class _CustomAttributeCardState extends State<CustomAttributeCard> {
  bool _isSecretVisible = false;

  bool get _isSecretField {
    final label =
        widget.attribute.labelController.text.trim().toLowerCase();
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
    if (!mounted) return;
    if (!_isSecretField && _isSecretVisible) {
      setState(() => _isSecretVisible = false);
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
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Icon(TablerIcons.menu_2,
                size: 24, color: Color(0xFF2E3138)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: widget.attribute.labelController,
                  maxLines: 1,
                  style: itemText(13, const Color(0xFF2E3138),
                      fontWeight: FontWeight.w500),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: widget.attribute.valueController,
                  maxLines: 1,
                  obscureText: isSecretField && !_isSecretVisible,
                  style: itemText(11, const Color(0xFF6B7280),
                      fontWeight: FontWeight.w400),
                  decoration: const InputDecoration(
                    hintText: 'Enter value',
                    hintStyle: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF98A2B3),
                        fontWeight: FontWeight.w400),
                    border: InputBorder.none,
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
              children: [
                if (isSecretField) ...[
                  InkWell(
                    onTap: () =>
                        setState(() => _isSecretVisible = !_isSecretVisible),
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
                WebsiteRemoveButton(onTap: widget.onRemove),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Credit Card Section Card ──────────────────────────────────────────────────

class CreditCardSectionCard extends StatelessWidget {
  const CreditCardSectionCard({
    super.key,
    this.title,
    this.showHeaderAction = true,
    required this.fields,
    required this.onAddField,
    required this.onRemoveField,
  });

  final String? title;
  final bool showHeaderAction;
  final List<CreditCardFieldDraft> fields;
  final VoidCallback onAddField;
  final ValueChanged<CreditCardFieldDraft>? onRemoveField;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      ),
      child: Column(
        children: [
          if (title != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF5F6F8),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!,
                        style: itemText(13, const Color(0xFF2E3138),
                            fontWeight: FontWeight.w700)),
                  ),
                  if (showHeaderAction) const SectionMinusBadge(),
                ],
              ),
            ),
          for (var index = 0; index < fields.length; index++) ...[
            _CreditCardFieldRow(
              field: fields[index],
              onRemove: onRemoveField == null
                  ? null
                  : () => onRemoveField!(fields[index]),
            ),
            if (index != fields.length - 1)
              const Divider(
                  height: 1, thickness: 1, color: Color(0xFFE8ECF3)),
          ],
          const Divider(height: 1, thickness: 1, color: Color(0xFFE8ECF3)),
          InkWell(
            onTap: onAddField,
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text('+ add another field',
                      style: itemText(12, const Color(0xFF0B63E5),
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Icon(TablerIcons.chevron_down,
                      size: 14, color: Color(0xFF6A7282)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditCardFieldRow extends StatefulWidget {
  const _CreditCardFieldRow({required this.field, this.onRemove});

  final CreditCardFieldDraft field;
  final VoidCallback? onRemove;

  @override
  State<_CreditCardFieldRow> createState() => _CreditCardFieldRowState();
}

class _CreditCardFieldRowState extends State<_CreditCardFieldRow> {
  Future<void> _pickDate() async {
    final current = _parseDate(widget.field.valueController.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
    );
    if (picked != null) {
      setState(() {
        widget.field.valueController.text = _formatDate(picked);
      });
    }
  }

  DateTime? _parseDate(String raw) {
    final parts = raw.trim().split('/');
    if (parts.length != 3) return null;
    final month = int.tryParse(parts[0].trim());
    final day = int.tryParse(parts[1].trim());
    final year = int.tryParse(parts[2].trim());
    if (month == null || day == null || year == null) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(TablerIcons.menu_2,
                size: 18, color: Color(0xFF3A3A3A)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field.isLabelEditable
                    ? TextField(
                        controller: field.labelController,
                        maxLines: 1,
                        style: itemText(12, const Color(0xFF5E56E8),
                            fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          hintText: 'field name',
                          hintStyle: TextStyle(
                              fontSize: 12, color: Color(0xFF98A2B3)),
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                      )
                    : Text(
                        field.labelController.text,
                        style: itemText(12, const Color(0xFF5E56E8),
                            fontWeight: FontWeight.w500),
                      ),
                const SizedBox(height: 4),
                field.showsCalendarPicker
                    ? InkWell(
                        onTap: _pickDate,
                        child: Text(
                          field.valueController.text.isEmpty
                              ? field.valueHint
                              : field.valueController.text,
                          style: itemText(
                              16,
                              field.valueController.text.isEmpty
                                  ? const Color(0xFF8A8F98)
                                  : const Color(0xFF6B7280),
                              fontWeight: FontWeight.w400),
                        ),
                      )
                    : TextField(
                        controller: field.valueController,
                        maxLines: 1,
                        obscureText: field.isSecret,
                        obscuringCharacter: '•',
                        keyboardType: field.keyboardType,
                        inputFormatters: field.isLabelEditable
                            ? null
                            : field.labelController.text.toLowerCase().contains('expir') ||
                                    field.labelController.text.toLowerCase().contains('valid')
                                ? [_MonthYearTextInputFormatter()]
                                : null,
                        style: itemText(16, const Color(0xFF6B7280),
                            fontWeight: FontWeight.w400),
                        decoration: InputDecoration(
                          hintText: field.valueHint,
                          hintStyle: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF8A8F98),
                              fontWeight: FontWeight.w400),
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (field.showsCalendarPicker)
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.calendar_today_outlined,
                    size: 18, color: Color(0xFF8A8F98)),
              ),
            )
          else if (field.removable && widget.onRemove != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SectionMinusBadge(onTap: widget.onRemove),
            ),
        ],
      ),
    );
  }
}

// ── Month/year formatter ──────────────────────────────────────────────────────

class _MonthYearTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final trimmed =
        digits.length > 6 ? digits.substring(0, 6) : digits;
    final formatted = _formatMonthYear(trimmed);
    final digitsBeforeCursor = newValue.selection.baseOffset <= 0
        ? 0
        : newValue.text
            .substring(
                0,
                math.min(
                    newValue.selection.baseOffset, newValue.text.length))
            .replaceAll(RegExp(r'[^0-9]'), '')
            .length;
    final clampedDigits =
        digitsBeforeCursor.clamp(0, trimmed.length);
    final selectionOffset = _selectionOffsetForDigits(clampedDigits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: TextRange.empty,
    );
  }

  String _formatMonthYear(String digits) {
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return digits;
    return '${digits.substring(0, 2)} / ${digits.substring(2)}';
  }

  int _selectionOffsetForDigits(int digitsCount) {
    if (digitsCount <= 2) return digitsCount;
    return digitsCount + 3;
  }
}

// ── Footer button ─────────────────────────────────────────────────────────────

class LoginFooterButton extends StatelessWidget {
  const LoginFooterButton({
    super.key,
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
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isEnabled
              ? backgroundColor
              : backgroundColor.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: borderColor != null
              ? Border.all(color: borderColor!)
              : null,
        ),
        child: Text(
          label,
          style: itemText(12,
              isEnabled ? textColor : textColor.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Modal header ──────────────────────────────────────────────────────────────

class ModalIconAction extends StatelessWidget {
  const ModalIconAction({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: const Color(0xFF5E6676)),
      ),
    );
  }
}

// ── Attachment section ────────────────────────────────────────────────────────

class AttachmentSection extends StatelessWidget {
  const AttachmentSection({
    super.key,
    required this.attachments,
    required this.onAddPressed,
    required this.onRemove,
  });

  final List<LoginAttachment> attachments;
  final Future<void> Function() onAddPressed;
  final ValueChanged<LoginAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(TablerIcons.paperclip,
                size: 14, color: Color(0xFF5A78C5)),
            const SizedBox(width: 6),
            Text('attachments',
                style: itemText(11, const Color(0xFF344054),
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onAddPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDDE3EC)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(TablerIcons.upload,
                      size: 18, color: Color(0xFF3B6FD3)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add files or images',
                          style: itemText(12, const Color(0xFF2E3138),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Upload attachments for this item',
                          style: itemText(10, const Color(0xFF7B8798),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const Icon(TablerIcons.plus,
                    size: 16, color: Color(0xFF3B6FD3)),
              ],
            ),
          ),
        ),
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < attachments.length; i++) ...[
            _AttachmentTile(
              attachment: attachments[i],
              onRemove: () => onRemove(attachments[i]),
            ),
            if (i != attachments.length - 1) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile(
      {required this.attachment, required this.onRemove});

  final LoginAttachment attachment;
  final VoidCallback onRemove;

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    }
    if (bytes >= 1024) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    }
    return '$bytes B';
  }

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
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: attachment.isImage
                  ? const Color(0xFFDCE5FA)
                  : const Color(0xFFEEF2F8),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              attachment.isImage
                  ? TablerIcons.photo
                  : TablerIcons.file_description,
              size: 18,
              color: const Color(0xFF6B7A92),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: itemText(11, const Color(0xFF2B3444),
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(_formatSize(attachment.size),
                    style: itemText(10, const Color(0xFF7B8CA6),
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          WebsiteRemoveButton(onTap: onRemove),
        ],
      ),
    );
  }
}
