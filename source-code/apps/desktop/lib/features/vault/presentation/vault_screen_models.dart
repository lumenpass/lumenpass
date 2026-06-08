part of 'vault_screen.dart';

class _NewItemType {
  const _NewItemType({
    required this.id,
    required this.label,
    this.icon,
    required this.iconColor,
    this.showPlus = false,
    this.imagePath,
  });

  final String id;
  final String label;
  final IconData? icon;
  final Color iconColor;
  final bool showPlus;
  final String? imagePath;
}

class _LoginCustomAttribute {
  _LoginCustomAttribute({
    required String label,
    required String value,
    this.isSecret = false,
  })  : labelController = TextEditingController(text: label),
        valueController = TextEditingController(text: value);

  final TextEditingController labelController;
  final TextEditingController valueController;
  final bool isSecret;

  bool get shouldProtect =>
      isSecret || AppKdbxFieldKeys.isProtectedKey(labelController.text.trim());

  void dispose() {
    labelController.dispose();
    valueController.dispose();
  }
}

class _LoginAttachment {
  const _LoginAttachment({
    required this.name,
    required this.size,
    required this.path,
    required this.isImage,
    this.bytes,
  });

  factory _LoginAttachment.fromPlatformFile(PlatformFile file) {
    final extension = file.extension?.toLowerCase() ?? '';
    const imageExtensions = <String>{
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'heic',
    };
    return _LoginAttachment(
      name: file.name,
      size: file.size,
      path: file.path,
      isImage: imageExtensions.contains(extension),
    );
  }

  factory _LoginAttachment.fromMockAttachment(_MockAttachment attachment) {
    return _LoginAttachment(
      name: attachment.name,
      size: _parseAttachmentSizeLabel(attachment.sizeLabel),
      path: null,
      isImage: attachment.isImage,
      bytes: attachment.bytes,
    );
  }

  final String name;
  final int size;
  final String? path;
  final bool isImage;
  final Uint8List? bytes;
}

class _EntryDetailFieldData {
  const _EntryDetailFieldData({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.labelColor,
    bool isSecret = false,
    bool showStrength = false,
  })  : _isSecret = isSecret,
        _showStrength = showStrength;

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color? labelColor;
  final bool? _isSecret;
  final bool? _showStrength;

  bool get isSecret => _isSecret ?? false;
  bool get showStrength => _showStrength ?? false;
}

class _MockEntry {
  const _MockEntry({
    required this.title,
    required this.subtitle,
    required this.dateLabel,
    required this.initials,
    required this.tileColor,
    required this.tileTextColor,
    required this.website,
    required this.username,
    required this.password,
    required this.notes,
    required this.totpAuthUrl,
    required this.attachments,
    this.tags = const <String>[],
    VaultItemType itemType = VaultItemType.login,
    List<_EntryDetailFieldData> detailFields = const <_EntryDetailFieldData>[],
    this.createdAt,
    this.updatedAt,
    this.uuid = '',
    this.groupUuid = '',
    this.hasPasskeyChip = false,
    this.metricLine,
    this.metricBadge,
    this.metricIcon,
    this.metricIconColor = _VaultColors.icon,
    this.showBanner = false,
    this.showMenu = false,
    this.selected = false,
    this.cardBrand,
    this.socialProvider = '',
    this.faviconPngBase64,
  })  : _itemType = itemType,
        _detailFields = detailFields;

  final String uuid;
  final String groupUuid;
  final String title;
  final String subtitle;
  final String dateLabel;
  final String initials;
  final Color tileColor;
  final Color tileTextColor;
  final bool hasPasskeyChip;
  final String? metricLine;
  final String? metricBadge;
  final IconData? metricIcon;
  final Color metricIconColor;
  final String website;
  final String username;
  final String password;
  final String notes;
  final String totpAuthUrl;
  final List<_MockAttachment> attachments;
  final List<String> tags;
  final VaultItemType? _itemType;
  final List<_EntryDetailFieldData>? _detailFields;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool showBanner;
  final bool showMenu;
  final bool selected;
  final _CardBrand? cardBrand;
  final String socialProvider;

  /// Mirror of [KdbxEntry.faviconPngBase64] — the cached favicon payload
  /// (base64 PNG) or the failure sentinel. `null` means we have not
  /// attempted to fetch yet.
  final String? faviconPngBase64;

  VaultItemType get itemType => _itemType ?? VaultItemType.login;
  List<_EntryDetailFieldData> get detailFields =>
      _detailFields ?? const <_EntryDetailFieldData>[];

  DateTime get lastTouchedAt =>
      _latestTimestamp(updatedAt, createdAt) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  _MockEntry copyWith({
    String? uuid,
    String? groupUuid,
    String? title,
    String? subtitle,
    String? dateLabel,
    String? initials,
    Color? tileColor,
    Color? tileTextColor,
    bool? hasPasskeyChip,
    String? metricLine,
    String? metricBadge,
    IconData? metricIcon,
    Color? metricIconColor,
    String? website,
    String? username,
    String? password,
    String? notes,
    String? totpAuthUrl,
    List<_MockAttachment>? attachments,
    List<String>? tags,
    VaultItemType? itemType,
    List<_EntryDetailFieldData>? detailFields,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? showBanner,
    bool? showMenu,
    bool? selected,
    _CardBrand? cardBrand,
    String? socialProvider,
  }) {
    return _MockEntry(
      uuid: uuid ?? this.uuid,
      groupUuid: groupUuid ?? this.groupUuid,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      dateLabel: dateLabel ?? this.dateLabel,
      initials: initials ?? this.initials,
      tileColor: tileColor ?? this.tileColor,
      tileTextColor: tileTextColor ?? this.tileTextColor,
      hasPasskeyChip: hasPasskeyChip ?? this.hasPasskeyChip,
      metricLine: metricLine ?? this.metricLine,
      metricBadge: metricBadge ?? this.metricBadge,
      metricIcon: metricIcon ?? this.metricIcon,
      metricIconColor: metricIconColor ?? this.metricIconColor,
      website: website ?? this.website,
      username: username ?? this.username,
      password: password ?? this.password,
      notes: notes ?? this.notes,
      totpAuthUrl: totpAuthUrl ?? this.totpAuthUrl,
      attachments: attachments ?? this.attachments,
      tags: tags ?? this.tags,
      itemType: itemType ?? this.itemType,
      detailFields: detailFields ?? this.detailFields,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      showBanner: showBanner ?? this.showBanner,
      showMenu: showMenu ?? this.showMenu,
      selected: selected ?? this.selected,
      cardBrand: cardBrand ?? this.cardBrand,
      socialProvider: socialProvider ?? this.socialProvider,
      faviconPngBase64: faviconPngBase64,
    );
  }
}

enum _CardBrand {
  visa,
  mastercard,
  amex,
  discover,
  diners,
  jcb,
  unionPay,
  maestro,
}

class _MockAttachment {
  const _MockAttachment({
    required this.name,
    required this.sizeLabel,
    required this.isImage,
    this.bytes,
  });

