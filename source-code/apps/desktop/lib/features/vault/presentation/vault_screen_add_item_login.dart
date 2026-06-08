part of 'vault_screen.dart';

class _AddLoginItemModal extends ConsumerStatefulWidget {
  const _AddLoginItemModal({
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

  /// When set, loads this entry and saves via [KdbxRepository.updateEntry].
  final _MockEntry? editingEntry;

  @override
  ConsumerState<_AddLoginItemModal> createState() => _AddLoginItemModalState();
}

class _AddLoginItemModalState extends ConsumerState<_AddLoginItemModal> {
  final LayerLink _addMoreLink = LayerLink();
  final LayerLink _passwordSuggestionLink = LayerLink();
  final OverlayPortalController _passwordSuggestionOverlayController =
      OverlayPortalController();
  final FocusNode _passwordFocusNode = FocusNode();
  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final List<TextEditingController> _websiteControllers;
  late final TextEditingController _notesController;
  late final TextEditingController _tagController;
  final List<_LoginCustomAttribute> _customAttributes =
      <_LoginCustomAttribute>[];
  final List<_LoginAttachment> _attachments = <_LoginAttachment>[];
  final List<String> _tags = <String>[];
  String? _selectedCategoryUuid;
  String? _totpAuthUrl;
  bool _showAddMoreOptions = false;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _isScanTotpOpen = false;
  bool _showGenerateSuggestion = false;
  bool _showSuggestionOptions = false;
  bool _isSuggestionPanelHovered = false;
  int _suggestionLength = 20;
  bool _suggestionNumbers = true;
  bool _suggestionSymbols = true;
  String _suggestedPassword = '';
  Timer? _clipboardClearTimer;

  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.editingEntry;
    if (edit != null) {
      final entries = ref.read(vaultDatabaseEntriesProvider);
      final entryIdx = entries.indexWhere((e) => e.uuid == edit.uuid);
      final kdbx = entryIdx >= 0 ? entries[entryIdx] : null;

      _titleController = TextEditingController(text: kdbx?.title ?? edit.title);
      _usernameController =
          TextEditingController(text: kdbx?.username ?? edit.username);
      _passwordController = TextEditingController(
        text:
            kdbx?.fieldByKey(AppKdbxFieldKeys.password)?.value ?? edit.password,
      );

      final primaryUrl = kdbx?.url ?? edit.website;
      _websiteControllers = <TextEditingController>[
        TextEditingController(text: primaryUrl),
      ];
      if (kdbx != null) {
        for (var i = 2; i <= 20; i++) {
          final field = kdbx.fieldByKey('URL $i');
          if (field == null) break;
          _websiteControllers.add(TextEditingController(text: field.value));
        }
      }

      _notesController = TextEditingController(text: kdbx?.notes ?? edit.notes);
      _tagController = TextEditingController();
      _tags.addAll(kdbx?.tags ?? edit.tags);
      _attachments.addAll(
        edit.attachments.map(_LoginAttachment.fromMockAttachment),
      );

      if (kdbx != null) {
        const standardAndSystem = <String>{
          AppKdbxFieldKeys.title,
          AppKdbxFieldKeys.userName,
          AppKdbxFieldKeys.password,
          AppKdbxFieldKeys.url,
          AppKdbxFieldKeys.otpAuth,
          'otp',
        };
        for (final field in kdbx.fields) {
          final key = field.key;
          if (standardAndSystem.contains(key)) continue;
          if (AppKdbxFieldKeys.isAttachmentMetaKey(key)) continue;
          if (RegExp(r'^URL \d+$').hasMatch(key)) continue;
          if (key.toLowerCase().contains('kpex_passkey_')) continue;
          if (_shouldHideFromDetailFields(label: key, sourceKey: key)) continue;
          _customAttributes.add(
            _LoginCustomAttribute(
              label: key,
              value: field.value,
              isSecret: field.isProtected,
            ),
          );
        }
        final otpField =
            kdbx.fieldByKey(AppKdbxFieldKeys.otpAuth) ?? kdbx.fieldByKey('otp');
        if (otpField != null && otpField.value.isNotEmpty) {
          _totpAuthUrl = otpField.value;
        }
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
    _passwordFocusNode.addListener(_handlePasswordFocusChanged);
    _suggestedPassword = _buildSuggestedPassword();
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    for (final c in _websiteControllers) {
      c.dispose();
    }
    _notesController.dispose();
    _tagController.dispose();
    _passwordFocusNode
      ..removeListener(_handlePasswordFocusChanged)
      ..dispose();
    for (final a in _customAttributes) {
      a.dispose();
    }
    super.dispose();
  }

  void _handlePasswordFocusChanged() {
    if (!mounted) {
      return;
    }
    _syncSuggestionVisibility();
  }

  void _syncSuggestionVisibility() {
    if (!mounted) {
      return;
    }
    final shouldShow = _passwordFocusNode.hasFocus || _isSuggestionPanelHovered;
    if (_showGenerateSuggestion != shouldShow) {
      setState(() {
        _showGenerateSuggestion = shouldShow;
        if (!shouldShow) {
          _showSuggestionOptions = false;
        }
      });
    }
    if (shouldShow) {
      _passwordSuggestionOverlayController.show();
    } else {
      _passwordSuggestionOverlayController.hide();
    }
  }

  void _setSuggestionPanelHovered(bool hovered) {
    _isSuggestionPanelHovered = hovered;
    _syncSuggestionVisibility();
  }

  String _buildSuggestedPassword() {
    return _genPassword(
      length: _suggestionLength,
      letters: true,
      numbers: _suggestionNumbers,
      symbols: _suggestionSymbols,
    );
  }

  void _regenerateSuggestedPassword() {
    setState(() {
      _suggestedPassword = _buildSuggestedPassword();
    });
  }

  Future<void> _applySuggestedPassword() async {
    final generated = _suggestedPassword.trim();
    if (generated.isEmpty) {
      return;
    }
    _passwordController
      ..text = generated
      ..selection = TextSelection.collapsed(offset: generated.length);
    _passwordFocusNode.unfocus();
    _passwordSuggestionOverlayController.hide();
    setState(() {
      _showGenerateSuggestion = false;
      _showSuggestionOptions = false;
    });

    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: generated));
      _clipboardClearTimer?.cancel();
      final seconds = ref.read(vaultClipboardClearSecondsProvider);
      if (seconds != null) {
        _clipboardClearTimer = Timer(Duration(seconds: seconds), () {
          Clipboard.setData(const ClipboardData(text: ''));
        });
      }
    } catch (_) {
      copied = false;
    }
    widget.onShowToast(
      copied
          ? 'Suggested password applied and copied to clipboard'
          : 'Suggested password applied (clipboard unavailable)',
    );
  }

