import 'dart:convert';
import 'dart:io';

import '../domain/import_parsed_item.dart';

/// Parses NordPass vault exports.
///
/// NordPass exports a single CSV file with the columns:
/// `name,url,additional_urls,username,password,note,cardholdername,cardnumber,`
/// `cvc,pin,expirydate,zipcode,folder,shared_folder,full_name,phone_number,`
/// `email,address1,address2,city,country,state,type,custom_fields`.
///
/// The `type` column drives how each row is mapped:
///   * `password`    → username/password/url/email + notes (a login)
///   * `note`        → secure note (free-form text in the `note` column)
///   * `credit_card` → cardholder/number/cvc/pin/expiry + zip mapped to fields
///   * `identity`    → full_name/phone/email/address/… mapped to labeled fields
///   * `folder`      → a folder definition, not an item — skipped
///
/// Every value is sanitized before it reaches the internal entry schema so
/// malformed control characters can't corrupt the stored vault, and exact
/// duplicate items are collapsed to avoid bloating the target vault.
class NordPassParser {
  const NordPassParser();

  Future<List<ImportParsedItem>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('File not found: $filePath');
    }

    final extension = _fileExtension(filePath);
    if (extension != '.csv') {
      throw FormatException(
          'Unsupported NordPass file: "$extension". '
          'NordPass exports must be a .csv file.');
    }

    final content = await file.readAsString();
    return parseCsv(content);
  }

  // ── CSV ─────────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The NordPass CSV file is empty.');
    }

    final records = _parseCsvRecords(content);
    if (records.isEmpty) {
      throw const FormatException('The NordPass CSV file has no rows.');
    }

    final headers = records.first
        .map((h) => h.trim().toLowerCase())
        .toList(growable: false);
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    // A NordPass CSV is identified by its `type` column alongside the
    // NordPass-specific card/identity columns (`cardholdername`/`additional_urls`).
    // Reject anything that doesn't look like one with a clear message.
    final looksLikeNordPass = columns.containsKey('type') &&
        columns.containsKey('name') &&
        (columns.containsKey('cardholdername') ||
            columns.containsKey('additional_urls') ||
            columns.containsKey('custom_fields'));
    if (!looksLikeNordPass) {
      throw const FormatException(
          'This CSV does not look like a NordPass export. Expected columns '
          'such as "name", "type", "username", "password", and "custom_fields".');
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
          'No importable rows were found in this NordPass CSV export.');
    }

    return parsed;
  }

  ImportParsedItem? _parseRow(
    List<String> row,
    Map<String, int> columns,
    int rowNumber,
  ) {
    final type = (_cell(row, columns['type']) ?? 'password')
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');
    final name = _cell(row, columns['name']) ?? '';
    final rawNote = _cell(row, columns['note']);
    final folder = _cell(row, columns['folder']);

    final customFields = <CustomImportField>[];
    String? username;
    String? password;
    String? url;
    String? notes;

    switch (type) {
      case 'folder':
        // A folder definition, not an item. NordPass emits one row per folder
        // so the export can round-trip its tree; we represent folders as tags
        // on the items themselves, so there's nothing to import here.
        return null;
      case 'password':
        final user = _cell(row, columns['username']);
        final email = _cell(row, columns['email']);
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
        _addAdditionalUrls(
          customFields,
          _cell(row, columns['additional_urls']),
          primary: url,
        );
        notes = _cleanNote(rawNote);
      case 'note':
      case 'secure_note':
        notes = _cleanNote(rawNote);
      case 'credit_card':
      case 'creditcard':
      case 'payment':
        _addField(customFields, 'Cardholder Name',
            _cell(row, columns['cardholdername']));
        _addField(customFields, 'Number', _cell(row, columns['cardnumber']),
            protected: true);
        _addField(customFields, 'Security Code', _cell(row, columns['cvc']),
            protected: true);
        _addField(customFields, 'PIN', _cell(row, columns['pin']),
            protected: true);
        _addField(
            customFields, 'Expiration', _cell(row, columns['expirydate']));
        _addField(customFields, 'Zip Code', _cell(row, columns['zipcode']));
        notes = _cleanNote(rawNote);
      case 'identity':
        _addField(customFields, 'Full Name', _cell(row, columns['full_name']));
        _addField(customFields, 'Email', _cell(row, columns['email']));
        _addField(customFields, 'Phone', _cell(row, columns['phone_number']));
        _addField(customFields, 'Address 1', _cell(row, columns['address1']));
        _addField(customFields, 'Address 2', _cell(row, columns['address2']));
        _addField(customFields, 'City', _cell(row, columns['city']));
        _addField(customFields, 'State', _cell(row, columns['state']));
        _addField(customFields, 'Zip Code', _cell(row, columns['zipcode']));
        _addField(customFields, 'Country', _cell(row, columns['country']));
        notes = _cleanNote(rawNote);
      default:
        // Unknown / future NordPass item type. Rather than drop user data,
        // fall back to a best-effort login mapping so nothing is lost.
        username = _cell(row, columns['username']) ?? _cell(row, columns['email']);
        password = _cell(row, columns['password']);
        url = _firstUri(_cell(row, columns['url']));
        notes = _cleanNote(rawNote);
    }

    // NordPass stores extra fields as a JSON array in `custom_fields`. Flatten
    // any present onto the item; unrecognized shapes are skipped silently.
    _addCustomFields(customFields, _cell(row, columns['custom_fields']));

    final tags = <String>[];
    if (folder != null && folder.trim().isNotEmpty) {
      tags.add(folder.trim());
    }
    final sharedFolder = _cell(row, columns['shared_folder']);
    if (sharedFolder != null && sharedFolder.trim().isNotEmpty) {
      tags.add(sharedFolder.trim());
    }

    final item = ImportParsedItem(
      title: _sanitize(name) ?? '',
      username: _sanitize(username),
      password: _sanitize(password),
      url: _sanitize(url),
      notes: _sanitize(notes),
      tags: tags,
      customFields: customFields,
    );

    item.storeSourceField('nordpass_type', type);
    item.storeSourceField('csv_row', rowNumber.toString());

    if (item.title.trim().isEmpty) {
      item.addError('Missing title in row $rowNumber');
    }

    return item;
  }

  // ── Structured field helpers ──────────────────────────────────────────────

  /// Adds the comma-joined `additional_urls` as numbered custom fields,
  /// skipping the one already promoted to the primary [primary] URL.
  void _addAdditionalUrls(
    List<CustomImportField> out,
    String? raw, {
    String? primary,
  }) {
    if (raw == null || raw.trim().isEmpty) return;
    var index = 1;
    for (final piece in raw.split(',')) {
      final value = piece.trim();
      if (value.isEmpty) continue;
      if (primary != null && value == primary) continue;
      _addField(out, 'URL ${index++}', value);
    }
  }

  /// NordPass stores additional custom fields as a JSON array in the
  /// `custom_fields` column. Each entry typically exposes a `label`/`name` and
  /// a `value`, with `type` == `hidden`/`secret` denoting a protected field.
  /// Shapes that don't match are skipped silently so an unexpected structure
  /// can never abort the whole import.
  void _addCustomFields(List<CustomImportField> out, String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } catch (_) {
      return; // Not JSON — nothing structured to extract.
    }
    if (decoded is! List) return;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final label = _str(entry['label']) ??
          _str(entry['name']) ??
          _str(entry['title']) ??
          '';
      final value = _str(entry['value']) ?? _str(entry['content']);
      final typeStr = (_str(entry['type']) ?? '').toLowerCase();
      final protected = typeStr == 'hidden' ||
          typeStr == 'secret' ||
          typeStr == 'password' ||
          entry['hidden'] == true;
      _addField(out, label, value, protected: protected);
    }
  }

  /// Strips control characters from a free-form note while preserving its
  /// visible multi-line content.
  String? _cleanNote(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final result = _sanitize(raw)?.trim() ?? '';
    return result.isEmpty ? null : result;
  }

  /// A record-aware CSV tokenizer that correctly handles quoted fields that
  /// span multiple physical lines (NordPass notes routinely contain embedded
  /// newlines, e.g. backup codes).
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

  /// NordPass stores multiple URIs comma-joined in a single value. Use the
  /// first as the primary URL.
  String? _firstUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final comma = value.indexOf(',');
    if (comma > 0) return value.substring(0, comma).trim();
    return value.trim();
  }

  /// Builds a stable key for duplicate detection across identical items.
  String _dedupKey(ImportParsedItem item) {
    return [
      (item.getSourceField('nordpass_type') ?? ''),
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

