import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../domain/import_parsed_item.dart';

class OnePuxParser {
  const OnePuxParser();

  Future<List<ImportParsedItem>> parse(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FormatException('File not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? dataFile;
    for (final file in archive) {
      if (file.name == 'export.data') {
        dataFile = file;
        break;
      }
    }

    if (dataFile == null) {
      throw const FormatException(
          'Invalid 1PUX file: missing export.data inside archive');
    }

    final jsonContent = utf8.decode(dataFile.content as List<int>);
    final jsonData = jsonDecode(jsonContent) as Map<String, dynamic>;
    return _parseJson(jsonData);
  }

  List<ImportParsedItem> _parseJson(Map<String, dynamic> jsonData) {
    final accounts = jsonData['accounts'] as List<dynamic>?;
    if (accounts == null || accounts.isEmpty) {
      throw const FormatException(
          'Invalid 1PUX file: no accounts found in export data');
    }

    final items = <ImportParsedItem>[];

    for (final account in accounts) {
      final accountMap = account as Map<String, dynamic>;
      final vaults = accountMap['vaults'] as List<dynamic>?;
      if (vaults == null) continue;

      for (final vault in vaults) {
        final vaultMap = vault as Map<String, dynamic>;
        final vaultItems = vaultMap['items'] as List<dynamic>?;
        if (vaultItems == null) continue;

        for (final item in vaultItems) {
          final itemMap = item as Map<String, dynamic>;
          final parsed = _parseItem(itemMap);
          if (parsed != null) {
            items.add(parsed);
          }
        }
      }
    }

    if (items.isEmpty) {
      throw const FormatException(
          'No login items found in 1PUX export file');
    }

    return items;
  }

  ImportParsedItem? _parseItem(Map<String, dynamic> itemMap) {
    final categoryUuid = itemMap['categoryUuid'] as String? ?? '';

    if (!categoryUuid.contains('001')) {
      return null;
    }

    final overview = itemMap['overview'] as Map<String, dynamic>? ?? {};
    final details = itemMap['details'] as Map<String, dynamic>? ?? {};

    final title = (overview['title'] as String?) ?? '';
    final url = _extractUrl(overview);
    final tags = _extractTags(overview);
    final subtitle = (overview['subtitle'] as String?) ?? '';
    final notesRaw = details['notesPlain'] as String?;

    String? username;
    String? password;
    String? otpAuthUrl;
    final customFields = <CustomImportField>[];

    final loginFields = details['loginFields'] as List<dynamic>?;
    if (loginFields != null) {
      for (final lf in loginFields) {
        final lfMap = lf as Map<String, dynamic>;
        final designation = lfMap['designation'] as String? ?? '';
        final name = lfMap['name'] as String? ?? '';
        final value = lfMap['value'] as String? ?? '';
        final fieldType = lfMap['fieldType'] as String? ?? '';

        if (designation == 'username' || name == 'username') {
          username = value;
        } else if (designation == 'password' || name == 'password') {
          password = value;
        } else if (designation == 'TOTP' || fieldType == 'O') {
          otpAuthUrl = value;
        } else if (name.isNotEmpty && value.isNotEmpty &&
            fieldType != 'T') {
          customFields.add(CustomImportField(
            name: name,
            value: value,
            isProtected: fieldType == 'P',
          ));
        }
      }
    }

    if (username == null || username.isEmpty) {
      final subtitleLower = subtitle.toLowerCase();
      if (subtitle.isNotEmpty &&
          !subtitleLower.contains('signs in with') &&
          !subtitleLower.contains('sign in with') &&
          !subtitleLower.contains('google') &&
          !subtitleLower.contains('facebook')) {
        username = subtitle;
      }
    }

    final sections = details['sections'] as List<dynamic>?;
    if (sections != null) {
      for (final section in sections) {
        final sectionMap = section as Map<String, dynamic>;
        final sectionTitle = sectionMap['title'] as String? ?? '';
        final fields = sectionMap['fields'] as List<dynamic>?;
        if (fields == null) continue;

        for (final field in fields) {
          final fieldMap = field as Map<String, dynamic>;
          final fieldTitle = fieldMap['title'] as String? ?? '';
          final valueMap = fieldMap['value'] as Map<String, dynamic>? ?? {};

          if (valueMap.isEmpty) continue;

          for (final entry in valueMap.entries) {
            final v = entry.value;
            if (v == null || v.toString().isEmpty) continue;

            final fTitle = fieldTitle.toLowerCase();
            if (fTitle == 'username' && (username == null || username.isEmpty)) {
              username = v.toString();
            } else if (fTitle == 'password' &&
                (password == null || password.isEmpty)) {
              password = v.toString();
            } else if (fTitle == 'notes' && notesRaw == null) {
              // Already handled notesPlain above
            } else if (fTitle.contains('one-time') || fTitle == 'totp') {
              otpAuthUrl ??= v.toString();
            } else if (fieldTitle.isNotEmpty) {
              customFields.add(CustomImportField(
                name: '${sectionTitle.isNotEmpty ? "$sectionTitle: " : ""}$fieldTitle',
                value: v.toString(),
                isProtected: entry.key == 'concealed',
              ));
            }
          }
        }
      }
    }

    final item = ImportParsedItem(
      title: title,
      username: username,
      password: password,
      url: url,
      otpAuthUrl: otpAuthUrl,
      notes: notesRaw,
      tags: tags,
      customFields: customFields,
    );

    item.storeSourceField('subtitle', subtitle);

    if (title.isEmpty) {
      final fallbackTitle = subtitle.isNotEmpty ? subtitle : 'Untitled';
      item.addError('Missing title. Using fallback: "$fallbackTitle"');
    }

    return item;
  }

  String? _extractUrl(Map<String, dynamic> overview) {
    final url = overview['url'] as String?;
    if (url != null && url.isNotEmpty) {
      final comma = url.indexOf(',');
      if (comma > 0) {
        return url.substring(0, comma);
      }
      return url;
    }

    final urls = overview['urls'] as List<dynamic>?;
    if (urls != null && urls.isNotEmpty) {
      final first = urls.first as Map<String, dynamic>?;
      return first?['url'] as String?;
    }

    return null;
  }

  List<String> _extractTags(Map<String, dynamic> overview) {
    final tags = overview['tags'] as List<dynamic>?;
    if (tags == null || tags.isEmpty) return const <String>[];
    return tags.map((t) => t.toString().trim()).where((t) => t.isNotEmpty).toList(growable: false);
  }
}
