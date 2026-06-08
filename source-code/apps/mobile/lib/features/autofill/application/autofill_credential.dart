import 'package:flutter/foundation.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

/// Projection of a vault entry that the OS-level AutoFill providers
/// (iOS Credential Provider extension, Android AutofillService) need to
/// answer fill requests. Only login-style entries are eligible.
class AutoFillCredential {
  const AutoFillCredential({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    this.otpAuthUrl,
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

  /// Attempts to project a [KdbxEntry] into an AutoFill credential.
  ///
  /// Returns `null` when the entry is not a login item or does not carry
  /// enough information to be filled (no username AND no password, or no
  /// URL/title we can advertise to the OS).
  static AutoFillCredential? fromEntry(KdbxEntry entry) {
    final type = classifyVaultItemType(entry);
    if (type != VaultItemType.login) return null;

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

    if (password.isEmpty && username.isEmpty && !canAssertPasskey) {
      return null;
    }
    if (title.isEmpty && url.isEmpty) return null;

    final colors = vaultListTileArgbForEntry(entry);

    return AutoFillCredential(
      id: entry.uuid,
      title: title.isNotEmpty ? title : url,
      username: username,
      password: password,
      url: url,
      otpAuthUrl: entry.otpAuthUrl,
      faviconUrl: url.isNotEmpty ? faviconUrlForWebsite(url) : null,
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
}
