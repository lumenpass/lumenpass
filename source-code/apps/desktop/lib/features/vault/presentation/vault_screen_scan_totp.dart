part of 'vault_screen.dart';

enum _ScanTotpStep { input, preview }

class _ScanTotpOverlay extends StatefulWidget {
  const _ScanTotpOverlay({
    required this.onClose,
    required this.onTotpConfirmed,
    required this.onShowToast,
  });

  final VoidCallback onClose;
  final ValueChanged<String> onTotpConfirmed;
  final ValueChanged<String> onShowToast;

  @override
  State<_ScanTotpOverlay> createState() => _ScanTotpOverlayState();
}

class _ScanTotpOverlayState extends State<_ScanTotpOverlay> {
  _ScanTotpStep _step = _ScanTotpStep.input;
  bool _isDragOver = false;
  bool _isProcessing = false;
  String? _otpauthUrl;
  String? _error;
  final TextEditingController _manualCtrl = TextEditingController();
  Timer? _timer;
  DateTime _now = DateTime.now();

  static const MethodChannel _channel = MethodChannel('lumenpass/window');
  static const TOTPService _totpService = TOTPService();

  @override
  void dispose() {
    _timer?.cancel();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  String? _normalizeOtpAuth(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'otpauth') return trimmed;
    final clean = trimmed.replaceAll(' ', '').toUpperCase();
    if (RegExp(r'^[A-Z2-7=]{8,}$').hasMatch(clean)) {
      return 'otpauth://totp/Account?secret=$clean&issuer=Added manually';
    }
    return null;
  }

  ({String issuer, String account}) _parseOtpInfo(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return (issuer: 'Unknown', account: '');
    final path = Uri.decodeComponent(uri.path.replaceFirst('/', '')).trim();
    String issuer = uri.queryParameters['issuer'] ?? '';
    String account = path;
    if (path.contains(':')) {
      final parts = path.split(':');
      if (issuer.isEmpty) issuer = parts[0].trim();
      account = parts.sublist(1).join(':').trim();
    }
    if (issuer.isEmpty) issuer = account;
    return (issuer: issuer, account: account == issuer ? '' : account);
  }

  Future<void> _handleFilePath(String path) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final result = await _channel
          .invokeMethod<String>('decodeQRFromFile', {'path': path});
      if (!mounted) return;
      if (result != null && result.isNotEmpty) {
        final normalized = _normalizeOtpAuth(result);
        if (normalized != null && _totpService.isValidOtpAuth(normalized)) {
          setState(() {
            _otpauthUrl = normalized;
            _isProcessing = false;
            _step = _ScanTotpStep.preview;
          });
          _startTimer();
        } else {
          setState(() {
            _error = 'QR code found but not a valid TOTP code.';
            _isProcessing = false;
          });
        }
      } else {
        setState(() {
          _error = 'No QR code found in this image.';
          _isProcessing = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to read the image file.';
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path != null) await _handleFilePath(path);
  }

  Future<void> _scanScreen() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      final result = await _channel.invokeMethod<String>('scanScreen');
      if (!mounted) return;
      if (result != null && result.isNotEmpty) {
        final normalized = _normalizeOtpAuth(result);
        if (normalized != null && _totpService.isValidOtpAuth(normalized)) {
          setState(() {
            _otpauthUrl = normalized;
            _isProcessing = false;
            _step = _ScanTotpStep.preview;
          });
          _startTimer();
        } else {
          setState(() {
            _error = 'QR code found but not a valid TOTP code.';
            _isProcessing = false;
          });
        }
      } else {
        setState(() {
          _error = 'No TOTP QR code detected on screen.';
          _isProcessing = false;
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'CAPTURE_FAILED'
            ? 'Screen capture failed. Please grant Screen Recording permission in System Settings.'
            : 'Could not scan screen.';
        _isProcessing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not scan screen.';
        _isProcessing = false;
      });
    }
  }

