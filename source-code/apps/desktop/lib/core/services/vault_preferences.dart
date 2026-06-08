import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/kdbx_repository_provider.dart';

const String vaultDomainSettingKey = 'vault.domainSetting';
const String vaultAutoLockMinutesKey = 'vault.autoLockMinutes';
const String vaultClipboardClearSecondsKey = 'vault.clipboardClearSeconds';
const String vaultAutoFetchItemIconKey = 'vault.autoFetchItemIcon';
const String vaultDisabledAutofillDomainsKey = 'vault.disabledAutofillDomains';

final vaultDomainSettingProvider = StateProvider<String>((ref) => 'default');

/// Null means "never". Otherwise the number of minutes until auto-lock.
final vaultAutoLockMinutesProvider = StateProvider<int?>((ref) => 30);

/// Null means "never". Otherwise the number of seconds until clipboard clear.
final vaultClipboardClearSecondsProvider = StateProvider<int?>((ref) => 60);

final vaultAutoFetchItemIconProvider = StateProvider<bool>((ref) => true);

final vaultDisabledAutofillDomainsProvider =
    StateProvider<List<DisabledAutofillDomain>>((ref) => const []);

/// In-session cache: favicon URL → true (loaded OK) | false (failed).
/// A missing key means the URL has not been attempted this session.
final faviconFetchResultProvider =
    StateProvider<Map<String, bool>>((ref) => {});

Future<void> loadVaultPreferences(ProviderContainer container) async {
  final storage = container.read(localStorageProvider);

  const validDomainSettings = {'default', 'baseDomain', 'subdomain'};
  final domainSetting = await storage.read(key: vaultDomainSettingKey);
  if (domainSetting != null && validDomainSettings.contains(domainSetting)) {
    container.read(vaultDomainSettingProvider.notifier).state = domainSetting;
  }

  final lockStr = await storage.read(key: vaultAutoLockMinutesKey);
  if (lockStr != null) {
    container.read(vaultAutoLockMinutesProvider.notifier).state =
        lockStr == 'never' ? null : int.tryParse(lockStr);
  }

  final clipStr = await storage.read(key: vaultClipboardClearSecondsKey);
  if (clipStr != null) {
    container.read(vaultClipboardClearSecondsProvider.notifier).state =
        clipStr == 'never' ? null : int.tryParse(clipStr);
  }

  final iconStr = await storage.read(key: vaultAutoFetchItemIconKey);
  if (iconStr != null) {
    container.read(vaultAutoFetchItemIconProvider.notifier).state =
        iconStr == 'true';
  }

  final disabledDomains =
      await storage.read(key: vaultDisabledAutofillDomainsKey);
  if (disabledDomains != null) {
    container.read(vaultDisabledAutofillDomainsProvider.notifier).state =
        pruneDisabledAutofillDomains(
      decodeDisabledAutofillDomains(disabledDomains),
    );
  }
}

class DisabledAutofillDomain {
  const DisabledAutofillDomain({
    required this.domain,
    required this.disabledAt,
    required this.expiresAt,
  });

  final String domain;
  final int disabledAt;
  final int? expiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'domain': domain,
        'disabledAt': disabledAt,
        'expiresAt': expiresAt,
      };

  static DisabledAutofillDomain? fromJson(Map<String, dynamic> json) {
    final rawDomain = json['domain'];
    if (rawDomain is! String || rawDomain.trim().isEmpty) return null;
    final disabledAt = json['disabledAt'];
    final expiresAt = json['expiresAt'];
    return DisabledAutofillDomain(
      domain: normalizeDisabledAutofillDomain(rawDomain),
      disabledAt: disabledAt is num
          ? disabledAt.round()
          : DateTime.now().millisecondsSinceEpoch,
      expiresAt: expiresAt is num ? expiresAt.round() : null,
    );
  }
}

String normalizeDisabledAutofillDomain(String domain) {
  final trimmed = domain.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  try {
    final uri =
        Uri.parse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
    final host = uri.host.isNotEmpty ? uri.host : trimmed;
    return host.replaceFirst(RegExp(r'^www\.'), '');
  } catch (_) {
    return trimmed.replaceFirst(RegExp(r'^www\.'), '');
  }
}

List<DisabledAutofillDomain> pruneDisabledAutofillDomains(
  List<DisabledAutofillDomain> domains, {
  int? now,
}) {
  final currentTime = now ?? DateTime.now().millisecondsSinceEpoch;
  final byDomain = <String, DisabledAutofillDomain>{};
  for (final item in domains) {
    final domain = normalizeDisabledAutofillDomain(item.domain);
    if (domain.isEmpty) continue;
    if (item.expiresAt != null && item.expiresAt! <= currentTime) continue;
    final normalized = DisabledAutofillDomain(
      domain: domain,
      disabledAt: item.disabledAt,
      expiresAt: item.expiresAt,
    );
    final existing = byDomain[domain];
    if (existing == null || normalized.disabledAt >= existing.disabledAt) {
      byDomain[domain] = normalized;
    }
  }
  final result = byDomain.values.toList()
    ..sort((a, b) => a.domain.compareTo(b.domain));
  return result;
}

List<DisabledAutofillDomain> decodeDisabledAutofillDomains(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DisabledAutofillDomain.fromJson)
        .whereType<DisabledAutofillDomain>()
        .toList();
  } catch (_) {
    return const [];
  }
}

String encodeDisabledAutofillDomains(List<DisabledAutofillDomain> domains) {
  return jsonEncode(
    pruneDisabledAutofillDomains(domains).map((item) => item.toJson()).toList(),
  );
}
