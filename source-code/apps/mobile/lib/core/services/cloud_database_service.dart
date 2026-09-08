import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'webdav_service.dart';
import 'sftp_service.dart';
import 's3_service.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class CloudFolder {
  const CloudFolder({required this.id, required this.name, this.path});
  final String id;
  final String name;
  final String? path;
  String get displayPath => path ?? name;
}

class CloudFile {
  const CloudFile({required this.id, required this.name, this.path});
  final String id;
  final String name;
  final String? path;
  String get displayPath => path ?? name;
}

/// Outcome of a cloud-credential health check. Mirrors the desktop
/// `CloudCredentialStatus` so the mobile Cloud Services screen can surface the
/// same "connected / reconnect / offline" states.
enum CloudCredentialStatus {
  /// Credentials look healthy; sync should work.
  valid,

  /// Not a cloud provider (local) — no check applies.
  notApplicable,

  /// No credentials are persisted on this device.
  notSignedIn,

  /// Tokens exist but the provider rejected them (revoked, expired, etc.).
  authExpired,

  /// Credentials may still be fine, but the provider was unreachable.
  networkError,
}

class CloudCredentialResult {
  const CloudCredentialResult(this.status, {this.providerLabel, this.message});

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

// ── Providers ─────────────────────────────────────────────────────────────────

final cloudGoogleAccountProvider = StateProvider<String?>((ref) => null);
final cloudDropboxAccountProvider = StateProvider<String?>((ref) => null);
final cloudOneDriveAccountProvider = StateProvider<String?>((ref) => null);
final cloudWebDavAccountProvider = StateProvider<String?>((ref) => null);
final cloudSftpAccountProvider = StateProvider<String?>((ref) => null);
final cloudS3AccountProvider = StateProvider<String?>((ref) => null);

// ── CloudDatabaseService ──────────────────────────────────────────────────────

/// Singleton service for cloud storage file operations (Google Drive + Dropbox).
/// Adapted from the desktop BackupService for mobile (uses flutter_web_auth_2
/// for Dropbox OAuth instead of a local HTTP callback server).
class CloudDatabaseService {
  CloudDatabaseService._();
  static final CloudDatabaseService instance = CloudDatabaseService._();

  static const _kDropboxAppKey = String.fromEnvironment('DROPBOX_APP_KEY');
  static bool get isDropboxConfigured => _kDropboxAppKey.isNotEmpty;

  static const _kOneDriveClientId = String.fromEnvironment(
    'ONEDRIVE_CLIENT_ID',
  );
  static bool get isOneDriveConfigured => _kOneDriveClientId.isNotEmpty;

  // Microsoft Graph / OneDrive OAuth endpoints (personal accounts).
  static const _kOneDriveAuthorizeUrl =
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize';
  static const _kOneDriveTokenUrl =
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';
  static const _kGraphBaseUrl = 'https://graph.microsoft.com/v1.0';
  static const _kOneDriveScopes =
      'Files.ReadWrite.All offline_access User.Read';

  static const _kGoogleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const _kGoogleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static bool get isGoogleDriveConfigured {
    if (Platform.isAndroid) return true;
    return _kGoogleClientId.isNotEmpty;
  }

  static const _kDriveFullScope = 'https://www.googleapis.com/auth/drive';

  static const _kDriveScopes = [
    'https://www.googleapis.com/auth/drive.file',
    _kDriveFullScope,
  ];

  static final _googleSignIn = GoogleSignIn(
    clientId: Platform.isAndroid
        ? null
        : (_kGoogleClientId.isEmpty ? null : _kGoogleClientId),
    serverClientId: _kGoogleServerClientId.isEmpty
        ? null
        : _kGoogleServerClientId,
    scopes: _kDriveScopes,
  );

  String? _dropboxAccessToken;
  ProviderContainer? _container;

  /// Shared future for [init]. Health probes await this (via [ensureReady])
  /// so they never read a half-restored state (e.g. `_sftpConfig == null`)
  /// while the fire-and-forget `init()` kicked off from `main()` is still
  /// loading credentials from secure storage — the race that made SFTP report
  /// "not connected" on a cold start until a manual refresh.
  Future<void>? _initFuture;

  String? _oneDriveAccessToken;
  String? _oneDriveRefreshToken;
  DateTime? _oneDriveTokenExpiry;

  // Secure storage keys for persisted cloud connections. Using
  // flutter_secure_storage directly here (rather than the core
  // `SecureStorageService`) keeps this service free of a dependency on the
  // higher-level repository providers — init() is called before providers
  // are fully wired up.
  static const _kDropboxTokenKey = 'cloud.dropbox.token';
  static const _kDropboxEmailKey = 'cloud.dropbox.email';
  static const _kOneDriveAccessTokenKey = 'cloud.onedrive.accessToken';
  static const _kOneDriveRefreshTokenKey = 'cloud.onedrive.refreshToken';
  static const _kOneDriveExpiryKey = 'cloud.onedrive.expiry';
  static const _kOneDriveEmailKey = 'cloud.onedrive.email';
  static const _kWebDavHostKey = 'cloud.webdav.host';
  static const _kWebDavPortKey = 'cloud.webdav.port';
  static const _kWebDavUsernameKey = 'cloud.webdav.username';
  static const _kWebDavPasswordKey = 'cloud.webdav.password';
  static const _kWebDavRootPathKey = 'cloud.webdav.rootPath';
  static const _kWebDavAccountKey = 'cloud.webdav.account';
  static const _kSftpHostKey = 'cloud.sftp.host';
  static const _kSftpPortKey = 'cloud.sftp.port';
  static const _kSftpUsernameKey = 'cloud.sftp.username';
  static const _kSftpAuthMethodKey = 'cloud.sftp.authMethod';
  static const _kSftpPasswordKey = 'cloud.sftp.password';
  static const _kSftpKeyFilePathKey = 'cloud.sftp.keyFilePath';
  static const _kSftpTransferModeKey = 'cloud.sftp.transferMode';
  static const _kSftpRootPathKey = 'cloud.sftp.rootPath';
  static const _kSftpAccountKey = 'cloud.sftp.account';

  static const _kS3AccessKey = 'cloud.s3.accessKey';
  static const _kS3SecretKey = 'cloud.s3.secretKey';
  static const _kS3Region = 'cloud.s3.region';
  static const _kS3Bucket = 'cloud.s3.bucket';
  static const _kS3RootPathKey = 'cloud.s3.rootPath';
  static const _kS3AccountKey = 'cloud.s3.account';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  GoogleSignInAccount? get currentGoogleAccount => _googleSignIn.currentUser;
  String? get currentDropboxToken => _dropboxAccessToken;
  bool get isOneDriveConnected =>
      _oneDriveAccessToken != null && _oneDriveAccessToken!.isNotEmpty;

