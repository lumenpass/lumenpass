import 'package:otp/otp.dart';
import 'package:test/test.dart';
import 'package:lumenpass_core/src/services/totp_service.dart';

void main() {
  const service = TOTPService();

  group('generateCode', () {
    test('returns null for null input', () {
      expect(service.generateCode(null), isNull);
    });

    test('returns null for empty string', () {
      expect(service.generateCode(''), isNull);
    });

    test('returns null for non-otpauth URI', () {
      expect(service.generateCode('https://example.com'), isNull);
    });

    test('returns null when secret is missing', () {
      expect(service.generateCode('otpauth://totp/Test?issuer=X'), isNull);
    });

    test('returns null when secret is empty', () {
      expect(
          service.generateCode('otpauth://totp/Test?secret=&issuer=X'), isNull);
    });

    test('returns null (no throw) for invalid Base32 secret', () {
      // The otpauth URI is well-formed but the secret contains characters that
      // are not valid Base32 (lowercase, symbols, '0'/'1'). The underlying otp
      // package throws a FormatException; generateCode must swallow it.
      expect(
        () => service.generateCode(
          'otpauth://totp/?secret=mVL2ezoeMFA^Cj(23&gU;(Z8r',
        ),
        returnsNormally,
      );
      expect(
        service.generateCode(
          'otpauth://totp/?secret=mVL2ezoeMFA^Cj(23&gU;(Z8r',
        ),
        isNull,
      );
    });

    test('returns 6-digit code by default', () {
      final code = service.generateCode(
        'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&issuer=TestIssuer',
      );
      expect(code, isNotNull);
      expect(code!.length, 6);
      expect(int.tryParse(code), isNotNull);
    });

    test('returns 8-digit code when digits=8', () {
      final code = service.generateCode(
        'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&digits=8',
      );
      expect(code, isNotNull);
      expect(code!.length, 8);
    });

    test('default algorithm is SHA1 (RFC 6238 standard)', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final now = DateTime(2025, 1, 1, 0, 0, 0);
      final ms = now.millisecondsSinceEpoch;

      final codeNoAlg = service.generateCode(
        'otpauth://totp/Test?secret=$secret',
        timestamp: now,
      );

      final codeSha1 = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA1',
        timestamp: now,
      );

      final codeSha256 = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA256',
        timestamp: now,
      );

      expect(codeNoAlg, equals(codeSha1),
          reason: 'No algorithm specified should default to SHA1');
      expect(codeNoAlg, isNot(equals(codeSha256)),
          reason: 'SHA1 default should differ from SHA256');
    });

    test('explicit SHA256 algorithm works', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final now = DateTime(2025, 1, 1, 0, 0, 0);

      final code = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA256',
        timestamp: now,
      );

      final expected = OTP.generateTOTPCodeString(
        secret,
        now.millisecondsSinceEpoch,
        algorithm: Algorithm.SHA256,
        isGoogle: true,
      );

      expect(code, equals(expected));
    });

    test('explicit SHA512 algorithm works', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final now = DateTime(2025, 1, 1, 0, 0, 0);

      final code = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA512',
        timestamp: now,
      );

      final expected = OTP.generateTOTPCodeString(
        secret,
        now.millisecondsSinceEpoch,
        algorithm: Algorithm.SHA512,
        isGoogle: true,
      );

      expect(code, equals(expected));
    });

    test('matches otp package with isGoogle:true and SHA1', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final now = DateTime(2025, 6, 15, 12, 0, 0);

      final code = service.generateCode(
        'otpauth://totp/Test?secret=$secret',
        timestamp: now,
      );

      final expected = OTP.generateTOTPCodeString(
        secret,
        now.millisecondsSinceEpoch,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );

      expect(code, equals(expected));
    });

    test('custom period is respected', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final now = DateTime(2025, 1, 1, 0, 0, 15);

      final code30 = service.generateCode(
        'otpauth://totp/Test?secret=$secret&period=30',
        timestamp: now,
      );

      final code60 = service.generateCode(
        'otpauth://totp/Test?secret=$secret&period=60',
        timestamp: now,
      );

      expect(code30, isNotNull);
      expect(code60, isNotNull);
    });

    test('produces consistent codes for same timestamp', () {
      const url = 'otpauth://totp/Mozilla:admin@lumenpass.app'
          '?secret=JBSWY3DPEHPK3PXP&issuer=Mozilla';
      final fixedTime = DateTime(2025, 3, 15, 10, 30, 0);

      final code1 = service.generateCode(url, timestamp: fixedTime);
      final code2 = service.generateCode(url, timestamp: fixedTime);

      expect(code1, equals(code2));
    });

    test('produces different codes for different time periods', () {
      const url = 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP';
      final t1 = DateTime(2025, 1, 1, 0, 0, 0);
      final t2 = DateTime(2025, 1, 1, 0, 1, 0);

      final code1 = service.generateCode(url, timestamp: t1);
      final code2 = service.generateCode(url, timestamp: t2);

      expect(code1, isNot(equals(code2)),
          reason: 'Different 30-second windows should produce different codes');
    });

    test('RFC 6238 known test vector SHA1 at epoch 59', () {
      const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final timestamp = DateTime.fromMillisecondsSinceEpoch(59000);

      final code = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA1&digits=8',
        timestamp: timestamp,
      );

      expect(code, equals('94287082'));
    });

    test('case-insensitive algorithm parameter', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final now = DateTime(2025, 1, 1, 0, 0, 0);

      final codeLower = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=sha1',
        timestamp: now,
      );

      final codeUpper = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA1',
        timestamp: now,
      );

      expect(codeLower, equals(codeUpper));
    });

    test('unknown algorithm falls back to SHA1', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final now = DateTime(2025, 1, 1, 0, 0, 0);

      final codeUnknown = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=MD5',
        timestamp: now,
      );

      final codeSha1 = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA1',
        timestamp: now,
      );

      expect(codeUnknown, equals(codeSha1),
          reason: 'Unknown algorithm should fall back to SHA1');
    });

    test('real-world Google Authenticator compatible URI', () {
      const uri = 'otpauth://totp/Google:user@gmail.com'
          '?secret=JBSWY3DPEHPK3PXP&issuer=Google';
      final fixedTime = DateTime(2025, 1, 1, 0, 0, 0);

      final code = service.generateCode(uri, timestamp: fixedTime);

      final expected = OTP.generateTOTPCodeString(
        'JBSWY3DPEHPK3PXP',
        fixedTime.millisecondsSinceEpoch,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );

      expect(code, equals(expected),
          reason:
              'Google Authenticator URIs without algorithm param should use SHA1');
    });

    test('URI with all parameters specified', () {
      const uri = 'otpauth://totp/GitHub:dev@example.com'
          '?secret=JBSWY3DPEHPK3PXP&issuer=GitHub'
          '&algorithm=SHA256&digits=6&period=30';
      final fixedTime = DateTime(2025, 1, 1, 0, 0, 0);

      final code = service.generateCode(uri, timestamp: fixedTime);

      final expected = OTP.generateTOTPCodeString(
        'JBSWY3DPEHPK3PXP',
        fixedTime.millisecondsSinceEpoch,
        algorithm: Algorithm.SHA256,
        isGoogle: true,
      );

      expect(code, equals(expected));
    });
  });

  group('secondsRemaining', () {
    test('returns period when at exact period boundary', () {
      final atBoundary = DateTime.fromMillisecondsSinceEpoch(30 * 1000 * 100);
      final remaining = service.secondsRemaining(
        'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP',
        timestamp: atBoundary,
      );
      expect(remaining, 30);
    });

    test('returns 1 when one second before next period', () {
      final oneBeforeNext =
          DateTime.fromMillisecondsSinceEpoch((30 * 100 + 29) * 1000);
      final remaining = service.secondsRemaining(
        'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP',
        timestamp: oneBeforeNext,
      );
      expect(remaining, 1);
    });

    test('respects custom period', () {
      final atBoundary =
          DateTime.fromMillisecondsSinceEpoch(60 * 1000 * 100);
      final remaining = service.secondsRemaining(
        'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&period=60',
        timestamp: atBoundary,
      );
      expect(remaining, 60);
    });

    test('defaults to 30s period when not specified', () {
      final ts = DateTime.fromMillisecondsSinceEpoch(10 * 1000);
      final remaining = service.secondsRemaining(
        'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP',
        timestamp: ts,
      );
      expect(remaining, 20);
    });

    test('defaults to 30s period for null URL', () {
      final ts = DateTime.fromMillisecondsSinceEpoch(10 * 1000);
      final remaining = service.secondsRemaining(null, timestamp: ts);
      expect(remaining, 20);
    });
  });

  group('cross-platform consistency', () {
    test(
        'default SHA1 matches what Google Authenticator / Authy would produce',
        () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final fixedTime = DateTime(2025, 1, 1, 0, 0, 0);

      final ourCode = service.generateCode(
        'otpauth://totp/Test?secret=$secret',
        timestamp: fixedTime,
      );

      final googleAuthCode = OTP.generateTOTPCodeString(
        secret,
        fixedTime.millisecondsSinceEpoch,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );

      expect(ourCode, equals(googleAuthCode),
          reason:
              'Our TOTP codes must match Google Authenticator (SHA1 default)');
    });

    test('all three algorithms produce different codes', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final now = DateTime(2025, 1, 1, 0, 0, 0);

      final sha1 = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA1',
        timestamp: now,
      );
      final sha256 = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA256',
        timestamp: now,
      );
      final sha512 = service.generateCode(
        'otpauth://totp/Test?secret=$secret&algorithm=SHA512',
        timestamp: now,
      );

      expect(sha1, isNot(equals(sha256)));
      expect(sha1, isNot(equals(sha512)));
      expect(sha256, isNot(equals(sha512)));
    });

    test('typical Mozilla/GitHub/Gitlab QR code (no algorithm param)', () {
      const uris = [
        'otpauth://totp/Mozilla:admin@lumenpass.app?secret=JBSWY3DPEHPK3PXP&issuer=Mozilla',
        'otpauth://totp/GitHub:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub',
        'otpauth://totp/GitLab:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitLab',
      ];
      final fixedTime = DateTime(2025, 1, 1, 0, 0, 0);

      for (final uri in uris) {
        final code = service.generateCode(uri, timestamp: fixedTime);
        final sha1Code = OTP.generateTOTPCodeString(
          'JBSWY3DPEHPK3PXP',
          fixedTime.millisecondsSinceEpoch,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );
        expect(code, equals(sha1Code),
            reason: 'URI "$uri" should use SHA1 default');
      }
    });
  });

  group('isValidOtpAuth', () {
    test('true for a valid Base32 otpauth URI', () {
      expect(
        service.isValidOtpAuth(
          'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&issuer=Test',
        ),
        isTrue,
      );
    });

    test('false for invalid Base32 secret (would otherwise crash)', () {
      expect(
        service.isValidOtpAuth(
          'otpauth://totp/?secret=mVL2ezoeMFA^Cj(23&gU;(Z8r',
        ),
        isFalse,
      );
    });

    test('false for null, empty, and non-otpauth input', () {
      expect(service.isValidOtpAuth(null), isFalse);
      expect(service.isValidOtpAuth(''), isFalse);
      expect(service.isValidOtpAuth('https://example.com'), isFalse);
    });
  });
}
