import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../theme/drive_clue_tokens.dart';

// ── Light content palette ────────────────────────────────────────────────────
const Color _kCanvas = DcColors.sidebar;
const Color _kPaperBright = DcColors.lightSurface;
const Color _kBorderSoft = DcColors.sidebarLine;
const Color _kTitle = DcColors.sidebarText;
const Color _kLabel = DcColors.sidebarMuted;
const Color _kIconColor = DcColors.sidebarMuted;

// ── Dark header palette (matches the vault title bar) ───────────────────────
const Color _kHeaderBg = DcColors.background;
const Color _kHeaderLine = DcColors.shellDivider;
const Color _kHeaderTitle = DcColors.text;
const Color _kHeaderLabel = DcColors.muted;
const Color _kHeaderControl = DcColors.panel;
const Color _kHeaderControlHover = DcColors.panelRaised;
const Color _kHeaderControlLine = DcColors.lineStrong;

TextStyle _t(
  double size,
  Color color, {
  FontWeight weight = FontWeight.w500,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Ubuntu Sans',
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: height,
    letterSpacing: 0,
  );
}

TextStyle _serif(double size, Color color, {double? height}) {
  return TextStyle(
    fontFamily: 'Ubuntu Sans',
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    height: height,
    letterSpacing: -0.2,
  );
}

/// A full-window, inner-page shell for flows that used to be modal dialogs.
///
/// Background: every wizard and provider-config surface in this app used to be
/// a [Dialog] drawn inside the single application window. Because those dialogs
/// were taller than the shell they lived in, each one had to call
/// `lumenpass/window setSize` before opening and shrink the window again on
/// close. That made the whole app window jump up and down as the user moved
/// between features.
///
/// With [DcFlowPage] those surfaces are ordinary pushed routes instead, so the
/// window stays at one fixed size for the app's whole lifetime.
///
/// The shell mirrors the established title-bar + light-content convention:
/// a dark 46 px header (optionally clearing the macOS traffic lights), a light
/// scrollable body, and a light footer for the primary actions.
class DcFlowPage extends StatelessWidget {
  const DcFlowPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    this.iconBackground,
    this.trailing,
    this.footer,
    this.onBack,
    this.scrollable = true,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 22, 24, 28),
    this.inset = true,
    this.accentColor,
  });

  /// Short page title shown inline in the dark title bar.
  final String title;

  /// One-line description shown after the title in the dark title bar.
  final String subtitle;

  /// Leading square badge icon in the title bar.
  final IconData icon;

  /// Optional solid background for the icon badge. When null, a subtle
  /// translucent tile is used.
  final Color? iconBackground;

  /// Body of the page, rendered inside a light card.
  final Widget body;

  /// Optional widget anchored at the trailing end of the title bar, before the
  /// back button (e.g. step indicators).
  final Widget? trailing;

  /// Optional footer bar for the page's primary actions.
  final Widget? footer;

  /// Back navigation. Defaults to popping the enclosing route.
  final VoidCallback? onBack;

  /// Whether the body should scroll. Set false for bodies that manage their own
  /// scrolling (e.g. a table with a fixed header).
  final bool scrollable;

  final EdgeInsets contentPadding;

  /// Whether the light card is inset from the window edges. Set false for
  /// full-bleed content such as long lists that should reach the header.
  final bool inset;

  /// Optional accent colour used for the icon badge border/tint.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final bool isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final Widget content = body;
    final Widget scrollableBody = scrollable
        ? SingleChildScrollView(padding: contentPadding, child: content)
        : Padding(padding: contentPadding, child: content);

    return Scaffold(
      backgroundColor: _kCanvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(context, isMacOS: isMacOS),
          Expanded(
            child: inset
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _buildCard(scrollableBody),
                  )
                : scrollableBody,
          ),
          if (footer != null) _buildFooter(footer!),
        ],
      ),
    );
  }

  Widget _buildCard(Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kPaperBright,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: _kBorderSoft),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: DcColors.lightCardShadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        child: child,
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {required bool isMacOS}) {
    return Container(
      height: DcMetrics.headerHeight,
      padding: EdgeInsets.only(left: isMacOS ? 94 : 16, right: 12),
      decoration: const BoxDecoration(
        color: _kHeaderBg,
        border: Border(bottom: BorderSide(color: _kHeaderLine)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground ?? _kHeaderControl,
              borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
              border: Border.all(
                color: iconBackground == null
                    ? _kHeaderControlLine
                    : Colors.transparent,
              ),
            ),
            child: Icon(icon, size: 16, color: _kHeaderTitle),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            maxLines: 1,
            softWrap: false,
            style: _serif(15, _kHeaderTitle),
          ),
          const SizedBox(width: 8),
          Text('·', style: _t(13, _kHeaderLabel)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: _t(12, _kHeaderLabel),
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
          const SizedBox(width: 12),
          _BackIconButton(
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(Widget footer) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: _kCanvas,
        border: Border(top: BorderSide(color: _kBorderSoft)),
      ),
      child: footer,
    );
  }
}

