part of 'vault_screen.dart';

/// Vault palette, mapped onto the DriveClue tokens ([DcColors]).
///
/// The names are kept from the previous palette so existing references pick up
/// the new look without touching their call sites. Every modal and dialog in
/// the vault workspace is a light surface under a dark [DcDialogTitleBar], so
/// the dark-slate entries that used to live here are gone — keeping them would
/// silently offer an unused "wrong" surface to new code.
class _VaultColors {
  /// Window and pane background (dark slate).
  static const Color canvas = DcColors.background;
  static const Color sidebar = DcColors.sidebar;

  static const Color title = DcColors.text;

  static const Color icon = DcColors.muted;
}

const Color _kPrimaryButtonColor = DcColors.selection;
const Color _kPrimaryButtonHoverColor = DcColors.selectionHover;
const Color _kDangerButtonColor = DcColors.red;

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
    return DcColors.red;
  }
  if (secondsRemaining <= 15) {
    return DcColors.amber;
  }
  return DcColors.green;
}
