import 'package:flutter/material.dart';

/// Shared elevated container that gives the app its soft, desktop-like panels.
class SectionSurface extends StatelessWidget {
  const SectionSurface({
    this.child,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.68),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