  final String name;
  final String sizeLabel;
  final bool isImage;
  final Uint8List? bytes;
}

const List<_NewItemType> _allNewItemTypes = <_NewItemType>[
  _NewItemType(
    id: 'login',
    label: 'Login',
    icon: TablerIcons.lock,
    iconColor: Color(0xFF2DA8B6),
  ),
  _NewItemType(
    id: 'secure-note',
    label: 'Secure Note',
    icon: TablerIcons.notes,
    iconColor: Color(0xFFE0A433),
    imagePath: 'assets/images/item_type_note.png',
  ),
  _NewItemType(
    id: 'credit-card',
    label: 'Credit Card',
    icon: TablerIcons.credit_card,
    iconColor: Color(0xFF4A9EE8),
  ),
  _NewItemType(
    id: 'identity',
    label: 'Identity',
    icon: TablerIcons.id,
    iconColor: Color(0xFF56B676),
    imagePath: 'assets/images/item_type_identity.png',
  ),
  _NewItemType(
    id: 'ssh-key',
    label: 'SSH Key',
    icon: TablerIcons.key,
    iconColor: Color(0xFF1D6570),
    showPlus: true,
    imagePath: 'assets/images/item_type_ssh.png',
  ),
  _NewItemType(
    id: 'document',
    label: 'Document',
    icon: TablerIcons.file_description,
    iconColor: Color(0xFF4F97F1),
  ),
  _NewItemType(
    id: 'bank-account',
    label: 'Bank Account',
    icon: TablerIcons.building_bank,
    iconColor: Color(0xFF1F9A76),
    imagePath: 'assets/images/item_type_bank.png',
  ),
  _NewItemType(
    id: 'api-credential',
    label: 'API Credential',
    icon: TablerIcons.key,
    iconColor: Color(0xFF8C57D9),
  ),
  _NewItemType(
    id: 'server',
    label: 'Server',
    icon: TablerIcons.server,
    iconColor: Color(0xFF4F97F1),
  ),
  _NewItemType(
    id: 'wifi-password',
    label: 'Wi-Fi Password',
    icon: TablerIcons.wifi,
    iconColor: Color(0xFFE0A433),
  ),
  _NewItemType(
    id: 'passport',
    label: 'Passport',
    icon: Icons.menu_book_outlined,
    iconColor: Color(0xFF2DA8B6),
  ),
];

const List<String> _loginAddMoreOptions = <String>[
  'Text',
  'Sensitive Text',
  'One-Time Password',
];

/// Shared by add and edit SSH key modals (keep in sync with each other).
const List<String> _sshKeyAddMoreOptions = <String>[
  'Passphrase',
  'Text',
  'Sensitive Text',
  'One-Time Password',
];

const List<(Color, Color)> _tilePalette = <(Color, Color)>[
  (Color(0xFFE5D6A4), Color(0xFF6E6546)),
  (Color(0xFFDDD7CC), Color(0xFF6A645A)),
  (Color(0xFFD7EACF), Color(0xFF5F7855)),
  (Color(0xFFE6DBF8), Color(0xFF6A5D86)),
  (Color(0xFFDCE5FA), Color(0xFF566789)),
  (Color(0xFFE4E8EF), Color(0xFF626B77)),
  (Color(0xFFFFE4E4), Color(0xFF885050)),
  (Color(0xFFE4F4FF), Color(0xFF476880)),
  (Color(0xFFFFF0D6), Color(0xFF7A5B1A)),
  (Color(0xFFD6F5EE), Color(0xFF2E6B58)),
];

const List<String> _monthAbbr = <String>[
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

_NewItemType? _newItemTypeForVaultType(VaultItemType itemType) {
  for (final candidate in _allNewItemTypes) {
    if (candidate.id == itemType.id) {
      return candidate;
    }
  }
  return null;
}

String _entrySubtitleForList(KdbxEntry entry, VaultItemType itemType) {
  if (itemType == VaultItemType.sshKey) {
    final sshPreview = _sshSubtitlePreview(entry);
    if (sshPreview.isNotEmpty) {
      return sshPreview;
    }
  }
  if (itemType == VaultItemType.creditCard) {
    final creditCardPreview = _creditCardSubtitlePreview(entry);
    if (creditCardPreview.isNotEmpty) {
      return creditCardPreview;
    }
  }

  final username = entry.username?.trim() ?? '';
  if (username.isNotEmpty) {
    return _truncateListPreview(_singleLinePreview(username), 56);
  }

  final website = entry.url?.trim() ?? '';
  if (website.isNotEmpty) {
    return _truncateListPreview(
        _singleLinePreview(_compactWebsite(website)), 56);
  }

  final notePreview = _singleLinePreview(entry.notes ?? '');
  if (notePreview.isNotEmpty) {
    return _truncateListPreview(notePreview, 56);
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
        AppKdbxFieldKeys.isAttachmentMetaKey(key) ||
        field.isProtected ||
        AppKdbxFieldKeys.isProtectedKey(key)) {
      continue;
    }

    final value = _singleLinePreview(field.value);
    if (value.isNotEmpty) {
      return _truncateListPreview(value, 56);
    }
  }

  return '';
}

String _creditCardSubtitlePreview(KdbxEntry entry) {
  final cardholder = _extractCreditCardholder(entry);
  final maskedLast4 = _maskedCreditCardLast4(_extractCreditCardNumber(entry));

  if (cardholder.isNotEmpty && maskedLast4.isNotEmpty) {
    return _truncateListPreview('$cardholder $maskedLast4', 56);
  }
  if (cardholder.isNotEmpty) {
    return _truncateListPreview(cardholder, 56);
  }
  if (maskedLast4.isNotEmpty) {
    return _truncateListPreview(maskedLast4, 56);
  }
  return '';
}

String _extractCreditCardholder(KdbxEntry entry) {
  const holderKeyHints = <String>[
    'cardholder',
    'name on card',
    'cardholder name',
    'card holder',
  ];
  for (final field in entry.fields) {
    final key = field.key.trim().toLowerCase();
    if (holderKeyHints.any(key.contains)) {
      final value = _singleLinePreview(field.value);
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return _singleLinePreview(entry.username?.trim() ?? '');
}

String _maskedCreditCardLast4(String rawNumber) {
  final digits = rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return '';
  }
  final last4 =
      digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  return 'xxx$last4';
}

String _sshSubtitlePreview(KdbxEntry entry) {
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
    return _truncateListPreview(_singleLinePreview(fingerprint), 56);
  }

  final privateKey = findFieldValue(
    const <String>['private key', 'openssh', 'pem'],
    includeValue: true,
    includeProtected: true,
  );
  if (privateKey != null && privateKey.isNotEmpty) {
    final contentPrev = _sshKeyContentPreview(privateKey);
    if (contentPrev != null) {
      return _truncateListPreview(contentPrev, 56);
    }
    final inferredType = _inferSshKeyType(privateKey);
    if (inferredType.isNotEmpty) {
      return '$inferredType private key';
    }
    return 'Private key imported';
  }

  final publicKey = findFieldValue(
    const <String>['public key', 'authorized key'],
    includeValue: true,
  );
  if (publicKey != null && publicKey.isNotEmpty) {
    return _truncateListPreview(_singleLinePreview(publicKey), 56);
  }

  final keyType = findFieldValue(const <String>['key type', 'algorithm']);
  if (keyType != null && keyType.isNotEmpty) {
    return _truncateListPreview('${_singleLinePreview(keyType)} key', 56);
  }

  return '';
}

