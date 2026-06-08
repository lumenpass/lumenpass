import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backup_service.dart';
import '../../../core/services/s3_service.dart';

/// Canonical list of cloud storage providers LumenPass can connect to.
///
/// This is the single source of truth used by the centralized Cloud Services
/// manager. Each entry maps 1:1 to the stringly-typed `storageType` tokens
/// already persisted on `DatabaseRecord` (`'googleDrive' | 'dropbox' |
/// 'oneDrive' | 'webdav' | 'sftp'`) and understood by
/// `BackupService.verifyCloudCredentialsForStorage`, so the enum stays
/// compatible with the rest of the app without a risky refactor.
enum CloudServiceProvider { googleDrive, dropbox, oneDrive, webdav, sftp, s3 }

extension CloudServiceProviderX on CloudServiceProvider {
  /// The `DatabaseRecord.storageType` token / credential-check key.
  String get storageType {
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return 'googleDrive';
      case CloudServiceProvider.dropbox:
        return 'dropbox';
      case CloudServiceProvider.oneDrive:
        return 'oneDrive';
      case CloudServiceProvider.webdav:
        return 'webdav';
      case CloudServiceProvider.sftp:
        return 'sftp';
      case CloudServiceProvider.s3:
        return 's3';
    }
  }

  /// Human-readable provider name.
  String get label {
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return 'Google Drive';
      case CloudServiceProvider.dropbox:
        return 'Dropbox';
      case CloudServiceProvider.oneDrive:
        return 'OneDrive';
      case CloudServiceProvider.webdav:
        return 'WebDAV';
      case CloudServiceProvider.sftp:
        return 'SFTP';
      case CloudServiceProvider.s3:
        return 'Amazon S3';
    }
  }

  /// Short description shown under the provider name.
  String get description {
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return 'Sync vaults with your Google Drive account';
      case CloudServiceProvider.dropbox:
        return 'Sync vaults with your Dropbox account';
      case CloudServiceProvider.oneDrive:
        return 'Sync vaults with your Microsoft OneDrive account';
      case CloudServiceProvider.webdav:
        return 'Sync vaults with any WebDAV-compatible server';
      case CloudServiceProvider.sftp:
        return 'Sync vaults with an SSH/SFTP server';
      case CloudServiceProvider.s3:
        return 'Sync vaults with Amazon S3 storage';
    }
  }

  /// Bundled brand icon (falls back to a generic icon when absent).
  String get assetPath {
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return 'assets/images/google-drive.png';
      case CloudServiceProvider.dropbox:
        return 'assets/images/dropbox.png';
      case CloudServiceProvider.oneDrive:
        return 'assets/images/onedrive.png';
      case CloudServiceProvider.webdav:
        return 'assets/images/webdav.png';
      case CloudServiceProvider.sftp:
        return 'assets/images/sftp.png';
      case CloudServiceProvider.s3:
        return 'assets/images/aws-s3-icon.png';
    }
  }

  /// Whether the provider is restricted to Premium accounts. Mirrors
  /// [kFreeStorageProviderTokens] in subscription_gate_service.dart
  /// (Google Drive + Dropbox are free; OneDrive + WebDAV + SFTP are premium).
  bool get isPremiumOnly {
    switch (this) {
      case CloudServiceProvider.googleDrive:
      case CloudServiceProvider.dropbox:
        return false;
      case CloudServiceProvider.oneDrive:
      case CloudServiceProvider.webdav:
      case CloudServiceProvider.sftp:
      case CloudServiceProvider.s3:
        return true;
    }
  }

  /// Whether this provider is usable in the current build. Google Drive and
  /// WebDAV/SFTP need no build-time key; Dropbox and OneDrive require an OAuth
  /// client id/key passed via --dart-define.
  bool get isConfigured {
    switch (this) {
      case CloudServiceProvider.googleDrive:
      case CloudServiceProvider.webdav:
      case CloudServiceProvider.sftp:
      case CloudServiceProvider.s3:
        return true;
      case CloudServiceProvider.dropbox:
        return BackupService.isDropboxConfigured;
      case CloudServiceProvider.oneDrive:
        return BackupService.isOneDriveConfigured;
    }
  }

  /// Whether credentials are currently present on this device. This reflects
  /// local connection state only — use
  /// `BackupService.verifyCloudCredentialsForStorage` for live validity.
  bool get isConnected {
    final backup = BackupService.instance;
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return backup.isGoogleConnected;
      case CloudServiceProvider.dropbox:
        return backup.currentDropboxToken != null;
      case CloudServiceProvider.oneDrive:
        return backup.isOneDriveConnected;
      case CloudServiceProvider.webdav:
        return backup.isWebDavConnected;
      case CloudServiceProvider.sftp:
        return backup.isSftpConnected;
      case CloudServiceProvider.s3:
        return S3Service.instance.isConfigured;
    }
  }

  /// The connected account label (email / account name), if any. Reads the
  /// reactive backup providers so the UI rebuilds when an account changes.
  String? accountLabel(WidgetRef ref) {
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return ref.watch(backupGoogleAccountProvider) ??
            BackupService.instance.currentGoogleEmail;
      case CloudServiceProvider.dropbox:
        return ref.watch(backupDropboxAccountProvider);
      case CloudServiceProvider.oneDrive:
        return ref.watch(backupOneDriveAccountProvider) ??
            BackupService.instance.currentOneDriveEmail;
      case CloudServiceProvider.webdav:
        return ref.watch(backupWebDavAccountProvider) ??
            BackupService.instance.currentWebDavAccount;
      case CloudServiceProvider.sftp:
        return ref.watch(backupSftpAccountProvider) ??
            BackupService.instance.currentSftpAccount;
      case CloudServiceProvider.s3:
        return 's3://${S3Service.instance.currentBucketId ?? ""}';
    }
  }
}
