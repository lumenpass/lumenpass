import 'package:flutter/foundation.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:path/path.dart' as p;

import '../services/cloud_sync_service.dart';

bool _databasePathsMatch(String registeredPath, String openVaultPath) {
  if (registeredPath == openVaultPath) return true;
  return p.equals(p.normalize(registeredPath), p.normalize(openVaultPath));
}

Future<KdbxDatabase> saveAndSyncDatabase(
  KdbxRepository repository,
  List<DatabaseRecord> registry,
) async {
  final database = await repository.saveDatabase();

  DatabaseRecord? record;
  for (final r in registry) {
    if (_databasePathsMatch(r.databasePath, database.path)) {
      record = r;
      break;
    }
  }

  final storageType = record?.storageType ?? 'local';
  debugPrint(
    '[Save] ✓ local save storage=$storageType '
    'path=${p.basename(database.path)}',
  );

  if (record != null &&
      (storageType == 'googleDrive' ||
          storageType == 'dropbox' ||
          storageType == 'oneDrive' ||
          storageType == 'webdav' ||
          storageType == 'sftp' ||
          storageType == 's3')) {
    debugPrint('[Save] → scheduling cloud sync ($storageType)');
    CloudSyncService.instance.scheduleUpload(record).ignore();
  }

  return database;
}
