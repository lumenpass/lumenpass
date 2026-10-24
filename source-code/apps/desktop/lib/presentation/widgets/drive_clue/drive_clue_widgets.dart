import 'package:flutter/material.dart';

import '../../theme/drive_clue_tokens.dart';

/// Shared DriveClue-style building blocks. They are purely presentational:
/// every callback is passed through untouched.

TextStyle _dcStyle(
  double size,
  Color color, {
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Rounded-7 slate panel (DriveClue's `.panel()` modifier).
class DcPanel extends StatelessWidget {
  const DcPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DcMetrics.panelPadding),
    this.color = DcColors.panel,
    this.bordered = false,
    this.width,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool bordered;
  final double? width;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: bordered ? Border.all(color: DcColors.line) : null,
      ),
      child: child,
    );
  }
}

/// A 21 px tinted icon followed by a 15 px semibold title.
class DcSectionHeader extends StatelessWidget {
  const DcSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.tint = DcColors.muted,
    this.titleColor = DcColors.text,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color tint;

  /// Title text color; override with a dark color on light surfaces.
  final Color titleColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 27,
            height: 27,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(icon, size: 21, color: tint),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _dcStyle(15, titleColor, weight: FontWeight.w600),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Uppercase caption strip above a striped table.
class DcTableHeader extends StatelessWidget {
  const DcTableHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.height = DcMetrics.tableHeaderHeight,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double height;

  /// The caption text style used inside table headers.
  static TextStyle get captionStyle => _dcStyle(
        10,
        DcColors.muted,
        weight: FontWeight.w700,
        letterSpacing: 0.5,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: const BoxDecoration(
        color: DcColors.rowAlternate,
        border: Border(bottom: BorderSide(color: DcColors.line)),
      ),
      alignment: Alignment.centerLeft,
      child: DefaultTextStyle.merge(style: captionStyle, child: child),
    );
  }
}

/// Striped table row; even rows use [DcColors.row], odd rows
/// [DcColors.rowAlternate].
class DcStripedRow extends StatelessWidget {
  const DcStripedRow({
    super.key,
    required this.index,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    this.selected = false,
  });

  final int index;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;

  static Color colorFor(int index, {bool selected = false}) {
    if (selected) return DcColors.selection;
    return index.isEven ? DcColors.row : DcColors.rowAlternate;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      color: colorFor(index, selected: selected),
      child: DefaultTextStyle.merge(
        style: _dcStyle(12, DcColors.text),
        child: child,
      ),
    );
  }
}

/// Small solid badge with 11 px bold white text (radius 4).
class DcStatusBadge extends StatelessWidget {
  const DcStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.minWidth = 0,
    this.foreground = Colors.white,
  });

  final String label;
  final Color color;
  final double minWidth;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(DcMetrics.badgeRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        style: _dcStyle(11, foreground, weight: FontWeight.w700),
      ),
    );
  }
}

/// Thin progress bar (radius 2, dark track).
class DcProgressBar extends StatelessWidget {
  const DcProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
  });

  /// 0.0 – 1.0.
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: ColoredBox(color: DcColors.barTrack),
            ),
            FractionallySizedBox(
              widthFactor: clamped,
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _DcHoverButton extends StatefulWidget {
  const _DcHoverButton({
    required this.builder,
    required this.onPressed,
    this.tooltip,
  });

  final Widget Function(bool hovered, bool enabled) builder;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  State<_DcHoverButton> createState() => _DcHoverButtonState();
}

class _DcHoverButtonState extends State<_DcHoverButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Widget result = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: widget.builder(_hovered && enabled, enabled),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      result = Tooltip(message: tooltip, child: result);
    }
    return result;
  }
}

