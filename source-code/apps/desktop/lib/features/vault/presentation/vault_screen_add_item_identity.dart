part of 'vault_screen.dart';

class _AddIdentityItemModal extends ConsumerStatefulWidget {
  const _AddIdentityItemModal({
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
  final _MockEntry? editingEntry;

  @override
  ConsumerState<_AddIdentityItemModal> createState() =>
      _AddIdentityItemModalState();
}

class _AddIdentityItemModalState extends ConsumerState<_AddIdentityItemModal> {
  final LayerLink _addMoreLink = LayerLink();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagController;
  late final List<_CreditCardFieldDraft> _identityFields;
  late final List<_CreditCardFieldDraft> _addressFields;
  late final List<_CreditCardFieldDraft> _internetFields;
  final List<_LoginCustomAttribute> _customAttributes =
      <_LoginCustomAttribute>[];
  final List<String> _tags = <String>[];
  String? _selectedCategoryUuid;
  bool _showAddMoreOptions = false;
  bool _isDirty = false;
  bool _isSaving = false;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    _identityFields = <_CreditCardFieldDraft>[
      _CreditCardFieldDraft(label: 'first name', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'initial', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'last name', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'gender', valueHint: 'text'),
      _CreditCardFieldDraft(
        label: 'birth date',
        valueHint: 'mm/dd/yyyy',
        keyboardType: TextInputType.datetime,
        trailingIcon: Icons.calendar_today_outlined,
        showsCalendarPicker: true,
      ),
      _CreditCardFieldDraft(label: 'occupation', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'company', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'department', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'job title', valueHint: 'text'),
    ];
    _addressFields = <_CreditCardFieldDraft>[
      _CreditCardFieldDraft(label: 'address', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'city', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'state', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'zip', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'country', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'default phone', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'home', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'cell', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'business', valueHint: 'text'),
    ];
    _internetFields = <_CreditCardFieldDraft>[
      _CreditCardFieldDraft(label: 'username', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'reminder question', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'reminder answer', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'email', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'website', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'ICQ', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'skype', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'AOL/IM', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'Yahoo', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'MSN', valueHint: 'text'),
      _CreditCardFieldDraft(label: 'firm signature', valueHint: 'text'),
    ];

    final edit = widget.editingEntry;
    if (edit != null) {
      final entries = ref.read(vaultDatabaseEntriesProvider);
      final idx = entries.indexWhere((e) => e.uuid == edit.uuid);
      final kdbx = idx >= 0 ? entries[idx] : null;

      _titleController = TextEditingController(text: kdbx?.title ?? edit.title);
      _notesController = TextEditingController(text: kdbx?.notes ?? edit.notes);
      _tagController = TextEditingController();
      _tags.addAll(kdbx?.tags ?? edit.tags);

      if (kdbx != null) {
        for (final draft in <_CreditCardFieldDraft>[
          ..._identityFields,
          ..._addressFields,
          ..._internetFields,
        ]) {
          final v = editIdentityFieldValueFromKdbx(
            kdbx,
            draft.labelController.text,
          );
          if (v.isNotEmpty) draft.valueController.text = v;
        }
        final knownStorageKeys = <String>{
          AppKdbxFieldKeys.title,
          AppKdbxFieldKeys.userName,
          'Full Name',
          for (final label in <String>[
            'first name',
            'initial',
            'last name',
            'gender',
            'birth date',
            'occupation',
            'company',
            'department',
            'job title',
            'address',
            'city',
            'state',
            'zip',
            'country',
            'default phone',
            'home',
            'cell',
            'business',
            'username',
            'reminder question',
            'reminder answer',
            'email',
            'website',
            'ICQ',
            'skype',
            'AOL/IM',
            'Yahoo',
            'MSN',
            'firm signature',
          ])
            ...identityStorageKeysForLabel(label),
        };
        for (final field in kdbx.fields) {
          if (knownStorageKeys.contains(field.key)) continue;
          if (AppKdbxFieldKeys.isAttachmentMetaKey(field.key)) continue;
          if (field.key.toLowerCase().contains('kpex_passkey_')) continue;
          _customAttributes.add(
            _LoginCustomAttribute(
              label: field.key,
              value: field.value,
              isSecret: field.isProtected,
            ),
          );
        }
      }
    } else {
      _titleController = TextEditingController(text: 'Identity');
      _notesController = TextEditingController();
      _tagController = TextEditingController();
    }
    _titleController.addListener(_markDirty);
    _notesController.addListener(_markDirty);
    for (final f in <_CreditCardFieldDraft>[
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
    for (final f in <_CreditCardFieldDraft>[
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
    final f = _CreditCardFieldDraft(
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

  void _removeField(_CreditCardFieldDraft field) {
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
        _LoginCustomAttribute(
          label: option.toLowerCase(),
          value: '',
          isSecret: AppKdbxFieldKeys.isProtectedKey(option),
        ),
      );
      _showAddMoreOptions = false;
    });
  }

  void _removeCustomAttribute(int index) {
    final attribute = _customAttributes[index];
    setState(() {
      _isDirty = true;
      _customAttributes.removeAt(index);
    });
    attribute.dispose();
  }

  void _reorderCustomAttribute(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex) {
      return;
    }
    setState(() {
      _isDirty = true;
      final attribute = _customAttributes.removeAt(oldIndex);
      _customAttributes.insert(newIndex, attribute);
    });
  }

  void _addTag(String rawTag) {
    final normalized = rawTag.trim();
    if (normalized.isEmpty) return;
    final alreadyExists = _tags.any(
      (tag) => tag.toLowerCase() == normalized.toLowerCase(),
    );
    if (alreadyExists) return;
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
    _showDiscardDialog(context, widget.onClose);
  }

  bool _hasMeaningfulContent(String title) {
    if (_isEditing) {
      return title.isNotEmpty;
    }
    final hasSectionValue = <_CreditCardFieldDraft>[
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
        _customAttributes.any((a) =>
            a.labelController.text.trim().isNotEmpty &&
            a.valueController.text.trim().isNotEmpty) ||
        _tags.isNotEmpty;
  }

  Future<void> _saveEdit() async {
    final edit = widget.editingEntry;
    if (edit == null) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      widget.onShowToast('Title is required');
      return;
    }

    final fields = <EntryField>[
      EntryField(key: AppKdbxFieldKeys.title, value: title, isStandard: true),
    ];

    String valueForLabel(String label) {
      for (final field in _identityFields) {
        if (field.labelController.text.trim().toLowerCase() == label) {
          return field.valueController.text.trim();
        }
      }
      return '';
    }

    final fullNameParts = <String>[
      valueForLabel('first name'),
      valueForLabel('initial'),
      valueForLabel('last name'),
    ].where((v) => v.isNotEmpty).toList(growable: false);
    final fullName = fullNameParts.join(' ').trim();
    if (fullName.isNotEmpty) {
      fields.add(EntryField(
          key: AppKdbxFieldKeys.userName, value: fullName, isStandard: true));
      fields.add(EntryField(key: 'Full Name', value: fullName));
    }

    for (final field in <_CreditCardFieldDraft>[
      ..._identityFields,
      ..._addressFields,
      ..._internetFields,
    ]) {
      final key = field.labelController.text.trim();
      final value = field.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(EntryField(key: identityStorageKeyForLabel(key), value: value));
    }

    for (final attr in _customAttributes) {
      final key = attr.labelController.text.trim();
      final value = attr.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(EntryField(
        key: key,
        value: value,
        isProtected: attr.shouldProtect,
      ));
    }

    setState(() => _isSaving = true);
    await _delayBeforeSavingOperation();
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      await repository.updateEntry(
        entryUuid: edit.uuid,
        fields: fields,
        notes: _notesController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
      );
      final database = await saveAndSyncDatabase(
          repository, ref.read(databaseRegistryProvider));
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultEntriesProvider);
      ref.invalidate(vaultSidebarTagsProvider);
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
    final targetGroupUuid = _resolveEffectiveCategoryUuid(
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

    String valueForLabel(String label) {
      for (final field in _identityFields) {
        if (field.labelController.text.trim().toLowerCase() == label) {
          return field.valueController.text.trim();
        }
      }
      return '';
    }

    final fullNameParts = <String>[
      valueForLabel('first name'),
      valueForLabel('initial'),
      valueForLabel('last name'),
    ].where((v) => v.isNotEmpty).toList(growable: false);
    final fullName = fullNameParts.join(' ').trim();
    if (fullName.isNotEmpty) {
      fields.add(EntryField(
          key: AppKdbxFieldKeys.userName, value: fullName, isStandard: true));
      fields.add(EntryField(key: 'Full Name', value: fullName));
    }

    for (final field in <_CreditCardFieldDraft>[
      ..._identityFields,
      ..._addressFields,
      ..._internetFields,
    ]) {
      final key = field.labelController.text.trim();
      final value = field.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(EntryField(key: identityStorageKeyForLabel(key), value: value));
    }

    for (final attribute in _customAttributes) {
      final key = attribute.labelController.text.trim();
      final value = attribute.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(EntryField(
        key: key,
        value: value,
        isProtected: attribute.shouldProtect,
      ));
    }

    setState(() => _isSaving = true);
    await _delayBeforeSavingOperation();
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final createdEntry = await repository.createEntry(
        groupUuid: targetGroupUuid,
        fields: fields,
        notes: _notesController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
      );
      final database = await saveAndSyncDatabase(
          repository, ref.read(databaseRegistryProvider));
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultEntriesProvider);
      ref.invalidate(vaultSidebarTagsProvider);
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
    final existingTags = ref.watch(vaultSidebarTagsProvider);
    final rootGroupUuid = ref.watch(
      kdbxRepositoryProvider.select((r) => r.rootGroupUuid),
    );
    final selectedGroupUuid = ref.watch(vaultSelectedGroupProvider);
    final effectiveCategoryUuid = _resolveEffectiveCategoryUuid(
      categories: categories,
      rootGroupUuid: rootGroupUuid,
      selectedGroupUuid: selectedGroupUuid,
      selectedCategoryUuid: _selectedCategoryUuid,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final modalWidth = math.min(760.0, constraints.maxWidth);
        final modalHeight = math.min(820.0, constraints.maxHeight);
        final modalTheme = Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
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
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: modalWidth,
                constraints: BoxConstraints(maxHeight: modalHeight),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7EBF0),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFD0D8E2)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1C172033),
                      blurRadius: 44,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (_isEditing)
                          const SizedBox(width: 24)
                        else
                          _ModalIconAction(
                            icon: TablerIcons.arrow_left,
                            onTap: widget.onReturnToPicker ?? () {},
                          ),
                        Expanded(
                          child: Text(
                            _isEditing ? 'Edit Item' : 'New Item',
                            textAlign: TextAlign.center,
                            style: _text(20, const Color(0xFF2E3138),
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        _ModalIconAction(
                            icon: TablerIcons.x, onTap: _confirmClose),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: <Color>[
                                Color(0xFF87E0A6),
                                Color(0xFF4DBD7D),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Image.asset(
                            'assets/images/item_type_identity.png',
                            width: 34,
                            height: 34,
                            errorBuilder: (_, __, ___) => const Icon(
                              TablerIcons.id,
                              size: 30,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (!_isEditing) ...<Widget>[
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
                              child: const Icon(TablerIcons.chevron_down,
                                  size: 14, color: Color(0xFF667085)),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: _isEditing
                                  ? const Color(0xFFF7F8FB)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _isEditing
                                    ? const Color(0xFFE8ECF3)
                                    : const Color(0xFF9CB8EE),
                                width: _isEditing ? 1 : 3,
                              ),
                            ),
                            alignment: Alignment.centerLeft,
                            child: TextField(
                              controller: _titleController,
                              maxLines: 1,
                              textAlignVertical: TextAlignVertical.center,
                              style: const TextStyle(
                                fontSize: 22,
                                height: 1,
                                color: Color(0xFF2E3138),
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                              ),
                              decoration: const InputDecoration(
                                filled: false,
                                fillColor: Colors.transparent,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
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
                          children: <Widget>[
                            _CreditCardSectionCard(
                              title: 'Identification',
                              showHeaderAction: false,
                              fields: _identityFields,
                              onAddField: _addField,
                              onRemoveField: _removeField,
                            ),
                            const SizedBox(height: 14),
                            _CreditCardSectionCard(
                              title: 'Address',
                              showHeaderAction: false,
                              fields: _addressFields,
                              onAddField: _addField,
                              onRemoveField: _removeField,
                            ),
                            const SizedBox(height: 14),
                            _CreditCardSectionCard(
                              title: 'Internet Details',
                              showHeaderAction: false,
                              fields: _internetFields,
                              onAddField: _addField,
                              onRemoveField: _removeField,
                            ),
                            if (!_isEditing) ...<Widget>[
                              const SizedBox(height: 14),
                              _CategoryDropdownField(
                                categories: categories,
                                rootGroupUuid: rootGroupUuid,
                                selectedCategoryUuid: effectiveCategoryUuid,
                                onChanged: (value) => setState(
                                    () => _selectedCategoryUuid = value),
                              ),
                              const SizedBox(height: 12),
                            ],
                            CompositedTransformTarget(
                              link: _addMoreLink,
                              child: InkWell(
                                onTap: () => setState(() =>
                                    _showAddMoreOptions = !_showAddMoreOptions),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F7FB),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Text(
                                        '+ add more',
                                        style: _text(
                                            12, const Color(0xFF0B63E5),
                                            fontWeight: FontWeight.w600),
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
                            ),
                            if (_customAttributes.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 10),
                              _CustomAttributeList(
                                attributes: _customAttributes,
                                onRemove: _removeCustomAttribute,
                                onReorder: _reorderCustomAttribute,
                              ),
                            ],
                            const SizedBox(height: 14),
                            _LoginFormField(
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
                                style: _text(12, const Color(0xFF6D63D6),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _TagEditor(
                              tags: _tags,
                              existingTags: existingTags
                                  .map((e) => e.tag)
                                  .toList(growable: false),
                              controller: _tagController,
                              onAddTag: _addTag,
                              onRemoveTag: _removeTag,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(height: 1, color: const Color(0xFFCCD4DF)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        _LoginFooterButton(
                          label: 'Cancel',
                          backgroundColor: const Color(0xFFEBEEF3),
                          textColor: const Color(0xFF3E4B60),
                          borderColor: const Color(0xFFC0C9D4),
                          onTap: _isSaving ? null : _confirmClose,
                        ),
                        const SizedBox(width: 10),
                        _LoginFooterButton(
                          label: _isSaving
                              ? 'Saving...'
                              : (_isEditing ? 'Save changes' : 'Save'),
                          backgroundColor: _kPrimaryButtonColor,
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
              if (_showAddMoreOptions)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: false,
                    child: CompositedTransformFollower(
                      link: _addMoreLink,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.bottomLeft,
                      followerAnchor: Alignment.topLeft,
                      offset: const Offset(0, 8),
                      child: Align(
                        alignment: Alignment.topLeft,
                        widthFactor: 1,
                        heightFactor: 1,
                        child: SizedBox(
                          width: 320,
                          child: Material(
                            color: Colors.transparent,
                            child: _AddMoreOptionsCard(
                              options: _loginAddMoreOptions,
                              onSelected: _addCustomAttribute,
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
      },
    );
  }
}
