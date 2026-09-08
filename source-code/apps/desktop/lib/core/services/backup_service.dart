import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../repository/kdbx_repository_provider.dart';
import '../repository/vault_write_scheduler_provider.dart';
import 'bookmark_service.dart';
import 'cloud_token_store.dart';
import 'google_auth/google_auth.dart';
import 'onedrive_service.dart';
import 's3_service.dart';
import 'sftp_service.dart';

import 'webdav_service.dart';

// ── Models ────────────────────────────────────────────────────────────────────

/// A folder entry returned by cloud storage folder-listing APIs.
class CloudFolder {
  const CloudFolder({required this.id, required this.name, this.path});
  final String id;
  final String name;
  final String? path;

  String get displayPath => path ?? name;
}

/// A file entry returned by cloud storage file-listing APIs.
class CloudFile {
  const CloudFile({required this.id, required this.name, this.path});
  final String id;
  final String name;
  final String? path;

  String get displayPath => path ?? name;
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum BackupDestination {
  localFolder,
  googleDrive,
  dropbox,
  oneDrive,
  webdav,
  sftp,
  s3,
}

enum BackupStatus { idle, running, done, error }

/// Outcome of a cloud-credential health check run before unlocking a
/// cloud-backed vault. The unlock flow uses this to warn the user when
/// future syncs would silently fail.
enum CloudCredentialStatus {
  /// Credentials look healthy; sync should work.
  valid,

  /// Vault is local — no cloud check applies.
  notApplicable,

  /// No credentials are persisted on this device (user disconnected or
  /// never connected on this install).
  notSignedIn,

  /// Tokens exist but the provider rejected them (revoked, password
  /// changed, scope removed, etc.).
  authExpired,

  /// Credentials may still be fine, but the provider was unreachable.
  networkError,
}

class CloudCredentialResult {
  const CloudCredentialResult(
    this.status, {
    this.providerLabel,
    this.message,
  });

  final CloudCredentialStatus status;
  final String? providerLabel;
  final String? message;

  bool get isHealthy =>
      status == CloudCredentialStatus.valid ||
      status == CloudCredentialStatus.notApplicable;

