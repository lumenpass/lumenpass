import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

/// Projection of a vault entry that the OS-level AutoFill providers
/// (iOS Credential Provider extension, Android AutofillService) need to
/// answer fill requests. Every vault entry is projected so the AutoFill
/// picker can search the full vault, not just login items.
class AutoFillCredential {
  const AutoFillCredential({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    this.otpAuthUrl,
    this.iconPngBase64,
    this.faviconUrl,
    required this.avatarInitials,
    required this.avatarBackgroundArgb,
    required this.avatarForegroundArgb,
    this.hasPasskey = false,
    this.passkeyCredentialIdB64url,
    this.passkeyPrivateKeyPem,
    this.passkeyRpId,
    this.passkeyUserHandleB64url,
  });

  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String? otpAuthUrl;

  /// Exact bitmap the mobile app uses for this row, when one exists.
  ///
  /// This lets the native AutoFill picker mirror the vault list instead of
  /// trying to reconstruct the icon from a weaker fallback model.
  final String? iconPngBase64;

  /// Google favicon helper URL (same logic as [VaultEntryAvatar] / desktop).
  final String? faviconUrl;
  final String avatarInitials;
  final int avatarBackgroundArgb;
  final int avatarForegroundArgb;
  final bool hasPasskey;

  /// Base64url credential id (same as browser extension / desktop vault).
  final String? passkeyCredentialIdB64url;

