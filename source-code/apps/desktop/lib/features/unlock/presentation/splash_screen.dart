import 'package:flutter/material.dart';

import '../../../presentation/widgets/lumenpass_wordmark.dart';

const Color _kPaper = Color(0xFFF7F4EC);
const Color _kOrange = Color(0xFFFF5B22);
const Color _kMuted = Color(0xFF626560);

class DesktopSplashScreen extends StatefulWidget {
  const DesktopSplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<DesktopSplashScreen> createState() => _DesktopSplashScreenState();
}

class _DesktopSplashScreenState extends State<DesktopSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    Future<void>.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPaper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const LumenPassWordmark(
              key: ValueKey<String>('splash-wordmark'),
              fontSize: 38,
            ),
            const SizedBox(height: 9),
            const Text(
              'Private by default. Yours to control.',
              style: TextStyle(
                color: _kMuted,
                fontFamily: 'Ubuntu Sans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 25),
            _HeartbeatDots(controller: _pulseController),
          ],
        ),
      ),
    );
  }
}

class _HeartbeatDots extends StatelessWidget {
  const _HeartbeatDots({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey<String>('splash-loading-dots'),
      label: 'Loading LumenPass',
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List<Widget>.generate(3, (int index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _PulseDot(
                controller: controller,
                delay: index * 0.22,
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.controller, required this.delay});

  final AnimationController controller;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final Animation<double> offsetAnimation = Tween<double>(
      begin: 0,
      end: -6,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          delay.clamp(0.0, 0.7),
          (delay + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeInOut,
        ),
      ),
    );

    final Animation<double> opacityAnimation = Tween<double>(
      begin: 0.28,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          delay.clamp(0.0, 0.7),
          (delay + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeInOut,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(0, offsetAnimation.value),
          child: Opacity(opacity: opacityAnimation.value, child: child),
        );
      },
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: _kOrange,
        ),
      ),
    );
  }
}
