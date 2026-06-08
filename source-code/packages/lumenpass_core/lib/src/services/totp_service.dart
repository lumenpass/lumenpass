import 'package:otp/otp.dart';

/// Parses otpauth URIs and produces the current TOTP code.
class TOTPService {
  const TOTPService();

  String? generateCode(String? otpAuthUrl, {DateTime? timestamp}) {
    if (otpAuthUrl == null || otpAuthUrl.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(otpAuthUrl);
    if (uri == null || uri.scheme != 'otpauth') {
      return null;
    }

    final secret = uri.queryParameters['secret'];
    if (secret == null || secret.isEmpty) {
      return null;
    }

    final period = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;
    final digits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
    final algorithm = _parseAlgorithm(uri.queryParameters['algorithm']);

    // The `otp` package throws a [FormatException] (e.g. "Invalid Base32
    // characters") when the secret is not valid Base32. Callers may invoke
    // this during a widget build, so swallow the error and return null instead
    // of letting an unhandled exception crash the UI.
    try {
      return OTP.generateTOTPCodeString(
        secret,
        (timestamp ?? DateTime.now()).millisecondsSinceEpoch,
        interval: period,
        length: digits,
        algorithm: algorithm,
        isGoogle: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns true when [otpAuthUrl] is a well-formed otpauth URI whose secret
  /// can actually produce a TOTP code (valid Base32). Use this to validate
  /// input before moving to a preview/confirm step.
  bool isValidOtpAuth(String? otpAuthUrl) {
    return generateCode(otpAuthUrl) != null;
  }

  int secondsRemaining(String? otpAuthUrl, {DateTime? timestamp}) {
    final uri = Uri.tryParse(otpAuthUrl ?? '');
    final period = int.tryParse(uri?.queryParameters['period'] ?? '') ?? 30;
    final now = (timestamp ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final remainder = now % period;
    return remainder == 0 ? period : period - remainder;
  }

  Algorithm _parseAlgorithm(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'SHA256':
        return Algorithm.SHA256;
      case 'SHA512':
        return Algorithm.SHA512;
      case 'SHA1':
      default:
        return Algorithm.SHA1;
    }
  }
}

