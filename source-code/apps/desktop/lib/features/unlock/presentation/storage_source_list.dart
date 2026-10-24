import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../presentation/theme/drive_clue_tokens.dart';

/// Brand accent colors used to tint provider logo tiles.
abstract final class StorageBrandColors {
  static const Color local = DcColors.selection;
  static const Color googleDrive = Color(0xFF1FA463);
  static const Color dropbox = Color(0xFF0061FE);
  static const Color oneDrive = Color(0xFF0078D4);
  static const Color webDav = DcColors.orange;
  static const Color sftp = DcColors.teal;
  static const Color s3 = Color(0xFFE88A00);
}

/// One provider row in a [StorageSourceList].
class StorageSourceEntry {
  const StorageSourceEntry({
    required this.id,
    required this.icon,
    required this.brandColor,
    required this.title,
    required this.detail,
    required this.ready,
    required this.selected,
    this.account,
    this.busy = false,
    this.actionLabel,
    this.onAction,
    this.onSelect,
    this.onDisconnect,
    this.disabledReason,
  });

  /// Stable key so rows keep their state when they move between groups.
  final String id;
  final Widget icon;
  final Color brandColor;
  final String title;

  /// Connected account (email, host, bucket...). Shown next to the title.
  final String? account;

  /// Folder / file path line, or a hint when nothing is chosen yet.
  final String detail;

  /// Whether the provider can be used right now (connected, or local).
  final bool ready;
  final bool selected;
  final bool busy;

  /// Inline action. Ready rows show it only while selected; rows that are not
  /// ready show it as a quiet "Connect" link.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Selecting a ready row. Rows that are not ready run [onAction] on tap.
  final VoidCallback? onSelect;

  /// When set, a ready row gets a "…" menu with a Disconnect item.
  final VoidCallback? onDisconnect;

  /// Explains why a provider cannot be connected in this build.
  final String? disabledReason;
}

/// A compact, grouped, single-select list of storage providers:
/// ready providers first, then the ones that still need connecting.
class StorageSourceList extends StatelessWidget {
  const StorageSourceList({
    super.key,
    required this.entries,
    this.readyLabel = 'Connected',
    this.availableLabel = 'Available to connect',
  });

  final List<StorageSourceEntry> entries;
  final String readyLabel;
  final String availableLabel;