/// Small macOS-style bordered button (SwiftUI `.bordered`, `.small`).
class DcBorderedButton extends StatelessWidget {
  const DcBorderedButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.tooltip,
    this.height = 26,
    this.foreground = DcColors.text,
    this.semanticLabel,
  });

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final double height;
  final Color foreground;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? label ?? tooltip,
      child: _DcHoverButton(
        onPressed: onPressed,
        tooltip: tooltip,
        builder: (hovered, enabled) {
          final fg = enabled ? foreground : DcColors.faint;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            height: height,
            padding: EdgeInsets.symmetric(horizontal: label == null ? 6 : 10),
            decoration: BoxDecoration(
              color: hovered
                  ? const Color(0x2EFFFFFF)
                  : const Color(0x17FFFFFF),
              borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
              border: Border.all(color: DcColors.lineStrong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) Icon(icon, size: 14, color: fg),
                if (icon != null && label != null) const SizedBox(width: 6),
                if (label != null)
                  Text(
                    label!,
                    maxLines: 1,
                    style: _dcStyle(12, fg, weight: FontWeight.w500),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Solid blue (or [color]) action button.
class DcPrimaryButton extends StatelessWidget {
  const DcPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = DcColors.selection,
    this.hoverColor = DcColors.selectionHover,
    this.height = 32,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color hoverColor;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: _DcHoverButton(
        onPressed: onPressed,
        builder: (hovered, enabled) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            height: height,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: !enabled
                  ? color.withValues(alpha: 0.45)
                  : hovered
                      ? hoverColor
                      : color,
              borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: _dcStyle(13, Colors.white, weight: FontWeight.w600),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 28 px gray bar pinned to the bottom of a window.
class DcStatusBar extends StatelessWidget {
  const DcStatusBar({
    super.key,
    required this.leading,
    this.trailing = const <Widget>[],
  });

  final List<Widget> leading;
  final List<Widget> trailing;

  /// Text style for plain status bar labels.
  static TextStyle get labelStyle => _dcStyle(11, DcColors.sidebarText);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DcMetrics.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: DcColors.footer,
        border: Border(top: BorderSide(color: DcColors.shellDivider)),
      ),
      child: DefaultTextStyle.merge(
        style: labelStyle,
        child: IconTheme.merge(
          data: const IconThemeData(color: DcColors.sidebarText, size: 13),
          child: Row(
            children: <Widget>[
              ...leading,
              const Spacer(),
              for (var i = 0; i < trailing.length; i++) ...<Widget>[
                if (i > 0) const _DcStatusBarSeparator(),
                trailing[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DcStatusBarSeparator extends StatelessWidget {
  const _DcStatusBarSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0x40263340),
    );
  }
}

/// Uppercase sidebar section caption (11 px bold, tracking 0.8).
class DcSidebarSectionLabel extends StatelessWidget {
  const DcSidebarSectionLabel({
    super.key,
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(15, 15, 12, 8),
  });

  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: _dcStyle(
                DcMetrics.sectionLabelSize,
                DcColors.sidebarMuted,
                weight: FontWeight.w700,
                letterSpacing: DcMetrics.sectionLabelTracking,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Count pill used on sidebar rows: white capsule, blue text when selected.
class DcCountPill extends StatelessWidget {
  const DcCountPill({super.key, required this.count, this.selected = false});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: selected ? Colors.white : const Color(0xCCFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: _dcStyle(
          10,
          selected ? DcColors.selection : DcColors.sidebarMuted,
          weight: FontWeight.w600,
        ).copyWith(fontFeatures: const <FontFeature>[
          FontFeature.tabularFigures(),
        ]),
      ),
    );
  }
}

/// Full-width sidebar row: blue fill when selected, no rounding.
class DcSidebarRow extends StatefulWidget {
  const DcSidebarRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.iconColor = DcColors.selection,
    this.count,
    this.selected = false,
    this.trailing,
    this.height = DcMetrics.sidebarRowHeight,
    this.indent = 15,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? leading;
  final Color iconColor;
  final int? count;
  final bool selected;
  final Widget? trailing;
  final double height;
  final double indent;

  @override
  State<DcSidebarRow> createState() => _DcSidebarRowState();
}

class _DcSidebarRowState extends State<DcSidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final fg = selected ? Colors.white : DcColors.sidebarText;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: widget.height),
          padding: EdgeInsets.only(left: widget.indent, right: 10),
          color: selected
              ? DcColors.selection
              : _hovered
                  ? DcColors.sidebarHover
                  : Colors.transparent,
          child: Row(
            children: <Widget>[
              if (widget.leading != null)
                widget.leading!
              else if (widget.icon != null)
                SizedBox(
                  width: 17,
                  child: Icon(
                    widget.icon,
                    size: 14,
                    color: selected ? Colors.white : widget.iconColor,
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _dcStyle(
                    12,
                    fg,
                    weight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
              if (widget.count != null) ...<Widget>[
                const SizedBox(width: 4),
                DcCountPill(count: widget.count!, selected: selected),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
