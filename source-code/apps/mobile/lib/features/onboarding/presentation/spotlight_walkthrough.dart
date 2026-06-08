import 'package:flutter/material.dart';

class SpotlightWalkthroughStep {
  const SpotlightWalkthroughStep({
    required this.key,
    required this.title,
    this.message,
    this.borderRadius = 18,
  });

  final GlobalKey key;
  final String title;
  final String? message;
  final double borderRadius;
}

class SpotlightWalkthroughOverlay extends StatefulWidget {
  const SpotlightWalkthroughOverlay({
    super.key,
    required this.steps,
    required this.initialIndex,
    required this.onStepChanged,
    required this.onFinish,
    required this.onSkip,
  });

  final List<SpotlightWalkthroughStep> steps;
  final int initialIndex;
  final ValueChanged<int> onStepChanged;
  final VoidCallback onFinish;
  final VoidCallback onSkip;

  @override
  State<SpotlightWalkthroughOverlay> createState() =>
      _SpotlightWalkthroughOverlayState();
}

class _SpotlightWalkthroughOverlayState
    extends State<SpotlightWalkthroughOverlay>
    with WidgetsBindingObserver {
  late int _index;
  Rect? _targetRect;

  SpotlightWalkthroughStep get _step => widget.steps[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex.clamp(0, widget.steps.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant SpotlightWalkthroughOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _measure() async {
    if (!mounted) return;
    final context = _step.key.currentContext;
    if (context == null) return;

    await Scrollable.ensureVisible(
      context,
      duration: MediaQuery.disableAnimationsOf(this.context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.42,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );

    if (!mounted) return;
    final renderObject = _step.key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final offset = renderObject.localToGlobal(Offset.zero);
    setState(() => _targetRect = offset & renderObject.size);
  }

  void _next() {
    if (_index >= widget.steps.length - 1) {
      widget.onFinish();
      return;
    }
    setState(() => _index += 1);
    widget.onStepChanged(_index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index -= 1);
    widget.onStepChanged(_index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    final target = _targetRect;
    if (target == null || widget.steps.isEmpty) {
      return const SizedBox.expand();
    }

    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final curve = Curves.easeOutCubic;
    final spotlightRect = target.inflate(8);

    return Semantics(
      label:
          'Walkthrough step ${_index + 1} of ${widget.steps.length}. ${_step.title}',
      explicitChildNodes: true,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: spotlightRect),
                duration: duration,
                curve: curve,
                builder: (context, rect, _) {
                  return CustomPaint(
                    painter: _SpotlightPainter(
                      target: rect ?? spotlightRect,
                      borderRadius: _step.borderRadius + 8,
                    ),
                  );
                },
              ),
            ),
            _TooltipCard(
              target: target,
              step: _step,
              index: _index,
              count: widget.steps.length,
              duration: duration,
              curve: curve,
              onBack: _index == 0 ? null : _back,
              onNext: _next,
              onSkip: widget.onSkip,
            ),
          ],
        ),
      ),
    );
  }
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.target,
    required this.step,
    required this.index,
    required this.count,
    required this.duration,
    required this.curve,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final Rect target;
  final SpotlightWalkthroughStep step;
  final int index;
  final int count;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const width = 248.0;
    const margin = 18.0;
    const pointerSize = 14.0;
    final topCandidate = target.bottom + pointerSize + 10;
    final forceAbove = index >= 3;
    final showAbove = forceAbove || topCandidate + 132 > size.height;
    final aboveOffset = forceAbove ? 208.0 : 176.0;
    final top = showAbove
        ? target.top - aboveOffset - pointerSize
        : topCandidate;
    final left = (target.center.dx - width / 2).clamp(
      margin,
      size.width - width - margin,
    );
    final safeTop = top.clamp(margin, size.height - 178).toDouble();
    final pointerLeft = (target.center.dx - left - pointerSize / 2).clamp(
      18.0,
      width - 18.0 - pointerSize,
    );
    final isLast = index == count - 1;

    return AnimatedPositioned(
      duration: duration,
      curve: curve,
      left: left,
      top: safeTop,
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!showAbove)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: pointerLeft),
                child: const _TooltipPointer(pointsUp: true),
              ),
            ),
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: curve,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: Container(
              key: ValueKey(index),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${index + 1}/$count',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  if (step.message != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      step.message!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TextButton(
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.76),
                        ),
                        child: const Text('Skip'),
                      ),
                      if (onBack != null) ...[
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: onBack,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(
                              alpha: 0.58,
                            ),
                          ),
                          child: const Text('Back'),
                        ),
                      ],
                      const Spacer(),
                      FilledButton(
                        onPressed: onNext,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(76, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(isLast ? 'Done' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (showAbove)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: pointerLeft),
                child: const _TooltipPointer(pointsUp: false),
              ),
            ),
        ],
      ),
    );
  }
}

class _TooltipPointer extends StatelessWidget {
  const _TooltipPointer({required this.pointsUp});

  final bool pointsUp;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(14, 14),
      painter: _TooltipPointerPainter(pointsUp: pointsUp),
    );
  }
}

class _TooltipPointerPainter extends CustomPainter {
  const _TooltipPointerPainter({required this.pointsUp});

  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xF2080D14));
  }

  @override
  bool shouldRepaint(covariant _TooltipPointerPainter oldDelegate) {
    return oldDelegate.pointsUp != pointsUp;
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.target, required this.borderRadius});

  final Rect target;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    final cutout = Path()
      ..addRRect(
        RRect.fromRectAndRadius(target, Radius.circular(borderRadius)),
      );
    final path = Path.combine(PathOperation.difference, overlay, cutout);
    canvas.drawPath(path, Paint()..color = const Color(0xA6000000));

    final rrect = RRect.fromRectAndRadius(
      target,
      Radius.circular(borderRadius),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.82),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..color = Colors.white.withValues(alpha: 0.20),
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.target != target ||
        oldDelegate.borderRadius != borderRadius;
  }
}