  double _suggestionPanelWidth(BuildContext context) {
    final preview =
        _suggestedPassword.isEmpty ? 'Generating...' : _suggestedPassword;
    final passwordPainter = TextPainter(
      text: TextSpan(
        text: preview,
        style: _text(14, const Color(0xFF49515D), fontWeight: FontWeight.w700),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();

    // Include static left icon area + action buttons + internal paddings.
    final estimated = passwordPainter.width + 170;
    final maxWidth = math.min(620.0, MediaQuery.sizeOf(context).width - 80);
    return estimated.clamp(320.0, maxWidth).toDouble();
  }

  ({String label, Color textColor, Color bgColor, Color borderColor})
      _suggestedPasswordStrength() {
    final password = _suggestedPassword;
    if (password.isEmpty) {
      return (
        label: 'N/A',
        textColor: const Color(0xFF6B7280),
        bgColor: const Color(0xFFF3F4F6),
        borderColor: const Color(0xFFE5E7EB),
      );
    }

    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.length >= 16) score++;
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    if (RegExp(r'(.)\1{2,}').hasMatch(password)) score--;

    if (score <= 3) {
      return (
        label: 'Poor',
        textColor: const Color(0xFFB42318),
        bgColor: const Color(0xFFFEE4E2),
        borderColor: const Color(0xFFFDA29B),
      );
    }
    if (score <= 5) {
      return (
        label: 'Medium',
        textColor: const Color(0xFFB54708),
        bgColor: const Color(0xFFFEF0C7),
        borderColor: const Color(0xFFFEC84B),
      );
    }
    if (score <= 7) {
      return (
        label: 'Strong',
        textColor: const Color(0xFF067647),
        bgColor: const Color(0xFFD1FADF),
        borderColor: const Color(0xFFA6F4C5),
      );
    }
    return (
      label: 'Very Strong',
      textColor: const Color(0xFF155EEF),
      bgColor: const Color(0xFFDDEBFF),
      borderColor: const Color(0xFFB2CCFF),
    );
  }

  Widget _buildSuggestedPasswordRichText() {
    final text = _suggestedPassword;
    if (text.isEmpty) {
      return Text(
        'Generating...',
        style: _text(11, const Color(0xFF98A2B3), fontWeight: FontWeight.w500),
      );
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: text.split('').map((char) {
          final Color color;
          if (RegExp(r'[0-9]').hasMatch(char)) {
            color = const Color(0xFF2B6DD8);
          } else if (RegExp(r'[^A-Za-z0-9]').hasMatch(char)) {
            color = const Color(0xFFE19017);
          } else {
            color = const Color(0xFF49515D);
          }
          return TextSpan(
            text: char,
            style: _text(14, color, fontWeight: FontWeight.w700),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _buildSuggestionToggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool last = false,
  }) {
    return Container(
      height: 38,
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE1E7F0), width: 1),
              ),
            ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: _text(
                12,
                const Color(0xFF3F4B5D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 36,
              height: 20,
              decoration: BoxDecoration(
                color:
                    value ? const Color(0xFF4353E0) : const Color(0xFFD0D8E6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordSuggestionPanel() {
    final strength = _suggestedPasswordStrength();
    return MouseRegion(
      onEnter: (_) => _setSuggestionPanelHovered(true),
      onExit: (_) => _setSuggestionPanelHovered(false),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDDE3EC)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x10172033),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4353E0),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    TablerIcons.key,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: _applySuggestedPassword,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Use Suggested Password',
                                style: _text(
                                  11,
                                  const Color(0xFF1E2530),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: strength.bgColor,
                                  borderRadius: BorderRadius.circular(999),
                                  border:
                                      Border.all(color: strength.borderColor),
                                ),
                                child: Text(
                                  strength.label,
                                  style: _text(
                                    7,
                                    strength.textColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 1),
                          _buildSuggestedPasswordRichText(),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _InlineActionIconButton(
                  icon: TablerIcons.refresh,
                  onTap: _regenerateSuggestedPassword,
                ),
                const SizedBox(width: 5),
                _InlineActionIconButton(
                  icon: _showSuggestionOptions
                      ? TablerIcons.chevron_up
                      : TablerIcons.adjustments_horizontal,
                  onTap: () => setState(
                      () => _showSuggestionOptions = !_showSuggestionOptions),
                ),
              ],
            ),
            if (_showSuggestionOptions) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF3FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDCE4F1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          'Length',
                          style: _text(
                            10,
                            const Color(0xFF5A667A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$_suggestionLength',
                          style: _text(
                            10,
                            const Color(0xFF1E2530),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 9),
                        activeTrackColor: const Color(0xFF4353E0),
                        inactiveTrackColor: const Color(0xFFC9D3E3),
                        thumbColor: const Color(0xFF4353E0),
                        overlayColor: const Color(0x224353E0),
                      ),
                      child: Slider(
                        value: _suggestionLength.toDouble(),
                        min: 8,
                        max: 64,
                        divisions: 56,
                        onChanged: (value) {
                          setState(() {
                            _suggestionLength = value.round();
                            _suggestedPassword = _buildSuggestedPassword();
                          });
                        },
                      ),
                    ),
                    _buildSuggestionToggle(
                      label: 'Numbers',
                      value: _suggestionNumbers,
                      onChanged: (value) {
                        setState(() {
                          _suggestionNumbers = value;
                          _suggestedPassword = _buildSuggestedPassword();
                        });
                      },
                    ),
                    _buildSuggestionToggle(
                      label: 'Symbols',
                      value: _suggestionSymbols,
                      onChanged: (value) {
                        setState(() {
                          _suggestionSymbols = value;
                          _suggestedPassword = _buildSuggestedPassword();
                        });
                      },
                      last: true,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
    if (option == 'One-Time Password') {
      setState(() {
        _showAddMoreOptions = false;
        _isScanTotpOpen = true;
      });
      return;
    }
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

  void _appendAttachmentFields(List<EntryField> fields) {
    for (var i = 0; i < _attachments.length; i++) {
      final attachment = _attachments[i];
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

  Future<List<EntryAttachment>> _resolveEditAttachments(
    KdbxRepository repository,
    String entryUuid,
  ) async {
    if (_attachments.isEmpty) {
      return const <EntryAttachment>[];
    }

    final existingByName = <String, EntryBinaryAttachment>{
      for (final attachment in await repository.getEntryAttachments(entryUuid))
        attachment.name: attachment,
    };

    return _attachments.map((attachment) {
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
    final hasWebsite = _websiteControllers.any((c) {
      final v = c.text.trim();
      return v.isNotEmpty && v != 'https://';
    });
    return title != 'Login' ||
        _usernameController.text.trim().isNotEmpty ||
        _passwordController.text.isNotEmpty ||
        hasWebsite ||
        _notesController.text.trim().isNotEmpty ||
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
      fields.add(EntryField(
        key: key,
        value: value,
        isProtected: attr.shouldProtect,
      ));
    }

    final entries = ref.read(vaultDatabaseEntriesProvider);
    final kdbxIdx = entries.indexWhere((e) => e.uuid == edit.uuid);
    final kdbx = kdbxIdx >= 0 ? entries[kdbxIdx] : null;
    if (kdbx != null) {
      if (_totpAuthUrl != null && _totpAuthUrl!.isNotEmpty) {
        final existingOtpField =
            kdbx.fieldByKey(AppKdbxFieldKeys.otpAuth) ?? kdbx.fieldByKey('otp');
        final otpKey = existingOtpField?.key ?? AppKdbxFieldKeys.otpAuth;
        fields.add(EntryField(
          key: otpKey,
          value: _totpAuthUrl!,
          isProtected: true,
          isStandard: true,
        ));
      }
      for (final field in kdbx.fields) {
        if (field.key.toLowerCase().contains('kpex_passkey_')) {
          fields.add(field);
        }
      }
    }
    _appendAttachmentFields(fields);

    setState(() => _isSaving = true);
    await _delayBeforeSavingOperation();
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final entryAttachments =
          await _resolveEditAttachments(repository, edit.uuid);
      await repository.updateEntry(
        entryUuid: edit.uuid,
        fields: fields,
        notes: _notesController.text.trim(),
        tags: List<String>.unmodifiable(_tags),
        attachments: entryAttachments,
      );
      final database = await saveAndSyncDatabase(
          repository, ref.read(databaseRegistryProvider));
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultEntriesProvider);
      ref.invalidate(vaultSidebarTagsProvider);
      widget.onItemSaved(edit.uuid);
      widget.onShowToast('Item saved');
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
      fields.add(EntryField(
        key: AppKdbxFieldKeys.otpAuth,
        value: _totpAuthUrl!,
        isProtected: true,
        isStandard: true,
      ));
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
    _appendAttachmentFields(fields);

    setState(() => _isSaving = true);
    await _delayBeforeSavingOperation();
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
      final database = await saveAndSyncDatabase(
          repository, ref.read(databaseRegistryProvider));
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultEntriesProvider);
      ref.invalidate(vaultSidebarTagsProvider);
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
                      children: <Widget>[
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: const Color(0xFF9DE3E8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(TablerIcons.key,
                              size: 24, color: Color(0xFF1B5D66)),
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
                              color: const Color(0xFFF7F9FB),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF8BA9D8), width: 2),
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
                            _LoginFormField(
                              label: 'username',
                              controller: _usernameController,
                              icon: TablerIcons.user,
                              iconColor: const Color(0xFF5C7CFA),
                              hintText: 'name@example.com',
                            ),
                            const SizedBox(height: 12),
                            TextFieldTapRegion(
                              child: OverlayPortal(
                                controller:
                                    _passwordSuggestionOverlayController,
                                overlayChildBuilder: (context) {
                                  if (!_showGenerateSuggestion) {
                                    return const SizedBox.shrink();
                                  }
                                  return TextFieldTapRegion(
                                    child: CompositedTransformFollower(
                                      link: _passwordSuggestionLink,
                                      showWhenUnlinked: false,
                                      targetAnchor: Alignment.bottomLeft,
                                      followerAnchor: Alignment.topLeft,
                                      offset: const Offset(0, 6),
                                      child: Align(
                                        alignment: Alignment.topLeft,
                                        child: SizedBox(
                                          width: _suggestionPanelWidth(context),
                                          child:
                                              _buildPasswordSuggestionPanel(),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: CompositedTransformTarget(
                                  link: _passwordSuggestionLink,
                                  child: _LoginFormField(
                                    label: 'password',
                                    controller: _passwordController,
                                    obscureText: true,
                                    icon: TablerIcons.key,
                                    iconColor: const Color(0xFFC08A1A),
                                    hintText: 'Enter password',
                                    focusNode: _passwordFocusNode,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _LoginFormField(
                              label: 'website',
                              controller: _websiteControllers.first,
                              icon: TablerIcons.world_www,
                              iconColor: const Color(0xFF635BDB),
                              hintText: 'https://example.com',
                            ),
                            for (var i = 1;
                                i < _websiteControllers.length;
                                i++) ...<Widget>[
                              const SizedBox(height: 12),
                              _LoginFormField(
                                label: 'website',
                                controller: _websiteControllers[i],
                                icon: TablerIcons.world_www,
                                iconColor: const Color(0xFF635BDB),
                                hintText: 'https://example.com',
                                trailing: _WebsiteRemoveButton(
                                    onTap: () => _removeWebsiteField(i)),
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
                                      horizontal: 10, vertical: 6),
                                  child: Text(
                                    '+ add another website / url',
                                    style: _text(12, const Color(0xFF3B6FD3),
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _LoginFormField(
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
                              onChangeTap: () =>
                                  setState(() => _isScanTotpOpen = true),
                              onRemoveTap: () => setState(() {
                                _totpAuthUrl = null;
                                _isDirty = true;
                              }),
                            ),
                            const SizedBox(height: 12),
                            if (!_isEditing) ...<Widget>[
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
                                    color: const Color(0xFFE8EEF9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Text('+ add more',
                                          style: _text(
                                              12, const Color(0xFF3B6FD3),
                                              fontWeight: FontWeight.w600)),
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
                            const SizedBox(height: 10),
                            _AttachmentSection(
                              attachments: _attachments,
                              onAddPressed: _pickAttachments,
                              onRemove: _removeAttachment,
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('tags',
                                  style: _text(12, const Color(0xFF6D63D6),
                                      fontWeight: FontWeight.w600)),
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
              if (_isScanTotpOpen)
                Positioned.fill(
                  child: _ScanTotpOverlay(
                    onClose: () => setState(() => _isScanTotpOpen = false),
                    onShowToast: widget.onShowToast,
                    onTotpConfirmed: (url) => setState(() {
                      _totpAuthUrl = url;
                      _isScanTotpOpen = false;
                      _isDirty = true;
                    }),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InlineActionIconButton extends StatefulWidget {
  const _InlineActionIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_InlineActionIconButton> createState() =>
      _InlineActionIconButtonState();
}

class _InlineActionIconButtonState extends State<_InlineActionIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFE6ECF6) : const Color(0xFFF1F4F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD5DEE9)),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 13,
            color: const Color(0xFF6A7588),
          ),
        ),
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
              color:
                  hasTotp ? const Color(0xFF444CE7) : const Color(0xFFE2E8F0),
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
                  style: _text(11, const Color(0xFF6B7280),
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  hasTotp ? 'Configured' : 'Not set',
                  style: _text(
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
                  style: _text(11, const Color(0xFFE53E3E),
                      fontWeight: FontWeight.w600),
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
                style: _text(
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
