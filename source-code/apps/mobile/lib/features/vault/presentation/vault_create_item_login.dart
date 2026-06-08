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
import 'vault_totp_capture_overlay.dart';

const List<String> _loginAddMoreOptions = <String>[
  'phone',
  'email',
  'security question',
  'license key',
  'One-Time Password',
  'Sensitive Text',
  'custom field',
];

class AddLoginItemModal extends ConsumerStatefulWidget {
  const AddLoginItemModal({
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

  /// When set, the modal opens in edit mode: fields are pre-populated and
  /// saving calls [KdbxRepository.updateEntry] instead of [createEntry].
  final KdbxEntry? editingEntry;

  @override
  ConsumerState<AddLoginItemModal> createState() => _AddLoginItemModalState();
}

class _AddLoginItemModalState extends ConsumerState<AddLoginItemModal> {
  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final List<TextEditingController> _websiteControllers;
  late final TextEditingController _notesController;
  late final TextEditingController _tagController;
  final List<LoginCustomAttribute> _customAttributes = <LoginCustomAttribute>[];
  final List<LoginAttachment> _attachments = <LoginAttachment>[];
  final List<String> _tags = <String>[];
  String? _selectedCategoryUuid;
  String? _totpAuthUrl;
  bool _showAddMoreOptions = false;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _obscurePassword = true;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.editingEntry;
    if (edit != null) {
      _titleController = TextEditingController(text: edit.title);
      _usernameController = TextEditingController(text: edit.username ?? '');
      _passwordController = TextEditingController(
        text: edit.fieldByKey(AppKdbxFieldKeys.password)?.value ?? '',
      );
      final primaryUrl = edit.url ?? '';
      _websiteControllers = <TextEditingController>[
        TextEditingController(text: primaryUrl),
      ];
      for (var i = 2; i <= 20; i++) {
        final field = edit.fieldByKey('URL $i');
        if (field == null) break;
        _websiteControllers.add(TextEditingController(text: field.value));
      }
      _notesController = TextEditingController(text: edit.notes ?? '');
      _tagController = TextEditingController();
      _tags.addAll(edit.tags);
      final otpField =
          edit.fieldByKey(AppKdbxFieldKeys.otpAuth) ?? edit.fieldByKey('otp');
      if (otpField != null && otpField.value.isNotEmpty) {
        _totpAuthUrl = otpField.value;
      }

      const standardAndSystem = <String>{
        AppKdbxFieldKeys.title,
        AppKdbxFieldKeys.userName,
        AppKdbxFieldKeys.password,
        AppKdbxFieldKeys.url,
        AppKdbxFieldKeys.otpAuth,
        'otp',
      };
      for (final field in edit.fields) {
        final key = field.key;
        if (standardAndSystem.contains(key)) continue;
        if (AppKdbxFieldKeys.isAttachmentMetaKey(key)) continue;
        if (RegExp(r'^URL \d+$').hasMatch(key)) continue;
        if (key.toLowerCase().contains('kpex_passkey_')) continue;
        _customAttributes.add(
          LoginCustomAttribute(
            label: key,
            value: field.value,
            isSecret: field.isProtected,
          ),
        );
      }
    } else {
      _titleController = TextEditingController(text: 'Login');
      _usernameController = TextEditingController();
      _passwordController = TextEditingController();
      _websiteControllers = <TextEditingController>[TextEditingController()];
      _notesController = TextEditingController();
      _tagController = TextEditingController();
    }
    _titleController.addListener(_markDirty);
    _usernameController.addListener(_markDirty);
    _passwordController.addListener(_markDirty);
    for (final c in _websiteControllers) {
      c.addListener(_markDirty);
    }
    _notesController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    for (final c in _websiteControllers) {
      c.dispose();
    }
    _notesController.dispose();
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

  void _addWebsiteField() {
    final c = TextEditingController(text: 'https://');
    c.addListener(_markDirty);
    setState(() {
      _isDirty = true;
      _websiteControllers.add(c);
    });
  }

  void _removeWebsiteField(int index) {
    final controller = _websiteControllers[index];
    setState(() {
      _isDirty = true;
      _websiteControllers.removeAt(index);
    });
    controller.dispose();
  }

  void _addCustomAttribute(String option) {
    if (option.toLowerCase() == 'one-time password') {
      setState(() => _showAddMoreOptions = false);
      _openTotpEditor();
      return;
    }
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

  Future<void> _openTotpEditor() async {
    final url = await showTotpCaptureOverlay(context);
    if (!mounted || url == null || url.trim().isEmpty) {
      return;
    }
    setState(() {
      _totpAuthUrl = url;
      _isDirty = true;
    });
  }

  bool _hasMeaningfulContent(String title) {
    final hasWebsite = _websiteControllers.any((c) {
      final v = c.text.trim();
      return v.isNotEmpty && v != 'https://';
    });
    return title != 'Login' ||
        _usernameController.text.trim().isNotEmpty ||
        _passwordController.text.isNotEmpty ||
        hasWebsite ||
        _notesController.text.trim().isNotEmpty ||
        (_totpAuthUrl != null && _totpAuthUrl!.trim().isNotEmpty) ||
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
      EntryField(
        key: AppKdbxFieldKeys.userName,
        value: _usernameController.text.trim(),
        isStandard: true,
      ),
      EntryField(
        key: AppKdbxFieldKeys.password,
        value: _passwordController.text,
        isProtected: true,
        isStandard: true,
      ),
      EntryField(
        key: AppKdbxFieldKeys.url,
        value: _websiteControllers.first.text.trim(),
        isStandard: true,
      ),
    ];

    for (var i = 1; i < _websiteControllers.length; i++) {
      final value = _websiteControllers[i].text.trim();
      if (value.isEmpty || value == 'https://') continue;
      fields.add(EntryField(key: 'URL ${i + 1}', value: value));
    }

    for (final attr in _customAttributes) {
      final key = attr.labelController.text.trim();
      final value = attr.valueController.text.trim();
      if (key.isEmpty) continue;
      fields.add(
        EntryField(key: key, value: value, isProtected: attr.shouldProtect),
      );
    }

    final otpField =
        edit.fieldByKey(AppKdbxFieldKeys.otpAuth) ?? edit.fieldByKey('otp');
    if (_totpAuthUrl != null && _totpAuthUrl!.isNotEmpty) {
      fields.add(
        EntryField(
          key: otpField?.key ?? AppKdbxFieldKeys.otpAuth,
          value: _totpAuthUrl!,
          isProtected: true,
          isStandard: true,
        ),
      );
    }
    for (final field in edit.fields) {
      if (field.key.toLowerCase().contains('kpex_passkey_')) {
        fields.add(field);
      }
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
      widget.onShowToast('Login item saved');
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
      EntryField(
        key: AppKdbxFieldKeys.userName,
        value: _usernameController.text.trim(),
        isStandard: true,
      ),
      EntryField(
        key: AppKdbxFieldKeys.password,
        value: _passwordController.text,
        isProtected: true,
        isStandard: true,
      ),
      EntryField(
        key: AppKdbxFieldKeys.url,
        value: _websiteControllers.first.text.trim(),
        isStandard: true,
      ),
    ];

    for (var i = 1; i < _websiteControllers.length; i++) {
      final value = _websiteControllers[i].text.trim();
      if (value.isEmpty) continue;
      fields.add(EntryField(key: 'URL ${i + 1}', value: value));
    }
    if (_totpAuthUrl != null && _totpAuthUrl!.isNotEmpty) {
      fields.add(
        EntryField(
          key: AppKdbxFieldKeys.otpAuth,
          value: _totpAuthUrl!,
          isProtected: true,
          isStandard: true,
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
        notes: _notesController.text.trim(),
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
      widget.onShowToast('Login item saved');
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
      child: Stack(
        children: [
          Container(
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
                // Header row
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
                // Icon + type selector + title
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
                        size: 22,
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
                // Scrollable form body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        LoginFormField(
                          label: 'username',
                          controller: _usernameController,
                          icon: TablerIcons.user,
                          iconColor: const Color(0xFF5C7CFA),
                          hintText: 'name@example.com',
                        ),
                        const SizedBox(height: 12),
                        // Password field with show/hide toggle
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  TablerIcons.key,
                                  size: 14,
                                  color: Color(0xFFC08A1A),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'password',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF344054),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F9FB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFD0D8E2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _passwordController,
                                      maxLines: 1,
                                      obscureText: _obscurePassword,
                                      obscuringCharacter: '•',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF111827),
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'Enter password',
                                        hintStyle: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF98A2B3),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        border: InputBorder.none,
                                        isCollapsed: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        _obscurePassword
                                            ? TablerIcons.eye
                                            : TablerIcons.eye_off,
                                        size: 16,
                                        color: const Color(0xFF6B7280),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LoginFormField(
                          label: 'website',
                          controller: _websiteControllers.first,
                          icon: TablerIcons.world_www,
                          iconColor: const Color(0xFF635BDB),
                          hintText: 'https://example.com',
                        ),
                        for (
                          var i = 1;
                          i < _websiteControllers.length;
                          i++
                        ) ...[
                          const SizedBox(height: 12),
                          LoginFormField(
                            label: 'website',
                            controller: _websiteControllers[i],
                            icon: TablerIcons.world_www,
                            iconColor: const Color(0xFF635BDB),
                            hintText: 'https://example.com',
                            trailing: WebsiteRemoveButton(
                              onTap: () => _removeWebsiteField(i),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            onTap: _addWebsiteField,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                '+ add another website / url',
                                style: itemText(
                                  12,
                                  const Color(0xFF3B6FD3),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        LoginFormField(
                          label: 'notes',
                          controller: _notesController,
                          maxLines: 4,
                          minLines: 4,
                          icon: TablerIcons.notes,
                          iconColor: const Color(0xFFB98A1B),
                          hintText: 'Add any notes about this item here.',
                        ),
                        const SizedBox(height: 12),
                        _TotpEditRow(
                          totpAuthUrl: _totpAuthUrl,
                          onChangeTap: _openTotpEditor,
                          onRemoveTap: () => setState(() {
                            _totpAuthUrl = null;
                            _isDirty = true;
                          }),
                        ),
                        const SizedBox(height: 12),
                        CategoryDropdownField(
                          categories: categories,
                          rootGroupUuid: rootGroupUuid,
                          selectedCategoryUuid: effectiveCategoryUuid,
                          onChanged: (value) =>
                              setState(() => _selectedCategoryUuid = value),
                        ),
                        const SizedBox(height: 12),
                        // + add more toggle
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
                            options: _loginAddMoreOptions,
                            onSelected: _addCustomAttribute,
                          ),
                        ],
                        if (_customAttributes.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          for (
                            var i = 0;
                            i < _customAttributes.length;
                            i++
                          ) ...[
                            CustomAttributeCard(
                              attribute: _customAttributes[i],
                              onRemove: () => _removeCustomAttribute(i),
                            ),
                            if (i != _customAttributes.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
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
        ],
      ),
    );
  }
}

class _TotpEditRow extends StatelessWidget {
  const _TotpEditRow({
    required this.totpAuthUrl,
    required this.onChangeTap,
    required this.onRemoveTap,
  });

  final String? totpAuthUrl;
  final VoidCallback onChangeTap;
  final VoidCallback onRemoveTap;

  @override
  Widget build(BuildContext context) {
    final hasTotp = totpAuthUrl != null && totpAuthUrl!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasTotp ? const Color(0xFFF0F4FF) : const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasTotp ? const Color(0xFFB2CCFF) : const Color(0xFFDDE3EC),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: hasTotp
                  ? const Color(0xFF444CE7)
                  : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Icon(
              TablerIcons.clock,
              size: 13,
              color: hasTotp ? Colors.white : const Color(0xFF8A97AC),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '2FA / TOTP',
                  style: itemText(
                    11,
                    const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasTotp ? 'Configured' : 'Not set',
                  style: itemText(
                    12,
                    hasTotp ? const Color(0xFF3B5BDB) : const Color(0xFF9BA8BE),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (hasTotp) ...<Widget>[
            InkWell(
              onTap: onRemoveTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Remove',
                  style: itemText(
                    11,
                    const Color(0xFFE53E3E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          InkWell(
            onTap: onChangeTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                hasTotp ? 'Change' : 'Add 2FA',
                style: itemText(
                  11,
                  hasTotp ? const Color(0xFF3B5BDB) : const Color(0xFF444CE7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
