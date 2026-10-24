import 'dart:async';

import 'package:flutter/material.dart';

import '../../../presentation/theme/drive_clue_tokens.dart';

// ── Light palette (matches the unlock credentials dialog) ───────────────────
const _kBackground = DcColors.sidebar;
const _kPaperBright = DcColors.lightSurface;
const _kCardBorder = DcColors.sidebarLine;
const _kCardShadow = DcColors.lightCardShadow;
const _kInk = DcColors.sidebarText;
const _kMuted = DcColors.sidebarMuted;
const _kAccent = DcColors.selection;
const _kPeach = DcColors.lightSelectionFill;
const _kMint = DcColors.tealOnLight;
const _kMintSoft = Color(0x1F1F8A7D);

TextStyle _uText(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double height = 1.3,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: fontWeight,
    fontFamily: 'Ubuntu Sans',
    height: height,
  );
}

TextStyle _displayText(double size, Color color, {double? height}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    fontFamily: 'Ubuntu Sans',
    letterSpacing: -0.45,
    height: height,
  );
}

/// Desktop counterpart to the mobile `UnlockingProgressScreen`.
///
/// Runs [unlockTask] in parallel with a minimum-visible animation so the
/// spinner/lock art never flashes. On success it invokes [onSuccess]; on
/// failure it invokes [onFailure] with the error message (the caller pops
/// back to the credentials dialog).
class UnlockingProgressScreen extends StatefulWidget {
  const UnlockingProgressScreen({
    super.key,
    required this.unlockTask,
    required this.onSuccess,
    required this.onFailure,
    this.vaultName,
  });

  final Future<void> Function() unlockTask;
  final VoidCallback onSuccess;
  final void Function(String message) onFailure;
  final String? vaultName;

  @override
  State<UnlockingProgressScreen> createState() =>
      _UnlockingProgressScreenState();
}

class _UnlockingProgressScreenState extends State<UnlockingProgressScreen>
    with TickerProviderStateMixin {
  static const _kMinVisible = Duration(milliseconds: 1400);

  late final AnimationController _spinCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _run();
    });
  }

  Future<void> _run() async {
    final started = DateTime.now();
    try {
      // Let the route transition + first paint finish before kicking off the
      // heavy KDBX decrypt, which blocks the UI isolate.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await widget.unlockTask();
      await _awaitMinVisible(started);
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      await _awaitMinVisible(started);
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      widget.onFailure(msg.isEmpty ? 'Unlock failed. Please try again.' : msg);
    }
  }

  Future<void> _awaitMinVisible(DateTime started) async {
    final elapsed = DateTime.now().difference(started);
    final remaining = _kMinVisible - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: Stack(
        children: <Widget>[
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.fromLTRB(40, 30, 40, 32),
                decoration: BoxDecoration(
                  color: _kPaperBright,
                  borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
                  border: Border.all(color: _kCardBorder),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: _kCardShadow,
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _kAccent,
                        borderRadius:
                            BorderRadius.circular(DcMetrics.badgeRadius),
                      ),
                      child: Text(
                        'SECURE VAULT',
                        style: _uText(
                          DcMetrics.sectionLabelSize,
                          Colors.white,
                          fontWeight: FontWeight.w700,
                        ).copyWith(
                          letterSpacing: DcMetrics.sectionLabelTracking,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 144,
                      height: 144,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          RotationTransition(
                            turns: _spinCtrl,
                            child: CustomPaint(
                              size: const Size(144, 144),
                              painter: _ArcPainter(),
                            ),
                          ),
                          ScaleTransition(
                            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                              CurvedAnimation(
                                parent: _pulseCtrl,
                                curve: Curves.easeInOut,
                              ),
                            ),
                            child: Container(
                              width: 88,
                              height: 88,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _kPeach,
                                borderRadius: BorderRadius.circular(
                                  DcMetrics.panelRadius + 7,
                                ),
                              ),
                              child: Image.asset(
                                'assets/images/lock_vault.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Unlocking your vault',
                      style: _displayText(27, _kInk, height: 1.05),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      widget.vaultName == null
                          ? 'Decrypting your secure data. This takes just a moment.'
                          : 'Decrypting “${widget.vaultName}”. This takes just a moment.',
                      textAlign: TextAlign.center,
                      style: _uText(
                        11.5,
                        _kMuted,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _kMintSoft,
                        borderRadius:
                            BorderRadius.circular(DcMetrics.badgeRadius),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.shield_outlined,
                            size: 13,
                            color: _kMint,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'VERIFYING CREDENTIALS',
                            style: _uText(
                              8.5,
                              _kInk,
                              fontWeight: FontWeight.w800,
                            ).copyWith(letterSpacing: 0.75),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _DotsIndicator(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - 6;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = _kAccent.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..shader = SweepGradient(
        colors: [
          _kAccent.withValues(alpha: 0.0),
          _kAccent.withValues(alpha: 0.9),
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      2.3,
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DotsIndicator extends StatefulWidget {
  const _DotsIndicator();

  @override
  State<_DotsIndicator> createState() => _DotsIndicatorState();
}

class _DotsIndicatorState extends State<_DotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (t + i * 0.18) % 1.0;
            final scale = 0.7 + 0.6 * (1 - (phase * 2 - 1).abs());
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: _kAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
