import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/models/database_record.dart';
import '../../../core/repository/kdbx_repository_provider.dart';
import '../../unlock/application/database_registry.dart';
import '../application/import_state.dart';
import '../application/import_executor.dart';

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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFCEC7BB)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x295B4638),
              blurRadius: 32,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    TablerIcons.file_import,
                    size: 22,
                    color: Color(0xFF22C55E),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Confirm Import',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E2021),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$readyCount items ready for import',
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF74766F),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3EDE4),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD8D2C7)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(TablerIcons.database,
                                size: 12, color: Color(0xFF74766F)),
                            const SizedBox(width: 6),
                            Text(
                              'Target Vault: $vaultName',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF4F524E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Import Mode',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF686B67),
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
                  color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      TablerIcons.alert_triangle,
                      size: 18,
                      color: Color(0xFFEF4444),
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
                          color: Color(0xFFDC2626),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Container(height: 1, color: const Color(0xFFD8D2C7)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _FooterButton(
                  label: 'Back',
                  backgroundColor: const Color(0xFFFFFCF6),
                  textColor: const Color(0xFF4F524E),
                  borderColor: const Color(0xFFCEC7BB),
                  onTap: onCancel,
                ),
                const SizedBox(width: 10),
                _FooterButton(
                  label: 'Start Import',
                  backgroundColor: mode == ImportMode.replace
                      ? const Color(0xFFEF4444)
                      : const Color(0xFFFF5B22),
                  textColor: Colors.white,
                  onTap: onConfirm,
                ),
              ],
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
    final accentColor =
        isWarning ? const Color(0xFFEF4444) : const Color(0xFF22C55E);
    final bgColor = accentColor.withValues(alpha: 0.08);
    final borderColor = accentColor.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
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
                    color: Color(0xFF1E2021),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF74766F),
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
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: _hovered && isEnabled
                  ? widget.backgroundColor.withValues(alpha: 0.8)
                  : widget.backgroundColor,
              borderRadius: BorderRadius.circular(12),
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
