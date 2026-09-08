import '../constants/kdbx_field_keys.dart';
import '../models/kdbx_entry.dart';
import 'vault_card_brand.dart';
import 'vault_item_type.dart';

const List<String> kVaultListMonthAbbr = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// ARGB tile colors for initials / fallback avatars (matches desktop `_tilePalette`).
const List<({int backgroundArgb, int foregroundArgb})>
    kVaultListTileArgbPalette = <({int backgroundArgb, int foregroundArgb})>[
  (backgroundArgb: 0xFFE5D6A4, foregroundArgb: 0xFF6E6546),
  (backgroundArgb: 0xFFDDD7CC, foregroundArgb: 0xFF6A645A),
  (backgroundArgb: 0xFFD7EACF, foregroundArgb: 0xFF5F7855),
  (backgroundArgb: 0xFFE6DBF8, foregroundArgb: 0xFF6A5D86),
  (backgroundArgb: 0xFFDCE5FA, foregroundArgb: 0xFF566789),
  (backgroundArgb: 0xFFE4E8EF, foregroundArgb: 0xFF626B77),
  (backgroundArgb: 0xFFFFE4E4, foregroundArgb: 0xFF885050),
  (backgroundArgb: 0xFFE4F4FF, foregroundArgb: 0xFF476880),
  (backgroundArgb: 0xFFFFF0D6, foregroundArgb: 0xFF7A5B1A),
  (backgroundArgb: 0xFFD6F5EE, foregroundArgb: 0xFF2E6B58),
];

DateTime? latestEntryTimestamp(DateTime? a, DateTime? b) {
  if (a == null) {
    return b;
  }
  if (b == null) {
    return a;
  }
  return a.isAfter(b) ? a : b;
}

({int backgroundArgb, int foregroundArgb}) vaultListTileArgbForEntry(
    KdbxEntry entry) {
  final colorIndex =
      entry.title.hashCode.abs() % kVaultListTileArgbPalette.length;
  return kVaultListTileArgbPalette[colorIndex];
}

String vaultEntryListInitials(KdbxEntry entry) {
  final raw = entry.title.trim();
  if (raw.length >= 2) {
    return raw.substring(0, 2);
  }
  return raw;
}

/// Relative date label: `Today`, `Yesterday`, or `Apr 10` (desktop list pane).
String formatVaultEntryListDateLabel({
  required DateTime now,
  DateTime? updatedAt,
  DateTime? createdAt,
}) {
  final touched = latestEntryTimestamp(updatedAt, createdAt);
  if (touched == null) {
    return '';
  }
  final diff = now.difference(touched);
  if (diff.inDays == 0) {
    return 'Today';
  }
  if (diff.inDays == 1) {
    return 'Yesterday';
  }
  return '${kVaultListMonthAbbr[touched.month - 1]} ${touched.day}';
}

String? faviconUrlForWebsite(String website) {
  final trimmed = website.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final uri =
        Uri.parse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
    if (uri.host.isEmpty) {
      return null;
    }
    return 'https://www.google.com/s2/favicons?sz=32&domain=${uri.host}';
  } catch (_) {
    return null;
  }
}

String vaultEntryListSubtitle(KdbxEntry entry, VaultItemType itemType) {
  if (itemType == VaultItemType.sshKey) {
    final sshPreview = sshSubtitlePreview(entry);
    if (sshPreview.isNotEmpty) {
      return sshPreview;
    }
  }
  if (itemType == VaultItemType.creditCard) {
    final creditCardPreview = creditCardSubtitlePreview(entry);
    if (creditCardPreview.isNotEmpty) {
      return creditCardPreview;
    }
  }

  final username = entry.username?.trim() ?? '';
  if (username.isNotEmpty) {
    return truncateListPreview(singleLinePreview(username), 56);
  }

  final website = entry.url?.trim() ?? '';
  if (website.isNotEmpty) {
    return truncateListPreview(
      singleLinePreview(compactWebsite(website)),
      56,
    );
  }

  final notePreview = singleLinePreview(entry.notes ?? '');
  if (notePreview.isNotEmpty) {
    return truncateListPreview(notePreview, 56);
  }

  const normalizedStandardKeys = <String>{
    'title',
    'username',
    'password',
    'url',
    'otpauth',
    'notes',
  };

  for (final field in entry.fields) {
    final key = field.key.trim();
    final normalizedKey = key.toLowerCase();
    if (normalizedStandardKeys.contains(normalizedKey) ||
        key == AppKdbxFieldKeys.itemIconPresetId ||
        AppKdbxFieldKeys.isAttachmentMetaKey(key) ||
        field.isProtected ||
        AppKdbxFieldKeys.isProtectedKey(key)) {
      continue;
    }

    final value = singleLinePreview(field.value);
    if (value.isNotEmpty) {
      return truncateListPreview(value, 56);
    }
  }

  return '';
}

String creditCardSubtitlePreview(KdbxEntry entry) {
  final cardholder = extractCreditCardholder(entry);
  final maskedLast4 =
      maskedCreditCardLast4(extractCreditCardNumberFromEntry(entry));

  if (cardholder.isNotEmpty && maskedLast4.isNotEmpty) {
    return truncateListPreview('$cardholder $maskedLast4', 56);
  }
  if (cardholder.isNotEmpty) {
    return truncateListPreview(cardholder, 56);
  }
  if (maskedLast4.isNotEmpty) {
    return truncateListPreview(maskedLast4, 56);
  }
  return '';
}