String _inferSshKeyType(String source) {
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

String _singleLinePreview(String input) {
  return input.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _truncateListPreview(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength - 1)}…';
}

String _compactWebsite(String rawUrl) {
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

// Per-entry cache for the (relatively expensive) KDBX→_MockEntry projection.
// Invalidated automatically when the entry's `updatedAt` changes, so saves
// that bump the timestamp (the normal path for edits) cause a recompute.
// Deleted entries leak at most one cache slot per uuid until
// `_clearMockEntryCache()` is called on vault teardown.
class _MockEntryCacheItem {
  _MockEntryCacheItem(this.updatedAt, this.mock);

  final DateTime? updatedAt;
  final _MockEntry mock;
}

final Map<String, _MockEntryCacheItem> _mockEntryCache =
    <String, _MockEntryCacheItem>{};

void _clearMockEntryCache() {
  _mockEntryCache.clear();
}

_MockEntry _mockEntryFromKdbx(KdbxEntry entry) {
  final cached = _mockEntryCache[entry.uuid];
  if (cached != null && cached.updatedAt == entry.updatedAt) {
    return cached.mock;
  }
  final mock = _computeMockEntryFromKdbx(entry);
  _mockEntryCache[entry.uuid] = _MockEntryCacheItem(entry.updatedAt, mock);
  return mock;
}

_MockEntry _computeMockEntryFromKdbx(KdbxEntry entry) {
  final itemType = classifyVaultItemType(entry);
  final colorIndex = entry.title.hashCode.abs() % _tilePalette.length;
  final (tileColor, tileTextColor) = _tilePalette[colorIndex];

  final raw = entry.title.trim();
  final initials = raw.length >= 2 ? raw.substring(0, 2) : raw;

  final subtitle = _entrySubtitleForList(entry, itemType);

  final updatedAt = _latestTimestamp(entry.updatedAt, entry.createdAt);
  final String dateLabel;
  if (updatedAt == null) {
    dateLabel = '';
  } else {
    final now = DateTime.now();
    final diff = now.difference(updatedAt);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (diff.inDays == 0) {
      dateLabel =
          'Today ${twoDigits(updatedAt.hour)}:${twoDigits(updatedAt.minute)}';
    } else if (diff.inDays == 1) {
      dateLabel = 'Yesterday';
    } else if (updatedAt.year == now.year || updatedAt.isAfter(now)) {
      dateLabel = '${_monthAbbr[updatedAt.month - 1]} ${updatedAt.day}';
    } else {
      dateLabel =
          '${_monthAbbr[updatedAt.month - 1]} ${updatedAt.day}, ${updatedAt.year}';
    }
  }

  final password = entry.fieldByKey(AppKdbxFieldKeys.password)?.value ?? '';
  final hasTotp = entry.otpAuthUrl != null && entry.otpAuthUrl!.isNotEmpty;
  final hasPasskey = entry.fields.any(
    (f) => f.key.toLowerCase().contains('passkey'),
  );

  final socialProviderField = entry.fields
      .where((f) => !f.isProtected && f.key == 'lp_social_provider')
      .firstOrNull;
  final socialProvider = socialProviderField?.value.trim() ?? '';

  final attachments = _attachmentsFromEntry(entry);
  final cardBrand = itemType == VaultItemType.creditCard
      ? _detectCardBrand(_extractCreditCardNumber(entry))
      : null;

  return _MockEntry(
    uuid: entry.uuid,
    groupUuid: entry.groupUuid,
    title: entry.title,
    subtitle: subtitle,
    dateLabel: dateLabel,
    initials: initials,
    tileColor: tileColor,
    tileTextColor: tileTextColor,
    website: entry.url ?? '',
    username: entry.username ?? '',
    password: password,
    notes: entry.notes ?? '',
    totpAuthUrl: entry.otpAuthUrl ?? '',
    attachments: attachments,
    tags: entry.tags,
    itemType: itemType,
    detailFields: _buildDetailFields(entry, itemType),
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
    hasPasskeyChip: hasPasskey,
    metricLine: hasTotp ? 'totp' : null,
    metricIcon: hasTotp ? TablerIcons.clock : null,
    cardBrand: cardBrand,
    socialProvider: socialProvider,
    faviconPngBase64: entry.faviconPngBase64,
  );
}

String _extractCreditCardNumber(KdbxEntry entry) {
  const cardNumberKeys = <String>{
    'card number',
    'card no',
    'credit card number',
    'cc number',
    'pan',
    'number',
  };

  for (final field in entry.fields) {
    final key = field.key.trim().toLowerCase();
    if (cardNumberKeys.contains(key)) {
      return field.value;
    }
  }

  return '';
}

_CardBrand? _detectCardBrand(String rawNumber) {
  final digits = rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return null;
  }

  bool startsWithAny(Iterable<String> prefixes) =>
      prefixes.any(digits.startsWith);

  final prefix2 =
      digits.length >= 2 ? int.tryParse(digits.substring(0, 2)) : null;
  final prefix3 =
      digits.length >= 3 ? int.tryParse(digits.substring(0, 3)) : null;
  final prefix4 =
      digits.length >= 4 ? int.tryParse(digits.substring(0, 4)) : null;
  final prefix6 =
      digits.length >= 6 ? int.tryParse(digits.substring(0, 6)) : null;

  if (digits.startsWith('4')) {
    return _CardBrand.visa;
  }
  if ((prefix2 != null && prefix2 >= 51 && prefix2 <= 55) ||
      (prefix4 != null && prefix4 >= 2221 && prefix4 <= 2720)) {
    return _CardBrand.mastercard;
  }
  if (startsWithAny(const <String>['34', '37'])) {
    return _CardBrand.amex;
  }
  if (startsWithAny(const <String>['6011', '65']) ||
      (prefix3 != null && prefix3 >= 644 && prefix3 <= 649) ||
      (prefix6 != null && prefix6 >= 622126 && prefix6 <= 622925)) {
    return _CardBrand.discover;
  }
  if (startsWithAny(const <String>[
    '300',
    '301',
    '302',
    '303',
    '304',
    '305',
    '36',
    '38',
    '39'
  ])) {
    return _CardBrand.diners;
  }
  if (prefix4 != null && prefix4 >= 3528 && prefix4 <= 3589) {
    return _CardBrand.jcb;
  }
  if (startsWithAny(const <String>['62'])) {
    return _CardBrand.unionPay;
  }
  if (startsWithAny(const <String>['50', '56', '57', '58', '6'])) {
    return _CardBrand.maestro;
  }

  return null;
}

