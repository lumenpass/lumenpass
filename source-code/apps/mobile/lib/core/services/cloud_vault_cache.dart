import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cloud_database_service.dart';

/// Stable local path for a cloud-backed vault (same formula as import in
/// [add_vault_sheet]).
Future<String> cloudDatabaseCachePath({
  required String storageType,
  required String cloudFileId,
  required String cloudFileName,
}) async {
  final appSupport = await getApplicationSupportDirectory();
  final folder = switch (storageType) {
    'googleDrive' => 'google_drive',
    'oneDrive' => 'onedrive',
    'webdav' => 'webdav',
    'sftp' => 'sftp',
    's3' => 's3',
    _ => 'dropbox',
  };
  final safeBase = p
      .basenameWithoutExtension(cloudFileName)
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final ext = p.extension(cloudFileName).toLowerCase().isEmpty
      ? '.kdbx'
      : p.extension(cloudFileName).toLowerCase();
  final hash = sha1
      .convert(utf8.encode('$storageType:$cloudFileId'))
      .toString()
      .substring(0, 12);
  return p.join(
    appSupport.path,
    'cloud_databases',
    folder,
    '${safeBase}_$hash$ext',
  );
}

/// Returns the path that should be passed to [KdbxRepository.openDatabase].
Future<String> resolvedLocalDatabasePath(DatabaseRecord record) async {
  if ((record.storageType == 'googleDrive' ||
          record.storageType == 'dropbox' ||
          record.storageType == 'oneDrive' ||
          record.storageType == 'webdav' ||
          record.storageType == 'sftp' ||
          record.storageType == 's3') &&
      record.cloudFileId != null &&
      record.cloudFileId!.isNotEmpty &&
      record.cloudFileName != null &&
      record.cloudFileName!.isNotEmpty) {
    return cloudDatabaseCachePath(
      storageType: record.storageType,
      cloudFileId: record.cloudFileId!,
      cloudFileName: record.cloudFileName!,
    );
  }

  // Local vaults: the stored absolute path embeds the iOS app-container UUID,
  // which is rotated on every clean install / rebuild. The file itself is not
  // deleted, only its absolute path becomes stale. If the stored path no longer
  // exists, fall back to the file with the same name inside the current
  // application documents directory (where local vaults are always created).
  final storedPath = record.databasePath;
  if (await File(storedPath).exists()) {
    return storedPath;
  }
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final candidate = p.join(docsDir.path, p.basename(storedPath));
    if (await File(candidate).exists()) {
      return candidate;
    }
  } catch (_) {
    // Fall through to the stored path; the caller surfaces a "not found" error.
  }
  return storedPath;
}

/// Returns the stable identifier used to key per-vault unlock data
/// (biometric / PIN) in [VaultUnlockService], and performs a one-time
/// migration of any legacy data that was keyed by the vault's absolute file
/// path.
///
/// Unlock data used to be keyed by the resolved local file path. On iOS that
/// path embeds the app container UUID, which rotates across App Store updates,
/// so the derived keys would no longer resolve and users lost their biometric
/// setup. Keying by the stable [DatabaseRecord.id] fixes this. The migration
/// copies still-reachable legacy data over on first run after the update.
Future<String> resolvedVaultUnlockId(
  DatabaseRecord record,
  VaultUnlockService unlockService,
) async {
  final legacyPath = await resolvedLocalDatabasePath(record);
  await unlockService.migrateVaultIdentity(
    oldVaultPath: legacyPath,
    newVaultId: record.id,
  );
  return record.id;
}

/// Downloads the vault from Google Drive / Dropbox when the cached file is
/// missing (e.g. after OS cleanup or reinstall).
Future<void> ensureCloudDatabaseCached(DatabaseRecord record) async {
  if (record.cloudFileId == null ||
      record.cloudFileId!.isEmpty ||
      record.cloudFileName == null ||
      record.cloudFileName!.isEmpty) {
    throw Exception(
      'This cloud vault needs to be added again so the app can sync it from '
      'Google Drive or Dropbox.',
    );
  }

  final path = await cloudDatabaseCachePath(
    storageType: record.storageType,
    cloudFileId: record.cloudFileId!,
    cloudFileName: record.cloudFileName!,
  );

  final file = File(path);
  if (await file.exists()) {
    return;
  }

  await Directory(p.dirname(path)).create(recursive: true);

  final Uint8List bytes;
  switch (record.storageType) {
    case 'googleDrive':
      bytes = await CloudDatabaseService.instance.downloadGoogleDriveFile(
        record.cloudFileId!,
      );
    case 'dropbox':
      bytes = await CloudDatabaseService.instance.downloadDropboxFile(
        record.cloudFileId!,
      );
    case 'oneDrive':
      bytes = await CloudDatabaseService.instance.downloadOneDriveFile(
        record.cloudFileId!,
      );
    case 'webdav':
      bytes = await CloudDatabaseService.instance.downloadWebDavFile(
        record.cloudFileId!,
      );
    case 'sftp':
      bytes = await CloudDatabaseService.instance.downloadSftpFile(
        record.cloudFileId!,
      );
    case 's3':
      bytes = await CloudDatabaseService.instance.downloadS3File(
        record.cloudFileId!,
      );
    default:
      throw Exception('Unsupported cloud storage type.');
  }

  await file.writeAsBytes(bytes, flush: true);
}
