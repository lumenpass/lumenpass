import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'google_auth.dart';

/// macOS Google OAuth.
///
/// The official `google_sign_in` plugin's iOS pod is intentionally stripped
/// from the macOS build (see `macos/Podfile`) because Flutter does not
/// auto-link FlutterMacOS into iOS-only plugin pods, which leaves the
/// `FLTGoogleSignInPlugin` symbols unresolved at link time. macOS therefore
/// uses Google's "loopback IP address" desktop OAuth flow with PKCE:
///   1. Bind a local HTTP server on a fixed loopback port.
///   2. Open the system browser to the Google authorization URL pointing
///      back at `http://127.0.0.1:<port>/callback`.
///   3. Exchange the returned code for an access + refresh token.
///   4. Persist the refresh token in the app's support directory so we
///      can refresh access transparently in later sessions.
///
/// Requires the `com.apple.security.network.client` and
/// `com.apple.security.network.server` entitlements in the macOS sandbox.
class MacOSGoogleAuth implements GoogleAuth {
  MacOSGoogleAuth({
    required this.clientId,
    this.clientSecret,
    required this.scopes,
  });

  final String clientId;
  final String? clientSecret;
  final List<String> scopes;

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _userInfoEndpoint =
      'https://www.googleapis.com/oauth2/v3/userinfo';
  static const _revokeEndpoint = 'https://oauth2.googleapis.com/revoke';

  /// Fixed loopback port shared with the Windows / Linux flows so a single
  /// Authorized redirect URI works in Google Cloud Console.
  ///
  /// Register BOTH of these URIs as Authorized redirect URIs on the client
  /// (Google treats `localhost` and `127.0.0.1` as different strings):
  ///   http://127.0.0.1:17824/callback
  ///   http://localhost:17824/callback
  static const int _redirectPort = 17824;
  static const String _redirectUri =
      'http://127.0.0.1:$_redirectPort/callback';

  static const _persistedFileName = 'macos_google_auth.json';

  _MacOSGoogleCredentials? _currentUser;
  bool _hydrated = false;

  @override
  GoogleCredentials? get currentUser => _currentUser;

  @override
  bool get isConnected => _currentUser != null;

  @override
  String? get currentEmail => _currentUser?.email;

