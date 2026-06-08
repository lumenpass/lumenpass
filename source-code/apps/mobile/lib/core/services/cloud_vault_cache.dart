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
  return record.databasePath;
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
