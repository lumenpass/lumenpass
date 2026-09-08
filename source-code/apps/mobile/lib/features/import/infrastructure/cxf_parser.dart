import 'dart:convert';
import 'dart:developer' as developer;

import '../domain/import_parsed_item.dart';

/// Result of parsing a CXF 1.0 payload from the Credential Exchange Protocol.
class CxfParseResult {
  const CxfParseResult({
    required this.exporterName,
    required this.items,
    required this.totalAccounts,
  });

  final String exporterName;
  final List<ImportParsedItem> items;
  final int totalAccounts;
}

/// Parses the JSON payload emitted by `ASExportedCredentialData.encode()`.
///
/// The format is the FIDO Alliance Credential Exchange Format (CXF) 1.0.
/// The relevant shape, confirmed against Apple's `ASExportedCredentialData`
/// output, is:
///
/// ```json
/// {
///   "accounts": [
///     {
///       "items": [
///         {
///           "title": "Wifi Cafe Louis",
///           "subtitle": "—",
///           "tags": ["Imported …"],
///           "scope": { "urls": ["https://…"], "androidApps": [] },
///           "credentials": [
///             {
///               "type": "basic-auth",
///               "username": { "fieldType": "string", "value": "alice" },
///               "password": { "fieldType": "concealed-string", "value": "…" }
///             },
///             { "type": "note", "content": { "fieldType": "string", "value": "…" } },
///             { "type": "totp", "secret": "…", "period": 30, "digits": 6 }
///           ]
///         }
///       ]
///     }
///   ]
/// }
/// ```
///
/// Field values inside credentials are usually `EditableField` objects of the
/// shape `{ id, label, fieldType, value }` — *not* plain strings. The helpers
/// here accept either shape defensively.
class CxfParser {
  const CxfParser();

  CxfParseResult parse(String jsonString) {
    final Map<String, dynamic> root;
    try {
      root = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('Invalid CXF JSON: $e');
    }

    final exporterName = _str(root['exporterDisplayName']) ??
        _str(root['exporterRpId']) ??
        'Unknown';
    final accounts = root['accounts'] as List<dynamic>? ?? const [];

    final items = <ImportParsedItem>[];

    for (final account in accounts) {
      if (account is! Map<String, dynamic>) continue;
      _parseAccount(account, items);
    }

    developer.log(
      'CXF: parsed ${items.length} items from ${accounts.length} '
      'account(s), exporter=$exporterName',
      name: 'cxf_parser',
    );

    return CxfParseResult(
      exporterName: exporterName,
      items: items,
      totalAccounts: accounts.length,
    );
  }

  void _parseAccount(Map<String, dynamic> account, List<ImportParsedItem> out) {
    // Items can sit directly on the account or inside collections.
    final directItems = account['items'] as List<dynamic>?;
    if (directItems != null) {
      for (final item in directItems) {
        if (item is! Map<String, dynamic>) continue;
        final parsed = _parseItem(item);
        if (parsed != null) out.add(parsed);
      }
    }

    final collections = account['collections'] as List<dynamic>?;
    if (collections != null) {
      for (final collection in collections) {
        if (collection is! Map<String, dynamic>) continue;
        final collectionItems = collection['items'] as List<dynamic>?;
        if (collectionItems == null) continue;

        final collectionTitle = _str(collection['title']);
        for (final item in collectionItems) {
          if (item is! Map<String, dynamic>) continue;
          final parsed = _parseItem(item, collectionTag: collectionTitle);
          if (parsed != null) out.add(parsed);
        }
      }
    }
  }

  ImportParsedItem? _parseItem(
    Map<String, dynamic> item, {
    String? collectionTag,
  }) {
    String? username;
    String? password;
    String? url;
    String? otpAuthUrl;
    final notesParts = <String>[];
    final customFields = <CustomImportField>[];
    final tags = <String>[];

    if (collectionTag != null && collectionTag.isNotEmpty) {
      tags.add(collectionTag);
    }

    // Item-level tags.
    final itemTags = item['tags'] as List<dynamic>?;
    if (itemTags != null) {
      for (final t in itemTags) {
        final s = _str(t);
        if (s != null && s.isNotEmpty) tags.add(s);
      }
    }

    // URL from the item scope (urls[] first, then androidApps[]).
    url = _firstScopeUrl(item['scope']);

    // Walk the credentials list and dispatch by type.
    final credentials = item['credentials'] as List<dynamic>?;
    if (credentials != null) {
      for (final cred in credentials) {
        if (cred is! Map<String, dynamic>) continue;
        final type = (_str(cred['type']) ?? '').toLowerCase();

        switch (type) {
          case 'basic-auth':
            username ??= _str(cred['username']);
            password ??= _str(cred['password']);
            url ??= _firstUrlList(cred['urls']);
            break;
          case 'totp':
          case 'otp':
            otpAuthUrl ??= _buildOtpAuthUrl(cred);
            break;
          case 'note':
            final content = _str(cred['content']);
            if (content != null && content.isNotEmpty) {
              notesParts.add(content);
            }
            break;
          case 'passkey':
            _extractPasskey(cred, customFields);
            break;
          default:
            _extractGenericCredential(cred, customFields);
        }
      }
    }

    final title = _firstNonEmpty([
      _str(item['title']),
      _str(item['subtitle']),
      username,
      url,
    ]);

    // Skip items that carry no usable data at all.
    if (title == null &&
        username == null &&
        password == null &&
        url == null &&
        otpAuthUrl == null &&
        notesParts.isEmpty &&
        customFields.isEmpty) {
      return null;
    }

    return ImportParsedItem(
      title: title ?? 'Imported',
      username: username,
      password: password,
      url: url,
      otpAuthUrl: _normalizeTotp(otpAuthUrl),
      notes: notesParts.isEmpty ? null : notesParts.join('\n'),
      tags: tags.isEmpty ? null : tags,
      customFields: customFields.isEmpty ? null : customFields,
    );
  }

