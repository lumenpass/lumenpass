import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/services/cloud_database_service.dart';
import '../../../core/services/cloud_sync_service.dart';

enum DatabaseConnectionHealthState { checking, healthy, error }

class DatabaseConnectionHealth {
  const DatabaseConnectionHealth.checking({
    this.providerLabel,
    this.checkedAt,
  })  : state = DatabaseConnectionHealthState.checking,
        code = null,
        title = null,
        details = null,
        recommendedActions = const <String>[];

  const DatabaseConnectionHealth.healthy({
    this.providerLabel,
    this.checkedAt,
  })  : state = DatabaseConnectionHealthState.healthy,
        code = null,
        title = null,
        details = null,
        recommendedActions = const <String>[];

  const DatabaseConnectionHealth.error({
    required this.code,
    required this.title,
    required this.details,
    required this.recommendedActions,
    this.providerLabel,
    this.checkedAt,
  }) : state = DatabaseConnectionHealthState.error;

  final DatabaseConnectionHealthState state;
  final String? code;
  final String? providerLabel;
  final String? title;
  final String? details;
  final List<String> recommendedActions;
  final DateTime? checkedAt;

  bool get isChecking => state == DatabaseConnectionHealthState.checking;
  bool get isHealthy => state == DatabaseConnectionHealthState.healthy;
  bool get hasError => state == DatabaseConnectionHealthState.error;
  bool get blocksUnlock => !isHealthy;
}

abstract class DatabaseConnectionHealthProbe {
  const DatabaseConnectionHealthProbe();

  Future<DatabaseConnectionHealth> check(DatabaseRecord record);
}

final databaseConnectionHealthProbeProvider =
    Provider<DatabaseConnectionHealthProbe>(
  (ref) => const LiveDatabaseConnectionHealthProbe(),
);

class LiveDatabaseConnectionHealthProbe
    implements DatabaseConnectionHealthProbe {
  const LiveDatabaseConnectionHealthProbe();

  static const Duration _kProbeTimeout = Duration(seconds: 12);

  @override
  Future<DatabaseConnectionHealth> check(DatabaseRecord record) async {
    if (!isCloudBackedDatabaseRecord(record)) {
      return DatabaseConnectionHealth.healthy(
        providerLabel: providerLabelForStorageType(record.storageType),
        checkedAt: DateTime.now(),
      );
    }

    final providerLabel = providerLabelForStorageType(record.storageType);
    final checkedAt = DateTime.now();

    // Step 1: Verify cloud credentials (12s timeout).
    final credentialResult = await CloudDatabaseService.instance
        .verifyCloudCredentialsForStorage(record.storageType)
        .timeout(
          _kProbeTimeout,
          onTimeout: () => CloudCredentialResult(
            CloudCredentialStatus.networkError,
            providerLabel: providerLabel,
            message:
                'Timed out while checking $providerLabel. Try again when the '
                'connection is stable.',
          ),
        );

    if (!credentialResult.isHealthy) {
      return _healthFromCredentialResult(
        record,
        credentialResult,
        checkedAt: checkedAt,
      );
    }

    // Step 2: Verify remote access (12s timeout).
    try {
      await _verifyRemoteAccess(record).timeout(_kProbeTimeout);
    } on TimeoutException {
      return DatabaseConnectionHealth.error(
        code: 'health_timeout',
        providerLabel: providerLabel,
        title: 'Timed out while checking this vault',
        details: 'LumenPass could not finish verifying the remote copy on '
            '$providerLabel. Sync may still be unavailable.',
        recommendedActions: <String>[
          'Make sure $providerLabel is reachable from this device.',
          'Run Check again once the connection is stable.',
          'Reconnect $providerLabel if the timeout keeps happening.',
        ],
        checkedAt: checkedAt,
      );
    } catch (error) {
      return _healthFromRemoteAccessError(
        record,
        error,
        checkedAt: checkedAt,
      );
    }

    // Step 3: Flush pending dirty syncs.
    if (await CloudSyncService.instance.isDirty(record.databasePath)) {
      try {
        await CloudSyncService.instance.flush(record).timeout(_kProbeTimeout);
      } catch (error) {
        final settled =
            CloudSyncService.instance.statusFor(record.databasePath);
        return _healthFromDirtySyncFailure(
          record,
          settled.error ?? error,
          checkedAt: checkedAt,
        );
      }

      if (await CloudSyncService.instance.isDirty(record.databasePath)) {
        final settled =
            CloudSyncService.instance.statusFor(record.databasePath);
        return _healthFromDirtySyncFailure(
          record,
          settled.error,
          checkedAt: checkedAt,
        );
      }
    }

    return DatabaseConnectionHealth.healthy(
      providerLabel: providerLabel,
      checkedAt: checkedAt,
    );
  }

  /// Lightweight check that the cloud file reference is still valid by
  /// fetching the remote file's modified time.
  Future<void> _verifyRemoteAccess(DatabaseRecord record) async {
    final fileId = record.cloudFileId;
    if (fileId == null || fileId.isEmpty) {
      throw StateError(
        'This vault is no longer linked to its remote file reference. '
        'Remove it from the list and open it again from '
        '${providerLabelForStorageType(record.storageType)}.',
      );
    }

    switch (record.storageType) {
      case 'googleDrive':
        await CloudDatabaseService.instance
            .getGoogleDriveFileModifiedTime(fileId);
        return;
      case 'dropbox':
        await CloudDatabaseService.instance.getDropboxFileModifiedTime(fileId);
        return;
      case 'oneDrive':
        await CloudDatabaseService.instance
            .getOneDriveFileModifiedTime(fileId);
        return;
      case 'webdav':
        await CloudDatabaseService.instance
            .getWebDavFileModifiedTime(fileId);
        return;
      case 'sftp':
        await CloudDatabaseService.instance.getSftpFileModifiedTime(fileId);
        return;
      case 's3':
        await CloudDatabaseService.instance.getS3FileModifiedTime(fileId);
        return;
      default:
        return;
    }
  }
}

