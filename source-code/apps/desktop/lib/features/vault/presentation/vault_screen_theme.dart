part of 'vault_screen.dart';

class _VaultColors {
  static const Color canvas = Color(0xFFF6F8FB);
  static const Color sidebar = Color(0xFFF2F5FA);
  static const Color title = Color(0xFF22314A);
  static const Color headerLabel = Color(0xFF73839D);
  static const Color sidebarLabel = Color(0xFF7A899F);
  static const Color icon = Color(0xFF8A97AC);
  static const Color borderSoft = Color(0xFFE1E7F0);
  static const Color borderPane = Color(0xFFE8EDF5);
}

const Color _kPrimaryButtonColor = Color(0xFF0A3B48);
const Color _kPrimaryButtonHoverColor = Color(0xFF0D4A59);
const Color _kDangerButtonColor = Color(0xFFDC2626);

TextStyle _text(
  double size,
  Color color, {
  FontWeight fontWeight = FontWeight.w400,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: size + 2 + currentTextSizeDelta,
    color: color,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    fontFamily: currentFontFamily,
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