  bool get isAuthIssue =>
      status == CloudCredentialStatus.notSignedIn ||
      status == CloudCredentialStatus.authExpired;
}

const bool kBackupRestoreFeatureEnabled =
    bool.fromEnvironment('BACKUP_RESTORE_FEATURE_ENABLED', defaultValue: true);

typedef BackupTimerFactory = Timer Function(Duration delay, void Function() cb);
typedef BackupClock = DateTime Function();
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class LocalBackupInfo {
  const LocalBackupInfo({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
  final DateTime createdAt;
}

class BackupRestoreProgress {
  const BackupRestoreProgress({
    required this.value,
    required this.message,
    this.logs = const <String>[],
  });

  final double value;
  final String message;
  final List<String> logs;
}

// ── Providers ─────────────────────────────────────────────────────────────────

final backupEnabledProvider = StateProvider<bool>((ref) => false);
final backupDestinationProvider =
    StateProvider<BackupDestination>((ref) => BackupDestination.localFolder);
final backupStatusProvider =
    StateProvider<BackupStatus>((ref) => BackupStatus.idle);
final backupLastTimestampProvider = StateProvider<DateTime?>((ref) => null);
final backupNextTimestampProvider = StateProvider<DateTime?>((ref) => null);

/// Number of days to keep local backup copies before they are automatically
/// pruned. Defaults to 7. Persisted under [_kBackupRetentionDays].
final backupRetentionDaysProvider = StateProvider<int>((ref) => 7);
final backupActiveVaultPathProvider = StateProvider<String?>((ref) => null);
final backupRestoreProgressProvider =
    StateProvider<BackupRestoreProgress?>((ref) => null);
final backupLocalPathProvider = StateProvider<String?>((ref) => null);
final backupGoogleAccountProvider = StateProvider<String?>((ref) => null);
final backupDropboxAccountProvider = StateProvider<String?>((ref) => null);
final backupGoogleFolderIdProvider = StateProvider<String?>((ref) => null);
final backupGoogleFolderNameProvider = StateProvider<String?>((ref) => null);
final backupDropboxFolderPathProvider = StateProvider<String?>((ref) => null);
final backupDropboxFolderNameProvider = StateProvider<String?>((ref) => null);
final backupOneDriveAccountProvider = StateProvider<String?>((ref) => null);
final backupOneDriveFolderIdProvider = StateProvider<String?>((ref) => null);
final backupOneDriveFolderNameProvider = StateProvider<String?>((ref) => null);
final backupWebDavAccountProvider = StateProvider<String?>((ref) => null);
final backupWebDavFolderPathProvider = StateProvider<String?>((ref) => null);
final backupWebDavFolderNameProvider = StateProvider<String?>((ref) => null);
final backupSftpAccountProvider = StateProvider<String?>((ref) => null);
final backupSftpFolderPathProvider = StateProvider<String?>((ref) => null);
final backupSftpFolderNameProvider = StateProvider<String?>((ref) => null);

final backupS3AccountProvider = StateProvider<String?>((ref) => null);
final backupS3FolderPathProvider = StateProvider<String?>((ref) => null);
final backupS3FolderNameProvider = StateProvider<String?>((ref) => null);

// ── Storage keys ──────────────────────────────────────────────────────────────

const String _kBackupEnabled = 'backup_enabled';
const String _kBackupDestination = 'backup_destination';
const String _kBackupLocalPath = 'backup_local_path';
const String _kBackupLocalBookmark = 'backup_local_bookmark';
const String _kBackupGoogleAccount = 'backup_google_account';
const String _kBackupDropboxToken = 'backup_dropbox_token';
const String _kBackupDropboxAccount = 'backup_dropbox_account';
const String _kBackupLastTimestamp = 'backup_last_timestamp';
const String _kBackupRetentionDays = 'backup_retention_days';
const String _kBackupGoogleFolderId = 'backup_google_folder_id';
const String _kBackupGoogleFolderName = 'backup_google_folder_name';
const String _kBackupDropboxFolderPath = 'backup_dropbox_folder_path';
const String _kBackupDropboxFolderName = 'backup_dropbox_folder_name';
const String _kBackupOneDriveAccessToken = 'backup_onedrive_access_token';
const String _kBackupOneDriveRefreshToken = 'backup_onedrive_refresh_token';
const String _kBackupOneDriveAccount = 'backup_onedrive_account';
const String _kBackupOneDriveTokenExpiry = 'backup_onedrive_token_expiry';
const String _kBackupOneDriveFolderId = 'backup_onedrive_folder_id';
const String _kBackupOneDriveFolderName = 'backup_onedrive_folder_name';
const String _kBackupWebDavHost = 'backup_webdav_host';
const String _kBackupWebDavPort = 'backup_webdav_port';
const String _kBackupWebDavUsername = 'backup_webdav_username';
const String _kBackupWebDavPassword = 'backup_webdav_password';
const String _kBackupWebDavRootPath = 'backup_webdav_root_path';
const String _kBackupWebDavAccount = 'backup_webdav_account';
const String _kBackupWebDavFolderPath = 'backup_webdav_folder_path';
const String _kBackupWebDavFolderName = 'backup_webdav_folder_name';
const String _kBackupSftpHost = 'backup_sftp_host';
const String _kBackupSftpPort = 'backup_sftp_port';
const String _kBackupSftpUsername = 'backup_sftp_username';
const String _kBackupSftpAuthMethod = 'backup_sftp_auth_method';
const String _kBackupSftpPassword = 'backup_sftp_password';
const String _kBackupSftpKeyFilePath = 'backup_sftp_key_file_path';
const String _kBackupSftpKeyFileBookmark = 'backup_sftp_key_file_bookmark';
const String _kBackupSftpTransferMode = 'backup_sftp_transfer_mode';
const String _kBackupSftpRootPath = 'backup_sftp_root_path';
const String _kBackupSftpAccount = 'backup_sftp_account';
const String _kBackupSftpFolderPath = 'backup_sftp_folder_path';
const String _kBackupSftpFolderName = 'backup_sftp_folder_name';

const String _kBackupS3Account = 'backup_s3_account';
const String _kBackupS3AccessKey = 'backup_s3_access_key';
const String _kBackupS3SecretKey = 'backup_s3_secret_key';
const String _kBackupS3Region = 'backup_s3_region';
const String _kBackupS3Bucket = 'backup_s3_bucket';
const String _kBackupS3RootPath = 'backup_s3_root_path';
const String _kBackupS3Host = 'backup_s3_host';
const String _kBackupS3SessionToken = 'backup_s3_session_token';
const String _kBackupS3FolderPath = 'backup_s3_folder_path';
const String _kBackupS3FolderName = 'backup_s3_folder_name';

// ── BackupService ─────────────────────────────────────────────────────────────

/// Singleton service managing scheduled vault backups.
///
/// Automatic backups use the user's local wall clock and fire at exactly
/// 00:00, 04:00, 08:00, 12:00, 16:00, and 20:00 for the currently unlocked vault.
///
/// Configure OAuth credentials via dart-define:
///   --dart-define=GOOGLE_CLIENT_ID=YOUR_CLIENT_ID
///   --dart-define=DROPBOX_APP_KEY=YOUR_APP_KEY
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const String _kDropboxAppKey =
      String.fromEnvironment('DROPBOX_APP_KEY');
  static bool get isDropboxConfigured => _kDropboxAppKey.isNotEmpty;

  static const String _kDefaultDropboxFolderPath = '/lumenpass-backups';

  static const String _kOneDriveClientId =
      String.fromEnvironment('ONEDRIVE_CLIENT_ID');
  static bool get isOneDriveConfigured => _kOneDriveClientId.isNotEmpty;

  static const String _kDefaultOneDriveFolderName = 'LumenPass';

  ProviderContainer? _container;
  final Completer<void> _initCompleter = Completer<void>();
  bool _initStarted = false;
  Timer? _timer;
  BackupTimerFactory _timerFactory = (delay, cb) => Timer(delay, cb);
  BackupClock _clock = DateTime.now;
  ProcessRunner _processRunner = Process.run;
  String? _backupRootDirectoryOverride;
  String? _scheduledVaultPath;
  CloudTokenStore? _tokenStore;

  /// Keys that contain credentials (OAuth tokens, passwords, API keys) and
  /// must be stored in the OS keychain via [CloudTokenStore], not in the
  /// plain-text [LocalStorageProvider].
  static const _sensitiveKeys = <String>[
    _kBackupDropboxToken,
    _kBackupOneDriveAccessToken,
    _kBackupOneDriveRefreshToken,
    _kBackupOneDriveTokenExpiry,
    _kBackupWebDavPassword,
    _kBackupSftpPassword,
    _kBackupS3AccessKey,
    _kBackupS3SecretKey,
    _kBackupS3SessionToken,
  ];

  static const List<int> fixedLocalBackupHours = <int>[0, 4, 8, 12, 16, 20];

  // Google Sign-In — reads GIDClientID from Info.plist when dart-define is absent.
  static const _kGoogleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

  /// Full Drive access. Required so that vaults the user opened from Drive
  /// (i.e. files **not** created by this app) can still be written back.
  ///
  /// Narrower scopes (`drive.file` / `drive.readonly`) only allow updating
  /// files the app itself created or that were handed to it via the Google
  /// Picker — attempting `files.update` on an arbitrary Drive file returns
  /// `403 — The user has not granted the app ... write access to the file`.
  static const _kDriveFullScope = 'https://www.googleapis.com/auth/drive';

  static const _kGoogleClientSecret =
      String.fromEnvironment('GOOGLE_CLIENT_SECRET');

  /// Single platform-resolved Google OAuth client. All three desktop
  /// platforms (Windows, macOS, Linux) use the loopback PKCE flow because the
  /// official `google_sign_in` plugin has no working implementation on any of
  /// them in this app.
  static final GoogleAuth _googleAuth = googleAuthFor(
    clientId: _kGoogleClientId,
    clientSecret: _kGoogleClientSecret.isEmpty ? null : _kGoogleClientSecret,
    scopes: const <String>[
      'https://www.googleapis.com/auth/drive.file',
      _kDriveFullScope,
      'email',
    ],
  );

  String? _dropboxAccessToken;

  String? _oneDriveAccessToken;
  DateTime? _oneDriveTokenExpiry;

  WebDavConfig? _webDavConfig;
  SftpConfig? _sftpConfig;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> ensureReady() async {
    if (!_initStarted) return;
    await _initCompleter.future;
  }

  Future<void> init(ProviderContainer container) async {
    _initStarted = true;
    _container = container;
    try {
      final storage = container.read(localStorageProvider);

      // -- Migrate sensitive credentials to OS keychain --------------------------
      _tokenStore = CloudTokenStore();
      await _tokenStore!.migrateFrom(
        legacyRead: (key) => storage.read(key: key),
        legacyDelete: (key) => storage.delete(key: key),
        sensitiveKeys: _sensitiveKeys,
      );

      // -- Non-sensitive preferences (plain key-value) --------------------------
      final enabledStr = await storage.read(key: _kBackupEnabled);

      final localPath = await storage.read(key: _kBackupLocalPath);
      final googleAccount = await storage.read(key: _kBackupGoogleAccount);
      final dropboxAccount = await storage.read(key: _kBackupDropboxAccount);
      final lastTs = await storage.read(key: _kBackupLastTimestamp);
      final retentionDaysStr = await storage.read(key: _kBackupRetentionDays);
      final googleFolderId = await storage.read(key: _kBackupGoogleFolderId);
      final googleFolderName =
          await storage.read(key: _kBackupGoogleFolderName);
      final dropboxFolderPath =
          await storage.read(key: _kBackupDropboxFolderPath);
      final dropboxFolderName =
          await storage.read(key: _kBackupDropboxFolderName);
      final oneDriveAccount = await storage.read(key: _kBackupOneDriveAccount);
      final oneDriveFolderId =
          await storage.read(key: _kBackupOneDriveFolderId);
      final oneDriveFolderName =
          await storage.read(key: _kBackupOneDriveFolderName);

      // -- Sensitive credentials (OS keychain) ----------------------------------
      final tokenStore = _tokenStore!;
      final dropboxToken = await tokenStore.read(_kBackupDropboxToken);
      final oneDriveAccessToken =
          await tokenStore.read(_kBackupOneDriveAccessToken);
      final oneDriveRefreshToken =
          await tokenStore.read(_kBackupOneDriveRefreshToken);
      final oneDriveTokenExpiryStr =
          await tokenStore.read(_kBackupOneDriveTokenExpiry);
      final oneDriveTokenExpiry = oneDriveTokenExpiryStr != null
          ? DateTime.tryParse(oneDriveTokenExpiryStr)
          : null;

      final enabled = enabledStr == 'true';

      container.read(backupEnabledProvider.notifier).state = enabled;
      // Destination selector has been removed from the UI — always use local.
      container.read(backupDestinationProvider.notifier).state =
          BackupDestination.localFolder;
      container.read(backupLocalPathProvider.notifier).state = localPath;
      container.read(backupGoogleAccountProvider.notifier).state =
          googleAccount;
      container.read(backupDropboxAccountProvider.notifier).state =
          dropboxAccount;
      container.read(backupGoogleFolderIdProvider.notifier).state =
          googleFolderId;
      container.read(backupGoogleFolderNameProvider.notifier).state =
          googleFolderName;
      container.read(backupDropboxFolderPathProvider.notifier).state =
          dropboxFolderPath;
      container.read(backupDropboxFolderNameProvider.notifier).state =
          dropboxFolderName;
      container.read(backupLastTimestampProvider.notifier).state =
          lastTs != null ? DateTime.tryParse(lastTs) : null;

      // Retention window for local backups. Falls back to the 7-day default
      // when unset or corrupt so pruning always has a sane bound.
      container.read(backupRetentionDaysProvider.notifier).state =
          int.tryParse(retentionDaysStr ?? '') ?? 7;

      if (dropboxToken != null) _dropboxAccessToken = dropboxToken;

      // If Dropbox is connected but no folder is configured, default to the app
      // folder so backups don't end up in the Dropbox root.
      if (_dropboxAccessToken != null &&
          (dropboxFolderPath == null || dropboxFolderPath.isEmpty)) {
        container.read(backupDropboxFolderPathProvider.notifier).state =
            _kDefaultDropboxFolderPath;
        container.read(backupDropboxFolderNameProvider.notifier).state =
            _kDefaultDropboxFolderPath;
        await storage.write(
          key: _kBackupDropboxFolderPath,
          value: _kDefaultDropboxFolderPath,
        );
        await storage.write(
          key: _kBackupDropboxFolderName,
          value: _kDefaultDropboxFolderPath,
        );
      }

      // Restore OneDrive tokens.
      if (oneDriveAccessToken != null) {
        _oneDriveAccessToken = oneDriveAccessToken;
        _oneDriveTokenExpiry = oneDriveTokenExpiry;
        // Hand the persisted tokens to OneDriveService — all OneDrive file
        // operations delegate to it, so without this it would report
        // "Not connected" after every app restart.
        OneDriveService.instance.restoreTokens(
          accessToken: oneDriveAccessToken,
          refreshToken: oneDriveRefreshToken,
          expiry: _oneDriveTokenExpiry,
        );
      }
      container.read(backupOneDriveAccountProvider.notifier).state =
          oneDriveAccount;
      container.read(backupOneDriveFolderIdProvider.notifier).state =
          oneDriveFolderId;
      container.read(backupOneDriveFolderNameProvider.notifier).state =
          oneDriveFolderName;

      // Restore WebDAV configuration (password is a secret, stored separately).
      final webDavHost = await storage.read(key: _kBackupWebDavHost);
      final webDavPortStr = await storage.read(key: _kBackupWebDavPort);
      final webDavUsername = await storage.read(key: _kBackupWebDavUsername);
      final webDavPassword = await tokenStore.read(_kBackupWebDavPassword);
      final webDavRootPath = await storage.read(key: _kBackupWebDavRootPath);
      final webDavAccount = await storage.read(key: _kBackupWebDavAccount);
      final webDavFolderPath =
          await storage.read(key: _kBackupWebDavFolderPath);
      final webDavFolderName =
          await storage.read(key: _kBackupWebDavFolderName);

      if (webDavHost != null &&
          webDavHost.isNotEmpty &&
          webDavPassword != null &&
          webDavPassword.isNotEmpty) {
        _webDavConfig = WebDavConfig(
          host: webDavHost,
          port: int.tryParse(webDavPortStr ?? '') ?? 443,
          username: webDavUsername ?? '',
          password: webDavPassword,
          rootPath: webDavRootPath ?? '/',
        );
        // Hand the restored config to the singleton so file operations work
        // after a restart without re-entering credentials.
        WebDavService.instance.restore(_webDavConfig!);
      }
      container.read(backupWebDavAccountProvider.notifier).state =
          webDavAccount;
      container.read(backupWebDavFolderPathProvider.notifier).state =
          webDavFolderPath;
      container.read(backupWebDavFolderNameProvider.notifier).state =
          webDavFolderName;

      // Restore SFTP configuration (password is a secret, stored separately).
      final sftpHost = await storage.read(key: _kBackupSftpHost);
      final sftpPortStr = await storage.read(key: _kBackupSftpPort);
      final sftpUsername = await storage.read(key: _kBackupSftpUsername);
      final sftpAuthMethod = await storage.read(key: _kBackupSftpAuthMethod);
      final sftpPassword = await tokenStore.read(_kBackupSftpPassword);
      final sftpKeyFilePath = await storage.read(key: _kBackupSftpKeyFilePath);
      final sftpKeyFileBookmark =
          await storage.read(key: _kBackupSftpKeyFileBookmark);
      final sftpTransferMode =
          await storage.read(key: _kBackupSftpTransferMode);
      final sftpRootPath = await storage.read(key: _kBackupSftpRootPath);
      final sftpAccount = await storage.read(key: _kBackupSftpAccount);
      final sftpFolderPath = await storage.read(key: _kBackupSftpFolderPath);
      final sftpFolderName = await storage.read(key: _kBackupSftpFolderName);

      final s3Account = await storage.read(key: _kBackupS3Account);
      final s3AccessKey = await tokenStore.read(_kBackupS3AccessKey);
      final s3SecretKey = await tokenStore.read(_kBackupS3SecretKey);
      final s3Region = await storage.read(key: _kBackupS3Region);
      final s3Bucket = await storage.read(key: _kBackupS3Bucket);
      final s3RootPath = await storage.read(key: _kBackupS3RootPath);
      final s3Host = await storage.read(key: _kBackupS3Host);
      final s3SessionToken = await tokenStore.read(_kBackupS3SessionToken);
      final s3FolderPath = await storage.read(key: _kBackupS3FolderPath);
      final s3FolderName = await storage.read(key: _kBackupS3FolderName);

      if (sftpHost != null &&
          sftpHost.isNotEmpty &&
          ((sftpPassword != null && sftpPassword.isNotEmpty) ||
              (sftpKeyFilePath != null && sftpKeyFilePath.isNotEmpty))) {
        _sftpConfig = SftpConfig.fromJson(
          <String, dynamic>{
            'host': sftpHost,
            'port': int.tryParse(sftpPortStr ?? '') ?? 22,
            'username': sftpUsername ?? '',
            'authMethod': sftpAuthMethod,
            'keyFilePath': sftpKeyFilePath,
            'keyFileBookmark': sftpKeyFileBookmark,
            'transferMode': sftpTransferMode,
            'rootPath': sftpRootPath ?? '/',
          },
          password: sftpPassword ?? '',
        );
        SftpService.instance.restore(_sftpConfig!);
      }
      container.read(backupSftpAccountProvider.notifier).state = sftpAccount;
      container.read(backupSftpFolderPathProvider.notifier).state =
          sftpFolderPath;
      container.read(backupSftpFolderNameProvider.notifier).state =
          sftpFolderName;

      // Restore S3 configuration (access key + secret key are secrets).
      if (s3AccessKey != null &&
          s3AccessKey.isNotEmpty &&
          s3SecretKey != null &&
          s3SecretKey.isNotEmpty &&
          s3Bucket != null &&
          s3Bucket.isNotEmpty) {
        final s3Config = S3Config(
          accessKey: s3AccessKey,
          secretKey: s3SecretKey,
          region: s3Region ?? 'us-east-1',
          bucketId: s3Bucket,
          host: s3Host,
          sessionToken: s3SessionToken,
          rootPath: s3RootPath ?? '',
        );
        S3Service.instance.configure(s3Config);
      }

      container.read(backupS3AccountProvider.notifier).state = s3Account;
      container.read(backupS3FolderPathProvider.notifier).state = s3FolderPath;
      container.read(backupS3FolderNameProvider.notifier).state = s3FolderName;

      if (enabled && container.read(activeDatabaseProvider) != null) {
        resumeForUnlockedVault();
      }

      // Warm the Google Drive credential cache from disk so the unlock
      // screen's first health probe sees hydrated credentials instead of a
      // cold `_currentUser == null`. Fire-and-forget: hydration is fast, and
      // blocking init on a possible network token refresh would delay every
      // launch. Correctness does not depend on this completing first — the
      // serialized hydration inside GoogleAuth guarantees concurrent probes
      // never observe a half-hydrated state. Errors (e.g. a rethrown network
      // failure during refresh) are swallowed here so they can't surface as
      // an unhandled async error; the probe re-runs the check and classifies
      // them properly.
      unawaited(
        _googleAuth.signInSilently().catchError(
          (Object error) {
            debugPrint('[Backup] eager Google hydration failed: $error');
            return null;
          },
        ),
      );
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  /// Enables or disables automatic backup.
  /// Enabling schedules the next fixed local-time backup for the active vault.
  Future<void> setEnabled(bool enabled) async {
    final container = _container;
    if (container == null) return;

    await container.read(localStorageProvider).write(
          key: _kBackupEnabled,
          value: enabled ? 'true' : 'false',
        );
    container.read(backupEnabledProvider.notifier).state = enabled;

    if (enabled) {
      resumeForUnlockedVault();
    } else {
      cancelForLockedVault();
    }
  }

  void configureForTests({
    BackupClock? clock,
    BackupTimerFactory? timerFactory,
    ProcessRunner? processRunner,
    String? backupRootDirectory,
    ProviderContainer? container,
  }) {
    _clock = clock ?? _clock;
    _timerFactory = timerFactory ?? _timerFactory;
    _processRunner = processRunner ?? _processRunner;
    _backupRootDirectoryOverride =
        backupRootDirectory ?? _backupRootDirectoryOverride;
    _container = container ?? _container;
  }

  /// Test-only entry point for exercising the retention prune in isolation.
  @visibleForTesting
  Future<void> pruneOldBackupsForTesting(String vaultPath) =>
      _pruneOldBackups(vaultPath);

  void resumeForUnlockedVault() {
    final container = _container;
    if (container == null || !kBackupRestoreFeatureEnabled) return;
    final db = container.read(activeDatabaseProvider);
    if (db == null || !container.read(backupEnabledProvider)) {
      cancelForLockedVault();
      return;
    }
    _scheduledVaultPath = db.path;
    container.read(backupActiveVaultPathProvider.notifier).state = db.path;
    _scheduleNextFixedBackup();
    // Prune expired local backups whenever a vault becomes active so stale
    // copies are removed on launch/unlock, not just after the next backup run.
    unawaited(
      _pruneOldBackups(db.path).catchError((Object e) {
        debugPrint('[Backup] startup prune failed: $e');
      }),
    );
  }

  void cancelForLockedVault() {
    _cancelTimer();
    _scheduledVaultPath = null;
    final container = _container;
    if (container != null) {
      container.read(backupNextTimestampProvider.notifier).state = null;
      container.read(backupActiveVaultPathProvider.notifier).state = null;
    }
  }

  /// Returns the next fixed backup time in local wall-clock time.
  DateTime nextFixedBackupTime([DateTime? from]) {
    final now = from ?? _clock();
    for (final hour in fixedLocalBackupHours) {
      final candidate = DateTime(now.year, now.month, now.day, hour);
      if (candidate.isAfter(now)) return candidate;
    }
    final tomorrow = now.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
  }

  /// Lists local backup snapshots for [vaultPath], newest first.
  ///
  /// When [vaultPath] is omitted the active (unlocked) vault path is used.
  /// Unlock-screen restore passes an explicit path so backups can be listed
  /// for a vault that is locked or too corrupted to open.
  Future<List<LocalBackupInfo>> listLocalBackups({String? vaultPath}) async {
    final path = vaultPath ?? _container?.read(activeDatabaseProvider)?.path;
    if (path == null || path.isEmpty) return const <LocalBackupInfo>[];
    final vaultDir = await _localVaultBackupDirectory(path);
    final dir = Directory(vaultDir);
    if (!await dir.exists()) return const <LocalBackupInfo>[];
    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.kdbx'))
        .cast<File>()
        .toList();
    final backups = <LocalBackupInfo>[];
    for (final file in files) {
      final stat = await file.stat();
      backups.add(LocalBackupInfo(
        path: file.path,
        fileName: p.basename(file.path),
        sizeBytes: stat.size,
        createdAt: stat.changed,
      ));
    }
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  Future<bool> canOpenLocalBackupFolder() async {
    final root = await _localBackupRootDirectory();
    final dir = Directory(root);
    if (await dir.exists()) return true;
    try {
      await dir.create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openLocalBackupFolder({String? vaultPath}) async {
    final String targetPath;
    if (vaultPath != null && vaultPath.isNotEmpty) {
      targetPath = await _localVaultBackupDirectory(vaultPath);
    } else {
      targetPath = await _localBackupRootDirectory();
    }
    final dir = Directory(targetPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = dir.path;
    if (Platform.isWindows) {
      await _processRunner(
          'explorer.exe', ['/select,${File(path).absolute.path}']);
    } else if (Platform.isMacOS) {
      await _processRunner('open', [path]);
    } else {
      try {
        await _processRunner('xdg-open', [path]);
      } catch (_) {
        await _processRunner('gtk-launch', [path]);
      }
    }
  }

  /// KDBX file-format signatures (little-endian) that mark the start of
  /// every valid v3/v4 KeePass database. Used to short-circuit obviously
  /// invalid files before we attempt to copy them over the live vault.
  static const List<int> _kdbxSignature1 = <int>[0x03, 0xD9, 0xA2, 0x9A];
  static const List<int> _kdbxSignature2 = <int>[0x67, 0xFB, 0x4B, 0xB5];

  /// Verifies [backupPath] is structurally a KDBX file without attempting
  /// to decrypt it. Restore is a pure file-replacement operation — the
  /// existing unlock screen handles password / keyfile / biometric / PIN
  /// composite credentials uniformly after the file is in place, so this
  /// method intentionally does NOT ask for a master password.
  ///
  /// Returns a developer-friendly error string on failure or `null` if
  /// the file looks safe to copy over the live vault.
  Future<String?> validateBackupFile({
    required String backupPath,
    String? targetVaultPath,
  }) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      return 'Selected backup file no longer exists on disk.';
    }
    final lower = backupPath.toLowerCase();
    if (!lower.endsWith('.kdbx')) {
      return 'Only .kdbx backup files are supported.';
    }
    int sizeBytes;
    try {
      sizeBytes = await file.length();
    } catch (e) {
      return 'Unable to read backup file: $e';
    }
    if (sizeBytes < 12) {
      return 'Backup file appears to be corrupt or truncated.';
    }
    if (targetVaultPath != null) {
      try {
        if (p.canonicalize(backupPath) == p.canonicalize(targetVaultPath)) {
          return 'Cannot restore the live vault onto itself.';
        }
      } catch (_) {}
    }
    try {
      final raf = await file.open();
      try {
        final header = await raf.read(8);
        if (header.length < 8) {
          return 'Backup file is too small to be a valid KDBX database.';
        }
        for (var i = 0; i < 4; i++) {
          if (header[i] != _kdbxSignature1[i]) {
            return 'Backup file is not in KDBX format (bad magic).';
          }
        }
        for (var i = 0; i < 4; i++) {
          if (header[4 + i] != _kdbxSignature2[i]) {
            return 'Backup file is not in KDBX format (bad secondary magic).';
          }
        }
      } finally {
        await raf.close();
      }
    } catch (e) {
      return 'Could not read backup header: $e';
    }
    return null;
  }

  /// Restores [backup] by replacing the file at [targetVaultPath] (or the
  /// active database path) with the snapshot's bytes. Restore is a
  /// **file-level operation** — we never decrypt the backup. After the
  /// copy completes the caller is expected to navigate the user to the
  /// unlock screen, where the existing flow handles password, keyfile,
  /// biometric, and PIN credentials uniformly.
  ///
  /// A pre-restore fallback copy is kept on disk so we can roll back if
  /// the rename or post-write checks fail.
  Future<void> restoreLocalBackup(
    LocalBackupInfo backup, {
    String? targetVaultPath,
  }) async {
    final container = _container;
    final activeDb = container?.read(activeDatabaseProvider);
    final livePath = targetVaultPath ?? activeDb?.path;
    if (livePath == null || livePath.isEmpty) {
      throw StateError(
          'No active vault path is known — open or select a vault first.');
    }
    final liveFile = File(livePath);
    final liveExisted = await liveFile.exists();
    // Missing vault files are allowed — unlock-screen restore can recreate
    // a deleted/corrupted database from its backup snapshot.
    if (!await File(backup.path).exists()) {
      throw StateError(
          'Selected backup file no longer exists at ${backup.path}.');
    }
    final structuralIssue = await validateBackupFile(
      backupPath: backup.path,
      targetVaultPath: livePath,
    );
    if (structuralIssue != null) {
      throw StateError(structuralIssue);
    }

    final logs = <String>[];
    void progress(double value, String message) {
      logs.add(message);
      container?.read(backupRestoreProgressProvider.notifier).state =
          BackupRestoreProgress(
              value: value, message: message, logs: List.unmodifiable(logs));
      debugPrint('[Restore] ${(value * 100).toStringAsFixed(0)}% $message');
    }

    // Stage temp + fallback copies inside a directory we always own
    // (the app's temporary directory). Writing siblings next to `livePath`
    // would require *folder*-level sandbox access on macOS, but the live
    // vault only has a *file*-scoped security bookmark — that's why direct
    // sibling writes failed with PathAccessException.
    final stagingDir = await getTemporaryDirectory();
    final stamp = _restoreStamp(_clock());
    final baseName = p.basenameWithoutExtension(livePath);
    final fallbackPath =
        p.join(stagingDir.path, '$baseName.restore-fallback-$stamp.kdbx');
    final tempPath =
        p.join(stagingDir.path, '$baseName.restore-tmp-$stamp.kdbx');
    bool fallbackCreated = false;
    try {
      progress(0.1, 'Releasing active vault locks');
      // Note: we deliberately do NOT call cancelForLockedVault() or drop
      // the file's security-scoped bookmark here — sandboxed macOS builds
      // need that bookmark to remain active so the upcoming overwrite of
      // [livePath] is permitted. The orchestrator releases it after the
      // bytes are on disk.
      // The orchestrator already flushed pending writes before invoking this
      // restore; reset the scheduler so no stale scheduled save lands on the
      // file being overwritten.
      container?.read(vaultWriteSchedulerProvider).reset();
      container?.read(kdbxRepositoryProvider).closeDatabase();
      container?.read(activeDatabaseProvider.notifier).state = null;

      if (liveExisted) {
        progress(0.3, 'Creating emergency fallback copy');
        await liveFile.copy(fallbackPath);
        fallbackCreated = true;
      } else {
        progress(0.3, 'Live vault missing — recreating from backup');
        final parent = Directory(p.dirname(livePath));
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
      }

      progress(0.55, 'Copying backup snapshot to a staging file');
      await File(backup.path).copy(tempPath);

      progress(0.8, 'Writing restored vault bytes');
      // Use copy() rather than rename(): rename across filesystems fails,
      // and rename into a sandboxed path requires folder-level access we
      // don't have. copy() goes through the file's bookmarked descriptor.
      await File(tempPath).copy(livePath);

      progress(0.95, 'Verifying restored file on disk');
      final restored = File(livePath);
      if (!await restored.exists() || (await restored.length()) < 12) {
        throw StateError('Restored vault is missing or empty after overwrite.');
      }
      progress(1, 'Restore complete — unlock to access your data');
    } catch (e) {
      progress(0.97, 'Restore failed, rolling back');
      if (fallbackCreated && await File(fallbackPath).exists()) {
        try {
          await File(fallbackPath).copy(livePath);
        } catch (rollbackErr) {
          throw Exception(
              'Restore failed AND rollback could not restore the original vault: $rollbackErr (original error: $e)');
        }
      }
      throw Exception('Restore failed; rollback was attempted. $e');
    } finally {
      if (await File(tempPath).exists()) {
        try {
          await File(tempPath).delete();
        } catch (_) {}
      }
      if (fallbackCreated && await File(fallbackPath).exists()) {
        try {
          await File(fallbackPath).delete();
        } catch (_) {}
      }
    }
  }

  /// Runs a single backup to the currently configured destination.
  Future<void> runBackup() async {
    final container = _container;
    if (container == null) return;

    final db = container.read(activeDatabaseProvider);
    if (db == null) {
      debugPrint('[Backup] no active vault — skipping');
      return;
    }

    if (container.read(backupStatusProvider) == BackupStatus.running) return;

    container.read(backupStatusProvider.notifier).state = BackupStatus.running;

    try {
      final activeVaultPath = _scheduledVaultPath;
      if (activeVaultPath != null && db.path != activeVaultPath) return;

      // Destination selector removed from UI — always backup locally.
      const destination = BackupDestination.localFolder;
      final timestamp = _clock();
      final safeName =
          timestamp.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final vaultLabel =
          _sanitizeBackupSegment(p.basenameWithoutExtension(db.path));
      final fileName = '${vaultLabel}_backup_$safeName.kdbx';

      switch (destination) {
        case BackupDestination.localFolder:
          await _backupToLocalFolder(db.path, fileName, vaultLabel: vaultLabel);
        case BackupDestination.googleDrive:
          await _backupToGoogleDrive(db.path, fileName);
        case BackupDestination.dropbox:
          await _backupToDropbox(db.path, fileName, vaultLabel: vaultLabel);
        case BackupDestination.oneDrive:
          await _backupToOneDrive(db.path, fileName, vaultLabel: vaultLabel);
        case BackupDestination.webdav:
          await _backupToWebDav(db.path, fileName, vaultLabel: vaultLabel);
        case BackupDestination.sftp:
          await _backupToSftp(db.path, fileName, vaultLabel: vaultLabel);
        case BackupDestination.s3:
          await _backupToS3(db.path, fileName, vaultLabel: vaultLabel);
      }

      container.read(backupLastTimestampProvider.notifier).state = timestamp;
      await container.read(localStorageProvider).write(
            key: _kBackupLastTimestamp,
            value: timestamp.toIso8601String(),
          );

      // Enforce the configured retention window after each successful backup
      // so old copies don't accumulate on disk. Failures here must not fail
      // the backup itself — the fresh copy is already safely written.
      try {
        await _pruneOldBackups(db.path);
      } catch (e) {
        debugPrint('[Backup] prune failed: $e');
      }

      container.read(backupStatusProvider.notifier).state = BackupStatus.done;
    } catch (e) {
      debugPrint('[Backup] runBackup failed: $e');
      container.read(backupStatusProvider.notifier).state = BackupStatus.error;
    }

    // Auto-reset to idle after a brief pause so the status row stays visible.
    await Future<void>.delayed(const Duration(seconds: 4));
    final c = _container;
    if (c != null && c.read(backupStatusProvider) != BackupStatus.running) {
      c.read(backupStatusProvider.notifier).state = BackupStatus.idle;
    }
  }

  // ── Destination ────────────────────────────────────────────────────────────

  Future<void> setDestination(BackupDestination dest) async {
    final container = _container;
    if (container == null) return;
    container.read(backupDestinationProvider.notifier).state = dest;
    await container.read(localStorageProvider).write(
          key: _kBackupDestination,
          value: _destinationToString(dest),
        );
  }

  /// Persists the local-backup retention window (in days) and immediately
  /// applies it to the active vault so shortening the window prunes right
  /// away instead of waiting for the next scheduled backup.
  Future<void> setRetentionDays(int days) async {
    final container = _container;
    if (container == null) return;
    final clamped = days < 1 ? 1 : days;
    container.read(backupRetentionDaysProvider.notifier).state = clamped;
    await container.read(localStorageProvider).write(
          key: _kBackupRetentionDays,
          value: clamped.toString(),
        );
    final activePath = container.read(activeDatabaseProvider)?.path;
    if (activePath != null && activePath.isNotEmpty) {
      try {
        await _pruneOldBackups(activePath);
      } catch (e) {
        debugPrint('[Backup] prune after retention change failed: $e');
      }
    }
  }

  Future<void> setLocalPath(String path, String bookmark) async {
    final container = _container;
    if (container == null) return;
    container.read(backupLocalPathProvider.notifier).state = path;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupLocalPath, value: path);
    await storage.write(key: _kBackupLocalBookmark, value: bookmark);
  }

  Future<void> setGoogleDriveFolder(String id, String name) async {
    final container = _container;
    if (container == null) return;
    container.read(backupGoogleFolderIdProvider.notifier).state = id;
    container.read(backupGoogleFolderNameProvider.notifier).state = name;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupGoogleFolderId, value: id);
    await storage.write(key: _kBackupGoogleFolderName, value: name);
  }

  Future<void> setDropboxFolder(String path, String name) async {
    final container = _container;
    if (container == null) return;
    container.read(backupDropboxFolderPathProvider.notifier).state = path;
    container.read(backupDropboxFolderNameProvider.notifier).state = name;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupDropboxFolderPath, value: path);
    await storage.write(key: _kBackupDropboxFolderName, value: name);
  }

  // ── Google Drive ───────────────────────────────────────────────────────────

  Future<void> connectGoogle() async {
    final container = _container;
    if (container == null) return;
    try {
      final creds = await _googleAuth.signIn();
      if (creds == null) return;
      final email = creds.email;
      container.read(backupGoogleAccountProvider.notifier).state = email;
      await container
          .read(localStorageProvider)
          .write(key: _kBackupGoogleAccount, value: email);
    } catch (e) {
      debugPrint('[Backup] Google sign-in failed: $e');
      rethrow;
    }
  }

  /// Detects Google API "user hasn't granted write access" errors. Matches
  /// both googleapis `DetailedApiRequestError(status: 403)` and the 403 body
  /// text returned by the REST endpoints.
  bool _isDriveWritePermissionError(Object e) {
    final s = e.toString();
    if (!s.contains('403')) return false;
    return s.contains('has not granted the app') ||
        s.contains('insufficientFilePermissions') ||
        s.contains('insufficient permissions') ||
        s.contains('insufficientPermissions');
  }

  Future<void> disconnectGoogle() async {
    final container = _container;
    if (container == null) {
      debugPrint('[Backup] disconnectGoogle called before init');
      return;
    }
    try {
      await _googleAuth.signOut();
    } catch (e) {
      // signOut() can throw on macOS when there is no live session (e.g. the
      // token was revoked server-side or the user already signed out in the
      // browser). Treat it as best-effort and still clear local state so the
      // UI doesn't get stuck showing a "connected" account.
      debugPrint('[Backup] Google signOut failed, clearing local state: $e');
    }
    container.read(backupGoogleAccountProvider.notifier).state = null;
    container.read(backupGoogleFolderIdProvider.notifier).state = null;
    container.read(backupGoogleFolderNameProvider.notifier).state = null;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupGoogleAccount, value: null);
    await storage.write(key: _kBackupGoogleFolderId, value: null);
    await storage.write(key: _kBackupGoogleFolderName, value: null);
    if (container.read(backupDestinationProvider) ==
        BackupDestination.googleDrive) {
      await setDestination(BackupDestination.localFolder);
    }
  }

  // ── Dropbox ────────────────────────────────────────────────────────────────

  /// Runs a PKCE OAuth2 authorization flow for Dropbox.
  /// Requires DROPBOX_APP_KEY passed via --dart-define.
  Future<void> connectDropbox() async {
    const clientId = _kDropboxAppKey;
    if (clientId.isEmpty) {
      throw Exception(
        'DROPBOX_APP_KEY not configured. '
        'Pass it via --dart-define=DROPBOX_APP_KEY=<your_key>',
      );
    }

    const redirectPort = 17823;
    const redirectUrl = 'http://localhost:$redirectPort/callback';

    final verifier = _generatePkceVerifier();
    final challenge = _generatePkceChallenge(verifier);

    final authUri = Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUrl,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
      'scope': 'files.metadata.read files.content.read files.content.write',
    });

    HttpServer? server;
    try {
      // Bind first so the browser redirect can't race the server startup.
      server = await HttpServer.bind(
        'localhost',
        redirectPort,
        shared: true,
      );

      // Open system browser for authorization.
      final ok = await launchUrl(authUri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw Exception(
            'Could not open the browser for Dropbox authorization.');
      }

      // Capture OAuth callback (ignore unrelated requests like /favicon.ico).
      final codeCompleter = Completer<String>();
      final timeoutTimer = Timer(
        const Duration(minutes: 2),
        () {
          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(
              Exception(
                'Dropbox OAuth timed out. '
                'Make sure the Redirect URI is set to $redirectUrl in your Dropbox app settings, '
                'then try again.',
              ),
            );
          }
        },
      );

      unawaited(() async {
        try {
          await for (final request in server!) {
            final qp = request.requestedUri.queryParameters;
            final code = qp['code'];

            if (request.requestedUri.path != '/callback') {
              request.response
                ..statusCode = 404
                ..headers.set('content-type', 'text/plain; charset=utf-8')
                ..write('Not found');
              await request.response.close();
              continue;
            }

            if (code == null || code.isEmpty) {
              request.response
                ..statusCode = 400
                ..headers.set('content-type', 'text/plain; charset=utf-8')
                ..write('Missing authorization code');
              await request.response.close();
              continue;
            }

            request.response
              ..statusCode = 200
              ..headers.set('content-type', 'text/html; charset=utf-8')
              ..write(
                '<html><body style="font-family:sans-serif;padding:40px">'
                '<h2>LumenPass — Dropbox connected ✓</h2>'
                '<p>You may close this tab and return to LumenPass.</p>'
                '</body></html>',
              );
            await request.response.close();

            if (!codeCompleter.isCompleted) {
              codeCompleter.complete(code);
            }
            break;
          }
        } catch (_) {
          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(
              Exception('Dropbox OAuth callback server stopped unexpectedly.'),
            );
          }
        }
      }());