bool isCloudBackedDatabaseRecord(DatabaseRecord record) {
  switch (record.storageType) {
    case 'googleDrive':
    case 'dropbox':
    case 'oneDrive':
    case 'webdav':
    case 'sftp':
    case 's3':
      return true;
    default:
      return false;
  }
}

String providerLabelForStorageType(String storageType) {
  switch (storageType) {
    case 'googleDrive':
      return 'Google Drive';
    case 'dropbox':
      return 'Dropbox';
    case 'oneDrive':
      return 'OneDrive';
    case 'webdav':
      return 'WebDAV';
    case 'sftp':
      return 'SFTP';
    case 's3':
      return 'Amazon S3';
    default:
      return 'Local Storage';
  }
}

DatabaseConnectionHealth _healthFromCredentialResult(
  DatabaseRecord record,
  CloudCredentialResult result, {
  required DateTime checkedAt,
}) {
  final providerLabel =
      result.providerLabel ?? providerLabelForStorageType(record.storageType);
  switch (result.status) {
    case CloudCredentialStatus.notSignedIn:
      return DatabaseConnectionHealth.error(
        code: 'credential_not_signed_in',
        providerLabel: providerLabel,
        title: '$providerLabel is not connected',
        details: result.message ??
            '$providerLabel is no longer connected on this device, so this '
                'vault cannot confirm sync status.',
        recommendedActions: <String>[
          'Reconnect $providerLabel on this device.',
          'Run Check again after reconnecting.',
          'If the issue remains, remove this vault from the list and open it again from $providerLabel.',
        ],
        checkedAt: checkedAt,
      );
    case CloudCredentialStatus.authExpired:
      return DatabaseConnectionHealth.error(
        code: 'credential_auth_expired',
        providerLabel: providerLabel,
        title: '$providerLabel needs to be reconnected',
        details: result.message ??
            'The saved $providerLabel credentials were rejected, so this '
                'vault cannot sync safely right now.',
        recommendedActions: <String>[
          'Reconnect $providerLabel.',
          'Run Check again after reconnecting.',
          'If sync still fails, remove this vault from the list and add it again from $providerLabel.',
        ],
        checkedAt: checkedAt,
      );
    case CloudCredentialStatus.networkError:
      return DatabaseConnectionHealth.error(
        code: 'credential_network_error',
        providerLabel: providerLabel,
        title: 'Could not reach $providerLabel',
        details: result.message ??
            'LumenPass could not reach $providerLabel, so this vault cannot '
                'confirm sync status right now.',
        recommendedActions: <String>[
          'Check network, VPN, or firewall access to $providerLabel.',
          'Run Check again after connectivity is restored.',
          'Reconnect $providerLabel if the provider stays reachable but this warning keeps returning.',
        ],
        checkedAt: checkedAt,
      );
    case CloudCredentialStatus.valid:
    case CloudCredentialStatus.notApplicable:
      return DatabaseConnectionHealth.healthy(
        providerLabel: providerLabel,
        checkedAt: checkedAt,
      );
  }
}

DatabaseConnectionHealth _healthFromRemoteAccessError(
  DatabaseRecord record,
  Object error, {
  required DateTime checkedAt,
}) {
  final providerLabel = providerLabelForStorageType(record.storageType);
  final normalizedError = normalizeDatabaseHealthError(error);
  final missingLink =
      normalizedError.toLowerCase().contains('cloud file reference') ||
          normalizedError.toLowerCase().contains('no longer linked');

  return DatabaseConnectionHealth.error(
    code: missingLink ? 'missing_cloud_link' : 'remote_file_unavailable',
    providerLabel: providerLabel,
    title: missingLink
        ? 'This vault has lost its remote link'
        : 'The remote vault copy could not be verified',
    details: missingLink
        ? normalizedError
        : 'LumenPass could reach $providerLabel, but it could not verify the '
            'saved remote file for this vault.\n\n$normalizedError',
    recommendedActions: <String>[
      'Reconnect $providerLabel if the account or server details changed.',
      'Run Check again after reconnecting.',
      'If this vault still cannot be verified, remove it from the list and open it again from $providerLabel.',
    ],
    checkedAt: checkedAt,
  );
}

DatabaseConnectionHealth _healthFromDirtySyncFailure(
  DatabaseRecord record,
  Object? error, {
  required DateTime checkedAt,
}) {
  final providerLabel = providerLabelForStorageType(record.storageType);
  final normalizedError = normalizeDatabaseHealthError(error);

  return DatabaseConnectionHealth.error(
    code: 'pending_sync_failure',
    providerLabel: providerLabel,
    title: 'Pending changes did not sync',
    details: normalizedError.isEmpty
        ? 'This vault still has local changes that could not be confirmed by '
            '$providerLabel.'
        : 'This vault still has local changes that could not be confirmed by '
            '$providerLabel.\n\n$normalizedError',
    recommendedActions: <String>[
      'Reconnect $providerLabel and run Check again.',
      'Keep a backup of the local vault before making more edits.',
      'If this warning does not clear, remove this vault from the list and open it again from $providerLabel.',
    ],
    checkedAt: checkedAt,
  );
}

String normalizeDatabaseHealthError(Object? error) {
  if (error == null) return '';
  var text = error.toString().trim();
  const prefixes = <String>[
    'Exception: ',
    'StateError: ',
    'Bad state: ',
  ];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
    }
  }
  return text;
}
