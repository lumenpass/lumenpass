import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../application/vault_entries_providers.dart';
import '../../../core/repository/database_save_sync.dart';
import '../../../core/repository/providers.dart';
import '../../unlock/application/database_registry.dart';
import 'vault_create_item_models.dart';
import 'vault_create_item_shared.dart';

enum _CreditCardSectionKind { primary, contact, additional }

const List<String> _ccAddMoreOptions = <String>[
  'custom field',
  'Sensitive Text',
  'note',
];

class AddCreditCardItemModal extends ConsumerStatefulWidget {
  const AddCreditCardItemModal({
    super.key,
    required this.onClose,
    required this.onShowToast,
    required this.onItemSaved,
    this.onReturnToPicker,
    this.editingEntry,
  });

  final VoidCallback onClose;
  final ValueChanged<String> onShowToast;
  final ValueChanged<String> onItemSaved;
  final VoidCallback? onReturnToPicker;

  /// When set, the modal opens in edit mode.
  final KdbxEntry? editingEntry;

  @override
  ConsumerState<AddCreditCardItemModal> createState() =>
      _AddCreditCardItemModalState();
}

class _AddCreditCardItemModalState
    extends ConsumerState<AddCreditCardItemModal> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagController;
  late final List<CreditCardFieldDraft> _primaryFields;
  late final List<CreditCardFieldDraft> _contactFields;
  late final List<CreditCardFieldDraft> _additionalFields;
  final List<LoginCustomAttribute> _customAttributes = <LoginCustomAttribute>[];
  final List<String> _tags = <String>[];
  String? _selectedCategoryUuid;
  bool _showAddMoreOptions = false;
  bool _isDirty = false;
  bool _isSaving = false;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.editingEntry;
    _primaryFields = <CreditCardFieldDraft>[
      CreditCardFieldDraft(label: 'cardholder name', valueHint: 'text'),
      CreditCardFieldDraft(label: 'type', valueHint: 'type'),
      CreditCardFieldDraft(label: 'number', valueHint: 'text'),
      CreditCardFieldDraft(
        label: 'verification number',
        valueHint: 'number',
        isSecret: true,
      ),
      CreditCardFieldDraft(label: 'expiry date', valueHint: 'MM / YYYY'),
      CreditCardFieldDraft(label: 'valid from', valueHint: 'MM / YYYY'),
    ];
    _contactFields = <CreditCardFieldDraft>[
      CreditCardFieldDraft(
        label: 'issuing bank',
        valueHint: 'text',
        removable: true,
      ),
      CreditCardFieldDraft(
        label: 'phone (local)',
        valueHint: 'text',
        removable: true,
      ),
      CreditCardFieldDraft(
        label: 'phone (toll free)',
        valueHint: 'text',
        removable: true,
      ),
      CreditCardFieldDraft(
        label: 'phone (intl)',
        valueHint: 'text',
        removable: true,
      ),
      CreditCardFieldDraft(
        label: 'website',
        valueHint: 'text',
        removable: true,
      ),
    ];
    _additionalFields = <CreditCardFieldDraft>[
      CreditCardFieldDraft(
        label: 'PIN',
        valueHint: 'password',
        isSecret: true,
        removable: true,
      ),
      CreditCardFieldDraft(
        label: 'credit limit',
        valueHint: 'text',
        removable: true,
      ),
      CreditCardFieldDraft(
        label: 'cash withdrawal limit',
        valueHint: 'text',
        removable: true,
      ),
      CreditCardFieldDraft(
        label: 'interest rate',
        valueHint: 'text',
        removable: true,
      ),
      CreditCardFieldDraft(
        label: 'issue number',
        valueHint: 'text',
        removable: true,
      ),
    ];

    if (edit != null) {
      _titleController = TextEditingController(text: edit.title);
      _notesController = TextEditingController(text: edit.notes ?? '');
      _tagController = TextEditingController();
      _tags.addAll(edit.tags);
      // Pre-fill known section fields from the entry.
      final allSectionFields = <CreditCardFieldDraft>[
        ..._primaryFields,
        ..._contactFields,
        ..._additionalFields,
      ];
      for (final draft in allSectionFields) {
        final label = draft.labelController.text.trim().toLowerCase();
        // Try to find a matching field in the kdbx entry by key.
        for (final field in edit.fields) {
          final key = field.key.toLowerCase();
          if (key == label ||
              (label == 'number' && key == 'card number') ||
              (label == 'verification number' &&
                  (key == 'cvc' || key == 'cvv')) ||
              (label == 'expiry date' && key == 'expiry date') ||
              (label == 'valid from' && key == 'valid from') ||
              (label == 'issuing bank' && key == 'issuing bank') ||
              (label == 'cardholder name' && key == 'username')) {
            draft.valueController.text = field.value;
            break;
          }
        }
      }
      // Any unrecognized fields go to custom attributes.
      const knownKeys = <String>{
        'title',
        'username',
        'url',
        'cardholder name',
        'card number',
        'cvc',
        'cvv',
        'expiry date',
        'valid from',
        'issuing bank',
        'type',
        'pin',
        'credit limit',
        'cash withdrawal limit',
        'interest rate',
        'issue number',
        'phone (local)',
        'phone (toll free)',
        'phone (intl)',
        'website',
        'phone',
        'email',
      };
      for (final field in edit.fields) {
        final k = field.key.toLowerCase();
        if (k == AppKdbxFieldKeys.title.toLowerCase()) continue;
        if (k == AppKdbxFieldKeys.userName.toLowerCase()) continue;
        if (k == AppKdbxFieldKeys.url.toLowerCase()) continue;
        if (AppKdbxFieldKeys.isAttachmentMetaKey(field.key)) continue;
        if (knownKeys.contains(k)) continue;
        _customAttributes.add(
          LoginCustomAttribute(
            label: field.key,
            value: field.value,
            isSecret: field.isProtected,
          ),
        );
      }
    } else {
      _titleController = TextEditingController(text: 'Credit Card');
      _notesController = TextEditingController();
      _tagController = TextEditingController();
    }

    _titleController.addListener(_markDirty);
    _notesController.addListener(_markDirty);
    for (final f in _primaryFields) {
      f.valueController.addListener(_markDirty);
    }
    for (final f in _contactFields) {
      f.valueController.addListener(_markDirty);
    }
    for (final f in _additionalFields) {
      f.valueController.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    for (final f in _primaryFields) {
      f.dispose();
    }
    for (final f in _contactFields) {
      f.dispose();
    }
    for (final f in _additionalFields) {
      f.dispose();
    }
    for (final a in _customAttributes) {
      a.dispose();
    }
    super.dispose();
  }

  List<CreditCardFieldDraft> _fieldsForSection(_CreditCardSectionKind section) {
    switch (section) {
      case _CreditCardSectionKind.primary:
        return _primaryFields;
      case _CreditCardSectionKind.contact:
        return _contactFields;
      case _CreditCardSectionKind.additional:
        return _additionalFields;
    }
  }

  void _addField(_CreditCardSectionKind section) {
    final f = CreditCardFieldDraft(
      label: '',
      valueHint: 'text',
      removable: true,
      isLabelEditable: true,
    );
    f.valueController.addListener(_markDirty);
    setState(() {
      _isDirty = true;
      _fieldsForSection(section).add(f);
    });
  }

  void _removeField(
    _CreditCardSectionKind section,
    CreditCardFieldDraft field,
  ) {
    setState(() {
      _isDirty = true;
      _fieldsForSection(section).remove(field);
    });
    field.dispose();
  }

  void _addCustomAttribute(String option) {
    setState(() {
      _isDirty = true;
      _customAttributes.add(
        LoginCustomAttribute(
          label: option.toLowerCase(),
          value: '',
          isSecret: AppKdbxFieldKeys.isProtectedKey(option),
        ),
      );
      _showAddMoreOptions = false;
    });
  }

  void _removeCustomAttribute(int index) {
    final attr = _customAttributes[index];
    setState(() {
      _isDirty = true;
      _customAttributes.removeAt(index);
    });
    attr.dispose();
  }

  void _addTag(String rawTag) {
    final normalized = rawTag.trim();
    if (normalized.isEmpty) return;
    if (_tags.any((t) => t.toLowerCase() == normalized.toLowerCase())) return;
    setState(() {
      _isDirty = true;
      _tags.add(normalized);
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _isDirty = true;
      _tags.remove(tag);
    });
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _confirmClose() {
    if (!_isDirty) {
      widget.onClose();
      return;
    }
    showDiscardDialog(context, widget.onClose);
  }

  bool _hasMeaningfulContent(String title) {
    final allFields = <CreditCardFieldDraft>[
      ..._primaryFields,
      ..._contactFields,
      ..._additionalFields,
    ];
    final hasSectionValue = allFields.any(
      (field) =>
          field.labelController.text.trim().isNotEmpty &&
          field.valueController.text.trim().isNotEmpty,
    );
    return title != 'Credit Card' ||
        _notesController.text.trim().isNotEmpty ||
        hasSectionValue ||
        _tags.isNotEmpty;
  }

  Future<void> _saveEdit() async {
    final edit = widget.editingEntry!;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      widget.onShowToast('Title is required');
      return;
    }

    final fields = <EntryField>[
      EntryField(key: AppKdbxFieldKeys.title, value: title, isStandard: true),
    ];

    final cardholderField = _primaryFields.firstWhere(
      (f) => f.labelController.text.trim().toLowerCase() == 'cardholder name',
      orElse: () => _primaryFields.first,
    );
    final cardholder = cardholderField.valueController.text.trim();
    if (cardholder.isNotEmpty) {
      fields.add(
        EntryField(
          key: AppKdbxFieldKeys.userName,
          value: cardholder,
          isStandard: true,
        ),
      );
    }

    final websiteField = _contactFields
        .cast<CreditCardFieldDraft?>()
        .firstWhere(
          (f) => f?.labelController.text.trim().toLowerCase() == 'website',
          orElse: () => null,
        );
    final website = websiteField?.valueController.text.trim() ?? '';
    if (website.isNotEmpty) {
      fields.add(
        EntryField(key: AppKdbxFieldKeys.url, value: website, isStandard: true),
      );
    }

    for (final field in <CreditCardFieldDraft>[
      ..._primaryFields,
      ..._contactFields,
      ..._additionalFields,
    ]) {
      final key = field.labelController.text.trim();
      final value = field.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      final normalizedKey = key.toLowerCase();
      if (normalizedKey == 'cardholder name' || normalizedKey == 'website') {
        continue;
      }
      String effectiveKey = key;
      switch (normalizedKey) {
        case 'number':
          effectiveKey = 'Card Number';
          break;
        case 'verification number':
          effectiveKey = 'CVC';
          break;
        case 'expiry date':
          effectiveKey = 'Expiry Date';
          break;
        case 'valid from':
          effectiveKey = 'Valid From';
          break;
        case 'issuing bank':
          effectiveKey = 'Issuing Bank';
          break;
      }
      fields.add(
        EntryField(
          key: effectiveKey,
          value: value,
          isProtected: field.isSecret,
        ),
      );
    }

    for (final attr in _customAttributes) {
      final key = attr.labelController.text.trim();
      final value = attr.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(
        EntryField(key: key, value: value, isProtected: attr.shouldProtect),
      );
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      await repository.updateEntry(
        entryUuid: edit.uuid,
        fields: fields,
        notes: _notesController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
      );
      final registry = ref.read(databaseRegistryProvider);
      final database = await saveAndSyncDatabase(repository, registry);
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultVisibleEntriesProvider);
      ref.invalidate(vaultAllTagsProvider);
      ref.invalidate(vaultSidebarCategoriesProvider);
      widget.onItemSaved(edit.uuid);
      widget.onShowToast('Credit card saved');
      if (!mounted) return;
      widget.onClose();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      widget.onShowToast('Unable to save: $error');
    }
  }

  Future<void> _save({
    required List<({String uuid, String name, String notes, int count})>
    categories,
    required String? rootGroupUuid,
    required String? selectedGroupUuid,
  }) async {
    if (_isEditing) {
      await _saveEdit();
      return;
    }
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      widget.onShowToast('Title is required');
      return;
    }
    if (!_hasMeaningfulContent(title)) {
      widget.onShowToast('Add at least one value before saving');
      return;
    }
    final targetGroupUuid = resolveEffectiveCategoryUuid(
      categories: categories,
      rootGroupUuid: rootGroupUuid,
      selectedGroupUuid: selectedGroupUuid,
      selectedCategoryUuid: _selectedCategoryUuid,
    );
    if (targetGroupUuid == null || targetGroupUuid.isEmpty) {
      widget.onShowToast('Select a category before saving');
      return;
    }

    final fields = <EntryField>[
      EntryField(key: AppKdbxFieldKeys.title, value: title, isStandard: true),
    ];

    final cardholderField = _primaryFields.firstWhere(
      (f) => f.labelController.text.trim().toLowerCase() == 'cardholder name',
      orElse: () => _primaryFields.first,
    );
    final cardholder = cardholderField.valueController.text.trim();
    if (cardholder.isNotEmpty) {
      fields.add(
        EntryField(
          key: AppKdbxFieldKeys.userName,
          value: cardholder,
          isStandard: true,
        ),
      );
    }

    final websiteField = _contactFields
        .cast<CreditCardFieldDraft?>()
        .firstWhere(
          (f) => f?.labelController.text.trim().toLowerCase() == 'website',
          orElse: () => null,
        );
    final website = websiteField?.valueController.text.trim() ?? '';
    if (website.isNotEmpty) {
      fields.add(
        EntryField(key: AppKdbxFieldKeys.url, value: website, isStandard: true),
      );
    }

    for (final field in <CreditCardFieldDraft>[
      ..._primaryFields,
      ..._contactFields,
      ..._additionalFields,
    ]) {
      final key = field.labelController.text.trim();
      final value = field.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      final normalizedKey = key.toLowerCase();
      if (normalizedKey == 'cardholder name' || normalizedKey == 'website') {
        continue;
      }
      String effectiveKey = key;
      switch (normalizedKey) {
        case 'number':
          effectiveKey = 'Card Number';
          break;
        case 'verification number':
          effectiveKey = 'CVC';
          break;
        case 'expiry date':
          effectiveKey = 'Expiry Date';
          break;
        case 'valid from':
          effectiveKey = 'Valid From';
          break;
        case 'issuing bank':
          effectiveKey = 'Issuing Bank';
          break;
      }
      fields.add(
        EntryField(
          key: effectiveKey,
          value: value,
          isProtected: field.isSecret,
        ),
      );
    }

    for (final attr in _customAttributes) {
      final key = attr.labelController.text.trim();
      final value = attr.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(
        EntryField(key: key, value: value, isProtected: attr.shouldProtect),
      );
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final createdEntry = await repository.createEntry(
        groupUuid: targetGroupUuid,
        fields: fields,
        notes: _notesController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
      );
      final registry = ref.read(databaseRegistryProvider);
      final database = await saveAndSyncDatabase(repository, registry);
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultVisibleEntriesProvider);
      ref.invalidate(vaultAllTagsProvider);
      ref.invalidate(vaultSidebarCategoriesProvider);
      widget.onItemSaved(createdEntry.uuid);
      widget.onShowToast('Credit card saved');
      if (!mounted) return;
      widget.onClose();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      widget.onShowToast('Unable to save item: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vaultSidebarCategoriesProvider);
    final existingTags = ref.watch(vaultAllTagsProvider);
    final rootGroupUuid = ref.watch(
      kdbxRepositoryProvider.select((r) => r.rootGroupUuid),
    );
    final selectedGroupUuid = ref.watch(vaultSelectedGroupProvider);
    final effectiveCategoryUuid = resolveEffectiveCategoryUuid(
      categories: categories,
      rootGroupUuid: rootGroupUuid,
      selectedGroupUuid: selectedGroupUuid,
      selectedCategoryUuid: _selectedCategoryUuid,
    );

    final modalTheme = Theme.of(context).copyWith(
      inputDecorationTheme: const InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF2F6BFF),
        selectionColor: Color(0x1F2F6BFF),
        selectionHandleColor: Color(0xFF2F6BFF),
      ),
    );

    return Theme(
      data: modalTheme,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFE7EBF0),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD0D8E2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1C172033),
              blurRadius: 44,
              offset: Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ModalIconAction(
                  icon: TablerIcons.arrow_left,
                  onTap: widget.onReturnToPicker ?? widget.onClose,
                ),
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit Item' : 'New Item',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E3138),
                    ),
                  ),
                ),
                ModalIconAction(icon: TablerIcons.x, onTap: _confirmClose),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF91C8F9), Color(0xFF4FA9F3)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 9,
                        child: Container(
                          height: 8,
                          color: const Color(0xFF31455E),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 22,
                        child: Container(
                          height: 5,
                          color: const Color(0xFFBEEBFF),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 12,
                        child: Container(
                          width: 16,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E88E5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 7,
                        child: Container(
                          width: 10,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E88E5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: widget.onReturnToPicker,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      TablerIcons.chevron_down,
                      size: 14,
                      color: Color(0xFF667085),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE8ECF3)),
                    ),
                    alignment: Alignment.centerLeft,
                    child: TextField(
                      controller: _titleController,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFF2E3138),
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    CreditCardSectionCard(
                      fields: _primaryFields,
                      onAddField: () =>
                          _addField(_CreditCardSectionKind.primary),
                      onRemoveField: null,
                    ),
                    const SizedBox(height: 14),
                    CreditCardSectionCard(
                      title: 'Contact Information',
                      fields: _contactFields,
                      onAddField: () =>
                          _addField(_CreditCardSectionKind.contact),
                      onRemoveField: (field) =>
                          _removeField(_CreditCardSectionKind.contact, field),
                    ),
                    const SizedBox(height: 14),
                    CreditCardSectionCard(
                      title: 'Additional Details',
                      fields: _additionalFields,
                      onAddField: () =>
                          _addField(_CreditCardSectionKind.additional),
                      onRemoveField: (field) => _removeField(
                        _CreditCardSectionKind.additional,
                        field,
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () => setState(
                        () => _showAddMoreOptions = !_showAddMoreOptions,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '+ add more',
                              style: itemText(
                                12,
                                const Color(0xFF0B63E5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              _showAddMoreOptions
                                  ? TablerIcons.chevron_up
                                  : TablerIcons.chevron_down,
                              size: 14,
                              color: const Color(0xFF6A7282),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showAddMoreOptions) ...[
                      const SizedBox(height: 8),
                      AddMoreOptionsCard(
                        options: _ccAddMoreOptions,
                        onSelected: _addCustomAttribute,
                      ),
                    ],
                    if (_customAttributes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (var i = 0; i < _customAttributes.length; i++) ...[
                        CustomAttributeCard(
                          attribute: _customAttributes[i],
                          onRemove: () => _removeCustomAttribute(i),
                        ),
                        if (i != _customAttributes.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                    const SizedBox(height: 14),
                    LoginFormField(
                      label: 'notes',
                      controller: _notesController,
                      maxLines: 4,
                      minLines: 4,
                      icon: TablerIcons.notes,
                      iconColor: const Color(0xFF6D63D6),
                      hintText: 'Add any notes about this item here.',
                    ),
                    const SizedBox(height: 14),
                    CategoryDropdownField(
                      categories: categories,
                      rootGroupUuid: rootGroupUuid,
                      selectedCategoryUuid: effectiveCategoryUuid,
                      onChanged: (value) =>
                          setState(() => _selectedCategoryUuid = value),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'tags',
                        style: itemText(
                          12,
                          const Color(0xFF6D63D6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TagEditor(
                      tags: _tags,
                      existingTags: existingTags,
                      controller: _tagController,
                      onAddTag: _addTag,
                      onRemoveTag: _removeTag,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: const Color(0xFFCCD4DF)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                LoginFooterButton(
                  label: 'Cancel',
                  backgroundColor: const Color(0xFFEBEEF3),
                  textColor: const Color(0xFF3E4B60),
                  borderColor: const Color(0xFFC0C9D4),
                  onTap: _isSaving ? null : _confirmClose,
                ),
                const SizedBox(width: 10),
                LoginFooterButton(
                  label: _isSaving ? 'Saving...' : 'Save',
                  backgroundColor: kPrimaryButtonColor,
                  textColor: Colors.white,
                  onTap: _isSaving
                      ? null
                      : () => _save(
                          categories: categories,
                          rootGroupUuid: rootGroupUuid,
                          selectedGroupUuid: selectedGroupUuid,
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
