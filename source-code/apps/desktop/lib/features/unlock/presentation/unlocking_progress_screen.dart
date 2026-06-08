import 'dart:async';

import 'package:flutter/material.dart';

const _kBackground = Color(0xFFF6F8FB);
const _kInk = Color(0xFF22314A);
const _kMuted = Color(0xFF73839D);
const _kAccent = Color(0xFF4B6CFF);

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
    fontFamily: 'Inter',
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RotationTransition(
                    turns: _spinCtrl,
                    child: CustomPaint(
                      size: const Size(200, 200),
                      painter: _ArcPainter(),
                    ),
                  ),
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1.0)
                        .animate(CurvedAnimation(
                      parent: _pulseCtrl,
                      curve: Curves.easeInOut,
                    )),
                    child: Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _kAccent.withValues(alpha: 0.18),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Image.asset(
                        'assets/images/lock_vault.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'Unlocking your vault',
              style: _uText(22, _kInk, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                widget.vaultName == null
                    ? 'Decrypting your secure data. This takes just a moment.'
                    : 'Decrypting “${widget.vaultName}”. This takes just a moment.',
                textAlign: TextAlign.center,
                style: _uText(14, _kMuted, fontWeight: FontWeight.w500, height: 1.4),
              ),
            ),
            const SizedBox(height: 32),
            const _DotsIndicator(),
          ],
        ),
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
