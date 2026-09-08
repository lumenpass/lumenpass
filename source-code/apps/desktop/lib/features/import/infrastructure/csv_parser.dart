import 'dart:convert';

import '../domain/import_parsed_item.dart';

class CsvParser {
  const CsvParser();

  List<ImportParsedItem> parse(String csvContent) {
    final lines = _splitLines(csvContent);
    if (lines.isEmpty) {
      throw FormatException('CSV file is empty');
    }

    final headerLine = lines.first;
    final headers = _parseCsvLine(headerLine);
    final columnIndices = _mapColumnIndices(headers);

    if (!columnIndices.containsKey('title')) {
      throw FormatException(
          'CSV missing required column. Expected "Title" in: $headers');
    }

    final items = <ImportParsedItem>[];
    final errors = <String>[];

    for (var i = 1; i < lines.length; i++) {
      try {
        final values = _parseCsvLine(lines[i]);

        final title = _getValue(values, columnIndices['title']);
        final url = _getValue(values, columnIndices['url']);
        final username = _getValue(values, columnIndices['username']);
        final password = _getValue(values, columnIndices['password']);
        final otpAuth =
            _getOtpValue(values, columnIndices['otp']);
        final tagsRaw = _getValue(values, columnIndices['tags']);
        final notes = _getValue(values, columnIndices['notes']);

        final item = ImportParsedItem(
          title: title ?? '',
          url: url,
          username: username,
          password: password,
          otpAuthUrl: otpAuth,
          notes: notes,
          tags: _parseTags(tagsRaw),
        );

        item.storeSourceField('csv_row', i.toString());
        item.storeSourceField('title_raw', title ?? '');
        item.storeSourceField('username_raw', username ?? '');
        item.storeSourceField('password_raw', password ?? '');
        item.storeSourceField('url_raw', url ?? '');
        item.storeSourceField('otpAuth_raw', otpAuth ?? '');
        item.storeSourceField('notes_raw', notes ?? '');
        item.storeSourceField('tags_raw', tagsRaw ?? '');

        if (title == null || title.trim().isEmpty) {
          item.addError('Missing title in row ${i + 1}');
        }

        items.add(item);
      } on FormatException catch (e) {
        errors.add('Row ${i + 1}: ${e.message}');
      }
    }

    if (items.isEmpty && errors.isNotEmpty) {
      throw FormatException(
          'Failed to parse any rows: ${errors.take(5).join("; ")}');
    }

    return items;
  }

  List<String> _splitLines(String content) {
    if (content.isEmpty) return const <String>[];
    return const LineSplitter().convert(content);
  }

  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    var i = 0;
    final len = line.length;

    while (i < len) {
      final ch = line[i];

      if (ch == '"') {
        i++;
        final buffer = StringBuffer();
        while (i < len) {
          if (line[i] == '"') {
            if (i + 1 < len && line[i + 1] == '"') {
              buffer.write('"');
              i += 2;
            } else {
              i++;
              break;
            }
          } else {
            buffer.write(line[i]);
            i++;
          }
        }
        fields.add(buffer.toString());

        if (i < len) {
          if (line[i] == ',') {
            i++;
          }
        }
      } else if (ch == ',') {
        fields.add('');
        i++;
      } else {
        var end = i;
        while (end < len && line[end] != ',' && line[end] != '"') {
          end++;
        }
        fields.add(line.substring(i, end));
        i = end;
        if (i < len && line[i] == ',') {
          i++;
        }
      }
    }

    if (line.isNotEmpty && line[line.length - 1] == ',') {
      fields.add('');
    }

    return fields;
  }

  Map<String, int> _mapColumnIndices(List<String> headers) {
    final indices = <String, int>{};

    for (var i = 0; i < headers.length; i++) {
      final normalized = headers[i].trim().toLowerCase();
      switch (normalized) {
        case 'title':
          indices['title'] = i;
        case 'url':
        case 'urls':
          indices['url'] = i;
        case 'username':
          indices['username'] = i;
        case 'password':
          indices['password'] = i;
        case 'otpauth':
        case 'otp':
          indices['otp'] = i;
        case 'tags':
          indices['tags'] = i;
        case 'notes':
          indices['notes'] = i;
      }
    }

    return indices;
  }

  String? _getValue(List<String> values, int? index) {
    if (index == null || index >= values.length) return null;
    final value = values[index].trim();
    return value.isEmpty ? null : value;
  }

  String? _getOtpValue(List<String> values, int? index) {
    if (index == null || index >= values.length) return null;
    final value = values[index].trim();
    if (value.isEmpty) return null;
    if (value.toLowerCase().startsWith('otpauth://')) {
      return value;
    }
    return null;
  }

  List<String> _parseTags(String? tagsRaw) {
    if (tagsRaw == null || tagsRaw.trim().isEmpty) return const <String>[];

    return tagsRaw
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }
}
