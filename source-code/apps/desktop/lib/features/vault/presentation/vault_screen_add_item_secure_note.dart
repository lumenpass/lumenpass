part of 'vault_screen.dart';

class _AddSecureNoteItemModal extends ConsumerStatefulWidget {
  const _AddSecureNoteItemModal({
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
  ConsumerState<_AddSecureNoteItemModal> createState() =>
      _AddSecureNoteItemModalState();
}

class _AddSecureNoteItemModalState
    extends ConsumerState<_AddSecureNoteItemModal> {
  final LayerLink _addMoreLink = LayerLink();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagController;
  final List<_LoginCustomAttribute> _customAttributes =
      <_LoginCustomAttribute>[];
  final List<_LoginAttachment> _attachments = <_LoginAttachment>[];
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
    if (edit != null) {
      final entries = ref.read(vaultDatabaseEntriesProvider);
      final idx = entries.indexWhere((e) => e.uuid == edit.uuid);
      final kdbx = idx >= 0 ? entries[idx] : null;

      _titleController = TextEditingController(text: kdbx?.title ?? edit.title);
      _bodyController = TextEditingController(text: kdbx?.notes ?? edit.notes);
      _tagController = TextEditingController();
      _tags.addAll(kdbx?.tags ?? edit.tags);
      _attachments.addAll(
        edit.attachments.map(_LoginAttachment.fromMockAttachment),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadExistingBinaryAttachments());
      });

      if (kdbx != null) {
        for (final field in kdbx.fields) {
          final key = field.key;
          if (key == AppKdbxFieldKeys.title) continue;
          if (AppKdbxFieldKeys.isAttachmentMetaKey(key)) continue;
          if (key.toLowerCase().contains('kpex_passkey_')) continue;
          _customAttributes.add(
            _LoginCustomAttribute(
              label: key,
              value: field.value,
              isSecret: field.isProtected,
            ),
          );
        }
      }
    } else {
      _titleController = TextEditingController(text: 'Secure Note');
      _bodyController = TextEditingController();
      _tagController = TextEditingController();
    }
    _titleController.addListener(_markDirty);
    _bodyController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagController.dispose();
    for (final a in _customAttributes) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingBinaryAttachments() async {
    final edit = widget.editingEntry;
    if (edit == null || edit.uuid.isEmpty) {
      return;
    }
    try {
      final binaryAttachments =
          await ref.read(kdbxRepositoryProvider).getEntryAttachments(edit.uuid);
      if (!mounted || binaryAttachments.isEmpty) {
        return;
      }
      final mergedAttachments =
          _mergeBinaryAttachments(_attachments, binaryAttachments);
      setState(() {
        _attachments
          ..clear()
          ..addAll(mergedAttachments);
      });
    } catch (_) {
      // Keep metadata-only attachments if binary extraction fails.
    }
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

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose attachments',
        allowMultiple: true,
        lockParentWindow: true,
        withData: false,
        type: FileType.any,
      );
      final files = result?.files;
      if (files == null || files.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _isDirty = true;
        _attachments.addAll(
          files
              .where((file) => file.path != null)
              .map(_LoginAttachment.fromPlatformFile),
        );
      });
    } on MissingPluginException {
      widget.onShowToast('Attachment picker is unavailable here');
    } catch (error) {
      widget.onShowToast('Unable to add attachments: $error');
    }
  }

  void _removeAttachment(_LoginAttachment attachment) {
    setState(() {
      _isDirty = true;
      _attachments.remove(attachment);
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

  bool _hasCompletedCustomAttribute() {
    return _customAttributes.any((a) {
      return a.labelController.text.trim().isNotEmpty &&
          a.valueController.text.trim().isNotEmpty;
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
    return title != 'Secure Note' ||
        _bodyController.text.trim().isNotEmpty ||
        _hasCompletedCustomAttribute() ||
        _attachments.isNotEmpty ||
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
    for (final attr in _customAttributes) {
      final key = attr.labelController.text.trim();
      if (key.isEmpty) continue;
      fields.add(EntryField(
        key: key,
        value: attr.valueController.text,
        isProtected: attr.shouldProtect,
      ));
    }
    _appendAttachmentFields(fields, _attachments);

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final entryAttachments =
          await _resolveEditAttachments(repository, edit.uuid, _attachments);
      await repository.updateEntry(
        entryUuid: edit.uuid,
        fields: fields,
        notes: _bodyController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
        attachments: entryAttachments,
      );
      publishAndScheduleSave(ref, repository);
      widget.onItemSaved(edit.uuid);
      widget.onShowToast('Secure note saved');
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
      widget.onShowToast('Add some content before saving');
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
    _appendAttachmentFields(fields, _attachments);

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final entryAttachments = _newEntryAttachmentsFrom(_attachments);
      final createdEntry = await repository.createEntry(
        groupUuid: targetGroupUuid,
        fields: fields,
        notes: _bodyController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
        attachments: entryAttachments,
      );
      publishAndScheduleSave(ref, repository);
      widget.onItemSaved(createdEntry.uuid);
      widget.onShowToast('Secure note saved');
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
        final modalWidth = math.min(680.0, constraints.maxWidth);
        final modalHeight = math.min(760.0, constraints.maxHeight);
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
            cursorColor: _kPrimaryButtonColor,
            selectionColor: DcColors.selectionSoft,
            selectionHandleColor: _kPrimaryButtonColor,
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
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _ItemModalColors.surface,
                  borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: DcColors.shadow,
                      blurRadius: 44,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DcDialogTitleBar(
                      title:
                          _isEditing ? 'Edit Secure Note' : 'New Secure Note',
                      onBack: _isEditing ? null : widget.onReturnToPicker,
                      onClose: _confirmClose,
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: <Widget>[
                          const _AddItemTypeIcon(
                            icon: TablerIcons.notes,
                            color: DcColors.orange,
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
                                  color: _ItemModalColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(TablerIcons.chevron_down,
                                    size: 14,
                                    color: _ItemModalColors.headerLabel),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Container(
                              height: 42,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: _ItemModalColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: _kPrimaryButtonColor, width: 2),
                              ),
                              alignment: Alignment.centerLeft,
                              child: TextField(
                                controller: _titleController,
                                maxLines: 1,
                                textAlignVertical: TextAlignVertical.center,
                                style: _displayText(
                                  22,
                                  _ItemModalColors.title,
                                  height: 1,
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
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: <Widget>[
                            _LoginFormField(
                              label: 'note',
                              controller: _bodyController,
                              maxLines: 8,
                              minLines: 8,
                              icon: TablerIcons.notes,
                              iconColor: DcColors.amberOnLight,
                              hintText: 'Add any notes about this item here.',
                            ),
                            const SizedBox(height: 12),
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
                                    color: _ItemModalColors.peachSoft,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Text(
                                        '+ add more',
                                        style: _text(12, _kPrimaryButtonColor,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        _showAddMoreOptions
                                            ? TablerIcons.chevron_up
                                            : TablerIcons.chevron_down,
                                        size: 14,
                                        color: _ItemModalColors.icon,
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
                            if (!_isEditing) ...<Widget>[
                              const SizedBox(height: 12),
                              _CategoryDropdownField(
                                categories: categories,
                                rootGroupUuid: rootGroupUuid,
                                selectedCategoryUuid: effectiveCategoryUuid,
                                onChanged: (value) => setState(
                                    () => _selectedCategoryUuid = value),
                              ),
                            ],
                            const SizedBox(height: 10),
                            _AttachmentSection(
                              attachments: _attachments,
                              onAddPressed: _pickAttachments,
                              onRemove: _removeAttachment,
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'tags',
                                style: _text(12, _kPrimaryButtonColor,
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
                    Container(height: 1, color: _ItemModalColors.borderSoft),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          _LoginFooterButton(
                            label: 'Cancel',
                            backgroundColor: _ItemModalColors.surfaceMuted,
                            textColor: _ItemModalColors.headerLabel,
                            borderColor: _ItemModalColors.borderPane,
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
