import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../theme/app_theme.dart';
import '../../theme/drive_clue_tokens.dart';
import 'dc_dialog_title_bar.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Shared light confirmation / alert dialog
/// ─────────────────────────────────────────────────────────────────────────
///
/// The vault list screen used to open several one-off [AlertDialog]s that
/// still used the dark slate surfaces (`DcColors.panel` / `DcColors.text`).
/// On the now-light unlock screen those read as foreign dark panels, and a
/// couple of them put light text on a white background.
///
/// [DcConfirmDialog] is the single light surface those call sites share:
///
///   • branded dark title bar (same component the inner pages use)
///   • optional status icon + heading + explanatory copy
///   • optional extra body (lists, acknowledgements, tables)
///   • footer with a ghost Cancel and a primary / destructive action
///
/// Use [showDcConfirmDialog] for the common "confirm this action" shape, or
/// construct [DcConfirmDialog] directly when the body needs custom widgets.
class DcConfirmDialog extends StatelessWidget {
  const DcConfirmDialog({
    super.key,
    required this.barTitle,
    required this.heading,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.icon = TablerIcons.alert_triangle,
    this.isDestructive = false,
    this.body,
    this.confirmIcon,
    this.onConfirm,
    this.onCancel,
    this.width = 460,
    this.extraActions = const <Widget>[],
    this.confirmEnabled = true,
  });

  /// Text shown in the dark branded title bar.
  final String barTitle;

  /// Heading inside the light body.
  final String heading;

  /// Explanatory copy under the heading.
  final String message;

  final String confirmLabel;
  final String cancelLabel;

  /// Icon in the heading badge. Defaults to a warning triangle.
  final IconData icon;

  /// When true the icon badge and primary button use the danger colour.
  final bool isDestructive;

  /// Optional widget rendered between the heading block and the footer.
  final Widget? body;

  final IconData? confirmIcon;

  /// Defaults to popping `true`.
  final VoidCallback? onConfirm;

  /// Defaults to popping `false`.
  final VoidCallback? onCancel;

  final double width;

  /// Additional footer buttons rendered before Cancel (e.g. "Check again").
  final List<Widget> extraActions;

  /// When false the primary button is disabled (e.g. acknowledgements not yet
  /// checked). Cancel and the close button stay available.
  final bool confirmEnabled;

  @override
  Widget build(BuildContext context) {
    final accent = isDestructive ? DcColors.redOnLight : DcColors.selection;

    return Theme(
      // The dialog is hosted above the app's own theme scope in tests and in
      // some routes, so restate it to keep Material defaults light.
      data: AppTheme.driveClue(),
      child: Dialog(
        backgroundColor: DcColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        ),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DcDialogTitleBar(
                title: barTitle,
                onClose: onCancel ?? () => Navigator.of(context).pop(false),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.24),
                              ),
                            ),
                            child: Icon(icon, size: 21, color: accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  heading,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    height: 1.25,
                                    color: DcColors.sidebarText,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  message,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.5,
                                    color: DcColors.sidebarMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (body != null) ...<Widget>[
                        const SizedBox(height: 16),
                        body!,
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: DcColors.sidebarLine),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (extraActions.isNotEmpty) ...<Widget>[
                      // Secondary actions sit on their own line so a long
                      // primary label can never squeeze them into a sliver.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: extraActions,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        OutlinedButton(
                          onPressed: onCancel ??
                              () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DcColors.sidebarMuted,
                            side: const BorderSide(
                              color: DcColors.lightLineStrong,
                            ),
                            backgroundColor: DcColors.lightSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            minimumSize: const Size(0, 38),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DcColors.sidebarMuted,
                            ),
                          ),
                          child: Text(cancelLabel),
                        ),
                        _ConfirmButton(
                          label: confirmLabel,
                          icon: confirmIcon,
                          background: accent,
                          onPressed: confirmEnabled
                              ? (onConfirm ??
                                  () => Navigator.of(context).pop(true))
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a [DcConfirmDialog] and returns `true` only when the primary action
/// was pressed. Cancel, the close button, and the backdrop all return `false`.
Future<bool> showDcConfirmDialog(
  BuildContext context, {
  required String barTitle,
  required String heading,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData icon = TablerIcons.alert_triangle,
  bool isDestructive = false,
  Widget? body,
  IconData? confirmIcon,
  double width = 460,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => DcConfirmDialog(
      barTitle: barTitle,
      heading: heading,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon,
      isDestructive: isDestructive,
      body: body,
      confirmIcon: confirmIcon,
      width: width,
    ),
  );
  return result ?? false;
}

/// Muted card used inside [DcConfirmDialog.body] for warning notes and
/// supporting details.
class DcDialogNote extends StatelessWidget {
  const DcDialogNote({
    super.key,
    required this.child,
    this.tone = DcDialogNoteTone.neutral,
  });

  final Widget child;
  final DcDialogNoteTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color border) = switch (tone) {
      DcDialogNoteTone.neutral => (
          DcColors.lightInset,
          DcColors.sidebarLine,
        ),
      DcDialogNoteTone.warning => (
          DcColors.amberSoft,
          DcColors.amberLine,
        ),
      DcDialogNoteTone.danger => (
          DcColors.redSoft,
          DcColors.redLine,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}

enum DcDialogNoteTone { neutral, warning, danger }

/// Primary footer button. Avoids `ElevatedButton.icon` so the button has no
/// reserved leading gap when no icon is supplied.
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.label,
    required this.background,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final Color background;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
