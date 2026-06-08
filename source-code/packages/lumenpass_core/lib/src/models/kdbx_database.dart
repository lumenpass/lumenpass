import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kdbx/kdbx.dart' as native;

import 'kdbx_entry.dart';
import 'kdbx_group.dart';

part 'kdbx_database.freezed.dart';
part 'kdbx_database.g.dart';

/// Immutable snapshot of the currently opened KeePass database.
@freezed
class KdbxDatabase with _$KdbxDatabase {
  const factory KdbxDatabase({
    required String name,
    required String path,
    required KdbxGroup rootGroup,
    required DateTime openedAt,
    @Default(false) bool isDirty,
    @Default(0) int groupCount,
    @Default(0) int entryCount,
    @Default(<KdbxEntry>[]) List<KdbxEntry> entries,
  }) = _KdbxDatabase;

  factory KdbxDatabase.fromJson(Map<String, dynamic> json) =>
      _$KdbxDatabaseFromJson(json);

  factory KdbxDatabase.fromNative(
    native.KdbxFile source, {
    required String path,
    required DateTime openedAt,
  }) {
    final recycleBinUuid = source.body.meta.recycleBinUUID.get()?.toString();
    final rootGroup = KdbxGroup.fromNative(
      source.body.rootGroup,
      recycleBinUuid: recycleBinUuid,
    );
    final entries = rootGroup.flattenedEntries().toList(growable: false);

    return KdbxDatabase(
      name: source.body.meta.databaseName.get() ?? 'Lumenpass Vault',
      path: path,
      rootGroup: rootGroup,
      openedAt: openedAt,
      isDirty: source.isDirty,
      groupCount: source.body.rootGroup.getAllGroups().length,
      entryCount: entries.length,
      entries: entries,
    );
  }
}