/// Circular back control matched to the vault title bar's controls.
class _BackIconButton extends StatefulWidget {
  const _BackIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BackIconButton> createState() => _BackIconButtonState();
}

class _BackIconButtonState extends State<_BackIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hovered ? _kHeaderControlHover : _kHeaderControl,
              shape: BoxShape.circle,
              border: Border.all(color: _kHeaderControlLine),
            ),
            child: const Icon(
              TablerIcons.arrow_left,
              size: 16,
              color: _kHeaderTitle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Section label used inside [DcFlowPage] bodies: a small, tracked-out caption
/// above a group of rows.
class DcFlowSectionLabel extends StatelessWidget {
  const DcFlowSectionLabel({super.key, required this.label, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: _t(
            DcMetrics.sectionLabelSize,
            _kLabel,
            weight: FontWeight.w700,
          ).copyWith(letterSpacing: DcMetrics.sectionLabelTracking),
        ),
        if (count != null) ...<Widget>[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _kCanvas,
              borderRadius: BorderRadius.circular(DcMetrics.badgeRadius),
              border: Border.all(color: _kBorderSoft),
            ),
            child: Text(
              '$count',
              style: _t(10, _kLabel, weight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

/// Light, bordered card used to group rows inside a [DcFlowPage] body.
class DcFlowCard extends StatelessWidget {
  const DcFlowCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _kCanvas,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: _kBorderSoft),
      ),
      child: child,
    );
  }
}

/// Footer button matching the shell's action styling.
class DcFlowButton extends StatelessWidget {
  const DcFlowButton({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;
    final Color fg = primary ? Colors.white : _kTitle;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (busy) ...<Widget>[
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
        Text(label),
        if (icon != null && !busy) ...<Widget>[
          const SizedBox(width: 6),
          Icon(icon, size: 15),
        ],
      ],
    );

    final style = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll<Color>(
        primary ? DcColors.selection : _kPaperBright,
      ),
      foregroundColor: WidgetStatePropertyAll<Color>(fg),
      overlayColor: WidgetStatePropertyAll<Color>(
        primary ? Colors.white24 : _kHeaderControlHover,
      ),
      elevation: const WidgetStatePropertyAll<double>(0),
      padding: const WidgetStatePropertyAll<EdgeInsets>(
        EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        ),
      ),
      side: WidgetStatePropertyAll<BorderSide>(
        primary
            ? BorderSide.none
            : const BorderSide(color: DcColors.lightLineStrong),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        _t(12, fg, weight: FontWeight.w600),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 36)),
    );

    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: style,
      child: child,
    );
  }
}

/// Reusable header step-indicator ("Step 1 of 2") for multi-step flows.
class DcFlowStepDots extends StatelessWidget {
  const DcFlowStepDots({
    super.key,
    required this.total,
    required this.current,
  });

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < total; i++) ...<Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == current ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i <= current
                  ? DcColors.selection
                  : _kHeaderControlLine,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (i != total - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// Muted, centered placeholder shown when a flow has nothing to list yet.
class DcFlowEmptyState extends StatelessWidget {
  const DcFlowEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kCanvas,
              borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
              border: Border.all(color: _kBorderSoft),
            ),
            child: Icon(icon, size: 20, color: _kIconColor),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: _t(13, _kTitle, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: _t(11, _kLabel, height: 1.5),
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}
