part of 'vault_screen.dart';

class _DetailField {
  _DetailField({
    required this.id,
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    bool isSecret = false,
    bool showStrength = false,
    bool isCardNumber = false,
    this.labelColor,
  })  : _isSecret = isSecret,
        _showStrength = showStrength,
        _isCardNumber = isCardNumber,
        layerLink = LayerLink();

  final String id;
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color? labelColor;
  final bool? _isSecret;
  final bool? _showStrength;
  final bool? _isCardNumber;
  final LayerLink layerLink;

  bool get isSecret => _isSecret ?? false;
  bool get showStrength => _showStrength ?? false;
  bool get isCardNumber => _isCardNumber ?? false;
}

class _SshDetailSnapshot {
  const _SshDetailSnapshot({
    required this.summaryTitle,
    required this.privateKey,
    required this.publicKey,
    required this.fingerprint,
    required this.keyFileName,
    required this.passphrase,
  });

  final String summaryTitle;
  final String privateKey;
  final String publicKey;
  final String fingerprint;
  final String keyFileName;
  final String passphrase;
}

class _DetailPane extends ConsumerStatefulWidget {
  const _DetailPane({
    required this.entry,
    required this.onShowToast,
    required this.onRequestDelete,
    required this.onRequestRemovePasskey,
    required this.onOpenScanTotp,
    required this.onOpenEditItem,
    required this.onOpenSshAgentSettings,
    required this.onRequestRestore,
    required this.onRequestPermanentDelete,
  });

  final _MockEntry entry;
  final ValueChanged<String> onShowToast;
  final VoidCallback onRequestDelete;
  final VoidCallback onRequestRemovePasskey;
  final VoidCallback onOpenScanTotp;
  final VoidCallback onOpenEditItem;
  final VoidCallback onOpenSshAgentSettings;
  final VoidCallback onRequestRestore;
  final VoidCallback onRequestPermanentDelete;

