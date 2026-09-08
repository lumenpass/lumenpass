import 'dart:convert';
import 'dart:io';

import '../domain/import_parsed_item.dart';

/// Parses Proton Pass vault exports.
///
/// Proton Pass exports a single CSV file with the columns:
/// `type,name,url,email,username,password,note,totp,createTime,modifyTime,vault`.
///
/// The `type` column drives how each row is mapped:
///   * `login`      → username/email/password/url/totp + notes
///   * `note`       → secure note (data in the `note` column)
///   * `identity`   → JSON blob in the `note` column mapped to labeled fields
///   * `creditCard` → JSON blob in the `note` column mapped to card fields
///   * `sshKey`     → JSON blob (when present) mapped to key fields, else note
///
/// Every value is sanitized before it reaches the internal entry schema so
/// malformed control characters can't corrupt the stored vault, and exact
/// duplicate items are collapsed to avoid bloating the target vault.
class ProtonPassParser {
  const ProtonPassParser();

  /// Friendly labels for Proton Pass identity fields, in display order.
  /// Keys map to the JSON object Proton stores in the `note` column for
  /// identity items.
  static const Map<String, String> _identityLabels = <String, String>{
    'fullName': 'Full Name',
    'firstName': 'First Name',
    'middleName': 'Middle Name',
    'lastName': 'Last Name',
    'birthdate': 'Birthdate',
    'gender': 'Gender',
    'email': 'Email',
    'phoneNumber': 'Phone',
    'secondPhoneNumber': 'Second Phone',
    'organization': 'Organization',
    'company': 'Company',
    'jobTitle': 'Job Title',
    'streetAddress': 'Street Address',
    'floor': 'Floor',
    'zipOrPostalCode': 'Zip/Postal Code',
    'city': 'City',
    'county': 'County',
    'stateOrProvince': 'State/Province',
    'countryOrRegion': 'Country/Region',
    'website': 'Website',
    'personalWebsite': 'Personal Website',
    'workPhoneNumber': 'Work Phone',
    'workEmail': 'Work Email',
    'xHandle': 'X (Twitter)',
    'linkedin': 'LinkedIn',
    'reddit': 'Reddit',
    'facebook': 'Facebook',
    'yahoo': 'Yahoo',
    'instagram': 'Instagram',
  };

  /// Identity keys whose values are sensitive enough to store protected.
  static const Set<String> _protectedIdentityKeys = <String>{
    'socialSecurityNumber',
    'passportNumber',
    'licenseNumber',
  };

  static const Map<String, String> _protectedIdentityLabels = <String, String>{
    'socialSecurityNumber': 'Social Security Number',
    'passportNumber': 'Passport Number',
    'licenseNumber': 'License Number',
  };

  /// The Proton Pass "extra section" array keys that may carry custom fields.
  static const List<String> _identityExtraArrays = <String>[
    'extraPersonalDetails',
    'extraAddressDetails',
    'extraContactDetails',
    'extraWorkDetails',
    'extraSections',
  ];

