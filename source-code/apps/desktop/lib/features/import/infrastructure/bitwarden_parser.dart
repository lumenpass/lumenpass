import 'dart:convert';
import 'dart:io';

import '../domain/import_parsed_item.dart';

/// Parses Bitwarden vault exports in the two officially supported formats:
/// unencrypted JSON (`.json`) and CSV (`.csv`).
///
/// Every value is sanitized before it reaches the internal entry schema so
/// malformed control characters can't corrupt the stored vault, and exact
/// duplicate items are collapsed to avoid bloating the target vault.
class BitwardenParser {
  const BitwardenParser();

  // Bitwarden item `type` ids (JSON export).
  static const int _typeLogin = 1;
  static const int _typeSecureNote = 2;
  static const int _typeCard = 3;
  static const int _typeIdentity = 4;
  static const int _typeSshKey = 5;

  /// Friendly labels for the Bitwarden identity sub-object, in display order.
  static const Map<String, String> _identityLabels = <String, String>{
    'title': 'Title',
    'firstName': 'First Name',
    'middleName': 'Middle Name',
    'lastName': 'Last Name',
    'username': 'Username',
    'company': 'Company',
    'email': 'Email',
    'phone': 'Phone',
    'ssn': 'SSN',
    'passportNumber': 'Passport Number',
    'licenseNumber': 'License Number',
    'address1': 'Address 1',
    'address2': 'Address 2',
    'address3': 'Address 3',
    'city': 'City',
    'state': 'State',
    'postalCode': 'Postal Code',
    'country': 'Country',
  };