  @override
  Future<GoogleCredentials?> signIn() async {
    if (clientId.isEmpty) {
      throw Exception(
        'GOOGLE_CLIENT_ID not configured. '
        'Pass it via --dart-define=GOOGLE_CLIENT_ID=<your_client_id>',
      );
    }

    final verifier = _generatePkceVerifier();
    final challenge = _generatePkceChallenge(verifier);

    HttpServer? server;
    try {
      try {
        server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          _redirectPort,
          shared: true,
        );
      } on SocketException catch (e) {
        throw Exception(
          'Could not bind the local Google OAuth callback server on '
          '$_redirectUri ($e). If a previous sign-in attempt is still in '
          'progress wait a moment and try again, or make sure no other app '
          'is using port $_redirectPort.',
        );
      }
      final redirectUri = _redirectUri;

      final authUri = Uri.parse(_authEndpoint).replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopes.join(' '),
        'access_type': 'offline',
        'prompt': 'consent',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      });

      debugPrint(
        '[MacOSGoogleAuth] starting Google OAuth — redirect_uri=$redirectUri',
      );

      final ok = await launchUrl(authUri, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw Exception(
          'Could not open the browser for Google sign-in.',
        );
      }

      final codeCompleter = Completer<String>();
      final timeout = Timer(const Duration(minutes: 3), () {
        if (!codeCompleter.isCompleted) {
          codeCompleter.completeError(
            Exception('Google sign-in timed out. Please try again.'),
          );
        }
      });

      unawaited(() async {
        try {
          await for (final request in server!) {
            if (request.requestedUri.path != '/callback') {
              request.response
                ..statusCode = 404
                ..headers.set('content-type', 'text/plain; charset=utf-8')
                ..write('Not found');
              await request.response.close();
              continue;
            }

            final qp = request.requestedUri.queryParameters;
            final error = qp['error'];
            final code = qp['code'];

            if (error != null && error.isNotEmpty) {
              request.response
                ..statusCode = 400
                ..headers.set('content-type', 'text/html; charset=utf-8')
                ..write(
                  '<html><body style="font-family:sans-serif;padding:40px">'
                  '<h2>LumenPass — Google sign-in failed</h2>'
                  '<p>$error</p>'
                  '</body></html>',
                );
              await request.response.close();
              if (!codeCompleter.isCompleted) {
                codeCompleter.completeError(
                  Exception('Google authorization error: $error'),
                );
              }
              break;
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
                '<h2>LumenPass — Google connected ✓</h2>'
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
              Exception('Google OAuth callback server stopped unexpectedly.'),
            );
          }
        }
      }());

      final code = await codeCompleter.future;
      timeout.cancel();

      final tokenBody = <String, String>{
        'code': code,
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      };
      if (clientSecret != null && clientSecret!.isNotEmpty) {
        tokenBody['client_secret'] = clientSecret!;
      }

      final tokenRes = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: tokenBody,
      );
      if (tokenRes.statusCode != 200) {
        throw Exception(
            'Google token exchange failed (${tokenRes.statusCode}): ${tokenRes.body}');
      }
      final tokenData = jsonDecode(tokenRes.body) as Map<String, dynamic>;
      final accessToken = tokenData['access_token'] as String?;
      final refreshToken = tokenData['refresh_token'] as String?;
      final expiresIn = (tokenData['expires_in'] as num?)?.toInt() ?? 3600;
      if (accessToken == null) {
        throw Exception('Google token response missing access_token');
      }

      final email = await _fetchEmail(accessToken);
      final expiry = DateTime.now().add(Duration(seconds: expiresIn));

      final creds = _MacOSGoogleCredentials._(
        owner: this,
        email: email,
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiry: expiry,
      );
      _currentUser = creds;
      await _persist();
      return creds;
    } finally {
      await server?.close(force: true);
    }
  }

  @override
  Future<GoogleCredentials?> signInSilently() async {
    if (!_hydrated) {
      await _hydrateFromDisk();
    }
    final current = _currentUser;
    if (current == null) return null;
    if (DateTime.now()
        .isBefore(current._expiry.subtract(const Duration(minutes: 1)))) {
      return current;
    }
    final refreshed = await _refreshAccessToken(current);
    return refreshed;
  }

  @override
  Future<void> signOut() async {
    final user = _currentUser;
    final token = user?._refreshToken ?? user?._accessToken;
    if (token != null && token.isNotEmpty) {
      try {
        await http.post(
          Uri.parse(_revokeEndpoint),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'token': token},
        );
      } catch (e) {
        debugPrint('[MacOSGoogleAuth] revoke failed: $e');
      }
    }
    _currentUser = null;
    await _clearPersistedFile();
  }

  Future<_MacOSGoogleCredentials?> _refreshAccessToken(
      _MacOSGoogleCredentials creds) async {
    final refreshToken = creds._refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      _currentUser = null;
      await _clearPersistedFile();
      return null;
    }
    final body = <String, String>{
      'client_id': clientId,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    };
    if (clientSecret != null && clientSecret!.isNotEmpty) {
      body['client_secret'] = clientSecret!;
    }
    try {
      final res = await http.post(
        Uri.parse(_tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
      if (res.statusCode != 200) {
        debugPrint(
            '[MacOSGoogleAuth] refresh failed (${res.statusCode}): ${res.body}');
        _currentUser = null;
        await _clearPersistedFile();
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      if (accessToken == null) {
        _currentUser = null;
        await _clearPersistedFile();
        return null;
      }
      creds._accessToken = accessToken;
      creds._expiry = DateTime.now().add(Duration(seconds: expiresIn));
      await _persist();
      return creds;
    } catch (e) {
      debugPrint('[MacOSGoogleAuth] refresh error: $e');
      return null;
    }
  }

  Future<String> _fetchEmail(String accessToken) async {
    try {
      final res = await http.get(
        Uri.parse(_userInfoEndpoint),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return (data['email'] as String?) ?? 'Connected';
      }
    } catch (e) {
      debugPrint('[MacOSGoogleAuth] userinfo failed: $e');
    }
    return 'Connected';
  }

  Future<File> _persistedFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _persistedFileName));
  }

  Future<void> _persist() async {
    final user = _currentUser;
    if (user == null) {
      await _clearPersistedFile();
      return;
    }
    try {
      final file = await _persistedFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'email': user.email,
        'access_token': user._accessToken,
        'refresh_token': user._refreshToken,
        'expiry': user._expiry.toIso8601String(),
      }));
    } catch (e) {
      debugPrint('[MacOSGoogleAuth] persist failed: $e');
    }
  }

  Future<void> _hydrateFromDisk() async {
    _hydrated = true;
    try {
      final file = await _persistedFile();
      if (!await file.exists()) return;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final email = data['email'] as String? ?? 'Connected';
      final accessToken = data['access_token'] as String? ?? '';
      final refreshToken = data['refresh_token'] as String?;
      final expiry = DateTime.tryParse(data['expiry'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (accessToken.isEmpty &&
          (refreshToken == null || refreshToken.isEmpty)) {
        return;
      }
      _currentUser = _MacOSGoogleCredentials._(
        owner: this,
        email: email,
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiry: expiry,
      );
    } catch (e) {
      debugPrint('[MacOSGoogleAuth] hydrate failed: $e');
    }
  }

  Future<void> _clearPersistedFile() async {
    try {
      final file = await _persistedFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  String _generatePkceVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _generatePkceChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}

class _MacOSGoogleCredentials implements GoogleCredentials {
  _MacOSGoogleCredentials._({
    required MacOSGoogleAuth owner,
    required this.email,
    required String accessToken,
    required String? refreshToken,
    required DateTime expiry,
  })  : _owner = owner,
        _accessToken = accessToken,
        _refreshToken = refreshToken,
        _expiry = expiry;

  final MacOSGoogleAuth _owner;
  @override
  final String email;
  String _accessToken;
  final String? _refreshToken;
  DateTime _expiry;

  @override
  Future<Map<String, String>> get authHeaders async {
    if (DateTime.now().isAfter(_expiry.subtract(const Duration(minutes: 1)))) {
      await _owner._refreshAccessToken(this);
    }
    return {'Authorization': 'Bearer $_accessToken'};
  }
}
