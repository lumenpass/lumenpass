import 'dart:io';
import 'dart:typed_data';

import 'package:kdbx/kdbx.dart' as native;
import 'package:kdbx/src/kdbx_header.dart' as native_header;

import '../constants/kdbx_field_keys.dart';
import '../errors/app_exception.dart';
import '../models/entry_attachment.dart';
import '../models/entry_binary_attachment.dart';
import '../models/entry_field.dart';
import '../models/kdbx_database.dart';
import '../models/kdbx_entry.dart';
import '../services/totp_service.dart';

/// Contract for all KeePass database access used by the app.
abstract class KdbxRepository {
  KdbxDatabase? get currentDatabase;
  bool get hasOpenDatabase;
  String? get rootGroupUuid;

  Future<KdbxDatabase> openDatabase({
    required String databasePath,
    String? password,
    Uint8List? keyFileBytes,
  });

  void closeDatabase();

  Future<KdbxDatabase> createDatabase({
    required String databasePath,
    required String databaseName,
    String? password,
    Uint8List? keyFileBytes,
    native.KdbxVersion? version,
  });

  Future<KdbxDatabase> saveDatabase({String? outputPath});

  Future<String> createGroup({
    required String parentGroupUuid,
    required String name,
    String? notes,
  });

  Future<void> updateGroup({
    required String groupUuid,
    required String name,
    String? notes,
  });

  Future<void> deleteGroup(String groupUuid);
  Future<void> moveEntryToGroup({
    required String entryUuid,
    required String targetGroupUuid,
  });

  Future<List<KdbxEntry>> searchEntries({String query = ''});

  Future<KdbxEntry> createEntry({
    required String groupUuid,
    required List<EntryField> fields,
    String? notes,
    List<String> tags = const <String>[],
    List<EntryAttachment> attachments = const <EntryAttachment>[],
  });

  Future<KdbxEntry> updateEntry({
    required String entryUuid,
    required List<EntryField> fields,
    String? notes,
    List<String>? tags,
    List<EntryAttachment>? attachments,
  });

  Future<void> deleteEntry(String entryUuid);

  /// Writes the cached favicon payload (base64 PNG, or the sentinel
  /// [AppKdbxFieldKeys.faviconFailedSentinel]) into the entry's hidden
  /// custom field. Call [saveDatabase] afterwards to persist.
  Future<void> setEntryFaviconCache({
    required String entryUuid,
    required String payload,
  });

  Future<List<KdbxEntry>> entriesWithInvalidCreatedAt({required DateTime now});

  Future<void> setEntryCreatedAt({
    required String entryUuid,
    required DateTime createdAt,
  });

  Future<void> restoreEntry(String entryUuid);

  Future<void> permanentlyDeleteEntry(String entryUuid);

  Future<String?> getTOTP(String entryUuid);

  Future<List<EntryBinaryAttachment>> getEntryAttachments(String entryUuid);
}

/// Concrete repository backed directly by the `kdbx` package.
class KdbxRepositoryImpl implements KdbxRepository {
  KdbxRepositoryImpl({
    required native.KdbxFormat format,
    required TOTPService totpService,
  })  : _format = format,
        _totpService = totpService;

  final native.KdbxFormat _format;
  final TOTPService _totpService;

  native.KdbxFile? _activeFile;
  String? _activePath;
  DateTime? _openedAt;
  List<_IndexedEntry>? _entryIndexCache;

  @override
  KdbxDatabase? get currentDatabase {
    final file = _activeFile;
    final path = _activePath;
    final openedAt = _openedAt;

    if (file == null || path == null || openedAt == null) {
      return null;
    }

    return KdbxDatabase.fromNative(
      file,
      path: path,
      openedAt: openedAt,
    );
  }

  @override
  bool get hasOpenDatabase => _activeFile != null;

  @override
  String? get rootGroupUuid => _activeFile?.body.rootGroup.uuid.toString();

