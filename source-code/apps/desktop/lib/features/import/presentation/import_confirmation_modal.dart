import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/models/database_record.dart';
import '../../../core/repository/kdbx_repository_provider.dart';
import '../../unlock/application/database_registry.dart';
import '../application/import_state.dart';
import '../application/import_executor.dart';
import 'import_light_colors.dart';
import '../../../presentation/widgets/drive_clue/dc_dialog_title_bar.dart';

class ImportConfirmationModal extends ConsumerWidget {
  const ImportConfirmationModal({
    super.key,
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(importStateProvider);
    final mode = importState.importMode;
    final readyCount = importState.readyCount;
    final activeDatabase = ref.watch(activeDatabaseProvider);
    final repository = ref.watch(kdbxRepositoryProvider);
    final registry = ref.watch(databaseRegistryProvider);

    // The import always targets the currently open vault. Resolve its name the
    // same way the sidebar does: live KDBX name → cached snapshot name →
    // registry nickname → generic fallback.
    final activePath = activeDatabase?.path ?? repository.currentDatabase?.path;
    DatabaseRecord? record;
    if (activePath != null) {
      for (final r in registry) {
        if (r.databasePath == activePath) {
          record = r;
          break;
        }
      }
    }
    final String liveName = repository.currentDatabase?.name.trim() ?? '';
    final String snapshotName = activeDatabase?.name.trim() ?? '';
    final String recordNickname = record?.nickname.trim() ?? '';
    final String vaultName = liveName.isNotEmpty
        ? liveName
        : snapshotName.isNotEmpty
            ? snapshotName
            : recordNickname.isNotEmpty
                ? recordNickname
                : 'Vault';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 440,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ImportColors.panel,
          borderRadius: BorderRadius.circular(7),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: ImportColors.shadow,
              blurRadius: 32,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const DcDialogTitleBar(title: 'Confirm Import'),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('$readyCount items ready for import',
                      style: const TextStyle(
                          fontSize: 12, color: ImportColors.muted)),
                  const SizedBox(height: 8),
                  Text('Target Vault: $vaultName',
                      style: const TextStyle(
                          fontSize: 12, color: ImportColors.text)),
                  const SizedBox(height: 14),
                  const Text(
                    'Import Mode',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ImportColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (mode == ImportMode.append)
                    const _ModeOption(
                      icon: TablerIcons.plus,
                      title: 'Append',
                      description:
                          'Add imported items to your existing vault. No existing data will be modified.',
                    )
                  else
                    const _ModeOption(
                      icon: TablerIcons.replace,
                      title: 'Replace',
                      description:
                          'Replace all existing vault data with the imported items.',
                      isWarning: true,
                    ),
                  if (mode == ImportMode.replace) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ImportColors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: ImportColors.red.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(
                            TablerIcons.alert_triangle,
                            size: 18,
                            color: ImportColors.red,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Warning: This will permanently delete ALL existing '
                              'credentials in your vault and replace them with the '
                              'imported items. This action cannot be undone.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: ImportColors.red,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(height: 1, color: ImportColors.line),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      _FooterButton(
                        label: 'Back',
                        backgroundColor: ImportColors.rowAlternate,
                        textColor: ImportColors.muted,
                        borderColor: ImportColors.lineStrong,
                        onTap: onCancel,
                      ),
                      const SizedBox(width: 10),
                      _FooterButton(
                        label: 'Start Import',
                        backgroundColor: mode == ImportMode.replace
                            ? ImportColors.red
                            : ImportColors.selection,
                        textColor: Colors.white,
                        onTap: onConfirm,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.icon,
    required this.title,
    required this.description,
    this.isWarning = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final accentColor = isWarning ? ImportColors.red : ImportColors.green;
    final bgColor = accentColor.withValues(alpha: 0.08);
    final borderColor = accentColor.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ImportColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ImportColors.muted,
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

class _FooterButton extends StatefulWidget {
  const _FooterButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  State<_FooterButton> createState() => _FooterButtonState();
}

class _FooterButtonState extends State<_FooterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: _hovered && isEnabled
                  ? widget.backgroundColor.withValues(alpha: 0.8)
                  : widget.backgroundColor,
              borderRadius: BorderRadius.circular(6),
              border: widget.borderColor != null
                  ? Border.all(color: widget.borderColor!)
                  : null,
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: widget.textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
