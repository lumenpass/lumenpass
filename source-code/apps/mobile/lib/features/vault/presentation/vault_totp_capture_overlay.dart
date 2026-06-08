import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

Future<String?> showTotpCaptureOverlay(BuildContext context) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (ctx, animation, secondaryAnimation) =>
          _TotpCaptureOverlay(onClose: () => Navigator.of(ctx).pop()),
    ),
  );
}

bool isOtpFieldKey(String key) {
  final normalized = key.trim().toLowerCase();
  return normalized == 'otp' ||
      normalized == AppKdbxFieldKeys.otpAuth.toLowerCase() ||
      normalized == 'otp auth' ||
      normalized.contains('otpauth') ||
      normalized.contains('otp auth');
}

String preferredOtpFieldKey(KdbxEntry entry) {
  for (final field in entry.fields) {
    if (isOtpFieldKey(field.key)) {
      return field.key;
    }
  }
  return AppKdbxFieldKeys.otpAuth;
}

enum _TotpCaptureStep { input, preview }

class _TotpCaptureOverlay extends StatefulWidget {
  const _TotpCaptureOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_TotpCaptureOverlay> createState() => _TotpCaptureOverlayState();
}

class _TotpCaptureOverlayState extends State<_TotpCaptureOverlay> {
  static const TOTPService _totpService = TOTPService();

  _TotpCaptureStep _step = _TotpCaptureStep.input;
  final TextEditingController _manualCtrl = TextEditingController();
  Timer? _timer;
  DateTime _now = DateTime.now();
  String? _otpauthUrl;
  String? _error;
  bool _isLaunchingScanner = false;

  @override
  void dispose() {
    _timer?.cancel();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  String? _normalizeOtpAuth(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'otpauth') {
      return trimmed;
    }
    final clean = trimmed.replaceAll(' ', '').toUpperCase();
    if (RegExp(r'^[A-Z2-7=]{8,}$').hasMatch(clean)) {
      return 'otpauth://totp/Account?secret=$clean&issuer=Added manually';
    }
    return null;
  }

