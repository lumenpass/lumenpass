import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/models/database_record.dart';
import '../../../core/services/appearance_preferences.dart';
import '../../../core/services/backup_service.dart';

import '../../../presentation/theme/app_theme.dart';
import '../../../presentation/theme/drive_clue_tokens.dart';
import '../../../presentation/widgets/drive_clue/dc_dialog_title_bar.dart';
import '../../unlock/application/database_registry.dart';
import 'cloud_service_provider.dart';

// ── Light palette (sidebar-toned, matches the Cloud Services page) ─────────
const Color _kSurface = DcColors.lightSurface;
const Color _kBorderSoft = DcColors.sidebarLine;
const Color _kBorderRow = DcColors.lightLineStrong;
const Color _kTitle = DcColors.sidebarText;
const Color _kLabel = DcColors.sidebarMuted;
const Color _kDanger = DcColors.redOnLight;

TextStyle _t(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: fontWeight,
    fontFamily: currentFontFamily,
    height: height,
  );
}

/// Page-heading style used by the inner pages: tight tracking, heavy weight.
TextStyle _heading(double size, Color color, {double? height}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    fontFamily: currentFontFamily,
    letterSpacing: -0.3,
    height: height,
  );
}

/// Shared light confirmation sheet: branded title bar, a warning-tile heading
/// with the explanatory copy, then a Cancel / confirm footer. Pops `true` only
/// when the confirm action is pressed; cancel, close and the backdrop pop
/// `false`.
Widget _buildConfirmDialog(
  BuildContext ctx, {
  required String barTitle,
  required String heading,
  required String message,
  required String confirmLabel,
}) {
  return Theme(
    data: AppTheme.driveClue(),
    child: Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DcDialogTitleBar(
              title: barTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kDanger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _kDanger.withValues(alpha: 0.24),
                      ),
                    ),
                    child: const Icon(
                      TablerIcons.alert_triangle,
                      size: 22,
                      color: _kDanger,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          heading,
                          style: _heading(17, _kTitle, height: 1.2),
                        ),
                        const SizedBox(height: 5),
                        Text(message, style: _t(12.5, _kLabel, height: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _kBorderSoft)),
              ),
              child: Row(
                children: <Widget>[
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kLabel,
                      side: const BorderSide(color: _kBorderRow),
                      backgroundColor: _kSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 38),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: _t(12, _kLabel, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kDanger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 38),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle:
                          _t(12, Colors.white, fontWeight: FontWeight.w600),
                    ),
                    child: Text(confirmLabel),
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

/// Shows the standardized "disconnect this service" confirmation dialog used by
/// both the Cloud Services screen and the Open Existing Database modal.
///
/// Returns `true` only when the user explicitly confirms. Cancelling or
/// dismissing the dialog returns `false` and the caller must take no action.
Future<bool> confirmCloudDisconnect(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _buildConfirmDialog(
      ctx,
      barTitle: 'Disconnect service',
      heading: 'Do you want to disconnect this service?',
      message:
          'The vaults connected through this provider will be removed from '
          'this app (local references only). The actual vault files remain '
          'stored on the cloud disk and will not be deleted.',
      confirmLabel: 'Disconnect',
    ),
  );
  return confirmed ?? false;
}

/// Executes the full disconnect flow for [provider]. Callers must have already
/// obtained confirmation via [confirmCloudDisconnect].
///
/// The flow performs, in order:
/// 1. Deletes the saved offline authentication token for the provider from
///    local storage and 2. fully disconnects the provider (terminates the
///    active session and clears connection state) — both handled by the
///    matching `BackupService.disconnect*` method.
/// 3. Removes every vault reference that was added through this provider from
///    the local registry (and therefore from the in-app vaults list).
///
/// This NEVER deletes, moves, or modifies any file on the cloud disk — only the
/// local bookmarks/references are removed. Vaults from other providers and
/// local vaults are left untouched.
///
/// Shows the standardized confirmation dialog for removing every local vault
/// reference tied to [providerLabel], without disconnecting the provider
/// session or deleting any remote files.
Future<bool> confirmUnlinkCloudDatabases(
  BuildContext context, {
  required String providerLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _buildConfirmDialog(
      ctx,
      barTitle: 'Unlink vaults',
      heading: 'Unlink all $providerLabel vaults?',
      message:
          'Every vault linked through $providerLabel will be removed from this '
          'app (local references only). The actual vault files remain on '
          '$providerLabel and will not be deleted.',
      confirmLabel: 'Unlink Databases',
    ),
  );
  return confirmed ?? false;
}

/// Removes every local vault reference scoped to [storageType].
///
/// Unlike [performCloudDisconnect], this does not sign out or clear the saved
/// provider credentials — it only drops the in-app registry entries /
/// bookmarks for that provider.
Future<List<DatabaseRecord>> unlinkCloudDatabasesByStorageType(
  WidgetRef ref,
  String storageType,
) {
  return ref
      .read(databaseRegistryProvider.notifier)
      .removeByStorageType(storageType);
}

/// Returns the vault records that were removed so the caller can reconcile any
/// local selection state.
Future<List<DatabaseRecord>> performCloudDisconnect(
  WidgetRef ref,
  CloudServiceProvider provider,
) async {
  // Stages 1 + 2: drop the saved token and tear down the provider session.
  switch (provider) {
    case CloudServiceProvider.googleDrive:
      await BackupService.instance.disconnectGoogle();
      break;
    case CloudServiceProvider.dropbox:
      await BackupService.instance.disconnectDropbox();
      break;
    case CloudServiceProvider.oneDrive:
      await BackupService.instance.disconnectOneDrive();
      break;
    case CloudServiceProvider.webdav:
      await BackupService.instance.disconnectWebDav();
      break;
    case CloudServiceProvider.sftp:
      await BackupService.instance.disconnectSftp();
      break;
    case CloudServiceProvider.s3:
      await BackupService.instance.disconnectS3();
      break;
  }

  // Stage 3: remove local vault references scoped to this provider only.
  return ref
      .read(databaseRegistryProvider.notifier)
      .removeByStorageType(provider.storageType);
}
