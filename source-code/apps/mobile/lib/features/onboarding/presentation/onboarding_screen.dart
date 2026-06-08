import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

const _introBackground = Color(0xFFF4F9FA);
const _introInk = Color(0xFF0A3B48);
const _introCopy = Color(0xFF3C6772);
const _introMuted = Color(0xFF5B818A);
const _introStep = Color(0xFF2F626E);
const _introDotIdle = Color(0xFFB7CCD2);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  var _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= 2) {
      widget.onFinish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _skipToLast() {
    _controller.animateToPage(
      2,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _introBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: const [_IntroOne(), _IntroTwo(), _IntroThree()],
              ),
            ),
            _BottomBar(
              index: _index,
              onPrimary: _next,
              onSkip: _skipToLast,
              onContinueFromLast: widget.onFinish,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.onPrimary,
    required this.onSkip,
    required this.onContinueFromLast,
  });

  final int index;
  final VoidCallback onPrimary;
  final VoidCallback onSkip;
  final VoidCallback onContinueFromLast;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final isLast = index == 2;
    final buttonLabel = isLast ? l.onboardingGetStarted : l.onboardingContinue;
    final buttonAction = isLast ? onContinueFromLast : onPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressDots(
            activeIndex: index,
            alignment: isLast
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
          ),
          const SizedBox(height: 18),
          if (index == 1) ...[
            _PrimaryCta(label: buttonLabel, onPressed: buttonAction),
            const SizedBox(height: 12),
            _BottomHint(l.onboardingSwipeHint),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: _introInk,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(l.onboardingSkip),
              ),
            ),
          ] else ...[
            _BottomHint(
              isLast ? l.onboardingReadyHint : l.onboardingSwipeHint,
            ),
            const SizedBox(height: 18),
            _PrimaryCta(label: buttonLabel, onPressed: buttonAction),
          ],
        ],
      ),
    );
  }
}

class _IntroOne extends StatelessWidget {
  const _IntroOne();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                Text(
                  'LumenPass',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _introInk,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFE8F4F6), Color(0xFFCBE4EA)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _StepPill('01 / 03'),
                        Spacer(),
                        _CardSnippet(
                          title: 'Save once. Sign in anywhere.',
                          body:
                              'Your passwords, cards, and notes stay in one encrypted vault you unlock.',
                          icon: Icons.password_rounded,
                        ),
                      ],
                    ),
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

class _IntroTwo extends StatelessWidget {
  const _IntroTwo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StepText('02 / 03'),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  height: 316,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0A3B48), Color(0xFF1E6678)],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          right: -18,
                          top: -18,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0x664FC6D1),
                                  blurRadius: 56,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Transform.translate(
                            offset: const Offset(0, 18),
                            child: Container(
                              width: 218,
                              height: 192,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE7F2F4),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  width: 146,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _introInk,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'Autofill in a single\ntap',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: _introInk,
                    fontSize: 34,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'LumenPass fills logins instantly, so you move faster without lowering security.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _introCopy,
                    fontSize: 16,
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

class _IntroThree extends StatelessWidget {
  const _IntroThree();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _StepText('03 / 03'),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  height: 348,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF0A3B48), Color(0xFF145262)],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.shield_outlined,
                            color: Colors.white.withValues(alpha: 0.94),
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Zero-knowledge sync keeps only\nyou in control',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'Everything stays\nprivate.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: _introInk,
                    fontSize: 34,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Your vault encrypts before sync, so only you can read it on every device.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF32555F),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
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

class _StepPill extends StatelessWidget {
  const _StepPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _introInk,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: _introBackground,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _StepText extends StatelessWidget {
  const _StepText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: _introStep,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _BottomHint extends StatelessWidget {
  const _BottomHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = text == "You're all set to begin"
        ? const Color(0xFF6A8790)
        : _introMuted;

    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    required this.activeIndex,
    this.alignment = MainAxisAlignment.center,
  });

  final int activeIndex;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignment,
      children: List.generate(3, (index) => _Dot(active: index == activeIndex)),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? _introInk : _introDotIdle,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _introInk,
          foregroundColor: _introBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

class _CardSnippet extends StatelessWidget {
  const _CardSnippet({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.87),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _introInk,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _introBackground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _introInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _introCopy,
                    height: 1.4,
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
