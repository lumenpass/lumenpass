import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

class MobileNewItemType {
  const MobileNewItemType({
    required this.id,
    required this.label,
    this.icon,
    required this.iconColor,
    this.imagePath,
  });

  final String id;
  final String label;
  final IconData? icon;
  final Color iconColor;
  final String? imagePath;
}

const List<MobileNewItemType> kAllNewItemTypes = <MobileNewItemType>[
  MobileNewItemType(
    id: 'login',
    label: 'Login',
    icon: TablerIcons.lock,
    iconColor: Color(0xFF2DA8B6),
  ),
  MobileNewItemType(
    id: 'secure-note',
    label: 'Secure Note',
    icon: TablerIcons.notes,
    iconColor: Color(0xFFE0A433),
    imagePath: 'assets/images/item_type_note.png',
  ),
  MobileNewItemType(
    id: 'credit-card',
    label: 'Credit Card',
    icon: TablerIcons.credit_card,
    iconColor: Color(0xFF4A9EE8),
  ),
  MobileNewItemType(
    id: 'identity',
    label: 'Identity',
    icon: TablerIcons.id,
    iconColor: Color(0xFF56B676),
    imagePath: 'assets/images/item_type_identity.png',
  ),
  MobileNewItemType(
    id: 'ssh-key',
    label: 'SSH Key',
    icon: TablerIcons.key,
    iconColor: Color(0xFF1D6570),
    imagePath: 'assets/images/item_type_ssh.png',
  ),
  MobileNewItemType(
    id: 'bank-account',
    label: 'Bank Account',
    icon: TablerIcons.building_bank,
    iconColor: Color(0xFF1F9A76),
    imagePath: 'assets/images/item_type_bank.png',
  ),
];

const Set<String> kHiddenAddItemTypeIds = <String>{
  'document',
  'api-credential',
  'server',
  'wifi-password',
  'passport',
};

/// Helper: resolve which group uuid should be pre-selected when creating a new entry.
String? resolveEffectiveCategoryUuid({
  required List<({String uuid, String name, String notes, int count})>
      categories,
  required String? rootGroupUuid,
  required String? selectedGroupUuid,
  String? selectedCategoryUuid,
}) {
  final categoryUuids = categories.map((c) => c.uuid).toSet();
  if (selectedCategoryUuid != null &&
      (selectedCategoryUuid == rootGroupUuid ||
          categoryUuids.contains(selectedCategoryUuid))) {
    return selectedCategoryUuid;
  }
  if (selectedGroupUuid != null &&
      (selectedGroupUuid == rootGroupUuid ||
          categoryUuids.contains(selectedGroupUuid))) {
    return selectedGroupUuid;
  }
  if (categories.isNotEmpty) {
    return categories.first.uuid;
  }
  return rootGroupUuid;
}

/// Canonical mapping from field label to possible storage keys for Identity fields.
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
    if (value.isNotEmpty) return value;
  }
  return kdbx.fieldByKey(label.trim())?.value ?? '';
}

/// Canonical mapping from field label to storage key for Identity fields.
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

/// Canonical mapping from field label to storage key for Bank Account fields.
String bankStorageKeyForLabel(String label) {
  switch (label.trim().toLowerCase()) {
    case 'bank name':
      return 'Bank Name';
    case 'name on account':
    case 'account holder':
      return 'Account Holder';
    case 'type':
    case 'account type':
      return 'Account Type';
    case 'routing number':
      return 'Routing Number';
    case 'account number':
      return 'Account Number';
    case 'swift':
    case 'swift/bic':
    case 'swift bic':
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

/// Convert a raw field key to a human-readable display label.
String displayLabelForFieldKey(String key) {
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
  if (spaced.isEmpty) return key;

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

/// Returns true if [key] is the storage key for an SSH private key field.
bool isSshPrivateKeyStorageKey(String key) {
  final k = key.toLowerCase();
  return k == 'private key' || k.contains('private key');
}
