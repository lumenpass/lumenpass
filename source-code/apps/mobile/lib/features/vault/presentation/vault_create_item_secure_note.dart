import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../application/vault_entries_providers.dart';
import '../../../core/repository/database_save_sync.dart';
import '../../../core/repository/providers.dart';
import '../../unlock/application/database_registry.dart';
import 'vault_create_item_models.dart';
import 'vault_create_item_shared.dart';

const List<String> _secureNoteAddMoreOptions = <String>[
  'custom field',
  'Sensitive Text',
  'url',
  'date',
];

class AddSecureNoteItemModal extends ConsumerStatefulWidget {
  const AddSecureNoteItemModal({
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
  ConsumerState<AddSecureNoteItemModal> createState() =>
      _AddSecureNoteItemModalState();
}

class _AddSecureNoteItemModalState
    extends ConsumerState<AddSecureNoteItemModal> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagController;
  final List<LoginCustomAttribute> _customAttributes = <LoginCustomAttribute>[];
  final List<LoginAttachment> _attachments = <LoginAttachment>[];
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
      _titleController = TextEditingController(text: edit.title);
      _bodyController = TextEditingController(text: edit.notes ?? '');
      _tagController = TextEditingController();
      _tags.addAll(edit.tags);

      const standardAndSystem = <String>{AppKdbxFieldKeys.title};
      for (final field in edit.fields) {
        final key = field.key;
        if (standardAndSystem.contains(key)) continue;
        if (AppKdbxFieldKeys.isAttachmentMetaKey(key)) continue;
        _customAttributes.add(
          LoginCustomAttribute(
            label: key,
            value: field.value,
            isSecret: field.isProtected,
          ),
        );
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
    final attribute = _customAttributes[index];
    setState(() {
      _isDirty = true;
      _customAttributes.removeAt(index);
    });
    attribute.dispose();
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose attachments',
        allowMultiple: true,
        withData: false,
        type: FileType.any,
      );
      final files = result?.files;
      if (files == null || files.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _attachments.addAll(
          files
              .where((file) => file.path != null)
              .map(
                (file) => LoginAttachment(
                  name: file.name,
                  size: file.size,
                  path: file.path,
                  isImage: _isImageName(file.name),
                ),
              ),
        );
      });
    } on MissingPluginException {
      widget.onShowToast('Attachment picker is unavailable here');
    } catch (error) {
      widget.onShowToast('Unable to add attachments: $error');
    }
  }

  bool _isImageName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  void _removeAttachment(LoginAttachment attachment) {
    setState(() => _attachments.remove(attachment));
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

  bool _hasMeaningfulContent(String title) {
    return title != 'Secure Note' ||
        _bodyController.text.trim().isNotEmpty ||
        _attachments.isNotEmpty ||
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
    for (final attr in _customAttributes) {
      final key = attr.labelController.text.trim();
      if (key.isEmpty) continue;
      fields.add(
        EntryField(
          key: key,
          value: attr.valueController.text,
          isProtected: attr.shouldProtect,
        ),
      );
    }
    // Preserve attachment metadata fields from the original entry.
    for (final field in edit.fields) {
      if (AppKdbxFieldKeys.isAttachmentMetaKey(field.key)) {
        fields.add(field);
      }
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      await repository.updateEntry(
        entryUuid: edit.uuid,
        fields: fields,
        notes: _bodyController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
      );
      final registry = ref.read(databaseRegistryProvider);
      final database = await saveAndSyncDatabase(repository, registry);
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultVisibleEntriesProvider);
      ref.invalidate(vaultAllTagsProvider);
      ref.invalidate(vaultSidebarCategoriesProvider);
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

    for (final attr in _customAttributes) {
      final key = attr.labelController.text.trim();
      final value = attr.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) continue;
      fields.add(
        EntryField(key: key, value: value, isProtected: attr.shouldProtect),
      );
    }

    for (var i = 0; i < _attachments.length; i++) {
      final a = _attachments[i];
      fields.add(
        EntryField(
          key: '${AppKdbxFieldKeys.attachmentNamePrefix}$i',
          value: a.name,
        ),
      );
      fields.add(
        EntryField(
          key: '${AppKdbxFieldKeys.attachmentSizePrefix}$i',
          value: a.size.toString(),
        ),
      );
      fields.add(
        EntryField(
          key: '${AppKdbxFieldKeys.attachmentImagePrefix}$i',
          value: a.isImage ? '1' : '0',
        ),
      );
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final entryAttachments = _attachments
          .where((a) => a.path != null)
          .map((a) => EntryAttachment(fileName: a.name, filePath: a.path!))
          .toList(growable: false);
      final createdEntry = await repository.createEntry(
        groupUuid: targetGroupUuid,
        fields: fields,
        notes: _bodyController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
        attachments: entryAttachments,
      );
      final registry = ref.read(databaseRegistryProvider);
      final database = await saveAndSyncDatabase(repository, registry);
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultVisibleEntriesProvider);
      ref.invalidate(vaultAllTagsProvider);
      ref.invalidate(vaultSidebarCategoriesProvider);
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
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFFFE1AE),
                  ),
                  alignment: Alignment.center,
                  child: Image.asset(
                    'assets/images/item_type_note.png',
                    width: 32,
                    height: 32,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      TablerIcons.notes,
                      size: 22,
                      color: Color(0xFFC17800),
                    ),
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
                      color: const Color(0xFFF7F9FB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF8BA9D8),
                        width: 2,
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
                    LoginFormField(
                      label: 'note',
                      controller: _bodyController,
                      maxLines: 8,
                      minLines: 8,
                      icon: TablerIcons.notes,
                      iconColor: const Color(0xFFB98A1B),
                      hintText: 'Add any notes about this item here.',
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => setState(
                        () => _showAddMoreOptions = !_showAddMoreOptions,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EEF9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '+ add more',
                              style: itemText(
                                12,
                                const Color(0xFF3B6FD3),
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
                        options: _secureNoteAddMoreOptions,
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
                    const SizedBox(height: 12),
                    CategoryDropdownField(
                      categories: categories,
                      rootGroupUuid: rootGroupUuid,
                      selectedCategoryUuid: effectiveCategoryUuid,
                      onChanged: (value) =>
                          setState(() => _selectedCategoryUuid = value),
                    ),
                    const SizedBox(height: 10),
                    AttachmentSection(
                      attachments: _attachments,
                      onAddPressed: _pickAttachments,
                      onRemove: _removeAttachment,
                    ),
                    const SizedBox(height: 10),
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