      final code = await codeCompleter.future;
      timeoutTimer.cancel();

      // Exchange code for access token.
      final tokenRes = await http.post(
        Uri.parse('https://api.dropboxapi.com/oauth2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'code': code,
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'redirect_uri': redirectUrl,
          'code_verifier': verifier,
        },
      );

      if (tokenRes.statusCode != 200) {
        throw Exception('Dropbox token exchange failed: ${tokenRes.body}');
      }

      final tokenData = jsonDecode(tokenRes.body) as Map<String, dynamic>;
      final accessToken = tokenData['access_token'] as String?;
      if (accessToken == null) {
        throw Exception('Dropbox response missing access_token');
      }

      _dropboxAccessToken = accessToken;

      // Fetch account email.
      final accountRes = await http.post(
        Uri.parse('https://api.dropboxapi.com/2/users/get_current_account'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: 'null',
      );

      String email = 'Connected';
      if (accountRes.statusCode == 200) {
        final data = jsonDecode(accountRes.body) as Map<String, dynamic>;
        email = (data['email'] as String?) ?? 'Connected';
      }

      final container = _container;
      if (container == null) return;
      container.read(backupDropboxAccountProvider.notifier).state = email;
      final storage = container.read(localStorageProvider);
      await _tokenStore!.write(_kBackupDropboxToken, accessToken);
      await storage.write(key: _kBackupDropboxAccount, value: email);

      // Default Dropbox backups folder if none selected yet.
      final existingFolder =
          container.read(backupDropboxFolderPathProvider) ?? '';
      if (existingFolder.isEmpty) {
        container.read(backupDropboxFolderPathProvider.notifier).state =
            _kDefaultDropboxFolderPath;
        container.read(backupDropboxFolderNameProvider.notifier).state =
            _kDefaultDropboxFolderPath;
        await storage.write(
          key: _kBackupDropboxFolderPath,
          value: _kDefaultDropboxFolderPath,
        );
        await storage.write(
          key: _kBackupDropboxFolderName,
          value: _kDefaultDropboxFolderPath,
        );
      }
      return;
    } on SocketException catch (e) {
      throw Exception(
        'Failed to start local callback server on $redirectUrl ($e). '
        'If a previous Dropbox connect is still in progress, wait a moment and try again.',
      );
    } finally {
      await server?.close(force: true);
    }
  }

  Future<void> disconnectDropbox() async {
    _dropboxAccessToken = null;
    final container = _container;
    if (container == null) {
      debugPrint('[Backup] disconnectDropbox called before init');
      return;
    }
    container.read(backupDropboxAccountProvider.notifier).state = null;
    container.read(backupDropboxFolderPathProvider.notifier).state = null;
    container.read(backupDropboxFolderNameProvider.notifier).state = null;
    final storage = container.read(localStorageProvider);
    await _tokenStore!.delete(_kBackupDropboxToken);
    await storage.write(key: _kBackupDropboxAccount, value: null);
    await storage.write(key: _kBackupDropboxFolderPath, value: null);
    await storage.write(key: _kBackupDropboxFolderName, value: null);
    if (container.read(backupDestinationProvider) ==
        BackupDestination.dropbox) {
      await setDestination(BackupDestination.localFolder);
    }
  }

  // ── OneDrive ──────────────────────────────────────────────────────────────

  /// Runs a PKCE OAuth2 authorization flow for OneDrive (Microsoft Graph).
  /// Requires ONEDRIVE_CLIENT_ID passed via --dart-define.
  Future<void> connectOneDrive() async {
    if (!isOneDriveConfigured) {
      throw Exception(
        'ONEDRIVE_CLIENT_ID not configured. '
        'Pass it via --dart-define=ONEDRIVE_CLIENT_ID=<your_client_id>',
      );
    }

    final result = await OneDriveService.instance.connect();

    _oneDriveAccessToken = result.accessToken;
    _oneDriveTokenExpiry = result.expiresAt;

    final email = result.email;
    final container = _container;
    if (container == null) return;
    container.read(backupOneDriveAccountProvider.notifier).state = email;
    final storage = container.read(localStorageProvider);
    await _tokenStore!.write(_kBackupOneDriveAccessToken, result.accessToken);
    await _tokenStore!.write(
      _kBackupOneDriveRefreshToken,
      result.refreshToken,
    );
    await storage.write(key: _kBackupOneDriveAccount, value: email);
    await _tokenStore!.write(
      _kBackupOneDriveTokenExpiry,
      result.expiresAt.toIso8601String(),
    );

    // Default OneDrive folder if none selected yet.
    final existingFolder = container.read(backupOneDriveFolderIdProvider) ?? '';
    if (existingFolder.isEmpty) {
      // Create or find the default LumenPass folder in root
      try {
        final folderId = await OneDriveService.instance
            .createFolder('root', _kDefaultOneDriveFolderName);
        container.read(backupOneDriveFolderIdProvider.notifier).state =
            folderId;
        container.read(backupOneDriveFolderNameProvider.notifier).state =
            _kDefaultOneDriveFolderName;
        await storage.write(
          key: _kBackupOneDriveFolderId,
          value: folderId,
        );
        await storage.write(
          key: _kBackupOneDriveFolderName,
          value: _kDefaultOneDriveFolderName,
        );
      } catch (e) {
        debugPrint('[Backup] Failed to create default OneDrive folder: $e');
      }
    }
  }

  Future<void> disconnectOneDrive() async {
    _oneDriveAccessToken = null;
    _oneDriveTokenExpiry = null;
    OneDriveService.instance.disconnect();
    final container = _container;
    if (container == null) {
      debugPrint('[Backup] disconnectOneDrive called before init');
      return;
    }
    container.read(backupOneDriveAccountProvider.notifier).state = null;
    container.read(backupOneDriveFolderIdProvider.notifier).state = null;
    container.read(backupOneDriveFolderNameProvider.notifier).state = null;
    final storage = container.read(localStorageProvider);
    await _tokenStore!.delete(_kBackupOneDriveAccessToken);
    await _tokenStore!.delete(_kBackupOneDriveRefreshToken);
    await storage.write(key: _kBackupOneDriveAccount, value: null);
    await _tokenStore!.delete(_kBackupOneDriveTokenExpiry);
    await storage.write(key: _kBackupOneDriveFolderId, value: null);
    await storage.write(key: _kBackupOneDriveFolderName, value: null);
    if (container.read(backupDestinationProvider) ==
        BackupDestination.oneDrive) {
      await setDestination(BackupDestination.localFolder);
    }
  }

  bool get isOneDriveConnected => OneDriveService.instance.isConnected;

  String? get currentOneDriveToken => _oneDriveAccessToken;

  String? get currentOneDriveEmail =>
      _container?.read(backupOneDriveAccountProvider);

  Future<void> setOneDriveFolder(String folderId, String name) async {
    final container = _container;
    if (container == null) return;
    container.read(backupOneDriveFolderIdProvider.notifier).state = folderId;
    container.read(backupOneDriveFolderNameProvider.notifier).state = name;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupOneDriveFolderId, value: folderId);
    await storage.write(key: _kBackupOneDriveFolderName, value: name);
  }

  /// Lists folders inside [parentId] on OneDrive.
  /// Pass null to list root-level folders.
  Future<List<CloudFolder>> listOneDriveFolders({String? parentId}) async {
    final folders = await OneDriveService.instance.listFolders(
      parentId: parentId,
    );
    return folders
        .map((f) => CloudFolder(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  /// Lists .kdbx files inside [parentId] on OneDrive.
  Future<List<CloudFile>> listOneDriveFiles({String? parentId}) async {
    final files = await OneDriveService.instance.listFiles(
      parentId: parentId,
      extension: '.kdbx',
    );
    return files
        .map((f) => CloudFile(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  /// Uploads [bytes] to an existing OneDrive item, overwriting its content.
  Future<void> uploadBytesToOneDrive(
    Uint8List bytes,
    String itemId,
    String fileName,
  ) async {
    await OneDriveService.instance.uploadBytes(bytes, itemId, fileName);
  }

  /// Downloads the content of a OneDrive item by its ID.
  Future<Uint8List> downloadOneDriveFile(String itemId) async {
    return OneDriveService.instance.downloadFile(itemId);
  }

  /// Returns the last-modified time of a OneDrive item.
  Future<DateTime?> getOneDriveFileModifiedTime(String itemId) async {
    return OneDriveService.instance.getFileModifiedTime(itemId);
  }

  /// Uploads a new file into a OneDrive folder, returning the new item ID.
  Future<String> uploadNewFileToOneDrive(
    Uint8List bytes,
    String folderId,
    String fileName,
  ) async {
    return OneDriveService.instance.uploadNewFile(bytes, folderId, fileName);
  }

  /// Creates a folder on OneDrive inside [parentId]. Returns a [CloudFolder].
  Future<CloudFolder> createOneDriveFolder(
    String name, {
    String? parentId,
  }) async {
    final folderId =
        await OneDriveService.instance.createFolder(parentId ?? 'root', name);
    return CloudFolder(id: folderId, name: name);
  }

  // ── WebDAV ───────────────────────────────────────────────────────────────────

  /// Validates [config], verifies the server/credentials/root-path are usable,
  /// and persists the configuration (password stored in the secret store).
  ///
  /// Throws on validation or connectivity failure so the UI can surface it.
  Future<void> connectWebDav(WebDavConfig config) async {
    await WebDavService.instance.connect(config);
    _webDavConfig = WebDavService.instance.config;

    final container = _container;
    if (container == null) return;
    final stored = _webDavConfig!;
    final account = stored.accountLabel;
    container.read(backupWebDavAccountProvider.notifier).state = account;

    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupWebDavHost, value: stored.host);
    await storage.write(key: _kBackupWebDavPort, value: stored.port.toString());
    await storage.write(key: _kBackupWebDavUsername, value: stored.username);
    await _tokenStore!.write(_kBackupWebDavPassword, stored.password);
    await storage.write(key: _kBackupWebDavRootPath, value: stored.rootPath);
    await storage.write(key: _kBackupWebDavAccount, value: account);

    // Default the backup folder to the configured root if none chosen yet.
    final existingFolder = container.read(backupWebDavFolderPathProvider) ?? '';
    if (existingFolder.isEmpty) {
      container.read(backupWebDavFolderPathProvider.notifier).state =
          stored.rootPath;
      container.read(backupWebDavFolderNameProvider.notifier).state =
          stored.rootPath;
      await storage.write(
          key: _kBackupWebDavFolderPath, value: stored.rootPath);
      await storage.write(
          key: _kBackupWebDavFolderName, value: stored.rootPath);
    }
  }

  /// Verifies a candidate [config] without persisting it — used by the
  /// settings form's "Test connection" button.
  Future<void> testWebDavConnection(WebDavConfig config) async {
    await WebDavService.instance.testConnection(config);
  }

  /// Confirms the chosen path is a usable read/write destination by writing,
  /// reading back and deleting a small probe file. Throws when it is not.
  Future<void> verifyWebDavWritable(WebDavConfig config) async {
    await WebDavService.instance.verifyWritable(config);
  }

  Future<void> disconnectWebDav() async {
    _webDavConfig = null;
    WebDavService.instance.disconnect();
    final container = _container;
    if (container == null) {
      debugPrint('[Backup] disconnectWebDav called before init');
      return;
    }
    container.read(backupWebDavAccountProvider.notifier).state = null;
    container.read(backupWebDavFolderPathProvider.notifier).state = null;
    container.read(backupWebDavFolderNameProvider.notifier).state = null;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupWebDavHost, value: null);
    await storage.write(key: _kBackupWebDavPort, value: null);
    await storage.write(key: _kBackupWebDavUsername, value: null);
    await _tokenStore!.delete(_kBackupWebDavPassword);
    await storage.write(key: _kBackupWebDavRootPath, value: null);
    await storage.write(key: _kBackupWebDavAccount, value: null);
    await storage.write(key: _kBackupWebDavFolderPath, value: null);
    await storage.write(key: _kBackupWebDavFolderName, value: null);
    if (container.read(backupDestinationProvider) == BackupDestination.webdav) {
      await setDestination(BackupDestination.localFolder);
    }
  }

  bool get isWebDavConnected => WebDavService.instance.isConnected;

  WebDavConfig? get currentWebDavConfig => _webDavConfig;

  String? get currentWebDavAccount =>
      _container?.read(backupWebDavAccountProvider);

  Future<void> setWebDavFolder(String folderPath, String name) async {
    final container = _container;
    if (container == null) return;
    container.read(backupWebDavFolderPathProvider.notifier).state = folderPath;
    container.read(backupWebDavFolderNameProvider.notifier).state = name;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupWebDavFolderPath, value: folderPath);
    await storage.write(key: _kBackupWebDavFolderName, value: name);
  }

  /// Lists folders inside [parentId] on WebDAV (null → configured root).
  Future<List<CloudFolder>> listWebDavFolders({String? parentId}) async {
    final folders =
        await WebDavService.instance.listFolders(parentPath: parentId);
    return folders
        .map((f) => CloudFolder(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  /// Lists .kdbx files inside [parentId] on WebDAV.
  Future<List<CloudFile>> listWebDavFiles({String? parentId}) async {
    final files = await WebDavService.instance.listFiles(
      parentPath: parentId,
      extension: '.kdbx',
    );
    return files
        .map((f) => CloudFile(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  /// Uploads [bytes] to an existing WebDAV resource, overwriting its content.
  Future<void> uploadBytesToWebDav(Uint8List bytes, String remotePath) async {
    await WebDavService.instance.uploadBytes(bytes, remotePath);
  }

  /// Downloads the content of a WebDAV resource by its server-relative path.
  Future<Uint8List> downloadWebDavFile(String remotePath) async {
    return WebDavService.instance.downloadFile(remotePath);
  }

  /// Returns the last-modified time of a WebDAV resource.
  Future<DateTime?> getWebDavFileModifiedTime(String remotePath) async {
    return WebDavService.instance.getFileModifiedTime(remotePath);
  }

  /// Uploads a new file into a WebDAV folder, returning its server-relative
  /// path (used as the cloudFileId).
  Future<String> uploadNewFileToWebDav(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    return WebDavService.instance.uploadNewFile(bytes, folderPath, fileName);
  }

  /// Creates a folder on WebDAV inside [parentId]. Returns a [CloudFolder].
  Future<CloudFolder> createWebDavFolder(
    String name, {
    String? parentId,
  }) async {
    final folder = await WebDavService.instance.createFolder(
      name,
      parentPath: parentId,
    );
    return CloudFolder(id: folder.id, name: folder.name, path: folder.path);
  }

  /// Lists folders under [parentId] (server root when null) using an explicit,
  /// possibly-unsaved [config] — powers the GUI root-path picker after "Test".
  Future<List<CloudFolder>> browseWebDavFolders(
    WebDavConfig config, {
    String? parentId,
  }) async {
    final folders = await WebDavService.instance.browseFolders(
      config,
      parentPath: parentId,
    );
    return folders
        .map((f) => CloudFolder(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  /// Creates a folder under [parentId] using an explicit, possibly-unsaved
  /// [config]. Returns the created [CloudFolder].
  Future<CloudFolder> createWebDavFolderIn(
    WebDavConfig config,
    String name, {
    String? parentId,
  }) async {
    final folder = await WebDavService.instance.createFolderIn(
      config,
      name,
      parentPath: parentId,
    );
    return CloudFolder(id: folder.id, name: folder.name, path: folder.path);
  }

  // ── SFTP ───────────────────────────────────────────────────────────────────

  Future<void> connectSftp(SftpConfig config) async {
    await SftpService.instance.connect(config);
    _sftpConfig = SftpService.instance.config;

    final container = _container;
    if (container == null) return;
    final stored = _sftpConfig!;
    final account = stored.accountLabel;
    container.read(backupSftpAccountProvider.notifier).state = account;

    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupSftpHost, value: stored.host);
    await storage.write(key: _kBackupSftpPort, value: stored.port.toString());
    await storage.write(key: _kBackupSftpUsername, value: stored.username);
    await storage.write(
        key: _kBackupSftpAuthMethod, value: stored.authMethod.name);
    await _tokenStore!.write(_kBackupSftpPassword, stored.password);
    await storage.write(
        key: _kBackupSftpKeyFilePath, value: stored.keyFilePath);
    await storage.write(
      key: _kBackupSftpKeyFileBookmark,
      value: stored.keyFileBookmark,
    );
    await storage.write(
      key: _kBackupSftpTransferMode,
      value: stored.transferMode.name,
    );
    await storage.write(key: _kBackupSftpRootPath, value: stored.rootPath);
    await storage.write(key: _kBackupSftpAccount, value: account);

    final existingFolder = container.read(backupSftpFolderPathProvider) ?? '';
    if (existingFolder.isEmpty) {
      container.read(backupSftpFolderPathProvider.notifier).state =
          stored.rootPath;
      container.read(backupSftpFolderNameProvider.notifier).state =
          stored.rootPath;
      await storage.write(key: _kBackupSftpFolderPath, value: stored.rootPath);
      await storage.write(key: _kBackupSftpFolderName, value: stored.rootPath);
    }
  }

  Future<void> testSftpConnection(SftpConfig config) async {
    await SftpService.instance.testConnection(config);
  }

  Future<void> verifySftpWritable(SftpConfig config) async {
    await SftpService.instance.verifyWritable(config);
  }

  Future<void> disconnectSftp() async {
    _sftpConfig = null;
    await SftpService.instance.disconnect();
    final container = _container;
    if (container == null) {
      debugPrint('[Backup] disconnectSftp called before init');
      return;
    }
    container.read(backupSftpAccountProvider.notifier).state = null;
    container.read(backupSftpFolderPathProvider.notifier).state = null;
    container.read(backupSftpFolderNameProvider.notifier).state = null;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupSftpHost, value: null);
    await storage.write(key: _kBackupSftpPort, value: null);
    await storage.write(key: _kBackupSftpUsername, value: null);
    await storage.write(key: _kBackupSftpAuthMethod, value: null);
    await _tokenStore!.delete(_kBackupSftpPassword);
    await storage.write(key: _kBackupSftpKeyFilePath, value: null);
    await storage.write(key: _kBackupSftpKeyFileBookmark, value: null);
    await storage.write(key: _kBackupSftpTransferMode, value: null);
    await storage.write(key: _kBackupSftpRootPath, value: null);
    await storage.write(key: _kBackupSftpAccount, value: null);
    await storage.write(key: _kBackupSftpFolderPath, value: null);
    await storage.write(key: _kBackupSftpFolderName, value: null);
    if (container.read(backupDestinationProvider) == BackupDestination.sftp) {
      await setDestination(BackupDestination.localFolder);
    }
  }

  bool get isSftpConnected => SftpService.instance.isConnected;

  // ── S3 ──────────────────────────────────────────────────────────────────────

  bool get isS3Connected => S3Service.instance.isConfigured;

  S3Config? get currentS3Config {
    if (!S3Service.instance.isConfigured) return null;
    return S3Config(
      accessKey: '',
      secretKey: '',
      region: S3Service.instance.currentRegion ?? 'us-east-1',
      bucketId: S3Service.instance.currentBucketId ?? '',
      rootPath: S3Service.instance.currentRootPath ?? '',
    );
  }

  String? get currentS3Account => _container?.read(backupS3AccountProvider);

  Future<void> connectS3(S3Config config) async {
    final container = _container;
    if (container == null) return;
    S3Service.instance.configure(config);
    final storage = container.read(localStorageProvider);
    final account =
        's3://${config.bucketId}${config.rootPath.isNotEmpty ? '/${config.rootPath}' : ''}';
    await storage.write(key: _kBackupS3Account, value: account);
    // Persist the actual S3 credentials so they survive app restarts.
    await _tokenStore!.write(_kBackupS3AccessKey, config.accessKey);
    await _tokenStore!.write(_kBackupS3SecretKey, config.secretKey);
    await storage.write(key: _kBackupS3Region, value: config.region);
    await storage.write(key: _kBackupS3Bucket, value: config.bucketId);
    await storage.write(key: _kBackupS3RootPath, value: config.rootPath);
    if (config.host != null) {
      await storage.write(key: _kBackupS3Host, value: config.host);
    }
    if (config.sessionToken != null) {
      await _tokenStore!.write(
        _kBackupS3SessionToken,
        config.sessionToken,
      );
    }
    container.read(backupS3AccountProvider.notifier).state = account;

    final existingFolder = container.read(backupS3FolderPathProvider) ?? '';
    if (existingFolder.isNotEmpty) {
      container.read(backupS3FolderPathProvider.notifier).state =
          config.rootPath;
      container.read(backupS3FolderNameProvider.notifier).state =
          config.rootPath.split('/').where((s) => s.isNotEmpty).lastOrNull ??
              config.rootPath;
    }
  }

  Future<void> setS3Folder(String folderPath, String name) async {
    final container = _container;
    if (container == null) return;
    container.read(backupS3FolderPathProvider.notifier).state = folderPath;
    container.read(backupS3FolderNameProvider.notifier).state = name;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupS3FolderPath, value: folderPath);
    await storage.write(key: _kBackupS3FolderName, value: name);
  }

  Future<void> disconnectS3() async {
    final container = _container;
    if (container == null) return;
    S3Service.instance.dispose();
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupS3Account, value: null);
    await _tokenStore!.delete(_kBackupS3AccessKey);
    await _tokenStore!.delete(_kBackupS3SecretKey);
    await storage.write(key: _kBackupS3Region, value: null);
    await storage.write(key: _kBackupS3Bucket, value: null);
    await storage.write(key: _kBackupS3RootPath, value: null);
    await storage.write(key: _kBackupS3Host, value: null);
    await _tokenStore!.delete(_kBackupS3SessionToken);
    await storage.write(key: _kBackupS3FolderPath, value: null);
    await storage.write(key: _kBackupS3FolderName, value: null);
    container.read(backupS3AccountProvider.notifier).state = null;
    container.read(backupS3FolderPathProvider.notifier).state = null;
    container.read(backupS3FolderNameProvider.notifier).state = null;
    if (container.read(backupDestinationProvider) == BackupDestination.s3) {
      await setDestination(BackupDestination.localFolder);
    }
  }

  Future<Uint8List> downloadS3File(String objectKey) async {
    return S3Service.instance.downloadObject(objectKey);
  }

  Future<List<CloudFolder>> listS3Folders({String prefix = ''}) async {
    final prefixes = await S3Service.instance.listPrefixes(prefix: prefix);
    return prefixes
        .map((p) => CloudFolder(
              id: p,
              name: p.replaceFirst(RegExp('^$prefix'), '').replaceAll('/', ''),
            ))
        .toList();
  }

  Future<List<CloudFile>> listS3Files({String prefix = ''}) async {
    final result = await S3Service.instance.listObjects(prefix: prefix);
    return result.objects
        .where((obj) {
          final key = obj.key;
          final ext = key.toLowerCase();
          return !key.endsWith('/') &&
              (ext.endsWith('.kdbx') || ext.endsWith('.kdb'));
        })
        .map((obj) => CloudFile(
              id: obj.key,
              name: obj.key.split('/').last,
              path: obj.key,
            ))
        .toList();
  }

  Future<String?> uploadNewFileToS3(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    final normalizedPath = folderPath.endsWith('/') || folderPath.isEmpty
        ? folderPath
        : '$folderPath/';
    final key = '$normalizedPath$fileName';
    await S3Service.instance.uploadObject(key, bytes);
    return key;
  }

  /// Uploads bytes to an existing S3 object at [key] (overwrites in place).
  /// Used by [CloudSyncService] to push local changes to a cloud-backed vault.
  Future<void> uploadBytesToS3(Uint8List bytes, String key) async {
    await S3Service.instance.uploadObject(key, bytes);
  }

  /// Returns the last-modified time of the S3 object at [key], or `null` if
  /// the object does not exist or cannot be queried.
  Future<DateTime?> getS3FileModifiedTime(String key) async {
    return S3Service.instance.getObjectLastModified(key);
  }

  SftpConfig? get currentSftpConfig => _sftpConfig;

  String? get currentSftpAccount => _container?.read(backupSftpAccountProvider);

  Future<void> setSftpFolder(String folderPath, String name) async {
    final container = _container;
    if (container == null) return;
    container.read(backupSftpFolderPathProvider.notifier).state = folderPath;
    container.read(backupSftpFolderNameProvider.notifier).state = name;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupSftpFolderPath, value: folderPath);
    await storage.write(key: _kBackupSftpFolderName, value: name);
  }

  Future<List<CloudFolder>> listSftpFolders({String? parentId}) async {
    final folders =
        await SftpService.instance.listFolders(parentPath: parentId);
    return folders
        .map((f) => CloudFolder(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  Future<List<CloudFile>> listSftpFiles({String? parentId}) async {
    final files = await SftpService.instance.listFiles(
      parentPath: parentId,
      extension: '.kdbx',
    );
    return files
        .map((f) => CloudFile(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  Future<void> uploadBytesToSftp(Uint8List bytes, String remotePath) async {
    await SftpService.instance.uploadBytes(bytes, remotePath);
  }

  Future<Uint8List> downloadSftpFile(String remotePath) async {
    return SftpService.instance.downloadFile(remotePath);
  }

  Future<DateTime?> getSftpFileModifiedTime(String remotePath) async {
    return SftpService.instance.getFileModifiedTime(remotePath);
  }

  Future<String> uploadNewFileToSftp(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    return SftpService.instance.uploadNewFile(bytes, folderPath, fileName);
  }

  Future<CloudFolder> createSftpFolder(
    String name, {
    String? parentId,
  }) async {
    final folder = await SftpService.instance.createFolder(
      name,
      parentPath: parentId,
    );
    return CloudFolder(id: folder.id, name: folder.name, path: folder.path);
  }

  Future<List<CloudFolder>> browseSftpFolders(
    SftpConfig config, {
    String? parentId,
  }) async {
    final folders = await SftpService.instance.browseFolders(
      config,
      parentPath: parentId,
    );
    return folders
        .map((f) => CloudFolder(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  Future<CloudFolder> createSftpFolderIn(
    SftpConfig config,
    String name, {
    String? parentId,
  }) async {
    final folder = await SftpService.instance.createFolderIn(
      config,
      name,
      parentPath: parentId,
    );
    return CloudFolder(id: folder.id, name: folder.name, path: folder.path);
  }

  // ── Public: cloud folder browsing & file upload ────────────────────────────

  GoogleCredentials? get currentGoogleAccount => _googleAuth.currentUser;

  bool get isGoogleConnected => _googleAuth.isConnected;

  String? get currentGoogleEmail => _googleAuth.currentEmail;

  Future<Map<String, String>> _requireGoogleAuthHeaders() async {
    var creds = _googleAuth.currentUser;
    creds ??= await _googleAuth.signInSilently();
    if (creds == null) throw Exception('Not signed in to Google Drive');
    return creds.authHeaders;
  }

  Future<drive.DriveApi> _buildDriveApi() async {
    final headers = await _requireGoogleAuthHeaders();
    return drive.DriveApi(_GoogleAuthClient(headers));
  }

  String? get currentDropboxToken => _dropboxAccessToken;

  /// Lists folders inside [parentId] on Google Drive.
  /// Pass null to list root-level folders.
  Future<List<CloudFolder>> listGoogleDriveFolders({String? parentId}) async {
    final driveApi = await _buildDriveApi();

    final q = parentId != null
        ? "'$parentId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
        : "mimeType='application/vnd.google-apps.folder' and 'root' in parents and trashed=false";

    final result = await driveApi.files.list(
      q: q,
      orderBy: 'name',
      spaces: 'drive',
    );

    return (result.files ?? <drive.File>[])
        .where((f) => f.id != null && f.name != null)
        .map((f) => CloudFolder(id: f.id!, name: f.name!))
        .toList();
  }

  /// Creates a folder named [name] on Google Drive inside [parentId] (or root).
  Future<CloudFolder> createGoogleDriveFolder(String name,
      {String? parentId}) async {
    final driveApi = await _buildDriveApi();

    final meta = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    if (parentId != null) meta.parents = [parentId];

    final created = await driveApi.files.create(meta);
    return CloudFolder(id: created.id!, name: created.name ?? name);
  }

  /// Uploads [bytes] as [fileName] into Google Drive folder [folderId] (root if null).
  /// Returns the created file's Drive ID.
  Future<String> uploadBytesToGoogleDrive(
    Uint8List bytes,
    String fileName, {
    String? folderId,
  }) async {
    final driveApi = await _buildDriveApi();

    final meta = drive.File()..name = fileName;
    if (folderId != null) meta.parents = [folderId];

    final result = await driveApi.files.create(
      meta,
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
    );
    return result.id ?? '';
  }

  /// Updates (overwrites) an existing Google Drive file identified by [fileId].
  ///
  /// Automatically escalates to the full `drive` scope once if Google returns
  /// a "user has not granted write access" 403 — which happens on files the
  /// app didn't originally create and hasn't been given picker-level access
  /// to. The operation is retried once after the user accepts the consent
  /// prompt; if they decline, the original error is rethrown with an
  /// actionable hint.
  Future<void> updateGoogleDriveFile(
    String fileId,
    Uint8List bytes,
    String fileName,
  ) async {
    final sw = Stopwatch()..start();

    Future<void> doUpdate() async {
      final driveApi = await _buildDriveApi();
      final meta = drive.File()..name = fileName;
      await driveApi.files.update(
        meta,
        fileId,
        uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
      );
    }

    debugPrint(
      '[BackupService] PUT Google Drive file="$fileName" '
      'size=${bytes.length}B (auth=${sw.elapsedMilliseconds}ms)',
    );

    try {
      await doUpdate();
      debugPrint(
        '[BackupService] ✓ Google Drive file="$fileName" uploaded in '
        '${sw.elapsedMilliseconds}ms',
      );
    } catch (e) {
      if (!_isDriveWritePermissionError(e)) {
        debugPrint(
          '[BackupService] ✗ Google Drive update failed after '
          '${sw.elapsedMilliseconds}ms: $e',
        );
        rethrow;
      }

      debugPrint(
        '[BackupService] Google Drive 403 — write access denied '
        '(file="$fileName")',
      );

      // The loopback OAuth flow always requests the full `drive` scope at
      // sign-in, so there is no incremental scope grant we can attempt here.
      // Surface a clear "please reconnect" message instead.
      throw Exception(
        'Google Drive write access denied. Please reconnect Google Drive. '
        'Underlying error: $e',
      );
    }
  }

  /// Lists files inside [parentId] on Google Drive.
  /// Pass null to list files in the drive root.
  Future<List<CloudFile>> listGoogleDriveFiles({String? parentId}) async {
    final driveApi = await _buildDriveApi();

    final q = parentId != null
        ? "'$parentId' in parents and mimeType!='application/vnd.google-apps.folder' and trashed=false"
        : "mimeType!='application/vnd.google-apps.folder' and 'root' in parents and trashed=false";

    final result = await driveApi.files.list(
      q: q,
      orderBy: 'name',
      spaces: 'drive',
    );

    return (result.files ?? <drive.File>[])
        .where((f) => f.id != null && f.name != null)
        .map((f) => CloudFile(id: f.id!, name: f.name!))
        .toList();
  }

  /// Local cache files opened from Drive use `Name_<12 hex>.kdbx`; the remote
  /// file is usually `Name.kdbx`.
  static String? stripGoogleDriveCacheHashFromLocalName(String filename) {
    final re = RegExp(r'^(.+)_([a-f0-9]{12})(\.[^.]+)$');
    final m = re.firstMatch(filename);
    if (m == null) return null;
    return '${m.group(1)}${m.group(3)}';
  }

  /// When [DatabaseRecord.cloudFileId] is missing, search Drive by filename
  /// (configured backup folder first, then global exact name) and return the
  /// file id and name to persist on the registry.
  Future<({String id, String name})?> resolveMissingGoogleDriveFileMetadata({
    required String databasePath,
    String? cloudFileName,
  }) async {
    final base = p.basename(databasePath);
    final candidates = <String>[];
    if (cloudFileName != null && cloudFileName.trim().isNotEmpty) {
      candidates.add(cloudFileName.trim());
    }
    final stripped = stripGoogleDriveCacheHashFromLocalName(base);
    if (stripped != null && !candidates.contains(stripped)) {
      candidates.add(stripped);
    }
    if (!candidates.contains(base)) {
      candidates.add(base);
    }
    for (final name in candidates) {
      final meta = await _findGoogleDriveFileMetadataByCandidateName(name);
      if (meta != null) return meta;
    }
    return null;
  }

  Future<({String id, String name})?>
      _findGoogleDriveFileMetadataByCandidateName(
    String fileName,
  ) async {
    final folderId = _container?.read(backupGoogleFolderIdProvider);
    if (folderId != null && folderId.isNotEmpty) {
      try {
        final files = await listGoogleDriveFiles(parentId: folderId);
        final lower = fileName.toLowerCase();
        for (final f in files) {
          if (f.name.toLowerCase() == lower) {
            return (id: f.id, name: f.name);
          }
        }
      } catch (e) {
        debugPrint(
          '[BackupService] listGoogleDriveFiles(folder) for repair: $e',
        );
      }
    }
    return _searchGoogleDriveFileMetadataByExactName(fileName);
  }

  Future<({String id, String name})?> _searchGoogleDriveFileMetadataByExactName(
    String fileName,
  ) async {
    final driveApi = await _buildDriveApi();

    final escaped = fileName.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final q = "name = '$escaped' and trashed = false";

    drive.FileList result;
    try {
      result = await driveApi.files.list(
        q: q,
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        $fields: 'files(id,name,parents)',
      );
    } catch (e) {
      debugPrint('[BackupService] Drive name search failed: $e');
      return null;
    }

    final files = result.files ?? <drive.File>[];
    if (files.isEmpty) return null;

    final pref = _container?.read(backupGoogleFolderIdProvider);
    if (pref != null && pref.isNotEmpty && files.length > 1) {
      for (final f in files) {
        final id = f.id;
        final name = f.name;
        if (id == null || name == null) continue;
        if (f.parents?.contains(pref) == true) {
          return (id: id, name: name);
        }
      }
    }

    final first = files.first;
    if (first.id != null && first.name != null) {
      return (id: first.id!, name: first.name!);
    }
    return null;
  }

  /// Returns the `modifiedTime` metadata of a Google Drive file, or null if
  /// the field is missing. Used by the cloud-sync service to decide whether
  /// the remote copy is newer than the local cache.
  Future<DateTime?> getGoogleDriveFileModifiedTime(String fileId) async {
    final driveApi = await _buildDriveApi();

    final meta = await driveApi.files.get(
      fileId,
      $fields: 'modifiedTime,name,size',
    ) as drive.File;
    return meta.modifiedTime;
  }

  /// Downloads the full contents of a Google Drive file.
  Future<Uint8List> downloadGoogleDriveFile(String fileId) async {
    final driveApi = await _buildDriveApi();

    final response = await driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (response is! drive.Media) {
      throw Exception('Could not download the selected Google Drive file.');
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// Lists sub-folders at [path] in Dropbox (use '' or '/' for root).
  Future<List<CloudFolder>> listDropboxFolders(String path) async {
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not connected to Dropbox');
    }

    final normalised = path == '/' ? '' : path;
    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'path': normalised, 'recursive': false}),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Dropbox list_folder failed (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = data['entries'] as List<dynamic>;
    return entries
        .where((e) => (e as Map<String, dynamic>)['.tag'] == 'folder')
        .map((e) {
      final m = e as Map<String, dynamic>;
      return CloudFolder(
        id: m['path_lower'] as String,
        name: m['name'] as String,
      );
    }).toList();
  }

  /// Lists files at [path] in Dropbox (use '' or '/' for root).
  Future<List<CloudFile>> listDropboxFiles(String path) async {
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not connected to Dropbox');
    }

    final normalised = path == '/' ? '' : path;
    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'path': normalised, 'recursive': false}),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Dropbox list_folder failed (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = data['entries'] as List<dynamic>;
    return entries
        .where((e) => (e as Map<String, dynamic>)['.tag'] == 'file')
        .map((e) {
      final m = e as Map<String, dynamic>;
      return CloudFile(
        id: m['path_lower'] as String,
        name: m['name'] as String,
        path: (m['path_display'] as String?) ?? (m['path_lower'] as String?),
      );
    }).toList();
  }

  /// Creates a folder at [dropboxPath] (e.g. '/LumenPass').
  Future<void> createDropboxFolder(String dropboxPath) async {
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not connected to Dropbox');
    }

    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/create_folder_v2'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'path': dropboxPath, 'autorename': false}),
    );

    if (response.statusCode != 200 && response.statusCode != 409) {
      throw Exception(
          'Dropbox create_folder failed (${response.statusCode}): ${response.body}');
    }
  }

  /// Uploads [bytes] to [dropboxPath] (e.g. '/LumenPass/vault.kdbx').
  Future<void> uploadBytesToDropbox(Uint8List bytes, String dropboxPath) async {
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not connected to Dropbox');
    }

    debugPrint(
      '[BackupService] PUT Dropbox path=$dropboxPath size=${bytes.length}B',
    );
    final sw = Stopwatch()..start();
    final response = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': jsonEncode({
          'path': dropboxPath,
          'mode': 'overwrite',
          'autorename': true,
          'mute': false,
        }),
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      debugPrint(
        '[BackupService] ✗ Dropbox upload failed (${response.statusCode}) '
        'in ${sw.elapsedMilliseconds}ms: ${response.body}',
      );
      throw Exception(
          'Dropbox upload failed (${response.statusCode}): ${response.body}');
    }
    debugPrint(
      '[BackupService] ✓ Dropbox uploaded path=$dropboxPath in '
      '${sw.elapsedMilliseconds}ms',
    );
  }

  /// Returns the `server_modified` timestamp for a Dropbox file, or null
  /// when Dropbox doesn't return one. Used by the cloud-sync service to
  /// compare against the local cache before overwriting.
  Future<DateTime?> getDropboxFileModifiedTime(String dropboxPath) async {
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not connected to Dropbox');
    }

    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/get_metadata'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'path': dropboxPath,
        'include_media_info': false,
        'include_deleted': false,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Dropbox get_metadata failed (${response.statusCode}): ${response.body}');
    }

    final meta = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = meta['server_modified'] as String?;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Downloads the full contents of a Dropbox file.
  Future<Uint8List> downloadDropboxFile(String dropboxPath) async {
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not connected to Dropbox');
    }

    final response = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/download'),
      headers: {
        'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': jsonEncode({'path': dropboxPath}),
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Dropbox download failed (${response.statusCode}): ${response.body}');
    }

    return response.bodyBytes;
  }

  // ── Private: backup implementations ───────────────────────────────────────

  Future<void> _backupToLocalFolder(
    String sourcePath,
    String fileName, {
    required String vaultLabel,
  }) async {
    final container = _container;
    if (container == null) return;

    final localPath = container.read(backupLocalPathProvider);
    if (localPath != null) {
      final bookmark = await container
          .read(localStorageProvider)
          .read(key: _kBackupLocalBookmark);
      if (bookmark != null) {
        await BookmarkService.instance.resolveAndStartAccessing(bookmark);
      }
    }

    final destDir = await _localBackupRootDirectory();

    // Group backups by vault label to avoid mixing vaults.
    final vaultDir = p.join(destDir, vaultLabel);
    await Directory(vaultDir).create(recursive: true);
    final destPath = p.join(vaultDir, fileName);
    await File(sourcePath).copy(destPath);
    debugPrint('[Backup] saved to $destPath');
  }

  /// Deletes local backup copies for [vaultPath] that are older than the
  /// configured retention window ([backupRetentionDaysProvider]).
  ///
  /// Age is taken from the timestamp encoded in each backup's file name (see
  /// [runBackup]), which is immutable and reflects when the snapshot was
  /// actually taken. When a name can't be parsed we fall back to the file's
  /// stat time from [listLocalBackups]. Comparison uses [_clock] so tests can
  /// pin "now". A retention value below 1 day is treated as 1 to avoid wiping
  /// the backup that was just written.
  Future<void> _pruneOldBackups(String vaultPath) async {
    final container = _container;
    if (container == null) return;

    final retentionDays = container.read(backupRetentionDaysProvider);
    final effectiveDays = retentionDays < 1 ? 1 : retentionDays;
    final cutoff = _clock().subtract(Duration(days: effectiveDays));

    final backups = await listLocalBackups(vaultPath: vaultPath);
    for (final backup in backups) {
      final stamp = _parseBackupTimestampFromFileName(backup.fileName) ??
          backup.createdAt;
      if (stamp.isBefore(cutoff)) {
        try {
          final file = File(backup.path);
          if (await file.exists()) {
            await file.delete();
            debugPrint('[Backup] pruned expired backup ${backup.fileName}');
          }
        } catch (e) {
          debugPrint('[Backup] failed to delete ${backup.fileName}: $e');
        }
      }
    }
  }

  /// Recovers the [DateTime] embedded in a backup file name produced by
  /// [runBackup] (`<label>_backup_<iso-with-punctuation-dashed>.kdbx`).
  ///
  /// [runBackup] builds the stamp as
  /// `timestamp.toIso8601String().replaceAll(':', '-').replaceAll('.', '-')`,
  /// so the time portion after the `T` always has four `-`-separated groups
  /// (H, M, S, and milli/microseconds). Returns null when the name doesn't
  /// match, letting the caller fall back to the file's stat time.
  static DateTime? _parseBackupTimestampFromFileName(String fileName) {
    const marker = '_backup_';
    final markerIndex = fileName.lastIndexOf(marker);
    if (markerIndex < 0) return null;

    var stamp = fileName.substring(markerIndex + marker.length);
    if (stamp.endsWith('.kdbx')) {
      stamp = stamp.substring(0, stamp.length - '.kdbx'.length);
    }

    final tIndex = stamp.indexOf('T');
    if (tIndex < 0) return null;
    final datePart = stamp.substring(0, tIndex);
    final timeGroups = stamp.substring(tIndex + 1).split('-');
    if (timeGroups.length < 3) return null;

    final hh = timeGroups[0];
    final mm = timeGroups[1];
    final ss = timeGroups[2];
    final frac = timeGroups.length > 3 ? '.${timeGroups[3]}' : '';
    return DateTime.tryParse('${datePart}T$hh:$mm:$ss$frac');
  }

  Future<void> _backupToGoogleDrive(String sourcePath, String fileName) async {
    final driveApi = await _buildDriveApi();

    final folderId = _container?.read(backupGoogleFolderIdProvider);
    final bytes = await File(sourcePath).readAsBytes();
    final meta = drive.File()..name = fileName;
    if (folderId != null && folderId.isNotEmpty) meta.parents = [folderId];
    await driveApi.files.create(
      meta,
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
    );
    debugPrint('[Backup] uploaded to Google Drive: $fileName');
  }

  Future<void> _backupToDropbox(
    String sourcePath,
    String fileName, {
    required String vaultLabel,
  }) async {
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not connected to Dropbox');
    }

    final rawFolder = _container?.read(backupDropboxFolderPathProvider) ?? '';
    final normalisedFolder = (rawFolder.isEmpty || rawFolder == '/')
        ? _kDefaultDropboxFolderPath
        : rawFolder;
    final uploadRootDir = normalisedFolder == '/' ? '' : normalisedFolder;
    final uploadDir = uploadRootDir.isEmpty ? '' : '$uploadRootDir/$vaultLabel';

    // Ensure folder exists (safe if it already exists).
    if (uploadDir.isNotEmpty) {
      await createDropboxFolder(uploadDir);
    }

    final uploadPath =
        uploadDir.isEmpty ? '/$fileName' : '$uploadDir/$fileName';
    final bytes = await File(sourcePath).readAsBytes();
    final response = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/upload'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': jsonEncode({
          'path': uploadPath,
          'mode': 'add',
          'autorename': true,
          'mute': false,
        }),
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Dropbox upload failed (${response.statusCode}): ${response.body}',
      );
    }
    debugPrint('[Backup] uploaded to Dropbox: $fileName');
  }

  Future<void> _backupToOneDrive(
    String sourcePath,
    String fileName, {
    required String vaultLabel,
  }) async {
    if (!OneDriveService.instance.isConnected) {
      throw Exception('Not connected to OneDrive');
    }

    final rawFolderId = _container?.read(backupOneDriveFolderIdProvider) ?? '';
    if (rawFolderId.isEmpty) {
      throw Exception('No OneDrive backup folder configured');
    }

    // Ensure a sub-folder for this vault exists.
    String uploadFolderId;
    try {
      uploadFolderId =
          await OneDriveService.instance.createFolder(rawFolderId, vaultLabel);
    } catch (_) {
      // Folder may already exist — list children and find it.
      final folders = await OneDriveService.instance.listFolders(
        parentId: rawFolderId,
      );
      final match = folders.where((f) => f.name == vaultLabel).toList();
      if (match.isNotEmpty) {
        uploadFolderId = match.first.id;
      } else {
        rethrow;
      }
    }

    final bytes = await File(sourcePath).readAsBytes();
    await OneDriveService.instance
        .uploadNewFile(bytes, uploadFolderId, fileName);
  }

  Future<void> _backupToWebDav(
    String sourcePath,
    String fileName, {
    required String vaultLabel,
  }) async {
    if (!WebDavService.instance.isConnected) {
      throw Exception('Not connected to WebDAV');
    }

    final rawFolder = _container?.read(backupWebDavFolderPathProvider) ??
        _webDavConfig?.rootPath ??
        '';
    if (rawFolder.isEmpty) {
      throw Exception('No WebDAV backup folder configured');
    }

    // Ensure a sub-folder for this vault exists, then upload the file.
    final vaultFolder = await WebDavService.instance.createFolder(
      _sanitizeBackupSegment(vaultLabel),
      parentPath: rawFolder,
    );

    final bytes = await File(sourcePath).readAsBytes();
    await WebDavService.instance.uploadNewFile(bytes, vaultFolder.id, fileName);
  }

  Future<void> _backupToSftp(
    String sourcePath,
    String fileName, {
    required String vaultLabel,
  }) async {
    if (!SftpService.instance.isConnected) {
      throw Exception('Not connected to SFTP');
    }

    final rawFolder = _container?.read(backupSftpFolderPathProvider) ??
        _sftpConfig?.rootPath ??
        '';
    if (rawFolder.isEmpty) {
      throw Exception('No SFTP backup folder configured');
    }

    final vaultFolder = await SftpService.instance.createFolder(
      _sanitizeBackupSegment(vaultLabel),
      parentPath: rawFolder,
    );

    final bytes = await File(sourcePath).readAsBytes();
    await SftpService.instance.uploadNewFile(bytes, vaultFolder.id, fileName);
  }

  Future<void> _backupToS3(
    String sourcePath,
    String fileName, {
    required String vaultLabel,
  }) async {
    if (!S3Service.instance.isConfigured) {
      throw Exception('Not connected to Amazon S3');
    }

    final sanitizedLabel = _sanitizeBackupSegment(vaultLabel);
    final rootPath = S3Service.instance.currentRootPath ?? '';
    final prefix = rootPath.isEmpty
        ? ''
        : (rootPath.endsWith('/') ? rootPath : '$rootPath/');
    final storageKey = '$prefix$sanitizedLabel/$fileName';

    final bytes = await File(sourcePath).readAsBytes();
    await S3Service.instance.uploadObject(storageKey, bytes);
  }

  static String _sanitizeBackupSegment(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'vault';

    // Keep it filesystem + Dropbox-path friendly.
    final cleaned = trimmed
        .replaceAll(RegExp(r'[\/\\]'), '-') // path separators
        .replaceAll(RegExp(r'[:\*\?"<>\|]'), '-') // Windows-reserved chars
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Avoid absurdly long folder/file prefixes.
    return cleaned.length > 40 ? cleaned.substring(0, 40).trim() : cleaned;
  }

  // ── Private: timer ─────────────────────────────────────────────────────────

  void _scheduleNextFixedBackup() {
    _cancelTimer();
    final container = _container;
    if (container == null || _scheduledVaultPath == null) return;
    final next = nextFixedBackupTime();
    container.read(backupNextTimestampProvider.notifier).state = next;
    final delay = next.difference(_clock());
    _timer = _timerFactory(delay.isNegative ? Duration.zero : delay, () {
      unawaited(() async {
        await runBackup();
        if (_scheduledVaultPath != null &&
            _container?.read(backupEnabledProvider) == true) {
          _scheduleNextFixedBackup();
        }
      }());
    });
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<String> _localBackupRootDirectory() async {
    if (_backupRootDirectoryOverride != null) {
      return _backupRootDirectoryOverride!;
    }
    final localPath = _container?.read(backupLocalPathProvider);
    if (localPath != null && localPath.isNotEmpty) return localPath;
    final appSupport = await getApplicationSupportDirectory();
    return p.join(appSupport.path, 'backups');
  }

  Future<String> _localVaultBackupDirectory(String vaultPath) async {
    final root = await _localBackupRootDirectory();
    return p.join(
        root, _sanitizeBackupSegment(p.basenameWithoutExtension(vaultPath)));
  }

  static String _restoreStamp(DateTime dateTime) => dateTime
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-')
      .replaceAll('T', '_');

  // ── Private: PKCE helpers ──────────────────────────────────────────────────

  String _generatePkceVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _generatePkceChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // ── Private: helpers ───────────────────────────────────────────────────────

  String _destinationToString(BackupDestination dest) {
    return switch (dest) {
      BackupDestination.googleDrive => 'googleDrive',
      BackupDestination.dropbox => 'dropbox',
      BackupDestination.oneDrive => 'oneDrive',
      BackupDestination.webdav => 'webdav',
      BackupDestination.sftp => 'sftp',
      BackupDestination.s3 => 's3',
      BackupDestination.localFolder => 'local',
    };
  }

  // ── Cloud credential validation ────────────────────────────────────────────

  /// Probes whether the cloud credentials backing [storageType] are still
  /// usable so the unlock flow can warn the user before sync silently breaks.
  ///
  /// The check is conservative — it does NOT trigger an interactive sign-in,
  /// only a cheap, read-only API call using whatever access / refresh token
  /// is already on disk. Returns a [CloudCredentialResult] explaining the
  /// outcome (and a human-readable message when something is off).
  Future<CloudCredentialResult> verifyCloudCredentialsForStorage(
      String storageType) async {
    await ensureReady();

    switch (storageType) {
      case 'googleDrive':
        return _verifyGoogleDriveCredentials();
      case 'dropbox':
        return _verifyDropboxCredentials();
      case 'oneDrive':
        return _verifyOneDriveCredentials();
      case 'webdav':
        return _verifyWebDavCredentials();
      case 'sftp':
        return _verifySftpCredentials();
      case 's3':
        return _verifyS3Credentials();
      default:
        return const CloudCredentialResult(
          CloudCredentialStatus.notApplicable,
        );
    }
  }

  Future<CloudCredentialResult> _verifyGoogleDriveCredentials() async {
    const provider = 'Google Drive';
    try {
      final creds = await _googleAuth.signInSilently();
      if (creds == null) {
        return const CloudCredentialResult(
          CloudCredentialStatus.notSignedIn,
          providerLabel: provider,
          message: 'Google Drive is no longer connected on this device. '
              'Reconnect to keep this vault in sync.',
        );
      }

      // Cheap, read-only call that exercises the access token without
      // mutating remote state.
      final headers = await creds.authHeaders;
      final response = await http
          .get(
            Uri.parse(
                'https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return const CloudCredentialResult(
          CloudCredentialStatus.valid,
          providerLabel: provider,
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return CloudCredentialResult(
          CloudCredentialStatus.authExpired,
          providerLabel: provider,
          message:
              'Google Drive rejected the saved credentials (${response.statusCode}). '
              'Reconnect Google Drive so this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Google Drive returned ${response.statusCode}. Sync may not work '
            'until the service is reachable again.',
      );
    } on TimeoutException {
      return const CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach Google Drive. You can keep working offline; '
            'sync will resume when connectivity returns.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach Google Drive ($e). You can keep working '
            'offline; sync will resume when connectivity returns.',
      );
    } catch (e) {
      debugPrint('[BackupService] Google credential check failed: $e');
      return CloudCredentialResult(
        CloudCredentialStatus.authExpired,
        providerLabel: provider,
        message:
            'Could not validate Google Drive credentials. Reconnect to make '
            'sure this vault keeps syncing. ($e)',
      );
    }
  }

  Future<CloudCredentialResult> _verifyDropboxCredentials() async {
    const provider = 'Dropbox';
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      return const CloudCredentialResult(
        CloudCredentialStatus.notSignedIn,
        providerLabel: provider,
        message: 'Dropbox is no longer connected on this device. Reconnect to '
            'keep this vault in sync.',
      );
    }
    try {
      // `users/get_current_account` is a free, read-only endpoint that
      // returns 401 when the token has been revoked.
      final response = await http
          .post(
            Uri.parse('https://api.dropboxapi.com/2/users/get_current_account'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: 'null',
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return const CloudCredentialResult(
          CloudCredentialStatus.valid,
          providerLabel: provider,
        );
      }
      if (response.statusCode == 401) {
        return const CloudCredentialResult(
          CloudCredentialStatus.authExpired,
          providerLabel: provider,
          message:
              'Dropbox rejected the saved access token. Reconnect Dropbox so '
              'this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Dropbox returned ${response.statusCode}. Sync may not work until '
            'the service is reachable again.',
      );
    } on TimeoutException {
      return const CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach Dropbox. You can keep working offline; sync '
            'will resume when connectivity returns.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach Dropbox ($e). You can keep working offline; '
            'sync will resume when connectivity returns.',
      );
    } catch (e) {
      debugPrint('[BackupService] Dropbox credential check failed: $e');
      return CloudCredentialResult(
        CloudCredentialStatus.authExpired,
        providerLabel: provider,
        message:
            'Could not validate Dropbox credentials. Reconnect to make sure '
            'this vault keeps syncing. ($e)',
      );
    }
  }

  Future<CloudCredentialResult> _verifyOneDriveCredentials() async {
    const provider = 'OneDrive';
    if (_oneDriveAccessToken == null || _oneDriveAccessToken!.isEmpty) {
      return const CloudCredentialResult(
        CloudCredentialStatus.notSignedIn,
        providerLabel: provider,
        message: 'OneDrive is no longer connected on this device. Reconnect to '
            'keep this vault in sync.',
      );
    }

    // Access tokens are short-lived. Refresh transparently (using the saved
    // refresh token) before validating so an expired-but-refreshable session
    // doesn't get reported as "rejected" and force an unnecessary reconnect.
    String? token = _oneDriveAccessToken;
    try {
      final refreshed = await OneDriveService.instance.ensureFreshAccessToken();
      if (refreshed != null && refreshed.isNotEmpty) {
        token = refreshed;
        await _persistRefreshedOneDriveToken();
      }
    } catch (e) {
      // A failed refresh isn't fatal yet — the existing token might still be
      // valid. Fall through to the Graph probe, which is the source of truth.
      debugPrint('[BackupService] OneDrive token refresh failed: $e');
    }

    try {
      // Cheap read-only call to Microsoft Graph to validate the token.
      var response = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      // The token may have expired between the refresh check and this call, or
      // the refresh above may have been skipped. Give a single refresh + retry
      // a chance before declaring the credentials dead.
      if (response.statusCode == 401) {
        try {
          await OneDriveService.instance.refreshAccessToken();
          await _persistRefreshedOneDriveToken();
          final retryToken = _oneDriveAccessToken;
          if (retryToken != null && retryToken.isNotEmpty) {
            response = await http.get(
              Uri.parse('https://graph.microsoft.com/v1.0/me'),
              headers: {'Authorization': 'Bearer $retryToken'},
            ).timeout(const Duration(seconds: 10));
          }
        } catch (e) {
          debugPrint('[BackupService] OneDrive token retry refresh failed: $e');
        }
      }

      if (response.statusCode == 200) {
        return const CloudCredentialResult(
          CloudCredentialStatus.valid,
          providerLabel: provider,
        );
      }
      if (response.statusCode == 401) {
        return const CloudCredentialResult(
          CloudCredentialStatus.authExpired,
          providerLabel: provider,
          message:
              'OneDrive rejected the saved access token. Reconnect OneDrive so '
              'this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'OneDrive returned ${response.statusCode}. Sync may not work until '
            'the service is reachable again.',
      );
    } on TimeoutException {
      return const CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach OneDrive. You can keep working offline; sync '
            'will resume when connectivity returns.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach OneDrive ($e). You can keep working offline; '
            'sync will resume when connectivity returns.',
      );
    } catch (e) {
      debugPrint('[BackupService] OneDrive credential check failed: $e');
      return CloudCredentialResult(
        CloudCredentialStatus.authExpired,
        providerLabel: provider,
        message:
            'Could not validate OneDrive credentials. Reconnect to make sure '
            'this vault keeps syncing. ($e)',
      );
    }
  }

  /// Syncs the in-memory tokens with whatever [OneDriveService] currently holds
  /// (after a silent refresh) and persists them so the rotated access/refresh
  /// tokens survive an app restart.
  Future<void> _persistRefreshedOneDriveToken() async {
    final service = OneDriveService.instance;
    final access = service.currentAccessToken;
    if (access == null || access.isEmpty) return;

    _oneDriveAccessToken = access;
    _oneDriveTokenExpiry = service.tokenExpiry;

    final container = _container;
    if (container == null) return;
    final storage = container.read(localStorageProvider);
    await storage.write(key: _kBackupOneDriveAccessToken, value: access);
    final refresh = service.currentRefreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await storage.write(key: _kBackupOneDriveRefreshToken, value: refresh);
    }
    final expiry = service.tokenExpiry;
    if (expiry != null) {
      await storage.write(
        key: _kBackupOneDriveTokenExpiry,
        value: expiry.toIso8601String(),
      );
    }
  }

  Future<CloudCredentialResult> _verifyWebDavCredentials() async {
    const provider = 'WebDAV';
    final config = _webDavConfig;
    if (config == null) {
      return const CloudCredentialResult(
        CloudCredentialStatus.notSignedIn,
        providerLabel: provider,
        message: 'WebDAV is not configured on this device. Reconnect to keep '
            'this vault in sync.',
      );
    }

    try {
      await WebDavService.instance.testConnection(config);
      return const CloudCredentialResult(
        CloudCredentialStatus.valid,
        providerLabel: provider,
      );
    } on TimeoutException {
      return const CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach the WebDAV server. You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach the WebDAV server ($e). You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    } catch (e) {
      final text = e.toString();
      // testConnection throws a descriptive message; auth failures mention it.
      final isAuth = text.contains('Authentication failed') ||
          text.contains('401') ||
          text.contains('403');
      if (isAuth) {
        return CloudCredentialResult(
          CloudCredentialStatus.authExpired,
          providerLabel: provider,
          message: 'The WebDAV server rejected the saved credentials. '
              'Reconnect so this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: text.replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<CloudCredentialResult> _verifySftpCredentials() async {
    const provider = 'SFTP';
    final config = _sftpConfig;
    if (config == null) {
      return const CloudCredentialResult(
        CloudCredentialStatus.notSignedIn,
        providerLabel: provider,
        message: 'SFTP is not configured on this device. Reconnect to keep '
            'this vault in sync.',
      );
    }

    try {
      await SftpService.instance.testConnection(config);
      return const CloudCredentialResult(
        CloudCredentialStatus.valid,
        providerLabel: provider,
      );
    } on TimeoutException {
      return const CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach the SFTP server. You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach the SFTP server ($e). You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    } catch (e) {
      final text = e.toString();
      final isAuth = text.contains('Authentication failed') ||
          text.contains('Permission denied') ||
          text.contains('denied');
      if (isAuth) {
        return const CloudCredentialResult(
          CloudCredentialStatus.authExpired,
          providerLabel: provider,
          message: 'The SFTP server rejected the saved credentials. '
              'Reconnect so this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: text.replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<CloudCredentialResult> _verifyS3Credentials() async {
    const provider = 'Amazon S3';
    if (!S3Service.instance.isConfigured) {
      return const CloudCredentialResult(
        CloudCredentialStatus.notSignedIn,
        providerLabel: provider,
        message: 'Amazon S3 is not configured on this device. Reconnect to '
            'keep this vault in sync.',
      );
    }
    try {
      final testKey =
          '${S3Service.instance.currentRootPath ?? ''}.lumenpass-credential-probe';
      await S3Service.instance.listObjects(prefix: testKey, maxKeys: 1);
      return const CloudCredentialResult(
        CloudCredentialStatus.valid,
        providerLabel: provider,
      );
    } catch (e) {
      final text = e.toString();
      if (text.contains('403') ||
          text.contains('SignatureDoesNotMatch') ||
          text.contains('InvalidAccessKeyId')) {
        return const CloudCredentialResult(
          CloudCredentialStatus.authExpired,
          providerLabel: provider,
          message: 'The S3 server rejected the saved credentials. '
              'Reconnect so this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message: 'Could not reach Amazon S3. You can keep working offline; '
            'sync will resume when it is reachable again.',
      );
    }
  }
}

// ── Google Drive auth client ──────────────────────────────────────────────────

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);
  final Map<String, String> _headers;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request..headers.addAll(_headers));
  }
}
