import 'package:flutter/foundation.dart';

import 'local_storage_service.dart';
import 'secure_storage_service.dart';

const _cleanupMarker = 'migration.removedAppAccountData.v1.complete';

const _legacySecureAccountKeys = <String>['lp_session', 'lp_device_id'];

const _legacyLocalAccountKeys = <String>[
  'account.email',
  'account.authProvider',
  'account.plan',
  'account.expiresAt',
];

/// Removes credentials and profile data left by the retired app-account flow.
///
/// Only the exact legacy account keys are touched. Vault unlock secrets and
/// cloud-provider credentials remain intact. Failed deletions are retried on a
/// later launch because the completion marker is written only after success.
Future<void> cleanupRemovedMobileAccountData({
  required SecureStorageService secureStorage,
  required LocalStorageService localStorage,
}) async {
  try {
    if (await localStorage.read(_cleanupMarker) == 'true') return;
  } catch (error) {
    debugPrint('[Account cleanup] Could not read migration marker: $error');
  }

  var allDeletesSucceeded = true;
  for (final key in _legacySecureAccountKeys) {
    try {
      await secureStorage.delete(key);
    } catch (error) {
      allDeletesSucceeded = false;
      debugPrint(
        '[Account cleanup] Could not delete secure key "$key": $error',
      );
    }
  }

  for (final key in _legacyLocalAccountKeys) {
    try {
      await localStorage.delete(key);
    } catch (error) {
      allDeletesSucceeded = false;
      debugPrint('[Account cleanup] Could not delete local key "$key": $error');
    }
  }

  if (!allDeletesSucceeded) return;

  try {
    await localStorage.write(_cleanupMarker, 'true');
  } catch (error) {
    debugPrint('[Account cleanup] Could not write migration marker: $error');
  }
}
