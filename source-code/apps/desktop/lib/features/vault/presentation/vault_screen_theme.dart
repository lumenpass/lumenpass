part of 'vault_screen.dart';

class _VaultColors {
  static const Color canvas = Color(0xFFF5F1E8);
  static const Color sidebar = Color(0xFFE8DED0);
  static const Color surface = Color(0xFFFFFCF6);
  static const Color surfaceMuted = Color(0xFFF8F3EA);
  static const Color peach = Color(0xFFF3D4C5);
  static const Color peachSoft = Color(0xFFFAEDE5);
  static const Color title = Color(0xFF1E2021);
  static const Color headerLabel = Color(0xFF686B67);

  static const Color icon = Color(0xFF777A75);
  static const Color borderSoft = Color(0xFFD8D2C7);
  static const Color borderPane = Color(0xFFCEC7BB);
}

const Color _kPrimaryButtonColor = Color(0xFFFF5B22);
const Color _kPrimaryButtonHoverColor = Color(0xFFE94A13);
const Color _kDangerButtonColor = Color(0xFFCF3E32);

TextStyle _text(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    // Match the picker/unlock type scale: callers get the size they request.
    // The previous unconditional +2 made every home-screen label feel like a
    // separate, oversized type system.
    fontSize: size + currentTextSizeDelta,
    color: color,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    fontFamily: currentFontFamily,
  );
}

TextStyle _displayText(
  double size,
  Color color, {
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w700,
    fontFamily: currentFontFamily,
    letterSpacing: -0.45,
    height: height,
  );
}

String _formatAttachmentSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

const TOTPService _mockTotpService = TOTPService();

String _formattedTotpCode(_MockEntry entry, DateTime timestamp) {
  final rawCode = _mockTotpService.generateCode(
    entry.totpAuthUrl,
    timestamp: timestamp,
  );
  if (rawCode == null || rawCode.isEmpty) {
    return '--- ---';
  }
  if (rawCode.length != 6) {
    return rawCode;
  }
  return '${rawCode.substring(0, 3)} ${rawCode.substring(3)}';
}

int _totpSecondsRemaining(_MockEntry entry, DateTime timestamp) {
  return _mockTotpService.secondsRemaining(
    entry.totpAuthUrl,
    timestamp: timestamp,
  );
}

Color _totpCountdownColor(int secondsRemaining) {
  if (secondsRemaining <= 9) {
    return const Color(0xFFDC2626);
  }
  if (secondsRemaining <= 15) {
    return const Color(0xFFF59E0B);
  }
  return const Color(0xFF16A34A);
}
