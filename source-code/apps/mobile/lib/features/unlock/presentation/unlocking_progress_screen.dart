import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

const _kBackground = Color(0xFFF4F9FA);
const _kSurface = Color(0xFFFFFFFF);
const _kInk = Color(0xFF0A3B48);
const _kMuted = Color(0xFF4A6670);
const _kFaint = Color(0xFF7A93A0);
const _kAccent = Color(0xFF0A67FF);
const _kAccentSoft = Color(0xFFE4ECFA);

/// Full-screen intermediate step shown after the user submits credentials on
/// the Unlock Vault screen and before the Home screen.
///
/// Runs [unlockTask] in parallel with a minimum-visible animation so the
/// spinner/lock art never flashes. On success it invokes [onSuccess]; on
/// failure it invokes [onFailure] with the error message (the caller pops
/// back to the Unlock Vault screen).
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
  static const _kInitialDeferral = Duration(milliseconds: 350);
  static const _kPhaseStep = Duration(milliseconds: 720);

  static const List<String> _phases = <String>[
    'Preparing your keys',
    'Decrypting your vault',
    'Verifying integrity',
    'Almost there',
  ];

  late final AnimationController _spinCtrl;
  late final AnimationController _breathCtrl;
  late final AnimationController _barCtrl;
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<double> _entryScale;
  late final Animation<Offset> _entrySlide;

  int _phaseIndex = 0;
  Timer? _phaseTimer;
  bool _reduceMotion = false;
  bool _runStarted = false;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _entryFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );
    _entryScale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutQuint),
    );
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _runStarted) return;
      _runStarted = true;
      _entryCtrl.forward();
      _run();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      if (mounted) setState(() {});
    }
    _applyMotionPreference();
  }

  void _applyMotionPreference() {
    if (_reduceMotion) {
      if (_spinCtrl.isAnimating) _spinCtrl.stop();
      if (_breathCtrl.isAnimating) _breathCtrl.stop();
      if (_barCtrl.isAnimating) _barCtrl.stop();
      _spinCtrl.value = 0;
      _breathCtrl.value = 0.5;
      _barCtrl.value = 0.6;
    } else {
      if (!_spinCtrl.isAnimating) _spinCtrl.repeat();
      if (!_breathCtrl.isAnimating) _breathCtrl.repeat(reverse: true);
      if (!_barCtrl.isAnimating) _barCtrl.repeat();
    }
  }

  Future<void> _run() async {
    final started = DateTime.now();
    _phaseTimer = Timer.periodic(_kPhaseStep, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_phaseIndex < _phases.length - 1) {
        setState(() => _phaseIndex++);
      }
    });
    try {
      await Future<void>.delayed(_kInitialDeferral);
      await widget.unlockTask();
      await _awaitMinVisible(started);
      _phaseTimer?.cancel();
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      _phaseTimer?.cancel();
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
    _phaseTimer?.cancel();
    _spinCtrl.dispose();
    _breathCtrl.dispose();
    _barCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortest = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final heroSize = shortest.isFinite
                ? math.min(220.0, math.max(160.0, shortest * 0.48))
                : 200.0;
            final maxContentWidth = math.min(420.0, constraints.maxWidth);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FadeTransition(
                    opacity: _entryFade,
                    child: SlideTransition(
                      position: _entrySlide,
                      child: ScaleTransition(
                        scale: _entryScale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Hero(
                              size: heroSize,
                              spin: _spinCtrl,
                              breath: _breathCtrl,
                              reduceMotion: _reduceMotion,
                            ),
                            SizedBox(height: heroSize * 0.22),
                            const Text(
                              'Unlocking your vault',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _kInk,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                widget.vaultName == null
                                    ? 'Decrypting your secure data. This will take just a moment.'
                                    : 'Decrypting “${widget.vaultName}”. This will take just a moment.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _kMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            _PhaseLabel(text: _phases[_phaseIndex]),
                            const SizedBox(height: 14),
                            _ShimmerBar(
                              animation: _barCtrl,
                              reduceMotion: _reduceMotion,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Hero composition ─────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.size,
    required this.spin,
    required this.breath,
    required this.reduceMotion,
  });

  final double size;
  final Animation<double> spin;
  final Animation<double> breath;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final innerSize = size * 0.62;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _AmbientHalo(size: size),
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: spin,
                builder: (_, _) => CustomPaint(
                  size: Size.square(size),
                  painter: _SweepArcPainter(
                    rotation: spin.value,
                    reduceMotion: reduceMotion,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: breath,
              builder: (_, child) {
                final t = reduceMotion
                    ? 1.0
                    : Curves.easeInOut.transform(breath.value);
                final scale = 0.94 + 0.06 * t;
                return Transform.scale(scale: scale, child: child);
              },
              child: _LockDisk(size: innerSize),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientHalo extends StatelessWidget {
  const _AmbientHalo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              _kAccent.withValues(alpha: 0.10),
              _kAccent.withValues(alpha: 0.0),
            ],
            stops: const [0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

class _LockDisk extends StatelessWidget {
  const _LockDisk({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _kSurface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _kAccent.withValues(alpha: 0.18),
            blurRadius: 32,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _kInk.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.22),
      child: Image.asset(
        'assets/icons/lock_vault.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class _SweepArcPainter extends CustomPainter {
  _SweepArcPainter({required this.rotation, required this.reduceMotion});

  final double rotation;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - 8;
    final strokeWidth = math.max(3.5, size.width * 0.022);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = _kAccent.withValues(alpha: 0.10);
    canvas.drawCircle(center, radius, track);

    if (reduceMotion) {
      final still = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = _kAccent.withValues(alpha: 0.85);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 0.85,
        false,
        still,
      );
      return;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * 2 * math.pi);
    canvas.translate(-center.dx, -center.dy);

    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: [
        _kAccent.withValues(alpha: 0.0),
        _kAccent.withValues(alpha: 0.18),
        _kAccent.withValues(alpha: 0.85),
        _kAccent.withValues(alpha: 1.0),
      ],
      stops: const [0.0, 0.45, 0.88, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..shader = shader;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.55,
      false,
      sweep,
    );

    final tipAngle = -math.pi / 2 + math.pi * 1.55;
    final tip = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    final tipGlow = Paint()
      ..color = _kAccent.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(tip, strokeWidth * 1.1, tipGlow);
    final tipPaint = Paint()..color = _kAccent;
    canvas.drawCircle(tip, strokeWidth * 0.7, tipPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SweepArcPainter old) =>
      old.rotation != rotation || old.reduceMotion != reduceMotion;
}

// ── Phase label & shimmer bar ────────────────────────────────────────────────

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Text(
        text,
        key: ValueKey<String>(text),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _kFaint,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 168,
          height: 4,
          color: _kAccentSoft,
          child: reduceMotion
              ? const _StaticBarFill()
              : AnimatedBuilder(
                  animation: animation,
                  builder: (_, _) => CustomPaint(
                    painter: _ShimmerPainter(progress: animation.value),
                  ),
                ),
        ),
      ),
    );
  }
}

class _StaticBarFill extends StatelessWidget {
  const _StaticBarFill();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.6,
        heightFactor: 1,
        child: Container(color: _kAccent.withValues(alpha: 0.85)),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final segWidth = size.width * 0.55;
    final travel = size.width + segWidth;
    final eased = Curves.easeInOutCubic.transform(progress);
    final dx = -segWidth + travel * eased;
    final rect = Rect.fromLTWH(dx, 0, segWidth, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          _kAccent.withValues(alpha: 0.0),
          _kAccent.withValues(alpha: 0.95),
          _kAccent.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter old) =>
      old.progress != progress;
}
