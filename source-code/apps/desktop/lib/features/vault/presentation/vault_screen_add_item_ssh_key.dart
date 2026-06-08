part of 'vault_screen.dart';

enum _SshPrivateKeyAction {
  generateNewKey,
  importKeyFile,
  pasteFromClipboard,
  copyPrivateKey,
  downloadPrivateKey,
}

enum _SshKeyGenerationType {
  ed25519,
  rsa,
}

class _SshKeyGenerationConfig {
  const _SshKeyGenerationConfig({
    required this.type,
    required this.rsaBits,
    required this.passphrase,
  });

  final _SshKeyGenerationType type;
  final int rsaBits;
  final String passphrase;
}

class _SshGeneratedKeyMaterial {
  const _SshGeneratedKeyMaterial({
    required this.privateKey,
    required this.publicKey,
    required this.preview,
    required this.passphrase,
  });

  final String privateKey;
  final String? publicKey;
  final _SshPrivateKeyPreview? preview;
  final String passphrase;
}

class _SshPrivateKeyPreview {
  const _SshPrivateKeyPreview({
    required this.title,
    required this.fingerprint,
  });

  final String title;
  final String fingerprint;
}

class _AddSshKeyItemModal extends ConsumerStatefulWidget {
  const _AddSshKeyItemModal({
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
  ConsumerState<_AddSshKeyItemModal> createState() =>
      _AddSshKeyItemModalState();
}

class _AddSshKeyItemModalState extends ConsumerState<_AddSshKeyItemModal> {
  final LayerLink _addMoreLink = LayerLink();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagController;
  final List<_LoginCustomAttribute> _customAttributes =
      <_LoginCustomAttribute>[];
  final List<_LoginAttachment> _attachments = <_LoginAttachment>[];
  final List<String> _tags = <String>[];
  String? _selectedCategoryUuid;
  String? _privateKeyName;
  String? _privateKeyValue;
  String? _privateKeyPath;
  _SshPrivateKeyPreview? _privateKeyPreview;
  String _privateKeyStorageKey = 'Private Key';
  bool _showAddMoreOptions = false;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _isImporting = false;
  bool _isDragOver = false;
  Timer? _clipboardClearTimer;

  bool get _isEditing => widget.editingEntry != null;

  bool get _hasPrivateKeyMaterial =>
      (_privateKeyValue?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    final edit = widget.editingEntry;
    if (edit != null) {
      final entries = ref.read(vaultDatabaseEntriesProvider);
      final idx = entries.indexWhere((e) => e.uuid == edit.uuid);
      final kdbx = idx >= 0 ? entries[idx] : null;

      final pkField = sshPrivateKeyFieldFromKdbx(kdbx);
      _privateKeyStorageKey = pkField?.key ?? 'Private Key';

      _titleController = TextEditingController(text: kdbx?.title ?? edit.title);
      _notesController = TextEditingController(text: kdbx?.notes ?? edit.notes);
      _tagController = TextEditingController();
      _tags.addAll(kdbx?.tags ?? edit.tags);
      _attachments.addAll(
        edit.attachments.map(_LoginAttachment.fromMockAttachment),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadExistingBinaryAttachments());
      });

      if (pkField != null && pkField.value.trim().isNotEmpty) {
        _privateKeyValue = pkField.value;
        _privateKeyName =
            kdbx?.fieldByKey('Key File Name')?.value ?? 'Private key';
      }

      if (kdbx != null) {
        for (final field in kdbx.fields) {
          final key = field.key;
          if (key == AppKdbxFieldKeys.title) continue;
          if (AppKdbxFieldKeys.isAttachmentMetaKey(key)) continue;
          if (key.toLowerCase().contains('kpex_passkey_')) continue;
          // Import UI only; not user-editable metadata (avoids "Pasted Private Key" rows).
          if (key == 'Key File Name') continue;
          final keyNorm = key.toLowerCase();
          if (keyNorm.contains('private key') ||
              keyNorm.contains('openssh') ||
              keyNorm.contains('pem')) {
            continue;
          }
          _customAttributes.add(
            _LoginCustomAttribute(
              label: key,
              value: field.value,
              isSecret: field.isProtected,
            ),
          );
        }
      }

      final storedFp =
          _customAttributeValueForLabel('fingerprint')?.trim() ?? '';
      final storedKeyType =
          _customAttributeValueForLabel('key type')?.trim() ?? '';
      if (storedFp.isNotEmpty || storedKeyType.isNotEmpty) {
        _privateKeyPreview = _SshPrivateKeyPreview(
          title: storedKeyType.isNotEmpty ? storedKeyType : 'SSH private key',
          fingerprint: storedFp,
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final pk = _privateKeyValue;
        if (pk == null || pk.trim().isEmpty) return;
        final passphrase =
            _customAttributeValueForLabel('passphrase')?.trim() ?? '';
        final preview = await _buildPrivateKeyPreview(
          privateKey: pk,
          sourcePath: null,
          passphrase: passphrase,
        );
        if (!mounted) return;
        setState(() {
          if (preview != null) _privateKeyPreview = preview;
        });
      });
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
    _clipboardClearTimer?.cancel();
    _titleController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    for (final attribute in _customAttributes) {
      attribute.dispose();
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

  void _copySshPrivateKey() {
    final v = _privateKeyValue?.trim() ?? '';
    if (v.isEmpty) {
      widget.onShowToast('No private key to copy');
      return;
    }
    Clipboard.setData(ClipboardData(text: v));
    widget.onShowToast('Private key copied to clipboard');
    _clipboardClearTimer?.cancel();
    final seconds = ref.read(vaultClipboardClearSecondsProvider);
    if (seconds != null) {
      _clipboardClearTimer = Timer(Duration(seconds: seconds), () {
        Clipboard.setData(const ClipboardData(text: ''));
      });
    }
  }

  String _suggestedPrivateKeyFileName() {
    final name = (_privateKeyName ?? '').trim();
    if (name.isNotEmpty &&
        !name.toLowerCase().contains('pasted') &&
        name.contains('.')) {
      return name;
    }
    final pk = _privateKeyValue ?? '';
    if (pk.contains('BEGIN OPENSSH PRIVATE KEY')) {
      return 'id_ed25519';
    }
    if (pk.contains('BEGIN RSA PRIVATE KEY') ||
        pk.contains('BEGIN RSA PRIVATE')) {
      return 'id_rsa';
    }
    if (pk.contains('BEGIN EC PRIVATE KEY')) {
      return 'id_ecdsa';
    }
    if (pk.contains('BEGIN ENCRYPTED PRIVATE KEY') ||
        pk.contains('BEGIN PRIVATE KEY')) {
      return 'private_key.pem';
    }
    return 'ssh_private_key';
  }

  Future<void> _downloadSshPrivateKey() async {
    final v = _privateKeyValue?.trim() ?? '';
    if (v.isEmpty) {
      widget.onShowToast('No private key to save');
      return;
    }
    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save private key',
        fileName: _suggestedPrivateKeyFileName(),
        lockParentWindow: true,
        type: FileType.any,
      );
      if (outputPath == null || outputPath.trim().isEmpty) {
        return;
      }
      await File(outputPath).writeAsString(v, flush: true);
      if (!mounted) return;
      widget.onShowToast('Private key saved');
    } on MissingPluginException {
      widget.onShowToast('Save dialog is unavailable here');
    } catch (error) {
      if (!mounted) return;
      widget.onShowToast('Unable to save: $error');
    }
  }

  Future<void> _pickPrivateKey() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose private key',
        allowMultiple: false,
        lockParentWindow: true,
        withData: false,
        type: FileType.any,
      );
      final files = result?.files;
      if (files == null || files.isEmpty) {
        return;
      }
      final file = files.first;
      if (file.path == null) {
        return;
      }
      await _importPrivateKey(file.path!);
    } on MissingPluginException {
      widget.onShowToast('File picker is unavailable here');
    } catch (error) {
      widget.onShowToast('Unable to add private key: $error');
    }
  }

  Future<void> _importPrivateKey(String path) async {
    setState(() {
      _isImporting = true;
      _isDragOver = false;
    });

    try {
      final file = File(path);
      final contents = await file.readAsString();
      final fileName = path.split(Platform.pathSeparator).last;
      await _importPrivateKeyContent(
        privateKey: contents,
        displayName: fileName,
        sourcePath: path,
      );
    } catch (error) {
      widget.onShowToast('Unable to read private key: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _pastePrivateKeyFromClipboard() async {
    setState(() {
      _isImporting = true;
      _isDragOver = false;
    });

    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final clipboardText = clipboardData?.text ?? '';
      if (clipboardText.trim().isEmpty) {
        widget.onShowToast('Clipboard is empty');
        return;
      }
      if (!_looksLikePrivateKey(clipboardText)) {
        widget.onShowToast('Clipboard does not contain a private key');
        return;
      }
      await _importPrivateKeyContent(
        privateKey: clipboardText,
        displayName: 'Pasted Private Key',
        sourcePath: null,
        successToast: 'Private key pasted from clipboard',
      );
    } catch (error) {
      widget.onShowToast('Unable to paste private key: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _generatePrivateKey() async {
    final config = await _promptForPrivateKeyGenerationConfig();
    if (!mounted || config == null) {
      return;
    }

    setState(() {
      _isImporting = true;
      _isDragOver = false;
    });

    try {
      final material = await _generatePrivateKeyMaterial(config);
      if (!mounted) {
        return;
      }
      final displayName = config.type == _SshKeyGenerationType.ed25519
          ? 'Generated Ed25519 Key'
          : 'Generated RSA Key';
      setState(() {
        _isDirty = true;
        _privateKeyName = displayName;
        _privateKeyValue = material.privateKey;
        _privateKeyPath = null;
        _privateKeyPreview = material.preview;
      });
      _syncDerivedSshMetadataFields(
        preview: material.preview,
        publicKey: material.publicKey,
        passphrase: material.passphrase,
      );
      widget.onShowToast('Private key generated');
    } on ProcessException {
      widget.onShowToast('ssh-keygen is unavailable on this machine');
    } catch (error) {
      widget.onShowToast('Unable to generate private key: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<_SshGeneratedKeyMaterial> _generatePrivateKeyMaterial(
    _SshKeyGenerationConfig config,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('lumenpass_sshkey_');
    final keyPath = '${tempDir.path}${Platform.pathSeparator}id_lumenpass';
    final pubKeyPath = '$keyPath.pub';
    try {
      final args = <String>[
        '-t',
        config.type == _SshKeyGenerationType.ed25519 ? 'ed25519' : 'rsa',
        '-N',
        config.passphrase,
        '-f',
        keyPath,
        '-q',
      ];
      if (config.type == _SshKeyGenerationType.rsa) {
        args.insertAll(2, <String>['-b', config.rsaBits.toString()]);
      }
      final result = await Process.run(
        'ssh-keygen',
        args,
        runInShell: false,
      );
      if (result.exitCode != 0) {
        final stderrText = (result.stderr ?? '').toString().trim();
        throw Exception(
          stderrText.isEmpty ? 'Failed to generate key pair' : stderrText,
        );
      }
      final privateKey = (await File(keyPath).readAsString()).trim();
      String? publicKey;
      try {
        final raw = (await File(pubKeyPath).readAsString()).trim();
        if (raw.isNotEmpty) publicKey = raw;
      } catch (_) {}
      _SshPrivateKeyPreview? preview;
      try {
        final fingerprintResult = await Process.run(
          'ssh-keygen',
          <String>['-lf', pubKeyPath],
          runInShell: false,
        );
        if (fingerprintResult.exitCode == 0) {
          preview = _parsePrivateKeyPreview(
            fingerprintResult.stdout.toString(),
          );
        }
      } catch (_) {}
      if (preview == null) {
        try {
          final fingerprintResult = await Process.run(
            'ssh-keygen',
            <String>['-lf', keyPath],
            runInShell: false,
          );
          if (fingerprintResult.exitCode == 0) {
            preview = _parsePrivateKeyPreview(
              fingerprintResult.stdout.toString(),
            );
          }
        } catch (_) {}
      }
      return _SshGeneratedKeyMaterial(
        privateKey: privateKey,
        publicKey: publicKey,
        preview: preview,
        passphrase: config.passphrase,
      );
    } finally {
      try {
        await File(keyPath).delete();
      } catch (_) {}
      try {
        await File(pubKeyPath).delete();
      } catch (_) {}
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<_SshKeyGenerationConfig?>
      _promptForPrivateKeyGenerationConfig() async {
    var selectedType = _SshKeyGenerationType.ed25519;
    var rsaBits = 4096.0;
    var isPassphraseVisible = false;
    final passphraseController = TextEditingController();

    try {
      return await showDialog<_SshKeyGenerationConfig>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final isRsa = selectedType == _SshKeyGenerationType.rsa;
              final keyTypeLabel = isRsa ? 'RSA' : 'Ed25519';
              final helperText = isRsa
                  ? 'RSA keys are slower than Ed25519 keys, but work with older SSH servers.'
                  : 'Ed25519 is the fastest and most modern SSH key type.';
              return Theme(
                data: Theme.of(dialogContext).copyWith(
                  brightness: Brightness.light,
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF2F6BFF),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Color(0xFF1F2937),
                  ),
                  canvasColor: Colors.white,
                  splashColor: const Color(0x1A2F6BFF),
                  highlightColor: const Color(0x1A2F6BFF),
                  hoverColor: const Color(0x0F2F6BFF),
                ),
                child: Dialog(
                  backgroundColor: Colors.white,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              _LoginFooterButton(
                                label: 'Cancel',
                                backgroundColor: const Color(0xFFEBEEF3),
                                textColor: const Color(0xFF3E4B60),
                                borderColor: const Color(0xFFC0C9D4),
                                onTap: () => Navigator.of(dialogContext).pop(),
                              ),
                              const Spacer(),
                              _LoginFooterButton(
                                label: 'Generate',
                                backgroundColor: _kPrimaryButtonColor,
                                textColor: Colors.white,
                                onTap: () {
                                  Navigator.of(dialogContext).pop(
                                    _SshKeyGenerationConfig(
                                      type: selectedType,
                                      rsaBits: rsaBits.round(),
                                      passphrase: passphraseController.text,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Key Type',
                                  style: _text(
                                    13,
                                    const Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Container(
                                height: 40,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFF98A2B3)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<_SshKeyGenerationType>(
                                    value: selectedType,
                                    dropdownColor: Colors.white,
                                    menuMaxHeight: 220,
                                    borderRadius: BorderRadius.circular(12),
                                    style: _text(
                                      13,
                                      const Color(0xFF2E3138),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    icon: const Icon(
                                      TablerIcons.chevron_down,
                                      size: 16,
                                      color: Color(0xFF6B7280),
                                    ),
                                    items: <DropdownMenuItem<
                                        _SshKeyGenerationType>>[
                                      DropdownMenuItem<_SshKeyGenerationType>(
                                        value: _SshKeyGenerationType.ed25519,
                                        child: Text(
                                          'Ed25519',
                                          style: _text(
                                            13,
                                            const Color(0xFF2E3138),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      DropdownMenuItem<_SshKeyGenerationType>(
                                        value: _SshKeyGenerationType.rsa,
                                        child: Text(
                                          'RSA',
                                          style: _text(
                                            13,
                                            const Color(0xFF2E3138),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedType = value;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isRsa) ...<Widget>[
                            const SizedBox(height: 14),
                            Row(
                              children: <Widget>[
                                Text(
                                  'Bit Length',
                                  style: _text(
                                    13,
                                    const Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: const Color(0xFF2F6BFF),
                                      inactiveTrackColor:
                                          const Color(0xFFDDE3EC),
                                      thumbColor: Colors.white,
                                      overlayColor: const Color(0x1F2F6BFF),
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 13,
                                      ),
                                    ),
                                    child: Slider(
                                      value: rsaBits,
                                      min: 2048,
                                      max: 8192,
                                      divisions: 6,
                                      label: rsaBits.round().toString(),
                                      onChanged: (value) {
                                        setDialogState(() {
                                          rsaBits = value;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 78,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFD1D5DB)),
                                  ),
                                  child: Text(
                                    rsaBits.round().toString(),
                                    style: _text(
                                      13,
                                      const Color(0xFF2E3138),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            'Passphrase',
                            style: _text(
                              13,
                              const Color(0xFF6B7280),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFF98A2B3)),
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: TextField(
                                    controller: passphraseController,
                                    obscureText: !isPassphraseVisible,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: _text(
                                      13,
                                      const Color(0xFF2E3138),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: InputDecoration(
                                      filled: false,
                                      hintText: 'Leave blank for no passphrase',
                                      hintStyle: _text(
                                        13,
                                        const Color(0xFF98A2B3),
                                        fontWeight: FontWeight.w400,
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
                                  onTap: () => setDialogState(() {
                                    isPassphraseVisible = !isPassphraseVisible;
                                  }),
                                  borderRadius: BorderRadius.circular(999),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      isPassphraseVisible
                                          ? TablerIcons.eye_off
                                          : TablerIcons.eye,
                                      size: 16,
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            height: 3,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            helperText,
                            style: _text(
                              13,
                              const Color(0xFF374151),
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Selected: $keyTypeLabel',
                            style: _text(
                              11,
                              const Color(0xFF6B7280),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      passphraseController.dispose();
    }
  }

  Future<void> _importPrivateKeyContent({
    required String privateKey,
    required String displayName,
    required String? sourcePath,
    String successToast = 'Private key imported',
  }) async {
    final trimmed = privateKey.trim();
    if (trimmed.isEmpty) {
      widget.onShowToast('That key file is empty');
      return;
    }

    final keyRequiresPassphrase = _sshKeyRequiresPassphrase(trimmed);
    var toastMessage = successToast;
    if (keyRequiresPassphrase) {
      final existingPassphrase =
          _customAttributeValueForLabel('passphrase')?.trim() ?? '';
      var validatedPassphrase = existingPassphrase;

      if (validatedPassphrase.isNotEmpty) {
        final validationError = await _validatePrivateKeyPassphraseForKey(
          privateKey: trimmed,
          sourcePath: sourcePath,
          passphrase: validatedPassphrase,
        );
        if (validationError != null) {
          validatedPassphrase = '';
        }
      }

      if (validatedPassphrase.isEmpty) {
        var promptValue = existingPassphrase;
        while (validatedPassphrase.isEmpty) {
          final passphrase = await _promptForPrivateKeyPassphrase(
            fileName: displayName,
            initialPassphrase: promptValue,
          );
          if (!mounted) {
            return;
          }
          if (passphrase == null || passphrase.trim().isEmpty) {
            widget.onShowToast(
              'Encrypted key import canceled. A valid passphrase is required.',
            );
            return;
          }

          final candidate = passphrase.trim();
          final validationError = await _validatePrivateKeyPassphraseForKey(
            privateKey: trimmed,
            sourcePath: sourcePath,
            passphrase: candidate,
          );
          if (!mounted) {
            return;
          }
          if (validationError == null) {
            validatedPassphrase = candidate;
            _upsertCustomAttribute(
              label: 'passphrase',
              value: validatedPassphrase,
            );
            toastMessage = 'Private key imported and passphrase added';
            break;
          }

          promptValue = candidate;
          widget.onShowToast(validationError);
        }
      } else if (validatedPassphrase.isNotEmpty) {
        toastMessage = 'Encrypted private key imported';
      }
    }

    final effectivePassphrase = keyRequiresPassphrase
        ? (_customAttributeValueForLabel('passphrase')?.trim() ?? '')
        : '';

    if (!mounted) {
      return;
    }
    final preview = await _buildPrivateKeyPreview(
      privateKey: trimmed,
      sourcePath: sourcePath,
      passphrase: effectivePassphrase,
    );
    final publicKey = await _derivePublicKeyFromPrivateKeyContent(
      privateKey: trimmed,
      sourcePath: sourcePath,
      passphrase: effectivePassphrase.isEmpty ? null : effectivePassphrase,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isDirty = true;
      _privateKeyName = displayName;
      _privateKeyValue = trimmed;
      _privateKeyPath = sourcePath;
      _privateKeyPreview = preview;
    });
    _syncDerivedSshMetadataFields(
      preview: preview,
      publicKey: publicKey,
      passphrase: effectivePassphrase,
    );

    widget.onShowToast(toastMessage);
  }

  void _clearPrivateKey() {
    setState(() {
      _isDirty = true;
      _privateKeyName = null;
      _privateKeyValue = null;
      _privateKeyPath = null;
      _privateKeyPreview = null;
    });
    _syncDerivedSshMetadataFields(
      preview: null,
      publicKey: null,
      passphrase: '',
    );
  }

  void _addCustomAttribute(String option) {
    final normalizedLabel = option.trim().toLowerCase();
    if (normalizedLabel == 'passphrase') {
      final existingPassphrase =
          _customAttributeValueForLabel(normalizedLabel)?.trim() ?? '';
      if (existingPassphrase.isNotEmpty) {
        widget.onShowToast('Passphrase field already added');
        setState(() {
          _showAddMoreOptions = false;
        });
        return;
      }
    }

    setState(() {
      _isDirty = true;
      _customAttributes.add(
        _LoginCustomAttribute(
          label: normalizedLabel,
          value: '',
          isSecret: AppKdbxFieldKeys.isProtectedKey(normalizedLabel),
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
      if (files == null || files.isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
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
    if (normalized.isEmpty) {
      return;
    }
    if (_tags.any((tag) => tag.toLowerCase() == normalized.toLowerCase())) {
      return;
    }
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

  void _removeCustomAttributeByLabel(String label) {
    final normalizedLabel = label.trim().toLowerCase();
    final index = _customAttributes.indexWhere(
      (attribute) =>
          attribute.labelController.text.trim().toLowerCase() ==
          normalizedLabel,
    );
    if (index == -1) {
      return;
    }

    final attribute = _customAttributes.removeAt(index);
    attribute.dispose();
    if (mounted) {
      setState(() {});
    }
  }

  String? _customAttributeValueForLabel(String label) {
    final normalizedLabel = label.trim().toLowerCase();
    for (final attribute in _customAttributes) {
      if (attribute.labelController.text.trim().toLowerCase() ==
          normalizedLabel) {
        return attribute.valueController.text;
      }
    }
    return null;
  }

  void _upsertCustomAttribute({
    required String label,
    required String value,
  }) {
    final normalizedLabel = label.trim().toLowerCase();
    for (final attribute in _customAttributes) {
      if (attribute.labelController.text.trim().toLowerCase() ==
          normalizedLabel) {
        setState(() {
          attribute.labelController.text = normalizedLabel;
          attribute.valueController.text = value;
        });
        return;
      }
    }

    setState(() {
      _customAttributes.add(
        _LoginCustomAttribute(
          label: normalizedLabel,
          value: value,
          isSecret: AppKdbxFieldKeys.isProtectedKey(normalizedLabel),
        ),
      );
    });
  }

  Future<String?> _promptForPrivateKeyPassphrase({
    required String fileName,
    String initialPassphrase = '',
  }) async {
    final controller = TextEditingController(text: initialPassphrase);
    var isVisible = false;

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Theme(
                data: Theme.of(dialogContext).copyWith(
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
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textSelectionTheme: const TextSelectionThemeData(
                    cursorColor: Color(0xFF2F6BFF),
                    selectionColor: Color(0x1F2F6BFF),
                    selectionHandleColor: Color(0xFF2F6BFF),
                  ),
                ),
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x140F172A),
                          blurRadius: 30,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Enter SSH Key Passphrase',
                          style: _text(
                            18,
                            const Color(0xFF202939),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '$fileName is encrypted. Enter a valid passphrase to add this key.',
                          style: _text(
                            14,
                            const Color(0xFF4B5565),
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD6E1F5)),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  autofocus: true,
                                  obscureText: !isVisible,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textAlignVertical: TextAlignVertical.center,
                                  onSubmitted: (_) {
                                    Navigator.of(dialogContext)
                                        .pop(controller.text);
                                  },
                                  style: _text(
                                    14,
                                    const Color(0xFF111827),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    hintText: 'Passphrase',
                                    hintStyle: _text(
                                      14,
                                      const Color(0xFF98A2B3),
                                      fontWeight: FontWeight.w500,
                                    ),
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
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () => setDialogState(() {
                                  isVisible = !isVisible;
                                }),
                                borderRadius: BorderRadius.circular(999),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    isVisible
                                        ? TablerIcons.eye_off
                                        : TablerIcons.eye,
                                    size: 18,
                                    color: const Color(0xFF0B63E5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            _LoginFooterButton(
                              label: 'Cancel Add',
                              backgroundColor: const Color(0xFFF4F6FA),
                              textColor: const Color(0xFF374151),
                              onTap: () => Navigator.of(dialogContext).pop(),
                            ),
                            const SizedBox(width: 10),
                            _LoginFooterButton(
                              label: 'Save Passphrase',
                              backgroundColor: _kPrimaryButtonColor,
                              textColor: Colors.white,
                              onTap: () {
                                Navigator.of(dialogContext)
                                    .pop(controller.text);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _validatePrivateKeyPassphrase({
    required String filePath,
    required String passphrase,
  }) async {
    try {
      final process = await Process.start(
        'ssh-keygen',
        <String>['-y', '-f', filePath],
        runInShell: false,
      );
      process.stdin.writeln(passphrase);
      await process.stdin.close();

      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      final stdoutText = await stdoutFuture;
      final stderrText = await stderrFuture;

      if (exitCode == 0 && stdoutText.trim().isNotEmpty) {
        return null;
      }

      final normalizedError = stderrText.toLowerCase();
      if (normalizedError.contains('incorrect passphrase') ||
          normalizedError.contains('bad passphrase') ||
          normalizedError.contains('incorrect password')) {
        return 'That passphrase does not unlock this private key.';
      }

      return 'Unable to verify the passphrase for this private key.';
    } on ProcessException {
      return 'ssh-keygen is unavailable, so this passphrase cannot be verified here.';
    } catch (_) {
      return 'Unable to verify the passphrase for this private key.';
    }
  }

  Future<String?> _validatePrivateKeyPassphraseForKey({
    required String privateKey,
    required String? sourcePath,
    required String passphrase,
  }) async {
    final path = sourcePath?.trim() ?? '';
    if (path.isNotEmpty) {
      return _validatePrivateKeyPassphrase(
        filePath: path,
        passphrase: passphrase,
      );
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'lumenpass_sshkey_validate_',
    );
    final tempKeyPath = '${tempDir.path}${Platform.pathSeparator}id_temp';
    try {
      await File(tempKeyPath).writeAsString(privateKey);
      return await _validatePrivateKeyPassphrase(
        filePath: tempKeyPath,
        passphrase: passphrase,
      );
    } finally {
      try {
        await File(tempKeyPath).delete();
      } catch (_) {}
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  bool _looksLikePrivateKey(String text) {
    return RegExp(
      r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----',
      caseSensitive: false,
    ).hasMatch(text);
  }

  Future<_SshPrivateKeyPreview?> _buildPrivateKeyPreview({
    required String privateKey,
    required String? sourcePath,
    String? passphrase,
  }) async {
    final existingPath = sourcePath?.trim() ?? '';
    if (existingPath.isNotEmpty) {
      final preview = await _runSshFingerprintPreview(
        privateKeyPath: existingPath,
        passphrase: passphrase,
      );
      if (preview != null) {
        return preview;
      }
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'lumenpass_sshkey_preview_',
    );
    final tempKeyPath = '${tempDir.path}${Platform.pathSeparator}id_temp';
    try {
      await File(tempKeyPath).writeAsString(privateKey);
      return await _runSshFingerprintPreview(
        privateKeyPath: tempKeyPath,
        passphrase: passphrase,
      );
    } finally {
      try {
        await File(tempKeyPath).delete();
      } catch (_) {}
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<_SshPrivateKeyPreview?> _runSshFingerprintPreview({
    required String privateKeyPath,
    String? passphrase,
  }) async {
    try {
      final direct = await Process.run(
        'ssh-keygen',
        <String>['-lf', privateKeyPath],
        runInShell: false,
      );
      if (direct.exitCode == 0) {
        final parsed = _parsePrivateKeyPreview(direct.stdout.toString());
        if (parsed != null) {
          return parsed;
        }
      }

      final publicKey = await _derivePublicKeyFromPrivateKey(
        privateKeyPath: privateKeyPath,
        passphrase: passphrase,
      );
      if (publicKey == null || publicKey.trim().isEmpty) {
        return null;
      }

      final tempDir = await Directory.systemTemp.createTemp(
        'lumenpass_sshpub_preview_',
      );
      final tempPubPath = '${tempDir.path}${Platform.pathSeparator}id_temp.pub';
      try {
        await File(tempPubPath).writeAsString(publicKey);
        final fromPub = await Process.run(
          'ssh-keygen',
          <String>['-lf', tempPubPath],
          runInShell: false,
        );
        if (fromPub.exitCode != 0) {
          return null;
        }
        return _parsePrivateKeyPreview(fromPub.stdout.toString());
      } finally {
        try {
          await File(tempPubPath).delete();
        } catch (_) {}
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {
      return null;
    }
  }

  Future<String?> _derivePublicKeyFromPrivateKey({
    required String privateKeyPath,
    String? passphrase,
  }) async {
    try {
      final process = await Process.start(
        'ssh-keygen',
        <String>['-y', '-f', privateKeyPath],
        runInShell: false,
      );
      process.stdin.writeln(passphrase ?? '');
      await process.stdin.close();

      final stdoutText = await process.stdout.transform(utf8.decoder).join();
      await process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        return null;
      }
      return stdoutText.trim().isEmpty ? null : stdoutText.trim();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _derivePublicKeyFromPrivateKeyContent({
    required String privateKey,
    required String? sourcePath,
    String? passphrase,
  }) async {
    final existingPath = sourcePath?.trim() ?? '';
    if (existingPath.isNotEmpty) {
      return _derivePublicKeyFromPrivateKey(
        privateKeyPath: existingPath,
        passphrase: passphrase,
      );
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'lumenpass_sshkey_pub_',
    );
    final tempKeyPath = '${tempDir.path}${Platform.pathSeparator}id_temp';
    try {
      await File(tempKeyPath).writeAsString(privateKey);
      return await _derivePublicKeyFromPrivateKey(
        privateKeyPath: tempKeyPath,
        passphrase: passphrase,
      );
    } finally {
      try {
        await File(tempKeyPath).delete();
      } catch (_) {}
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  void _syncDerivedSshMetadataFields({
    required _SshPrivateKeyPreview? preview,
    required String? publicKey,
    required String passphrase,
  }) {
    _upsertOrRemoveCustomAttribute(
      label: 'public key',
      value: publicKey,
    );
    _upsertOrRemoveCustomAttribute(
      label: 'fingerprint',
      value: preview?.fingerprint,
    );
    _upsertOrRemoveCustomAttribute(
      label: 'key type',
      value: preview?.title,
    );
    _upsertOrRemoveCustomAttribute(
      label: 'passphrase',
      value: passphrase,
    );
  }

  void _upsertOrRemoveCustomAttribute({
    required String label,
    required String? value,
  }) {
    final normalizedValue = value?.trim() ?? '';
    if (normalizedValue.isEmpty) {
      _removeCustomAttributeByLabel(label);
      return;
    }
    _upsertCustomAttribute(label: label, value: normalizedValue);
  }

  _SshPrivateKeyPreview? _parsePrivateKeyPreview(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return null;
    }

    final first = lines.first;
    final bitsMatch = RegExp(r'^(\d+)').firstMatch(first);
    final fingerprintMatch = RegExp(r'^\d+\s+(\S+)').firstMatch(first);
    final typeMatch = RegExp(r'\(([^)]+)\)\s*$').firstMatch(first);
    if (fingerprintMatch == null || typeMatch == null) {
      return null;
    }

    final bits = bitsMatch?.group(1) ?? '';
    final rawType = (typeMatch.group(1) ?? '').toUpperCase();
    String title;
    if (rawType == 'RSA') {
      title = bits.isNotEmpty ? 'RSA, $bits-bit' : 'RSA';
    } else if (rawType == 'ED25519') {
      title = 'Ed25519';
    } else if (rawType.isNotEmpty) {
      title = bits.isNotEmpty ? '$rawType, $bits-bit' : rawType;
    } else {
      title = 'SSH Key';
    }

    return _SshPrivateKeyPreview(
      title: title,
      fingerprint: fingerprintMatch.group(1) ?? '',
    );
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
    final hasCustomFields = _customAttributes.any(
      (attribute) =>
          attribute.labelController.text.trim().isNotEmpty &&
          attribute.valueController.text.trim().isNotEmpty,
    );

    return title != 'SSH Key' ||
        (_privateKeyValue?.isNotEmpty ?? false) ||
        _notesController.text.trim().isNotEmpty ||
        hasCustomFields ||
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

    final privateKeyValue = _privateKeyValue?.trim() ?? '';
    if (privateKeyValue.isNotEmpty &&
        _sshKeyRequiresPassphrase(privateKeyValue)) {
      final passphrase =
          _customAttributeValueForLabel('passphrase')?.trim() ?? '';
      if (passphrase.isEmpty) {
        widget.onShowToast(
          'Encrypted private key requires a valid passphrase before saving',
        );
        return;
      }
      final validationError = await _validatePrivateKeyPassphraseForKey(
        privateKey: privateKeyValue,
        sourcePath: _privateKeyPath,
        passphrase: passphrase,
      );
      if (validationError != null) {
        widget.onShowToast(validationError);
        return;
      }
    }

    final entries = ref.read(vaultDatabaseEntriesProvider);
    final idx = entries.indexWhere((e) => e.uuid == edit.uuid);
    final kdbx = idx >= 0 ? entries[idx] : null;

    final newCustomAttrKeys = _customAttributes
        .map((a) => a.labelController.text.trim())
        .where((k) => k.isNotEmpty)
        .toSet();

    final fields = <EntryField>[
      EntryField(key: AppKdbxFieldKeys.title, value: title, isStandard: true),
    ];
    if (kdbx != null) {
      for (final field in kdbx.fields) {
        if (field.key == AppKdbxFieldKeys.title) continue;
        if (AppKdbxFieldKeys.isAttachmentMetaKey(field.key)) continue;
        if (isSshPrivateKeyStorageKey(field.key)) continue;
        if (field.key == 'Key File Name') continue;
        if (newCustomAttrKeys.contains(field.key)) continue;
        fields.add(field);
      }
    }
    for (final attr in _customAttributes) {
      final key = attr.labelController.text.trim();
      if (key.isEmpty) continue;
      if (isSshPrivateKeyStorageKey(key)) continue;
      fields.add(EntryField(
        key: key,
        value: attr.valueController.text,
        isProtected: attr.shouldProtect,
      ));
    }
    fields.add(
      EntryField(
        key: _privateKeyStorageKey,
        value: privateKeyValue,
        isProtected: true,
      ),
    );
    _appendAttachmentFields(fields, _attachments);

    setState(() => _isSaving = true);
    await _delayBeforeSavingOperation();
    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final entryAttachments =
          await _resolveEditAttachments(repository, edit.uuid, _attachments);
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

    final privateKeyValue = _privateKeyValue?.trim() ?? '';
    if (privateKeyValue.isNotEmpty &&
        _sshKeyRequiresPassphrase(privateKeyValue)) {
      final passphrase =
          _customAttributeValueForLabel('passphrase')?.trim() ?? '';
      if (passphrase.isEmpty) {
        widget.onShowToast(
          'Encrypted private key requires a valid passphrase before saving',
        );
        return;
      }
      final validationError = await _validatePrivateKeyPassphraseForKey(
        privateKey: privateKeyValue,
        sourcePath: _privateKeyPath,
        passphrase: passphrase,
      );
      if (validationError != null) {
        widget.onShowToast(validationError);
        return;
      }
    }

    final fields = <EntryField>[
      EntryField(key: AppKdbxFieldKeys.title, value: title, isStandard: true),
    ];

    if ((_privateKeyValue ?? '').isNotEmpty) {
      fields.add(
        EntryField(
          key: 'Private Key',
          value: _privateKeyValue!,
          isProtected: true,
        ),
      );
    }

    for (final attribute in _customAttributes) {
      final key = attribute.labelController.text.trim();
      final value = attribute.valueController.text.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      fields.add(
        EntryField(
          key: _displayLabelForFieldKey(key),
          value: value,
          isProtected: attribute.shouldProtect,
        ),
      );
    }
    _appendAttachmentFields(fields, _attachments);

    setState(() {
      _isSaving = true;
    });
    await _delayBeforeSavingOperation();

    try {
      final repository = ref.read(kdbxRepositoryProvider);
      final entryAttachments = _newEntryAttachmentsFrom(_attachments);
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
      widget.onShowToast('SSH key saved');
      if (!mounted) {
        return;
      }
      widget.onClose();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      widget.onShowToast('Unable to save item: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vaultSidebarCategoriesProvider);
    final existingTags = ref.watch(vaultSidebarTagsProvider);
    final rootGroupUuid = ref.watch(
      kdbxRepositoryProvider.select((repository) => repository.rootGroupUuid),
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
                            style: _text(
                              20,
                              const Color(0xFF2E3138),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _ModalIconAction(
                          icon: TablerIcons.x,
                          onTap: _confirmClose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        if (_isEditing)
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D3F55),
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFBFC8D5)),
                            ),
                            alignment: Alignment.center,
                            child: Image.asset(
                              'assets/images/item_type_ssh.png',
                              width: 36,
                              height: 36,
                              errorBuilder: (_, __, ___) => const Icon(
                                TablerIcons.prompt,
                                size: 28,
                                color: Colors.white,
                              ),
                            ),
                          )
                        else
                          _SshKeyHeroIcon(
                            onTap: widget.onReturnToPicker ?? () {},
                          ),
                        const SizedBox(width: 14),
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
                            _SshKeyImportSection(
                              isDragOver: _isDragOver,
                              isImporting: _isImporting,
                              importedFileName: _privateKeyName,
                              preview: _privateKeyPreview,
                              privateKeyMaterial: _privateKeyValue,
                              showExportActions: _hasPrivateKeyMaterial,
                              onCopyPrivateKey: _copySshPrivateKey,
                              onDownloadPrivateKey: _downloadSshPrivateKey,
                              onGeneratePrivateKey: _generatePrivateKey,
                              onImportPrivateKey: _pickPrivateKey,
                              onPastePrivateKey: _pastePrivateKeyFromClipboard,
                              onClearPrivateKey: _clearPrivateKey,
                              onDragEntered: () {
                                setState(() {
                                  _isDragOver = true;
                                });
                              },
                              onDragExited: () {
                                setState(() {
                                  _isDragOver = false;
                                });
                              },
                              onFileDropped: _importPrivateKey,
                            ),
                            const SizedBox(height: 16),
                            CompositedTransformTarget(
                              link: _addMoreLink,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _showAddMoreOptions = !_showAddMoreOptions;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F7FB),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      Text(
                                        '+ add more',
                                        style: _text(
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
                            if (!_isEditing) ...<Widget>[
                              const SizedBox(height: 14),
                              _CategoryDropdownField(
                                categories: categories,
                                rootGroupUuid: rootGroupUuid,
                                selectedCategoryUuid: effectiveCategoryUuid,
                                onChanged: (value) => setState(
                                    () => _selectedCategoryUuid = value),
                              ),
                            ],
                            const SizedBox(height: 14),
                            _AttachmentSection(
                              attachments: _attachments,
                              onAddPressed: _pickAttachments,
                              onRemove: _removeAttachment,
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'tags',
                                style: _text(
                                  12,
                                  const Color(0xFF6D63D6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _TagEditor(
                              tags: _tags,
                              existingTags: existingTags
                                  .map((entry) => entry.tag)
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
                    Container(
                      height: 1,
                      color: const Color(0xFFCCD4DF),
                    ),
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
                              options: _sshKeyAddMoreOptions,
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

bool _sshKeyRequiresPassphrase(String privateKey) {
  final normalized = privateKey.trim();
  if (normalized.isEmpty) {
    return false;
  }

  if (normalized.contains('-----BEGIN ENCRYPTED PRIVATE KEY-----')) {
    return true;
  }

  if (RegExp(
    r'^\s*Proc-Type:\s*4,\s*ENCRYPTED\s*$',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return true;
  }

  if (RegExp(
    r'^\s*DEK-Info:',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return true;
  }

  if (!normalized.contains('-----BEGIN OPENSSH PRIVATE KEY-----')) {
    return false;
  }

  try {
    final encoded = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();
    final bytes = base64Decode(encoded);
    final reader = _SshKeyByteReader(bytes);
    if (reader.readAscii(15) != 'openssh-key-v1\u0000') {
      return false;
    }
    final cipherName = reader.readString();
    final kdfName = reader.readString();
    return cipherName != 'none' || kdfName != 'none';
  } catch (_) {
    return false;
  }
}

class _SshKeyByteReader {
  _SshKeyByteReader(this.bytes);

  final Uint8List bytes;
  int _offset = 0;

  String readAscii(int length) {
    if (_offset + length > bytes.length) {
      throw const FormatException('Unexpected end of key data');
    }
    final chunk = bytes.sublist(_offset, _offset + length);
    _offset += length;
    return ascii.decode(chunk, allowInvalid: true);
  }

  int readUint32() {
    if (_offset + 4 > bytes.length) {
      throw const FormatException('Unexpected end of key data');
    }
    final value = (bytes[_offset] << 24) |
        (bytes[_offset + 1] << 16) |
        (bytes[_offset + 2] << 8) |
        bytes[_offset + 3];
    _offset += 4;
    return value;
  }

  String readString() {
    final length = readUint32();
    return readAscii(length);
  }
}

class _SshKeyHeroIcon extends StatelessWidget {
  const _SshKeyHeroIcon({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF2D3F55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFC8D5)),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              'assets/images/item_type_ssh.png',
              width: 36,
              height: 36,
              errorBuilder: (_, __, ___) => const Icon(
                TablerIcons.prompt,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            left: -2,
            bottom: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD38A),
                border: Border.all(color: const Color(0xFFFFA629), width: 2),
              ),
              alignment: Alignment.center,
              child: const Icon(
                TablerIcons.key,
                size: 16,
                color: Color(0xFF8A5600),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 2,
            child: InkWell(
              onTap: onTap,
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
          ),
        ],
      ),
    );
  }
}

const String _kSshPrivateKeyPreviewIconAsset =
    'assets/images/others/key-password.png';

/// Human-readable key type from PEM header (1Password-style primary line when
/// [ssh-keygen] has not produced a title yet).
String? _sshPemHumanTitle(String? key) {
  if (key == null) return null;
  final trimmed = key.trim();
  if (trimmed.isEmpty) return null;

  for (final raw in trimmed.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (!line.startsWith('-----BEGIN')) continue;
    final u = line.toUpperCase();
    if (u.contains('OPENSSH PRIVATE KEY')) return 'OpenSSH private key';
    if (u.contains('RSA PRIVATE KEY')) return 'RSA private key';
    if (u.contains('EC PRIVATE KEY')) return 'EC private key';
    if (u.contains('ENCRYPTED PRIVATE KEY')) return 'Encrypted private key';
    if (u.contains('BEGIN PRIVATE KEY-----')) return 'PKCS#8 private key';
    return 'PEM private key';
  }

  if (RegExp(
    r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return 'PEM private key';
  }
  return null;
}

String _sshImportNameFallbackTitle(String importedFileName) {
  final name = importedFileName.trim();
  final lower = name.toLowerCase();
  if (lower.contains('generated ed25519')) return 'Ed25519';
  if (lower.contains('generated rsa')) return 'RSA key';
  if (name.isNotEmpty &&
      !lower.contains('pasted') &&
      !lower.endsWith('private key')) {
    return name;
  }
  return 'SSH private key';
}

/// Bold line: `RSA, 2048-bit` from [preview], else PEM-derived title.
String _sshPreviewPrimaryTitle({
  required _SshPrivateKeyPreview? preview,
  required String? privateKeyMaterial,
  required String importedFileName,
}) {
  final typed = preview?.title.trim() ?? '';
  if (typed.isNotEmpty) return typed;
  return _sshPemHumanTitle(privateKeyMaterial) ??
      _sshImportNameFallbackTitle(importedFileName);
}

/// Second line: `SHA256:…` / `MD5:…` like 1Password.
String _sshPreviewFingerprintLine(String fingerprintRaw) {
  final fp = fingerprintRaw.trim();
  if (fp.isEmpty) return '';
  final lower = fp.toLowerCase();
  if (lower.startsWith('sha256:') || lower.startsWith('md5:')) {
    return fp;
  }
  return 'SHA256:$fp';
}

/// Abbreviated key-content line shown when fingerprint is unavailable.
/// e.g. `OpenSSH: b3BlbnNzaC1rZXktdjEAAAAABG5v.....`
String? _sshKeyContentPreview(String? privateKeyMaterial) {
  if (privateKeyMaterial == null) return null;
  final trimmed = privateKeyMaterial.trim();
  if (trimmed.isEmpty) return null;

  String label = 'Key';
  for (final raw in trimmed.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (!line.startsWith('-----BEGIN')) continue;
    final u = line.toUpperCase();
    if (u.contains('OPENSSH')) {
      label = 'OpenSSH';
    } else if (u.contains('RSA')) {
      label = 'RSA';
    } else if (u.contains('EC ') || u.contains('ECDSA')) {
      label = 'ECDSA';
    } else if (u.contains('DSA')) {
      label = 'DSA';
    }
    break;
  }

  final base64Body = trimmed
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty && !l.trim().startsWith('-----'))
      .join('');
  if (base64Body.isEmpty) return null;

  const previewLen = 28;
  final snippet = base64Body.length > previewLen
      ? '${base64Body.substring(0, previewLen)}.....'
      : base64Body;
  return '$label: $snippet';
}

/// Compact key summary (type + fingerprint) similar to 1Password’s SSH editor.
class _SshKeyLoadedPreviewShort extends StatelessWidget {
  const _SshKeyLoadedPreviewShort({
    required this.importedFileName,
    required this.preview,
    required this.privateKeyMaterial,
  });

  final String importedFileName;
  final _SshPrivateKeyPreview? preview;
  final String? privateKeyMaterial;

  @override
  Widget build(BuildContext context) {
    final fpRaw = preview?.fingerprint.trim() ?? '';
    final fpLine = _sshPreviewFingerprintLine(fpRaw);
    final hasFp = fpLine.isNotEmpty;
    final contentPreview =
        !hasFp ? _sshKeyContentPreview(privateKeyMaterial) : null;
    final subtitleText =
        hasFp ? fpLine : (contentPreview ?? 'Fingerprint unavailable');
    final hasSubtitle = hasFp || contentPreview != null;
    final primaryTitle = _sshPreviewPrimaryTitle(
      preview: preview,
      privateKeyMaterial: privateKeyMaterial,
      importedFileName: importedFileName,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Image.asset(
          _kSshPrivateKeyPreviewIconAsset,
          width: 56,
          height: 56,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const Icon(
            TablerIcons.key,
            size: 36,
            color: Color(0xFF8A5600),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            primaryTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _text(
              16,
              const Color(0xFF101828),
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            subtitleText,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: (9 + 2 + currentTextSizeDelta).toDouble(),
              height: 1.35,
              color: hasSubtitle
                  ? const Color(0xFF667085)
                  : const Color(0xFF98A2B3),
              fontWeight: FontWeight.w500,
              fontFamily: 'Menlo',
              letterSpacing: hasSubtitle ? 0.08 : 0.0,
            ),
          ),
        ),
      ],
    );
  }
}

class _SshKeyImportSection extends StatelessWidget {
  const _SshKeyImportSection({
    required this.isDragOver,
    required this.isImporting,
    required this.importedFileName,
    required this.preview,
    required this.privateKeyMaterial,
    required this.showExportActions,
    required this.onCopyPrivateKey,
    required this.onDownloadPrivateKey,
    required this.onGeneratePrivateKey,
    required this.onImportPrivateKey,
    required this.onPastePrivateKey,
    required this.onClearPrivateKey,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onFileDropped,
  });

  final bool isDragOver;
  final bool isImporting;
  final String? importedFileName;
  final _SshPrivateKeyPreview? preview;
  final String? privateKeyMaterial;
  final bool showExportActions;
  final VoidCallback onCopyPrivateKey;
  final Future<void> Function() onDownloadPrivateKey;
  final Future<void> Function() onGeneratePrivateKey;
  final Future<void> Function() onImportPrivateKey;
  final Future<void> Function() onPastePrivateKey;
  final VoidCallback onClearPrivateKey;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final Future<void> Function(String path) onFileDropped;

  @override
  Widget build(BuildContext context) {
    final hasImportedKey =
        importedFileName != null && importedFileName!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E7F0)),
      ),
      child: Column(
        children: <Widget>[
          if (isImporting)
            const SizedBox(
              height: 154,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Color(0xFF2F6BFF),
                  ),
                ),
              ),
            )
          else if (hasImportedKey)
            DropTarget(
              onDragEntered: (_) => onDragEntered(),
              onDragExited: (_) => onDragExited(),
              onDragDone: (detail) async {
                onDragExited();
                if (detail.files.isNotEmpty) {
                  await onFileDropped(detail.files.first.path);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                color:
                    isDragOver ? const Color(0xFFF2F7FF) : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 28,
                ),
                child: _SshKeyLoadedPreviewShort(
                  importedFileName: importedFileName!,
                  preview: preview,
                  privateKeyMaterial: privateKeyMaterial,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(18),
              child: DropTarget(
                onDragEntered: (_) => onDragEntered(),
                onDragExited: (_) => onDragExited(),
                onDragDone: (detail) async {
                  onDragExited();
                  if (detail.files.isNotEmpty) {
                    await onFileDropped(detail.files.first.path);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  height: 140,
                  decoration: BoxDecoration(
                    color: isDragOver
                        ? const Color(0xFFF2F7FF)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDragOver
                          ? const Color(0xFF9CB8EE)
                          : const Color(0xFFD4D9E2),
                      style: BorderStyle.solid,
                      width: isDragOver ? 1.6 : 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Image.asset(
                        _kSshPrivateKeyPreviewIconAsset,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, __, ___) => const Icon(
                          TablerIcons.key,
                          size: 34,
                          color: Color(0xFFC4C7CE),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Drag a private key file here to import.',
                        textAlign: TextAlign.center,
                        style: _text(
                          14,
                          const Color(0xFFB8B8B8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE6EBF2)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: PopupMenuButton<_SshPrivateKeyAction>(
                    enabled: !isImporting,
                    tooltip: 'Private key actions',
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: Colors.white,
                    onSelected: (action) async {
                      switch (action) {
                        case _SshPrivateKeyAction.generateNewKey:
                          await onGeneratePrivateKey();
                          break;
                        case _SshPrivateKeyAction.importKeyFile:
                          await onImportPrivateKey();
                          break;
                        case _SshPrivateKeyAction.pasteFromClipboard:
                          await onPastePrivateKey();
                          break;
                        case _SshPrivateKeyAction.copyPrivateKey:
                          onCopyPrivateKey();
                          break;
                        case _SshPrivateKeyAction.downloadPrivateKey:
                          await onDownloadPrivateKey();
                          break;
                      }
                    },
                    itemBuilder: (context) {
                      return <PopupMenuEntry<_SshPrivateKeyAction>>[
                        const PopupMenuItem<_SshPrivateKeyAction>(
                          value: _SshPrivateKeyAction.generateNewKey,
                          child: _SshKeyActionMenuItem(
                            icon: TablerIcons.key,
                            label: 'Generate a New Key',
                          ),
                        ),
                        const PopupMenuItem<_SshPrivateKeyAction>(
                          value: _SshPrivateKeyAction.importKeyFile,
                          child: _SshKeyActionMenuItem(
                            icon: TablerIcons.upload,
                            label: 'Import a Key File',
                          ),
                        ),
                        const PopupMenuItem<_SshPrivateKeyAction>(
                          value: _SshPrivateKeyAction.pasteFromClipboard,
                          child: _SshKeyActionMenuItem(
                            icon: TablerIcons.clipboard_text,
                            label: 'Paste Key from Clipboard',
                          ),
                        ),
                        if (hasImportedKey && showExportActions) ...<PopupMenuEntry<
                            _SshPrivateKeyAction>>[
                          const PopupMenuDivider(),
                          const PopupMenuItem<_SshPrivateKeyAction>(
                            value: _SshPrivateKeyAction.copyPrivateKey,
                            child: _SshKeyActionMenuItem(
                              icon: TablerIcons.copy,
                              label: 'Copy private key',
                            ),
                          ),
                          const PopupMenuItem<_SshPrivateKeyAction>(
                            value: _SshPrivateKeyAction.downloadPrivateKey,
                            child: _SshKeyActionMenuItem(
                              icon: TablerIcons.download,
                              label: 'Save private key to file…',
                            ),
                          ),
                        ],
                      ];
                    },
                    child: Row(
                      children: <Widget>[
                        Text(
                          hasImportedKey
                              ? '+ Replace Private Key'
                              : '+ Add Private Key',
                          style: _text(
                            12,
                            isImporting
                                ? const Color(0xFF9CB8EE)
                                : const Color(0xFF0B63E5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          TablerIcons.chevron_down,
                          size: 14,
                          color: isImporting
                              ? const Color(0xFFA8B4C8)
                              : const Color(0xFF667085),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasImportedKey && showExportActions) ...<Widget>[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Copy private key',
                    child: InkWell(
                      onTap: isImporting ? null : onCopyPrivateKey,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          TablerIcons.copy,
                          size: 16,
                          color: isImporting
                              ? const Color(0xFFD0D5DD)
                              : const Color(0xFF475467),
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Save private key to file',
                    child: InkWell(
                      onTap: isImporting ? null : () => onDownloadPrivateKey(),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          TablerIcons.download,
                          size: 16,
                          color: isImporting
                              ? const Color(0xFFD0D5DD)
                              : const Color(0xFF475467),
                        ),
                      ),
                    ),
                  ),
                ],
                if (hasImportedKey) ...<Widget>[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Remove private key',
                    child: InkWell(
                      onTap: isImporting ? null : onClearPrivateKey,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          TablerIcons.trash,
                          size: 16,
                          color: isImporting
                              ? const Color(0xFFD0D5DD)
                              : const Color(0xFF98A2B3),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SshKeyActionMenuItem extends StatelessWidget {
  const _SshKeyActionMenuItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: const Color(0xFF6B7280)),
        const SizedBox(width: 10),
        Text(
          label,
          style: _text(
            13,
            const Color(0xFF2E3138),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