  Future<List<ImportParsedItem>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('File not found: $filePath');
    }

    final extension = _fileExtension(filePath);
    final content = await file.readAsString();

    switch (extension) {
      case '.json':
        return parseJson(content);
      case '.csv':
        return parseCsv(content);
      default:
        throw FormatException(
            'Unsupported Bitwarden file: "$extension". '
            'Bitwarden exports must be .json or .csv.');
    }
  }

  // ── JSON ──────────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseJson(String content) {
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw const FormatException(
          'This file is not valid Bitwarden JSON. Re-export your vault from '
          'Bitwarden and try again.');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'Unrecognized Bitwarden JSON structure. Expected a vault export '
          'object at the top level.');
    }

    // Reject encrypted exports — we can't read them without the export key.
    if (decoded['encrypted'] == true) {
      throw const FormatException(
          'This Bitwarden export is encrypted and cannot be imported. '
          'Re-export with "Password protected export" turned off.');
    }

    final items = decoded['items'];
    if (items is! List) {
      throw const FormatException(
          'This file is missing the Bitwarden "items" list. It may be an '
          'unsupported or corrupted export version.');
    }

    final folderNames = _buildFolderMap(decoded['folders']);

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final item = _parseJsonItem(raw, folderNames);
      if (item == null) continue;
      if (!seen.add(_dedupKey(item))) continue; // skip exact duplicates
      parsed.add(item);
    }

    if (parsed.isEmpty) {
      throw const FormatException(
          'No importable items were found in this Bitwarden JSON export.');
    }

    return parsed;
  }

  Map<String, String> _buildFolderMap(dynamic folders) {
    final map = <String, String>{};
    if (folders is List) {
      for (final f in folders) {
        if (f is Map && f['id'] is String && f['name'] is String) {
          map[f['id'] as String] = f['name'] as String;
        }
      }
    }
    return map;
  }

  ImportParsedItem? _parseJsonItem(
    Map<String, dynamic> raw,
    Map<String, String> folderNames,
  ) {
    final type = raw['type'];
    final name = _str(raw['name']) ?? '';
    final notesParts = <String>[];
    final notes = _str(raw['notes']);
    if (notes != null && notes.trim().isNotEmpty) {
      notesParts.add(notes);
    }

    final customFields = <CustomImportField>[];

    // Generic custom fields are common to every Bitwarden item type.
    final fields = raw['fields'];
    if (fields is List) {
      for (final f in fields) {
        if (f is! Map) continue;
        // `type == 1` denotes a hidden/concealed Bitwarden field.
        _addField(
          customFields,
          _str(f['name']) ?? '',
          _str(f['value']),
          protected: f['type'] == 1,
        );
      }
    }

    String? username;
    String? password;
    String? url;
    String? otpAuthUrl;

    switch (type) {
      case _typeLogin:
        final login = raw['login'];
        if (login is Map) {
          username = _str(login['username']);
          password = _str(login['password']);
          url = _firstUri(login['uris']);
          otpAuthUrl = _normalizeTotp(_str(login['totp']), name);
        }
      case _typeCard:
        final card = raw['card'];
        if (card is Map) {
          _addField(customFields, 'Cardholder Name',
              _str(card['cardholderName']));
          _addField(customFields, 'Brand', _str(card['brand']));
          _addField(customFields, 'Number', _str(card['number']),
              protected: true);
          _addField(customFields, 'Expiration', _cardExpiry(card));
          _addField(customFields, 'Security Code', _str(card['code']),
              protected: true);
        }
      case _typeIdentity:
        final identity = raw['identity'];
        if (identity is Map) {
          _identityLabels.forEach((key, label) {
            _addField(customFields, label, _str(identity[key]));
          });
        }
      case _typeSshKey:
        final ssh = raw['sshKey'];
        if (ssh is Map) {
          _addField(customFields, 'Private Key', _str(ssh['privateKey']),
              protected: true);
          _addField(customFields, 'Public Key', _str(ssh['publicKey']));
          _addField(customFields, 'Fingerprint', _str(ssh['keyFingerprint']));
        }
      case _typeSecureNote:
        // Secure notes carry their data via `notes` / custom fields only.
        break;
      default:
        // Unknown / future item type — skip rather than import garbage.
        return null;
    }

    final tags = <String>[];
    final folderId = _str(raw['folderId']);
    if (folderId != null && folderNames.containsKey(folderId)) {
      tags.add(folderNames[folderId]!);
    }

    final item = ImportParsedItem(
      title: _sanitize(name) ?? '',
      username: _sanitize(username),
      password: _sanitize(password),
      url: _sanitize(url),
      otpAuthUrl: _sanitize(otpAuthUrl),
      notes: notesParts.isEmpty ? null : _sanitize(notesParts.join('\n')),
      tags: tags,
      customFields: customFields,
    );

    item.storeSourceField('bw_type', type?.toString() ?? '');
    item.storeSourceField('bw_id', _str(raw['id']) ?? '');

    if (item.title.trim().isEmpty) {
      item.addError('Missing title');
    }

    return item;
  }

  // ── CSV ─────────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The Bitwarden CSV file is empty.');
    }

    final records = _parseCsvRecords(content);
    if (records.isEmpty) {
      throw const FormatException('The Bitwarden CSV file has no rows.');
    }

    final headers = records.first
        .map((h) => h.trim().toLowerCase())
        .toList(growable: false);
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    // A Bitwarden CSV is identified by its login_* columns. Reject anything
    // that doesn't look like one with a clear message.
    final looksLikeBitwarden = columns.containsKey('name') &&
        (columns.containsKey('login_username') ||
            columns.containsKey('login_password') ||
            columns.containsKey('login_uri'));
    if (!looksLikeBitwarden) {
      throw const FormatException(
          'This CSV does not look like a Bitwarden export. Expected columns '
          'such as "name", "login_username", and "login_password".');
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var i = 1; i < records.length; i++) {
      final row = records[i];
      // Skip blank trailing lines.
      if (row.every((c) => c.trim().isEmpty)) continue;

      final name = _cell(row, columns['name']);
      final notes = _cell(row, columns['notes']);
      final username = _cell(row, columns['login_username']);
      final password = _cell(row, columns['login_password']);
      final url = _firstCsvUri(_cell(row, columns['login_uri']));
      final totp =
          _normalizeTotp(_cell(row, columns['login_totp']), name ?? '');
      final folder = _cell(row, columns['folder']);

      final customFields =
          _parseCsvFields(_cell(row, columns['fields']));

      final tags = <String>[];
      if (folder != null && folder.trim().isNotEmpty) {
        tags.add(folder.trim());
      }

      final item = ImportParsedItem(
        title: _sanitize(name) ?? '',
        username: _sanitize(username),
        password: _sanitize(password),
        url: _sanitize(url),
        otpAuthUrl: _sanitize(totp),
        notes: _sanitize(notes),
        tags: tags,
        customFields: customFields,
      );

      item.storeSourceField('csv_row', (i + 1).toString());

      if (item.title.trim().isEmpty) {
        item.addError('Missing title in row ${i + 1}');
      }

      if (!seen.add(_dedupKey(item))) continue; // skip exact duplicates
      parsed.add(item);
    }

    if (parsed.isEmpty) {
      throw const FormatException(
          'No importable rows were found in this Bitwarden CSV export.');
    }

    return parsed;
  }

  /// Parses the Bitwarden CSV `fields` blob — newline-separated `name: value`
  /// pairs — into structured custom fields.
  List<CustomImportField> _parseCsvFields(String? blob) {
    if (blob == null || blob.trim().isEmpty) return const <CustomImportField>[];

    final result = <CustomImportField>[];
    for (final line in const LineSplitter().convert(blob)) {
      if (line.trim().isEmpty) continue;
      final sep = line.indexOf(':');
      String name;
      String value;
      if (sep < 0) {
        name = '';
        value = line.trim();
      } else {
        name = line.substring(0, sep).trim();
        value = line.substring(sep + 1).trim();
      }
      _addField(result, name, value);
    }
    return result;
  }

  /// A record-aware CSV tokenizer. Unlike a naive line split, this correctly
  /// handles quoted fields that span multiple physical lines (Bitwarden notes
  /// and field blobs routinely contain embedded newlines).
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

  String? _firstUri(dynamic uris) {
    if (uris is! List || uris.isEmpty) return null;
    final first = uris.first;
    if (first is Map) {
      return _firstCsvUri(_str(first['uri']));
    }
    return null;
  }

  /// Bitwarden sometimes stores multiple URIs comma-joined in a single value.
  /// Use the first as the primary URL.
  String? _firstCsvUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final comma = value.indexOf(',');
    if (comma > 0) return value.substring(0, comma).trim();
    return value.trim();
  }

  /// Normalizes a Bitwarden TOTP value into an `otpauth://` URI. Raw secrets
  /// are wrapped; existing otpauth URIs are passed through unchanged.
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

  String? _cardExpiry(Map card) {
    final month = _str(card['expMonth']);
    final year = _str(card['expYear']);
    if (month == null && year == null) return null;
    final mm = (month ?? '').padLeft(2, '0');
    return '${mm.isEmpty ? '--' : mm}/${year ?? '----'}';
  }

  /// Builds a stable key for duplicate detection across identical items.
  String _dedupKey(ImportParsedItem item) {
    return [
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
