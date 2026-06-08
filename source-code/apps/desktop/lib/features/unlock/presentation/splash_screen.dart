import 'package:flutter/material.dart';

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

    Future.delayed(const Duration(milliseconds: 3000), () {
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
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/lumenpass-dark.png',
              width: 180,
            ),
            const SizedBox(height: 32),
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
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: _PulseDot(controller: controller, delay: i * 0.22),
          );
        }),
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
    final offsetAnim = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          delay.clamp(0.0, 0.7),
          (delay + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeInOut,
        ),
      ),
    );
    final opacityAnim = Tween<double>(begin: 0.35, end: 1.0).animate(
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
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, offsetAnim.value),
          child: Opacity(
            opacity: opacityAnim.value,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}
