import 'dart:convert';
import 'dart:io';

import '../domain/import_parsed_item.dart';

/// Parses RoboForm vault exports.
///
/// RoboForm exports a single CSV file with the columns:
/// `Name,Url,MatchUrl,Login,Pwd,Note,Folder,RfFieldsV2`.
///
/// The first seven columns are the well-known login fields. `RfFieldsV2` is a
/// trailing, *variable-width* region: RoboForm emits one quoted CSV column per
/// captured form field, each shaped `Label$,,,<type>,<value>` (for example
/// `User ID$,,,txt,me@x.test` or `TOTP KEY$,,,txt,otpauth://totp/?secret=…`).
/// Because each field is its own column, a single record can contain any number
/// of trailing columns beyond `RfFieldsV2`.
///
/// Mapping:
///   * `Name`               → title
///   * `Url`                → primary URL
///   * `Login` / `Pwd`      → username / password
///   * `Note`               → secure note (favorite/archived flags stripped)
///   * `Folder`             → tag
///   * `RfFieldsV2` entries → a `TOTP KEY` becomes the item's otpauth URL;
///                            other fields that aren't already the login/password
///                            are preserved as custom fields (pwd-typed fields
///                            are stored protected).
///
/// Values are de-escaped from RoboForm's CSV formula-injection guard (a leading
/// apostrophe before `= + - @`) and sanitized of control characters before they
/// reach the internal entry schema, and exact duplicate items are collapsed.
class RoboFormParser {
  const RoboFormParser();

