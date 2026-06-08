import 'dart:async';

import 'package:flutter/material.dart';

enum SnackBarVariant { success, error, info }

abstract final class AppSnackBar {
  static const _defaultDuration = Duration(seconds: 15);

  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;

  static void show(
    BuildContext context,
    String message, {
    SnackBarVariant variant = SnackBarVariant.info,
    Duration duration = _defaultDuration,
    IconData? icon,
    Color? backgroundColor,
  }) {
    final overlay =
        Navigator.maybeOf(context, rootNavigator: true)?.overlay ??
        Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    showOnOverlay(
      overlay,
      message,
      variant: variant,
      duration: duration,
      icon: icon,
      backgroundColor: backgroundColor,
    );
  }

  static void showOnOverlay(
    OverlayState overlay,
    String message, {
    SnackBarVariant variant = SnackBarVariant.info,
    Duration duration = _defaultDuration,
    IconData? icon,
    Color? backgroundColor,
  }) {
    final media = MediaQuery.maybeOf(overlay.context);
    final viewInsetsBottom = media?.viewInsets.bottom ?? 0;
    final safeBottom = media?.padding.bottom ?? 0;
    final bottomOffset =
        (viewInsetsBottom > 0 ? viewInsetsBottom : safeBottom) + 16;
    final style = _resolveStyle(
      variant,
      icon: icon,
      backgroundColor: backgroundColor,
    );

    dismissCurrent();

    late final OverlayEntry entry;
    void dismiss() {
      _activeTimer?.cancel();
      _activeTimer = null;
      if (_activeEntry == entry) {
        _activeEntry = null;
      }
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: bottomOffset,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: _ToastEntrance(
            child: _ToastBanner(
              message: message,
              backgroundColor: style.backgroundColor,
              accentColor: style.accentColor,
              icon: style.icon,
              onDismiss: dismiss,
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    _activeEntry = entry;
    _activeTimer = Timer(duration, dismiss);
  }

  static void dismissCurrent() {
    _activeTimer?.cancel();
    _activeTimer = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }

  static _ToastStyle _resolveStyle(
    SnackBarVariant variant, {
    IconData? icon,
    Color? backgroundColor,
  }) {
    final defaults = switch (variant) {
      SnackBarVariant.success => _ToastStyle(
        backgroundColor: const Color(0xFF15803D),
        accentColor: const Color(0xFF15803D),
        icon: Icons.check_circle_rounded,
      ),
      SnackBarVariant.error => _ToastStyle(
        backgroundColor: const Color(0xFFC43B32),
        accentColor: const Color(0xFFC43B32),
        icon: Icons.error_rounded,
      ),
      SnackBarVariant.info => _ToastStyle(
        backgroundColor: const Color(0xFF1C2A32),
        accentColor: const Color(0xFF1C2A32),
        icon: Icons.info_rounded,
      ),
    };
    return _ToastStyle(
      backgroundColor: backgroundColor ?? defaults.backgroundColor,
      accentColor: backgroundColor ?? defaults.accentColor,
      icon: icon ?? defaults.icon,
    );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
  }) => show(
    context,
    message,
    variant: SnackBarVariant.success,
    duration: duration,
  );

  static void error(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
  }) => show(
    context,
    message,
    variant: SnackBarVariant.error,
    duration: duration,
  );

  static void info(
    BuildContext context,
    String message, {
    Duration duration = _defaultDuration,
  }) =>
      show(context, message, variant: SnackBarVariant.info, duration: duration);
}

class _ToastStyle {
  const _ToastStyle({
    required this.backgroundColor,
    required this.accentColor,
    required this.icon,
  });

  final Color backgroundColor;
  final Color accentColor;
  final IconData icon;
}

class _ToastEntrance extends StatefulWidget {
  const _ToastEntrance({required this.child});

  final Widget child;

  @override
  State<_ToastEntrance> createState() => _ToastEntranceState();
}

class _ToastEntranceState extends State<_ToastEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.28),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class _ToastBanner extends StatelessWidget {
  const _ToastBanner({
    required this.message,
    required this.backgroundColor,
    required this.accentColor,
    required this.icon,
    required this.onDismiss,
  });

  final String message;
  final Color backgroundColor;
  final Color accentColor;
  final IconData icon;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.24,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