  @override
  Widget build(BuildContext context) {
    final ready = entries.where((e) => e.ready).toList();
    final available = entries.where((e) => !e.ready).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (ready.isNotEmpty) ...<Widget>[
          _GroupLabel(label: readyLabel, count: ready.length),
          const SizedBox(height: 6),
          _Group(entries: ready),
        ],
        if (available.isNotEmpty) ...<Widget>[
          if (ready.isNotEmpty) const SizedBox(height: 16),
          _GroupLabel(label: availableLabel, count: available.length),
          const SizedBox(height: 6),
          _Group(entries: available),
        ],
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: _text(
              DcMetrics.sectionLabelSize,
              DcColors.sidebarMuted,
              weight: FontWeight.w700,
              letterSpacing: DcMetrics.sectionLabelTracking,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: DcColors.sidebarLine,
              borderRadius: BorderRadius.circular(DcMetrics.badgeRadius),
            ),
            child: Text(
              '$count',
              style: _text(10, DcColors.sidebarText, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.entries});

  final List<StorageSourceEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DcColors.lightSurface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        border: Border.all(color: DcColors.sidebarLine),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: DcColors.lightCardShadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < entries.length; i++) ...<Widget>[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 62,
                color: DcColors.sidebarLine,
              ),
            _SourceRow(key: ValueKey<String>(entries[i].id), entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class _SourceRow extends StatefulWidget {
  const _SourceRow({super.key, required this.entry});

  final StorageSourceEntry entry;

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  bool _hovered = false;

  StorageSourceEntry get _e => widget.entry;

  VoidCallback? get _onTap {
    if (_e.busy) return null;
    if (_e.ready) return _e.selected ? null : _e.onSelect;
    return _e.onAction;
  }

  @override
  Widget build(BuildContext context) {
    final onTap = _onTap;
    final bool muted = !_e.ready;
    final Color fill = _e.selected
        ? DcColors.lightSelectionFill
        : (_hovered && onTap != null
            ? DcColors.sidebarHover
            : Colors.transparent);

    return MouseRegion(
      cursor:
          onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 58),
          color: fill,
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 3,
                height: 58,
                color: _e.selected ? DcColors.selection : Colors.transparent,
              ),
              const SizedBox(width: 11),
              _LogoTile(
                icon: _e.icon,
                brandColor: _e.brandColor,
                muted: muted,
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildText(muted)),
              const SizedBox(width: 10),
              _buildTrailing(),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildText(bool muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  _e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    13,
                    muted ? DcColors.sidebarMuted : DcColors.sidebarText,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              if (_e.account != null) ...<Widget>[
                const SizedBox(width: 8),
                const _StatusDot(color: DcColors.tealOnLight),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _e.account!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(11, DcColors.sidebarMuted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: <Widget>[
              Icon(
                _e.ready ? TablerIcons.folder : TablerIcons.plug_connected_x,
                size: 12,
                color: DcColors.sidebarMuted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _e.disabledReason ?? _e.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    11,
                    _e.selected ? DcColors.sidebarText : DcColors.sidebarMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrailing() {
    if (_e.busy) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: DcColors.selection,
        ),
      );
    }

    if (!_e.ready) {
      final bool enabled = _e.onAction != null;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            TablerIcons.plus,
            size: 13,
            color: enabled ? DcColors.selection : DcColors.sidebarMuted,
          ),
          const SizedBox(width: 4),
          Text(
            _e.actionLabel ?? 'Connect',
            style: _text(
              11.5,
              enabled ? DcColors.selection : DcColors.sidebarMuted,
              weight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axis: Axis.horizontal,
              child: child,
            ),
          ),
          child: _e.selected && _e.actionLabel != null
              ? Padding(
                  key: const ValueKey<String>('action'),
                  padding: const EdgeInsets.only(right: 10),
                  child: _RowActionButton(
                    label: _e.actionLabel!,
                    onPressed: _e.onAction,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey<String>('none')),
        ),
        _SelectIndicator(selected: _e.selected),
        if (_e.onDisconnect != null) ...<Widget>[
          const SizedBox(width: 4),
          _RowMenu(onDisconnect: _e.onDisconnect!),
        ],
      ],
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({
    required this.icon,
    required this.brandColor,
    required this.muted,
  });

  final Widget icon;
  final Color brandColor;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brandColor.withValues(alpha: muted ? 0.06 : 0.13),
        borderRadius: BorderRadius.circular(DcMetrics.controlRadius + 2),
        border: Border.all(
          color: brandColor.withValues(alpha: muted ? 0.12 : 0.28),
        ),
      ),
      child: Opacity(opacity: muted ? 0.55 : 1, child: icon),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SelectIndicator extends StatelessWidget {
  const _SelectIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: Icon(
        selected ? TablerIcons.circle_check_filled : TablerIcons.circle,
        key: ValueKey<bool>(selected),
        size: 18,
        color: selected ? DcColors.selection : DcColors.lightLineStrong,
      ),
    );
  }
}

class _RowActionButton extends StatelessWidget {
  const _RowActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: DcColors.selection,
        foregroundColor: Colors.white,
        disabledBackgroundColor: DcColors.sidebarLine,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DcMetrics.controlRadius),
        ),
        textStyle: _text(11, Colors.white, weight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.onDisconnect});

  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: PopupMenuButton<String>(
        tooltip: 'More',
        padding: EdgeInsets.zero,
        iconSize: 16,
        color: DcColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
          side: const BorderSide(color: DcColors.sidebarLine),
        ),
        icon: const Icon(
          TablerIcons.dots,
          size: 16,
          color: DcColors.sidebarMuted,
        ),
        onSelected: (value) {
          if (value == 'disconnect') onDisconnect();
        },
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'disconnect',
            height: 34,
            child: Row(
              children: <Widget>[
                const Icon(
                  TablerIcons.plug_connected_x,
                  size: 14,
                  color: DcColors.redOnLight,
                ),
                const SizedBox(width: 8),
                Text(
                  'Disconnect',
                  style:
                      _text(12, DcColors.redOnLight, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _text(
  double size,
  Color color, {
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    fontFamily: 'Ubuntu Sans',
    letterSpacing: letterSpacing,
  );
}