  /// WebDAV is always usable (no app-level credentials/config required).
  static bool get isWebDavConfigured => true;
  bool get isWebDavConnected => WebDavService.instance.isConnected;
  WebDavConfig? get currentWebDavConfig => WebDavService.instance.config;

  /// SFTP is always usable (no app-level credentials/config required).
  static bool get isSftpConfigured => true;
  bool get isSftpConnected => SftpService.instance.isConnected;
  SftpConfig? get currentSftpConfig => SftpService.instance.config;

  // ── S3 ──────────────────────────────────────────────────────────────────────

  static bool get isS3Configured => true;
  bool get isS3Connected => S3Service.instance.isConfigured;
  S3Config? get currentS3Config => isS3Connected
      ? S3Config(
          accessKey: '',
          secretKey: '',
          region: S3Service.instance.currentRegion ?? 'us-east-1',
          bucketId: S3Service.instance.currentBucketId ?? '',
          rootPath: S3Service.instance.currentRootPath ?? '',
        )
      : null;

  /// Wires the service to the app's provider container and rehydrates
  /// previously-established cloud connections (Dropbox token from secure
  /// storage + Google silent sign-in). Fire-and-forget from main(): the UI
  /// will reactively show "connected" state as soon as restoration completes.
  ///
  /// Concurrent callers share the same in-flight future so a cold-start health
  /// probe can [ensureReady] and observe fully-restored credentials instead of
  /// racing the still-running restore.
  Future<void> init(ProviderContainer container) {
    return _initFuture ??= _init(container);
  }

  /// Awaits the one-time [init] restore if it has been started. Safe to call
  /// before `init()` (returns immediately) — in practice `main()` always kicks
  /// off `init()` before the first widget builds.
  Future<void> ensureReady() async {
    final future = _initFuture;
    if (future == null) return;
    await future;
  }

  Future<void> _init(ProviderContainer container) async {
    _container = container;

    // ── Dropbox: restore persisted access token + account email ──────────
    try {
      final token = await _secureStorage.read(key: _kDropboxTokenKey);
      final email = await _secureStorage.read(key: _kDropboxEmailKey);
      if (token != null && token.isNotEmpty) {
        _dropboxAccessToken = token;
        container.read(cloudDropboxAccountProvider.notifier).state =
            (email != null && email.isNotEmpty) ? email : 'Connected';
      }
    } catch (e) {
      debugPrint('[CloudDatabaseService] Dropbox token restore failed: $e');
    }

    // ── OneDrive: restore persisted tokens + account email ───────────────
    try {
      final accessToken = await _secureStorage.read(
        key: _kOneDriveAccessTokenKey,
      );
      final refreshToken = await _secureStorage.read(
        key: _kOneDriveRefreshTokenKey,
      );
      final expiryRaw = await _secureStorage.read(key: _kOneDriveExpiryKey);
      final email = await _secureStorage.read(key: _kOneDriveEmailKey);
      if (accessToken != null && accessToken.isNotEmpty) {
        _oneDriveAccessToken = accessToken;
        _oneDriveRefreshToken = refreshToken;
        _oneDriveTokenExpiry = expiryRaw != null
            ? DateTime.tryParse(expiryRaw)
            : null;
        container.read(cloudOneDriveAccountProvider.notifier).state =
            (email != null && email.isNotEmpty) ? email : 'Connected';
      }
    } catch (e) {
      debugPrint('[CloudDatabaseService] OneDrive token restore failed: $e');
    }

    // ── WebDAV: restore persisted host/credentials + account label ───────
    try {
      final host = await _secureStorage.read(key: _kWebDavHostKey);
      final password = await _secureStorage.read(key: _kWebDavPasswordKey);
      if (host != null && host.isNotEmpty && password != null) {
        final portRaw = await _secureStorage.read(key: _kWebDavPortKey);
        final username =
            await _secureStorage.read(key: _kWebDavUsernameKey) ?? '';
        final rootPath =
            await _secureStorage.read(key: _kWebDavRootPathKey) ?? '/';
        final account = await _secureStorage.read(key: _kWebDavAccountKey);
        final config = WebDavConfig(
          host: host,
          port: int.tryParse(portRaw ?? '') ?? 443,
          username: username,
          password: password,
          rootPath: rootPath,
        );
        WebDavService.instance.restore(config);
        container
            .read(cloudWebDavAccountProvider.notifier)
            .state = (account != null && account.isNotEmpty)
            ? account
            : config.accountLabel;
      }
    } catch (e) {
      debugPrint('[CloudDatabaseService] WebDAV config restore failed: $e');
    }

    // ── SFTP: restore persisted host/credentials + account label ─────────
    try {
      final host = await _secureStorage.read(key: _kSftpHostKey);
      final password = await _secureStorage.read(key: _kSftpPasswordKey);
      if (host != null &&
          host.isNotEmpty &&
          (password != null && password.isNotEmpty ||
              await _secureStorage.read(key: _kSftpKeyFilePathKey) != null)) {
        final portRaw = await _secureStorage.read(key: _kSftpPortKey);
        final username =
            await _secureStorage.read(key: _kSftpUsernameKey) ?? '';
        final authMethodRaw = await _secureStorage.read(
          key: _kSftpAuthMethodKey,
        );
        final keyFilePath = await _secureStorage.read(
          key: _kSftpKeyFilePathKey,
        );
        final transferModeRaw = await _secureStorage.read(
          key: _kSftpTransferModeKey,
        );
        final rootPath =
            await _secureStorage.read(key: _kSftpRootPathKey) ?? '/';
        final account = await _secureStorage.read(key: _kSftpAccountKey);
        final config = SftpConfig(
          host: host,
          port: int.tryParse(portRaw ?? '') ?? 22,
          username: username,
          authMethod: authMethodRaw == 'publicKeyFile'
              ? SftpAuthMethod.publicKeyFile
              : SftpAuthMethod.password,
          password: password ?? '',
          keyFilePath: keyFilePath,
          transferMode: transferModeRaw == 'passive'
              ? SftpTransferMode.passive
              : SftpTransferMode.active,
          rootPath: rootPath,
        );
        final usable = await SftpService.instance.restore(config);
        if (usable) {
          container
              .read(cloudSftpAccountProvider.notifier)
              .state = (account != null && account.isNotEmpty)
              ? account
              : config.accountLabel;
        } else {
          // The persisted private key file is missing/unreadable, so the
          // connection cannot be used. Leave the account provider null so the
          // UI does not advertise a green "Connected" state that the health
          // check (and Open Database) would immediately reject.
          container.read(cloudSftpAccountProvider.notifier).state = null;
          debugPrint(
            '[CloudDatabaseService] SFTP restore skipped: key file unavailable',
          );
        }
      }
    } catch (e) {
      debugPrint('[CloudDatabaseService] SFTP config restore failed: $e');
    }

    // ── S3: restore persisted access key / secret key / region / bucket ────
    try {
      final accessKey = await _secureStorage.read(key: _kS3AccessKey);
      final secretKey = await _secureStorage.read(key: _kS3SecretKey);
      final region = await _secureStorage.read(key: _kS3Region);
      final bucket = await _secureStorage.read(key: _kS3Bucket);
      if (accessKey != null &&
          accessKey.isNotEmpty &&
          secretKey != null &&
          secretKey.isNotEmpty &&
          bucket != null &&
          bucket.isNotEmpty) {
        final rootPath = await _secureStorage.read(key: _kS3RootPathKey) ?? '';
        final account = await _secureStorage.read(key: _kS3AccountKey);
        final s3Config = S3Config(
          accessKey: accessKey,
          secretKey: secretKey,
          region: region ?? 'us-east-1',
          bucketId: bucket,
          rootPath: rootPath,
        );
        S3Service.instance.configure(s3Config);
        container
            .read(cloudS3AccountProvider.notifier)
            .state = (account != null && account.isNotEmpty)
            ? account
            : 's3://$bucket${rootPath.isNotEmpty ? '/$rootPath' : ''}';
      }
    } catch (e) {
      debugPrint('[CloudDatabaseService] S3 config restore failed: $e');
    }

    // ── Google Drive: silent sign-in (only if Google is configured) ──────
    if (isGoogleDriveConfigured) {
      try {
        final account = await _googleSignIn.signInSilently();
        if (account != null) {
          container.read(cloudGoogleAccountProvider.notifier).state =
              account.email;
        }
      } catch (e) {
        debugPrint('[CloudDatabaseService] Google silent sign-in failed: $e');
      }
    }
  }

