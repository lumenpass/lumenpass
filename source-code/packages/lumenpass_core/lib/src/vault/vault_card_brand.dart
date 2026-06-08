import '../models/kdbx_entry.dart';

/// Card network inferred from PAN digits (same heuristics as the desktop vault list).
enum VaultCardBrand {
  visa,
  mastercard,
  amex,
  discover,
  diners,
  jcb,
  unionPay,
  maestro,
}

String extractCreditCardNumberFromEntry(KdbxEntry entry) {
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

VaultCardBrand? detectVaultCardBrand(String rawNumber) {
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
    return VaultCardBrand.visa;
  }
  if ((prefix2 != null && prefix2 >= 51 && prefix2 <= 55) ||
      (prefix4 != null && prefix4 >= 2221 && prefix4 <= 2720)) {
    return VaultCardBrand.mastercard;
  }
  if (startsWithAny(const <String>['34', '37'])) {
    return VaultCardBrand.amex;
  }
  if (startsWithAny(const <String>['6011', '65']) ||
      (prefix3 != null && prefix3 >= 644 && prefix3 <= 649) ||
      (prefix6 != null && prefix6 >= 622126 && prefix6 <= 622925)) {
    return VaultCardBrand.discover;
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
    '39',
  ])) {
    return VaultCardBrand.diners;
  }
  if (prefix4 != null && prefix4 >= 3528 && prefix4 <= 3589) {
    return VaultCardBrand.jcb;
  }
  if (startsWithAny(const <String>['62'])) {
    return VaultCardBrand.unionPay;
  }
  if (startsWithAny(const <String>['50', '56', '57', '58', '6'])) {
    return VaultCardBrand.maestro;
  }

  return null;
}