  Future<List<ImportParsedItem>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('File not found: $filePath');
    }

    final extension = _fileExtension(filePath);
    if (extension != '.csv') {
      throw FormatException(
          'Unsupported Proton Pass file: "$extension". '
          'Proton Pass exports must be a .csv file.');
    }

    final content = await file.readAsString();
    return parseCsv(content);
  }

  // ── CSV ─────────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The Proton Pass CSV file is empty.');
    }

    final records = _parseCsvRecords(content);
    if (records.isEmpty) {
      throw const FormatException('The Proton Pass CSV file has no rows.');
    }

    final headers = records.first
        .map((h) => h.trim().toLowerCase())
        .toList(growable: false);
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    // A Proton Pass CSV is identified by its `type` + `name` columns plus the
    // Proton-specific `vault` column (or the email/totp pair). Reject anything
    // that doesn't look like one with a clear message.
    final looksLikeProton = columns.containsKey('type') &&
        columns.containsKey('name') &&
        (columns.containsKey('vault') ||
            (columns.containsKey('email') && columns.containsKey('totp')));
    if (!looksLikeProton) {
      throw const FormatException(
          'This CSV does not look like a Proton Pass export. Expected columns '
          'such as "type", "name", "username", "password", and "vault".');
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var i = 1; i < records.length; i++) {
      final row = records[i];
      // Skip blank trailing lines.
      if (row.every((c) => c.trim().isEmpty)) continue;

      final item = _parseRow(row, columns, i + 1);
      if (item == null) continue;
      if (!seen.add(_dedupKey(item))) continue; // skip exact duplicates
      parsed.add(item);
    }

    if (parsed.isEmpty) {
      throw const FormatException(
          'No importable rows were found in this Proton Pass CSV export.');
    }

    return parsed;
  }

  ImportParsedItem? _parseRow(
    List<String> row,
    Map<String, int> columns,
    int rowNumber,
  ) {
    final type = (_cell(row, columns['type']) ?? 'login').trim().toLowerCase();
    final name = _cell(row, columns['name']) ?? '';
    final rawNote = _cell(row, columns['note']);
    final vault = _cell(row, columns['vault']);

    final customFields = <CustomImportField>[];
    String? username;
    String? password;
    String? url;
    String? otpAuthUrl;
    String? notes;

    switch (type) {
      case 'login':
        final email = _cell(row, columns['email']);
        final user = _cell(row, columns['username']);
        // KDBX exposes a single UserName field. Prefer the explicit username,
        // fall back to the email, and keep the other one as a custom field so
        // nothing is lost.
        if (user != null && user.trim().isNotEmpty) {
          username = user;
          _addField(customFields, 'Email', email);
        } else {
          username = email;
        }
        password = _cell(row, columns['password']);
        url = _firstUri(_cell(row, columns['url']));
        otpAuthUrl = _normalizeTotp(_cell(row, columns['totp']), name);
        notes = _cleanNote(rawNote);
      case 'note':
        notes = _cleanNote(rawNote);
      case 'identity':
        notes = _parseIdentityNote(rawNote, customFields);
      case 'creditcard':
        notes = _parseCardNote(rawNote, customFields);
      case 'sshkey':
        notes = _parseSshKeyNote(rawNote, customFields);
      default:
        // Unknown / future Proton Pass item type — skip rather than import
        // an item we can't map correctly.
        return null;
    }

    final tags = <String>[];
    if (vault != null && vault.trim().isNotEmpty) {
      tags.add(vault.trim());
    }

    final item = ImportParsedItem(
      title: _sanitize(name) ?? '',
      username: _sanitize(username),
      password: _sanitize(password),
      url: _sanitize(url),
      otpAuthUrl: _sanitize(otpAuthUrl),
      notes: _sanitize(notes),
      tags: tags,
      customFields: customFields,
    );

    item.storeSourceField('proton_type', type);
    item.storeSourceField('csv_row', rowNumber.toString());

    if (item.title.trim().isEmpty) {
      item.addError('Missing title in row $rowNumber');
    }

    return item;
  }

  // ── Structured note parsing (identity / card / ssh) ───────────────────────

  /// Parses Proton's identity JSON blob (stored in the `note` column) into
  /// labeled custom fields. Returns the inner free-form note, if any.
  String? _parseIdentityNote(
    String? rawNote,
    List<CustomImportField> out,
  ) {
    final json = _tryDecodeObject(rawNote);
    if (json == null) {
      // Not JSON — treat the whole thing as a plain note.
      return _cleanNote(rawNote);
    }

    _identityLabels.forEach((key, label) {
      _addField(out, label, _str(json[key]));
    });

    _protectedIdentityLabels.forEach((key, label) {
      if (_protectedIdentityKeys.contains(key)) {
        _addField(out, label, _str(json[key]), protected: true);
      }
    });

    for (final arrayKey in _identityExtraArrays) {
      _addExtraSectionFields(out, json[arrayKey]);
    }

    final inner = _str(json['note']);
    return inner == null || inner.trim().isEmpty ? null : inner;
  }

  /// Parses Proton's credit-card JSON blob into labeled custom fields.
  /// Returns the inner free-form note, if any.
  String? _parseCardNote(
    String? rawNote,
    List<CustomImportField> out,
  ) {
    final json = _tryDecodeObject(rawNote);
    if (json == null) {
      return _cleanNote(rawNote);
    }

    _addField(out, 'Cardholder Name', _str(json['cardholderName']));
    _addField(out, 'Number', _str(json['number']), protected: true);
    _addField(out, 'Security Code', _str(json['verificationNumber']),
        protected: true);
    _addField(out, 'Expiration', _str(json['expirationDate']));
    _addField(out, 'PIN', _str(json['pin']), protected: true);

    final inner = _str(json['note']);
    return inner == null || inner.trim().isEmpty ? null : inner;
  }

  /// Parses Proton's SSH-key JSON blob (when present) into protected key
  /// fields. Returns the inner free-form note, if any. When the column isn't
  /// JSON it is treated as a plain note.
  String? _parseSshKeyNote(
    String? rawNote,
    List<CustomImportField> out,
  ) {
    final json = _tryDecodeObject(rawNote);
    if (json == null) {
      return _cleanNote(rawNote);
    }

    _addField(out, 'Private Key', _str(json['privateKey']), protected: true);
    _addField(out, 'Public Key', _str(json['publicKey']));
    _addField(
      out,
      'Fingerprint',
      _str(json['fingerprint'] ?? json['keyFingerprint']),
    );

    final inner = _str(json['note']);
    return inner == null || inner.trim().isEmpty ? null : inner;
  }

  /// Flattens Proton "extra section" arrays into custom fields. Each entry may
  /// expose a label under `fieldName`/`label`/`title`/`name` and a value under
  /// `value`/`content`/`data`. Shapes that don't match are skipped silently so
  /// an unexpected structure can never abort the whole import.
  void _addExtraSectionFields(List<CustomImportField> out, dynamic array) {
    if (array is! List || array.isEmpty) return;
    for (final entry in array) {
      if (entry is! Map) continue;
      final label = _str(entry['fieldName']) ??
          _str(entry['label']) ??
          _str(entry['title']) ??
          _str(entry['name']) ??
          '';
      final value = _str(entry['value']) ??
          _str(entry['content']) ??
          _extractDataValue(entry['data']);
      _addField(out, label, value);
    }
  }

  String? _extractDataValue(dynamic data) {
    if (data is String) return data;
    if (data is Map) {
      return _str(data['content']) ?? _str(data['value']);
    }
    return null;
  }

  Map<String, dynamic>? _tryDecodeObject(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Not valid JSON — caller falls back to treating it as a plain note.
    }
    return null;
  }

  /// Proton Pass leaks `favorite: <bool>` / `archived: <bool>` metadata into
  /// the note column. Strip those lines while preserving any real note text.
  String? _cleanNote(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final metadata = RegExp(
      r'^(favorite|archived)\s*:\s*(true|false)\s*$',
      caseSensitive: false,
    );
    final kept = const LineSplitter()
        .convert(raw)
        .where((line) => !metadata.hasMatch(line.trim()))
        .toList();
    final result = kept.join('\n').trim();
    return result.isEmpty ? null : result;
  }

  /// A record-aware CSV tokenizer that correctly handles quoted fields that
  /// span multiple physical lines (Proton notes and JSON blobs routinely
  /// contain embedded newlines).
  List<List<String>> _parseCsvRecords(String content) {
    final records = <List<String>>[];
    var fields = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    var sawAnyChar = false;
    var i = 0;
    final len = content.length;

    while (i < len) {
      final ch = content[i];

      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < len && content[i + 1] == '"') {
            buffer.write('"');
            i += 2;
          } else {
            inQuotes = false;
            i++;
          }
        } else {
          buffer.write(ch);
          i++;
        }
        continue;
      }

      if (ch == '"') {
        inQuotes = true;
        sawAnyChar = true;
        i++;
      } else if (ch == ',') {
        fields.add(buffer.toString());
        buffer.clear();
        sawAnyChar = true;
        i++;
      } else if (ch == '\r') {
        i++; // swallow; the following \n (or EOF) ends the record
      } else if (ch == '\n') {
        fields.add(buffer.toString());
        buffer.clear();
        records.add(fields);
        fields = <String>[];
        sawAnyChar = false;
        i++;
      } else {
        buffer.write(ch);
        sawAnyChar = true;
        i++;
      }
    }

    // Flush the final field/record if the file didn't end with a newline.
    if (sawAnyChar || buffer.isNotEmpty || fields.isNotEmpty) {
      fields.add(buffer.toString());
      records.add(fields);
    }

    return records;
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  /// Strips NULL bytes and C0/C1 control characters (except tab, LF, CR) that
  /// could corrupt storage or be used for injection, while preserving the
  /// exact visible content of credentials.
  static String? _sanitize(String? input) {
    if (input == null) return null;
    return input.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
      '',
    );
  }

  void _addField(
    List<CustomImportField> out,
    String name,
    String? value, {
    bool protected = false,
  }) {
    final cleanValue = _sanitize(value);
    if (cleanValue == null || cleanValue.trim().isEmpty) return;
    out.add(CustomImportField(
      name: _sanitize(name)?.trim() ?? '',
      value: cleanValue,
      isProtected: protected,
    ));
  }

  /// Proton stores multiple URIs comma-joined in a single value. Use the first
  /// as the primary URL.
  String? _firstUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final comma = value.indexOf(',');
    if (comma > 0) return value.substring(0, comma).trim();
    return value.trim();
  }

  /// Normalizes a Proton TOTP value into an `otpauth://` URI. Existing otpauth
  /// URIs are passed through unchanged; raw secrets are wrapped.
  String? _normalizeTotp(String? totp, String label) {
    if (totp == null || totp.trim().isEmpty) return null;
    final value = totp.trim();
    if (value.toLowerCase().startsWith('otpauth://')) {
      return value;
    }
    final secret = value.replaceAll(' ', '');
    if (secret.isEmpty) return null;
    final account = Uri.encodeComponent(
        label.trim().isEmpty ? 'Imported' : label.trim());
    return 'otpauth://totp/$account?secret=$secret';
  }

  /// Builds a stable key for duplicate detection across identical items.
  String _dedupKey(ImportParsedItem item) {
    return [
      (item.getSourceField('proton_type') ?? ''),
      item.title.trim().toLowerCase(),
      (item.username ?? '').trim().toLowerCase(),
      item.password ?? '',
      (item.url ?? '').trim().toLowerCase(),
      (item.notes ?? '').trim(),
    ].join('\u0000');
  }

  String? _cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return null;
    final value = row[index];
    return value.isEmpty ? null : value;
  }

  String? _str(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  String _fileExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }
}