  /// PKCS#8 PEM EC P-256 private key (protected in KDBX; mirrored for OS passkey fill).
  final String? passkeyPrivateKeyPem;
  final String? passkeyRpId;
  final String? passkeyUserHandleB64url;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'username': username,
    'password': password,
    'url': url,
    if (otpAuthUrl != null && otpAuthUrl!.isNotEmpty) 'otpAuthUrl': otpAuthUrl,
    if (iconPngBase64 != null && iconPngBase64!.isNotEmpty)
      'iconPngBase64': iconPngBase64,
    if (faviconUrl != null && faviconUrl!.isNotEmpty) 'faviconUrl': faviconUrl,
    'avatarInitials': avatarInitials,
    'avatarBackgroundArgb': avatarBackgroundArgb,
    'avatarForegroundArgb': avatarForegroundArgb,
    'hasPasskey': hasPasskey,
    if (passkeyCredentialIdB64url != null &&
        passkeyCredentialIdB64url!.isNotEmpty)
      'passkeyCredentialIdB64url': passkeyCredentialIdB64url,
    if (passkeyPrivateKeyPem != null && passkeyPrivateKeyPem!.isNotEmpty)
      'passkeyPrivateKeyPem': passkeyPrivateKeyPem,
    if (passkeyRpId != null && passkeyRpId!.isNotEmpty)
      'passkeyRpId': passkeyRpId,
    if (passkeyUserHandleB64url != null && passkeyUserHandleB64url!.isNotEmpty)
      'passkeyUserHandleB64url': passkeyUserHandleB64url,
  };

  static final Map<String, Future<String?>> _iconAssetCache =
      <String, Future<String?>>{};

  /// Attempts to project a [KdbxEntry] into an AutoFill credential.
  ///
  /// Every vault item is projected so the AutoFill picker can search the
  /// full vault. Returns `null` only when the entry carries nothing we can
  /// advertise to the OS (no title AND no URL).
  static Future<AutoFillCredential?> fromEntry(
    KdbxEntry entry, {
    bool includeRenderedIconPayload = false,
  }) async {
    final password =
        entry.fieldByKey(AppKdbxFieldKeys.password)?.value.trim() ?? '';
    final username = (entry.username ?? '').trim();
    final url = (entry.url ?? '').trim();
    final title = entry.title.trim();

    final passkeyCredId =
        entry.fieldByKey(AppKdbxFieldKeys.passkeyCredentialId)?.value.trim() ??
        '';
    // Read the PKCS#8 PEM private key. The canonical label is
    // `KPEX_PASSKEY_PRIVATE_KEY_PEM`, but an older build of the desktop
    // browser-extension bridge wrote it under `KPEX_PASSKEY_PRIVATE_KEY_PBF`.
    // Accept both so entries registered before the fix still work on mobile.
    final passkeyPk =
        (entry
                    .fieldByKey(AppKdbxFieldKeys.passkeyPrivateKeyPem)
                    ?.value
                    .trim() ??
                entry
                    .fieldByKey('KPEX_PASSKEY_PRIVATE_KEY_PBF')
                    ?.value
                    .trim() ??
                '')
            .trim();
    final passkeyRp =
        entry.fieldByKey(AppKdbxFieldKeys.passkeyRpId)?.value.trim() ?? '';
    final passkeyUh =
        entry.fieldByKey(AppKdbxFieldKeys.passkeyUserHandle)?.value.trim() ??
        '';
    final canAssertPasskey =
        passkeyCredId.isNotEmpty &&
        passkeyPk.isNotEmpty &&
        passkeyRp.isNotEmpty;

    // Diagnostic: for any entry that advertises passkey fields, log what we
    // actually read from the KDBX so we can see whether the protected private
    // key decrypts. Only fires when at least one passkey-ish field is present.
    if (passkeyCredId.isNotEmpty ||
        passkeyPk.isNotEmpty ||
        passkeyRp.isNotEmpty ||
        passkeyUh.isNotEmpty) {
      final pkField = entry.fieldByKey(AppKdbxFieldKeys.passkeyPrivateKeyPem);
      debugPrint(
        '[passkey-probe] uuid=${entry.uuid} '
        'title="${entry.title}" '
        'credIdLen=${passkeyCredId.length} '
        'pkLen=${passkeyPk.length} '
        'pkFieldPresent=${pkField != null} '
        'pkFieldIsProtected=${pkField?.isProtected} '
        'pkRawLen=${pkField?.value.length ?? -1} '
        'rpIdLen=${passkeyRp.length} '
        'uhLen=${passkeyUh.length} '
        'allKeys=${entry.fields.map((f) => f.key).where((k) => k.toLowerCase().contains("passkey")).toList()}',
      );

      // One-shot dump of the Google entry's PEM + credId so we can verify
      // the exact bytes via openssl and compare with iOS pubKey.
      final titleLower = entry.title.toLowerCase();
      final userLower = (entry.username ?? '').toLowerCase();
      if (titleLower.contains('google') &&
          userLower.contains('tran.senior.it')) {
        debugPrint('[passkey-probe] ===== GOOGLE ENTRY PEM DUMP =====');
        debugPrint('[passkey-probe] credIdB64=$passkeyCredId');
        debugPrint('[passkey-probe] rpId=$passkeyRp');
        debugPrint('[passkey-probe] username=${entry.username}');
        debugPrint('[passkey-probe] PEM_BEGIN');
        for (final line in passkeyPk.split('\n')) {
          debugPrint('[passkey-probe] PEM_LINE|$line');
        }
        debugPrint('[passkey-probe] PEM_END');
      }
    }

    if (password.isEmpty &&
        username.isEmpty &&
        url.isEmpty &&
        title.isEmpty &&
        !canAssertPasskey) {
      return null;
    }
    if (title.isEmpty && url.isEmpty) return null;

    final colors = vaultListTileArgbForEntry(entry);
    final iconPngBase64 = includeRenderedIconPayload
        ? await _resolveRenderedIconPngBase64(entry)
        : null;

    return AutoFillCredential(
      id: entry.uuid,
      title: title.isNotEmpty ? title : url,
      username: username,
      password: password,
      url: url,
      otpAuthUrl: entry.otpAuthUrl,
      iconPngBase64: iconPngBase64,
      // When we ship a rendered bitmap, the native picker must not fetch
      // Google's favicon helper — that returns a generic globe for localhost
      // and sandbox hosts while the vault list shows initials instead.
      faviconUrl: includeRenderedIconPayload || url.isEmpty
          ? null
          : faviconUrlForWebsite(url),
      avatarInitials: vaultEntryListInitials(entry),
      avatarBackgroundArgb: colors.backgroundArgb,
      avatarForegroundArgb: colors.foregroundArgb,
      hasPasskey: entryHasPasskeyChip(entry),
      passkeyCredentialIdB64url: passkeyCredId.isNotEmpty
          ? passkeyCredId
          : null,
      passkeyPrivateKeyPem: passkeyPk.isNotEmpty ? passkeyPk : null,
      passkeyRpId: passkeyRp.isNotEmpty ? passkeyRp : null,
      passkeyUserHandleB64url: passkeyUh.isNotEmpty ? passkeyUh : null,
    );
  }

  static Future<String?> _resolveRenderedIconPngBase64(KdbxEntry entry) async {
    final itemIconAssetPath = _vaultItemIconAssetPath(
      _vaultEntryItemIconPresetId(entry),
    );
    if (itemIconAssetPath != null) {
      return _iconAssetCache.putIfAbsent(
        itemIconAssetPath,
        () => _loadAssetIconBase64(itemIconAssetPath),
      );
    }

    final cachedFaviconPayload = entry.faviconPngBase64;
    if (cachedFaviconPayload != null &&
        cachedFaviconPayload.isNotEmpty &&
        cachedFaviconPayload != AppKdbxFieldKeys.faviconFailedSentinel) {
      return cachedFaviconPayload;
    }

    final colors = vaultListTileArgbForEntry(entry);
    return _initialsIconCache.putIfAbsent(
      '${vaultEntryListInitials(entry)}|'
      '${colors.backgroundArgb}|'
      '${colors.foregroundArgb}',
      () => _renderInitialsPngBase64(
        initials: vaultEntryListInitials(entry),
        backgroundArgb: colors.backgroundArgb,
        foregroundArgb: colors.foregroundArgb,
      ),
    );
  }

  static final Map<String, Future<String?>> _initialsIconCache =
      <String, Future<String?>>{};

  static Future<String?> _renderInitialsPngBase64({
    required String initials,
    required int backgroundArgb,
    required int foregroundArgb,
    int size = 64,
  }) async {
    try {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final bgColor = Color(backgroundArgb);
      final fgColor = Color(foregroundArgb);
      final radius = size * 0.19;
      final text = initials.length > 2 ? initials.substring(0, 2) : initials;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          Radius.circular(radius),
        ),
        Paint()..color = bgColor,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: fgColor,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.toDouble());
      textPainter.paint(
        canvas,
        Offset(
          (size - textPainter.width) / 2,
          (size - textPainter.height) / 2,
        ),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      try {
        final pngData = await image.toByteData(format: ImageByteFormat.png);
        if (pngData == null) return null;
        return base64Encode(pngData.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _loadAssetIconBase64(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 64,
        targetHeight: 64,
      );
      final frame = await codec.getNextFrame();
      try {
        final pngData = await frame.image.toByteData(
          format: ImageByteFormat.png,
        );
        if (pngData == null) return null;
        return base64Encode(pngData.buffer.asUint8List());
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static String? _vaultEntryItemIconPresetId(KdbxEntry entry) {
    final raw = entry.fieldByKey(AppKdbxFieldKeys.itemIconPresetId)?.value;
    final normalized = raw?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static String? _vaultItemIconAssetPath(String? presetId) {
    final raw = presetId?.trim() ?? '';
    if (!raw.startsWith('img:')) return null;
    final imageId = raw.substring(4).trim();
    if (imageId.isEmpty) return null;
    return 'assets/images/categories/$imageId.png';
  }
}
