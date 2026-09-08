import 'package:lumenpass_core/lumenpass_core.dart';

class CustomImportField {
  const CustomImportField({
    required this.name,
    required this.value,
    this.isProtected = false,
  });

  final String name;
  final String value;
  final bool isProtected;
}

class ImportParsedItem {
  ImportParsedItem({
    required this.title,
    this.username,
    this.password,
    this.url,
    this.otpAuthUrl,
    this.notes,
    List<String>? tags,
    List<CustomImportField>? customFields,
  })  : tags = List<String>.unmodifiable(tags ?? const <String>[]),
        customFields = List<CustomImportField>.unmodifiable(
            customFields ?? const <CustomImportField>[]);

  final String title;
  final String? username;
  final String? password;
  final String? url;
  final String? otpAuthUrl;
  final String? notes;
  final List<String> tags;
  final List<CustomImportField> customFields;

  List<EntryField> toEntryFields() {
    final fields = <EntryField>[
      EntryField(
        key: AppKdbxFieldKeys.title,
        value: title.trim(),
        isStandard: true,
      ),
    ];

    if (username != null && username!.trim().isNotEmpty) {
      fields.add(EntryField(
        key: AppKdbxFieldKeys.userName,
        value: username!.trim(),
        isStandard: true,
      ));
    }

    if (password != null && password!.isNotEmpty) {
      fields.add(EntryField(
        key: AppKdbxFieldKeys.password,
        value: password!,
        isProtected: true,
        isStandard: true,
      ));
    }

    if (url != null && url!.trim().isNotEmpty) {
      fields.add(EntryField(
        key: AppKdbxFieldKeys.url,
        value: url!.trim(),
        isStandard: true,
      ));
    }

    if (otpAuthUrl != null && otpAuthUrl!.trim().isNotEmpty) {
      fields.add(EntryField(
        key: AppKdbxFieldKeys.otpAuth,
        value: otpAuthUrl!.trim(),
        isProtected: true,
        isStandard: true,
      ));
    }

    for (final cf in customFields) {
      if (cf.name.trim().isEmpty || cf.value.isEmpty) continue;
      fields.add(EntryField(
        key: cf.name.trim(),
        value: cf.value,
        isProtected: cf.isProtected,
      ));
    }

    return fields;
  }

  @override
  String toString() => 'ImportParsedItem(title=$title)';
}