  void _extractPasskey(
    Map<String, dynamic> cred,
    List<CustomImportField> customFields,
  ) {
    final credentialId =
        _str(cred['credentialId']) ?? _str(cred['credentialID']);
    if (credentialId != null && credentialId.isNotEmpty) {
      customFields.add(CustomImportField(
        name: 'KPEX_PASSKEY_CREDENTIAL_ID',
        value: credentialId,
      ));
    }
    final rpId = _str(cred['rpId']) ?? _str(cred['relyingPartyIdentifier']);
    if (rpId != null && rpId.isNotEmpty) {
      customFields.add(CustomImportField(
        name: 'KPEX_PASSKEY_RELYING_PARTY',
        value: rpId,
      ));
    }
    final userHandle = _str(cred['userHandle']);
    if (userHandle != null && userHandle.isNotEmpty) {
      customFields.add(CustomImportField(
        name: 'KPEX_PASSKEY_USER_HANDLE',
        value: userHandle,
      ));
    }
    final userName = _str(cred['userName']);
    if (userName != null && userName.isNotEmpty) {
      customFields.add(CustomImportField(
        name: 'KPEX_PASSKEY_USERNAME',
        value: userName,
      ));
    }
    final key = _str(cred['key']) ?? _str(cred['privateKey']);
    if (key != null && key.isNotEmpty) {
      customFields.add(CustomImportField(
        name: 'KPEX_PASSKEY_PRIVATE_KEY_PEM',
        value: key,
        isProtected: true,
      ));
    }
  }

  /// Stores fields from credential types we don't model explicitly
  /// (credit-card, ssh-key, api-key, …) as custom KDBX fields so no data
  /// is silently dropped.
  void _extractGenericCredential(
    Map<String, dynamic> cred,
    List<CustomImportField> customFields,
  ) {
    cred.forEach((key, value) {
      if (key == 'type') return;
      final str = _str(value);
      if (str == null || str.isEmpty) return;
      final isProtected = value is Map<String, dynamic> &&
          (value['fieldType'] == 'concealed-string');
      customFields.add(CustomImportField(
        name: key,
        value: str,
        isProtected: isProtected,
      ));
    });
  }

  /// Builds an `otpauth://` URL from a CXF `totp` credential.
  String? _buildOtpAuthUrl(Map<String, dynamic> cred) {
    final secret = _str(cred['secret']);
    if (secret == null || secret.isEmpty) return null;

    // If the secret is already a full otpauth URL, use it directly.
    if (secret.startsWith('otpauth://')) return secret;

    final issuer = _str(cred['issuer']);
    final account = _str(cred['username']) ?? _str(cred['userName']);
    final algorithm = _str(cred['algorithm']);
    final digits = cred['digits'];
    final period = cred['period'];

    final label = [
      if (issuer != null && issuer.isNotEmpty) issuer,
      if (account != null && account.isNotEmpty) account,
    ].join(':');

    final params = <String, String>{'secret': secret};
    if (issuer != null && issuer.isNotEmpty) params['issuer'] = issuer;
    if (algorithm != null && algorithm.isNotEmpty) {
      params['algorithm'] = algorithm.toUpperCase();
    }
    if (digits != null) params['digits'] = digits.toString();
    if (period != null) params['period'] = period.toString();

    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'otpauth://totp/${Uri.encodeComponent(label)}?$query';
  }

  /// Returns the first URL declared in an item's `scope` object.
  String? _firstScopeUrl(dynamic scope) {
    if (scope is! Map<String, dynamic>) return null;
    final fromUrls = _firstUrlList(scope['urls']);
    if (fromUrls != null) return fromUrls;
    return _firstUrlList(scope['androidApps']);
  }

  String? _firstUrlList(dynamic list) {
    if (list is! List) return null;
    for (final entry in list) {
      final s = _str(entry);
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  String? _normalizeTotp(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    if (trimmed.startsWith('otpauth://')) return trimmed;
    // Bare TOTP secret — wrap it.
    if (RegExp(r'^[A-Za-z2-7]+=*$').hasMatch(trimmed)) {
      return 'otpauth://totp/?secret=$trimmed';
    }
    return trimmed;
  }

  /// Coerces a CXF field value into a string.
  ///
  /// Values may be a plain `String`, a number/bool, or an `EditableField`
  /// object `{ id, label, fieldType, value }`. Returns `null` for anything
  /// empty or unrepresentable.
  String? _str(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final t = value.trim();
      return t.isEmpty ? null : t;
    }
    if (value is num || value is bool) return value.toString();
    if (value is Map<String, dynamic>) {
      return _str(value['value']);
    }
    return null;
  }

  String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }
}
