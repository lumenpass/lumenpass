import 'dart:convert';
import 'dart:io';

import '../domain/import_parsed_item.dart';

/// Parses Enpass vault exports.
///
/// Enpass exposes three export shapes; this parser handles all three:
///
///  * **JSON** — `{ "folders": [...], "items": [...] }`. Each item has a
///    `category`, `title`, `note`, `folders` (UUID list) and a uniform
///    `fields[]` array of `{ label, value, type, sensitive }` objects.
///    Known field `type`s include `username`, `email`, `password`, `url`,
///    `totp`, `phone`, `text`, `numeric`, `date`, and `section` (a UI-only
///    separator that is skipped).
///  * **CSV** — header-less; each row is `Title,(Label,Value)…` with a
///    leading `*` on a label meaning the field is sensitive (e.g. `*Password`).
///    Custom fields are appended as additional label/value pairs and the
///    trailing cell often contains a multi-line `favorite:` / `archived:`
///    metadata block that is stripped from the note.
///  * **TXT** — human-readable blocks separated by blank lines, each line is
///    `Label : Value`. A `Title : ...` line begins a new item; lines that lack
///    the ` : ` separator are appended to the previous field as a multi-line
///    continuation (used for note bodies and recovery-code lists).
///
/// All three formats are normalised to the same [ImportParsedItem] shape with
/// the standard login fields (`username`, `password`, `url`, `otpAuthUrl`,
/// `notes`) promoted out of the per-item field bag and everything else kept as
/// custom fields. Folder names become tags. Values are sanitised against C0/C1
/// control characters and exact duplicates are collapsed.
class EnpassParser {
  const EnpassParser();

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
      case '.txt':
        return parseTxt(content);
      default:
        throw FormatException(
            'Unsupported Enpass file: "$extension". '
            'Enpass exports must be a .json, .csv, or .txt file.');
    }
  }

  // ── JSON ────────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseJson(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The Enpass JSON file is empty.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      throw FormatException('The Enpass JSON file is not valid JSON: $e');
    }

    if (decoded is! Map) {
      throw const FormatException(
          'The Enpass JSON file must contain a top-level object.');
    }
    if (!decoded.containsKey('items')) {
      throw const FormatException(
          'This JSON does not look like an Enpass export. Expected a top-level '
          '"items" array (and usually a "folders" array).');
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw const FormatException(
          'The Enpass JSON "items" key must be an array.');
    }

    // Build a folder UUID → folder title lookup so per-item folder references
    // turn into human-readable tags.
    final folderLookup = <String, String>{};
    final rawFolders = decoded['folders'];
    if (rawFolders is List) {
      for (final folder in rawFolders) {
        if (folder is! Map) continue;
        final uuid = _str(folder['uuid']);
        final title = _str(folder['title']);
        if (uuid != null && title != null && title.trim().isNotEmpty) {
          folderLookup[uuid] = title.trim();
        }
      }
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var i = 0; i < rawItems.length; i++) {
      final raw = rawItems[i];
      if (raw is! Map) continue;
      // Skip trashed items — they're already deleted from the user's view in
      // Enpass and importing them would resurrect them in the target vault.
      if (raw['trashed'] == 1 || raw['trashed'] == true) continue;
      final item = _parseJsonItem(raw, folderLookup, i + 1);
      if (item == null) continue;
      if (!seen.add(_dedupKey(item))) continue;
      parsed.add(item);
    }

    if (parsed.isEmpty) {
      throw const FormatException(
          'No importable items were found in this Enpass JSON export.');
    }

    return parsed;
  }

  ImportParsedItem? _parseJsonItem(
    Map raw,
    Map<String, String> folderLookup,
    int itemIndex,
  ) {
    final title = _str(raw['title']) ?? '';
    final category =
        (_str(raw['category']) ?? 'login').toLowerCase().trim();
    final rawNote = _str(raw['note']);

    String? username;
    String? email;
    String? password;
    String? url;
    String? otpAuthUrl;
    final extraUrls = <String>[];
    final customFields = <CustomImportField>[];

    final rawFields = raw['fields'];
    if (rawFields is List) {
      // Stable order preservation: walk in the array's original order.
      for (final f in rawFields) {
        if (f is! Map) continue;
        if (f['deleted'] == 1 || f['deleted'] == true) continue;

        final fieldType = (_str(f['type']) ?? 'text').toLowerCase().trim();
        final label = (_str(f['label']) ?? '').trim();
        final value = _str(f['value']);
        final sensitive = f['sensitive'] == 1 || f['sensitive'] == true;

        // Section dividers carry no value and only exist to group fields in
        // the Enpass UI; skip them.
        if (fieldType == 'section') continue;
        if (value == null || value.isEmpty) continue;

        switch (fieldType) {
          case 'username':
            username ??= value;
          case 'email':
            email ??= value;
          case 'password':
            password ??= value;
          case 'url':
            if (url == null) {
              url = _firstUri(value);
            } else {
              extraUrls.add(value);
            }
          case 'totp':
            otpAuthUrl ??= _normalizeTotp(value, title);
          default:
            _addField(
              customFields,
              label.isEmpty ? _humanizeFieldType(fieldType) : label,
              value,
              protected: sensitive,
            );
        }
      }
    }

    // KDBX exposes a single UserName slot. Prefer the explicit username,
    // fall back to email, and preserve the other side as a custom field so
    // nothing is lost.
    if (username == null && email != null) {
      username = email;
    } else if (email != null && email != username) {
      _addField(customFields, 'Email', email);
    }

    for (var i = 0; i < extraUrls.length; i++) {
      _addField(customFields, 'URL ${i + 2}', extraUrls[i]);
    }

    final tags = <String>[];
    final rawFolderRefs = raw['folders'];
    if (rawFolderRefs is List) {
      for (final ref in rawFolderRefs) {
        final folderName = folderLookup[_str(ref)];
        if (folderName != null && folderName.isNotEmpty) {
          tags.add(folderName);
        }
      }
    }
    if (raw['favorite'] == 1 || raw['favorite'] == true) {
      tags.add('Favorite');
    }
    if (raw['archived'] == 1 || raw['archived'] == true) {
      tags.add('Archived');
    }

    final item = ImportParsedItem(
      title: _sanitize(title) ?? '',
      username: _sanitize(username),
      password: _sanitize(password),
      url: _sanitize(url),
      otpAuthUrl: _sanitize(otpAuthUrl),
      notes: _cleanNote(rawNote),
      tags: tags,
      customFields: customFields,
    );

    item.storeSourceField('enpass_category', category);
    item.storeSourceField('enpass_index', itemIndex.toString());

    if (item.title.trim().isEmpty) {
      item.addError('Missing title in item #$itemIndex');
    }

    return item;
  }

  // ── CSV ─────────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseCsv(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The Enpass CSV file is empty.');
    }

    final records = _parseCsvRecords(content);
    if (records.isEmpty) {
      throw const FormatException('The Enpass CSV file has no rows.');
    }

    // Enpass CSVs are header-less. Cheap shape sanity check: every record
    // should have at least one cell, and the second cell of at least one
    // row should be a recognisable Enpass label like "Username", "Password",
    // "*Password", "Key", "E-mail", etc. We don't enforce this strictly
    // because the very first record can be a non-login custom record.
    final hasAnyEnpassLabel = records.any((row) {
      for (var c = 1; c < row.length; c += 2) {
        final label = row[c].trim().toLowerCase();
        if (_enpassCsvLabels.contains(label) ||
            label.startsWith('*')) {
          return true;
        }
      }
      return false;
    });
    if (!hasAnyEnpassLabel) {
      throw const FormatException(
          'This CSV does not look like an Enpass export. Expected '
          'label/value pairs like "Username", "*Password", "Website", etc.');
    }

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    for (var i = 0; i < records.length; i++) {
      final row = records[i];
      if (row.every((c) => c.trim().isEmpty)) continue;
      final item = _parseCsvRow(row, i + 1);
      if (item == null) continue;
      if (!seen.add(_dedupKey(item))) continue;
      parsed.add(item);
    }

    if (parsed.isEmpty) {
      throw const FormatException(
          'No importable rows were found in this Enpass CSV export.');
    }

    return parsed;
  }

  ImportParsedItem? _parseCsvRow(List<String> row, int rowNumber) {
    if (row.isEmpty) return null;
    final title = row.first;

    String? username;
    String? email;
    String? password;
    String? url;
    String? otpAuthUrl;
    String? notes;
    final extraUrls = <String>[];
    final customFields = <CustomImportField>[];

    // Walk the trailing tokens as alternating label/value pairs. If a token
    // sits in the label slot but its label is empty AND the next token does
    // not exist, treat it as a trailing free-text note (Enpass occasionally
    // emits the note as the last value of a "phantom" pair).
    var c = 1;
    while (c < row.length) {
      final rawLabel = row[c];
      if (c + 1 >= row.length) {
        // Unpaired trailing cell — treat as free-text note.
        final tail = rawLabel.trim();
        if (tail.isNotEmpty) {
          notes = (notes == null || notes.isEmpty) ? tail : '$notes\n$tail';
        }
        break;
      }
      final value = row[c + 1];
      c += 2;

      var label = rawLabel.trim();
      if (label.isEmpty && value.trim().isEmpty) continue;

      final sensitive = label.startsWith('*');
      if (sensitive) label = label.substring(1).trim();
      final normalizedLabel = label.toLowerCase();

      if (normalizedLabel == 'additional details' ||
          normalizedLabel == 'additional info') {
        // Section divider — skip.
        continue;
      }

      switch (normalizedLabel) {
        case 'username':
          username ??= value;
        case 'e-mail':
        case 'email':
          email ??= value;
        case 'password':
          password ??= value;
        case 'website':
        case 'url':
          if (url == null) {
            url = _firstUri(value);
          } else {
            extraUrls.add(value);
          }
        case 'one-time code':
        case 'otp':
        case 'totp':
          otpAuthUrl ??= _normalizeTotp(value, title);
        case 'note':
        case 'notes':
          final cleaned = _stripFavoriteArchived(value);
          if (cleaned.isNotEmpty) {
            notes = (notes == null || notes.isEmpty)
                ? cleaned
                : '$notes\n$cleaned';
          }
        default:
          if (label.isEmpty) {
            // Unlabeled value — treat as appended note text.
            final tail = value.trim();
            if (tail.isNotEmpty) {
              notes = (notes == null || notes.isEmpty)
                  ? tail
                  : '$notes\n$tail';
            }
          } else {
            // Custom field; Enpass occasionally embeds the favorite/archived
            // metadata block at the tail end of the value, so strip it.
            final cleanedValue = _stripFavoriteArchived(value);
            if (cleanedValue.isNotEmpty) {
              _addField(customFields, label, cleanedValue,
                  protected: sensitive);
            }
          }
      }
    }

    if (username == null && email != null) {
      username = email;
    } else if (email != null && email != username) {
      _addField(customFields, 'Email', email);
    }

    for (var i = 0; i < extraUrls.length; i++) {
      _addField(customFields, 'URL ${i + 2}', extraUrls[i]);
    }

    final item = ImportParsedItem(
      title: _sanitize(title) ?? '',
      username: _sanitize(username),
      password: _sanitize(password),
      url: _sanitize(url),
      otpAuthUrl: _sanitize(otpAuthUrl),
      notes: _cleanNote(notes),
      customFields: customFields,
    );

    item.storeSourceField('enpass_source', 'csv');
    item.storeSourceField('csv_row', rowNumber.toString());

    if (item.title.trim().isEmpty) {
      item.addError('Missing title in row $rowNumber');
    }

    return item;
  }

  // ── TXT ─────────────────────────────────────────────────────────────────

  List<ImportParsedItem> parseTxt(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('The Enpass TXT file is empty.');
    }

    // Records are separated by one or more blank lines.
    final blocks = content.split(RegExp(r'\r?\n\s*\r?\n+'));

    final parsed = <ImportParsedItem>[];
    final seen = <String>{};

    var blockIndex = 0;
    var hadAnyTitle = false;
    for (final block in blocks) {
      blockIndex++;
      if (block.trim().isEmpty) continue;
      final item = _parseTxtBlock(block, blockIndex);
      if (item == null) continue;
      hadAnyTitle = true;
      if (!seen.add(_dedupKey(item))) continue;
      parsed.add(item);
    }

    if (!hadAnyTitle) {
      throw const FormatException(
          'This TXT does not look like an Enpass export. Expected blocks of '
          '"Label : Value" lines starting with "Title : ...".');
    }
    if (parsed.isEmpty) {
      throw const FormatException(
          'No importable blocks were found in this Enpass TXT export.');
    }

    return parsed;
  }

  ImportParsedItem? _parseTxtBlock(String block, int blockIndex) {
    final lines = LineSplitter.split(block).toList(growable: false);
    if (lines.isEmpty) return null;

    // Build the (label, value) sequence. Lines without " : " are appended to
    // the previously opened field as a multi-line continuation.
    final pairs = <List<String>>[];
    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        if (pairs.isNotEmpty) {
          pairs.last[1] = '${pairs.last[1]}\n';
        }
        continue;
      }
      final sepIndex = line.indexOf(' : ');
      if (sepIndex < 0) {
        if (pairs.isEmpty) {
          // Bare line before any labeled pair — treat as the title fallback.
          pairs.add(<String>['Title', line.trim()]);
        } else {
          pairs.last[1] = '${pairs.last[1]}\n$line';
        }
        continue;
      }
      final label = line.substring(0, sepIndex).trim();
      final value = line.substring(sepIndex + 3);
      pairs.add(<String>[label, value]);
    }

    // The first pair must be a Title; otherwise this is not an Enpass record.
    if (pairs.isEmpty) return null;
    if (pairs.first[0].toLowerCase() != 'title') return null;
    final title = pairs.first[1];

    String? username;
    String? email;
    String? password;
    String? url;
    String? otpAuthUrl;
    String? notes;
    final extraUrls = <String>[];
    final extraPasswords = <String>[];
    final customFields = <CustomImportField>[];

    for (var i = 1; i < pairs.length; i++) {
      final label = pairs[i][0];
      final value = pairs[i][1];
      if (label.isEmpty && value.trim().isEmpty) continue;

      final normalized = label.toLowerCase();

      switch (normalized) {
        case 'username':
        case 'new username':
          username ??= value.trim();
        case 'email':
        case 'e-mail':
          email ??= value.trim();
        case 'password':
          if (password == null) {
            password = value;
          } else {
            extraPasswords.add(value);
          }
        case 'website':
        case 'url':
          if (url == null) {
            url = _firstUri(value);
          } else {
            extraUrls.add(value);
          }
        case 'one-time code':
        case 'totp':
        case 'otp':
          otpAuthUrl ??= _normalizeTotp(value, title);
        case 'note':
        case 'notes':
          final stripped = _stripFavoriteArchived(value);
          if (stripped.isNotEmpty) {
            notes = (notes == null || notes.isEmpty)
                ? stripped
                : '$notes\n$stripped';
          }
        default:
          if (label.isEmpty) continue;
          // Enpass exports unused template slots as `Field N : password`
          // or `Field N : note` — these are type tokens, not data.
          if (_looksLikeFieldSlot(label) && _isPlaceholderType(value)) {
            continue;
          }
          _addField(customFields, label, value);
      }
    }

    if (username == null && email != null) {
      username = email;
    } else if (email != null && email != username) {
      _addField(customFields, 'Email', email);
    }

    for (var i = 0; i < extraUrls.length; i++) {
      _addField(customFields, 'URL ${i + 2}', extraUrls[i]);
    }
    for (var i = 0; i < extraPasswords.length; i++) {
      _addField(customFields, 'Password ${i + 2}', extraPasswords[i],
          protected: true);
    }

    final item = ImportParsedItem(
      title: _sanitize(title) ?? '',
      username: _sanitize(username),
      password: _sanitize(password),
      url: _sanitize(url),
      otpAuthUrl: _sanitize(otpAuthUrl),
      notes: _cleanNote(notes),
      customFields: customFields,
    );

    item.storeSourceField('enpass_source', 'txt');
    item.storeSourceField('txt_block', blockIndex.toString());

    if (item.title.trim().isEmpty) {
      item.addError('Missing title in block #$blockIndex');
    }

    return item;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static const Set<String> _enpassCsvLabels = <String>{
    'username',
    'e-mail',
    'email',
    'password',
    'website',
    'url',
    'one-time code',
    'phone number',
    'security question',
    'security answer',
    'key',
    'note',
    'notes',
  };

  bool _looksLikeFieldSlot(String label) {
    final m = RegExp(r'^field\s*\d+$', caseSensitive: false);
    return m.hasMatch(label.trim());
  }

  bool _isPlaceholderType(String value) {
    final v = value.trim().toLowerCase();
    return v == 'password' ||
        v == 'note' ||
        v == 'text' ||
        v == 'totp' ||
        v == 'email' ||
        v == 'url' ||
        v == 'numeric' ||
        v == 'date';
  }

  /// Strips trailing `favorite: …` / `archived: …` lines that Enpass embeds
  /// inside note/value cells; preserves the real content.
  String _stripFavoriteArchived(String value) {
    final lines = LineSplitter.split(value).toList(growable: true);
    lines.removeWhere((l) {
      final trimmed = l.trim().toLowerCase();
      return trimmed.startsWith('favorite:') ||
          trimmed.startsWith('archived:');
    });
    return lines.join('\n').trim();
  }

  String? _cleanNote(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final sanitized = _sanitize(raw)?.trim() ?? '';
    if (sanitized.isEmpty) return null;
    final stripped = _stripFavoriteArchived(sanitized).trim();
    return stripped.isEmpty ? null : stripped;
  }

  String _humanizeFieldType(String type) {
    switch (type) {
      case 'phone':
        return 'Phone';
      case 'numeric':
        return 'Number';
      case 'date':
        return 'Date';
      case 'text':
        return 'Note';
      default:
        // Title-case the type as a last resort.
        return type.isEmpty
            ? 'Field'
            : type[0].toUpperCase() + type.substring(1);
    }
  }

  /// Accepts either a full `otpauth://...` URI or a bare Base32 secret. Bare
  /// secrets are wrapped into a canonical otpauth URI using the item title as
  /// the account label.
  String? _normalizeTotp(String? value, String accountLabel) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toLowerCase().startsWith('otpauth://')) return trimmed;
    final account = Uri.encodeComponent(
        accountLabel.trim().isEmpty ? 'Enpass' : accountLabel.trim());
    return 'otpauth://totp/$account?secret=$trimmed';
  }

  String? _firstUri(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final comma = value.indexOf(',');
    if (comma > 0) return value.substring(0, comma).trim();
    return value.trim();
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

  /// Record-aware CSV tokenizer that respects quoted multi-line values — the
  /// trailing favorite/archived block in Enpass CSV exports routinely spans
  /// two physical lines, and a line-based parser would shred those records.
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
