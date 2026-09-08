import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_storage_service.dart';

const _cleanupMarker = 'migration.removedAppAccountData.v1.complete';

const _legacyAccountKeys = <String>[
  'lumenpass.auth.accessToken',
  'lumenpass.auth.refreshToken',
  'lumenpass.auth.expiresAt',
  'lumenpass.auth.provider',
  'lumenpass.auth.profile',
];

/// Removes credentials left by the retired LumenPass account system.
///
/// Only the exact legacy account keys are touched. Vault unlock secrets and
/// cloud-provider credentials remain intact. Failed deletions are retried on a
/// later launch because the completion marker is written only after success.
Future<void> cleanupRemovedDesktopAccountData(
  LocalStorageService localStorage, {
  FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
}) async {
  try {
    if (await localStorage.read(key: _cleanupMarker) == 'true') return;
  } catch (error) {
    debugPrint('[Account cleanup] Could not read migration marker: $error');
  }

  var allDeletesSucceeded = true;
  for (final key in _legacyAccountKeys) {
    try {
      await secureStorage.delete(key: key);
    } catch (error) {
      allDeletesSucceeded = false;
      debugPrint('[Account cleanup] Could not delete "$key": $error');
    }
  }

  if (!allDeletesSucceeded) return;

  try {
    await localStorage.write(key: _cleanupMarker, value: 'true');
  } catch (error) {
    debugPrint('[Account cleanup] Could not write migration marker: $error');
  }
}