  // ── Google Drive ───────────────────────────────────────────────────────────

  Future<void> connectGoogle() async {
    if (!isGoogleDriveConfigured) {
      throw Exception(
        'Google Drive is not configured. '
        'On iOS, pass GOOGLE_CLIENT_ID via --dart-define and copy '
        'ios/Flutter/GoogleClient.xcconfig.example to GoogleClient.xcconfig. '
        'On Android, pass GOOGLE_SERVER_CLIENT_ID (Web client ID) '
        'via --dart-define.',
      );
    }
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return;
      await _ensureDriveWriteScope(account);
      _container?.read(cloudGoogleAccountProvider.notifier).state =
          account.email;
    } on PlatformException catch (e) {
      throw Exception(_describeGoogleSignInError(e));
    }
  }

  static String _describeGoogleSignInError(PlatformException e) {
    final details = e.message ?? e.details?.toString() ?? '';

    if (details.contains('ApiException: 10') ||
        details.contains('DEVELOPER_ERROR')) {
      if (Platform.isAndroid) {
        return 'Google Sign-In configuration error. '
            'Ensure your debug/release SHA-1 fingerprint and package name '
            'are registered as an Android OAuth client in the '
            'Google Cloud Console, and that GOOGLE_SERVER_CLIENT_ID '
            '(Web client ID) is passed via --dart-define.';
      }
      return 'Google Sign-In configuration error. '
          'Verify the GOOGLE_CLIENT_ID and reversed client ID in '
          'ios/Flutter/GoogleClient.xcconfig match your Google Cloud project.';
    }

    if (details.contains('ApiException: 12501') ||
        details.contains('sign_in_cancelled') ||
        e.code == 'sign_in_cancelled') {
      return 'Sign-in was cancelled.';
    }

    if (details.contains('ApiException: 12502')) {
      return 'Sign-in is already in progress. Please wait.';
    }

    if (details.contains('ApiException: 7') ||
        details.contains('NETWORK_ERROR')) {
      return 'Network error. Check your internet connection and try again.';
    }

    if (details.contains('ApiException: 8') ||
        details.contains('INTERNAL_ERROR')) {
      return 'An internal Google Sign-In error occurred. Please try again.';
    }

    return 'Google Sign-In failed: ${e.message ?? e.code}';
  }

  Future<void> disconnectGoogle() async {
    await _googleSignIn.signOut();
    _container?.read(cloudGoogleAccountProvider.notifier).state = null;
  }

  /// Creates a folder named [name] on Google Drive inside [parentId] (or root).
  Future<CloudFolder> createGoogleDriveFolder(
    String name, {
    String? parentId,
  }) async {
    final account = await _requireGoogleAccount();
    final driveApi = await _buildDriveApi(account);

    final meta = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    if (parentId != null && parentId.isNotEmpty) meta.parents = [parentId];

    final created = await driveApi.files.create(meta);
    return CloudFolder(id: created.id!, name: created.name ?? name);
  }

