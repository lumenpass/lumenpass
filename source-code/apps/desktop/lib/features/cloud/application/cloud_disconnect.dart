import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/database_record.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/services/s3_service.dart';
import '../../../presentation/theme/app_theme.dart';
import '../../unlock/application/database_registry.dart';
import 'cloud_service_provider.dart';

const Color _kTitle = Color(0xFF22314A);
const Color _kLabel = Color(0xFF73839D);
const Color _kWarnText = Color(0xFFC0392B);

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
    fontFamily: 'Inter',
    height: height,
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
    builder: (ctx) => Theme(
      data: AppTheme.light(),
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Do you want to disconnect this service?',
          style: _t(16, _kTitle, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'The vaults connected through this provider will be removed from '
          'this app (local references only). The actual vault files remain '
          'stored on the cloud disk and will not be deleted.',
          style: _t(13, _kLabel, height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: _t(13, _kLabel)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kWarnText,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
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