  @override
  Future<KdbxDatabase> openDatabase({
    required String databasePath,
    String? password,
    Uint8List? keyFileBytes,
  }) async {
    final file = File(databasePath);
    if (!await file.exists()) {
      throw const VaultAccessException(
          'The selected database file was not found.');
    }

    final bytes = await file.readAsBytes();
    final credentials = _buildCredentials(
      password: password,
      keyFileBytes: keyFileBytes,
    );

    try {
      final opened = await _format.read(bytes, credentials);
      _activeFile?.dispose();
      _activeFile = opened;
      _activePath = databasePath;
      _openedAt = DateTime.now();
      _invalidateCaches();
      return currentDatabase!;
    } on native.KdbxInvalidKeyException {
      throw const VaultAccessException(
        'The password or key file did not unlock this database.',
      );
    } on native.KdbxException catch (error) {
      throw VaultAccessException('Unable to open the database: $error');
    } on FormatException catch (error) {
      throw VaultAccessException(
          'The selected key file is invalid: ${error.message}');
    }
  }

  @override
  void closeDatabase() {
    _activeFile?.dispose();
    _activeFile = null;
    _activePath = null;
    _openedAt = null;
    _invalidateCaches();
  }

  @override
  Future<KdbxDatabase> createDatabase({
    required String databasePath,
    required String databaseName,
    String? password,
    Uint8List? keyFileBytes,
    native.KdbxVersion? version,
  }) async {
    final passwordValue = password != null && password.isNotEmpty
        ? native.ProtectedValue.fromString(password)
        : null;

    if (passwordValue == null && keyFileBytes == null) {
      throw const VaultAccessException(
        'Enter a password, choose a key file, or provide both.',
      );
    }

    final credentials = native.Credentials.composite(
      passwordValue,
      keyFileBytes,
    );

    final header = (version != null && version.major == 3)
        ? native_header.KdbxHeader.createV3()
        : null;

    try {
      final newFile = _format.create(credentials, databaseName, header: header);
      final bytes = await newFile.save();
      await File(databasePath).writeAsBytes(bytes, flush: true);

      _activeFile?.dispose();
      _activeFile = newFile;
      _activePath = databasePath;
      _openedAt = DateTime.now();
      _invalidateCaches();
      return currentDatabase!;
    } on native.KdbxException catch (error) {
      throw VaultAccessException('Unable to create the database: $error');
    }
  }

  @override
  Future<KdbxDatabase> saveDatabase({String? outputPath}) async {
    final activeFile = _requireFile();
    final targetPath = outputPath ?? _activePath;
    if (targetPath == null || targetPath.isEmpty) {
      throw const VaultStateException(
          'No output path is available for saving.');
    }

    final payload = await activeFile.save();
    await File(targetPath).writeAsBytes(payload, flush: true);
    _activePath = targetPath;
    _invalidateCaches();
    return currentDatabase!;
  }

  @override
  Future<String> createGroup({
    required String parentGroupUuid,
    required String name,
    String? notes,
  }) async {
    final file = _requireFile();
    final parentGroup = _findGroup(parentGroupUuid);
    final group = file.createGroup(
      parent: parentGroup,
      name: name.trim(),
    );

    final trimmedNotes = notes?.trim();
    if (trimmedNotes != null && trimmedNotes.isNotEmpty) {
      group.notes.set(trimmedNotes);
    }

    _invalidateCaches();
    return group.uuid.toString();
  }

  @override
  Future<void> updateGroup({
    required String groupUuid,
    required String name,
    String? notes,
  }) async {
    final group = _findGroup(groupUuid);
    group.name.set(name.trim());
    final trimmedNotes = notes?.trim() ?? '';
    group.notes.set(trimmedNotes);
    _invalidateCaches();
  }

  @override
  Future<void> deleteGroup(String groupUuid) async {
    final group = _findGroup(groupUuid);
    _requireFile().deleteGroup(group);
    _invalidateCaches();
  }

  @override
  Future<void> moveEntryToGroup({
    required String entryUuid,
    required String targetGroupUuid,
  }) async {
    final file = _requireFile();
    final entry = _findEntry(entryUuid);
    final targetGroup = _findGroup(targetGroupUuid);
    file.move(entry, targetGroup);
    _invalidateCaches();
  }

  @override
  Future<List<KdbxEntry>> searchEntries({String query = ''}) async {
    final entries = _getIndexedEntries();

    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return entries.map((entry) => entry.entry).toList(growable: false);
    }