  ({String issuer, String account}) _parseOtpInfo(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return (issuer: '', account: '');
    }
    final path = Uri.decodeComponent(uri.path.replaceFirst('/', '')).trim();
    String issuer = uri.queryParameters['issuer']?.trim() ?? '';
    String account = path;
    if (path.contains(':')) {
      final parts = path.split(':');
      if (issuer.isEmpty) {
        issuer = parts.first.trim();
      }
      account = parts.sublist(1).join(':').trim();
    }
    if (issuer.isEmpty) {
      issuer = account;
    }
    if (account == issuer) {
      account = '';
    }
    return (issuer: issuer, account: account);
  }

  void _goToPreviewFromInput(String rawInput) {
    final normalized = _normalizeOtpAuth(rawInput);
    if (normalized == null || !_totpService.isValidOtpAuth(normalized)) {
      setState(
        () => _error = 'Enter valid otpauth:// URL or Base32 TOTP secret.',
      );
      return;
    }
    setState(() {
      _otpauthUrl = normalized;
      _error = null;
      _step = _TotpCaptureStep.preview;
    });
    _startTimer();
  }

  void _goToPreview() => _goToPreviewFromInput(_manualCtrl.text);

  Future<void> _scanWithCamera() async {
    if (_isLaunchingScanner) {
      return;
    }
    setState(() {
      _isLaunchingScanner = true;
      _error = null;
    });
    final scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TotpCameraScannerSheet(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _isLaunchingScanner = false);
    if (scanned == null || scanned.trim().isEmpty) {
      return;
    }
    _manualCtrl.text = scanned.trim();
    _goToPreviewFromInput(scanned);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: const Color(0x52000000),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: GestureDetector(
            onTap: () {},
            child: switch (_step) {
              _TotpCaptureStep.input => _buildInputStep(context),
              _TotpCaptureStep.preview => _buildPreviewStep(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInputStep(BuildContext context) {
    final canContinue = _manualCtrl.text.trim().isNotEmpty;

    return Container(
      width: MediaQuery.sizeOf(context).width - 32,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Add 2FA Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF202939),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Scan QR with camera or paste otpauth URL/setup key manually.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isLaunchingScanner ? null : _scanWithCamera,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0A3B48),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _isLaunchingScanner
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: Text(
              _isLaunchingScanner ? 'Opening camera...' : 'Scan QR With Camera',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Expanded(child: Divider(color: Color(0xFFE4E9F2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'or enter manually',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A97AC),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFE4E9F2))),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _manualCtrl,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _goToPreview(),
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'otpauth://totp/... or TOTP secret (Base32)',
              hintStyle: const TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              fillColor: const Color(0xFFF7F9FB),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF4B6CFF)),
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFE53E3E),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3E4A5E),
                    side: const BorderSide(color: Color(0xFFD6DCE6)),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: canContinue ? _goToPreview : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewStep(BuildContext context) {
    final url = _otpauthUrl!;
    final info = _parseOtpInfo(url);
    final rawCode = _totpService.generateCode(url, timestamp: _now);
    final formattedCode = _formatTotpCode(rawCode);
    final seconds = _totpService.secondsRemaining(url, timestamp: _now);
    final countdownColor = _totpCountdownColor(seconds);
    final progress = seconds / 30.0;

    return Container(
      width: MediaQuery.sizeOf(context).width - 32,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              InkWell(
                onTap: () => setState(() => _step = _TotpCaptureStep.input),
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Preview 2FA Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF202939),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: const Row(
              children: <Widget>[
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: Color(0xFF059669),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '2FA code ready to add',
                    style: TextStyle(
                      color: Color(0xFF065F46),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (info.issuer.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              info.issuer,
              style: const TextStyle(
                color: Color(0xFF202939),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (info.account.isNotEmpty)
              Text(
                info.account,
                style: const TextStyle(
                  color: Color(0xFF73839D),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E9F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Current TOTP Code',
                  style: TextStyle(
                    color: Color(0xFF8A97AC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Text(
                      formattedCode,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        height: 1,
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(
                          '${seconds.toString().padLeft(2, '0')}s',
                          style: TextStyle(
                            color: countdownColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 78,
                          height: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: const Color(0xFFE8EDF5),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                countdownColor,
                              ),
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
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3E4A5E),
                    side: const BorderSide(color: Color(0xFFD6DCE6)),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(url),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Use This 2FA'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotpCameraScannerSheet extends StatefulWidget {
  const _TotpCameraScannerSheet();

  @override
  State<_TotpCameraScannerSheet> createState() =>
      _TotpCameraScannerSheetState();
}

class _TotpCameraScannerSheetState extends State<_TotpCameraScannerSheet> {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _torchOn = false;
  bool _frontCamera = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      _handled = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) {
      return;
    }
    setState(() => _torchOn = !_torchOn);
  }

  Future<void> _switchCamera() async {
    await _controller.switchCamera();
    if (!mounted) {
      return;
    }
    setState(() => _frontCamera = !_frontCamera);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.86,
        decoration: const BoxDecoration(
          color: Color(0xFF0C1820),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Row(
                children: <Widget>[
                  const Text(
                    'Scan TOTP QR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleTorch,
                    icon: Icon(
                      _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: _switchCamera,
                    icon: Icon(
                      _frontCamera
                          ? Icons.camera_rear_rounded
                          : Icons.camera_front_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) {
                          return Container(
                            color: const Color(0xFF101A23),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Camera unavailable. Allow camera permission in settings, or use manual input.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          );
                        },
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xAAFFFFFF),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Text(
                'Point camera at QR code',
                style: TextStyle(
                  color: Color(0xFFD6E1EC),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTotpCode(String? raw) {
  final value = (raw ?? '').replaceAll(RegExp(r'\s+'), '');
  if (value.length == 6) {
    return '${value.substring(0, 3)} ${value.substring(3)}';
  }
  return value.isEmpty ? '------' : value;
}

Color _totpCountdownColor(int secondsRemaining) {
  if (secondsRemaining <= 9) {
    return const Color(0xFFDC2626);
  }
  if (secondsRemaining <= 15) {
    return const Color(0xFFF59E0B);
  }
  return const Color(0xFF16A34A);
}