  @override
  ConsumerState<_DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends ConsumerState<_DetailPane> {
  static const double _scrollbarThickness = 6;
  Timer? _clipboardClearTimer;

  late List<_DetailField> _fields;
  late final ScrollController _scrollController;
  int _nextFieldId = 0;
  final Map<String, bool> _fieldHovered = {};

  bool _passkeyBannerIgnored = false;
  bool _weakPasswordBannerIgnored = false;
  List<_MockAttachment> _resolvedAttachments = const <_MockAttachment>[];

  OverlayEntry? _menuOverlay;
  String? _menuOpenId;

  String? _removePendingId;
  bool get _canScanTotp => widget.entry.itemType == VaultItemType.login;

  String? _currentCategoryName() {
    final activeDatabase = ref.watch(activeDatabaseProvider);
    if (activeDatabase == null || widget.entry.groupUuid.isEmpty) {
      return null;
    }

    final group =
        _findGroupInTree(activeDatabase.rootGroup, widget.entry.groupUuid);
    if (group == null || group.isRecycleBin) {
      return null;
    }

    final name = group.name.trim();
    if (name.isEmpty || name == activeDatabase.rootGroup.name.trim()) {
      return null;
    }

    return name;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  KdbxGroup? _findGroupInTree(KdbxGroup group, String uuid) {
    if (group.uuid == uuid) {
      return group;
    }

    for (final child in group.groups) {
      final match = _findGroupInTree(child, uuid);
      if (match != null) {
        return match;
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initFields();
    _resolvedAttachments = widget.entry.attachments;
    _loadBinaryAttachments();
  }

  void _initFields() {
    _nextFieldId = 0;
    _fields = widget.entry.detailFields
        .map(
          (field) => _DetailField(
            id: 'field_${_nextFieldId++}',
            icon: field.icon,
            label: field.label,
            value: field.value,
            iconColor: field.iconColor,
            labelColor: field.labelColor,
            isSecret: field.isSecret,
            showStrength: field.showStrength,
            isCardNumber: field.isCardNumber,
          ),
        )
        .toList(growable: false);
    _fieldHovered.clear();
    for (final field in _fields) {
      _fieldHovered[field.id] = false;
    }
  }

  @override
  void didUpdateWidget(_DetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) {
      _dismissMenu(fromDispose: true);
      setState(() {
        _initFields();
        _removePendingId = null;
        _passkeyBannerIgnored = false;
        _weakPasswordBannerIgnored = false;
        _resolvedAttachments = widget.entry.attachments;
      });
      _loadBinaryAttachments();
    }
  }

  Future<void> _loadBinaryAttachments() async {
    if (widget.entry.uuid.isEmpty) {
      return;
    }
    try {
      final attSw = Stopwatch()..start();
      final binaryAttachments = await ref
          .read(kdbxRepositoryProvider)
          .getEntryAttachments(widget.entry.uuid);
      debugPrint('[PERF] getEntryAttachments took '
          '${attSw.elapsedMilliseconds}ms '
          '(count=${binaryAttachments.length}, uuid=${widget.entry.uuid})');
      if (!mounted) {
        return;
      }
      if (binaryAttachments.isEmpty) {
        return;
      }
      setState(() {
        _resolvedAttachments = binaryAttachments
            .map(
              (attachment) => _MockAttachment(
                name: attachment.name,
                sizeLabel: _formatAttachmentSizeLabel(attachment.size),
                isImage: attachment.isImage,
                bytes: attachment.bytes,
              ),
            )
            .toList(growable: false);
      });
    } catch (_) {
      // Keep metadata-only attachments if binary extraction fails.
    }
  }

  void _openImagePreview(_MockAttachment attachment) {
    final bytes = attachment.bytes;
    if (!attachment.isImage) {
      return;
    }
    if (bytes == null) {
      widget.onShowToast('Image preview is unavailable for this attachment');
      return;
    }
    showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Close image preview',
      barrierDismissible: true,
      barrierColor: const Color(0xD9000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return GestureDetector(
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Stack(
                children: <Widget>[
                  Center(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 6,
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    top: 18,
                    right: 18,
                    child: InkWell(
                      onTap: () => Navigator.of(dialogContext).pop(),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0x66000000),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          TablerIcons.x,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadAttachment(_MockAttachment attachment) async {
    final bytes = attachment.bytes;
    if (bytes == null) {
      widget.onShowToast('Attachment bytes are unavailable');
      return;
    }

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save attachment',
      fileName: attachment.name,
      lockParentWindow: true,
      type: FileType.any,
    );
    if (outputPath == null || outputPath.trim().isEmpty) {
      return;
    }

    await File(outputPath).writeAsBytes(bytes, flush: true);
    if (!mounted) {
      return;
    }
    widget.onShowToast('Attachment saved');
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    _dismissMenu(fromDispose: true);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    widget.onShowToast('$label copied to clipboard');
    _clipboardClearTimer?.cancel();
    final seconds = ref.read(vaultClipboardClearSecondsProvider);
    if (seconds != null) {
      _clipboardClearTimer = Timer(Duration(seconds: seconds), () {
        Clipboard.setData(const ClipboardData(text: ''));
      });
    }
  }

  String _findFieldValue(Iterable<String> labels) {
    final normalizedLabels = labels.map((label) => label.toLowerCase()).toSet();
    for (final field in _fields) {
      if (normalizedLabels.contains(field.label.trim().toLowerCase())) {
        return field.value.trim();
      }
    }
    return '';
  }

  String _inferSshSummaryTitle({
    required String keyType,
    required String publicKey,
    required String privateKey,
    required String keyFileName,
  }) {
    final normalizedType = keyType.trim().toLowerCase();
    final normalizedPublic = publicKey.trim().toLowerCase();
    final normalizedPrivate = privateKey.trim().toLowerCase();
    final normalizedFileName = keyFileName.trim().toLowerCase();

    final bitsMatch = RegExp(r'(2048|3072|4096|8192)')
        .firstMatch('$normalizedType $normalizedFileName');
    final bits = bitsMatch?.group(1);

    final isRsa = normalizedType.contains('rsa') ||
        normalizedPublic.startsWith('ssh-rsa') ||
        normalizedPrivate.contains('begin rsa private key') ||
        normalizedFileName.contains('rsa');
    if (isRsa) {
      return bits == null ? 'RSA' : 'RSA, $bits-bit';
    }

    final isEd25519 = normalizedType.contains('ed25519') ||
        normalizedPublic.startsWith('ssh-ed25519') ||
        normalizedFileName.contains('ed25519');
    if (isEd25519) {
      return 'Ed25519';
    }

    if (keyType.trim().isNotEmpty) {
      return keyType.trim();
    }

    return 'SSH Key';
  }

  _SshDetailSnapshot _buildSshSnapshot() {
    final privateKey = _findFieldValue(const <String>['private key']);
    final publicKey = _findFieldValue(const <String>['public key']);
    final fingerprint = _findFieldValue(const <String>['fingerprint']);
    final keyFileName = _findFieldValue(const <String>['key file name']);
    final passphrase = _findFieldValue(const <String>['passphrase']);
    final keyType = _findFieldValue(const <String>['key type']);

    return _SshDetailSnapshot(
      summaryTitle: _inferSshSummaryTitle(
        keyType: keyType,
        publicKey: publicKey,
        privateKey: privateKey,
        keyFileName: keyFileName,
      ),
      privateKey: privateKey,
      publicKey: publicKey,
      fingerprint: fingerprint,
      keyFileName: keyFileName,
      passphrase: passphrase,
    );
  }

  bool _isSshCoreField(_DetailField field) {
    const sshCoreLabels = <String>{
      'private key',
      'public key',
      'fingerprint',
      'key file name',
      'passphrase',
      'key type',
    };
    return sshCoreLabels.contains(field.label.trim().toLowerCase());
  }

  bool _shouldShowWeakPasswordBanner() {
    if (_weakPasswordBannerIgnored) return false;
    final password = widget.entry.password;
    if (password.isEmpty) return false;
    final strength = _evalPasswordStrength(password);
    return strength == _PasswordStrength.weak ||
        strength == _PasswordStrength.fair;
  }

  List<Widget> _buildStandardFieldRows(List<_DetailField> fields) {
    if (fields.isEmpty) {
      return const <Widget>[];
    }

    final lastField = fields.last;
    final hideCardNumber = ref.watch(vaultHideCreditCardNumberProvider);

    return <Widget>[
      _FieldRowsSection(
        children: <Widget>[
          for (final field in fields)
            CompositedTransformTarget(
              link: field.layerLink,
              child: field.isSecret
                  ? _SecretFieldRow(
                      icon: field.icon,
                      label: field.label,
                      secretValue: field.value,
                      iconColor: field.iconColor,
                      hovered: _fieldHovered[field.id] == true ||
                          _menuOpenId == field.id,
                      menuOpen: _menuOpenId == field.id,
                      showDivider: field != lastField,
                      showVisibilityToggle: true,
                      showStrength: field.showStrength,
                      onCopyPressed: () => _copyToClipboard(
                        field.value,
                        field.label,
                      ),
                      onHoverChanged: (v) => setState(
                        () => _fieldHovered[field.id] = v,
                      ),
                      onArrowPressed: () {
                        if (_menuOpenId == field.id) {
                          _dismissMenu();
                        } else {
                          _showFieldMenu(
                            link: field.layerLink,
                            isPassword: true,
                            fieldId: field.id,
                            fieldLabel: field.label,
                            fieldValue: field.value,
                          );
                        }
                      },
                    )
                  : _FieldRow(
                      icon: field.icon,
                      label: field.label,
                      value: field.isCardNumber && hideCardNumber
                          ? _maskCreditCardNumberForDisplay(field.value)
                          : field.value,
                      iconColor: field.iconColor,
                      labelColor: field.labelColor,
                      hovered: _fieldHovered[field.id] == true ||
                          _menuOpenId == field.id,
                      menuOpen: _menuOpenId == field.id,
                      showDivider: field != lastField,
                      onCopyPressed: () => _copyToClipboard(
                        field.value,
                        field.label,
                      ),
                      onHoverChanged: (v) => setState(
                        () => _fieldHovered[field.id] = v,
                      ),
                      onArrowPressed: () {
                        if (_menuOpenId == field.id) {
                          _dismissMenu();
                        } else {
                          _showFieldMenu(
                            link: field.layerLink,
                            isPassword: false,
                            fieldId: field.id,
                            fieldLabel: field.label,
                            fieldValue: field.isCardNumber && hideCardNumber
                                ? _maskCreditCardNumberForDisplay(field.value)
                                : field.value,
                          );
                        }
                      },
                    ),
            ),
        ],
      ),
    ];
  }

  void _showFieldMenu({
    required LayerLink link,
    required bool isPassword,
    required String fieldId,
    required String fieldLabel,
    required String fieldValue,
  }) {
    _menuOverlay?.remove();
    _menuOverlay = null;
    setState(() => _menuOpenId = fieldId);

    _menuOverlay = OverlayEntry(
      builder: (ctx) => _FieldMenuOverlay(
        link: link,
        isPassword: isPassword,
        onDismiss: _dismissMenu,
        onDuplicate: isPassword
            ? null
            : () {
                _dismissMenu();
                _duplicateField(fieldId);
              },
        onViewLarge: () {
          _dismissMenu();
          _openLargeView(fieldLabel, fieldValue);
        },
        onRemove: isPassword
            ? null
            : () {
                _dismissMenu();
                setState(() => _removePendingId = fieldId);
              },
      ),
    );

    Overlay.of(context).insert(_menuOverlay!);
  }

  void _dismissMenu({bool fromDispose = false}) {
    _menuOverlay?.remove();
    _menuOverlay = null;
    if (!fromDispose && mounted) setState(() => _menuOpenId = null);
  }

  void _openLargeView(String label, String value) {
    showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Close large value view',
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        return _LargeValueOverlay(
          label: label,
          value: value,
          onClose: () => Navigator.of(dialogContext).pop(),
          onCopy: () => _copyToClipboard(value, label),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: child,
        );
      },
    );
  }

  void _duplicateField(String id) {
    final field = _fields.firstWhere((f) => f.id == id);
    final newId = 'field_${_nextFieldId++}';
    final idx = _fields.indexWhere((f) => f.id == id);
    setState(() {
      _fields = List<_DetailField>.from(_fields)
        ..insert(
          idx + 1,
          _DetailField(
            id: newId,
            icon: field.icon,
            label: field.label,
            value: field.value,
            iconColor: field.iconColor,
            labelColor: field.labelColor,
          ),
        );
      _fieldHovered[newId] = false;
    });
  }

  void _removeField(String id) {
    setState(() {
      _fields = List<_DetailField>.from(_fields)
        ..removeWhere((f) => f.id == id);
      _fieldHovered.remove(id);
      _removePendingId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final buildSw = Stopwatch()..start();
    final categoryName = _currentCategoryName();
    final hasWebsite = widget.entry.website.trim().isNotEmpty;
    final parsedWebsiteHost =
        hasWebsite ? Uri.tryParse(widget.entry.website)?.host ?? '' : '';
    final websiteHost = parsedWebsiteHost.isNotEmpty
        ? parsedWebsiteHost
        : widget.entry.website.trim();
    final itemTypeVisual = _newItemTypeForVaultType(widget.entry.itemType);
    final itemTypeLabel = itemTypeVisual?.label ?? 'Secure item';
    final itemTypeColor = itemTypeVisual?.iconColor ?? _kPrimaryButtonColor;
    final isSshAgentEnabled = ref.watch(sshAgentEnabledProvider);
    final activeDb = ref.watch(activeDatabaseProvider);
    final isInTrash = activeDb != null &&
        (_findGroupInTree(activeDb.rootGroup, widget.entry.groupUuid)
                ?.isRecycleBin ??
            false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[PERF] _DetailPane.build synchronous portion took '
          '${buildSw.elapsedMicroseconds / 1000}ms '
          '(fields=${_fields.length}, uuid=${widget.entry.uuid})');
    });

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissMenu,
        child: Container(
          color: _VaultColors.surface,
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  Container(
                    height: 92,
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF6EE),
                      border: Border(
                        bottom: BorderSide(
                          color: Color(0xFFE7CFC0),
                          width: 1.2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 52,
                          height: 52,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _VaultColors.surface,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _kPrimaryButtonColor.withValues(
                                alpha: 0.18,
                              ),
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x14D8673E),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: _FaviconTile(
                              entry: widget.entry,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                widget.entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _displayText(
                                  23,
                                  _VaultColors.title,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                websiteHost.isNotEmpty
                                    ? websiteHost
                                    : (categoryName ?? 'Secure item'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _text(
                                  13,
                                  _VaultColors.headerLabel,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isInTrash && _canScanTotp) ...<Widget>[
                          _VaultToolbarIconButton(
                            icon: TablerIcons.scan,
                            tooltip: 'Scan 2FA code',
                            onPressed: widget.onOpenScanTotp,
                            accentColor: const Color(0xFF6C63D5),
                          ),
                          const SizedBox(width: 7),
                        ],
                        if (!isInTrash)
                          _VaultToolbarIconButton(
                            icon: TablerIcons.edit,
                            tooltip: 'Edit item',
                            onPressed: widget.onOpenEditItem,
                            accentColor: _kPrimaryButtonColor,
                          ),
                        if (isInTrash)
                          _VaultToolbarIconButton(
                            icon: TablerIcons.restore,
                            tooltip: 'Recover item',
                            onPressed: widget.onRequestRestore,
                            accentColor: const Color(0xFF168B76),
                          ),
                        if (hasWebsite) ...<Widget>[
                          const SizedBox(width: 7),
                          _VaultToolbarIconButton(
                            icon: TablerIcons.external_link,
                            tooltip: 'Open website',
                            accentColor: const Color(0xFF2E6EDB),
                            onPressed: () async {
                              final url = Uri.parse(widget.entry.website);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ],
                        const SizedBox(width: 7),
                        _DetailMoreMenu(
                          destructiveLabel:
                              isInTrash ? 'Delete permanently' : 'Delete item',
                          onDelete: isInTrash
                              ? widget.onRequestPermanentDelete
                              : widget.onRequestDelete,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ScrollbarTheme(
                      data: const ScrollbarThemeData(
                        thumbColor: WidgetStatePropertyAll<Color>(
                          Color(0xFFAAA69F),
                        ),
                        trackColor: WidgetStatePropertyAll<Color>(
                          _VaultColors.surfaceMuted,
                        ),
                        trackBorderColor: WidgetStatePropertyAll<Color>(
                          _VaultColors.borderSoft,
                        ),
                      ),
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        interactive: true,
                        thickness: _scrollbarThickness,
                        radius: const Radius.circular(999),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(top: 14, bottom: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (widget.entry.hasPasskeyChip &&
                                    !_passkeyBannerIgnored)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: _PasskeyBanner(
                                      onRemovePasskey:
                                          widget.onRequestRemovePasskey,
                                    ),
                                  ),
                                if (widget.entry.hasPasskeyChip &&
                                    !_passkeyBannerIgnored)
                                  const SizedBox(height: 14),
                                if (_shouldShowWeakPasswordBanner()) ...<Widget>[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: _WeakPasswordBanner(
                                      onChangePassword: () async {
                                        final url =
                                            Uri.parse(widget.entry.website);
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url,
                                              mode: LaunchMode
                                                  .externalApplication);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                if (widget.entry.itemType ==
                                    VaultItemType.sshKey) ...<Widget>[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: _SshAgentSetupBanner(
                                      enabled: isSshAgentEnabled,
                                      onOpenSettings:
                                          widget.onOpenSshAgentSettings,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: _SshDetailPanel(
                                      snapshot: _buildSshSnapshot(),
                                      onCopy: _copyToClipboard,
                                      onViewPrivateKey: () {
                                        final privateKey = _findFieldValue(
                                          const <String>['private key'],
                                        );
                                        if (privateKey.isEmpty) {
                                          return;
                                        }
                                        _openLargeView(
                                          'Private Key',
                                          privateKey,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ..._buildStandardFieldRows(
                                    _fields
                                        .where(
                                            (field) => !_isSshCoreField(field))
                                        .toList(growable: false),
                                  ),
                                ] else ...<Widget>[
                                  if (widget.entry.totpAuthUrl
                                      .isNotEmpty) ...<Widget>[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      child: _LiveTotpRow(
                                        entry: widget.entry,
                                        onCopyTotp: _copyToClipboard,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (widget.entry.socialProvider
                                      .isNotEmpty) ...<Widget>[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                      ),
                                      child: _SocialLoginCard(
                                        providerId: widget.entry.socialProvider,
                                        domain: widget.entry.website,
                                        username: widget.entry.username,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  ..._buildStandardFieldRows(_fields),
                                ],
                                if (widget.entry.itemType ==
                                        VaultItemType.sshKey &&
                                    widget.entry.totpAuthUrl
                                        .isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 14),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: _LiveTotpRow(
                                      entry: widget.entry,
                                      onCopyTotp: _copyToClipboard,
                                    ),
                                  ),
                                ],
                                if (widget.entry.notes
                                    .trim()
                                    .isNotEmpty) ...<Widget>[
                                  if (_fields.isNotEmpty)
                                    const SizedBox(height: 14),
                                  _DetailCard(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        8,
                                        14,
                                        12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Row(
                                            children: <Widget>[
                                              const Expanded(
                                                child: _SectionLabel(
                                                  icon: TablerIcons.notes,
                                                  label: 'Notes',
                                                  iconColor: Color(0xFFB98A1B),
                                                ),
                                              ),
                                              _FlatRowAction(
                                                icon: TablerIcons.copy,
                                                tooltip: 'Copy notes',
                                                onTap: () => _copyToClipboard(
                                                  widget.entry.notes,
                                                  'Notes',
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 36,
                                            ),
                                            child: SelectableText(
                                              widget.entry.notes,
                                              style: _text(
                                                14,
                                                _VaultColors.title,
                                                fontWeight: FontWeight.w500,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                if (_resolvedAttachments
                                    .isNotEmpty) ...<Widget>[
                                  const SizedBox(height: 14),
                                  _DetailCard(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: _AttachmentsSection(
                                        attachments: _resolvedAttachments,
                                        onAttachmentTap: (attachment) {
                                          _openImagePreview(attachment);
                                        },
                                        onAttachmentDownload: (attachment) {
                                          _downloadAttachment(attachment);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                                if (_fields.isNotEmpty ||
                                    widget.entry.notes.trim().isNotEmpty ||
                                    _resolvedAttachments.isNotEmpty)
                                  const SizedBox(height: 14),
                                _DetailCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      _EntryDateStats(
                                        createdAt: _formatDateTime(
                                          widget.entry.createdAt,
                                        ),
                                        updatedAt: _formatDateTime(
                                          widget.entry.updatedAt,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.fromLTRB(
                                          14,
                                          12,
                                          14,
                                          12,
                                        ),
                                        decoration: const BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: _kDetailCardBorder,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            if (widget.entry.tags
                                                .isNotEmpty) ...<Widget>[
                                              _EntryTagsRow(
                                                tags: widget.entry.tags,
                                              ),
                                              const SizedBox(height: 10),
                                            ],
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: <Widget>[
                                                _ItemTypeTag(
                                                  label: itemTypeLabel,
                                                  color: itemTypeColor,
                                                ),
                                                if (categoryName != null)
                                                  _CategoryTag(
                                                    categoryName: categoryName,
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const _DetailCreditsBar(),
                ],
              ),
              if (_removePendingId != null)
                Positioned.fill(
                  child: _RemoveAttributeConfirmationOverlay(
                    onCancel: () => setState(() => _removePendingId = null),
                    onConfirm: () => _removeField(_removePendingId!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemTypeTag extends StatelessWidget {
  const _ItemTypeTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _text(
          10,
          color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1,
        ),
      ),
    );
  }
}

class _SshDetailPanel extends StatelessWidget {
  const _SshDetailPanel({
    required this.snapshot,
    required this.onCopy,
    required this.onViewPrivateKey,
  });

  final _SshDetailSnapshot snapshot;
  final Future<void> Function(String value, String label) onCopy;
  final VoidCallback onViewPrivateKey;

  @override
  Widget build(BuildContext context) {
    final hasFingerprint = snapshot.fingerprint.trim().isNotEmpty;
    final fingerprintLabel = hasFingerprint
        ? snapshot.fingerprint.trim()
        : 'Fingerprint unavailable';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F2)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: <Widget>[
                const _CircularDetailIcon(
                  icon: TablerIcons.key,
                  color: Color(0xFF2E5ECC),
                  size: 44,
                  iconSize: 20,
                  backgroundColor: Color(0xFFF0F6FF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        snapshot.summaryTitle,
                        style: _text(
                          15,
                          const Color(0xFF1F2937),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        fingerprintLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          11,
                          const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasFingerprint)
                  _FlatRowAction(
                    icon: TablerIcons.copy,
                    tooltip: 'Copy fingerprint',
                    onTap: () => onCopy(snapshot.fingerprint, 'Fingerprint'),
                  ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFFE9EEF6),
          ),
          if (snapshot.publicKey.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.key,
              iconColor: const Color(0xFF5A78C5),
              label: 'public key',
              value: snapshot.publicKey,
              monospace: true,
              onCopy: () => onCopy(snapshot.publicKey, 'Public key'),
            ),
          if (snapshot.publicKey.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: Color(0xFFE9EEF6)),
          if (snapshot.fingerprint.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.fingerprint,
              iconColor: const Color(0xFF6C63D5),
              label: 'fingerprint',
              value: snapshot.fingerprint,
              monospace: true,
              onCopy: () => onCopy(snapshot.fingerprint, 'Fingerprint'),
            ),
          if (snapshot.fingerprint.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: Color(0xFFE9EEF6)),
          if (snapshot.privateKey.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.key,
              iconColor: const Color(0xFF2E5ECC),
              label: 'private key',
              value: snapshot.privateKey,
              secret: true,
              badgeText: 'Protected',
              onCopy: () => onCopy(snapshot.privateKey, 'Private key'),
              onView: onViewPrivateKey,
            ),
          if (snapshot.privateKey.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: Color(0xFFE9EEF6)),
          if (snapshot.keyFileName.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.file_description,
              iconColor: const Color(0xFF5A78C5),
              label: 'key file name',
              value: snapshot.keyFileName,
              onCopy: () => onCopy(snapshot.keyFileName, 'Key file name'),
            ),
          if (snapshot.keyFileName.isNotEmpty && snapshot.passphrase.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: Color(0xFFE9EEF6)),
          if (snapshot.passphrase.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.shield_lock,
              iconColor: const Color(0xFFD97706),
              label: 'passphrase',
              value: snapshot.passphrase,
              secret: true,
              onCopy: () => onCopy(snapshot.passphrase, 'Passphrase'),
            ),
        ],
      ),
    );
  }
}

class _SshDetailPanelRow extends StatelessWidget {
  const _SshDetailPanelRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.secret = false,
    this.monospace = false,
    this.badgeText,
    this.onCopy,
    this.onView,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool secret;
  final bool monospace;
  final String? badgeText;
  final VoidCallback? onCopy;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final displayValue =
        secret ? '•' * math.max(10, math.min(40, value.length)) : value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: _CircularDetailIcon(
              icon: icon,
              color: iconColor,
              size: 28,
              iconSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: _text(
                    12,
                    const Color(0xFF6D63D6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: monospace ? 13 : 15,
                    color: const Color(0xFF1F2937),
                    fontWeight: FontWeight.w500,
                    fontFamily: monospace ? 'Menlo' : 'Ubuntu Sans',
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (badgeText != null) ...<Widget>[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF8EF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFCBE9D5)),
              ),
              child: Text(
                badgeText!,
                style: _text(
                  10,
                  const Color(0xFF15803D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (onView != null) ...<Widget>[
            const SizedBox(width: 8),
            _FlatRowAction(
              icon: TablerIcons.maximize,
              tooltip: 'View large',
              onTap: onView!,
            ),
          ],
          if (onCopy != null) ...<Widget>[
            const SizedBox(width: 8),
            _FlatRowAction(
              icon: TablerIcons.copy,
              tooltip: 'Copy',
              onTap: onCopy!,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  const _CategoryTag({
    required this.categoryName,
  });

  final String categoryName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _VaultColors.peachSoft,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _VaultColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            TablerIcons.folder,
            size: 12,
            color: _kPrimaryButtonColor,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              categoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(
                10,
                _VaultColors.title,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircularDetailIcon extends StatelessWidget {
  const _CircularDetailIcon({
    required this.icon,
    required this.color,
    this.size = 28,
    this.iconSize = 15,
    this.backgroundColor,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

class _EntryDateStats extends StatelessWidget {
  const _EntryDateStats({
    required this.createdAt,
    required this.updatedAt,
  });

  final String createdAt;
  final String updatedAt;

  @override
  Widget build(BuildContext context) {
    const labelColor = _VaultColors.headerLabel;
    const valueColor = Color(0xFF908D86);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _CircularDetailIcon(
            icon: TablerIcons.clock,
            color: Color(0xFF168B76),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _EntryDateStat(
              label: 'Created',
              value: createdAt,
              labelColor: labelColor,
              valueColor: valueColor,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _EntryDateStat(
              label: 'Updated',
              value: updatedAt,
              labelColor: labelColor,
              valueColor: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryDateStat extends StatelessWidget {
  const _EntryDateStat({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: _text(11, labelColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _text(14, valueColor, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _DetailCreditsBar extends StatelessWidget {
  const _DetailCreditsBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: _VaultColors.surfaceMuted,
        border: Border(
          top: BorderSide(color: _VaultColors.borderSoft),
        ),
      ),
      child: const Row(
        children: <Widget>[
          _CircularDetailIcon(
            icon: TablerIcons.info_circle,
            color: Color(0xFF6C63D5),
            size: 30,
            iconSize: 16,
          ),
          SizedBox(width: 10),
          Expanded(
            child: _SidebarBuildInfoLabel(),
          ),
          SizedBox(width: 20),
          SizedBox(
            width: 190,
            child: _VaultSyncStatusRow(),
          ),
        ],
      ),
    );
  }
}

class _FlatFieldLabel extends StatelessWidget {
  const _FlatFieldLabel({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _CircularDetailIcon(
          icon: icon,
          color: iconColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _text(
              11,
              labelColor ?? _VaultColors.headerLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FlatRowAction extends StatelessWidget {
  const _FlatRowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = _kPrimaryButtonColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _AppTooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.09),
        shape: CircleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: color.withValues(alpha: 0.16),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

class _EntryTagsRow extends StatelessWidget {
  const _EntryTagsRow({
    required this.tags,
  });

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags
          .where((tag) => tag.trim().isNotEmpty)
          .map(
            (tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F7),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFE4E7EC)),
              ),
              child: Text(
                '#${tag.trim()}',
                style: _text(
                  11,
                  const Color(0xFF98A2B3),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _FieldMenuOverlay extends StatelessWidget {
  const _FieldMenuOverlay({
    required this.link,
    required this.isPassword,
    required this.onDismiss,
    this.onViewLarge,
    this.onDuplicate,
    this.onRemove,
  });

  final LayerLink link;
  final bool isPassword;
  final VoidCallback onDismiss;
  final VoidCallback? onViewLarge;
  final VoidCallback? onDuplicate;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onDismiss,
        child: Stack(
          children: <Widget>[
            CompositedTransformFollower(
              link: link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 4),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: isPassword
                    ? _AttributeMenu(
                        items: <_MenuAction>[
                          _MenuAction(
                            label: 'View in large',
                            icon: TablerIcons.eye,
                            onTap: onViewLarge,
                          ),
                          const _MenuAction(
                            label: 'Copy Secret Reference',
                            icon: TablerIcons.copy,
                          ),
                        ],
                      )
                    : _AttributeMenu(
                        items: <_MenuAction>[
                          _MenuAction(
                            label: 'Duplicate',
                            icon: TablerIcons.copy,
                            onTap: onDuplicate,
                          ),
                          _MenuAction(
                            label: 'View in large',
                            icon: TablerIcons.eye,
                            onTap: onViewLarge,
                          ),
                          _MenuAction(
                            label: 'Remove',
                            icon: TablerIcons.trash,
                            onTap: onRemove,
                            isDestructive: true,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverActionButtons extends StatelessWidget {
  const _HoverActionButtons({
    required this.onCopyPressed,
    required this.menuOpen,
    required this.onArrowPressed,
  });

  final VoidCallback onCopyPressed;
  final bool menuOpen;
  final VoidCallback onArrowPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _FlatRowAction(
          icon: TablerIcons.copy,
          tooltip: 'Copy',
          onTap: onCopyPressed,
          color: const Color(0xFF2E6EDB),
        ),
        const SizedBox(width: 2),
        _NeutralOverflowAction(
          icon: menuOpen ? TablerIcons.chevron_up : TablerIcons.dots_vertical,
          tooltip: 'More actions',
          onTap: onArrowPressed,
        ),
      ],
    );
  }
}

class _NeutralOverflowAction extends StatelessWidget {
  const _NeutralOverflowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _AppTooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          hoverColor: _VaultColors.title.withValues(alpha: 0.06),
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 18, color: _VaultColors.icon),
          ),
        ),
      ),
    );
  }
}

const Color _kDetailCardSurface = Color(0xFFFFF5EE);
const Color _kDetailCardBorder = Color(0xFFEFD8C9);

class _FieldRowsSection extends StatelessWidget {
  const _FieldRowsSection({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _DetailCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.all(1),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kDetailCardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kDetailCardBorder),
      ),
      child: child,
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.hovered,
    required this.menuOpen,
    required this.showDivider,
    required this.onCopyPressed,
    required this.onHoverChanged,
    required this.onArrowPressed,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color? labelColor;
  final bool hovered;
  final bool menuOpen;
  final bool showDivider;
  final VoidCallback onCopyPressed;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onArrowPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: InkWell(
        onTap: onCopyPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          decoration: BoxDecoration(
            color: hovered ? _VaultColors.peachSoft : Colors.transparent,
            border: Border(
              bottom: showDivider
                  ? const BorderSide(color: _kDetailCardBorder)
                  : BorderSide.none,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _FlatFieldLabel(
                        icon: icon,
                        label: label,
                        iconColor: hovered ? _kPrimaryButtonColor : iconColor,
                        labelColor: labelColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Opacity(
                      opacity: hovered ? 1 : 0.82,
                      child: _HoverActionButtons(
                        onCopyPressed: onCopyPressed,
                        menuOpen: menuOpen,
                        onArrowPressed: onArrowPressed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: _text(
                      16,
                      _VaultColors.title,
                      fontWeight: FontWeight.w500,
                      height: 1.22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialLoginCard extends StatelessWidget {
  const _SocialLoginCard({
    required this.providerId,
    required this.domain,
    required this.username,
  });

  final String providerId;
  final String domain;
  final String username;

  String _getProviderName(String id) {
    switch (id.toLowerCase()) {
      case 'google':
        return 'Google';
      case 'apple':
        return 'Apple';
      case 'github':
        return 'GitHub';
      case 'facebook':
        return 'Facebook';
      case 'microsoft':
        return 'Microsoft';
      case 'twitter':
        return 'X (Twitter)';
      case 'linkedin':
        return 'LinkedIn';
      default:
        return id.isNotEmpty ? id[0].toUpperCase() + id.substring(1) : 'Social';
    }
  }

  String _getProviderFaviconUrl(String id) {
    final String domain;
    switch (id.toLowerCase()) {
      case 'google':
        domain = 'google.com';
      case 'apple':
        domain = 'apple.com';
      case 'facebook':
        domain = 'facebook.com';
      case 'github':
        domain = 'github.com';
      case 'microsoft':
        domain = 'microsoft.com';
      case 'twitter':
        domain = 'x.com';
      case 'linkedin':
        domain = 'linkedin.com';
      default:
        domain = '${id.toLowerCase()}.com';
    }
    return 'https://www.google.com/s2/favicons?sz=32&domain=$domain';
  }

  @override
  Widget build(BuildContext context) {
    final faviconUrl = _getProviderFaviconUrl(providerId);
    final displayDomain = domain.isNotEmpty
        ? (Uri.tryParse(domain)?.host.isNotEmpty == true
            ? Uri.tryParse(domain)!.host
            : domain)
        : _getProviderName(providerId);

    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD0D8E2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Sign in with',
              style: _text(
                10,
                const Color(0xFF6D63D6),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2EAF4)),
                  ),
                  alignment: Alignment.center,
                  child: ClipOval(
                    child: Image.network(
                      faviconUrl,
                      width: 20,
                      height: 20,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        TablerIcons.link,
                        size: 18,
                        color: Color(0xFF6D63D6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        displayDomain,
                        style: _text(
                          15,
                          const Color(0xFF1F2937),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (username.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 1),
                        Text(
                          username,
                          style: _text(
                            13,
                            const Color(0xFF6B7280),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
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

enum _PasswordStrength { weak, fair, good, strong }

_PasswordStrength _evalPasswordStrength(String password) {
  if (password.isEmpty) return _PasswordStrength.weak;
  int score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(password)) score++;
  if (RegExp(r'[a-z]').hasMatch(password)) score++;
  if (RegExp(r'[0-9]').hasMatch(password)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
  if (score <= 2) return _PasswordStrength.weak;
  if (score == 3) return _PasswordStrength.fair;
  if (score == 4) return _PasswordStrength.good;
  return _PasswordStrength.strong;
}

(
  String label,
  double score,
  Color ring,
  Color text,
) _strengthStyle(_PasswordStrength s) {
  switch (s) {
    case _PasswordStrength.weak:
      return ('Weak', 0.24, const Color(0xFFE5484D), const Color(0xFF667085));
    case _PasswordStrength.fair:
      return ('Fair', 0.48, const Color(0xFFF5A524), const Color(0xFF667085));
    case _PasswordStrength.good:
      return ('Good', 0.74, const Color(0xFF6CCB5F), const Color(0xFF667085));
    case _PasswordStrength.strong:
      return (
        'Very Good',
        0.90,
        const Color(0xFF56B54A),
        const Color(0xFF667085),
      );
  }
}

class _SecretFieldRow extends StatefulWidget {
  const _SecretFieldRow({
    required this.icon,
    required this.label,
    required this.secretValue,
    required this.iconColor,
    required this.hovered,
    required this.menuOpen,
    required this.showDivider,
    this.showVisibilityToggle = true,
    this.showStrength = false,
    required this.onCopyPressed,
    required this.onHoverChanged,
    required this.onArrowPressed,
  });

  final IconData icon;
  final String label;
  final String secretValue;
  final Color iconColor;
  final bool hovered;
  final bool menuOpen;
  final bool showDivider;
  final bool showVisibilityToggle;
  final bool showStrength;
  final VoidCallback onCopyPressed;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onArrowPressed;

  @override
  State<_SecretFieldRow> createState() => _SecretFieldRowState();
}

class _SecretFieldRowState extends State<_SecretFieldRow> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => widget.onHoverChanged(true),
      onExit: (_) => widget.onHoverChanged(false),
      child: InkWell(
        onTap: widget.onCopyPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          decoration: BoxDecoration(
            color: widget.hovered ? _VaultColors.peachSoft : Colors.transparent,
            border: Border(
              bottom: widget.showDivider
                  ? const BorderSide(color: _kDetailCardBorder)
                  : BorderSide.none,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _FlatFieldLabel(
                        icon: widget.icon,
                        label: widget.label,
                        iconColor: widget.hovered
                            ? _kPrimaryButtonColor
                            : const Color(0xFFD08316),
                      ),
                    ),
                    if (widget.showStrength) ...<Widget>[
                      const SizedBox(width: 10),
                      _PasswordStrengthIndicator(value: widget.secretValue),
                    ],
                    const SizedBox(width: 10),
                    Opacity(
                      opacity: widget.hovered ? 1 : 0.82,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (widget.showVisibilityToggle) ...<Widget>[
                            _FlatRowAction(
                              icon: _visible
                                  ? TablerIcons.eye_off
                                  : TablerIcons.eye,
                              tooltip:
                                  _visible ? 'Hide password' : 'Show password',
                              onTap: () => setState(() => _visible = !_visible),
                              color: const Color(0xFF168B76),
                            ),
                            const SizedBox(width: 4),
                          ],
                          _HoverActionButtons(
                            onCopyPressed: widget.onCopyPressed,
                            menuOpen: widget.menuOpen,
                            onArrowPressed: widget.onArrowPressed,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Text(
                    _visible
                        ? widget.secretValue
                        : '•' * math.max(10, widget.secretValue.length),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: _text(
                      _visible ? 16 : 18,
                      _VaultColors.title,
                      fontWeight: FontWeight.w500,
                      height: 1.22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordStrengthIndicator extends StatelessWidget {
  const _PasswordStrengthIndicator({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final strength = _evalPasswordStrength(value);
    final (label, score, ringColor, textColor) = _strengthStyle(strength);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: _text(11, textColor, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 5),
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value: score,
            strokeWidth: 2.2,
            backgroundColor: const Color(0xFFE4EAF2),
            valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            strokeCap: StrokeCap.round,
          ),
        ),
      ],
    );
  }
}

class _TotpRow extends StatelessWidget {
  const _TotpRow({
    required this.code,
    required this.secondsRemaining,
    required this.onCopyPressed,
  });

  final String code;
  final int secondsRemaining;
  final VoidCallback onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final countdownColor = _totpCountdownColor(secondsRemaining);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: countdownColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: countdownColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          _CircularDetailIcon(
            icon: TablerIcons.clock,
            color: countdownColor,
            size: 32,
            iconSize: 17,
          ),
          const SizedBox(width: 10),
          Text(
            'TOTP',
            style: _text(
              14,
              _VaultColors.headerLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            code,
            style: _text(
              26,
              countdownColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: countdownColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${secondsRemaining.toString().padLeft(2, '0')}s',
              style: _text(
                15,
                countdownColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: countdownColor.withValues(alpha: 0.10),
            shape: CircleBorder(
              side: BorderSide(
                color: countdownColor.withValues(alpha: 0.16),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onCopyPressed,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  TablerIcons.copy,
                  size: 17,
                  color: countdownColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({
    required this.attachments,
    required this.onAttachmentTap,
    required this.onAttachmentDownload,
  });

  final List<_MockAttachment> attachments;
  final ValueChanged<_MockAttachment> onAttachmentTap;
  final ValueChanged<_MockAttachment> onAttachmentDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const _CircularDetailIcon(
              icon: TablerIcons.paperclip,
              color: Color(0xFF5A78C5),
            ),
            const SizedBox(width: 8),
            Text(
              'Attachments',
              style: _text(
                13,
                _VaultColors.headerLabel,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${attachments.length})',
              style: _text(
                12,
                const Color(0xFF8A97AC),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const _CircularDetailIcon(
              icon: TablerIcons.upload,
              color: Color(0xFF5A78C5),
              size: 26,
              iconSize: 14,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final attachment in attachments) ...<Widget>[
          _AttachmentTile(
            attachment: attachment,
            onTap: () => onAttachmentTap(attachment),
            onDownload: () => onAttachmentDownload(attachment),
          ),
          if (attachment != attachments.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.onTap,
    required this.onDownload,
  });

  final _MockAttachment attachment;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFCFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F2)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: attachment.isImage
                    ? const Color(0xFFDCE5FA)
                    : const Color(0xFFEEF2F8),
                shape: BoxShape.circle,
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: attachment.isImage && attachment.bytes != null
                  ? Image.memory(
                      attachment.bytes!,
                      fit: BoxFit.cover,
                      width: 36,
                      height: 36,
                    )
                  : (attachment.isImage
                      ? const Icon(
                          TablerIcons.photo,
                          size: 18,
                          color: _VaultColors.icon,
                        )
                      : const Icon(
                          TablerIcons.file_description,
                          size: 18,
                          color: _VaultColors.icon,
                        )),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    attachment.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      13,
                      const Color(0xFF2B3444),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attachment.sizeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      12,
                      const Color(0xFF7B8CA6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            _FlatRowAction(
              icon: TablerIcons.download,
              tooltip: 'Download attachment',
              onTap: onDownload,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    this.iconColor = _VaultColors.icon,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _CircularDetailIcon(icon: icon, color: iconColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: _text(
            13,
            _VaultColors.headerLabel,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.label,
    required this.icon,
    this.onTap,
    this.isDestructive = false,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isFirst;
  final bool isLast;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  @override
  Widget build(BuildContext context) {
    final foregroundColor = widget.isDestructive
        ? const Color(0xFFD94A4A)
        : const Color(0xFF2B3444);
    final radius = BorderRadius.vertical(
      top: widget.isFirst ? const Radius.circular(12) : Radius.zero,
      bottom: widget.isLast ? const Radius.circular(12) : Radius.zero,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: radius,
        hoverColor: const Color(0xFFF4F6FA),
        highlightColor: const Color(0xFFEFF3F9),
        splashColor: Colors.transparent,
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: <Widget>[
                Icon(widget.icon, size: 15, color: foregroundColor),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: _text(
                    12,
                    foregroundColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuAction {
  const _MenuAction({
    required this.label,
    required this.icon,
    this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDestructive;
}

class _AttributeMenu extends StatelessWidget {
  const _AttributeMenu({
    required this.items,
  })  : primaryLabel = null,
        secondaryLabel = null,
        onPrimaryPressed = null,
        onSecondaryPressed = null,
        secondaryIsDestructive = false;

  // ignore: unused_element, unused_element_parameter
  const _AttributeMenu.legacy({
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
    required this.secondaryIsDestructive,
  }) : items = null;

  final List<_MenuAction>? items;
  final String? primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onPrimaryPressed;
  final VoidCallback? onSecondaryPressed;
  final bool secondaryIsDestructive;

  List<_MenuAction> get resolvedItems {
    if (items != null) {
      return items!;
    }

    final resolved = <_MenuAction>[];
    if (primaryLabel != null) {
      resolved.add(
        _MenuAction(
          label: primaryLabel!,
          icon: TablerIcons.copy,
          onTap: onPrimaryPressed,
        ),
      );
    }
    if (secondaryLabel != null) {
      resolved.add(
        _MenuAction(
          label: secondaryLabel!,
          icon: secondaryIsDestructive ? TablerIcons.trash : TablerIcons.copy,
          onTap: onSecondaryPressed,
          isDestructive: secondaryIsDestructive,
        ),
      );
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = resolvedItems;

    return Container(
      width: 218,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9DEE8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x141A2438),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < menuItems.length; index++) ...<Widget>[
            _MenuItem(
              label: menuItems[index].label,
              icon: menuItems[index].icon,
              onTap: menuItems[index].onTap,
              isDestructive: menuItems[index].isDestructive,
              isFirst: index == 0,
              isLast: index == menuItems.length - 1,
            ),
            if (index != menuItems.length - 1)
              const Divider(height: 1, color: Color(0xFFE8ECF3)),
          ],
        ],
      ),
    );
  }
}

class _LargeValueOverlay extends StatelessWidget {
  const _LargeValueOverlay({
    required this.label,
    required this.value,
    required this.onClose,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onClose;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dialogWidth = math.min(760.0, constraints.maxWidth - 48);
                final valueFieldHeight = math.min(
                  148.0,
                  math.max(104.0, constraints.maxHeight * 0.15),
                );

                return ColoredBox(
                  color: const Color(0x99F8FAFC),
                  child: SafeArea(
                    minimum: const EdgeInsets.all(24),
                    child: Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          width: dialogWidth,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE5EAF2)),
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
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: _text(
                                        20,
                                        const Color(0xFF202939),
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  _ActionIcon(
                                    TablerIcons.copy,
                                    onTap: onCopy,
                                    tooltip: 'Copy',
                                  ),
                                  const SizedBox(width: 8),
                                  _ActionIcon(
                                    TablerIcons.x,
                                    onTap: onClose,
                                    tooltip: 'Close',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'View the full value below.',
                                style: _text(
                                  14,
                                  const Color(0xFF4B5565),
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: valueFieldHeight,
                                child: TextFormField(
                                  initialValue: value,
                                  readOnly: true,
                                  autofocus: true,
                                  expands: true,
                                  maxLines: null,
                                  minLines: null,
                                  style: _text(
                                    18,
                                    const Color(0xFF182235),
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFE),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFD8E2F0),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFD8E2F0),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF9DB9F4),
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  FilledButton(
                                    onPressed: onCopy,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _kPrimaryButtonColor,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(144, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: Text(
                                      'Copy Value',
                                      style: _text(
                                        14,
                                        Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: onClose,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(120, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      side: const BorderSide(
                                        color: Color(0xFFD6DCE6),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: Text(
                                      'Close',
                                      style: _text(
                                        14,
                                        const Color(0xFF3E4A5E),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AppTooltip extends StatelessWidget {
  const _AppTooltip({
    required this.message,
    required this.child,
  });

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      textStyle: const TextStyle(
        fontSize: 12,
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontFamily: 'Ubuntu Sans',
      ),
      child: child,
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon(
    this.icon, {
    this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 16, color: _VaultColors.icon),
      ),
    );
    if (tooltip != null) {
      return _AppTooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

class _DetailMoreMenu extends StatelessWidget {
  const _DetailMoreMenu({
    required this.destructiveLabel,
    required this.onDelete,
  });

  final String destructiveLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      color: _VaultColors.surface,
      surfaceTintColor: _VaultColors.surface,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _VaultColors.borderSoft),
      ),
      onSelected: (value) {
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: <Widget>[
              const Icon(
                TablerIcons.trash,
                size: 16,
                color: _kDangerButtonColor,
              ),
              const SizedBox(width: 10),
              Text(
                destructiveLabel,
                style: _text(
                  11,
                  _kDangerButtonColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        child: const Icon(
          TablerIcons.dots_vertical,
          size: 19,
          color: _VaultColors.icon,
        ),
      ),
    );
  }
}

class _EmptyDetailPane extends StatelessWidget {
  const _EmptyDetailPane();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _VaultColors.canvas,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: _VaultColors.peachSoft,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: _VaultColors.borderSoft,
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x17000000),
                          blurRadius: 18,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      TablerIcons.shield_lock,
                      size: 34,
                      color: _kPrimaryButtonColor,
                    ),
                  ),

                  const SizedBox(height: 22),

                  Text(
                    'Your vault is empty',
                    style: _text(
                      15,
                      _VaultColors.title,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Add your first item using the\n"+ New Item" button above.',
                    textAlign: TextAlign.center,
                    style: _text(
                      12,
                      _VaultColors.headerLabel,
                      fontWeight: FontWeight.w400,
                      height: 1.65,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Item type pills
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: const <Widget>[
                      _EmptyTypePill(
                        icon: TablerIcons.key,
                        label: 'SSH Keys',
                        iconColor: Color(0xFF2E5ECC),
                      ),
                      _EmptyTypePill(
                        icon: TablerIcons.notebook,
                        label: 'Secure Notes',
                        iconColor: Color(0xFF6B5FC0),
                      ),
                      _EmptyTypePill(
                        icon: TablerIcons.fingerprint,
                        label: 'Passkeys',
                        iconColor: Color(0xFF0891B2),
                      ),
                      _EmptyTypePill(
                        icon: TablerIcons.id_badge_2,
                        label: 'Identities',
                        iconColor: Color(0xFF059669),
                      ),
                      _EmptyTypePill(
                        icon: TablerIcons.clock,
                        label: 'TOTP Codes',
                        iconColor: Color(0xFFD97706),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const _DetailCreditsBar(),
        ],
      ),
    );
  }
}

class _EmptyTypePill extends StatelessWidget {
  const _EmptyTypePill({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: _VaultColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _VaultColors.borderSoft),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: _text(
              11,
              _VaultColors.title,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaviconTile extends ConsumerStatefulWidget {
  const _FaviconTile({
    required this.entry,
    required this.size,
  });

  final _MockEntry entry;
  final double size;

  @override
  ConsumerState<_FaviconTile> createState() => _FaviconTileState();
}

/// Compiled once. Hot path used for every favicon tile build, so keep this
/// at file scope rather than re-instantiating per build.
final RegExp _kPrivateIpv4Regex =
    RegExp(r'^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.');

/// Per-entry cache for decoded favicon PNG bytes. The base64 payload on a
/// `_MockEntry` does not change for its lifetime, so memoizing the decode
/// avoids re-running `base64Decode` (and re-allocating a fresh `Uint8List`)
/// on every scroll-frame rebuild. Decoded bytes also reach the Flutter image
/// cache with a stable `Uint8List` identity, so the GPU upload happens once
/// per entry instead of every time the tile rebuilds.
final Expando<Uint8List> _kDecodedFaviconCache =
    Expando<Uint8List>('decodedFaviconBytes');

/// Sentinel stored in [_kDecodedFaviconCache] for entries whose payload
/// failed to decode, so we don't keep retrying base64Decode on every build.
final Uint8List _kFaviconDecodeFailedSentinel = Uint8List(0);

class _FaviconTileState extends ConsumerState<_FaviconTile> {
  bool _cacheUpdatePending = false;
  bool _persistQueued = false;

  static bool _isLocalHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '127.0.0.1' || h == '::1') return true;
    if (h.endsWith('.local')) return true;
    if (_kPrivateIpv4Regex.hasMatch(h)) return true;
    return false;
  }

  String? _faviconUrl() {
    final website = widget.entry.website.trim();
    if (website.isEmpty) return null;
    try {
      final uri =
          Uri.parse(website.contains('://') ? website : 'https://$website');
      if (uri.host.isEmpty) return null;
      if (_isLocalHost(uri.host)) return null;
      return 'https://www.google.com/s2/favicons?sz=32&domain=${uri.host}';
    } catch (_) {
      return null;
    }
  }

  void _scheduleCacheUpdate(String url, bool succeeded) {
    if (_cacheUpdatePending) return;
    _cacheUpdatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cacheUpdatePending = false;
      if (!mounted) return;
      ref.read(faviconFetchResultProvider.notifier).update((s) {
        if (s[url] == succeeded) return s;
        return {...s, url: succeeded};
      });
    });
  }

  /// Decodes the cached base64 PNG bytes — if present and valid. Returns
  /// null when there are no cached bytes, when the payload is the failure
  /// sentinel, or when decoding fails.
  ///
  /// The decoded `Uint8List` is memoized on the underlying `_MockEntry` via
  /// [_kDecodedFaviconCache]. This is critical for scroll smoothness: the
  /// quick-search overlay's row builder reaches this method on every frame,
  /// and decoding even a 32×32 PNG payload (~1–2 KB of base64) per row per
  /// frame stalls the raster thread. With memoization the decode happens
  /// exactly once per entry per app session.
  Uint8List? _cachedFaviconBytes() {
    final entry = widget.entry;
    final cached = _kDecodedFaviconCache[entry];
    if (cached != null) {
      return identical(cached, _kFaviconDecodeFailedSentinel) ? null : cached;
    }
    final payload = entry.faviconPngBase64;
    if (payload == null || payload.isEmpty) return null;
    if (payload == AppKdbxFieldKeys.faviconFailedSentinel) return null;
    try {
      final decoded = base64Decode(payload);
      _kDecodedFaviconCache[entry] = decoded;
      return decoded;
    } catch (_) {
      _kDecodedFaviconCache[entry] = _kFaviconDecodeFailedSentinel;
      return null;
    }
  }

  /// Persist a fetched favicon (or failure) onto the entry exactly once
  /// per tile lifetime. Guarded so a flurry of loadingBuilder ticks does
  /// not repeatedly hit the persistence service.
  void _schedulePersist(String url, bool succeeded) {
    if (_persistQueued) return;
    _persistQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = ref.read(faviconPersistenceServiceProvider);
      if (succeeded) {
        service.enqueue(entryUuid: widget.entry.uuid, faviconUrl: url);
      } else {
        service.recordFailure(entryUuid: widget.entry.uuid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemTypeVisual = _newItemTypeForVaultType(widget.entry.itemType);
    final autoFetchIcon = ref.watch(vaultAutoFetchItemIconProvider);
    // Scoped subscription: only rebuild this tile when THIS tile's URL
    // result flips in the favicon cache, instead of the entire map (which
    // would cascade a rebuild storm across every visible tile whenever any
    // single favicon finishes loading).
    final faviconUrl = _faviconUrl();
    final fetchResultForUrl = faviconUrl == null
        ? null
        : ref.watch(
            faviconFetchResultProvider.select((s) => s[faviconUrl]),
          );
    final useGeneratedTile = widget.entry.itemType == VaultItemType.login;
    final useCardBrandTile =
        widget.entry.itemType == VaultItemType.creditCard &&
            widget.entry.cardBrand != null;
    final useSshBadgeTile = widget.entry.itemType == VaultItemType.sshKey;
    final useBankBadgeTile = widget.entry.itemType == VaultItemType.bankAccount;
    final useIdentityBadgeTile =
        widget.entry.itemType == VaultItemType.identity;
    final useSecureNoteBadgeTile =
        widget.entry.itemType == VaultItemType.secureNote;

    if (useCardBrandTile) {
      return _CardBrandBadge(
        brand: widget.entry.cardBrand!,
        size: widget.size,
      );
    }

    if (useGeneratedTile) {
      final initialsWidget = Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.entry.tileColor,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.entry.initials,
          style: _text(
            11,
            widget.entry.tileTextColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

      final cachedPayload = widget.entry.faviconPngBase64;
      final hasFailedPersist =
          cachedPayload == AppKdbxFieldKeys.faviconFailedSentinel;
      final cachedBytes = _cachedFaviconBytes();
      final int decodePx = (widget.size * 2).ceil();

      // Fast path: we already saved this favicon onto the entry, so we
      // never touch the network again. `Image.memory` is decoded by
      // Flutter's image cache so subsequent scrolls are free.
      if (cachedBytes != null) {
        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              cachedBytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              cacheWidth: decodePx,
              cacheHeight: decodePx,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => initialsWidget,
            ),
          ),
        );
      }

      // Previous fetch permanently failed — don't retry, avoid extra net IO.
      if (hasFailedPersist) return initialsWidget;

      final hasBeenAttempted = faviconUrl != null && fetchResultForUrl != null;
      final wasFetchSuccessful = hasBeenAttempted && fetchResultForUrl == true;

      // Show favicon when:
      //   • previously fetched successfully → keep showing even if toggle is off.
      //   • toggle is on and URL has not been attempted yet → attempt now.
      // Never retry a URL that already failed (hasBeenAttempted && !wasFetchSuccessful).
      final shouldShowFavicon = faviconUrl != null &&
          (wasFetchSuccessful || (!hasBeenAttempted && autoFetchIcon));

      if (!shouldShowFavicon) return initialsWidget;

      final needsCacheUpdate = !hasBeenAttempted;
      // Cap raster decode to 2× logical size (roughly covers typical DPR
      // without decoding a huge upstream image), and isolate repaint so
      // the favicon decode doesn't invalidate siblings.

      // Use ResizeImage to cap decode size while maintaining better cache behavior
      final imageProvider = ResizeImage(
        NetworkImage(faviconUrl),
        width: decodePx,
        height: decodePx,
      );

      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image(
            image: imageProvider,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              // If the image loaded synchronously (from cache), show it immediately
              if (wasSynchronouslyLoaded || frame != null) {
                if (frame != null && needsCacheUpdate) {
                  _scheduleCacheUpdate(faviconUrl, true);
                  _schedulePersist(faviconUrl, true);
                }
                return child;
              }
              // Still loading - show initials
              return initialsWidget;
            },
            errorBuilder: (_, __, ___) {
              if (needsCacheUpdate) _scheduleCacheUpdate(faviconUrl, false);
              _schedulePersist(faviconUrl, false);
              return initialsWidget;
            },
          ),
        ),
      );
    }

    if (useSshBadgeTile) {
      return Image.asset(
        'assets/images/item_type_ssh.png',
        width: widget.size,
        height: widget.size,
        errorBuilder: (_, __, ___) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: itemTypeVisual?.iconColor.withValues(alpha: 0.18) ??
                widget.entry.tileColor,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(
            TablerIcons.prompt,
            size: widget.size * 0.58,
            color: const Color(0xFF5D6F88),
          ),
        ),
      );
    }

    if (useBankBadgeTile) {
      return Image.asset(
        'assets/images/item_type_bank.png',
        width: widget.size,
        height: widget.size,
        errorBuilder: (_, __, ___) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: itemTypeVisual?.iconColor.withValues(alpha: 0.18) ??
                widget.entry.tileColor,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(
            itemTypeVisual?.icon ?? TablerIcons.building_bank,
            size: widget.size * 0.58,
            color: itemTypeVisual?.iconColor ?? widget.entry.tileTextColor,
          ),
        ),
      );
    }

    if (useIdentityBadgeTile) {
      return Image.asset(
        'assets/images/item_type_identity.png',
        width: widget.size,
        height: widget.size,
        errorBuilder: (_, __, ___) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: itemTypeVisual?.iconColor.withValues(alpha: 0.18) ??
                widget.entry.tileColor,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(
            itemTypeVisual?.icon ?? TablerIcons.id,
            size: widget.size * 0.58,
            color: itemTypeVisual?.iconColor ?? widget.entry.tileTextColor,
          ),
        ),
      );
    }

    if (useSecureNoteBadgeTile) {
      return Image.asset(
        'assets/images/item_type_note.png',
        width: widget.size,
        height: widget.size,
        errorBuilder: (_, __, ___) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: itemTypeVisual?.iconColor.withValues(alpha: 0.18) ??
                widget.entry.tileColor,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(
            itemTypeVisual?.icon ?? TablerIcons.notes,
            size: widget.size * 0.58,
            color: itemTypeVisual?.iconColor ?? widget.entry.tileTextColor,
          ),
        ),
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: itemTypeVisual?.iconColor.withValues(alpha: 0.18) ??
            widget.entry.tileColor,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(
        itemTypeVisual?.icon ?? TablerIcons.file_description,
        size: widget.size * 0.58,
        color: itemTypeVisual?.iconColor ?? widget.entry.tileTextColor,
      ),
    );
  }
}

class _CardBrandBadge extends StatelessWidget {
  const _CardBrandBadge({
    required this.brand,
    required this.size,
  });

  final _CardBrand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (brand) {
      case _CardBrand.visa:
        return _BrandTextTile(
          size: size,
          background: const LinearGradient(
            colors: <Color>[Color(0xFF1F63D6), Color(0xFF1349AF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'VISA',
          labelColor: Colors.white,
          fontSize: size * 0.27,
          fontWeight: FontWeight.w800,
        );
      case _CardBrand.mastercard:
        return _BrandMastercardTile(size: size);
      case _CardBrand.amex:
        return _BrandTextTile(
          size: size,
          background: const LinearGradient(
            colors: <Color>[Color(0xFF4CC4F0), Color(0xFF1596D1)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'AMEX',
          labelColor: Colors.white,
          fontSize: size * 0.22,
          fontWeight: FontWeight.w800,
        );
      case _CardBrand.discover:
        return _BrandDiscoverTile(size: size);
      case _CardBrand.diners:
        return _BrandTextTile(
          size: size,
          background: const LinearGradient(
            colors: <Color>[Color(0xFF1B75BC), Color(0xFF0C4C7F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'DINERS',
          labelColor: Colors.white,
          fontSize: size * 0.18,
          fontWeight: FontWeight.w800,
        );
      case _CardBrand.jcb:
        return _BrandJcbTile(size: size);
      case _CardBrand.unionPay:
        return _BrandTextTile(
          size: size,
          background: const LinearGradient(
            colors: <Color>[Color(0xFF1A56B0), Color(0xFF0E2E75)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'UP',
          labelColor: Colors.white,
          fontSize: size * 0.28,
          fontWeight: FontWeight.w800,
        );
      case _CardBrand.maestro:
        return _BrandMaestroTile(size: size);
    }
  }
}

class _BrandTextTile extends StatelessWidget {
  const _BrandTextTile({
    required this.size,
    required this.background,
    required this.label,
    required this.labelColor,
    required this.fontSize,
    required this.fontWeight,
  });

  final double size;
  final Gradient background;
  final String label;
  final Color labelColor;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: background,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: _text(
          fontSize,
          labelColor,
          fontWeight: fontWeight,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _BrandMastercardTile extends StatelessWidget {
  const _BrandMastercardTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            left: size * 0.21,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: const BoxDecoration(
                color: Color(0xFFEA5B2A),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: size * 0.21,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: const BoxDecoration(
                color: Color(0xFFF7A400),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandDiscoverTile extends StatelessWidget {
  const _BrandDiscoverTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: size * 0.16,
            top: size * 0.22,
            child: Text(
              'DISC',
              style: _text(
                size * 0.18,
                const Color(0xFF1F2937),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            right: size * 0.12,
            bottom: size * 0.18,
            child: Container(
              width: size * 0.3,
              height: size * 0.14,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFEA5B2A), Color(0xFFF7A400)],
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandJcbTile extends StatelessWidget {
  const _BrandJcbTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    Widget stripe(String label, List<Color> colors) {
      return Expanded(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: _text(
              size * 0.16,
              Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      padding: EdgeInsets.all(size * 0.16),
      child: Row(
        children: <Widget>[
          stripe('J', const <Color>[Color(0xFF007940), Color(0xFF00A86B)]),
          SizedBox(width: size * 0.05),
          stripe('C', const <Color>[Color(0xFF005BAC), Color(0xFF1A73E8)]),
          SizedBox(width: size * 0.05),
          stripe('B', const <Color>[Color(0xFFD6001C), Color(0xFFEF4444)]),
        ],
      ),
    );
  }
}

class _BrandMaestroTile extends StatelessWidget {
  const _BrandMaestroTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1E4DB7), Color(0xFF122E75)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        'MAE',
        style: _text(
          size * 0.18,
          Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SshAgentSetupBanner extends StatelessWidget {
  const _SshAgentSetupBanner({
    required this.enabled,
    required this.onOpenSettings,
  });

  final bool enabled;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final bgColor = enabled ? const Color(0xFF1E7A43) : const Color(0xFF2E5ECC);
    final title = enabled ? 'SSH Agent is On' : 'SSH Agent is Off';
    final description = enabled
        ? 'LumenPass can now help terminals and developer tools authenticate to SSH servers with your saved keys.'
        : 'Turn on SSH Agent to let compatible applications sign in to SSH servers seamlessly with your saved keys.';
    final buttonLabel =
        enabled ? 'Manage SSH Agent Setting.' : 'Open SSH Agent Setting.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _CircularDetailIcon(
                icon: TablerIcons.sparkles,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: _text(
                    14,
                    Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: _text(
              13,
              const Color(0xFFE8EEFF),
              fontWeight: FontWeight.w400,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onOpenSettings,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF2E5ECC),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              buttonLabel,
              style: _text(
                12,
                enabled ? const Color(0xFF1E7A43) : const Color(0xFF2E5ECC),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasskeyBanner extends StatelessWidget {
  const _PasskeyBanner({
    required this.onRemovePasskey,
  });

  final VoidCallback onRemovePasskey;

  static const Color _bg = Color(0xFF6B5FC0);
  static const Color _textMain = Color(0xFFFFFFFF);
  static const Color _textDesc = Color(0xFFDDD8F5);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _CircularDetailIcon(
                icon: TablerIcons.chevron_down,
                color: _textMain,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Passkey Created',
                  style: _text(
                    14,
                    _textMain,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/passkey_icon.png',
                    width: 20,
                    height: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You can now use Passkey to login to your account seamlessly without using password.',
            style: _text(
              13,
              _textDesc,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _PasskeyBannerButton(
                label: 'Remove Passkey',
                filled: false,
                onPressed: onRemovePasskey,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PasskeyBannerButton extends StatefulWidget {
  const _PasskeyBannerButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  State<_PasskeyBannerButton> createState() => _PasskeyBannerButtonState();
}

class _PasskeyBannerButtonState extends State<_PasskeyBannerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.filled
                ? (_hovered ? const Color(0xFFECE9FF) : const Color(0xFFFFFFFF))
                : (_hovered ? const Color(0x33FFFFFF) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: widget.filled
                ? null
                : Border.all(color: const Color(0x99FFFFFF)),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: _text(
              12,
              widget.filled ? const Color(0xFF6B5FC0) : const Color(0xFFFFFFFF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeakPasswordBanner extends StatelessWidget {
  const _WeakPasswordBanner({
    required this.onChangePassword,
  });

  final VoidCallback onChangePassword;

  static const Color _bg = Color(0xFFD85A3B);
  static const Color _textMain = Color(0xFFFFFFFF);
  static const Color _textDesc = Color(0xFFFFE4D6);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _CircularDetailIcon(
                icon: TablerIcons.chevron_down,
                color: _textMain,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weak password',
                  style: _text(
                    14,
                    _textMain,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const _CircularDetailIcon(
                icon: TablerIcons.alert_circle,
                color: _textMain,
                size: 30,
                iconSize: 17,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "This password could be stronger. Consider updating it to protect your account.",
            style: _text(
              13,
              _textDesc,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _WeakPasswordBannerButton(
                label: 'Open Website',
                filled: true,
                onPressed: onChangePassword,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeakPasswordBannerButton extends StatefulWidget {
  const _WeakPasswordBannerButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  State<_WeakPasswordBannerButton> createState() =>
      _WeakPasswordBannerButtonState();
}

class _WeakPasswordBannerButtonState extends State<_WeakPasswordBannerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.filled
                ? (_hovered ? const Color(0xFFFFF5F0) : const Color(0xFFFFFFFF))
                : (_hovered ? const Color(0x33FFFFFF) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: widget.filled
                ? null
                : Border.all(color: const Color(0x99FFFFFF)),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: _text(
              12,
              widget.filled ? const Color(0xFFD85A3B) : const Color(0xFFFFFFFF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin wrapper around [_TotpRow] that self-subscribes to the shared
/// [_TimeScope] ticker so only this leaf rebuilds on each 1-second tick —
/// not the surrounding detail pane / column / scroll view. This is the
/// hottest per-second rebuild in the vault screen; keeping its scope tiny
/// is critical for UI responsiveness after unlock.
class _LiveTotpRow extends StatelessWidget {
  const _LiveTotpRow({
    required this.entry,
    required this.onCopyTotp,
  });

  final _MockEntry entry;
  final Future<void> Function(String value, String label) onCopyTotp;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: _TimeScope.of(context),
      builder: (context, currentTime, _) {
        final code = _formattedTotpCode(entry, currentTime);
        final secondsRemaining = _totpSecondsRemaining(entry, currentTime);
        return _TotpRow(
          code: code,
          secondsRemaining: secondsRemaining,
          onCopyPressed: () => onCopyTotp(code, 'TOTP code'),
        );
      },
    );
  }
}