  Future<List<CloudFolder>> listGoogleDriveFolders({String? parentId}) async {
    final account = await _requireGoogleAccount();
    final driveApi = await _buildDriveApi(account);

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

  Future<List<CloudFile>> listGoogleDriveFiles({String? parentId}) async {
    final account = await _requireGoogleAccount();
    final driveApi = await _buildDriveApi(account);

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

  Future<Uint8List> downloadGoogleDriveFile(String fileId) async {
    final account = await _requireGoogleAccount();
    final driveApi = await _buildDriveApi(account);

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

  Future<String> uploadToGoogleDrive(
    Uint8List bytes,
    String fileName, {
    String? folderId,
  }) async {
    final account = await _requireGoogleAccount();
    final driveApi = await _buildDriveApi(account);

    final meta = drive.File()..name = fileName;
    if (folderId != null && folderId.isNotEmpty) meta.parents = [folderId];

    final result = await driveApi.files.create(
      meta,
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
    );
    return result.id ?? '';
  }

  Future<void> updateGoogleDriveFile(
    String fileId,
    Uint8List bytes,
    String fileName,
  ) async {
    final account = await _requireGoogleAccount();

    Future<void> doUpdate() async {
      final driveApi = await _buildDriveApi(account);
      final meta = drive.File()..name = fileName;
      await driveApi.files.update(
        meta,
        fileId,
        uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
      );
    }

    try {
      await doUpdate();
    } catch (e) {
      if (!_isDriveWritePermissionError(e)) rethrow;
      debugPrint(
        '[CloudDatabaseService] Google Drive 403 — requesting drive write '
        'scope and retrying (file="$fileName")',
      );
      final granted = await _ensureDriveWriteScope(account);
      if (!granted) {
        throw Exception(
          'Google Drive write access was not granted. '
          'Disconnect and reconnect Google Drive, then accept the '
          '"See, edit, create, and delete all of your Google Drive files" '
          'permission. Underlying error: $e',
        );
      }
      await doUpdate();
    }
  }

  Future<DateTime?> getGoogleDriveFileModifiedTime(String fileId) async {
    final account = await _requireGoogleAccount();
    final driveApi = await _buildDriveApi(account);
    final file =
        await driveApi.files.get(fileId, $fields: 'modifiedTime') as drive.File;
    return file.modifiedTime;
  }

  Future<DateTime?> getDropboxFileModifiedTime(String dropboxPath) async {
    final token = _requireDropboxToken();
    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/files/get_metadata'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'path': dropboxPath}),
    );
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = data['server_modified'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<bool> _ensureDriveWriteScope(GoogleSignInAccount account) async {
    try {
      final alreadyGranted = await _googleSignIn.canAccessScopes(const [
        _kDriveFullScope,
      ]);
      if (alreadyGranted) return true;
    } catch (_) {}
    try {
      debugPrint(
        '[CloudDatabaseService] requesting incremental Drive write scope for '
        '${account.email}',
      );
      final granted = await _googleSignIn.requestScopes(const [
        _kDriveFullScope,
      ]);
      debugPrint('[CloudDatabaseService] Drive write scope granted=$granted');
      return granted;
    } catch (e) {
      debugPrint('[CloudDatabaseService] requestScopes failed: $e');
      return false;
    }
  }

  bool _isDriveWritePermissionError(Object e) {
    final s = e.toString();
    if (!s.contains('403')) return false;
    return s.contains('has not granted the app') ||
        s.contains('insufficientFilePermissions') ||
        s.contains('insufficient permissions') ||
        s.contains('insufficientPermissions');
  }

  Future<GoogleSignInAccount> _requireGoogleAccount() async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    if (account == null) throw Exception('Not signed in to Google Drive.');
    return account;
  }

  Future<drive.DriveApi> _buildDriveApi(GoogleSignInAccount account) async {
    final headers = await account.authHeaders;
    return drive.DriveApi(_GoogleAuthClient(headers));
  }

  // ── Dropbox ────────────────────────────────────────────────────────────────

  /// PKCE OAuth2 flow using flutter_web_auth_2 (ASWebAuthenticationSession on
  /// iOS; Chrome Custom Tabs on Android).
  /// Requires DROPBOX_APP_KEY via --dart-define and the `lumenpass` URL scheme
  /// registered in AndroidManifest.xml / Info.plist.
  Future<void> connectDropbox() async {
    const clientId = _kDropboxAppKey;
    if (clientId.isEmpty) {
      throw Exception(
        'DROPBOX_APP_KEY not configured. '
        'Pass it via --dart-define=DROPBOX_APP_KEY=<key>',
      );
    }

    const callbackScheme = 'lumenpass';
    const redirectUrl = '$callbackScheme://dropbox-oauth/callback';

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

    final result = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: callbackScheme,
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('No authorization code returned from Dropbox.');
    }

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
      throw Exception('Dropbox response missing access_token.');
    }

    _dropboxAccessToken = accessToken;

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

    _container?.read(cloudDropboxAccountProvider.notifier).state = email;

    // Persist so subsequent app launches skip the OAuth round trip.
    try {
      await _secureStorage.write(key: _kDropboxTokenKey, value: accessToken);
      await _secureStorage.write(key: _kDropboxEmailKey, value: email);
    } catch (e) {
      debugPrint('[CloudDatabaseService] Dropbox token persist failed: $e');
    }
  }

  Future<void> disconnectDropbox() async {
    _dropboxAccessToken = null;
    _container?.read(cloudDropboxAccountProvider.notifier).state = null;
    try {
      await _secureStorage.delete(key: _kDropboxTokenKey);
      await _secureStorage.delete(key: _kDropboxEmailKey);
    } catch (e) {
      debugPrint('[CloudDatabaseService] Dropbox token delete failed: $e');
    }
  }

  /// Creates a folder at [dropboxPath] (e.g. '/LumenPass'). Silently accepts
  /// 409 "path/conflict" responses so repeated calls on the same path are
  /// idempotent.
  Future<void> createDropboxFolder(String dropboxPath) async {
    final token = _requireDropboxToken();

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
        'Dropbox create_folder failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<List<CloudFolder>> listDropboxFolders(String path) async {
    final token = _requireDropboxToken();
    final normalised = (path == '/' || path.isEmpty) ? '' : path;

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
        'Dropbox list_folder failed (${response.statusCode}): ${response.body}',
      );
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
        })
        .toList();
  }

  Future<List<CloudFile>> listDropboxFiles(String path) async {
    final token = _requireDropboxToken();
    final normalised = (path == '/' || path.isEmpty) ? '' : path;

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
        'Dropbox list_folder failed (${response.statusCode}): ${response.body}',
      );
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
            path:
                (m['path_display'] as String?) ?? (m['path_lower'] as String?),
          );
        })
        .toList();
  }

  Future<Uint8List> downloadDropboxFile(String dropboxPath) async {
    final token = _requireDropboxToken();

    final response = await http.post(
      Uri.parse('https://content.dropboxapi.com/2/files/download'),
      headers: {
        'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': jsonEncode({'path': dropboxPath}),
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Dropbox download failed (${response.statusCode}): ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  Future<void> uploadToDropbox(Uint8List bytes, String dropboxPath) async {
    final token = _requireDropboxToken();

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
      throw Exception(
        'Dropbox upload failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  String _requireDropboxToken() {
    final token = _dropboxAccessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not connected to Dropbox.');
    }
    return token;
  }

  // ── OneDrive (Microsoft Graph) ──────────────────────────────────────────

  /// PKCE OAuth2 flow using flutter_web_auth_2 against the Microsoft identity
  /// platform (consumers endpoint). Requires ONEDRIVE_CLIENT_ID via
  /// --dart-define and the `lumenpass` URL scheme registered in
  /// AndroidManifest.xml / Info.plist.
  Future<void> connectOneDrive() async {
    const clientId = _kOneDriveClientId;
    if (clientId.isEmpty) {
      throw Exception(
        'ONEDRIVE_CLIENT_ID not configured. '
        'Pass it via --dart-define=ONEDRIVE_CLIENT_ID=<client_id>',
      );
    }

    const callbackScheme = 'lumenpass';
    const redirectUrl = '$callbackScheme://onedrive-oauth/callback';

    final verifier = _generatePkceVerifier();
    final challenge = _generatePkceChallenge(verifier);

    final authUri = Uri.parse(_kOneDriveAuthorizeUrl).replace(
      queryParameters: <String, String>{
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUrl,
        'scope': _kOneDriveScopes,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      },
    );

    final result = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: callbackScheme,
    );

    final code = Uri.parse(result).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('No authorization code returned from OneDrive.');
    }

    final tokenRes = await http.post(
      Uri.parse(_kOneDriveTokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUrl,
        'code_verifier': verifier,
        'scope': _kOneDriveScopes,
      },
    );

    if (tokenRes.statusCode != 200) {
      throw Exception('OneDrive token exchange failed: ${tokenRes.body}');
    }

    _applyOneDriveTokenResponse(tokenRes.body);

    String email = 'Connected';
    try {
      final meRes = await http.get(
        Uri.parse('$_kGraphBaseUrl/me'),
        headers: {'Authorization': 'Bearer $_oneDriveAccessToken'},
      );
      if (meRes.statusCode == 200) {
        final data = jsonDecode(meRes.body) as Map<String, dynamic>;
        email =
            (data['userPrincipalName'] as String?) ??
            (data['mail'] as String?) ??
            (data['displayName'] as String?) ??
            'Connected';
      }
    } catch (e) {
      debugPrint('[CloudDatabaseService] OneDrive /me lookup failed: $e');
    }

    _container?.read(cloudOneDriveAccountProvider.notifier).state = email;
    await _persistOneDriveTokens(email);
  }

  Future<void> disconnectOneDrive() async {
    _oneDriveAccessToken = null;
    _oneDriveRefreshToken = null;
    _oneDriveTokenExpiry = null;
    _container?.read(cloudOneDriveAccountProvider.notifier).state = null;
    try {
      await _secureStorage.delete(key: _kOneDriveAccessTokenKey);
      await _secureStorage.delete(key: _kOneDriveRefreshTokenKey);
      await _secureStorage.delete(key: _kOneDriveExpiryKey);
      await _secureStorage.delete(key: _kOneDriveEmailKey);
    } catch (e) {
      debugPrint('[CloudDatabaseService] OneDrive token delete failed: $e');
    }
  }

  void _applyOneDriveTokenResponse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('OneDrive response missing access_token.');
    }
    _oneDriveAccessToken = accessToken;
    final refreshToken = data['refresh_token'] as String?;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _oneDriveRefreshToken = refreshToken;
    }
    final expiresIn = data['expires_in'];
    final seconds = expiresIn is int
        ? expiresIn
        : int.tryParse('${expiresIn ?? ''}') ?? 3600;
    _oneDriveTokenExpiry = DateTime.now().add(Duration(seconds: seconds));
  }

  Future<void> _persistOneDriveTokens(String email) async {
    try {
      await _secureStorage.write(
        key: _kOneDriveAccessTokenKey,
        value: _oneDriveAccessToken,
      );
      if (_oneDriveRefreshToken != null) {
        await _secureStorage.write(
          key: _kOneDriveRefreshTokenKey,
          value: _oneDriveRefreshToken,
        );
      }
      if (_oneDriveTokenExpiry != null) {
        await _secureStorage.write(
          key: _kOneDriveExpiryKey,
          value: _oneDriveTokenExpiry!.toIso8601String(),
        );
      }
      await _secureStorage.write(key: _kOneDriveEmailKey, value: email);
    } catch (e) {
      debugPrint('[CloudDatabaseService] OneDrive token persist failed: $e');
    }
  }

  /// Returns valid auth headers, refreshing the access token when it is within
  /// 5 minutes of expiry. Mirrors the desktop OneDriveService `_authHeaders`.
  Future<Map<String, String>> _oneDriveAuthHeaders() async {
    if (_oneDriveAccessToken == null) {
      throw Exception('Not connected to OneDrive.');
    }
    final expiry = _oneDriveTokenExpiry;
    final needsRefresh =
        expiry == null ||
        DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 5)));
    if (needsRefresh) {
      await _refreshOneDriveToken();
    }
    return {'Authorization': 'Bearer $_oneDriveAccessToken'};
  }

  Future<void> _refreshOneDriveToken() async {
    final refreshToken = _oneDriveRefreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception(
        'OneDrive session expired and no refresh token is available. '
        'Reconnect OneDrive.',
      );
    }
    final res = await http.post(
      Uri.parse(_kOneDriveTokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _kOneDriveClientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'scope': _kOneDriveScopes,
      },
    );
    if (res.statusCode != 200) {
      throw Exception('OneDrive token refresh failed: ${res.body}');
    }
    _applyOneDriveTokenResponse(res.body);
    final email = _container?.read(cloudOneDriveAccountProvider) ?? 'Connected';
    await _persistOneDriveTokens(email);
  }

  /// Creates a folder named [name] on OneDrive inside [parentId] (or root).
  /// Idempotent-ish: relies on conflictBehavior=rename on the server side, but
  /// callers that need the existing folder should list children instead.
  Future<CloudFolder> createOneDriveFolder(
    String name, {
    String? parentId,
  }) async {
    final headers = await _oneDriveAuthHeaders();
    final parent = (parentId == null || parentId.isEmpty) ? 'root' : parentId;
    final res = await http.post(
      Uri.parse('$_kGraphBaseUrl/me/drive/items/$parent/children'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'folder': <String, dynamic>{},
        '@microsoft.graph.conflictBehavior': 'fail',
      }),
    );
    // 409 Conflict means the folder already exists — find and return it.
    if (res.statusCode == 409) {
      final folders = await listOneDriveFolders(
        parentId: parent == 'root' ? null : parent,
      );
      final match = folders.where((f) => f.name == name).toList();
      if (match.isNotEmpty) return match.first;
      throw Exception(
        'OneDrive folder conflict but could not resolve existing folder: ${res.body}',
      );
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(
        'OneDrive create folder failed (${res.statusCode}): ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return CloudFolder(id: data['id'] as String, name: data['name'] as String);
  }

  Future<List<CloudFolder>> listOneDriveFolders({String? parentId}) async {
    final headers = await _oneDriveAuthHeaders();
    final base = (parentId == null || parentId.isEmpty)
        ? '$_kGraphBaseUrl/me/drive/root/children'
        : '$_kGraphBaseUrl/me/drive/items/$parentId/children';
    final url = '$base?\$select=id,name,folder,parentReference';
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode != 200) {
      throw Exception(
        'OneDrive list folders failed (${res.statusCode}): ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (data['value'] as List<dynamic>?) ?? <dynamic>[];
    return items
        .where((e) => (e as Map<String, dynamic>).containsKey('folder'))
        .map((e) {
          final m = e as Map<String, dynamic>;
          return CloudFolder(id: m['id'] as String, name: m['name'] as String);
        })
        .toList();
  }

  Future<List<CloudFile>> listOneDriveFiles({String? parentId}) async {
    final headers = await _oneDriveAuthHeaders();
    final base = (parentId == null || parentId.isEmpty)
        ? '$_kGraphBaseUrl/me/drive/root/children'
        : '$_kGraphBaseUrl/me/drive/items/$parentId/children';
    final url =
        '$base?\$select=id,name,file,lastModifiedDateTime,parentReference';
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode != 200) {
      throw Exception(
        'OneDrive list files failed (${res.statusCode}): ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (data['value'] as List<dynamic>?) ?? <dynamic>[];
    return items
        .where((e) => (e as Map<String, dynamic>).containsKey('file'))
        .map((e) {
          final m = e as Map<String, dynamic>;
          return CloudFile(id: m['id'] as String, name: m['name'] as String);
        })
        .toList();
  }

  Future<Uint8List> downloadOneDriveFile(String itemId) async {
    final headers = await _oneDriveAuthHeaders();
    final res = await http.get(
      Uri.parse('$_kGraphBaseUrl/me/drive/items/$itemId/content'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw Exception(
        'OneDrive download failed (${res.statusCode}): ${res.body}',
      );
    }
    return res.bodyBytes;
  }

  /// Overwrites the content of an existing OneDrive item by id.
  Future<void> updateOneDriveFile(
    String itemId,
    Uint8List bytes,
    String fileName,
  ) async {
    final headers = await _oneDriveAuthHeaders();
    final res = await http.put(
      Uri.parse('$_kGraphBaseUrl/me/drive/items/$itemId/content'),
      headers: {...headers, 'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(
        'OneDrive upload failed (${res.statusCode}): ${res.body}',
      );
    }
  }

  /// Uploads a new file [fileName] into [folderId] (or root), returning the
  /// new item id.
  Future<String> uploadNewFileToOneDrive(
    Uint8List bytes,
    String folderId,
    String fileName,
  ) async {
    final headers = await _oneDriveAuthHeaders();
    final parent = folderId.isEmpty ? 'root' : folderId;
    final encodedName = Uri.encodeComponent(fileName);
    final res = await http.put(
      Uri.parse(
        '$_kGraphBaseUrl/me/drive/items/$parent:/$encodedName:/content',
      ),
      headers: {...headers, 'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(
        'OneDrive upload failed (${res.statusCode}): ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<DateTime?> getOneDriveFileModifiedTime(String itemId) async {
    final headers = await _oneDriveAuthHeaders();
    final res = await http.get(
      Uri.parse(
        '$_kGraphBaseUrl/me/drive/items/$itemId?\$select=lastModifiedDateTime',
      ),
      headers: headers,
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = data['lastModifiedDateTime'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  // ── WebDAV ──────────────────────────────────────────────────────────────

  /// Validates [config], verifies the server/credentials/root-path are usable,
  /// persists the configuration (password stored in the secret store), and
  /// publishes the connected account label.
  Future<void> connectWebDav(WebDavConfig config) async {
    await WebDavService.instance.connect(config);
    final stored = WebDavService.instance.config ?? config;
    final account = stored.accountLabel;
    _container?.read(cloudWebDavAccountProvider.notifier).state = account;
    try {
      await _secureStorage.write(key: _kWebDavHostKey, value: stored.host);
      await _secureStorage.write(
        key: _kWebDavPortKey,
        value: stored.port.toString(),
      );
      await _secureStorage.write(
        key: _kWebDavUsernameKey,
        value: stored.username,
      );
      await _secureStorage.write(
        key: _kWebDavPasswordKey,
        value: stored.password,
      );
      await _secureStorage.write(
        key: _kWebDavRootPathKey,
        value: stored.rootPath,
      );
      await _secureStorage.write(key: _kWebDavAccountKey, value: account);
    } catch (e) {
      debugPrint('[CloudDatabaseService] WebDAV config persist failed: $e');
    }
  }

  /// Verifies a candidate [config] without persisting it — used by the
  /// "Test connection" button.
  Future<void> testWebDavConnection(WebDavConfig config) async {
    await WebDavService.instance.testConnection(config);
  }

  /// Confirms the chosen path is a usable read/write destination by writing,
  /// reading back and deleting a small probe file. Throws when it is not.
  Future<void> verifyWebDavWritable(WebDavConfig config) async {
    await WebDavService.instance.verifyWritable(config);
  }

  Future<void> disconnectWebDav() async {
    WebDavService.instance.disconnect();
    _container?.read(cloudWebDavAccountProvider.notifier).state = null;
    try {
      await _secureStorage.delete(key: _kWebDavHostKey);
      await _secureStorage.delete(key: _kWebDavPortKey);
      await _secureStorage.delete(key: _kWebDavUsernameKey);
      await _secureStorage.delete(key: _kWebDavPasswordKey);
      await _secureStorage.delete(key: _kWebDavRootPathKey);
      await _secureStorage.delete(key: _kWebDavAccountKey);
    } catch (e) {
      debugPrint('[CloudDatabaseService] WebDAV config delete failed: $e');
    }
  }

  /// Lists folders under [parentId] (configured root when null) on WebDAV.
  Future<List<CloudFolder>> listWebDavFolders({String? parentId}) async {
    final folders = await WebDavService.instance.listFolders(
      parentPath: parentId,
    );
    return folders
        .map((f) => CloudFolder(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  /// Lists files under [parentId] on WebDAV.
  Future<List<CloudFile>> listWebDavFiles({String? parentId}) async {
    final files = await WebDavService.instance.listFiles(parentPath: parentId);
    return files
        .map((f) => CloudFile(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  /// Lists folders under [parentId] (server root when null) using an explicit,
  /// possibly-unsaved [config] — powers the GUI path picker after "Test".
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

  /// Creates a folder under [parentId] using an explicit [config]. Returns the
  /// created [CloudFolder].
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

  Future<Uint8List> downloadWebDavFile(String remotePath) async {
    return WebDavService.instance.downloadFile(remotePath);
  }

  /// Overwrites an existing WebDAV resource (server-relative path).
  Future<void> updateWebDavFile(String remotePath, Uint8List bytes) async {
    await WebDavService.instance.uploadBytes(bytes, remotePath);
  }

  /// Uploads a new file into [folderPath], returning its server-relative path
  /// (used as the cloudFileId).
  Future<String> uploadNewFileToWebDav(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    return WebDavService.instance.uploadNewFile(bytes, folderPath, fileName);
  }

  Future<DateTime?> getWebDavFileModifiedTime(String remotePath) async {
    return WebDavService.instance.getFileModifiedTime(remotePath);
  }

  // ── SFTP ───────────────────────────────────────────────────────────────────

  Future<void> connectSftp(SftpConfig config) async {
    await SftpService.instance.connect(config);
    final stored = SftpService.instance.config ?? config;
    final account = stored.accountLabel;
    _container?.read(cloudSftpAccountProvider.notifier).state = account;
    try {
      await _secureStorage.write(key: _kSftpHostKey, value: stored.host);
      await _secureStorage.write(
        key: _kSftpPortKey,
        value: stored.port.toString(),
      );
      await _secureStorage.write(
        key: _kSftpUsernameKey,
        value: stored.username,
      );
      await _secureStorage.write(
        key: _kSftpAuthMethodKey,
        value: stored.authMethod.name,
      );
      if (stored.password.isNotEmpty) {
        await _secureStorage.write(
          key: _kSftpPasswordKey,
          value: stored.password,
        );
      }
      if (stored.keyFilePath != null && stored.keyFilePath!.isNotEmpty) {
        await _secureStorage.write(
          key: _kSftpKeyFilePathKey,
          value: stored.keyFilePath,
        );
      }
      await _secureStorage.write(
        key: _kSftpTransferModeKey,
        value: stored.transferMode.name,
      );
      await _secureStorage.write(
        key: _kSftpRootPathKey,
        value: stored.rootPath,
      );
      await _secureStorage.write(key: _kSftpAccountKey, value: account);
    } catch (e) {
      debugPrint('[CloudDatabaseService] SFTP config persist failed: $e');
    }
  }

  Future<void> testSftpConnection(SftpConfig config) async {
    await SftpService.instance.testConnection(config);
  }

  /// Whether the current SFTP configuration can still authenticate (the
  /// private key file, if used, exists on disk). Used to keep the Quick Access
  /// "Connected" state consistent with the per-vault health check.
  Future<bool> isSftpConnectionUsable() async {
    return SftpService.instance.isConfigUsable();
  }

  /// Clears the in-memory SFTP "Connected" state without deleting the persisted
  /// credentials, so the Quick Access banner reflects that the connection can
  /// no longer be used.
  void markSftpDisconnected() {
    _container?.read(cloudSftpAccountProvider.notifier).state = null;
  }

  Future<void> verifySftpWritable(SftpConfig config) async {
    await SftpService.instance.verifyWritable(config);
  }

  Future<void> disconnectSftp() async {
    await SftpService.instance.disconnect();
    _container?.read(cloudSftpAccountProvider.notifier).state = null;
    try {
      await _secureStorage.delete(key: _kSftpHostKey);
      await _secureStorage.delete(key: _kSftpPortKey);
      await _secureStorage.delete(key: _kSftpUsernameKey);
      await _secureStorage.delete(key: _kSftpAuthMethodKey);
      await _secureStorage.delete(key: _kSftpPasswordKey);
      await _secureStorage.delete(key: _kSftpKeyFilePathKey);
      await _secureStorage.delete(key: _kSftpTransferModeKey);
      await _secureStorage.delete(key: _kSftpRootPathKey);
      await _secureStorage.delete(key: _kSftpAccountKey);
    } catch (e) {
      debugPrint('[CloudDatabaseService] SFTP config delete failed: $e');
    }
  }

  // ── S3 ──────────────────────────────────────────────────────────────────────

  Future<void> connectS3(S3Config config) async {
    S3Service.instance.configure(config);
    final account =
        's3://${config.bucketId}${config.rootPath.isNotEmpty ? '/${config.rootPath}' : ''}';
    _container?.read(cloudS3AccountProvider.notifier).state = account;
    try {
      await _secureStorage.write(key: _kS3AccessKey, value: config.accessKey);
      await _secureStorage.write(key: _kS3SecretKey, value: config.secretKey);
      await _secureStorage.write(key: _kS3Region, value: config.region);
      await _secureStorage.write(key: _kS3Bucket, value: config.bucketId);
      await _secureStorage.write(key: _kS3RootPathKey, value: config.rootPath);
      await _secureStorage.write(key: _kS3AccountKey, value: account);
    } catch (e) {
      debugPrint('[CloudDatabaseService] S3 config persist failed: $e');
    }
  }

  Future<void> disconnectS3() async {
    S3Service.instance.dispose();
    _container?.read(cloudS3AccountProvider.notifier).state = null;
    try {
      await _secureStorage.delete(key: _kS3AccessKey);
      await _secureStorage.delete(key: _kS3SecretKey);
      await _secureStorage.delete(key: _kS3Region);
      await _secureStorage.delete(key: _kS3Bucket);
      await _secureStorage.delete(key: _kS3RootPathKey);
      await _secureStorage.delete(key: _kS3AccountKey);
    } catch (e) {
      debugPrint('[CloudDatabaseService] S3 config delete failed: $e');
    }
  }

  Future<List<CloudFolder>> listSftpFolders({String? parentId}) async {
    final folders = await SftpService.instance.listFolders(
      parentPath: parentId,
    );
    return folders
        .map((f) => CloudFolder(id: f.id, name: f.name, path: f.path))
        .toList();
  }

  Future<List<CloudFile>> listSftpFiles({String? parentId}) async {
    final files = await SftpService.instance.listFiles(parentPath: parentId);
    return files
        .map((f) => CloudFile(id: f.id, name: f.name, path: f.path))
        .toList();
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

  Future<Uint8List> downloadSftpFile(String remotePath) async {
    return SftpService.instance.downloadFile(remotePath);
  }

  Future<void> updateSftpFile(String remotePath, Uint8List bytes) async {
    await SftpService.instance.uploadBytes(bytes, remotePath);
  }

  Future<String> uploadNewFileToSftp(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    return SftpService.instance.uploadNewFile(bytes, folderPath, fileName);
  }

  Future<DateTime?> getSftpFileModifiedTime(String remotePath) async {
    return SftpService.instance.getFileModifiedTime(remotePath);
  }

  Future<DateTime?> getS3FileModifiedTime(String key) async {
    return S3Service.instance.getObjectLastModified(key);
  }

  // ── S3 file operations ────────────────────────────────────────────────────

  Future<List<CloudFolder>> listS3Folders({String? parentId}) async {
    final prefix = parentId ?? S3Service.instance.currentRootPath ?? '';
    final prefixes = await S3Service.instance.listPrefixes(prefix: prefix);
    return prefixes.map((p) {
      final segments = p.split('/').where((s) => s.isNotEmpty).toList();
      final name = segments.isNotEmpty ? segments.last : p;
      return CloudFolder(id: p, name: name, path: p);
    }).toList();
  }

  Future<List<CloudFile>> listS3Files({String? parentId}) async {
    final prefix = parentId ?? S3Service.instance.currentRootPath ?? '';
    final result = await S3Service.instance.listObjects(
      prefix: prefix,
      delimiter: '/',
    );
    return result.objects
        .where((o) => o.key.endsWith('.kdbx') || o.key.endsWith('.kdb'))
        .map(
          (o) => CloudFile(id: o.key, name: o.key.split('/').last, path: o.key),
        )
        .toList();
  }

  Future<Uint8List> downloadS3File(String key) async {
    return S3Service.instance.downloadObject(key);
  }

  Future<void> updateS3File(String key, Uint8List bytes) async {
    await S3Service.instance.uploadObject(key, bytes);
  }

  Future<String> uploadNewFileToS3(
    Uint8List bytes,
    String folderPath,
    String fileName,
  ) async {
    final normalizedPrefix = folderPath.endsWith('/') || folderPath.isEmpty
        ? folderPath
        : '$folderPath/';
    final key = '$normalizedPrefix$fileName';
    await S3Service.instance.uploadObject(key, bytes);
    return key;
  }

  // ── PKCE helpers ──────────────────────────────────────────────────────────

  String _generatePkceVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _generatePkceChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  // ── Cloud credential validation ─────────────────────────────────────────────

  /// Probes whether the cloud credentials backing [storageType] are still
  /// usable. Conservative: it never triggers an interactive sign-in, only a
  /// cheap read-only API call using whatever token is already on disk.

  Future<CloudCredentialResult> verifyCloudCredentialsForStorage(
    String storageType,
  ) async {
    // Wait for the fire-and-forget init() kicked off from main() to finish
    // restoring credentials from secure storage. Without this, a cold-start
    // health probe can read a half-restored state (e.g. `_sftpConfig == null`)
    // and wrongly report the provider as "not connected" until a manual
    // refresh — the exact SFTP bug this guards against.
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
        return const CloudCredentialResult(CloudCredentialStatus.notApplicable);
    }
  }

  Future<CloudCredentialResult> _verifyGoogleDriveCredentials() async {
    const provider = 'Google Drive';
    try {
      var account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      if (account == null) {
        return const CloudCredentialResult(
          CloudCredentialStatus.notSignedIn,
          providerLabel: provider,
          message:
              'Google Drive is no longer connected on this device. '
              'Reconnect to keep this vault in sync.',
        );
      }
      final headers = await account.authHeaders;
      final response = await http
          .get(
            Uri.parse(
              'https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)',
            ),
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
            'Google Drive returned ${response.statusCode}. Sync may not '
            'work until the service is reachable again.',
      );
    } on TimeoutException {
      return const CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach Google Drive. You can keep working offline; '
            'sync will resume when connectivity returns.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach Google Drive ($e). You can keep working '
            'offline; sync will resume when connectivity returns.',
      );
    } catch (e) {
      debugPrint('[CloudDatabaseService] Google credential check failed: $e');
      return CloudCredentialResult(
        CloudCredentialStatus.authExpired,
        providerLabel: provider,
        message:
            'Could not validate Google Drive credentials. Reconnect to '
            'make sure this vault keeps syncing. ($e)',
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
        message:
            'Dropbox is no longer connected on this device. Reconnect to '
            'keep this vault in sync.',
      );
    }
    try {
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
              'Dropbox rejected the saved access token. Reconnect Dropbox '
              'so this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Dropbox returned ${response.statusCode}. Sync may not work '
            'until the service is reachable again.',
      );
    } on TimeoutException {
      return const CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach Dropbox. You can keep working offline; sync '
            'will resume when connectivity returns.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach Dropbox ($e). You can keep working offline; '
            'sync will resume when connectivity returns.',
      );
    } catch (e) {
      debugPrint('[CloudDatabaseService] Dropbox credential check failed: $e');
      return CloudCredentialResult(
        CloudCredentialStatus.authExpired,
        providerLabel: provider,
        message:
            'Could not validate Dropbox credentials. Reconnect to make '
            'sure this vault keeps syncing. ($e)',
      );
    }
  }

  Future<CloudCredentialResult> _verifyOneDriveCredentials() async {
    const provider = 'OneDrive';
    if (_oneDriveAccessToken == null || _oneDriveAccessToken!.isEmpty) {
      return const CloudCredentialResult(
        CloudCredentialStatus.notSignedIn,
        providerLabel: provider,
        message:
            'OneDrive is no longer connected on this device. Reconnect to '
            'keep this vault in sync.',
      );
    }
    try {
      // Refreshes transparently when within 5 minutes of expiry.
      final headers = await _oneDriveAuthHeaders();
      final response = await http
          .get(Uri.parse('$_kGraphBaseUrl/me'), headers: headers)
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
              'OneDrive rejected the saved access token. Reconnect '
              'OneDrive so this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'OneDrive returned ${response.statusCode}. Sync may not work '
            'until the service is reachable again.',
      );
    } on TimeoutException {
      return const CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach OneDrive. You can keep working offline; sync '
            'will resume when connectivity returns.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach OneDrive ($e). You can keep working offline; '
            'sync will resume when connectivity returns.',
      );
    } catch (e) {
      debugPrint('[CloudDatabaseService] OneDrive credential check failed: $e');
      return CloudCredentialResult(
        CloudCredentialStatus.authExpired,
        providerLabel: provider,
        message:
            'Could not validate OneDrive credentials. Reconnect to make '
            'sure this vault keeps syncing. ($e)',
      );
    }
  }

  Future<CloudCredentialResult> _verifyWebDavCredentials() async {
    const provider = 'WebDAV';
    final config = WebDavService.instance.config;
    if (config == null) {
      return const CloudCredentialResult(
        CloudCredentialStatus.notSignedIn,
        providerLabel: provider,
        message:
            'WebDAV is not configured on this device. Reconnect to keep '
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
        message:
            'Could not reach the WebDAV server. You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach the WebDAV server ($e). You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    } catch (e) {
      final text = e.toString();
      final isAuth =
          text.contains('Authentication failed') ||
          text.contains('401') ||
          text.contains('403');
      if (isAuth) {
        return const CloudCredentialResult(
          CloudCredentialStatus.authExpired,
          providerLabel: provider,
          message:
              'The WebDAV server rejected the saved credentials. '
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
    final config = SftpService.instance.config;
    if (config == null) {
      return const CloudCredentialResult(
        CloudCredentialStatus.notSignedIn,
        providerLabel: provider,
        message:
            'SFTP is not configured on this device. Reconnect to keep '
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
        message:
            'Could not reach the SFTP server. You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    } on SocketException catch (e) {
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach the SFTP server ($e). You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    } catch (e) {
      final text = e.toString();
      final isAuth =
          text.contains('Authentication failed') ||
          text.contains('auth') ||
          text.contains('permission') ||
          text.contains('denied');
      if (isAuth) {
        return const CloudCredentialResult(
          CloudCredentialStatus.authExpired,
          providerLabel: provider,
          message:
              'The SFTP server rejected the saved credentials. '
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
        message:
            'Amazon S3 is not configured on this device. Reconnect to keep '
            'this vault in sync.',
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
          message:
              'The S3 server rejected the saved credentials. '
              'Reconnect so this vault can sync again.',
        );
      }
      return CloudCredentialResult(
        CloudCredentialStatus.networkError,
        providerLabel: provider,
        message:
            'Could not reach Amazon S3. You can keep working '
            'offline; sync will resume when it is reachable again.',
      );
    }
  }
}

// ── Google auth HTTP client ────────────────────────────────────────────────────

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);
  final Map<String, String> _headers;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request..headers.addAll(_headers));
  }
}
