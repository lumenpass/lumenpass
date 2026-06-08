import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/services/cloud_database_service.dart';
import '../../unlock/application/database_registry.dart';
import 'cloud_service_provider.dart';

const Color _kInk = Color(0xFF0A3B48);
const Color _kMuted = Color(0xFF6B858D);
const Color _kDanger = Color(0xFFC0392B);

/// Shows the standardized "disconnect this service" confirmation dialog used by
/// the mobile Cloud Services screen.
///
/// Returns `true` only when the user explicitly confirms.
Future<bool> confirmCloudDisconnect(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Disconnect this service?',
        style: TextStyle(
          color: _kInk,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: const Text(
        'The vaults connected through this provider will be removed from this '
        'app (local references only). The actual vault files remain stored on '
        'the cloud and will not be deleted.',
        style: TextStyle(color: _kMuted, fontSize: 13.5, height: 1.45),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel', style: TextStyle(color: _kMuted)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _kDanger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Executes the full disconnect flow for [provider]. Callers must have already
/// obtained confirmation via [confirmCloudDisconnect].
///
/// Drops the saved token, tears down the provider session, and removes every
/// vault reference registered through this provider from the local registry.
/// NEVER deletes or modifies any cloud file — only local references.
///
/// Returns the vault records that were removed.
Future<List<DatabaseRecord>> performCloudDisconnect(
  WidgetRef ref,
  CloudServiceProvider provider,
) async {
  switch (provider) {
    case CloudServiceProvider.googleDrive:
      await CloudDatabaseService.instance.disconnectGoogle();
      break;
    case CloudServiceProvider.dropbox:
      await CloudDatabaseService.instance.disconnectDropbox();
      break;
    case CloudServiceProvider.oneDrive:
      await CloudDatabaseService.instance.disconnectOneDrive();
      break;
    case CloudServiceProvider.webdav:
      await CloudDatabaseService.instance.disconnectWebDav();
      break;
    case CloudServiceProvider.sftp:
      await CloudDatabaseService.instance.disconnectSftp();
      break;
    case CloudServiceProvider.s3:
      await CloudDatabaseService.instance.disconnectS3();
      break;
  }

  return ref
      .read(databaseRegistryProvider.notifier)
      .removeByStorageType(provider.storageType);
}
