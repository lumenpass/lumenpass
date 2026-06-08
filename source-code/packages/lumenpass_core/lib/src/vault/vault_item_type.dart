import '../constants/kdbx_field_keys.dart';
import '../models/kdbx_entry.dart';

enum VaultItemType {
  login('login'),
  secureNote('secure-note'),
  creditCard('credit-card'),
  identity('identity'),
  sshKey('ssh-key'),
  document('document'),
  bankAccount('bank-account'),
  apiCredential('api-credential'),
  server('server'),
  wifiPassword('wifi-password'),
  passport('passport');

  const VaultItemType(this.id);

  final String id;

  static VaultItemType? fromId(String id) {
    for (final type in values) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
  }
}

/// Classifies a KeePass entry into a [VaultItemType] using a credential-shape
/// first, text second approach:
///
/// 1. If the entry has a very strong specialized signal (credit card number,
///    explicit "passport" / "wi-fi" markers, SSH armor, recognizable API
///    token field), return that type.
/// 2. Before the generic login shortcut, rescue identity entries that store
///    a display name in UserName but also have dedicated name-part fields.
/// 3. Otherwise, if it walks and quacks like a login (URL, UserName,
///    Password, OTPAuth, or passkey fields), return [VaultItemType.login].
///    This is the overwhelmingly common case and must win over generic
///    text matches like "Phone" on a custom field.
/// 4. Otherwise, fall through a cascade of weaker text-only heuristics:
///    bank account → server → identity → document → secure note.
///
/// The function never throws; field and value lookups are defensive against
/// empty or malformed entries.
VaultItemType classifyVaultItemType(KdbxEntry entry) {
  final title = entry.title.toLowerCase();
  final notes = (entry.notes ?? '').toLowerCase();
  final username = (entry.username ?? '').toLowerCase();
  final url = (entry.url ?? '').toLowerCase();
  final normalizedKeys = entry.fields
      .map((field) => field.key.toLowerCase())
      .toList(growable: false);
  final normalizedValues = entry.fields
      .map((field) => field.value.toLowerCase())
      .toList(growable: false);

  final titleNotes = '$title $notes'.trim();
  final keysJoined = normalizedKeys.join(' ');
  final valuesJoined = normalizedValues.join(' ');

  bool keyContainsAny(Iterable<String> needles) {
    return normalizedKeys.any(
      (key) => needles.any((needle) => key.contains(needle)),
    );
  }

  bool hasKeyExact(Iterable<String> exacts) {
    return normalizedKeys.any(exacts.contains);
  }

  /// Matches [needle] as a whole word inside [haystack], preventing false
  /// positives like "email address" triggering an "address" match or "rsa"
  /// matching "ursa". Whitespace / punctuation are treated as boundaries.
  bool wholeWord(String haystack, String needle) {
    if (needle.isEmpty) return false;
    final pattern = RegExp(
      '(^|[^a-z0-9])' + RegExp.escape(needle) + r'($|[^a-z0-9])',
      caseSensitive: false,
    );
    return pattern.hasMatch(haystack);
  }

  bool titleNotesHasWord(Iterable<String> needles) {
    return needles.any((n) => wholeWord(titleNotes, n));
  }

  // ── Credential-shape signals ────────────────────────────────────────────
  final hasUsername = username.isNotEmpty;
  final hasUrl = url.isNotEmpty;
  final hasPasswordField = hasKeyExact(<String>{
    'password',
    'passcode',
    'pin',
  });
  final hasOtpField = normalizedKeys.any(
    (key) => key == AppKdbxFieldKeys.otpAuth.toLowerCase() || key == 'otp',
  );
  final hasPasskeyField = keyContainsAny(
    const <String>['passkey', 'kpex_passkey_'],
  );
  final looksLikeLogin = hasUrl ||
      hasUsername ||
      hasPasswordField ||
      hasOtpField ||
      hasPasskeyField;
  final hasIdentityNameField = hasKeyExact(<String>{
        'full name',
        'first name',
        'last name',
        'middle name',
        'given name',
        'family name',
      }) ||
      keyContainsAny(const <String>[
        'full name',
        'first name',
        'last name',
        'middle name',
        'given name',
        'family name',
      ]);

  // Passkeys always map to logins regardless of other signals.
  if (hasPasskeyField) return VaultItemType.login;

  // ── Strong specialized signals (override even logins) ───────────────────
  //
  // Only accept very specific markers here — things that are near-impossible
  // for a generic login entry to have by accident.

  if (titleNotesHasWord(const <String>['passport']) ||
      titleNotesHasWord(const <String>['travel document'])) {
    return VaultItemType.passport;
  }

  final hasWifiField = hasKeyExact(<String>{'ssid'}) ||
      keyContainsAny(const <String>['ssid', 'wi-fi', 'wifi']);
  if (hasWifiField ||
      titleNotesHasWord(const <String>['wi-fi', 'wifi', 'ssid'])) {
    return VaultItemType.wifiPassword;
  }

  final hasCardField = hasKeyExact(<String>{
        'card number',
        'cardnumber',
        'cvv',
        'cvc',
        'expiry',
        'expiration',
      }) ||
      keyContainsAny(const <String>['card number', 'cvv', 'cvc']);
  if (hasCardField ||
      titleNotesHasWord(const <String>[
        'credit card',
        'debit card',
        'cvv',
        'cvc',
        'amex',
        'visa',
        'mastercard',
      ])) {
    return VaultItemType.creditCard;
  }

  // Explicit SSH armor in a value is essentially unambiguous.
  const sshArmor = <String>[
    '-----begin openssh private key-----',
    '-----begin rsa private key-----',
    '-----begin dsa private key-----',
    '-----begin ec private key-----',
    '-----begin private key-----',
    'ssh-rsa ',
    'ssh-ed25519 ',
    'ecdsa-sha2-nistp',
  ];
  if (sshArmor.any(valuesJoined.contains)) {
    return VaultItemType.sshKey;
  }
  final hasSshKeyField = hasKeyExact(<String>{
        'private key',
        'public key',
        'authorized_keys',
      }) ||
      keyContainsAny(
        const <String>['private key', 'public key', 'authorized_keys'],
      );
  if (hasSshKeyField) {
    return VaultItemType.sshKey;
  }

  // Bank-account markers that unambiguously describe a bank entry.
  final hasBankField = hasKeyExact(<String>{
        'account number',
        'routing number',
        'iban',
        'swift',
        'bic',
        'sort code',
      }) ||
      keyContainsAny(const <String>[
        'account number',
        'routing number',
        'iban ',
        'swift ',
        'sort code',
      ]);
  if (hasBankField ||
      titleNotesHasWord(const <String>[
        'iban',
        'swift',
        'bic',
        'routing',
      ]) ||
      (titleNotesHasWord(const <String>['bank']) &&
          titleNotesHasWord(const <String>['account']))) {
    return VaultItemType.bankAccount;
  }

  // API credential: dedicated key fields or very specific title.
  final hasApiField = hasKeyExact(<String>{
        'api key',
        'api token',
        'access token',
        'refresh token',
        'client id',
        'client secret',
        'secret key',
        'bearer token',
      }) ||
      keyContainsAny(const <String>[
        'api key',
        'api token',
        'access token',
        'refresh token',
        'client secret',
        'bearer token',
      ]);
  if (hasApiField ||
      titleNotesHasWord(const <String>['api key', 'api token'])) {
    return VaultItemType.apiCredential;
  }

  // Identities created by LumenPass store the assembled full name in the
  // KeePass UserName field for compatibility with existing display/autofill
  // paths. Treat name-part fields as an identity before the generic
  // UserName=>login shortcut, while still letting URL/password/OTP/passkey
  // credentials remain logins.
  if (hasIdentityNameField &&
      !hasUrl &&
      !hasPasswordField &&
      !hasOtpField &&
      !hasPasskeyField) {
    return VaultItemType.identity;
  }

  // ── Login short-circuit ─────────────────────────────────────────────────
  //
  // If the entry has the usual login shape, classify it as a login *before*
  // falling into the softer text heuristics. This is what prevents custom
  // fields like "Phone" on a Zoho login from being misread as Identity.
  if (looksLikeLogin) {
    return VaultItemType.login;
  }

  // ── Softer heuristics (no login shape at all) ───────────────────────────

  // Server: dedicated host/port-style fields or explicit wording.
  final hasServerField = hasKeyExact(<String>{
        'hostname',
        'host',
        'port',
        'server',
        'ip address',
      }) ||
      keyContainsAny(const <String>['hostname', 'ip address']);
  if (hasServerField ||
      titleNotesHasWord(const <String>['vps', 'hostname', 'ssh server'])) {
    return VaultItemType.server;
  }

  final hasIdentityField = hasKeyExact(<String>{
        'full name',
        'first name',
        'last name',
        'address',
        'phone',
        'phone number',
        'contact',
        'social security',
        'ssn',
        'driver license',
        'driver licence',
      }) ||
      keyContainsAny(const <String>[
        'full name',
        'first name',
        'last name',
        'phone number',
        'social security',
        'driver license',
        'driver licence',
      ]);
  if (hasIdentityField ||
      titleNotesHasWord(const <String>[
        'identity',
        'passport id',
        'driver license',
        'driver licence',
      ])) {
    return VaultItemType.identity;
  }

  final looksLikeDocument = titleNotesHasWord(const <String>[
        'certificate',
        'contract',
        'statement',
        'invoice',
        'license key',
        'licence key',
        'product key',
        'serial number',
      ]) ||
      keysJoined.contains('product key') ||
      keysJoined.contains('serial number') ||
      keysJoined.contains('license key');
  if (looksLikeDocument) {
    return VaultItemType.document;
  }

  return VaultItemType.secureNote;
}