  Future<List<ImportParsedItem>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('File not found: $filePath');
    }

    final extension = _fileExtension(filePath);
    if (extension != '.csv') {
      throw FormatException(
          'Unsupported RoboForm file: "$extension". '
          'RoboForm exports must be a .csv file.');
    }

    final content = await file.readAsString();
    return parseCsv(content);
  }

  // ── CSV ─────────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The RoboForm CSV file is empty.');
    }

    final records = _parseCsvRecords(content);
    if (records.isEmpty) {
      throw const FormatException('The RoboForm CSV file has no rows.');
    }

    final headers = records.first
        .map((h) => h.trim().toLowerCase())
        .toList(growable: false);
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    // A RoboForm CSV is identified by its signature column set. `rffieldsv2`
    // in particular is unique to RoboForm. Reject anything else with a clear
    // message so users learn they picked the wrong export.
    final looksLikeRoboForm = columns.containsKey('name') &&
        columns.containsKey('login') &&
        columns.containsKey('pwd') &&
        (columns.containsKey('rffieldsv2') || columns.containsKey('matchurl'));
    if (!looksLikeRoboForm) {
      throw const FormatException(
          'This CSV does not look like a RoboForm export. Expected columns '
          'such as "Name", "Url", "Login", "Pwd", and "RfFieldsV2".');
    }

    // Everything from the RfFieldsV2 column to the end of the record is a
    // RoboForm form-field entry. Fall back to the last known header index when
    // the column is absent so a malformed header can't crash the parse.
    final rfStart = columns['rffieldsv2'] ?? headers.length;

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var i = 1; i < records.length; i++) {
      final row = records[i];
      // Skip blank trailing lines.
      if (row.every((c) => c.trim().isEmpty)) continue;

      final item = _parseRow(row, columns, rfStart, i + 1);
      if (item == null) continue;
      if (!seen.add(_dedupKey(item))) continue; // skip exact duplicates
      parsed.add(item);
    }

    if (parsed.isEmpty) {
      throw const FormatException(
          'No importable rows were found in this RoboForm CSV export.');
    }

    return parsed;
  }

  ImportParsedItem? _parseRow(
    List<String> row,
    Map<String, int> columns,
    int rfStart,
    int rowNumber,
  ) {
    final name = _cell(row, columns['name']) ?? '';
    final url = _firstUri(_cell(row, columns['url']));
    final username = _deEscape(_cell(row, columns['login']));
    final password = _deEscape(_cell(row, columns['pwd']));
    final notes = _cleanNote(_cell(row, columns['note']));
    final folder = _cell(row, columns['folder']);

    final customFields = <CustomImportField>[];
    String? otpAuthUrl;

    // Parse the variable-width RfFieldsV2 region. Each entry that isn't the
    // primary login/password becomes a custom field; a TOTP entry is promoted
    // to the item's one-time-password URL.
    for (var c = rfStart; c < row.length; c++) {
      final raw = row[c];
      if (raw.trim().isEmpty) continue;
      final field = _parseRfField(raw);
      if (field == null) continue;

      final label = field.label;
      final value = _deEscape(field.value);
      if (value == null || value.trim().isEmpty) continue;

      final lowerLabel = label.toLowerCase();

      if (lowerLabel == 'totp key' || lowerLabel == 'totp' ||
          value.toLowerCase().startsWith('otpauth://')) {
        otpAuthUrl ??= _normalizeTotp(value, name);
        continue;
      }

      // Skip entries that merely restate the login/password we already have.
      final isLoginField =
          field.type == 'txt' && _equalsIgnoreCase(value, username);
      final isPwdField =
          field.type == 'pwd' && value == (password ?? '');
      if (isLoginField || isPwdField) {
        continue;
      }

      _addField(customFields, label, value, protected: field.type == 'pwd');
    }

    final tags = <String>[];
    if (folder != null && folder.trim().isNotEmpty) {
      tags.add(folder.trim());
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

    item.storeSourceField('csv_row', rowNumber.toString());

    if (item.title.trim().isEmpty) {
      item.addError('Missing title in row $rowNumber');
    }

    return item;
  }

  // ── RfFieldsV2 entry parsing ──────────────────────────────────────────────

  /// Parses a single `RfFieldsV2` entry of the form
  /// `<label>$,,,<type>,<value>`. The `$` separates the label from RoboForm's
  /// metadata; after it come three (usually empty) meta slots, the field type,
  /// then the value — which may itself contain commas (e.g. an otpauth URL),
  /// so everything past the type is rejoined verbatim.
  _RfField? _parseRfField(String raw) {
    final dollar = raw.indexOf(r'$');
    if (dollar < 0) return null;

    final label = raw.substring(0, dollar).trim();
    final rest = raw.substring(dollar + 1);
    final parts = rest.split(',');
    // parts: [meta1, meta2, meta3, type, value, (value cont…)]
    if (parts.length < 5) {
      // Not the expected shape — treat the whole remainder as the value.
      return _RfField(label: label, type: 'txt', value: rest);
    }
    final type = parts[3].trim().toLowerCase();
    final value = parts.sublist(4).join(',');
    return _RfField(label: label, type: type, value: value);
  }

  /// RoboForm (and the 1Password export it was built from) guards values that
  /// begin with a spreadsheet formula character by prefixing a single
  /// apostrophe. Reverse that escaping to restore the original credential.
  String? _deEscape(String? value) {
    if (value == null || value.length < 2) return value;
    if (value[0] == '\'' && _isFormulaLead(value[1])) {
      return value.substring(1);
    }
    return value;
  }

  bool _isFormulaLead(String ch) =>
      ch == '=' || ch == '+' || ch == '-' || ch == '@';

  /// Strips RoboForm's leaked `favorite:`/`archived:` flag lines from a note
  /// while preserving any real note text below them.
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
  /// span multiple physical lines (RoboForm notes routinely contain embedded
  /// newlines, e.g. the favorite/archived flags).
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

  /// RoboForm rarely comma-joins URLs, but guard against it by using the first.
  String? _firstUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final comma = value.indexOf(',');
    if (comma > 0) return value.substring(0, comma).trim();
    return value.trim();
  }

  /// Normalizes a RoboForm TOTP value into an `otpauth://` URI. RoboForm stores
  /// a complete otpauth URL (sometimes with an empty account label), which is
  /// passed through; a bare secret is wrapped.
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
      item.title.trim().toLowerCase(),
      (item.username ?? '').trim().toLowerCase(),
      item.password ?? '',
      (item.url ?? '').trim().toLowerCase(),
      (item.notes ?? '').trim(),
    ].join('\u0000');
  }

  bool _equalsIgnoreCase(String? a, String? b) {
    if (a == null || b == null) return false;
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  String? _cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return null;
    final value = row[index];
    return value.isEmpty ? null : value;
  }

  String _fileExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }
}

class _RfField {
  const _RfField({
    required this.label,
    required this.type,
    required this.value,
  });

  final String label;
  final String type;
  final String value;
}
