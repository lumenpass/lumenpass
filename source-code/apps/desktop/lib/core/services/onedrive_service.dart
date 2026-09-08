import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Model classes
// ---------------------------------------------------------------------------

class OneDriveAuthResult {
  const OneDriveAuthResult({
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });
  final String email;
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
}

class OneDriveFolder {
  const OneDriveFolder({required this.id, required this.name, this.path});
  final String id;
  final String name;
  final String? path;
}

class OneDriveFile {
  const OneDriveFile({
    required this.id,
    required this.name,
    this.path,
    this.size,
    this.lastModified,
  });
  final String id;
  final String name;
  final String? path;
  final int? size;
  final DateTime? lastModified;
}

// ---------------------------------------------------------------------------
// OneDriveService
// ---------------------------------------------------------------------------

class OneDriveService {
  OneDriveService._();
  static final OneDriveService instance = OneDriveService._();

  // -------------------------------------------------------------------------
  // Constants
  // -------------------------------------------------------------------------

  static const String _kOneDriveClientId =
      String.fromEnvironment('ONEDRIVE_CLIENT_ID');

  static bool get isConfigured => _kOneDriveClientId.isNotEmpty;

  static const String _authEndpoint =
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize';
  static const String _tokenEndpoint =
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';
  static const String _graphBaseUrl = 'https://graph.microsoft.com/v1.0';
  static const String _scopes = 'Files.ReadWrite.All offline_access User.Read';
  static const String defaultFolderName = 'LumenPass';
  static const int _authPort = 17824;
  static const String _redirectUri = 'http://localhost:$_authPort/callback';

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;

