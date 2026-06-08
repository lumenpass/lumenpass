import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around [LocalAuthentication] for biometric unlock.
class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true if the device can perform biometric or device-credential auth.
  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompts the user to authenticate. Returns true on success.
  Future<bool> authenticate({
    String reason = 'Authenticate to unlock your vault',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricAuthServiceProvider = Provider<BiometricAuthService>(
  (_) => BiometricAuthService(),
);