String extractCreditCardholder(KdbxEntry entry) {
  const holderKeyHints = <String>[
    'cardholder',
    'name on card',
    'cardholder name',
    'card holder',
  ];
  for (final field in entry.fields) {
    final key = field.key.trim().toLowerCase();
    if (holderKeyHints.any(key.contains)) {
      final value = singleLinePreview(field.value);
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return singleLinePreview(entry.username?.trim() ?? '');
}

String maskedCreditCardLast4(String rawNumber) {
  final digits = rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return '';
  }
  final last4 =
      digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  return 'xxx$last4';
}

/// Masks the middle digits of a credit card number for view-only display,
/// keeping the first 4 and last 3 digits visible. Any non-digit characters
/// (spaces, dashes) are stripped before masking. If the number is too short to
/// have a hidden middle section it is returned unchanged.
String maskCreditCardNumberForDisplay(String rawNumber) {
  final digits = rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
  // Need at least first 4 + last 3 + 1 hidden digit to mask meaningfully.
  if (digits.length <= 7) {
    return rawNumber;
  }
  final first4 = digits.substring(0, 4);
  final last3 = digits.substring(digits.length - 3);
  final hiddenCount = digits.length - 7;
  final masked = '\u2022' * hiddenCount;
  return '$first4$masked$last3';
}

String sshSubtitlePreview(KdbxEntry entry) {
  String? findFieldValue(
    List<String> matches, {
    bool includeValue = false,
    bool includeProtected = false,
  }) {
    for (final field in entry.fields) {
      if (!includeProtected && field.isProtected) {
        continue;
      }
      final key = field.key.toLowerCase();
      final value = field.value.trim();
      if (value.isEmpty) {
        continue;
      }
      final normalizedValue = value.toLowerCase();
      final keyMatch = matches.any(key.contains);
      final valueMatch = includeValue && matches.any(normalizedValue.contains);
      if (keyMatch || valueMatch) {
        return value;
      }
    }
    return null;
  }

  final fingerprint = findFieldValue(
    const <String>['fingerprint', 'sha256:'],
    includeValue: true,
  );
  if (fingerprint != null && fingerprint.isNotEmpty) {
    return truncateListPreview(singleLinePreview(fingerprint), 56);
  }

  final publicKey = findFieldValue(
    const <String>['public key', 'authorized key'],
    includeValue: true,
  );
  if (publicKey != null && publicKey.isNotEmpty) {
    return truncateListPreview(singleLinePreview(publicKey), 56);
  }

  final keyType = findFieldValue(const <String>['key type', 'algorithm']);
  if (keyType != null && keyType.isNotEmpty) {
    return truncateListPreview('${singleLinePreview(keyType)} key', 56);
  }

  final fileName = findFieldValue(
    const <String>['key file name', 'filename', 'file name'],
  );
  if (fileName != null && fileName.isNotEmpty) {
    return truncateListPreview(singleLinePreview(fileName), 56);
  }

  final privateKey = findFieldValue(
    const <String>['private key', 'openssh', 'pem'],
    includeValue: true,
    includeProtected: true,
  );
  if (privateKey != null && privateKey.isNotEmpty) {
    final inferredType = inferSshKeyType(privateKey);
    if (inferredType.isNotEmpty) {
      return '$inferredType private key';
    }
    return 'Private key imported';
  }

  return '';
}

String inferSshKeyType(String source) {
  final normalized = source.toLowerCase();
  if (normalized.contains('ed25519')) {
    return 'Ed25519';
  }
  if (normalized.contains('rsa')) {
    return 'RSA';
  }
  if (normalized.contains('ecdsa')) {
    return 'ECDSA';
  }
  if (normalized.contains('dsa')) {
    return 'DSA';
  }
  return '';
}

String singleLinePreview(String input) {
  return input.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String truncateListPreview(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength - 1)}…';
}

String compactWebsite(String rawUrl) {
  final value = rawUrl.trim();
  if (value.isEmpty) {
    return value;
  }

  try {
    final uri = Uri.parse(value);
    final host = uri.host.trim();
    if (host.isEmpty) {
      return value;
    }
    return host.startsWith('www.') ? host.substring(4) : host;
  } catch (_) {
    return value;
  }
}

bool entryHasPasskeyChip(KdbxEntry entry) {
  return entry.fields.any((f) => f.key.toLowerCase().contains('passkey'));
}

bool entryHasTotp(KdbxEntry entry) {
  final u = entry.otpAuthUrl;
  return u != null && u.trim().isNotEmpty;
}

/// Sentinel used when an entry has no usable timestamp at all, so comparisons
/// stay total and such entries sort to the bottom.
final DateTime _kEpoch = DateTime.fromMillisecondsSinceEpoch(0);

/// The timestamp that best represents when an entry was last *used*, falling
/// back to last updated and then created. Mirrors the desktop vault ordering
/// (`lastUsedAt ?? updatedAt ?? createdAt`).
DateTime effectiveLastUsedAt(KdbxEntry entry) {
  return entry.lastUsedAt ?? entry.updatedAt ?? entry.createdAt ?? _kEpoch;
}

/// The timestamp that best represents when an entry was last *updated*,
/// falling back to created.
DateTime effectiveLastUpdatedAt(KdbxEntry entry) {
  return entry.updatedAt ?? entry.createdAt ?? _kEpoch;
}

/// Orders entries most-recently-used first. Primary key is Last Used,
/// tiebroken by Last Updated, then title for a stable, total ordering.
int compareVaultEntriesByLastUsed(KdbxEntry a, KdbxEntry b) {
  final byUsed = effectiveLastUsedAt(b).compareTo(effectiveLastUsedAt(a));
  if (byUsed != 0) {
    return byUsed;
  }
  final byUpdated =
      effectiveLastUpdatedAt(b).compareTo(effectiveLastUpdatedAt(a));
  if (byUpdated != 0) {
    return byUpdated;
  }
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}
