import 'dart:io';

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

const List<String> _sshAddMoreOptions = <String>[
  'public key',
  'passphrase',
  'fingerprint',
  'key type',
  'Sensitive Text',
  'custom field',
];

class AddSshKeyItemModal extends ConsumerStatefulWidget {
  const AddSshKeyItemModal({
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
  ConsumerState<AddSshKeyItemModal> createState() => _AddSshKeyItemModalState();
}

class _AddSshKeyItemModalState extends ConsumerState<AddSshKeyItemModal> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagController;
  final List<LoginCustomAttribute> _customAttributes = <LoginCustomAttribute>[];
  final List<String> _tags = <String>[];
  String? _selectedCategoryUuid;
  String? _privateKeyName;
  String? _privateKeyValue;
  bool _showAddMoreOptions = false;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _isImporting = false;

  bool get _hasPrivateKeyMaterial =>
      (_privateKeyValue?.trim().isNotEmpty ?? false);

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.editingEntry;
    if (edit != null) {
      _titleController = TextEditingController(text: edit.title);
      _notesController = TextEditingController(text: edit.notes ?? '');
      _tagController = TextEditingController();
      _tags.addAll(edit.tags);

      // Pre-fill private key from entry.
      final pkField = edit.fieldByKey('Private Key');
      if (pkField != null && pkField.value.trim().isNotEmpty) {
        _privateKeyName = 'Private Key';
        _privateKeyValue = pkField.value;
      }

      // All non-standard fields go to custom attributes.
      const reserved = <String>{'title', 'private key'};
      for (final field in edit.fields) {
        final k = field.key.toLowerCase();
        if (reserved.contains(k)) continue;
        if (AppKdbxFieldKeys.isAttachmentMetaKey(field.key)) continue;
        _customAttributes.add(
          LoginCustomAttribute(
            label: field.key,
            value: field.value,
            isSecret: field.isProtected,
          ),
        );
      }
    } else {
      _titleController = TextEditingController(text: 'SSH Key');
      _notesController = TextEditingController();
      _tagController = TextEditingController();
    }

    _titleController.addListener(_markDirty);
    _notesController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    for (final attr in _customAttributes) {
      attr.dispose();
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

  void _clearPrivateKey() {
    setState(() {
      _isDirty = true;
      _privateKeyName = null;
      _privateKeyValue = null;
    });
  }

  Future<void> _pickPrivateKey() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose private key',
        allowMultiple: false,
        withData: false,
        type: FileType.any,
      );
      final files = result?.files;
      if (files == null || files.isEmpty) return;
      final file = files.first;
      if (file.path == null) return;
      await _importPrivateKeyFromPath(file.path!, file.name);
    } on MissingPluginException {
      widget.onShowToast('File picker is unavailable here');
    } catch (error) {
      widget.onShowToast('Unable to add private key: $error');
    }
  }

  Future<void> _importPrivateKeyFromPath(String path, String name) async {
    setState(() => _isImporting = true);
    try {
      final contents = await File(path).readAsString();
      if (!mounted) return;
      setState(() {
        _isDirty = true;
        _privateKeyName = name;
        _privateKeyValue = contents;
      });
      widget.onShowToast('Private key imported');
    } catch (error) {
      if (!mounted) return;
      widget.onShowToast('Unable to read private key: $error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _pastePrivateKeyFromClipboard() async {
    setState(() => _isImporting = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.trim().isEmpty) {
        widget.onShowToast('Clipboard is empty');
        return;
      }
      if (!_looksLikePrivateKey(text)) {
        widget.onShowToast(
          'Clipboard does not appear to contain a private key',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _isDirty = true;
        _privateKeyName = 'Pasted Private Key';
        _privateKeyValue = text;
      });
      widget.onShowToast('Private key pasted from clipboard');
    } catch (error) {
      if (!mounted) return;
      widget.onShowToast('Unable to paste: $error');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  bool _looksLikePrivateKey(String text) {
    return text.contains('BEGIN') &&
        (text.contains('PRIVATE KEY') ||
            text.contains('OPENSSH') ||
            text.contains('RSA'));
  }

  void _addCustomAttribute(String option) {
    final label = option.trim().toLowerCase();
    if (label == 'passphrase') {
      final alreadyAdded = _customAttributes.any(
        (a) => a.labelController.text.trim().toLowerCase() == 'passphrase',
      );
      if (alreadyAdded) {
        widget.onShowToast('Passphrase field already added');
        setState(() => _showAddMoreOptions = false);
        return;
      }
    }
    setState(() {
      _isDirty = true;
      _customAttributes.add(
        LoginCustomAttribute(
          label: label,
          value: '',
          isSecret: AppKdbxFieldKeys.isProtectedKey(label),
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

  bool _hasMeaningfulContent(String title) {
    return title != 'SSH Key' ||
        _hasPrivateKeyMaterial ||
        _notesController.text.trim().isNotEmpty ||
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

    final privateKeyValue = _privateKeyValue?.trim() ?? '';
    if (privateKeyValue.isNotEmpty) {
      fields.add(
        EntryField(
          key: 'Private Key',
          value: privateKeyValue,
          isProtected: true,
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
      widget.onShowToast('SSH key saved');
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
      widget.onShowToast('Add a private key or more details before saving');
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

    final privateKeyValue = _privateKeyValue?.trim() ?? '';
    if (privateKeyValue.isNotEmpty) {
      fields.add(
        EntryField(
          key: 'Private Key',
          value: privateKeyValue,
          isProtected: true,
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
      widget.onShowToast('SSH key saved');
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
                    color: const Color(0xFF9DE3E8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    TablerIcons.key,
                    size: 24,
                    color: Color(0xFF1B5D66),
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
                    // Private key section
                    _buildPrivateKeySection(),
                    const SizedBox(height: 14),
                    CategoryDropdownField(
                      categories: categories,
                      rootGroupUuid: rootGroupUuid,
                      selectedCategoryUuid: effectiveCategoryUuid,
                      onChanged: (value) =>
                          setState(() => _selectedCategoryUuid = value),
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
                        options: _sshAddMoreOptions,
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

  Widget _buildPrivateKeySection() {
    if (_hasPrivateKeyMaterial) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3FBF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBEDFC3)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFD9F2DF),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(
                TablerIcons.key,
                size: 20,
                color: Color(0xFF1D6E34),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _privateKeyName ?? 'Private key',
                    style: itemText(
                      12,
                      const Color(0xFF1A2E1C),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Private key loaded',
                    style: itemText(
                      10,
                      const Color(0xFF4A7D52),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: _clearPrivateKey,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  TablerIcons.x,
                  size: 14,
                  color: Color(0xFFD94A4A),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFDDE3EC),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(TablerIcons.key, size: 14, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Text(
                'private key',
                style: itemText(
                  11,
                  const Color(0xFF344054),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Add a private key to this SSH item by importing a key file or pasting from clipboard.',
            style: itemText(
              11,
              const Color(0xFF6B7280),
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _isImporting ? null : _pickPrivateKey,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          TablerIcons.upload,
                          size: 14,
                          color: Color(0xFF3B6FD3),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Import file',
                          style: itemText(
                            12,
                            const Color(0xFF3B6FD3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _isImporting ? null : _pastePrivateKeyFromClipboard,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          TablerIcons.clipboard,
                          size: 14,
                          color: Color(0xFF4B5563),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Paste',
                          style: itemText(
                            12,
                            const Color(0xFF4B5563),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isImporting) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
