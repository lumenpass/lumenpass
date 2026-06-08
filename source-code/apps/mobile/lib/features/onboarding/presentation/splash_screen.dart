import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: false);

    _pulseScale = Tween<double>(begin: 0.6, end: 1.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    Future.delayed(const Duration(milliseconds: 3000), () {
      if (mounted) widget.onGetStarted();
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
            _HeartbeatDots(
              pulseScale: _pulseScale,
              pulseOpacity: _pulseOpacity,
              controller: _pulseController,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartbeatDots extends StatelessWidget {
  const _HeartbeatDots({
    required this.pulseScale,
    required this.pulseOpacity,
    required this.controller,
  });

  final Animation<double> pulseScale;
  final Animation<double> pulseOpacity;
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
            child: _PulseDot(
              controller: controller,
              delay: i * 0.22,
            ),
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
    final offsetAnimation = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(delay.clamp(0.0, 0.7), (delay + 0.4).clamp(0.0, 1.0),
            curve: Curves.easeInOut),
      ),
    );

    final opacityAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(delay.clamp(0.0, 0.7), (delay + 0.4).clamp(0.0, 1.0),
            curve: Curves.easeInOut),
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, offsetAnimation.value),
          child: Opacity(
            opacity: opacityAnimation.value,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
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
