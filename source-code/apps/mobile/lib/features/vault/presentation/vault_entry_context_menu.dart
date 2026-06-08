import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/repository/database_save_sync.dart';
import '../../../core/repository/providers.dart';
import '../../../core/ui/app_snack_bar.dart';
import '../../unlock/application/database_registry.dart';
import '../application/vault_items_list_providers.dart';
import 'vault_create_item.dart';

void showVaultEntryContextMenuDialog(
  BuildContext context, {
  required KdbxEntry entry,
  ValueChanged<String>? onItemSaved,
  VoidCallback? onDeleteSuccess,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      elevation: 0,
      child: VaultEntryContextMenu(
        entry: entry,
        onEdit: () =>
            showEditItemModal(context, entry: entry, onItemSaved: onItemSaved),
        onDeleteSuccess: onDeleteSuccess,
      ),
    ),
  );
}

// ── Theme constants ───────────────────────────────────────────────────────────

const _kBorder = Color(0xFFE3EAF0);
const _kInk = Color(0xFF0A3B48);
const _kMuted = Color(0xFF6B7A83);
const _kDestructive = Color(0xFFB42318);

/// Context menu shown when long-pressing an entry in the vault list.
class VaultEntryContextMenu extends ConsumerWidget {
  const VaultEntryContextMenu({
    super.key,
    required this.entry,
    required this.onEdit,
    this.onDeleteSuccess,
  });

  final KdbxEntry entry;
  final VoidCallback onEdit;
  final VoidCallback? onDeleteSuccess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUrl = (entry.url ?? '').trim().isNotEmpty;
    final hasTotp = entryHasTotp(entry);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: _kInk,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Actions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasUrl)
                  _MenuTile(
                    icon: Icons.open_in_new_rounded,
                    label: 'Open',
                    description: 'Launch the saved URL in your browser',
                    onTap: () {
                      Navigator.of(context).pop();
                      _openUrl(context, entry.url ?? '');
                    },
                  ),
                _MenuTile(
                  icon: Icons.edit_rounded,
                  label: 'Edit',
                  description: 'Update name, credentials, or details',
                  onTap: () {
                    Navigator.of(context).pop();
                    onEdit();
                  },
                ),
                _MenuTile(
                  icon: Icons.copy_rounded,
                  label: 'Duplicate',
                  description: 'Create an editable copy of this entry',
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _duplicateEntry(context, ref, entry);
                  },
                ),
                if (hasTotp)
                  _MenuTile(
                    icon: Icons.timelapse_rounded,
                    label: 'Copy TOTP',
                    description: 'Copy the current one-time code to clipboard',
                    onTap: () {
                      Navigator.of(context).pop();
                      _copyTotp(context, entry);
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Container(height: 1, color: _kBorder),
                ),
                _MenuTile(
                  icon: Icons.delete_rounded,
                  label: 'Delete',
                  description: 'Permanently remove this entry',
                  isDestructive: true,
                  onTap: () async {
                    // Do NOT pop before confirming — popping makes context
                    // stale so showDialog inside _confirmDelete would silently
                    // fail. We pop from inside _confirmDelete after the user
                    // confirms, while the context is still valid.
                    await _confirmDelete(context, ref, entry);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    var target = url.trim();
    if (!target.startsWith('http://') && !target.startsWith('https://')) {
      target = 'https://$target';
    }
    final uri = Uri.tryParse(target);
    if (uri == null) {
      _showToast(context, 'Invalid URL');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _duplicateEntry(
    BuildContext context,
    WidgetRef ref,
    KdbxEntry entry,
  ) async {
    try {
      final repo = ref.read(kdbxRepositoryProvider);
      final db = ref.read(activeDatabaseProvider);
      if (db == null) {
        _showToast(context, 'No database open');
        return;
      }

      final group =
          _findGroupByUuid(db.rootGroup, entry.groupUuid) ?? db.rootGroup;

      final modifiedFields = entry.fields.map((f) {
        if (f.key.toLowerCase() == 'title') {
          return EntryField(
            key: f.key,
            value: '${entry.title} Copy',
            isProtected: f.isProtected,
            isStandard: f.isStandard,
          );
        }
        return f;
      }).toList();

      await repo.createEntry(
        groupUuid: group.uuid,
        fields: modifiedFields,
        notes: entry.notes,
        tags: entry.tags,
        attachments: const [],
      );

      final registry = ref.read(databaseRegistryProvider);
      await saveAndSyncDatabase(repo, registry);
      await refreshVaultSnapshot(ref);

      if (!context.mounted) return;
      _showToast(context, 'Entry duplicated');
    } catch (e) {
      if (!context.mounted) return;
      _showToast(context, 'Failed to duplicate: ${e.toString()}');
    }
  }

  void _copyTotp(BuildContext context, KdbxEntry entry) {
    final totp = TOTPService();
    final code = totp.generateCode(entry.otpAuthUrl, timestamp: DateTime.now());
    if (code == null || code.trim().isEmpty) {
      _showToast(context, 'No TOTP available');
      return;
    }
    Clipboard.setData(ClipboardData(text: code));
    _showToast(context, 'TOTP copied');
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    KdbxEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB42318),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (context.mounted) Navigator.of(context).pop();
      ref.read(vaultItemsIsDeletingProvider.notifier).state = true;
      try {
        final repo = ref.read(kdbxRepositoryProvider);
        await repo.deleteEntry(entry.uuid);
        final registry = ref.read(databaseRegistryProvider);
        await saveAndSyncDatabase(repo, registry);
        await refreshVaultSnapshot(ref);
        onDeleteSuccess?.call();
      } catch (e) {
        debugPrint('Delete failed: $e');
      } finally {
        ref.read(vaultItemsIsDeletingProvider.notifier).state = false;
      }
    }
  }

  void _showToast(BuildContext context, String message) {
    AppSnackBar.info(context, message);
  }

  KdbxGroup? _findGroupByUuid(KdbxGroup group, String uuid) {
    if (group.uuid == uuid) {
      return group;
    }
    for (final child in group.groups) {
      final match = _findGroupByUuid(child, uuid);
      if (match != null) {
        return match;
      }
    }
    return null;
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? _kDestructive : _kInk;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: _kMuted,
                      height: 1.3,
                    ),
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
