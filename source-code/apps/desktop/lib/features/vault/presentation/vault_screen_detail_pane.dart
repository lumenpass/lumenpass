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
    this.imagePath,
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

  /// Colorful artwork for this field, when one exists for its concept.
  final String? imagePath;
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
            imagePath: field.imagePath,
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

  Widget? _buildFieldsCard(
    List<_DetailField> fields, {
    Widget? trailing,
    Widget? leading,
  }) {
    if (fields.isEmpty && trailing == null && leading == null) {
      return null;
    }

    final lastField =
        trailing == null && fields.isNotEmpty ? fields.last : null;
    final hideCardNumber = ref.watch(vaultHideCreditCardNumberProvider);

    return _FieldRowsSection(
      children: <Widget>[
        if (leading != null) leading,
        for (final field in fields)
          CompositedTransformTarget(
            link: field.layerLink,
            child: field.isSecret
                ? _SecretFieldRow(
                    icon: field.icon,
                    label: field.label,
                    secretValue: field.value,
                    iconColor: field.iconColor,
                    imagePath: field.imagePath,
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
                    imagePath: field.imagePath,
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
        if (trailing != null) trailing,
      ],
    );
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
            imagePath: field.imagePath,
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
    final websiteUrl = widget.entry.website.trim();
    final hasWebsite = websiteUrl.isNotEmpty;
    final parsedWebsiteHost =
        hasWebsite ? Uri.tryParse(websiteUrl)?.host ?? '' : '';
    final websiteHost =
        parsedWebsiteHost.isNotEmpty ? parsedWebsiteHost : websiteUrl;
    final itemTypeVisual = _newItemTypeForVaultType(widget.entry.itemType);
    final itemTypeLabel = itemTypeVisual?.label ?? 'Secure item';
    final itemTypeColor = itemTypeVisual?.iconColor ?? _kPrimaryButtonColor;
    final itemTypeIcon = itemTypeVisual?.icon ?? TablerIcons.file_description;
    final accent = _detailAccentFor(widget.entry, itemTypeColor);
    final isSshAgentEnabled = ref.watch(sshAgentEnabledProvider);
    final activeDb = ref.watch(activeDatabaseProvider);
    final isInTrash = activeDb != null &&
        (_findGroupInTree(activeDb.rootGroup, widget.entry.groupUuid)
                ?.isRecycleBin ??
            false);
    final isSshKey = widget.entry.itemType == VaultItemType.sshKey;
    final hasTotp = widget.entry.totpAuthUrl.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[PERF] _DetailPane.build synchronous portion took '
          '${buildSw.elapsedMicroseconds / 1000}ms '
          '(fields=${_fields.length}, uuid=${widget.entry.uuid})');
    });

    Widget inset(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kDetailSideInset),
          child: child,
        );

    // The passkey gets a prominent banner above the credentials card: it is
    // a headline credential worth calling out, matching the pre-redesign
    // layout. The social sign-in renders as the first row of the grouped
    // fields card instead of a separate card above it.
    final socialLoginRow = (!isSshKey && widget.entry.socialProvider.isNotEmpty)
        ? _SocialLoginDetailRow(
            providerId: widget.entry.socialProvider,
            domain: widget.entry.website,
            showDivider: _fields.isNotEmpty,
          )
        : null;
    final fieldsCard = _buildFieldsCard(
      isSshKey
          ? _fields
              .where((field) => !_isSshCoreField(field))
              .toList(growable: false)
          : _fields,
      leading: socialLoginRow,
    );
    final totpRow = hasTotp
        ? inset(
            _LiveTotpRow(
              entry: widget.entry,
              onCopyTotp: _copyToClipboard,
            ),
          )
        : null;

    final sections = <Widget>[
      if (widget.entry.hasPasskeyChip && !_passkeyBannerIgnored)
        inset(
          _PasskeyBanner(
            onRemovePasskey: widget.onRequestRemovePasskey,
            onDismiss: () =>
                setState(() => _passkeyBannerIgnored = true),
          ),
        ),
      if (_shouldShowWeakPasswordBanner())
        inset(
          _WeakPasswordBanner(
            onChangePassword: () async {
              final url = Uri.parse(widget.entry.website);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),
      if (isSshKey) ...<Widget>[
        inset(
          _SshAgentSetupBanner(
            enabled: isSshAgentEnabled,
            onOpenSettings: widget.onOpenSshAgentSettings,
          ),
        ),
        inset(
          _SshDetailPanel(
            snapshot: _buildSshSnapshot(),
            onCopy: _copyToClipboard,
            onViewPrivateKey: () {
              final privateKey = _findFieldValue(
                const <String>['private key'],
              );
              if (privateKey.isEmpty) {
                return;
              }
              _openLargeView('Private Key', privateKey);
            },
          ),
        ),
        if (fieldsCard != null) inset(fieldsCard),
        if (totpRow != null) totpRow,
      ] else ...<Widget>[
        if (totpRow != null) totpRow,
        if (fieldsCard != null) inset(fieldsCard),
      ],
      if (widget.entry.notes.trim().isNotEmpty)
        inset(
          _DetailCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: _SectionLabel(
                          icon: TablerIcons.notes,
                          imagePath: 'assets/images/ic_notes_color.png',
                          label: 'Notes',
                          iconColor: DcColors.amberOnLight,
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
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 36),
                    child: SelectableText(
                      widget.entry.notes,
                      style: _text(
                        13,
                        _DetailPalette.ink,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (_resolvedAttachments.isNotEmpty)
        inset(
          _DetailCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _AttachmentsSection(
                attachments: _resolvedAttachments,
                onAttachmentTap: _openImagePreview,
                onAttachmentDownload: _downloadAttachment,
              ),
            ),
          ),
        ),
      inset(
        _DetailMetaFooter(
          createdAt: widget.entry.createdAt,
          updatedAt: widget.entry.updatedAt,
          tags: widget.entry.tags,
          formatExact: _formatDateTime,
        ),
      ),
    ];

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissMenu,
        child: Container(
          color: _DetailPalette.canvas,
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  _DetailHeader(
                    entry: widget.entry,
                    accent: accent,
                    websiteHost: websiteHost,
                    websiteUrl: websiteUrl,
                    itemTypeLabel: itemTypeLabel,
                    itemTypeIcon: itemTypeIcon,
                    itemTypeColor: itemTypeColor,
                    itemTypeImagePath: itemTypeVisual?.imagePath,
                    categoryName: categoryName,
                    actions: <Widget>[
                      if (!isInTrash && _canScanTotp) ...<Widget>[
                        _DetailHeaderAction(
                          icon: TablerIcons.scan,
                          imagePath: 'assets/images/ic_scan_color.png',
                          tooltip: 'Scan 2FA code',
                          color: _DetailPalette.indigo,
                          onPressed: widget.onOpenScanTotp,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (isInTrash)
                        _DetailHeaderAction(
                          icon: TablerIcons.restore,
                          tooltip: 'Recover item',
                          color: DcColors.tealOnLight,
                          onPressed: widget.onRequestRestore,
                        )
                      else
                        _DetailHeaderAction(
                          icon: TablerIcons.edit,
                          imagePath: 'assets/images/ic_edit_color.png',
                          tooltip: 'Edit item',
                          color: DcColors.selection,
                          onPressed: widget.onOpenEditItem,
                        ),
                      const SizedBox(width: 6),
                      _DetailMoreMenu(
                        destructiveLabel:
                            isInTrash ? 'Delete permanently' : 'Delete item',
                        onDelete: isInTrash
                            ? widget.onRequestPermanentDelete
                            : widget.onRequestDelete,
                      ),
                    ],
                  ),
                  Expanded(
                    child: ScrollbarTheme(
                      data: const ScrollbarThemeData(
                        thumbColor: WidgetStatePropertyAll<Color>(
                          _DetailPalette.lineStrong,
                        ),
                        trackColor: WidgetStatePropertyAll<Color>(
                          Colors.transparent,
                        ),
                        trackBorderColor: WidgetStatePropertyAll<Color>(
                          Colors.transparent,
                        ),
                      ),
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        interactive: true,
                        thickness: _scrollbarThickness,
                        radius: const Radius.circular(999),
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(
                            context,
                          ).copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(top: 4, bottom: 28),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: _kDetailContentMaxWidth,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    for (var i = 0;
                                        i < sections.length;
                                        i++) ...<Widget>[
                                      if (i > 0)
                                        const SizedBox(
                                          height: _kDetailSectionGap,
                                        ),
                                      sections[i],
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
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

// ── Detail layout constants ─────────────────────────────────────────────────

/// Content column cap so rows do not stretch across very wide windows.
const double _kDetailContentMaxWidth = 720;

/// Horizontal inset shared by the header and every content section.
const double _kDetailSideInset = 20;

/// Vertical rhythm between content sections.
const double _kDetailSectionGap = 16;

/// Accent colors for login avatars and the header wash. All of them keep
/// white initials readable (WCAG AA for large text).
const List<Color> _kDetailAccentPalette = <Color>[
  Color(0xFF3882C2),
  Color(0xFF1F8A7D),
  Color(0xFF4F5BD5),
  Color(0xFFD9673A),
  Color(0xFFC2477A),
  Color(0xFF2F9E5B),
  Color(0xFF8A63D2),
  Color(0xFFB7791F),
];

/// Stable per-item accent: logins get a color derived from their title,
/// every other item type uses its type color.
Color _detailAccentFor(_MockEntry entry, Color itemTypeColor) {
  if (entry.itemType != VaultItemType.login) {
    return itemTypeColor;
  }
  final seed = entry.title.trim().toLowerCase();
  if (seed.isEmpty) {
    return _kDetailAccentPalette.first;
  }
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _kDetailAccentPalette[hash % _kDetailAccentPalette.length];
}

/// One or two uppercase letters for the large header avatar.
String _detailAvatarInitials(String title) {
  final words = title
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    return words.first.substring(0, 1).toUpperCase();
  }
  return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
}

String _formatDetailDate(DateTime value) {
  return '${value.day} ${_monthAbbr[value.month - 1]} ${value.year}';
}

String _relativeTimeLabel(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(value);
  if (diff.isNegative) {
    return _formatDetailDate(value);
  }
  String plural(int count, String unit) =>
      '$count $unit${count == 1 ? '' : 's'} ago';
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return plural(diff.inMinutes, 'minute');
  if (diff.inDays < 1) return plural(diff.inHours, 'hour');
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return plural(diff.inDays, 'day');
  if (diff.inDays < 30) return plural(diff.inDays ~/ 7, 'week');
  if (diff.inDays < 365) return plural(diff.inDays ~/ 30, 'month');
  return plural(diff.inDays ~/ 365, 'year');
}

// ── Header ──────────────────────────────────────────────────────────────────

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.entry,
    required this.accent,
    required this.websiteHost,
    required this.websiteUrl,
    required this.itemTypeLabel,
    required this.itemTypeIcon,
    required this.itemTypeColor,
    required this.categoryName,
    required this.actions,
    this.itemTypeImagePath,
  });

  final _MockEntry entry;
  final Color accent;
  final String websiteHost;
  final String websiteUrl;
  final String itemTypeLabel;
  final IconData itemTypeIcon;
  final Color itemTypeColor;
  final String? categoryName;
  final List<Widget> actions;

  /// Colorful artwork for the entry's item type, shown in the type pill.
  final String? itemTypeImagePath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _kDetailContentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              _kDetailSideInset,
              22,
              _kDetailSideInset,
              18,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _DetailAvatar(entry: entry, accent: accent),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: 2),
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          22,
                          _DetailPalette.ink,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (websiteHost.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        _DetailWebsiteLink(
                          host: websiteHost,
                          url: websiteUrl,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          _DetailPill(
                            icon: itemTypeIcon,
                            label: itemTypeLabel,
                            color: itemTypeColor,
                            imagePath: itemTypeImagePath,
                          ),
                          if (categoryName != null)
                            _DetailPill(
                              icon: TablerIcons.folder,
                              label: categoryName!,
                              color: DcColors.selection,
                              outlined: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailAvatar extends StatelessWidget {
  const _DetailAvatar({required this.entry, required this.accent});

  static const double _size = 56;

  final _MockEntry entry;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // No backing card: the tile fills the slot itself (gradient initials,
    // brand badge, favicon image) or is transparent full-bleed artwork, so
    // the header matches the bare tiles used in the list rows.
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: _FaviconTile(entry: entry, size: _size, accent: accent),
    );
  }
}

class _DetailWebsiteLink extends StatefulWidget {
  const _DetailWebsiteLink({required this.host, required this.url});

  final String host;
  final String url;

  @override
  State<_DetailWebsiteLink> createState() => _DetailWebsiteLinkState();
}

class _DetailWebsiteLinkState extends State<_DetailWebsiteLink> {
  bool _hovered = false;

  Future<void> _open() async {
    final raw = widget.url;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null) {
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AppTooltip(
      message: 'Open website',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: _open,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  widget.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    13,
                    DcColors.selection,
                    fontWeight: FontWeight.w500,
                  ).copyWith(
                    decoration: _hovered
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationColor: DcColors.selection,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                TablerIcons.arrow_up_right,
                size: 13,
                color: DcColors.selection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({
    required this.icon,
    required this.label,
    required this.color,
    this.outlined = false,
    this.imagePath,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool outlined;

  /// Colorful artwork rendered instead of [icon] when available.
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color:
            outlined ? _DetailPalette.surface : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: outlined ? Border.all(color: _DetailPalette.line) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (imagePath != null)
            SizedBox(
              width: 14,
              height: 14,
              child: Image.asset(
                imagePath!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) =>
                    Icon(icon, size: 12, color: color),
              ),
            )
          else
            Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(
                11,
                _DetailPalette.ink,
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

/// Uniform 34 px header button: white, hairline border, colored glyph.
class _DetailHeaderAction extends StatefulWidget {
  const _DetailHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.imagePath,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  /// Colorful artwork shown instead of [icon] when set.
  final String? imagePath;

  @override
  State<_DetailHeaderAction> createState() => _DetailHeaderActionState();
}

class _DetailHeaderActionState extends State<_DetailHeaderAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return _AppTooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: _DetailHeaderButtonFace(
              hovered: _hovered,
              child: widget.imagePath != null
                  ? Image.asset(
                      widget.imagePath!,
                      width: 16,
                      height: 16,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) =>
                          Icon(widget.icon, size: 16, color: widget.color),
                    )
                  : Icon(widget.icon, size: 16, color: widget.color),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailHeaderButtonFace extends StatelessWidget {
  const _DetailHeaderButtonFace({required this.hovered, required this.child});

  final bool hovered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Rendered raw: no bordered button face — just the glyph, with the
    // hover state kept only for accessibility feedback.
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: hovered ? 0.6 : 1,
      child: child,
    );
  }
}

// ── Rows ────────────────────────────────────────────────────────────────────

/// Shared credential row: label above value, copy/more appear on hover and
/// a short "Copied" confirmation replaces them after a copy.
class _DetailValueRow extends StatefulWidget {
  const _DetailValueRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.hovered,
    required this.menuOpen,
    required this.showDivider,
    required this.onCopy,
    required this.onHoverChanged,
    required this.onMore,
    this.labelColor,
    this.imagePath,
    this.persistentActions = const <Widget>[],
    this.footer,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;

  /// Colorful artwork that replaces [icon] when the field has one.
  final String? imagePath;
  final Widget value;
  final bool hovered;
  final bool menuOpen;
  final bool showDivider;
  final VoidCallback onCopy;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onMore;
  final List<Widget> persistentActions;
  final Widget? footer;

  @override
  State<_DetailValueRow> createState() => _DetailValueRowState();
}

class _DetailValueRowState extends State<_DetailValueRow> {
  Timer? _copiedTimer;
  bool _copied = false;

  void _handleCopy() {
    widget.onCopy();
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showActions = widget.hovered || widget.menuOpen;
    return MouseRegion(
      onEnter: (_) => widget.onHoverChanged(true),
      onExit: (_) => widget.onHoverChanged(false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleCopy,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: widget.showDivider
                    ? const BorderSide(color: _kDetailCardBorder)
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: <Widget>[
                _CircularDetailIcon(
                  icon: widget.icon,
                  color: widget.iconColor,
                  imagePath: widget.imagePath,
                  size: 32,
                  iconSize: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          11,
                          widget.labelColor ?? _DetailPalette.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      widget.value,
                      if (widget.footer != null) ...<Widget>[
                        const SizedBox(height: 7),
                        widget.footer!,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ...widget.persistentActions,
                if (_copied)
                  const _CopiedBadge()
                else
                  AnimatedOpacity(
                    opacity: showActions ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: IgnorePointer(
                      ignoring: !showActions,
                      child: _HoverActionButtons(
                        onCopyPressed: _handleCopy,
                        menuOpen: widget.menuOpen,
                        onArrowPressed: widget.onMore,
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

class _CopiedBadge extends StatelessWidget {
  const _CopiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: DcColors.tealOnLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(TablerIcons.check, size: 13, color: DcColors.tealOnLight),
          const SizedBox(width: 4),
          Text(
            'Copied',
            style: _text(
              11,
              DcColors.tealOnLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final strength = _evalPasswordStrength(value);
    final (label, _, color, _) = _strengthStyle(strength);
    final filled = switch (strength) {
      _PasswordStrength.weak => 1,
      _PasswordStrength.fair => 2,
      _PasswordStrength.good => 3,
      _PasswordStrength.strong => 4,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < 4; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 3),
          Container(
            width: 26,
            height: 4,
            decoration: BoxDecoration(
              color: i < filled ? color : _DetailPalette.line,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Text(
          label,
          style: _text(11, _DetailPalette.muted, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Prominent "Passkey Created" banner above the credentials card. Removing
/// the passkey is a button here instead of being tucked behind an overflow
/// menu.
class _PasskeyBanner extends StatelessWidget {
  const _PasskeyBanner({
    required this.onRemovePasskey,
    required this.onDismiss,
  });

  final VoidCallback onRemovePasskey;
  final VoidCallback onDismiss;

  static const Color _bg = Color(0xFF6B5FC0);
  static const Color _textDesc = Color(0xFFDDD8F5);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
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
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => const Icon(
                      TablerIcons.fingerprint,
                      size: 16,
                      color: _bg,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Passkey Created',
                  style: _text(
                    14,
                    Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _PasskeyBannerButton(
                icon: TablerIcons.x,
                tooltip: 'Dismiss banner',
                filled: false,
                onPressed: onDismiss,
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
                filled: true,
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
    this.label,
    this.icon,
    this.tooltip,
    required this.filled,
    required this.onPressed,
  }) : assert((label == null) != (icon == null));

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final bool filled;
  final VoidCallback onPressed;

  @override
  State<_PasskeyBannerButton> createState() => _PasskeyBannerButtonState();
}

class _PasskeyBannerButtonState extends State<_PasskeyBannerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.label == null ? 24 : 30,
          padding: EdgeInsets.symmetric(
            horizontal: widget.label == null ? 4 : 14,
          ),
          decoration: BoxDecoration(
            // Filled is the solid white action; outline is the translucent
            // white ghost used for the quiet dismiss control.
            color: widget.filled
                ? (_hovered ? const Color(0xFFECE9FF) : Colors.white)
                : (_hovered ? const Color(0x33FFFFFF) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: widget.filled
                ? null
                : Border.all(color: const Color(0x99FFFFFF)),
          ),
          alignment: Alignment.center,
          child: widget.label != null
              ? Text(
                  widget.label!,
                  style: _text(
                    12,
                    _PasskeyBanner._bg,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Icon(
                  widget.icon,
                  size: 14,
                  color: Colors.white,
                ),
        ),
      ),
    );

    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

// ── Footer ──────────────────────────────────────────────────────────────────

/// Quiet metadata line closing the pane: tags, created and last-updated.
class _DetailMetaFooter extends StatelessWidget {
  const _DetailMetaFooter({
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    required this.formatExact,
  });

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> tags;
  final String Function(DateTime?) formatExact;

  @override
  Widget build(BuildContext context) {
    final visibleTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    final metaStyle = _text(12, _DetailPalette.muted);
    final created = createdAt;
    final updated = updatedAt;
    final stamps = <Widget>[
      if (created != null)
        _AppTooltip(
          message: formatExact(created),
          child:
              Text('Created ${_formatDetailDate(created)}', style: metaStyle),
        ),
      if (updated != null)
        _AppTooltip(
          message: formatExact(updated),
          child: Text(
            'Updated ${_relativeTimeLabel(updated)}',
            style: metaStyle,
          ),
        ),
    ];
    if (visibleTags.isEmpty && stamps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (visibleTags.isNotEmpty) ...<Widget>[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final tag in visibleTags) _DetailTagChip(tag: tag),
              ],
            ),
            if (stamps.isNotEmpty) const SizedBox(height: 12),
          ],
          if (stamps.isNotEmpty)
            Row(
              children: <Widget>[
                const _ColorfulDetailIcon(
                  icon: TablerIcons.history,
                  imagePath: 'assets/images/ic_history_color.png',
                  size: 14,
                  fallbackColor: _DetailPalette.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      for (var i = 0; i < stamps.length; i++) ...<Widget>[
                        if (i > 0) Text('  ·  ', style: metaStyle),
                        stamps[i],
                      ],
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DetailTagChip extends StatelessWidget {
  const _DetailTagChip({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DcColors.purple.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$tag',
        style: _text(
          11,
          _DetailPalette.ink,
          fontWeight: FontWeight.w600,
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
        color: _DetailPalette.surface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: <Widget>[
                const _CircularDetailIcon(
                  icon: TablerIcons.key,
                  imagePath: 'assets/images/ic_ssh_color.png',
                  color: DcColors.selection,
                  size: 44,
                  iconSize: 28,
                  backgroundColor: _DetailPalette.inset,
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
                          _DetailPalette.ink,
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
                          _DetailPalette.muted,
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
                    imagePath: 'assets/images/ic_copy_color.png',
                    tooltip: 'Copy fingerprint',
                    onTap: () => onCopy(snapshot.fingerprint, 'Fingerprint'),
                  ),
              ],
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: _DetailPalette.line,
          ),
          if (snapshot.publicKey.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.key,
              imagePath: 'assets/images/ic_key_color.png',
              iconColor: DcColors.selection,
              label: 'public key',
              value: snapshot.publicKey,
              monospace: true,
              onCopy: () => onCopy(snapshot.publicKey, 'Public key'),
            ),
          if (snapshot.publicKey.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: _DetailPalette.line),
          if (snapshot.fingerprint.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.fingerprint,
              imagePath: 'assets/images/ic_fingerprint_color.png',
              iconColor: DcColors.indigo,
              label: 'fingerprint',
              value: snapshot.fingerprint,
              monospace: true,
              onCopy: () => onCopy(snapshot.fingerprint, 'Fingerprint'),
            ),
          if (snapshot.fingerprint.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: _DetailPalette.line),
          if (snapshot.privateKey.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.key,
              imagePath: 'assets/images/ic_shield_lock_color.png',
              iconColor: DcColors.selection,
              label: 'private key',
              value: snapshot.privateKey,
              secret: true,
              badgeText: 'Protected',
              onCopy: () => onCopy(snapshot.privateKey, 'Private key'),
              onView: onViewPrivateKey,
            ),
          if (snapshot.privateKey.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: _DetailPalette.line),
          if (snapshot.keyFileName.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.file_description,
              imagePath: 'assets/images/ic_filename_color.png',
              iconColor: DcColors.selection,
              label: 'key file name',
              value: snapshot.keyFileName,
              onCopy: () => onCopy(snapshot.keyFileName, 'Key file name'),
            ),
          if (snapshot.keyFileName.isNotEmpty && snapshot.passphrase.isNotEmpty)
            const Divider(height: 1, thickness: 1, color: _DetailPalette.line),
          if (snapshot.passphrase.isNotEmpty)
            _SshDetailPanelRow(
              icon: TablerIcons.shield_lock,
              imagePath: 'assets/images/ic_lock_passphrase_color.png',
              iconColor: DcColors.orange,
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
    this.imagePath,
    this.secret = false,
    this.monospace = false,
    this.badgeText,
    this.onCopy,
    this.onView,
  });

  final IconData icon;
  final Color iconColor;

  /// Colorful artwork shown instead of [icon] when set.
  final String? imagePath;
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
              imagePath: imagePath,
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
                    _DetailPalette.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: monospace ? 13 : 15,
                    color: _DetailPalette.ink,
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
            DcStatusBadge(
              label: badgeText!,
              color: DcColors.green,
              foreground: DcColors.sidebarText,
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
              imagePath: 'assets/images/ic_copy_color.png',
              tooltip: 'Copy',
              onTap: onCopy!,
            ),
          ],
        ],
      ),
    );
  }
}

class _CircularDetailIcon extends StatelessWidget {
  const _CircularDetailIcon({
    required this.icon,
    required this.color,
    this.imagePath,
    this.size = 28,
    this.iconSize = 15,
    this.backgroundColor,
  });

  final IconData icon;
  final Color color;

  /// Colorful artwork for this field, rendered instead of [icon] when set.
  final String? imagePath;
  final double size;
  final double iconSize;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    // Rendered raw: no chip background, border, or padding — just the
    // glyph tinted with its accent color, or the colorful artwork.
    final artwork = imagePath;
    if (artwork != null) {
      return SizedBox(
        width: iconSize,
        height: iconSize,
        child: Image.asset(
          artwork,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Icon(icon, size: iconSize, color: color),
        ),
      );
    }
    return Icon(icon, size: iconSize, color: color);
  }
}

/// Standalone colorful artwork slot with a Tabler glyph fallback — used
/// where the [imagePath] lives on the widget itself rather than on
/// [_CircularDetailIcon].
class _ColorfulDetailIcon extends StatelessWidget {
  const _ColorfulDetailIcon({
    required this.icon,
    required this.imagePath,
    required this.size,
    required this.fallbackColor,
  });

  final IconData icon;
  final String imagePath;
  final double size;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      imagePath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(icon, size: size, color: fallbackColor),
    );
  }
}

/// DriveClue-style 28 px status bar along the bottom of the vault window:
/// sync status pinned left, then license/links/statistics on the right.
class _VaultStatusBar extends ConsumerWidget {
  const _VaultStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleCount = ref.watch(vaultEntriesProvider).length;
    final totalCount = ref.watch(vaultDatabaseEntriesProvider).length;
    final countLabel = visibleCount == totalCount
        ? '$totalCount item${totalCount == 1 ? '' : 's'}'
        : '$visibleCount of $totalCount items';

    return DcStatusBar(
      leading: const <Widget>[
        _VaultSyncStatusRow(compact: true),
      ],
      trailing: <Widget>[
        const DcStatusBarAction(
          icon: TablerIcons.shield_check,
          label: 'Free license',
          bold: true,
          tooltip: 'LumenPass is free and open source — no subscription.',
          url: _kLicenseInfoUrl,
        ),
        const DcStatusBarAction(
          icon: TablerIcons.download,
          label: 'Other platforms & extensions',
          tooltip: 'Download LumenPass for other platforms',
          url: _kDownloadsUrl,
        ),
        const DcStatusBarAction(
          icon: TablerIcons.brand_github,
          label: 'GitHub',
          tooltip: 'View the source on GitHub',
          url: _kRepositoryUrl,
        ),
        const DcStatusBarAction(
          icon: TablerIcons.coffee,
          label: 'Buy me a coffee',
          tooltip: 'Support LumenPass development',
          accentColor: Color(0xFF9A6A16),
          url: _kDonateUrl,
        ),
        Text(countLabel),
        const _SidebarAutoLockCountdownLabel(),
      ],
    );
  }
}

const String _kDownloadsUrl = 'https://www.lumenpass.app/downloads';
const String _kRepositoryUrl = 'https://github.com/lumenpass/lumenpass';
const String _kDonateUrl = 'https://donorbox.org/donate-to-tranit';
const String _kLicenseInfoUrl = 'https://www.apache.org/licenses/LICENSE-2.0';

class _FlatRowAction extends StatelessWidget {
  const _FlatRowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.imagePath,
    this.color = _kPrimaryButtonColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Colorful artwork shown instead of [icon] when set.
  final String? imagePath;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _AppTooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: imagePath != null
              ? Image.asset(
                  imagePath!,
                  width: 15,
                  height: 15,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, __, ___) =>
                      Icon(icon, size: 14, color: color),
                )
              : Icon(icon, size: 14, color: color),
        ),
      ),
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
          color: DcColors.selection,
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 16, color: _DetailPalette.muted),
        ),
      ),
    );
  }
}

/// Light palette for the item detail pane: the pane sits on the sidebar
/// blue-gray and its cards are white, matching the left menu.
abstract final class _DetailPalette {
  static const Color canvas = DcColors.sidebar;
  static const Color surface = DcColors.lightSurface;
  static const Color inset = DcColors.lightInset;
  static const Color hover = DcColors.lightInset;
  static const Color ink = DcColors.sidebarText;
  static const Color muted = DcColors.sidebarMuted;
  static const Color line = DcColors.sidebarLine;
  static const Color lineStrong = DcColors.lightLineStrong;
  static const Color danger = DcColors.redOnLight;
  static const Color shadow = DcColors.lightCardShadow;

  /// Deeper indigo that stays readable on white (passkey, 2FA scan).
  static const Color indigo = Color(0xFF4F5BD5);
}

const Color _kDetailCardSurface = _DetailPalette.surface;
const Color _kDetailCardBorder = _DetailPalette.line;

/// White card holding the credential rows. No title bar: the rows speak for
/// themselves, and the card stays visually quiet.
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kDetailCardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kDetailCardBorder),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: _DetailPalette.shadow,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
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
    this.imagePath,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color? labelColor;
  final String? imagePath;
  final bool hovered;
  final bool menuOpen;
  final bool showDivider;
  final VoidCallback onCopyPressed;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onArrowPressed;

  @override
  Widget build(BuildContext context) {
    return _DetailValueRow(
      icon: icon,
      iconColor: iconColor,
      label: label,
      labelColor: labelColor,
      imagePath: imagePath,
      hovered: hovered,
      menuOpen: menuOpen,
      showDivider: showDivider,
      onCopy: onCopyPressed,
      onHoverChanged: onHoverChanged,
      onMore: onArrowPressed,
      value: Text(
        value,
        overflow: TextOverflow.ellipsis,
        maxLines: 3,
        style: _text(
          14,
          _DetailPalette.ink,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      ),
    );
  }
}

/// Social sign-in rendered as the leading row of the grouped fields card,
/// sharing the row geometry of the passkey and attribute rows.
class _SocialLoginDetailRow extends StatelessWidget {
  const _SocialLoginDetailRow({
    required this.providerId,
    required this.domain,
    required this.showDivider,
  });

  final String providerId;
  final String domain;
  final bool showDivider;

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
      padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: showDivider
              ? const BorderSide(color: _kDetailCardBorder)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _DetailPalette.surface,
              shape: BoxShape.circle,
              border: Border.all(color: _DetailPalette.line),
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
                  color: DcColors.indigo,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Sign in with ${_getProviderName(providerId)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    11,
                    _DetailPalette.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayDomain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    14,
                    _DetailPalette.ink,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      return ('Weak', 0.24, DcColors.red, _DetailPalette.muted);
    case _PasswordStrength.fair:
      return ('Fair', 0.48, DcColors.orange, _DetailPalette.muted);
    case _PasswordStrength.good:
      return ('Good', 0.74, DcColors.green, _DetailPalette.muted);
    case _PasswordStrength.strong:
      return (
        'Very Good',
        0.90,
        DcColors.green,
        _DetailPalette.muted,
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
    this.imagePath,
  });

  final IconData icon;
  final String label;
  final String secretValue;
  final Color iconColor;

  /// Colorful artwork that replaces [icon] when the field has one.
  final String? imagePath;
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
    final value = widget.secretValue;
    return _DetailValueRow(
      icon: widget.icon,
      iconColor: DcColors.orange,
      label: widget.label,
      imagePath: widget.imagePath,
      hovered: widget.hovered,
      menuOpen: widget.menuOpen,
      showDivider: widget.showDivider,
      onCopy: widget.onCopyPressed,
      onHoverChanged: widget.onHoverChanged,
      onMore: widget.onArrowPressed,
      value: Text(
        _visible ? value : '•' * math.min(18, math.max(10, value.length)),
        overflow: TextOverflow.ellipsis,
        maxLines: _visible ? 3 : 1,
        style: _visible
            ? TextStyle(
                fontSize: (14 + currentTextSizeDelta).toDouble(),
                color: _DetailPalette.ink,
                fontWeight: FontWeight.w500,
                fontFamily: 'Menlo',
                height: 1.35,
              )
            : _text(
                15,
                _DetailPalette.ink,
                fontWeight: FontWeight.w600,
                height: 1.25,
                letterSpacing: 1.2,
              ),
      ),
      footer: widget.showStrength && value.isNotEmpty
          ? _PasswordStrengthBar(value: value)
          : null,
      persistentActions: <Widget>[
        if (widget.showVisibilityToggle) ...<Widget>[
          _NeutralOverflowAction(
            icon: _visible ? TablerIcons.eye_off : TablerIcons.eye,
            tooltip: _visible ? 'Hide' : 'Reveal',
            onTap: () => setState(() => _visible = !_visible),
          ),
          const SizedBox(width: 2),
        ],
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
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: _DetailPalette.surface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
      ),
      child: Row(
        children: <Widget>[
          _CircularDetailIcon(
            icon: TablerIcons.clock,
            imagePath: 'assets/images/ic_clock_color.png',
            color: countdownColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'TOTP',
                  style: _text(
                    11,
                    _DetailPalette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  code,
                  style: TextStyle(
                    fontSize: (22 + currentTextSizeDelta).toDouble(),
                    color: countdownColor,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Menlo',
                    letterSpacing: 1,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Depleting ring around the remaining seconds replaces the solid
          // badge plus the full-width progress stripe: the countdown itself
          // becomes the progress indicator and the color signals urgency.
          SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    value: secondsRemaining / 30,
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                    color: countdownColor,
                    backgroundColor:
                        countdownColor.withValues(alpha: 0.15),
                  ),
                ),
                Text(
                  '$secondsRemaining',
                  style: _text(
                    10,
                    _DetailPalette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _FlatRowAction(
            icon: TablerIcons.copy,
            tooltip: 'Copy TOTP',
            onTap: onCopyPressed,
            color: DcColors.selection,
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
              imagePath: 'assets/images/ic_paperclip_color.png',
              color: DcColors.selection,
            ),
            const SizedBox(width: 8),
            Text(
              'Attachments',
              style: _text(
                13,
                _DetailPalette.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${attachments.length})',
              style: _text(
                12,
                _DetailPalette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const _CircularDetailIcon(
              icon: TablerIcons.upload,
              imagePath: 'assets/images/ic_upload_color.png',
              color: DcColors.selection,
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
          color: _DetailPalette.surface,
          borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
          border: Border.all(color: _DetailPalette.line),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: attachment.isImage
                    ? _DetailPalette.inset
                    : _DetailPalette.inset,
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
                  : Image.asset(
                      attachment.isImage
                          ? 'assets/images/ic_file_image_color.png'
                          : 'assets/images/ic_filename_color.png',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => Icon(
                        attachment.isImage
                            ? TablerIcons.photo
                            : TablerIcons.file_description,
                        size: 18,
                        color: _DetailPalette.muted,
                      ),
                    ),
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
                      _DetailPalette.ink,
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
                      _DetailPalette.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            _FlatRowAction(
              icon: TablerIcons.download,
              imagePath: 'assets/images/ic_download_color.png',
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
    this.iconColor = _DetailPalette.muted,
    this.imagePath,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  /// Colorful artwork shown instead of [icon] when set.
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _CircularDetailIcon(
          icon: icon,
          imagePath: imagePath,
          color: iconColor,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: _text(
            13,
            _DetailPalette.ink,
            fontWeight: FontWeight.w600,
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
    final foregroundColor =
        widget.isDestructive ? _DetailPalette.danger : _DetailPalette.ink;
    final radius = BorderRadius.vertical(
      top: widget.isFirst
          ? const Radius.circular(DcMetrics.panelRadius)
          : Radius.zero,
      bottom: widget.isLast
          ? const Radius.circular(DcMetrics.panelRadius)
          : Radius.zero,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: radius,
        hoverColor: _DetailPalette.inset,
        highlightColor: _DetailPalette.inset,
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
        color: _DetailPalette.surface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: _DetailPalette.lineStrong),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x29263340),
            blurRadius: 18,
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
              const Divider(height: 1, color: _DetailPalette.line),
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
                  color: const Color(0x80E3EBF2),
                  child: SafeArea(
                    minimum: const EdgeInsets.all(24),
                    child: Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          width: dialogWidth,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: _DetailPalette.surface,
                            borderRadius:
                                BorderRadius.circular(DcMetrics.panelRadius),
                            border: Border.all(color: _DetailPalette.line),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x29263340),
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
                                        _DetailPalette.ink,
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
                                  _DetailPalette.ink,
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
                                    _DetailPalette.ink,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: _DetailPalette.inset,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          DcMetrics.controlRadius),
                                      borderSide: const BorderSide(
                                        color: _DetailPalette.line,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          DcMetrics.controlRadius),
                                      borderSide: const BorderSide(
                                        color: _DetailPalette.line,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          DcMetrics.controlRadius),
                                      borderSide: const BorderSide(
                                        color: Color(0x663882C2),
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
                                      minimumSize: const Size(120, 32),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            DcMetrics.controlRadius),
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
                                      minimumSize: const Size(96, 32),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      backgroundColor: _DetailPalette.surface,
                                      side: const BorderSide(
                                        color: _DetailPalette.lineStrong,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            DcMetrics.controlRadius),
                                      ),
                                    ),
                                    child: Text(
                                      'Close',
                                      style: _text(
                                        14,
                                        _DetailPalette.ink,
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
        color: const Color(0xF2262E34),
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x40000000),
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
        child: Icon(icon, size: 16, color: _DetailPalette.muted),
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
      color: _DetailPalette.surface,
      surfaceTintColor: _DetailPalette.surface,
      elevation: 8,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        side: const BorderSide(color: _DetailPalette.lineStrong),
      ),
      onSelected: (value) {
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'delete',
          height: 38,
          child: Row(
            children: <Widget>[
              const Icon(
                TablerIcons.trash,
                size: 15,
                color: _DetailPalette.danger,
              ),
              const SizedBox(width: 10),
              Text(
                destructiveLabel,
                style: _text(
                  12,
                  _DetailPalette.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
      child: const _DetailHeaderButtonFace(
        hovered: false,
        child: _ColorfulDetailIcon(
          icon: TablerIcons.dots_vertical,
          imagePath: 'assets/images/ic_more_color.png',
          size: 16,
          fallbackColor: _DetailPalette.muted,
        ),
      ),
    );
  }
}

class _EmptyDetailPane extends ConsumerWidget {
  const _EmptyDetailPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = vaultEmptyStateCopy(
      totalItemCount: ref.watch(vaultDatabaseEntriesProvider).length,
      groupId: ref.watch(vaultSelectedGroupProvider),
      itemTypeId: ref.watch(vaultSelectedItemTypeIdProvider),
      tag: ref.watch(vaultSelectedTagProvider),
      searchQuery: ref.watch(vaultSearchQueryProvider),
      passwordAuditIssue: ref.watch(vaultPasswordAuditSelectionProvider)?.name,
    );
    return Container(
      color: _DetailPalette.canvas,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Image.asset(
                    'assets/images/sidebar_audit.png',
                    width: 46,
                    height: 46,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => const Icon(
                      TablerIcons.shield_lock,
                      size: 46,
                      color: _DetailPalette.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    copy.title,
                    style: _text(
                      17,
                      _DetailPalette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    copy.description,
                    textAlign: TextAlign.center,
                    style: _text(
                      12,
                      _DetailPalette.muted,
                      fontWeight: FontWeight.w400,
                      height: 1.6,
                    ),
                  ),
                  if (copy.showSuggestions) ...<Widget>[
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
                          iconColor: DcColors.selection,
                          imagePath: 'assets/images/item_type_ssh.png',
                        ),
                        _EmptyTypePill(
                          icon: TablerIcons.notebook,
                          label: 'Secure Notes',
                          iconColor: DcColors.indigo,
                          imagePath: 'assets/images/item_type_note.png',
                        ),
                        _EmptyTypePill(
                          icon: TablerIcons.fingerprint,
                          label: 'Passkeys',
                          iconColor: DcColors.cyan,
                          imagePath: 'assets/images/sidebar_passkey.png',
                        ),
                        _EmptyTypePill(
                          icon: TablerIcons.id_badge_2,
                          label: 'Identities',
                          iconColor: DcColors.tealOnLight,
                          imagePath: 'assets/images/item_type_identity.png',
                        ),
                        _EmptyTypePill(
                          icon: TablerIcons.clock,
                          label: 'TOTP Codes',
                          iconColor: DcColors.orange,
                          imagePath: 'assets/images/sidebar_totp.png',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
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
    this.imagePath,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _DetailPalette.surface,
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        border: Border.all(color: _DetailPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (imagePath != null)
            SizedBox(
              width: 14,
              height: 14,
              child: Image.asset(
                imagePath!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) =>
                    Icon(icon, size: 13, color: iconColor),
              ),
            )
          else
            Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: _text(
              11,
              _DetailPalette.ink,
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
    this.accent,
  });

  final _MockEntry entry;
  final double size;

  /// When set, the letter fallback becomes a solid accent tile with white
  /// initials (used by the large detail-pane avatar).
  final Color? accent;

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

    if (useCardBrandTile) {
      return _CardBrandBadge(
        brand: widget.entry.cardBrand!,
        size: widget.size,
      );
    }

    if (useGeneratedTile) {
      final accent = widget.accent;
      final initialsWidget = accent != null
          ? Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color.lerp(accent, Colors.white, 0.12)!,
                    accent,
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                _detailAvatarInitials(widget.entry.title),
                style: _text(
                  widget.size * 0.4,
                  Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            )
          : Container(
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

    // Every non-login type renders its colorful IconScout artwork so the list
    // rows, detail header and quick search all share one visual language.
    final artworkPath = itemTypeVisual?.imagePath;
    if (artworkPath != null) {
      return _ItemTypeArtwork(
        imagePath: artworkPath,
        size: widget.size,
        fallbackIcon: itemTypeVisual?.icon ?? TablerIcons.file_description,
        fallbackColor: itemTypeVisual?.iconColor ?? _kPrimaryButtonColor,
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

/// Colorful item-type artwork, rendered full-bleed: no tinted tile behind it
/// and no inset padding — the IconScout glyph fills the slot edge to edge so
/// the list rows, detail header and quick search all share one visual
/// language.
class _ItemTypeArtwork extends StatelessWidget {
  const _ItemTypeArtwork({
    required this.imagePath,
    required this.size,
    required this.fallbackIcon,
    required this.fallbackColor,
  });

  final String imagePath;
  final double size;
  final IconData fallbackIcon;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final art = Image.asset(
      imagePath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(
        fallbackIcon,
        size: size * 0.8,
        color: fallbackColor,
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Center(child: art),
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
            colors: <Color>[DcColors.selection, DcColors.selection],
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
            colors: <Color>[DcColors.cyan, DcColors.cyan],
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
            colors: <Color>[DcColors.selection, DcColors.selection],
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
            colors: <Color>[DcColors.selection, DcColors.selection],
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
        color: DcColors.lightSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DcColors.sidebarLine),
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
                color: DcColors.deepOrange,
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
                color: DcColors.orange,
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
        color: DcColors.lightSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DcColors.sidebarLine),
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
                DcColors.sidebarText,
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
                  colors: <Color>[DcColors.deepOrange, DcColors.orange],
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
        color: DcColors.lightSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DcColors.sidebarLine),
      ),
      padding: EdgeInsets.all(size * 0.16),
      child: Row(
        children: <Widget>[
          stripe('J', const <Color>[DcColors.teal, DcColors.teal]),
          SizedBox(width: size * 0.05),
          stripe('C', const <Color>[DcColors.selection, DcColors.selection]),
          SizedBox(width: size * 0.05),
          stripe('B', const <Color>[DcColors.red, DcColors.red]),
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
          colors: <Color>[DcColors.selection, DcColors.selection],
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
    final bgColor = enabled ? DcColors.green : DcColors.selection;
    final title = enabled ? 'SSH Agent is On' : 'SSH Agent is Off';
    final description = enabled
        ? 'LumenPass can now help terminals and developer tools authenticate to SSH servers with your saved keys.'
        : 'Turn on SSH Agent to let compatible applications sign in to SSH servers seamlessly with your saved keys.';
    final buttonLabel =
        enabled ? 'Manage SSH Agent Setting.' : 'Open SSH Agent Setting.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _DetailPalette.surface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border(left: BorderSide(color: bgColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _CircularDetailIcon(
                icon: TablerIcons.sparkles,
                imagePath: 'assets/images/ic_robot_color.png',
                color: bgColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: _text(
                    14,
                    _DetailPalette.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: _text(
              12,
              _DetailPalette.muted,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onOpenSettings,
            style: FilledButton.styleFrom(
              backgroundColor: DcColors.selection,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
              ),
            ),
            child: Text(
              buttonLabel,
              style: _text(
                12,
                Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeakPasswordBanner extends StatelessWidget {
  const _WeakPasswordBanner({
    required this.onChangePassword,
  });

  final VoidCallback onChangePassword;

  static const Color _bg = DcColors.redOnLight;
  static const Color _textMain = _DetailPalette.ink;
  static const Color _textDesc = _DetailPalette.muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _DetailPalette.surface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border(left: BorderSide(color: _bg, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _CircularDetailIcon(
                icon: TablerIcons.alert_triangle,
                imagePath: 'assets/images/ic_warning_color.png',
                color: _bg,
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
              const DcStatusBadge(label: 'WEAK', color: _bg),
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
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.filled
                ? (_hovered ? DcColors.selectionHover : DcColors.selection)
                : (_hovered ? _DetailPalette.hover : _DetailPalette.surface),
            borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            border: widget.filled
                ? null
                : Border.all(color: _DetailPalette.lineStrong),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: _text(
              12,
              widget.filled ? Colors.white : _DetailPalette.ink,
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
