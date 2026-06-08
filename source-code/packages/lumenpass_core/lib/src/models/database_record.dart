import 'dart:convert';

/// Represents a registered KeePass database known to LumenPass.
class DatabaseRecord {
  const DatabaseRecord({
    required this.id,
    required this.nickname,
    required this.databasePath,
    required this.addedAt,
    this.bookmark,
    this.isDefaultStartup = false,
    this.storageType = 'local',
    this.cloudFileId,
    this.cloudFileName,
    this.lastOpenedAt,
  });

  final String id;
  final String nickname;
  final String databasePath;
  final DateTime addedAt;

  /// Base64-encoded macOS security-scoped bookmark data.
  /// Allows re-accessing the file across app restarts in a sandboxed environment.
  final String? bookmark;
  final bool isDefaultStartup;

  /// Storage provider: 'local', 'googleDrive', 'dropbox', 'oneDrive',
  /// 'webdav', or 'sftp'.
  final String storageType;

  /// Provider-specific remote file identifier used to re-fetch the file if the
  /// local cache under [databasePath] is missing.
  final String? cloudFileId;

  /// Original cloud filename (e.g. `MyVault.kdbx`) — paired with [cloudFileId]
  /// for a stable local cache path.
  final String? cloudFileName;

  /// The last time this vault was successfully opened. Used to sort vaults
  /// by recency of use. `null` for vaults that have never been opened.
  final DateTime? lastOpenedAt;

  DatabaseRecord copyWith({
    String? id,
    String? nickname,
    String? databasePath,
    DateTime? addedAt,
    String? bookmark,
    bool? isDefaultStartup,
    String? storageType,
    String? cloudFileId,
    String? cloudFileName,
    DateTime? lastOpenedAt,
  }) {
    return DatabaseRecord(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      databasePath: databasePath ?? this.databasePath,
      addedAt: addedAt ?? this.addedAt,
      bookmark: bookmark ?? this.bookmark,
      isDefaultStartup: isDefaultStartup ?? this.isDefaultStartup,
      storageType: storageType ?? this.storageType,
      cloudFileId: cloudFileId ?? this.cloudFileId,
      cloudFileName: cloudFileName ?? this.cloudFileName,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'databasePath': databasePath,
        'addedAt': addedAt.toIso8601String(),
        'isDefaultStartup': isDefaultStartup,
        'storageType': storageType,
        if (bookmark != null && bookmark!.isNotEmpty) 'bookmark': bookmark,
        if (cloudFileId != null && cloudFileId!.isNotEmpty)
          'cloudFileId': cloudFileId,
        if (cloudFileName != null && cloudFileName!.isNotEmpty)
          'cloudFileName': cloudFileName,
        if (lastOpenedAt != null)
          'lastOpenedAt': lastOpenedAt!.toIso8601String(),
      };

  factory DatabaseRecord.fromJson(Map<String, dynamic> json) => DatabaseRecord(
        id: json['id'] as String,
        nickname: json['nickname'] as String,
        databasePath: json['databasePath'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
        bookmark: json['bookmark'] as String?,
        isDefaultStartup: json['isDefaultStartup'] as bool? ?? false,
        storageType: json['storageType'] as String? ?? 'local',
        cloudFileId: json['cloudFileId'] as String?,
        cloudFileName: json['cloudFileName'] as String?,
        lastOpenedAt: json['lastOpenedAt'] != null
            ? DateTime.parse(json['lastOpenedAt'] as String)
            : null,
      );

  static List<DatabaseRecord> listFromJson(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => DatabaseRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<DatabaseRecord> records) =>
      jsonEncode(records.map((r) => r.toJson()).toList());
}
