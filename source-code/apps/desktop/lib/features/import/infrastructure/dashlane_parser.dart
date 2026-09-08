import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../domain/import_parsed_item.dart';

/// Parses Dashlane exports.
///
/// Dashlane exports a credential bundle as five CSVs inside a ZIP, or the
/// user may upload any single CSV individually.
///
/// Supported CSVs:
///  * `credentials.csv` — `username,username2,username3,title,password,note,url,category,otpUrl`
///  * `securenotes.csv` — `title,note,category`
///  * `ids.csv` — `type,number,name,issue_date,expiration_date,place_of_issue,state`
///  * `payments.csv` — `type,account_name,account_holder,cc_number,code,…`
///  * `personalInfo.csv` — `type,title,first_name,middle_name,last_name,…`
class DashlaneParser {
  const DashlaneParser();

  Future<List<ImportParsedItem>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('File not found: $filePath');
    }

    final extension = _fileExtension(filePath);
    switch (extension) {
      case '.zip':
        return _parseZipFile(filePath);
      case '.csv':
        return _parseSingleCsvFile(filePath);
      default:
        throw FormatException(
            'Invalid file type "$extension". '
            'Dashlane exports must be a .zip archive or a .csv file.');
    }
  }

  Future<List<ImportParsedItem>> _parseZipFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Could not read Dashlane ZIP: $e');
    }

    final results = <ImportParsedItem>[];
    final seen = <String>{};
    var matchedAny = false;

    for (final entry in archive) {
      if (entry.isFile != true) continue;
      final lowered = entry.name.toLowerCase();
      if (lowered.contains('__macosx/') || lowered.contains('/.')) continue;
      final basename = _basename(entry.name).toLowerCase();
      if (!_isKnownDashlaneCsv(basename)) continue;

      matchedAny = true;
      String content;
      try {
        content = utf8.decode(entry.content as List<int>);
      } catch (e) {
        throw FormatException(
            'Could not decode "$basename" inside the Dashlane ZIP: $e');
      }

      final items = _parseCsvByBasename(basename, content);
      for (final item in items) {
        if (seen.add(_dedupKey(item))) results.add(item);
      }
    }

    if (!matchedAny) {
      throw const FormatException(
          'This ZIP does not contain any Dashlane CSV files '
          '(credentials.csv, securenotes.csv, ids.csv, payments.csv, '
          'personalInfo.csv).');
    }
    if (results.isEmpty) {
      throw const FormatException(
          'No importable items were found in the Dashlane ZIP.');
    }

    return results;
  }

  Future<List<ImportParsedItem>> _parseSingleCsvFile(String filePath) async {
    final content = await File(filePath).readAsString();
    final basename = _basename(filePath).toLowerCase();
    if (_isKnownDashlaneCsv(basename)) {
      return _parseCsvByBasename(basename, content);
    }
    return parseCsvSniffed(content);
  }

  /// Identifies a Dashlane CSV by its header and dispatches to the right parser.
  List<ImportParsedItem> parseCsvSniffed(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The Dashlane CSV file is empty.');
    }
    final records = _parseCsvRecords(content);
    if (records.isEmpty) {
      throw const FormatException('The Dashlane CSV file has no rows.');
    }
    final headers = records.first.map((h) => h.trim().toLowerCase()).toList();
    if (_isCredentialsHeader(headers)) return parseCredentialsCsv(content);
    if (_isSecureNotesHeader(headers)) return parseSecureNotesCsv(content);
    if (_isIdsHeader(headers)) return parseIdsCsv(content);
    if (_isPaymentsHeader(headers)) return parsePaymentsCsv(content);
    if (_isPersonalInfoHeader(headers)) return parsePersonalInfoCsv(content);
    throw const FormatException(
        'This CSV does not look like a Dashlane export. Expected one of: '
        'credentials, securenotes, ids, payments, or personalInfo.');
  }

  List<ImportParsedItem> _parseCsvByBasename(String basename, String content) {
    switch (basename) {
      case 'credentials.csv':
        return parseCredentialsCsv(content);
      case 'securenotes.csv':
        return parseSecureNotesCsv(content);
      case 'ids.csv':
        return parseIdsCsv(content);
      case 'payments.csv':
        return parsePaymentsCsv(content);
      case 'personalinfo.csv':
        return parsePersonalInfoCsv(content);
      default:
        return const <ImportParsedItem>[];
    }
  }

  bool _isKnownDashlaneCsv(String basename) {
    return basename == 'credentials.csv' ||
        basename == 'securenotes.csv' ||
        basename == 'ids.csv' ||
        basename == 'payments.csv' ||
        basename == 'personalinfo.csv';
  }

  // ── Header sniffing ─────────────────────────────────────────────────────

  bool _isCredentialsHeader(List<String> h) =>
      h.contains('username') && h.contains('password') && h.contains('otpurl');

  bool _isSecureNotesHeader(List<String> h) =>
      h.contains('title') &&
      h.contains('note') &&
      h.contains('category') &&
      h.length <= 4;

  bool _isIdsHeader(List<String> h) =>
      h.contains('type') &&
      h.contains('number') &&
      h.contains('place_of_issue');

  bool _isPaymentsHeader(List<String> h) =>
      h.contains('cc_number') || h.contains('routing_number');

  bool _isPersonalInfoHeader(List<String> h) =>
      h.contains('first_name') && h.contains('last_name');

  // ── credentials.csv ─────────────────────────────────────────────────────

  List<ImportParsedItem> parseCredentialsCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The credentials CSV is empty.');
    }
    final records = _parseCsvRecords(content);
    if (records.length < 2) return const <ImportParsedItem>[];

    final headers = records.first.map((h) => h.trim().toLowerCase()).toList();
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var r = 1; r < records.length; r++) {
      final row = records[r];
      if (row.every((c) => c.trim().isEmpty)) continue;

      final title = _cell(row, columns['title']);
      final username = _cell(row, columns['username']) ??
          _cell(row, columns['username2']) ??
          _cell(row, columns['username3']);
      final password = _cell(row, columns['password']);
      final url = _firstUri(_cell(row, columns['url']));
      final rawNote = _cell(row, columns['note']);
      final category = _cell(row, columns['category']);
      final otpUrl = _cell(row, columns['otpurl']);

      // Alternate usernames stored as custom fields when a primary exists.
      final customFields = <CustomImportField>[];
      if (_cell(row, columns['username']) != null) {
        final u2 = _cell(row, columns['username2']);
        final u3 = _cell(row, columns['username3']);
        if (u2 != null) {
          _addField(customFields, 'Username 2', u2);
        }
        if (u3 != null) {
          _addField(customFields, 'Username 3', u3);
        }
      }

      // Parse `fields:` block from notes into additional custom fields.
      final noteAndFields = _extractFieldsFromNote(rawNote);

      final tags = <String>[];
      if (category != null && category.isNotEmpty) {
        tags.add(category);
      }

      final item = ImportParsedItem(
        title: _sanitize(title ?? '') ?? '',
        username: _sanitize(username),
        password: _sanitize(password),
        url: _sanitize(url),
        otpAuthUrl: _normalizeTotp(otpUrl, title ?? ''),
        notes: _cleanNote(noteAndFields.cleanedNote),
        tags: tags,
        customFields: [...customFields, ...noteAndFields.customFields],
      );

      item.storeSourceField('dashlane_type', 'credential');
      item.storeSourceField('csv_row', (r + 1).toString());

      if (item.title.trim().isEmpty) {
        item.addError('Missing title in row ${r + 1}');
      }

      if (seen.add(_dedupKey(item))) parsed.add(item);
    }

    return parsed;
  }

  // ── securenotes.csv ─────────────────────────────────────────────────────

  List<ImportParsedItem> parseSecureNotesCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The securenotes CSV is empty.');
    }
    final records = _parseCsvRecords(content);
    if (records.length < 2) return const <ImportParsedItem>[];

    final headers = records.first.map((h) => h.trim().toLowerCase()).toList();
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var r = 1; r < records.length; r++) {
      final row = records[r];
      if (row.every((c) => c.trim().isEmpty)) continue;

      final title = _cell(row, columns['title']);
      final rawNote = _cell(row, columns['note']);
      final category = _cell(row, columns['category']);

      final noteAndFields = _extractFieldsFromNote(rawNote);

      final tags = <String>[];
      if (category != null && category.isNotEmpty) {
        tags.add(category);
      }

      final item = ImportParsedItem(
        title: _sanitize(title ?? '') ?? '',
        notes: _cleanNote(noteAndFields.cleanedNote),
        tags: tags,
        customFields: noteAndFields.customFields,
      );

      item.storeSourceField('dashlane_type', 'securenote');
      item.storeSourceField('csv_row', (r + 1).toString());

      if (item.title.trim().isEmpty) {
        item.addError('Missing title in row ${r + 1}');
      }

      if (seen.add(_dedupKey(item))) parsed.add(item);
    }

    return parsed;
  }

  // ── ids.csv ─────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseIdsCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The ids CSV is empty.');
    }
    final records = _parseCsvRecords(content);
    if (records.length < 2) return const <ImportParsedItem>[];

    final headers = records.first.map((h) => h.trim().toLowerCase()).toList();
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var r = 1; r < records.length; r++) {
      final row = records[r];
      if (row.every((c) => c.trim().isEmpty)) continue;

      final type = _cell(row, columns['type']) ?? 'ID';
      final name = _cell(row, columns['name']);
      final number = _cell(row, columns['number']);
      final issueDate = _cell(row, columns['issue_date']);
      final expirationDate = _cell(row, columns['expiration_date']);
      final placeOfIssue = _cell(row, columns['place_of_issue']);
      final state = _cell(row, columns['state']);

      final title = name ?? '$type Document';
      final customFields = <CustomImportField>[];
      _addField(customFields, 'Type', type);
      _addField(customFields, 'Number', number, protected: true);
      _addField(customFields, 'Issue Date', issueDate);
      _addField(customFields, 'Expiration Date', expirationDate);
      _addField(customFields, 'Place of Issue', placeOfIssue);
      _addField(customFields, 'State', state);

      final item = ImportParsedItem(
        title: _sanitize(title) ?? '',
        customFields: customFields,
      );

      item.storeSourceField('dashlane_type', 'id');
      item.storeSourceField('csv_row', (r + 1).toString());

      if (seen.add(_dedupKey(item))) parsed.add(item);
    }

    return parsed;
  }

  // ── payments.csv ────────────────────────────────────────────────────────

  List<ImportParsedItem> parsePaymentsCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The payments CSV is empty.');
    }
    final records = _parseCsvRecords(content);
    if (records.length < 2) return const <ImportParsedItem>[];

    final headers = records.first.map((h) => h.trim().toLowerCase()).toList();
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var r = 1; r < records.length; r++) {
      final row = records[r];
      if (row.every((c) => c.trim().isEmpty)) continue;

      final type = _cell(row, columns['type']) ?? 'Payment';
      final accountName = _cell(row, columns['account_name']);
      final accountHolder = _cell(row, columns['account_holder']);
      final ccNumber = _cell(row, columns['cc_number']);
      final code = _cell(row, columns['code']);
      final expMonth = _cell(row, columns['expiration_month']);
      final expYear = _cell(row, columns['expiration_year']);
      final routingNumber = _cell(row, columns['routing_number']);
      final accountNumber = _cell(row, columns['account_number']);
      final country = _cell(row, columns['country']);
      final issuingBank = _cell(row, columns['issuing_bank']);
      final note = _cell(row, columns['note']);
      final name = _cell(row, columns['name']);

      final title = name ?? accountName ?? '$type Card';
      final customFields = <CustomImportField>[];
      _addField(customFields, 'Type', type);
      _addField(customFields, 'Account Name', accountName);
      _addField(customFields, 'Account Holder', accountHolder);
      _addField(customFields, 'Card Number', ccNumber, protected: true);
      _addField(customFields, 'Security Code', code, protected: true);
      if (expMonth != null || expYear != null) {
        _addField(customFields, 'Expiration',
            '${expMonth ?? '??'}/${expYear ?? '??'}');
      }
      _addField(customFields, 'Routing Number', routingNumber, protected: true);
      _addField(customFields, 'Account Number', accountNumber, protected: true);
      _addField(customFields, 'Country', country);
      _addField(customFields, 'Issuing Bank', issuingBank);

      final item = ImportParsedItem(
        title: _sanitize(title) ?? '',
        notes: _cleanNote(note),
        customFields: customFields,
      );

      item.storeSourceField('dashlane_type', 'payment');
      item.storeSourceField('csv_row', (r + 1).toString());

      if (seen.add(_dedupKey(item))) parsed.add(item);
    }

    return parsed;
  }

  // ── personalInfo.csv ────────────────────────────────────────────────────

  List<ImportParsedItem> parsePersonalInfoCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The personalInfo CSV is empty.');
    }
    final records = _parseCsvRecords(content);
    if (records.length < 2) return const <ImportParsedItem>[];

    final headers = records.first.map((h) => h.trim().toLowerCase()).toList();
    final columns = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      columns[headers[i]] = i;
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var r = 1; r < records.length; r++) {
      final row = records[r];
      if (row.every((c) => c.trim().isEmpty)) continue;

      final type = _cell(row, columns['type']) ?? 'Personal';
      final title = _cell(row, columns['title']) ??
          _cell(row, columns['item_name']) ??
          '$type Info';
      final customFields = <CustomImportField>[];

      // Walk every column except `type` and `title` and store non-empty ones.
      for (var c = 0; c < headers.length; c++) {
        final h = headers[c];
        if (h == 'type' || h == 'title') continue;
        final v = _cell(row, c);
        if (v == null) continue;
        _addField(customFields, _humanizeHeader(h), v);
      }

      final item = ImportParsedItem(
        title: _sanitize(title) ?? '',
        customFields: customFields,
      );

      item.storeSourceField('dashlane_type', type);
      item.storeSourceField('csv_row', (r + 1).toString());

      if (seen.add(_dedupKey(item))) parsed.add(item);
    }

    return parsed;
  }

  // ── Note parsing / fields extraction ────────────────────────────────────

  /// Dashlane notes frequently contain a `fields:` block with `Key: Value`
  /// pairs — sometimes prefixed with `Notes:` for the real note content.
  /// This method splits the raw note into the human-readable portion and
  /// any custom fields embedded inside.
  _NoteAndFields _extractFieldsFromNote(String? rawNote) {
    if (rawNote == null || rawNote.trim().isEmpty) {
      return _NoteAndFields('', const <CustomImportField>[]);
    }

    final lines = LineSplitter.split(rawNote).toList();
    final noteLines = <String>[];
    final customFields = <CustomImportField>[];
    var inFieldsBlock = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (!inFieldsBlock) noteLines.add('');
        continue;
      }

      // Detect start of a `fields:` block — e.g. `fields: Key: value` or
      // `fields: : password` (the latter is a Dashlane template-type token).
      if (trimmed.startsWith('fields:')) {
        inFieldsBlock = true;
        final rest = trimmed.substring('fields:'.length).trim();
        _parseFieldLine(rest, customFields);
        continue;
      }

      // Lines that start with `Notes:` carry the real note body.
      if (trimmed.startsWith('Notes:')) {
        final rest = trimmed.substring('Notes:'.length).trim();
        if (rest.isNotEmpty) noteLines.add(rest);
        inFieldsBlock = false;
        continue;
      }

      if (inFieldsBlock) {
        _parseFieldLine(trimmed, customFields);
      } else {
        noteLines.add(line);
      }
    }

    return _NoteAndFields(noteLines.join('\n'), customFields);
  }

  /// Parses a single `Key: Value` line and adds it to [out].
  void _parseFieldLine(String line, List<CustomImportField> out) {
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0) return;
    final key = line.substring(0, colonIdx).trim();
    final value = line.substring(colonIdx + 1).trim();
    if (key.isEmpty && value.isEmpty) return;
    // Skip Dashlane template-type tokens like `: password`, `: note`.
    if (key.isEmpty && _isPlaceholderType(value)) return;
    if (key.isEmpty) return;
    if (value.isEmpty) return;
    final protected = key.toLowerCase() == 'password' ||
        key.toLowerCase() == 'code' ||
        key.toLowerCase() == 'security code';
    _addField(out, key, value, protected: protected);
  }

  bool _isPlaceholderType(String value) {
    final v = value.trim().toLowerCase();
    return v == 'password' ||
        v == 'note' ||
        v == 'text' ||
        v == 'totp' ||
        v == 'email' ||
        v == 'url';
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _humanizeHeader(String header) {
    return header
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String? _normalizeTotp(String? value, String accountLabel) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toLowerCase().startsWith('otpauth://')) return trimmed;
    final account = Uri.encodeComponent(
        accountLabel.trim().isEmpty ? 'Dashlane' : accountLabel.trim());
    return 'otpauth://totp/$account?secret=$trimmed';
  }

  String? _firstUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final comma = value.indexOf(',');
    if (comma > 0) return value.substring(0, comma).trim();
    return value.trim();
  }

  String? _cleanNote(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final sanitized = _sanitize(raw)?.trim() ?? '';
    if (sanitized.isEmpty) return null;
    final lines = LineSplitter.split(sanitized).toList(growable: true);
    lines.removeWhere((l) {
      final t = l.trim().toLowerCase();
      return t.startsWith('favorite:') || t.startsWith('archived:');
    });
    final result = lines.join('\n').trim();
    return result.isEmpty ? null : result;
  }

  String? _cell(List<String> row, int? index) {
    if (index == null || index >= row.length) return null;
    final v = row[index].trim();
    return v.isEmpty ? null : v;
  }

  void _addField(
    List<CustomImportField> out,
    String name,
    String? value, {
    bool protected = false,
  }) {
    final cleanValue = _sanitize(value);
    if (cleanValue == null || cleanValue.trim().isEmpty) return;
    final cleanName = _sanitize(name)?.trim() ?? '';
    if (cleanName.isEmpty) return;
    out.add(CustomImportField(
      name: cleanName,
      value: cleanValue,
      isProtected: protected,
    ));
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

  String _basename(String path) {
    final lastSlash = path.lastIndexOf('/');
    final lastBackslash = path.lastIndexOf('\\');
    final sep = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    return sep < 0 ? path : path.substring(sep + 1);
  }

  String _fileExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }
}

class _NoteAndFields {
  _NoteAndFields(this.cleanedNote, this.customFields);
  final String cleanedNote;
  final List<CustomImportField> customFields;
}
