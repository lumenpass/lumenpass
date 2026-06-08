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

const List<String> _identityAddMoreOptions = <String>[
  'address',
  'city',
  'state',
  'zip',
  'country',
  'phone',
  'email',
  'Sensitive Text',
  'custom field',
];

class AddIdentityItemModal extends ConsumerStatefulWidget {
  const AddIdentityItemModal({
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
  ConsumerState<AddIdentityItemModal> createState() =>
      _AddIdentityItemModalState();
}

class _AddIdentityItemModalState extends ConsumerState<AddIdentityItemModal> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagController;
  late final List<CreditCardFieldDraft> _identityFields;
  late final List<CreditCardFieldDraft> _addressFields;
  late final List<CreditCardFieldDraft> _internetFields;
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
    _identityFields = <CreditCardFieldDraft>[
      CreditCardFieldDraft(label: 'first name', valueHint: 'text'),
      CreditCardFieldDraft(label: 'initial', valueHint: 'text'),
      CreditCardFieldDraft(label: 'last name', valueHint: 'text'),
      CreditCardFieldDraft(label: 'gender', valueHint: 'text'),
      CreditCardFieldDraft(
        label: 'birth date',
        valueHint: 'mm/dd/yyyy',
        keyboardType: TextInputType.datetime,
        trailingIcon: Icons.calendar_today_outlined,
        showsCalendarPicker: true,
      ),
      CreditCardFieldDraft(label: 'occupation', valueHint: 'text'),
      CreditCardFieldDraft(label: 'company', valueHint: 'text'),
      CreditCardFieldDraft(label: 'department', valueHint: 'text'),
      CreditCardFieldDraft(label: 'job title', valueHint: 'text'),
    ];
    _addressFields = <CreditCardFieldDraft>[
      CreditCardFieldDraft(label: 'address', valueHint: 'text'),
      CreditCardFieldDraft(label: 'city', valueHint: 'text'),
      CreditCardFieldDraft(label: 'state', valueHint: 'text'),
      CreditCardFieldDraft(label: 'zip', valueHint: 'text'),
      CreditCardFieldDraft(label: 'country', valueHint: 'text'),
      CreditCardFieldDraft(label: 'default phone', valueHint: 'text'),
      CreditCardFieldDraft(label: 'home', valueHint: 'text'),
      CreditCardFieldDraft(label: 'cell', valueHint: 'text'),
      CreditCardFieldDraft(label: 'business', valueHint: 'text'),
    ];
    _internetFields = <CreditCardFieldDraft>[
      CreditCardFieldDraft(label: 'username', valueHint: 'text'),
      CreditCardFieldDraft(label: 'reminder question', valueHint: 'text'),
      CreditCardFieldDraft(label: 'reminder answer', valueHint: 'text'),
      CreditCardFieldDraft(label: 'email', valueHint: 'text'),
      CreditCardFieldDraft(label: 'website', valueHint: 'text'),
      CreditCardFieldDraft(label: 'ICQ', valueHint: 'text'),
      CreditCardFieldDraft(label: 'skype', valueHint: 'text'),
      CreditCardFieldDraft(label: 'AOL/IM', valueHint: 'text'),
      CreditCardFieldDraft(label: 'Yahoo', valueHint: 'text'),
      CreditCardFieldDraft(label: 'MSN', valueHint: 'text'),
      CreditCardFieldDraft(label: 'firm signature', valueHint: 'text'),
    ];

    if (edit != null) {
      _titleController = TextEditingController(text: edit.title);
      _notesController = TextEditingController(text: edit.notes ?? '');
      _tagController = TextEditingController();
      _tags.addAll(edit.tags);
      for (final draft in <CreditCardFieldDraft>[
        ..._identityFields,
        ..._addressFields,
        ..._internetFields,
      ]) {
        final value = editIdentityFieldValueFromKdbx(
          edit,
          draft.labelController.text,
        );
        if (value.isNotEmpty) draft.valueController.text = value;
      }
      // Unrecognized fields → custom attributes.
      final knownKeys = <String>{
        AppKdbxFieldKeys.title.toLowerCase(),
        AppKdbxFieldKeys.userName.toLowerCase(),
        'full name',
        for (final d in <CreditCardFieldDraft>[
          ..._identityFields,
          ..._addressFields,
          ..._internetFields,
        ])
          for (final key in identityStorageKeysForLabel(d.labelController.text))
            key.toLowerCase(),
      };
      for (final field in edit.fields) {
        final k = field.key.toLowerCase();
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
      _titleController = TextEditingController(text: 'Identity');
      _notesController = TextEditingController();
      _tagController = TextEditingController();
    }

    _titleController.addListener(_markDirty);
    _notesController.addListener(_markDirty);
    for (final f in <CreditCardFieldDraft>[
      ..._identityFields,
      ..._addressFields,
      ..._internetFields,
    ]) {
      f.valueController.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    for (final f in <CreditCardFieldDraft>[
      ..._identityFields,
      ..._addressFields,
      ..._internetFields,
    ]) {
      f.dispose();
    }
    for (final a in _customAttributes) {
      a.dispose();
    }
    super.dispose();
  }

  void _addField() {
    final f = CreditCardFieldDraft(
      label: '',
      valueHint: 'text',
      removable: true,
      isLabelEditable: true,
    );
    f.valueController.addListener(_markDirty);
    setState(() {
      _isDirty = true;
      _identityFields.add(f);
    });
  }

  void _removeField(CreditCardFieldDraft field) {
    setState(() {
      _isDirty = true;
      _identityFields.remove(field);
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
    final hasSectionValue = <CreditCardFieldDraft>[
      ..._identityFields,
      ..._addressFields,
      ..._internetFields,
    ].any(
      (field) =>
          field.labelController.text.trim().isNotEmpty &&
          field.valueController.text.trim().isNotEmpty,
    );
    return title != 'Identity' ||
        _notesController.text.trim().isNotEmpty ||
        hasSectionValue ||
        _customAttributes.any(
          (a) =>
              a.labelController.text.trim().isNotEmpty &&
              a.valueController.text.trim().isNotEmpty,
        ) ||
        _tags.isNotEmpty;
  }

  String _valueForLabel(String label) {
    for (final field in _identityFields) {
      if (field.labelController.text.trim().toLowerCase() == label) {
        return field.valueController.text.trim();
      }
    }
    return '';
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

    final fullNameParts = <String>[
      _valueForLabel('first name'),
      _valueForLabel('initial'),
      _valueForLabel('last name'),
    ].where((v) => v.isNotEmpty).toList(growable: false);
    final fullName = fullNameParts.join(' ').trim();
    if (fullName.isNotEmpty) {
      fields.add(
        EntryField(
          key: AppKdbxFieldKeys.userName,
          value: fullName,
          isStandard: true,
        ),
      );
      fields.add(EntryField(key: 'Full Name', value: fullName));
    }

    for (final field in <CreditCardFieldDraft>[
      ..._identityFields,
      ..._addressFields,
      ..._internetFields,
    ]) {
      final key = field.labelController.text.trim();
      final value = field.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(
        EntryField(key: identityStorageKeyForLabel(key), value: value),
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
      widget.onShowToast('Identity saved');
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

    final fullNameParts = <String>[
      _valueForLabel('first name'),
      _valueForLabel('initial'),
      _valueForLabel('last name'),
    ].where((v) => v.isNotEmpty).toList(growable: false);
    final fullName = fullNameParts.join(' ').trim();
    if (fullName.isNotEmpty) {
      fields.add(
        EntryField(
          key: AppKdbxFieldKeys.userName,
          value: fullName,
          isStandard: true,
        ),
      );
      fields.add(EntryField(key: 'Full Name', value: fullName));
    }

    for (final field in <CreditCardFieldDraft>[
      ..._identityFields,
      ..._addressFields,
      ..._internetFields,
    ]) {
      final key = field.labelController.text.trim();
      final value = field.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(
        EntryField(key: identityStorageKeyForLabel(key), value: value),
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
      widget.onShowToast('Identity saved');
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
                if (_isEditing)
                  const SizedBox(width: 24)
                else
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
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF87E0A6), Color(0xFF4DBD7D)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Image.asset(
                    'assets/images/item_type_identity.png',
                    width: 30,
                    height: 30,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      TablerIcons.id,
                      size: 26,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (!_isEditing) ...[
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
                ],
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF9CB8EE),
                        width: 3,
                      ),
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
                      title: 'Identification',
                      showHeaderAction: false,
                      fields: _identityFields,
                      onAddField: _addField,
                      onRemoveField: _removeField,
                    ),
                    const SizedBox(height: 14),
                    CreditCardSectionCard(
                      title: 'Address',
                      showHeaderAction: false,
                      fields: _addressFields,
                      onAddField: _addField,
                      onRemoveField: _removeField,
                    ),
                    const SizedBox(height: 14),
                    CreditCardSectionCard(
                      title: 'Internet Details',
                      showHeaderAction: false,
                      fields: _internetFields,
                      onAddField: _addField,
                      onRemoveField: _removeField,
                    ),
                    const SizedBox(height: 14),
                    if (!_isEditing) ...[
                      CategoryDropdownField(
                        categories: categories,
                        rootGroupUuid: rootGroupUuid,
                        selectedCategoryUuid: effectiveCategoryUuid,
                        onChanged: (value) =>
                            setState(() => _selectedCategoryUuid = value),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                        options: _identityAddMoreOptions,
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
                  label: _isSaving
                      ? 'Saving...'
                      : (_isEditing ? 'Save changes' : 'Save'),
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