DateTime? _latestTimestamp(DateTime? a, DateTime? b) {
  if (a == null) {
    return b;
  }
  if (b == null) {
    return a;
  }
  return a.isAfter(b) ? a : b;
}

List<_EntryDetailFieldData> _buildDetailFields(
  KdbxEntry entry,
  VaultItemType itemType,
) {
  final normalizedStandardKeys =
      AppKdbxFieldKeys.standardKeys.map((key) => key.toLowerCase()).toSet();
  final fields = entry.fields
      .where((field) => field.value.trim().isNotEmpty)
      .toList(growable: false);
  final consumedIndexes = <int>{};
  final detailFields = <_EntryDetailFieldData>[];

  void consumeMatchingKeys(Iterable<String> keys) {
    final normalizedKeys = keys.map((key) => key.toLowerCase()).toSet();
    for (var index = 0; index < fields.length; index++) {
      if (normalizedKeys.contains(fields[index].key.toLowerCase())) {
        consumedIndexes.add(index);
      }
    }
  }

  bool hasUnconsumedKey(String key) {
    final normalizedKey = key.toLowerCase();
    for (var index = 0; index < fields.length; index++) {
      if (consumedIndexes.contains(index)) {
        continue;
      }
      if (fields[index].key.toLowerCase() == normalizedKey) {
        return true;
      }
    }
    return false;
  }

  void addField({
    required String label,
    required String value,
    String? sourceKey,
    bool isSecret = false,
    bool showStrength = false,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (_shouldHideFromDetailFields(label: label, sourceKey: sourceKey)) {
      return;
    }

    final effectiveIsSecret = isSecret ||
        AppKdbxFieldKeys.isProtectedKey(sourceKey ?? label) ||
        AppKdbxFieldKeys.isProtectedKey(label);
    final visual = _fieldVisualFor(
      sourceKey: sourceKey ?? label,
      label: label,
      itemType: itemType,
      isSecret: effectiveIsSecret,
    );
    detailFields.add(
      _EntryDetailFieldData(
        label: label,
        value: trimmed,
        icon: visual.icon,
        iconColor: visual.iconColor,
        labelColor: visual.labelColor,
        isSecret: effectiveIsSecret,
        showStrength: showStrength,
      ),
    );
  }

  void addMappedField({
    required String label,
    required List<String> matches,
    bool isSecret = false,
    bool showStrength = false,
    String Function(String)? valueTransformer,
  }) {
    for (var index = 0; index < fields.length; index++) {
      if (consumedIndexes.contains(index)) {
        continue;
      }

      final field = fields[index];
      final normalizedKey = field.key.toLowerCase();
      final normalizedValue = field.value.toLowerCase();
      if (normalizedStandardKeys.contains(normalizedKey)) {
        continue;
      }
      final isMatch = matches.any(
        (match) =>
            normalizedKey.contains(match) || normalizedValue.contains(match),
      );
      if (!isMatch) {
        continue;
      }

      consumedIndexes.add(index);
      addField(
        label: label,
        value: valueTransformer != null
            ? valueTransformer(field.value)
            : field.value,
        sourceKey: field.key,
        isSecret: isSecret || field.isProtected,
        showStrength: showStrength,
      );
      return;
    }
  }

  void addStandardWebsite() {
    final website = entry.url?.trim() ?? '';
    if (website.isEmpty) {
      return;
    }
    consumeMatchingKeys(const <String>[AppKdbxFieldKeys.url]);
    addField(
      label: 'Website',
      value: website,
      sourceKey: AppKdbxFieldKeys.url,
    );
  }

  void addStandardUsername({String label = 'Username'}) {
    final username = entry.username?.trim() ?? '';
    if (username.isEmpty) {
      return;
    }
    consumeMatchingKeys(const <String>[AppKdbxFieldKeys.userName]);
    addField(
      label: label,
      value: username,
      sourceKey: AppKdbxFieldKeys.userName,
    );
  }

  void addStandardPassword({String label = 'Password'}) {
    final password =
        entry.fieldByKey(AppKdbxFieldKeys.password)?.value.trim() ?? '';
    if (password.isEmpty) {
      return;
    }
    consumeMatchingKeys(const <String>[AppKdbxFieldKeys.password]);
    addField(
      label: label,
      value: password,
      sourceKey: AppKdbxFieldKeys.password,
      isSecret: true,
      showStrength: true,
    );
  }

  switch (itemType) {
    case VaultItemType.creditCard:
      addMappedField(
        label: 'Cardholder',
        matches: const <String>[
          'cardholder',
          'name on card',
          'cardholder name',
          'card holder',
        ],
      );
      if (detailFields.isEmpty &&
          (entry.username?.trim().isNotEmpty ?? false)) {
        addStandardUsername(label: 'Cardholder');
      }
      addMappedField(
        label: 'Card Number',
        matches: const <String>[
          'card number',
          'card no',
          'credit card number',
          'cc number',
          'pan',
        ],
      );
      addMappedField(
        label: 'Expiry Date',
        matches: const <String>[
          'expiry',
          'expiration',
          'exp date',
          'valid thru',
          'valid through',
        ],
        valueTransformer: _formatCardDate,
      );
      addMappedField(
        label: 'Valid From',
        matches: const <String>['valid from'],
        valueTransformer: _formatCardDate,
      );
      addMappedField(
        label: 'CVC',
        matches: const <String>['cvc', 'cvv', 'cvn', 'security code'],
        isSecret: true,
      );
      addMappedField(
        label: 'PIN',
        matches: const <String>['pin'],
        isSecret: true,
      );
      addStandardWebsite();
      break;
    case VaultItemType.bankAccount:
      addMappedField(
        label: 'Account Holder',
        matches: const <String>[
          'account holder',
          'holder name',
          'beneficiary',
        ],
      );
      addMappedField(
        label: 'Bank Name',
        matches: const <String>['bank name', 'bank'],
      );
      addMappedField(
        label: 'Account Number',
        matches: const <String>['account number', 'acct number', 'iban'],
      );
      addMappedField(
        label: 'Routing Number',
        matches: const <String>['routing', 'sort code', 'transit'],
      );
      addMappedField(
        label: 'SWIFT / BIC',
        matches: const <String>['swift', 'bic'],
      );
      addStandardWebsite();
      break;
    case VaultItemType.identity:
      addMappedField(
        label: 'Full Name',
        matches: const <String>['full name', 'name'],
      );
      addMappedField(
        label: 'Email',
        matches: const <String>['email', 'e-mail'],
      );
      addMappedField(
        label: 'Phone',
        matches: const <String>['phone', 'mobile', 'telephone'],
      );
      addMappedField(
        label: 'Address',
        matches: const <String>['address', 'street', 'city', 'postal'],
      );
      addMappedField(
        label: 'ID Number',
        matches: const <String>[
          'id number',
          'identity number',
          'driver license',
          'driver licence',
        ],
      );
      break;
    case VaultItemType.sshKey:
      addMappedField(
        label: 'Private Key',
        matches: const <String>['private key', 'ssh key', 'pem', 'openssh'],
        isSecret: true,
      );
      addMappedField(
        label: 'Public Key',
        matches: const <String>['public key', 'authorized key'],
      );
      addMappedField(
        label: 'Passphrase',
        matches: const <String>['passphrase'],
        isSecret: true,
      );
      addMappedField(
        label: 'Fingerprint',
        matches: const <String>['fingerprint'],
      );
      break;
    case VaultItemType.document:
      addStandardWebsite();
      addMappedField(
        label: 'Document ID',
        matches: const <String>['document id', 'serial number', 'reference'],
      );
      break;
    case VaultItemType.apiCredential:
      addMappedField(
        label: 'Client ID',
        matches: const <String>['client id', 'app id'],
      );
      addMappedField(
        label: 'Client Secret',
        matches: const <String>['client secret'],
        isSecret: true,
      );
      addMappedField(
        label: 'Access Token',
        matches: const <String>['access token', 'bearer token'],
        isSecret: true,
      );
      addMappedField(
        label: 'API Key',
        matches: const <String>['api key', 'secret key'],
        isSecret: true,
      );
      addStandardWebsite();
      break;
    case VaultItemType.server:
      addMappedField(
        label: 'Host',
        matches: const <String>['hostname', 'host', 'ip address'],
      );
      addMappedField(
        label: 'Port',
        matches: const <String>['port'],
      );
      addStandardUsername();
      addStandardPassword();
      addMappedField(
        label: 'Private Key',
        matches: const <String>['private key'],
        isSecret: true,
      );
      addMappedField(
        label: 'Public Key',
        matches: const <String>['public key'],
      );
      addStandardWebsite();
      break;
    case VaultItemType.wifiPassword:
      addMappedField(
        label: 'SSID',
        matches: const <String>['ssid', 'network name'],
      );
      addMappedField(
        label: 'Security',
        matches: const <String>['security', 'wireless type'],
      );
      addStandardPassword();
      break;
    case VaultItemType.passport:
      addMappedField(
        label: 'Passport Number',
        matches: const <String>['passport number', 'passport no'],
      );
      addMappedField(
        label: 'Full Name',
        matches: const <String>['full name', 'name'],
      );
      addMappedField(
        label: 'Nationality',
        matches: const <String>['nationality'],
      );
      addMappedField(
        label: 'Expiry Date',
        matches: const <String>['expiry', 'expiration', 'exp date'],
      );
      break;
    case VaultItemType.secureNote:
      addStandardWebsite();
      break;
    case VaultItemType.login:
      addStandardWebsite();
      addStandardUsername();
      addStandardPassword();
      break;
  }

  // Item-type heuristics should never suppress real saved standard fields.
  if (hasUnconsumedKey(AppKdbxFieldKeys.userName)) {
    addStandardUsername();
  }
  if (hasUnconsumedKey(AppKdbxFieldKeys.password)) {
    addStandardPassword();
  }
  if (hasUnconsumedKey(AppKdbxFieldKeys.url)) {
    addStandardWebsite();
  }

  for (var index = 0; index < fields.length; index++) {
    if (consumedIndexes.contains(index)) {
      continue;
    }

    final field = fields[index];
    if (normalizedStandardKeys.contains(field.key.toLowerCase())) {
      continue;
    }

    addField(
      label: _displayLabelForFieldKey(field.key),
      value: field.value,
      sourceKey: field.key,
      isSecret: field.isProtected,
      showStrength:
          field.key.toLowerCase() == AppKdbxFieldKeys.password.toLowerCase(),
    );
  }

  return detailFields;
}

String _formatCardDate(String value) {
  final trimmed = value.trim();
  // YYYY-MM → MM / YYYY
  final m1 = RegExp(r'^(\d{4})[/\-](\d{1,2})$').firstMatch(trimmed);
  if (m1 != null) {
    return '${m1.group(2)!.padLeft(2, '0')} / ${m1.group(1)}';
  }
  // MM/YYYY or MM-YYYY → MM / YYYY
  final m2 = RegExp(r'^(\d{1,2})[/\-](\d{4})$').firstMatch(trimmed);
  if (m2 != null) {
    return '${m2.group(1)!.padLeft(2, '0')} / ${m2.group(2)}';
  }
  return value;
}

bool _shouldHideFromDetailFields({
  required String label,
  String? sourceKey,
}) {
  final normalizedLabel = label.toLowerCase().trim();
  final normalizedSourceKey = sourceKey?.toLowerCase().trim() ?? '';

  if (normalizedSourceKey == 'lp_social_provider' ||
      normalizedSourceKey == 'lp_social_label') {
    return true;
  }

  final combined = '$normalizedSourceKey $normalizedLabel';
  final isPasskeyInternalField =
      normalizedSourceKey.contains('kpex_passkey_') ||
          combined.contains('kpex passkey') ||
          (combined.contains('passkey') &&
              (combined.contains('credential id') ||
                  combined.contains('relying party') ||
                  combined.contains('user handle') ||
                  combined.contains('private key') ||
                  combined.contains('username')));

  return normalizedLabel == 'otp' ||
      AppKdbxFieldKeys.isAttachmentMetaKey(sourceKey ?? '') ||
      normalizedLabel == 'totp' ||
      normalizedSourceKey == 'otp' ||
      normalizedSourceKey == 'totp' ||
      combined.contains('otp auth') ||
      combined.contains('otpauth') ||
      combined.contains('time otp') ||
      combined.contains('time otp secret') ||
      combined.contains('totp secret') ||
      combined.contains('base32') ||
      isPasskeyInternalField;
}

List<_MockAttachment> _attachmentsFromEntry(KdbxEntry entry) {
  final namesByIndex = <int, String>{};
  final sizesByIndex = <int, int>{};
  final isImageByIndex = <int, bool>{};

  for (final field in entry.fields) {
    final key = field.key;
    if (key.startsWith(AppKdbxFieldKeys.attachmentNamePrefix)) {
      final index = int.tryParse(
        key.substring(AppKdbxFieldKeys.attachmentNamePrefix.length),
      );
      if (index != null && field.value.trim().isNotEmpty) {
        namesByIndex[index] = field.value.trim();
      }
      continue;
    }
    if (key.startsWith(AppKdbxFieldKeys.attachmentSizePrefix)) {
      final index = int.tryParse(
        key.substring(AppKdbxFieldKeys.attachmentSizePrefix.length),
      );
      final size = int.tryParse(field.value.trim());
      if (index != null && size != null && size >= 0) {
        sizesByIndex[index] = size;
      }
      continue;
    }
    if (key.startsWith(AppKdbxFieldKeys.attachmentImagePrefix)) {
      final index = int.tryParse(
        key.substring(AppKdbxFieldKeys.attachmentImagePrefix.length),
      );
      if (index != null) {
        final marker = field.value.trim().toLowerCase();
        isImageByIndex[index] = marker == '1' || marker == 'true';
      }
    }
  }

  final indexes = namesByIndex.keys.toList()..sort();
  return indexes
      .map(
        (index) => _MockAttachment(
          name: namesByIndex[index]!,
          sizeLabel: _formatAttachmentSizeLabel(sizesByIndex[index] ?? 0),
          isImage: isImageByIndex[index] ?? false,
        ),
      )
      .toList(growable: false);
}

String _formatAttachmentSizeLabel(int bytes) {
  if (bytes >= 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
  if (bytes >= 1024) {
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
  return '$bytes B';
}

int _parseAttachmentSizeLabel(String sizeLabel) {
  final match = RegExp(
    r'^([\d.]+)\s*(B|KB|MB|GB)$',
    caseSensitive: false,
  ).firstMatch(sizeLabel.trim());
  if (match == null) {
    return 0;
  }
  final value = double.tryParse(match.group(1) ?? '');
  if (value == null) {
    return 0;
  }
  const multipliers = <String, int>{
    'B': 1,
    'KB': 1024,
    'MB': 1024 * 1024,
    'GB': 1024 * 1024 * 1024,
  };
  final unit = (match.group(2) ?? 'B').toUpperCase();
  return (value * (multipliers[unit] ?? 1)).round();
}

String _displayLabelForFieldKey(String key) {
  const directLabels = <String, String>{
    'url': 'Website',
    'username': 'Username',
    'user name': 'Username',
    'otp auth': 'OTP',
    'otpauth': 'OTP',
    'cvv': 'CVV',
    'cvc': 'CVC',
    'ssid': 'SSID',
    'iban': 'IBAN',
  };

  final spaced = key
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (spaced.isEmpty) {
    return key;
  }

  final normalized = spaced.toLowerCase();
  if (directLabels.containsKey(normalized)) {
    return directLabels[normalized]!;
  }

  return spaced.split(' ').map((part) {
    final upper = part.toUpperCase();
    if (upper.length <= 4 && RegExp(r'^[A-Z0-9]+$').hasMatch(upper)) {
      return upper;
    }
    return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
  }).join(' ');
}

({IconData icon, Color iconColor, Color? labelColor}) _fieldVisualFor({
  required String sourceKey,
  required String label,
  required VaultItemType itemType,
  required bool isSecret,
}) {
  final normalized = '${sourceKey.toLowerCase()} ${label.toLowerCase()}';

  if (normalized.contains('url') || normalized.contains('website')) {
    return (
      icon: TablerIcons.world_www,
      iconColor: const Color(0xFF635BDB),
      labelColor: const Color(0xFF635BDB),
    );
  }
  if (normalized.contains('email')) {
    return (
      icon: Icons.alternate_email_rounded,
      iconColor: const Color(0xFF5C7CFA),
      labelColor: null,
    );
  }
  if (normalized.contains('username') ||
      normalized.contains('cardholder') ||
      normalized.contains('full name') ||
      normalized.contains('account holder') ||
      normalized.contains('holder')) {
    return (
      icon: TablerIcons.user,
      iconColor: const Color(0xFF5C7CFA),
      labelColor: null,
    );
  }
  if (normalized.contains('card') ||
      normalized.contains('cvv') ||
      normalized.contains('cvc') ||
      itemType == VaultItemType.creditCard) {
    return (
      icon: TablerIcons.credit_card,
      iconColor: const Color(0xFF4A9EE8),
      labelColor: null,
    );
  }
  if (normalized.contains('expiry') ||
      normalized.contains('expiration') ||
      normalized.contains('date')) {
    return (
      icon: Icons.calendar_today_outlined,
      iconColor: const Color(0xFF2DA8B6),
      labelColor: null,
    );
  }
  if (normalized.contains('bank') ||
      normalized.contains('routing') ||
      normalized.contains('iban') ||
      normalized.contains('swift') ||
      normalized.contains('bic')) {
    return (
      icon: TablerIcons.building_bank,
      iconColor: const Color(0xFF1F9A76),
      labelColor: null,
    );
  }
  if (normalized.contains('host') ||
      normalized.contains('server') ||
      normalized.contains('port') ||
      normalized.contains('ip')) {
    return (
      icon: TablerIcons.server,
      iconColor: const Color(0xFF4F97F1),
      labelColor: null,
    );
  }
  if (normalized.contains('wifi') || normalized.contains('ssid')) {
    return (
      icon: TablerIcons.wifi,
      iconColor: const Color(0xFFE0A433),
      labelColor: null,
    );
  }
  if (normalized.contains('passport') || normalized.contains('identity')) {
    return (
      icon: TablerIcons.id_badge_2,
      iconColor: const Color(0xFF56B676),
      labelColor: null,
    );
  }
  if (normalized.contains('private key') ||
      normalized.contains('public key') ||
      normalized.contains('fingerprint') ||
      normalized.contains('ssh')) {
    return (
      icon: TablerIcons.key,
      iconColor: const Color(0xFF1D6570),
      labelColor: null,
    );
  }
  if (normalized.contains('password') || normalized.contains('passphrase')) {
    return (
      icon: TablerIcons.lock,
      iconColor: const Color(0xFF5E6B7D),
      labelColor: null,
    );
  }
  if (normalized.contains('phone')) {
    return (
      icon: Icons.phone_outlined,
      iconColor: const Color(0xFF2DA8B6),
      labelColor: null,
    );
  }
  if (normalized.contains('address')) {
    return (
      icon: Icons.location_on_outlined,
      iconColor: const Color(0xFF56B676),
      labelColor: null,
    );
  }
  if (isSecret) {
    return (
      icon: TablerIcons.key,
      iconColor: const Color(0xFFC08A1A),
      labelColor: null,
    );
  }

  return (
    icon: Icons.label_outline_rounded,
    iconColor: const Color(0xFF8A97AC),
    labelColor: null,
  );
}

// ignore: unused_element
const List<_MockEntry> _mockEntries = <_MockEntry>[
  _MockEntry(
    title: 'GitHub',
    subtitle: 'mlserver56@gmail.com',
    dateLabel: 'Today',
    initials: 'Mi',
    tileColor: Color(0xFFE5D6A4),
    tileTextColor: Color(0xFF6E6546),
    hasPasskeyChip: true,
    metricLine: '132 • 132',
    metricBadge: '04',
    metricIcon: TablerIcons.clock,
    metricIconColor: Color(0xFFDE8A2E),
    website: 'https://github.com/login',
    username: 'alex@lumenpass.app',
    password: '••••••••••••',
    notes: 'MFA via authenticator. Recovery keys in secure note.',
    totpAuthUrl:
        'otpauth://totp/GitHub:alex@lumenpass.app?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30',
    attachments: <_MockAttachment>[
      _MockAttachment(
        name: 'qr-backup.png',
        sizeLabel: '842 KB',
        isImage: true,
      ),
      _MockAttachment(
        name: 'recovery-codes.pdf',
        sizeLabel: '214 KB',
        isImage: false,
      ),
    ],
    showBanner: true,
    showMenu: true,
    selected: true,
  ),
  _MockEntry(
    title: 'Notion',
    subtitle: 'workspace account — long note preview...',
    dateLabel: 'Yesterday',
    initials: 'No',
    tileColor: Color(0xFFDDD7CC),
    tileTextColor: Color(0xFF6A645A),
    website: 'https://notion.so/login',
    username: 'workspace@company.com',
    password: '••••••••••••',
    notes: 'Workspace recovery methods and SSO backup codes.',
    totpAuthUrl:
        'otpauth://totp/Notion:workspace@company.com?secret=KRSXG5DSNFXGOIDB&issuer=Notion&algorithm=SHA1&digits=6&period=30',
    attachments: <_MockAttachment>[
      _MockAttachment(
        name: 'workspace-policy.pdf',
        sizeLabel: '194 KB',
        isImage: false,
      ),
      _MockAttachment(
        name: 'device-setup.png',
        sizeLabel: '422 KB',
        isImage: true,
      ),
    ],
  ),
  _MockEntry(
    title: 'AWS Console',
    subtitle: 'root+prod@company.io',
    dateLabel: 'Mar 27',
    initials: 'Aw',
    tileColor: Color(0xFFD7EACF),
    tileTextColor: Color(0xFF5F7855),
    hasPasskeyChip: true,
    website: 'https://signin.aws.amazon.com',
    username: 'root+prod@company.io',
    password: '••••••••••••',
    notes: 'Hardware key required for root login. Use break-glass flow only.',
    totpAuthUrl:
        'otpauth://totp/AWS%20Console:root+prod@company.io?secret=IFBEGRCFIZDUQSKK&issuer=AWS%20Console&algorithm=SHA1&digits=6&period=30',
    attachments: <_MockAttachment>[
      _MockAttachment(
        name: 'root-contact-card.pdf',
        sizeLabel: '120 KB',
        isImage: false,
      ),
      _MockAttachment(
        name: 'backup-key.jpg',
        sizeLabel: '736 KB',
        isImage: true,
      ),
    ],
  ),
  _MockEntry(
    title: 'Figma',
    subtitle: 'design-team@company.com',
    dateLabel: 'Mar 22',
    initials: 'Fi',
    tileColor: Color(0xFFE6DBF8),
    tileTextColor: Color(0xFF6A5D86),
    website: 'https://www.figma.com/login',
    username: 'design-team@company.com',
    password: '••••••••••••',
    notes: 'Use shared design mailbox. Seat ownership belongs to brand team.',
    totpAuthUrl:
        'otpauth://totp/Figma:design-team@company.com?secret=MFRGGZDFMZTWQ2LK&issuer=Figma&algorithm=SHA1&digits=6&period=30',
    attachments: <_MockAttachment>[
      _MockAttachment(
        name: 'team-seat-sheet.pdf',
        sizeLabel: '88 KB',
        isImage: false,
      ),
      _MockAttachment(
        name: 'brand-board.png',
        sizeLabel: '301 KB',
        isImage: true,
      ),
    ],
  ),
  _MockEntry(
    title: 'Stripe',
    subtitle: 'billing-admin@startup.io',
    dateLabel: 'Mar 19',
    initials: 'St',
    tileColor: Color(0xFFDCE5FA),
    tileTextColor: Color(0xFF566789),
    metricLine: '907 • 441',
    metricBadge: '09',
    metricIcon: TablerIcons.shield,
    metricIconColor: Color(0xFF16A34A),
    website: 'https://dashboard.stripe.com/login',
    username: 'billing-admin@startup.io',
    password: '••••••••••••',
    notes:
        'Finance team only. Card updates must be mirrored in 1Password note.',
    totpAuthUrl:
        'otpauth://totp/Stripe:billing-admin@startup.io?secret=ONSWG4TFORVWK6LE&issuer=Stripe&algorithm=SHA1&digits=6&period=30',
    attachments: <_MockAttachment>[
      _MockAttachment(
        name: 'banking-rules.pdf',
        sizeLabel: '144 KB',
        isImage: false,
      ),
      _MockAttachment(
        name: 'finance-qr.png',
        sizeLabel: '412 KB',
        isImage: true,
      ),
    ],
  ),
  _MockEntry(
    title: 'Linear',
    subtitle: 'Project tracker note preview text...',
    dateLabel: 'Mar 14',
    initials: 'Li',
    tileColor: Color(0xFFE4E8EF),
    tileTextColor: Color(0xFF626B77),
    hasPasskeyChip: true,
    website: 'https://linear.app/login',
    username: 'ops@company.io',
    password: '••••••••••••',
    notes: 'Shared project workspace. Emergency access expires weekly.',
    totpAuthUrl:
        'otpauth://totp/Linear:ops@company.io?secret=NBSWY3DPO5XXE3DE&issuer=Linear&algorithm=SHA1&digits=6&period=30',
    attachments: <_MockAttachment>[
      _MockAttachment(
        name: 'incident-guide.pdf',
        sizeLabel: '210 KB',
        isImage: false,
      ),
      _MockAttachment(
        name: 'workspace-backup.png',
        sizeLabel: '642 KB',
        isImage: true,
      ),
    ],
  ),
];

// ── KDBX field helpers (shared by add + edit item flows) ───────────────────

String editCcFieldValueFromKdbx(KdbxEntry kdbx, String label) {
  switch (label.trim().toLowerCase()) {
    case 'cardholder name':
      return kdbx.username ??
          kdbx.fieldByKey('Cardholder Name')?.value ??
          kdbx.fieldByKey('cardholder name')?.value ??
          '';
    case 'number':
      for (final key in creditCardStorageKeysForLabel(label)) {
        final value = kdbx.fieldByKey(key)?.value ?? '';
        if (value.isNotEmpty) {
          return value;
        }
      }
      return '';
    case 'website':
      return kdbx.url ??
          kdbx.fieldByKey('Website')?.value ??
          kdbx.fieldByKey('website')?.value ??
          '';
    default:
      for (final key in creditCardStorageKeysForLabel(label)) {
        final value = kdbx.fieldByKey(key)?.value ?? '';
        if (value.isNotEmpty) {
          return value;
        }
      }
      return kdbx.fieldByKey(label.trim())?.value ?? '';
  }
}

Set<String> creditCardStorageKeysForLabel(String label) {
  switch (label.trim().toLowerCase()) {
    case 'cardholder name':
      return <String>{'Cardholder Name', 'cardholder name'};
    case 'number':
      return <String>{'Card Number', 'card number', 'number'};
    case 'verification number':
      return <String>{'CVC', 'CVV', 'verification number'};
    case 'expiry date':
      return <String>{'Expiry Date', 'expiry date'};
    case 'valid from':
      return <String>{'Valid From', 'valid from'};
    case 'issuing bank':
      return <String>{'Issuing Bank', 'issuing bank'};
    case 'type':
      return <String>{'type', 'Type'};
    case 'pin':
      return <String>{'PIN', 'pin'};
    case 'credit limit':
      return <String>{'credit limit', 'Credit Limit'};
    case 'cash withdrawal limit':
      return <String>{'cash withdrawal limit', 'Cash Withdrawal Limit'};
    case 'interest rate':
      return <String>{'interest rate', 'Interest Rate'};
    case 'issue number':
      return <String>{'issue number', 'Issue Number'};
    case 'phone (local)':
      return <String>{'phone (local)', 'Phone (Local)'};
    case 'phone (toll free)':
      return <String>{'phone (toll free)', 'Phone (Toll Free)'};
    case 'phone (intl)':
      return <String>{'phone (intl)', 'Phone (Intl)'};
    case 'website':
      return <String>{'website', 'Website'};
    default:
      final trimmed = label.trim();
      return <String>{trimmed};
  }
}

String creditCardStorageKeyForLabel(String label) {
  switch (label.trim().toLowerCase()) {
    case 'cardholder name':
      return 'Cardholder Name';
    case 'number':
      return 'Card Number';
    case 'verification number':
      return 'CVC';
    case 'expiry date':
      return 'Expiry Date';
    case 'valid from':
      return 'Valid From';
    case 'issuing bank':
      return 'Issuing Bank';
    case 'type':
      return 'type';
    case 'pin':
      return 'PIN';
    case 'credit limit':
      return 'credit limit';
    case 'cash withdrawal limit':
      return 'cash withdrawal limit';
    case 'interest rate':
      return 'interest rate';
    case 'issue number':
      return 'issue number';
    case 'phone (local)':
      return 'phone (local)';
    case 'phone (toll free)':
      return 'phone (toll free)';
    case 'phone (intl)':
      return 'phone (intl)';
    case 'website':
      return 'website';
    default:
      return label.trim();
  }
}


String bankStorageKeyForLabel(String label) {
  switch (label.trim().toLowerCase()) {
    case 'bank name':
      return 'Bank Name';
    case 'name on account':
      return 'Account Holder';
    case 'type':
      return 'Account Type';
    case 'routing number':
      return 'Routing Number';
    case 'account number':
      return 'Account Number';
    case 'swift':
      return 'SWIFT / BIC';
    case 'iban':
      return 'IBAN';
    case 'pin':
      return 'PIN';
    case 'phone':
      return 'Phone';
    case 'address':
      return 'Address';
    default:
      return label.trim();
  }
}

String editBankFieldValueFromKdbx(KdbxEntry kdbx, String label) {
  final storageKey = bankStorageKeyForLabel(label);
  final normalized = storageKey.toLowerCase();
  if (normalized == 'account holder') {
    return kdbx.fieldByKey('Account Holder')?.value ?? kdbx.username ?? '';
  }
  return kdbx.fieldByKey(storageKey)?.value ?? '';
}

Set<String> identityStorageKeysForLabel(String label) {
  switch (label.trim().toLowerCase()) {
    case 'first name':
      return <String>{'First Name', 'first name'};
    case 'initial':
      return <String>{'Initial', 'initial'};
    case 'last name':
      return <String>{'Last Name', 'last name'};
    case 'gender':
      return <String>{'Gender', 'gender'};
    case 'birth date':
      return <String>{'Birth Date', 'birth date'};
    case 'occupation':
      return <String>{'Occupation', 'occupation'};
    case 'company':
      return <String>{'Company', 'company'};
    case 'department':
      return <String>{'Department', 'department'};
    case 'job title':
      return <String>{'Job Title', 'job title'};
    case 'address':
      return <String>{'Address', 'address'};
    case 'city':
      return <String>{'City', 'city'};
    case 'state':
      return <String>{'State', 'state'};
    case 'zip':
      return <String>{'Zip', 'zip', 'ZIP', 'postal code', 'Postal Code'};
    case 'country':
      return <String>{'Country', 'country'};
    case 'default phone':
      return <String>{'Default Phone', 'default phone'};
    case 'home':
      return <String>{'Home', 'home'};
    case 'cell':
      return <String>{'Cell', 'cell'};
    case 'business':
      return <String>{'Business', 'business'};
    case 'username':
      return <String>{'Username', 'username'};
    case 'reminder question':
      return <String>{'Reminder Question', 'reminder question'};
    case 'reminder answer':
      return <String>{'Reminder Answer', 'reminder answer'};
    case 'email':
      return <String>{'Email', 'email'};
    case 'website':
      return <String>{'Website', 'website', AppKdbxFieldKeys.url};
    case 'icq':
      return <String>{'ICQ', 'icq'};
    case 'skype':
      return <String>{'Skype', 'skype'};
    case 'aol/im':
      return <String>{'AOL/IM', 'aol/im'};
    case 'yahoo':
      return <String>{'Yahoo', 'yahoo'};
    case 'msn':
      return <String>{'MSN', 'msn'};
    case 'firm signature':
      return <String>{'Firm Signature', 'firm signature'};
    default:
      final trimmed = label.trim();
      return <String>{trimmed};
  }
}

String editIdentityFieldValueFromKdbx(KdbxEntry kdbx, String label) {
  for (final key in identityStorageKeysForLabel(label)) {
    final value = kdbx.fieldByKey(key)?.value ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return kdbx.fieldByKey(label.trim())?.value ?? '';
}

String identityStorageKeyForLabel(String label) {
  switch (label.trim().toLowerCase()) {
    case 'first name':
      return 'First Name';
    case 'initial':
      return 'Initial';
    case 'last name':
      return 'Last Name';
    case 'gender':
      return 'Gender';
    case 'birth date':
      return 'Birth Date';
    case 'occupation':
      return 'Occupation';
    case 'company':
      return 'Company';
    case 'department':
      return 'Department';
    case 'job title':
      return 'Job Title';
    case 'address':
      return 'Address';
    case 'city':
      return 'City';
    case 'state':
      return 'State';
    case 'zip':
      return 'Zip';
    case 'country':
      return 'Country';
    case 'default phone':
      return 'Default Phone';
    case 'home':
      return 'Home';
    case 'cell':
      return 'Cell';
    case 'business':
      return 'Business';
    case 'username':
      return 'Username';
    case 'reminder question':
      return 'Reminder Question';
    case 'reminder answer':
      return 'Reminder Answer';
    case 'email':
      return 'Email';
    case 'website':
      return 'Website';
    case 'icq':
      return 'ICQ';
    case 'skype':
      return 'Skype';
    case 'aol/im':
      return 'AOL/IM';
    case 'yahoo':
      return 'Yahoo';
    case 'msn':
      return 'MSN';
    case 'firm signature':
      return 'Firm Signature';
    default:
      return label.trim();
  }
}


EntryField? sshPrivateKeyFieldFromKdbx(KdbxEntry? kdbx) {
  if (kdbx == null) return null;
  for (final field in kdbx.fields) {
    if (field.key == 'Private Key') return field;
  }
  for (final field in kdbx.fields) {
    final k = field.key.toLowerCase();
    if (k.contains('private key')) return field;
  }
  return null;
}

bool isSshPrivateKeyStorageKey(String key) {
  final k = key.toLowerCase();
  return k == 'private key' || k.contains('private key');
}
