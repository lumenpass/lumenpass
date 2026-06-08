import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/cloud_database_service.dart';

/// Canonical list of cloud storage providers LumenPass can connect to on
/// mobile. Single source of truth used by the centralized Cloud Services
/// screen. Each entry maps 1:1 to the stringly-typed `storageType` tokens
/// persisted on `DatabaseRecord` (`'googleDrive' | 'dropbox' | 'oneDrive' |
/// 'webdav'`) and understood by
/// `CloudDatabaseService.verifyCloudCredentialsForStorage`.
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
        return 'Sync vaults via secure SFTP/SSH connection';
      case CloudServiceProvider.s3:
        return 'Sync vaults with Amazon S3 cloud storage';
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

  /// Whether this provider is usable in the current build. Google Drive needs
  /// platform config; WebDAV is always usable; Dropbox and OneDrive require an
  /// OAuth client id/key passed via --dart-define.
  bool get isConfigured {
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return CloudDatabaseService.isGoogleDriveConfigured;
      case CloudServiceProvider.webdav:
        return CloudDatabaseService.isWebDavConfigured;
      case CloudServiceProvider.dropbox:
        return CloudDatabaseService.isDropboxConfigured;
      case CloudServiceProvider.oneDrive:
        return CloudDatabaseService.isOneDriveConfigured;
      case CloudServiceProvider.sftp:
        return true; // SFTP is always usable (no app-level config required)
      case CloudServiceProvider.s3:
        return true; // S3 is always usable (no app-level config required)
    }
  }

  /// Whether credentials are currently present on this device. Reads the
  /// reactive cloud account providers (falling back to the service singleton)
  /// so the value is overridable in tests and rebuilds on connect/disconnect.
  /// Use `CloudDatabaseService.verifyCloudCredentialsForStorage` for live
  /// validity.
  bool isConnectedFor(WidgetRef ref) {
    final cloud = CloudDatabaseService.instance;
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return ref.watch(cloudGoogleAccountProvider) != null ||
            cloud.currentGoogleAccount != null;
      case CloudServiceProvider.dropbox:
        return ref.watch(cloudDropboxAccountProvider) != null ||
            cloud.currentDropboxToken != null;
      case CloudServiceProvider.oneDrive:
        return ref.watch(cloudOneDriveAccountProvider) != null ||
            cloud.isOneDriveConnected;
      case CloudServiceProvider.webdav:
        return ref.watch(cloudWebDavAccountProvider) != null ||
            cloud.isWebDavConnected;
      case CloudServiceProvider.sftp:
        return ref.watch(cloudSftpAccountProvider) != null ||
            cloud.isSftpConnected;
      case CloudServiceProvider.s3:
        return ref.watch(cloudS3AccountProvider) != null ||
            cloud.isS3Connected;
    }
  }

  /// Whether credentials are currently present on this device (non-reactive).
  /// Reflects local connection state only.
  bool get isConnected {
    final cloud = CloudDatabaseService.instance;
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return cloud.currentGoogleAccount != null;
      case CloudServiceProvider.dropbox:
        return cloud.currentDropboxToken != null;
      case CloudServiceProvider.oneDrive:
        return cloud.isOneDriveConnected;
      case CloudServiceProvider.webdav:
        return cloud.isWebDavConnected;
      case CloudServiceProvider.sftp:
        return cloud.isSftpConnected;
      case CloudServiceProvider.s3:
        return cloud.isS3Connected;
    }
  }

  /// The connected account label (email / account name), if any. Reads the
  /// reactive cloud account providers so the UI rebuilds on connect/disconnect.
  String? accountLabel(WidgetRef ref) {
    switch (this) {
      case CloudServiceProvider.googleDrive:
        return ref.watch(cloudGoogleAccountProvider) ??
            CloudDatabaseService.instance.currentGoogleAccount?.email;
      case CloudServiceProvider.dropbox:
        return ref.watch(cloudDropboxAccountProvider);
      case CloudServiceProvider.oneDrive:
        return ref.watch(cloudOneDriveAccountProvider);
      case CloudServiceProvider.webdav:
        return ref.watch(cloudWebDavAccountProvider);
      case CloudServiceProvider.sftp:
        return ref.watch(cloudSftpAccountProvider);
      case CloudServiceProvider.s3:
        return ref.watch(cloudS3AccountProvider);
    }
  }
}
