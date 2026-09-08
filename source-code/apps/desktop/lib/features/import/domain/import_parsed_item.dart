import '../../../core/models/entry_field.dart';
import '../../../core/constants/kdbx_field_keys.dart';

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
    String? itemType,
    List<String>? tags,
    List<CustomImportField>? customFields,
    this.isForced = false,
  })  : itemType = itemType ??
            _defaultItemType(
              username: username,
              password: password,
              url: url,
              otpAuthUrl: otpAuthUrl,
              notes: notes,
            ),
        tags = List<String>.unmodifiable(tags ?? const <String>[]),
        customFields = List<CustomImportField>.unmodifiable(
            customFields ?? const <CustomImportField>[]),
        validationErrors = <String>[],
        _sourceFields = <String, String>{};

  final String title;
  final String? username;
  final String? password;
  final String? url;
  final String? otpAuthUrl;
  final String? notes;

  /// The vault item type id (matches `VaultItemType.id`, e.g. `login`,
  /// `secure-note`). Pre-assigned from the parsed item's shape and
  /// overridable by the user in the import preview.
  final String itemType;

  final List<String> tags;
  final List<CustomImportField> customFields;
  final List<String> validationErrors;

  final Map<String, String> _sourceFields;
  final bool isForced;

  /// Derives a sensible default item type from a parsed entry's shape.
  /// Entries that carry no login-shaped data (username/password/url/otp) but
  /// do have body text are pre-assigned as secure notes; everything else
  /// defaults to a login.
  static String _defaultItemType({
    String? username,
    String? password,
    String? url,
    String? otpAuthUrl,
    String? notes,
  }) {
    final hasLoginShape = (username != null && username.trim().isNotEmpty) ||
        (password != null && password.trim().isNotEmpty) ||
        (url != null && url.trim().isNotEmpty) ||
        (otpAuthUrl != null && otpAuthUrl.trim().isNotEmpty);
    if (!hasLoginShape && notes != null && notes.trim().isNotEmpty) {
      return 'secure-note';
    }
    return 'login';
  }

  bool get hasErrors => !isForced && validationErrors.isNotEmpty;
  bool get isReady => !hasErrors;
  bool get hasUsername => username != null && username!.trim().isNotEmpty;
  bool get hasPassword => password != null && password!.trim().isNotEmpty;
  bool get hasUrl => url != null && url!.trim().isNotEmpty;

  void addError(String error) {
    validationErrors.add(error);
  }

  void addErrors(Iterable<String> errors) {
    validationErrors.addAll(errors);
  }

  void storeSourceField(String key, String value) {
    _sourceFields[key] = value;
  }

  String? getSourceField(String key) => _sourceFields[key];

  void validate() {
    validationErrors.clear();

    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      addError('Title is required');
    }

    // A title is the only hard requirement. Logins typically carry a
    // username/password, while secure notes, cards, identities and SSH keys
    // store their data in notes or custom fields — and an empty-bodied note
    // that the user deliberately created is still a valid item to import.
  }

  ImportParsedItem copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? otpAuthUrl,
    String? notes,
    String? itemType,
    List<String>? tags,
    List<CustomImportField>? customFields,
    bool? isForced,
  }) {
    return ImportParsedItem(
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      otpAuthUrl: otpAuthUrl ?? this.otpAuthUrl,
      notes: notes ?? this.notes,
      itemType: itemType ?? this.itemType,
      tags: tags ?? this.tags,
      customFields: customFields ?? this.customFields,
      isForced: isForced ?? this.isForced,
    );
  }

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
  String toString() => 'ImportParsedItem(title=$title, ready=$isReady)';
}