  String? get currentAccessToken {
    if (_accessToken == null) return null;
    if (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!)) {
      return null;
    }
    return _accessToken;
  }

  /// The latest refresh token, if any. Exposed so callers can persist the
  /// rotated token after a silent refresh.
  String? get currentRefreshToken => _refreshToken;

  /// The current access-token expiry, if known.
  DateTime? get tokenExpiry => _tokenExpiry;

  bool get isConnected => _accessToken != null;

  /// Ensures the in-memory access token is still fresh, transparently
  /// refreshing it when it has expired (or is about to). Returns the valid
  /// access token, or `null` when there is nothing to refresh with.
  ///
  /// Unlike [_authHeaders] this is safe to call from credential health checks
  /// because it never throws when the token simply cannot be refreshed.
  Future<String?> ensureFreshAccessToken() async {
    if (_accessToken == null) return null;
    final expiresSoon = _tokenExpiry != null &&
        DateTime.now()
            .isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)));
    if (expiresSoon) {
      if (_refreshToken == null) return null;
      await refreshAccessToken();
    }
    return _accessToken;
  }

  // -------------------------------------------------------------------------
  // OAuth2 PKCE Flow
  // -------------------------------------------------------------------------

  Future<OneDriveAuthResult> connect() async {
    // Generate PKCE code verifier (43-128 chars, URL-safe random)
    final random = Random.secure();
    final codeVerifier = List.generate(
      64,
      (_) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'[
          random.nextInt(66)],
    ).join();

    // Generate code challenge (SHA256 of verifier, base64url-encoded)
    final codeChallenge = base64Url
        .encode(sha256.convert(utf8.encode(codeVerifier)).bytes)
        .replaceAll('=', '');

    debugPrint('[OneDrive] Starting OAuth2 PKCE flow...');

    // Start local HTTP server
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _authPort);
    debugPrint('[OneDrive] Local server listening on port $_authPort');

    final completer = Completer<String>();

    // Listen for the callback
    final subscription = server.listen((HttpRequest request) async {
      if (request.uri.path != '/callback') {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found')
          ..close();
        return;
      }

      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      if (error != null) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_errorHtml(error, request.uri.queryParameters['error_description']))
          ..close();
        if (!completer.isCompleted) {
          completer.completeError(Exception(
            '[OneDrive] Authorization error: $error - ${request.uri.queryParameters['error_description']}',
          ));
        }
        return;
      }

      if (code == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.html
          ..write(_errorHtml('missing_code', 'No authorization code received'))
          ..close();
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('[OneDrive] No authorization code in callback'),
          );
        }
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_successHtml())
        ..close();

      if (!completer.isCompleted) {
        completer.complete(code);
      }
    });

    // Build authorization URL
    final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: {
      'client_id': _kOneDriveClientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': _scopes,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });

    // Open browser
    final launched = await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    if (!launched) {
      await subscription.cancel();
      await server.close();
      throw Exception('[OneDrive] Failed to open browser for authentication');
    }

    debugPrint('[OneDrive] Browser opened, waiting for callback...');

    // Wait for auth code with timeout
    String authCode;
    try {
      authCode = await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw TimeoutException(
            '[OneDrive] Authentication timed out after 120 seconds. '
            'Please ensure the redirect URI ($_redirectUri) is configured '
            'in your Microsoft Azure app registration.',
          );
        },
      );
    } finally {
      await subscription.cancel();
      await server.close();
      debugPrint('[OneDrive] Local server closed');
    }

    debugPrint('[OneDrive] Authorization code received, exchanging for tokens...');

    // Exchange code for tokens
    final tokenResponse = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': authCode,
        'redirect_uri': _redirectUri,
        'client_id': _kOneDriveClientId,
        'code_verifier': codeVerifier,
      },
    );

    if (tokenResponse.statusCode != 200) {
      throw Exception(
        '[OneDrive] Token exchange failed (${tokenResponse.statusCode}): ${tokenResponse.body}',
      );
    }

    final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    _accessToken = tokenData['access_token'] as String;
    _refreshToken = tokenData['refresh_token'] as String?;
    final expiresIn = tokenData['expires_in'] as int;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    debugPrint('[OneDrive] Tokens received, fetching user profile...');

    // Fetch user profile
    final profileResponse = await http.get(
      Uri.parse('$_graphBaseUrl/me'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (profileResponse.statusCode != 200) {
      throw Exception(
        '[OneDrive] Failed to fetch user profile (${profileResponse.statusCode}): ${profileResponse.body}',
      );
    }

    final profile = jsonDecode(profileResponse.body) as Map<String, dynamic>;
    final email = (profile['mail'] ?? profile['userPrincipalName'] ?? '') as String;

    debugPrint('[OneDrive] Connected as: $email');

    return OneDriveAuthResult(
      email: email,
      accessToken: _accessToken!,
      refreshToken: _refreshToken,
      expiresAt: _tokenExpiry!,
    );
  }

  // -------------------------------------------------------------------------
  // Token Refresh
  // -------------------------------------------------------------------------

  Future<void> refreshAccessToken() async {
    if (_refreshToken == null) {
      throw Exception('[OneDrive] No refresh token available');
    }

    debugPrint('[OneDrive] Refreshing access token...');

    final response = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
        'client_id': _kOneDriveClientId,
        'scope': _scopes,
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        '[OneDrive] Token refresh failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    if (data['refresh_token'] != null) {
      _refreshToken = data['refresh_token'] as String;
    }
    final expiresIn = data['expires_in'] as int;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    debugPrint('[OneDrive] Token refreshed successfully');
  }

  // -------------------------------------------------------------------------
  // Auth Headers (ensures valid token)
  // -------------------------------------------------------------------------

  Future<Map<String, String>> _authHeaders() async {
    if (_accessToken == null) {
      throw Exception('[OneDrive] Not connected. Call connect() first.');
    }

    // Refresh if token expires within 5 minutes
    if (_tokenExpiry != null &&
        DateTime.now().isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      await refreshAccessToken();
    }

    return {'Authorization': 'Bearer $_accessToken'};
  }

  // -------------------------------------------------------------------------
  // Disconnect
  // -------------------------------------------------------------------------

  void disconnect() {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    debugPrint('[OneDrive] Disconnected');
  }

  // -------------------------------------------------------------------------
  // Restore Tokens
  // -------------------------------------------------------------------------

  void restoreTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _tokenExpiry = expiry;
    debugPrint('[OneDrive] Tokens restored');
  }

  // -------------------------------------------------------------------------
  // List Folders
  // -------------------------------------------------------------------------

  Future<List<OneDriveFolder>> listFolders({String? parentId}) async {
    final headers = await _authHeaders();

    final String url;
    if (parentId == null) {
      url = '$_graphBaseUrl/me/drive/root/children?\$select=id,name,folder,parentReference';
    } else {
      url = '$_graphBaseUrl/me/drive/items/$parentId/children?\$select=id,name,folder,parentReference';
    }

    debugPrint('[OneDrive] Listing folders: $url');

    final response = await http.get(Uri.parse(url), headers: headers);

    if (response.statusCode != 200) {
      throw Exception(
        '[OneDrive] Failed to list folders (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['value'] as List<dynamic>?) ?? [];

    return items
        .where((item) => (item as Map<String, dynamic>).containsKey('folder'))
        .map((item) {
      final map = item as Map<String, dynamic>;
      final parentRef = map['parentReference'] as Map<String, dynamic>?;
      final path = parentRef?['path'] as String?;
      return OneDriveFolder(
        id: map['id'] as String,
        name: map['name'] as String,
        path: path,
      );
    }).toList();
  }

  // -------------------------------------------------------------------------
  // List Files
  // -------------------------------------------------------------------------

  Future<List<OneDriveFile>> listFiles({String? parentId, String? extension}) async {
    final headers = await _authHeaders();

    final String url;
    if (parentId == null) {
      url = '$_graphBaseUrl/me/drive/root/children?\$select=id,name,file,folder,size,lastModifiedDateTime,parentReference';
    } else {
      url = '$_graphBaseUrl/me/drive/items/$parentId/children?\$select=id,name,file,folder,size,lastModifiedDateTime,parentReference';
    }

    debugPrint('[OneDrive] Listing files: $url');

    final response = await http.get(Uri.parse(url), headers: headers);

    if (response.statusCode != 200) {
      throw Exception(
        '[OneDrive] Failed to list files (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['value'] as List<dynamic>?) ?? [];

    var files = items
        .where((item) => (item as Map<String, dynamic>).containsKey('file'))
        .map((item) {
      final map = item as Map<String, dynamic>;
      final parentRef = map['parentReference'] as Map<String, dynamic>?;
      final path = parentRef?['path'] as String?;
      final lastModifiedStr = map['lastModifiedDateTime'] as String?;
      return OneDriveFile(
        id: map['id'] as String,
        name: map['name'] as String,
        path: path,
        size: map['size'] as int?,
        lastModified: lastModifiedStr != null ? DateTime.tryParse(lastModifiedStr) : null,
      );
    }).toList();

    if (extension != null) {
      files = files.where((f) => f.name.endsWith(extension)).toList();
    }

    return files;
  }

  // -------------------------------------------------------------------------
  // Upload File
  // -------------------------------------------------------------------------

  Future<void> uploadBytes(Uint8List bytes, String itemId, String fileName) async {
    final headers = await _authHeaders();

    if (bytes.length < 4 * 1024 * 1024) {
      // Simple upload for files < 4MB — overwrite existing item by ID
      debugPrint('[OneDrive] Simple upload: $fileName (${bytes.length} bytes)');

      final url = '$_graphBaseUrl/me/drive/items/$itemId/content';
      final response = await http.put(
        Uri.parse(url),
        headers: {
          ...headers,
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          '[OneDrive] Upload failed (${response.statusCode}): ${response.body}',
        );
      }

      debugPrint('[OneDrive] Upload complete: $fileName');
    } else {
      // Upload session for files >= 4MB
      debugPrint('[OneDrive] Creating upload session: $fileName (${bytes.length} bytes)');

      final sessionUrl = '$_graphBaseUrl/me/drive/items/$itemId/createUploadSession';
      final sessionResponse = await http.post(
        Uri.parse(sessionUrl),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'item': {
            '@microsoft.graph.conflictBehavior': 'replace',
            'name': fileName,
          },
        }),
      );

      if (sessionResponse.statusCode != 200) {
        throw Exception(
          '[OneDrive] Failed to create upload session (${sessionResponse.statusCode}): ${sessionResponse.body}',
        );
      }

      final sessionData = jsonDecode(sessionResponse.body) as Map<String, dynamic>;
      final uploadUrl = sessionData['uploadUrl'] as String;

      // Upload in 320KB chunks
      const chunkSize = 320 * 1024;
      var offset = 0;

      while (offset < bytes.length) {
        final end = (offset + chunkSize).clamp(0, bytes.length);
        final chunk = bytes.sublist(offset, end);

        debugPrint('[OneDrive] Uploading chunk: $offset-${end - 1}/${bytes.length}');

        final chunkResponse = await http.put(
          Uri.parse(uploadUrl),
          headers: {
            'Content-Length': chunk.length.toString(),
            'Content-Range': 'bytes $offset-${end - 1}/${bytes.length}',
          },
          body: chunk,
        );

        if (chunkResponse.statusCode != 202 &&
            chunkResponse.statusCode != 200 &&
            chunkResponse.statusCode != 201) {
          throw Exception(
            '[OneDrive] Chunk upload failed (${chunkResponse.statusCode}): ${chunkResponse.body}',
          );
        }

        offset = end;
      }

      debugPrint('[OneDrive] Upload session complete: $fileName');
    }
  }

  // -------------------------------------------------------------------------
  // Download File
  // -------------------------------------------------------------------------

  Future<Uint8List> downloadFile(String itemId) async {
    final headers = await _authHeaders();

    final url = '$_graphBaseUrl/me/drive/items/$itemId/content';
    debugPrint('[OneDrive] Downloading file: $itemId');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);
      request.followRedirects = true;

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 302) {
        final body = await streamedResponse.stream.bytesToString();
        throw Exception(
          '[OneDrive] Download failed (${streamedResponse.statusCode}): $body',
        );
      }

      final bytes = await streamedResponse.stream.toBytes();
      debugPrint('[OneDrive] Downloaded ${bytes.length} bytes');
      return Uint8List.fromList(bytes);
    } finally {
      client.close();
    }
  }

  // -------------------------------------------------------------------------
  // Get File Modified Time
  // -------------------------------------------------------------------------

  Future<DateTime?> getFileModifiedTime(String itemId) async {
    final headers = await _authHeaders();

    final url = '$_graphBaseUrl/me/drive/items/$itemId?\$select=lastModifiedDateTime';
    debugPrint('[OneDrive] Getting modified time for: $itemId');

    final response = await http.get(Uri.parse(url), headers: headers);

    if (response.statusCode != 200) {
      throw Exception(
        '[OneDrive] Failed to get file info (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final lastModifiedStr = data['lastModifiedDateTime'] as String?;

    if (lastModifiedStr == null) return null;
    return DateTime.tryParse(lastModifiedStr);
  }

  // -------------------------------------------------------------------------
  // Create Folder
  // -------------------------------------------------------------------------

  Future<String> createFolder(String parentId, String name) async {
    final headers = await _authHeaders();

    final url = '$_graphBaseUrl/me/drive/items/$parentId/children';
    debugPrint('[OneDrive] Creating folder: $name in $parentId');

    final response = await http.post(
      Uri.parse(url),
      headers: {
        ...headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        '@microsoft.graph.conflictBehavior': 'fail',
        'folder': <String, dynamic>{},
      }),
    );

    // 409 Conflict means the folder already exists — find it and return its id.
    if (response.statusCode == 409) {
      debugPrint('[OneDrive] Folder "$name" already exists, resolving id...');
      final folders = await listFolders(parentId: parentId == 'root' ? null : parentId);
      final match = folders.where((f) => f.name == name).toList();
      if (match.isNotEmpty) {
        debugPrint('[OneDrive] Resolved existing folder id: ${match.first.id}');
        return match.first.id;
      }
      // Fallback: couldn't find it by name, throw original error
      throw Exception(
        '[OneDrive] Folder conflict but could not resolve existing folder: ${response.body}',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        '[OneDrive] Failed to create folder (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final folderId = data['id'] as String;
    debugPrint('[OneDrive] Folder created: $folderId');
    return folderId;
  }

  // -------------------------------------------------------------------------
  // Upload New File to Folder
  // -------------------------------------------------------------------------

  Future<String> uploadNewFile(Uint8List bytes, String folderId, String fileName) async {
    final headers = await _authHeaders();

    final url = '$_graphBaseUrl/me/drive/items/$folderId:/$fileName:/content';
    debugPrint('[OneDrive] Uploading new file: $fileName to folder $folderId');

    final response = await http.put(
      Uri.parse(url),
      headers: {
        ...headers,
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        '[OneDrive] Failed to upload file (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final fileId = data['id'] as String;
    debugPrint('[OneDrive] File uploaded: $fileId');
    return fileId;
  }

  // -------------------------------------------------------------------------
  // HTML Templates
  // -------------------------------------------------------------------------

  String _successHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <title>LumenPass - OneDrive Connected</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: #f5f5f5; }
    .container { text-align: center; padding: 40px; background: white; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    .icon { font-size: 48px; margin-bottom: 16px; }
    h1 { color: #0078d4; margin-bottom: 8px; }
    p { color: #666; }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">&#10004;</div>
    <h1>Connected to OneDrive</h1>
    <p>You can close this window and return to LumenPass.</p>
  </div>
</body>
</html>
''';
  }

  String _errorHtml(String error, String? description) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <title>LumenPass - OneDrive Error</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: #f5f5f5; }
    .container { text-align: center; padding: 40px; background: white; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    .icon { font-size: 48px; margin-bottom: 16px; }
    h1 { color: #d32f2f; margin-bottom: 8px; }
    p { color: #666; }
    .error { color: #999; font-size: 12px; margin-top: 16px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">&#10060;</div>
    <h1>Connection Failed</h1>
    <p>${description ?? 'An error occurred during authentication.'}</p>
    <p class="error">Error: $error</p>
    <p>Please close this window and try again in LumenPass.</p>
  </div>
</body>
</html>
''';
  }
}
