import 'dart:io';

import '../domain/import_parsed_item.dart';

/// Parses Google Chrome / Chromium password CSV exports.
///
/// Chrome exports credentials via **Settings → Passwords → Export passwords**
/// as a CSV with the header: `name,url,username,password,note`.
///
/// The format is deliberately simple: one row per credential, no multi-line
/// fields, no TOTP support, no folder/tag columns. The `name` column is the
/// human-readable site title and `url` is the login URL.
class ChromeParser {
  const ChromeParser();

  Future<List<ImportParsedItem>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('File not found: $filePath');
    }

    final extension = _fileExtension(filePath);
    if (extension != '.csv') {
      throw FormatException(
          'Invalid file type "$extension". '
          'Chrome password exports must be a .csv file.');
    }

    final content = await file.readAsString();
    return parseCsv(content);
  }

  List<ImportParsedItem> parseCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The Chrome CSV file is empty.');
    }

    final records = _parseCsvRecords(content);
    if (records.isEmpty) {
      throw const FormatException('The Chrome CSV file has no rows.');
    }

    // Validate header.
    final headers =
        records.first.map((h) => h.trim().toLowerCase()).toList();
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    if (!columns.containsKey('name') ||
        !columns.containsKey('url') ||
        !columns.containsKey('username') ||
        !columns.containsKey('password')) {
      throw const FormatException(
          'This CSV does not look like a Chrome password export. '
          'Expected columns: name, url, username, password.');
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var r = 1; r < records.length; r++) {
      final row = records[r];
      if (row.every((c) => c.trim().isEmpty)) continue;
      final item = _parseRow(row, columns, r + 1);
      if (item == null) continue;
      if (!seen.add(_dedupKey(item))) continue;
      parsed.add(item);
    }

    if (parsed.isEmpty) {
      throw const FormatException(
          'No importable rows were found in this Chrome CSV export.');
    }

    return parsed;
  }

  ImportParsedItem? _parseRow(
    List<String> row,
    Map<String, int> columns,
    int rowNumber,
  ) {
    final name = _cell(row, columns['name']);
    final url = _cell(row, columns['url']);
    final username = _cell(row, columns['username']);
    final password = _cell(row, columns['password']);
    final note = _cell(row, columns['note']);

    final item = ImportParsedItem(
      title: _sanitize(name ?? '') ?? '',
      username: _sanitize(username),
      password: _sanitize(password),
      url: _sanitize(url),
      notes: _sanitize(note),
    );

    item.storeSourceField('csv_row', rowNumber.toString());

    if (item.title.trim().isEmpty) {
      item.addError('Missing name in row $rowNumber');
    }

    return item;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String? _cell(List<String> row, int? index) {
    if (index == null || index >= row.length) return null;
    final v = row[index].trim();
    return v.isEmpty ? null : v;
  }

  String _dedupKey(ImportParsedItem item) {
    return [
      item.title.trim().toLowerCase(),
      (item.username ?? '').trim().toLowerCase(),
      item.password ?? '',
      (item.url ?? '').trim().toLowerCase(),
      (item.notes ?? '').trim(),
    ].join('\u0000');
  }

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
        i++;
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

    if (sawAnyChar || buffer.isNotEmpty || fields.isNotEmpty) {
      fields.add(buffer.toString());
      records.add(fields);
    }

    return records;
  }

  static String? _sanitize(String? input) {
    if (input == null) return null;
    return input.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
      '',
    );
  }

  String _fileExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }
}