  void _tryManualInput() {
    final normalized = _normalizeOtpAuth(_manualCtrl.text);
    if (normalized == null || !_totpService.isValidOtpAuth(normalized)) {
      setState(
          () => _error = 'Enter a valid otpauth:// URL or Base32 TOTP secret.');
      return;
    }
    setState(() {
      _otpauthUrl = normalized;
      _error = null;
      _step = _ScanTotpStep.preview;
    });
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onClose,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: DcColors.scrim,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: GestureDetector(
              onTap: () {},
              child: _step == _ScanTotpStep.input
                  ? _buildInputStep()
                  : _buildPreviewStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputStep() {
    final bool canContinue =
        _manualCtrl.text.trim().isNotEmpty && !_isProcessing;

    return Container(
      width: 520,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: BoxDecoration(
        color: DcColors.panel,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: DcColors.line),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Add 2FA Code',
                  style: _text(17, DcColors.text,
                      fontWeight: FontWeight.w700),
                ),
              ),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child:
                      Icon(TablerIcons.x, size: 16, color: DcColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Drop zone
          DropTarget(
            onDragEntered: (_) => setState(() => _isDragOver = true),
            onDragExited: (_) => setState(() => _isDragOver = false),
            onDragDone: (detail) {
              setState(() => _isDragOver = false);
              if (detail.files.isNotEmpty) {
                _handleFilePath(detail.files.first.path);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: _isDragOver
                    ? DcColors.rowAlternate
                    : DcColors.panel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isDragOver
                      ? DcColors.selection
                      : DcColors.line,
                  width: _isDragOver ? 2 : 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: _isProcessing
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: DcColors.selection,
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          _isDragOver ? TablerIcons.scan : TablerIcons.qrcode,
                          size: 32,
                          color: _isDragOver
                              ? DcColors.selection
                              : DcColors.selection,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isDragOver
                              ? 'Drop to scan QR code'
                              : 'Drop a QR code image here',
                          style: _text(
                            13,
                            _isDragOver
                                ? DcColors.selection
                                : DcColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            _ScanActionButton(
                              icon: TablerIcons.folder_open,
                              label: 'Browse Image',
                              onTap: _pickFile,
                            ),
                            const SizedBox(width: 8),
                            _ScanActionButton(
                              icon: TablerIcons.device_desktop,
                              label: 'Scan Screen',
                              onTap: _scanScreen,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 20),

          // Divider "or"
          Row(
            children: <Widget>[
              const Expanded(child: Divider(color: DcColors.line)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or enter setup key manually',
                  style: _text(12, DcColors.muted,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const Expanded(child: Divider(color: DcColors.line)),
            ],
          ),
          const SizedBox(height: 16),

          // Manual input
          TextField(
            controller: _manualCtrl,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _tryManualInput(),
            style:
                _text(13, DcColors.text, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'otpauth://totp/... or TOTP secret (Base32)',
              hintStyle: _text(13, DcColors.selection,
                  fontWeight: FontWeight.w400),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: DcColors.panel,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: DcColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: DcColors.selection),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: DcColors.red),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: DcColors.red),
              ),
            ),
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                const Icon(TablerIcons.alert_circle,
                    size: 13, color: DcColors.red),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _error!,
                    style: _text(12, DcColors.red,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // Footer buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _ScanGhostButton(label: 'Cancel', onTap: widget.onClose),
              const SizedBox(width: 10),
              _ScanPrimaryButton(
                label: 'Continue',
                icon: TablerIcons.arrow_right,
                enabled: canContinue,
                onTap: _tryManualInput,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewStep() {
    final url = _otpauthUrl!;
    final info = _parseOtpInfo(url);
    final code = _totpService.generateCode(url, timestamp: _now) ?? '--- ---';
    final formattedCode = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    final seconds = _totpService.secondsRemaining(url, timestamp: _now);
    final progress = seconds / 30.0;
    final countdownColor = _totpCountdownColor(seconds);

    return Container(
      width: 480,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: BoxDecoration(
        color: DcColors.panel,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: DcColors.line),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header
          Row(
            children: <Widget>[
              InkWell(
                onTap: () {
                  _timer?.cancel();
                  setState(() {
                    _step = _ScanTotpStep.input;
                    _error = null;
                  });
                },
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(TablerIcons.arrow_left,
                      size: 16, color: DcColors.muted),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add 2FA Code',
                  style: _text(17, DcColors.text,
                      fontWeight: FontWeight.w700),
                ),
              ),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child:
                      Icon(TablerIcons.x, size: 16, color: DcColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Success banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: DcColors.rowAlternate,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x6647C7B8)),
            ),
            child: Row(
              children: <Widget>[
                const Icon(TablerIcons.circle_check,
                    size: 16, color: DcColors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '2FA code ready to add',
                    style: _text(13, DcColors.teal,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Issuer info
          if (info.issuer.isNotEmpty) ...<Widget>[
            Text(
              info.issuer,
              style: _text(15, DcColors.text,
                  fontWeight: FontWeight.w700),
            ),
            if (info.account.isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                info.account,
                style: _text(13, DcColors.muted,
                    fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 16),
          ],

          // TOTP Code card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: DcColors.panel,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: DcColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Current TOTP Code',
                  style: _text(11, DcColors.muted,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Text(
                      formattedCode,
                      style: _text(
                        28,
                        DcColors.text,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _AppTooltip(
                      message: 'Copy code',
                      child: InkWell(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: code));
                          widget.onShowToast('TOTP code copied to clipboard');
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            TablerIcons.copy,
                            size: 16,
                            color: DcColors.muted,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '${seconds}s',
                          style: _text(16, countdownColor,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 80,
                          height: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: DcColors.rowAlternate,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(countdownColor),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'The code refreshes every 30 seconds.',
            style:
                _text(12, DcColors.muted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),

          // Footer
          Row(
            children: <Widget>[
              _ScanGhostButton(label: 'Dismiss', onTap: widget.onClose),
              const Spacer(),
              _ScanPrimaryButton(
                label: 'Confirm Add 2FA',
                icon: TablerIcons.check,
                enabled: true,
                onTap: () => widget.onTotpConfirmed(url),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanActionButton extends StatefulWidget {
  const _ScanActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ScanActionButton> createState() => _ScanActionButtonState();
}

class _ScanActionButtonState extends State<_ScanActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered ? DcColors.rowAlternate : DcColors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  _hovered ? DcColors.selection : DcColors.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.icon,
                size: 13,
                color: _hovered
                    ? DcColors.selection
                    : DcColors.muted,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: _text(
                  12,
                  _hovered ? DcColors.selection : DcColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanGhostButton extends StatefulWidget {
  const _ScanGhostButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_ScanGhostButton> createState() => _ScanGhostButtonState();
}

class _ScanGhostButtonState extends State<_ScanGhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _hovered ? DcColors.rowAlternate : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: DcColors.line),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style:
                _text(13, DcColors.text, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _ScanPrimaryButton extends StatefulWidget {
  const _ScanPrimaryButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ScanPrimaryButton> createState() => _ScanPrimaryButtonState();
}

class _ScanPrimaryButtonState extends State<_ScanPrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.enabled && _hovered;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: widget.enabled
                ? (isActive ? _kPrimaryButtonHoverColor : _kPrimaryButtonColor)
                : _kPrimaryButtonColor.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.enabled
                ? <BoxShadow>[
                    BoxShadow(
                      color: isActive
                          ? _kPrimaryButtonColor.withValues(alpha: 0.24)
                          : _kPrimaryButtonColor.withValues(alpha: 0.14),
                      blurRadius: isActive ? 12 : 4,
                      offset: Offset(0, isActive ? 4 : 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.label,
                style: _text(13, Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Icon(widget.icon, size: 14, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
