import 'dart:io';

import 'google_auth_linux.dart';
import 'google_auth_macos.dart';
import 'google_auth_windows.dart';

/// Bearer-token credentials for a signed-in Google account.
///
/// Implementations are responsible for transparently refreshing the access
/// token before [authHeaders] returns when it's close to expiry.
abstract class GoogleCredentials {
  String get email;
  Future<Map<String, String>> get authHeaders;
}

/// Platform-agnostic Google OAuth surface used by `BackupService`.
///
/// All three desktop platforms route through the same loopback PKCE OAuth
/// flow because the official `google_sign_in` plugin has no working
/// implementation on Windows or Linux, and the iOS pod is intentionally
/// excluded from the macOS build (see `macos/Podfile`).
abstract class GoogleAuth {
  GoogleCredentials? get currentUser;

  bool get isConnected => currentUser != null;
  String? get currentEmail => currentUser?.email;

  /// Launches the system browser, performs a PKCE OAuth exchange against
  /// `127.0.0.1:<port>/callback`, and persists a refresh token.
  Future<GoogleCredentials?> signIn();

  /// Hydrates persisted credentials from disk and refreshes them if needed.
  /// Returns `null` when no usable credentials exist.
  Future<GoogleCredentials?> signInSilently();

  /// Revokes the current refresh/access token (best effort) and clears any
  /// persisted state. Safe to call when not signed in.
  Future<void> signOut();
}

/// Returns the [GoogleAuth] implementation appropriate for the current
/// desktop platform. Throws on unsupported platforms.
GoogleAuth googleAuthFor({
  required String clientId,
  String? clientSecret,
  required List<String> scopes,
}) {
  if (Platform.isMacOS) {
    return MacOSGoogleAuth(
      clientId: clientId,
      clientSecret: clientSecret,
      scopes: scopes,
    );
  }
  if (Platform.isWindows) {
    return WindowsGoogleAuth(
      clientId: clientId,
      clientSecret: clientSecret,
      scopes: scopes,
    );
  }
  if (Platform.isLinux) {
    return LinuxGoogleAuth(
      clientId: clientId,
      clientSecret: clientSecret,
      scopes: scopes,
    );
  }
  throw UnsupportedError(
    'GoogleAuth is not implemented for ${Platform.operatingSystem}',
  );
}