    return entries
        .where((entry) => entry.searchableText.contains(normalized))
        .map((entry) => entry.entry)
        .toList(growable: false);
  }

  @override
  Future<KdbxEntry> createEntry({
    required String groupUuid,
    required List<EntryField> fields,
    String? notes,
    List<String> tags = const <String>[],
    List<EntryAttachment> attachments = const <EntryAttachment>[],
  }) async {
    final file = _requireFile();
    final group = _findGroup(groupUuid);
    final entry = native.KdbxEntry.create(file, group);
    group.addEntry(entry);
    _applyFields(entry, fields: fields, notes: notes, tags: tags);
    _applyAttachments(entry, attachments: attachments);
    _invalidateCaches();
    return KdbxEntry.fromNative(entry);
  }

  @override
  Future<KdbxEntry> updateEntry({
    required String entryUuid,
    required List<EntryField> fields,
    String? notes,
    List<String>? tags,
    List<EntryAttachment>? attachments,
  }) async {
    final entry = _findEntry(entryUuid);
    final existingKeys = entry.stringEntries.map((item) => item.key).toList();
    for (final key in existingKeys) {
      entry.removeString(key);
    }
    if (attachments != null) {
      final existingBinaryKeys = entry.binaryEntries
          .map((binaryEntry) => binaryEntry.key)
          .toList(growable: false);
      for (final key in existingBinaryKeys) {
        entry.removeBinary(key);
      }
    }

    _applyFields(entry, fields: fields, notes: notes, tags: tags ?? const []);
    if (attachments != null) {
      _applyAttachments(entry, attachments: attachments);
    }
    entry.times.lastModificationTime.set(DateTime.now().toUtc());
    _invalidateCaches();
    return KdbxEntry.fromNative(entry);
  }

  @override
  Future<void> deleteEntry(String entryUuid) async {
    _requireFile().deleteEntry(_findEntry(entryUuid));
    _invalidateCaches();
  }

  @override
  Future<void> setEntryFaviconCache({
    required String entryUuid,
    required String payload,
  }) async {
    final entry = _findEntry(entryUuid);
    entry.setString(
      native.KdbxKey(AppKdbxFieldKeys.faviconPngBase64),
      native.PlainValue(payload),
    );
    _invalidateCaches();
  }

  @override
  Future<List<KdbxEntry>> entriesWithInvalidCreatedAt({
    required DateTime now,
  }) async {
    bool isInvalid(DateTime? value) {
      if (value == null) return true;
      return value.isAfter(now) || value.year <= 1970;
    }

    return _requireFile()
        .body
        .rootGroup
        .getAllEntries()
        .where((entry) => !entry.isInRecycleBin())
        .where((entry) {
          final createdAt = entry.times.creationTime.get();
          final updatedAt = entry.times.lastModificationTime.get();
          return isInvalid(createdAt) || isInvalid(updatedAt);
        })
        .map(KdbxEntry.fromNative)
        .toList(growable: false);
  }

  @override
  Future<void> setEntryCreatedAt({
    required String entryUuid,
    required DateTime createdAt,
  }) async {
    final entry = _findEntry(entryUuid);
    final utcCreatedAt = createdAt.toUtc();
    final now = DateTime.now().toUtc();
    final currentUpdatedAt = entry.times.lastModificationTime.get();

    final isUpdatedAtInvalid = currentUpdatedAt == null ||
        currentUpdatedAt.isAfter(now) ||
        currentUpdatedAt.year <= 1970;

    entry.times.creationTime.set(utcCreatedAt);
    if (isUpdatedAtInvalid) {
      entry.times.lastModificationTime.set(utcCreatedAt);
    } else {
      entry.times.lastModificationTime.set(now);
    }
    _invalidateCaches();
  }

  @override
  Future<void> restoreEntry(String entryUuid) async {
    final file = _requireFile();
    file.move(_findEntry(entryUuid), file.body.rootGroup);
    _invalidateCaches();
  }

  @override
  Future<void> permanentlyDeleteEntry(String entryUuid) async {
    _requireFile().deletePermanently(_findEntry(entryUuid));
    _invalidateCaches();
  }

  @override
  Future<String?> getTOTP(String entryUuid) async {
    final entry = _findEntry(entryUuid);
    // Match the fallback used by KdbxEntry.otpAuthUrl: some imported entries
    // store the secret under the lowercase 'otp' field instead of the standard
    // KdbxKeyCommon.OTP key. Without this fallback, getTOTP returns null for
    // entries that the search/sidebar correctly detect as having a TOTP.
    final otpUri = entry.getString(native.KdbxKeyCommon.OTP)?.getText() ??
        entry.getString(native.KdbxKey('otp'))?.getText();
    return _totpService.generateCode(otpUri);
  }

  @override
  Future<List<EntryBinaryAttachment>> getEntryAttachments(
      String entryUuid) async {
    final entry = _findEntry(entryUuid);
    const imageExtensions = <String>{
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'heic',
    };

    return entry.binaryEntries.map(
      (binaryEntry) {
        final name = binaryEntry.key.key;
        final extension =
            name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final bytes = binaryEntry.value.value;
        return EntryBinaryAttachment(
          name: name,
          size: bytes.length,
          isImage: imageExtensions.contains(extension),
          bytes: bytes,
        );
      },
    ).toList(growable: false);
  }

  native.Credentials _buildCredentials({
    String? password,
    Uint8List? keyFileBytes,
  }) {
    final passwordValue = password != null && password.isNotEmpty
        ? native.ProtectedValue.fromString(password)
        : null;

    if (passwordValue == null && keyFileBytes == null) {
      throw const VaultAccessException(
        'Enter a password, choose a key file, or provide both.',
      );
    }

    return native.Credentials.composite(passwordValue, keyFileBytes);
  }

  native.KdbxFile _requireFile() {
    final file = _activeFile;
    if (file == null) {
      throw const VaultStateException(
          'Open a database before using vault actions.');
    }
    return file;
  }

  List<_IndexedEntry> _getIndexedEntries() {
    final cached = _entryIndexCache;
    if (cached != null) {
      return cached;
    }

    final built = _requireFile()
        .body
        .rootGroup
        .getAllEntries()
        .where((entry) => !entry.isInRecycleBin())
        .map((entry) => _IndexedEntry.fromEntry(KdbxEntry.fromNative(entry)))
        .toList(growable: false);
    _entryIndexCache = built;
    return built;
  }

  void _invalidateCaches() {
    _entryIndexCache = null;
  }

  native.KdbxGroup _findGroup(String groupUuid) {
    return _requireFile().body.rootGroup.getAllGroups().firstWhere(
          (group) => group.uuid.toString() == groupUuid,
          orElse: () => throw const VaultStateException(
              'The requested group was not found.'),
        );
  }

  native.KdbxEntry _findEntry(String entryUuid) {
    return _requireFile().body.rootGroup.getAllEntries().firstWhere(
          (entry) => entry.uuid.toString() == entryUuid,
          orElse: () => throw const VaultStateException(
              'The requested entry was not found.'),
        );
  }

  void _applyFields(
    native.KdbxEntry entry, {
    required List<EntryField> fields,
    String? notes,
    required List<String> tags,
  }) {
    for (final field in fields.where((field) => field.value.isNotEmpty)) {
      final value =
          field.isProtected || AppKdbxFieldKeys.isProtectedKey(field.key)
              ? native.ProtectedValue.fromString(field.value)
              : native.PlainValue(field.value);

      entry.setString(native.KdbxKey(field.key), value);
    }

    if (notes != null && notes.isNotEmpty) {
      entry.setString(
        native.KdbxKey(AppKdbxFieldKeys.notes),
        native.PlainValue(notes),
      );
    }

    if (tags.isNotEmpty) {
      entry.tags.set(tags.join(';'));
    }
  }

  void _applyAttachments(
    native.KdbxEntry entry, {
    required List<EntryAttachment> attachments,
  }) {
    for (final attachment in attachments) {
      final bytes = attachment.bytes ??
          (() {
            final filePath = attachment.filePath;
            if (filePath == null) {
              return null;
            }
            final file = File(filePath);
            if (!file.existsSync()) {
              return null;
            }
            return file.readAsBytesSync();
          })();
      if (bytes == null) {
        continue;
      }
      entry.createBinary(
        isProtected: attachment.isProtected,
        name: attachment.fileName,
        bytes: bytes,
      );
    }
  }
}

class _IndexedEntry {
  const _IndexedEntry({
    required this.entry,
    required this.searchableText,
  });

  final KdbxEntry entry;
  final String searchableText;

  factory _IndexedEntry.fromEntry(KdbxEntry entry) {
    final searchableParts = <String>[
      entry.title,
      entry.username ?? '',
      entry.url ?? '',
      entry.notes ?? '',
      entry.tags.join(' '),
      ...entry.fields
          .where((field) =>
              !field.isProtected && !AppKdbxFieldKeys.isProtectedKey(field.key))
          .map((field) => '${field.key} ${field.value}'),
    ];

    return _IndexedEntry(
      entry: entry,
      searchableText: searchableParts.join('\n').toLowerCase(),
    );
  }
}
