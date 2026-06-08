/// Centralizes the logical field names we read from KeePass entries.
abstract final class AppKdbxFieldKeys {
  static const String title = 'Title';
  static const String userName = 'UserName';
  static const String password = 'Password';
  static const String url = 'URL';
  static const String otpAuth = 'OTPAuth';
  static const String notes = 'Notes';
  static const String attachmentNamePrefix = '__lp_att_name_';
  static const String attachmentSizePrefix = '__lp_att_size_';
  static const String attachmentImagePrefix = '__lp_att_img_';

  /// Hidden custom field that caches the entry's website favicon as a
  /// base64-encoded PNG. Populated lazily by the UI after a successful
  /// network fetch so subsequent opens render offline from the vault
  /// itself — no repeat network calls. Hidden from edit/display UI.
  static const String faviconPngBase64 = '__lp_favicon_png_b64';

  /// Sentinel value we write when a favicon fetch definitively failed
  /// (host unreachable, 404, etc.), so we don't re-attempt on every
  /// future render. Kept tiny so it doesn't bloat the DB.
  static const String faviconFailedSentinel = 'FAIL';

  /// Browser extension / desktop passkey custom fields (KeePassXC-style).
  static const String passkeyCredentialId = 'KPEX_PASSKEY_CREDENTIAL_ID';
  static const String passkeyPrivateKeyPem = 'KPEX_PASSKEY_PRIVATE_KEY_PEM';
  static const String passkeyRpId = 'KPEX_PASSKEY_RELYING_PARTY';
  static const String passkeyUsername = 'KPEX_PASSKEY_USERNAME';
  static const String passkeyUserHandle = 'KPEX_PASSKEY_USER_HANDLE';

  static const Set<String> standardKeys = <String>{
    title,
    userName,
    password,
    url,
    otpAuth,
  };

  static bool isProtectedKey(String key) {
    final normalized = key.toLowerCase();
    return normalized == password.toLowerCase() ||
        normalized == otpAuth.toLowerCase() ||
        normalized.contains('sensitive') ||
        normalized == passkeyPrivateKeyPem.toLowerCase() ||
        normalized.contains('secret') ||
        normalized.contains('token') ||
        (normalized.contains('pass') && !normalized.contains('passkey'));
  }

  static bool isStandardKey(String key) => standardKeys.contains(key);

  static bool isAttachmentMetaKey(String key) {
    return key.startsWith(attachmentNamePrefix) ||
        key.startsWith(attachmentSizePrefix) ||
        key.startsWith(attachmentImagePrefix);
  }

  /// Internal metadata keys (favicon cache, attachments) that should be
  /// invisible to the field editor / detail pane.
  static bool isInternalMetaKey(String key) {
    return isAttachmentMetaKey(key) || key == faviconPngBase64;
  }
}
