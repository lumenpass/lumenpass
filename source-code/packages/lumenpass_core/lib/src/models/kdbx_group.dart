import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kdbx/kdbx.dart' as native;

import 'kdbx_entry.dart';

part 'kdbx_group.freezed.dart';
part 'kdbx_group.g.dart';

/// Immutable tree node representing a KeePass group and its descendants.
@freezed
class KdbxGroup with _$KdbxGroup {
  const factory KdbxGroup({
    required String uuid,
    required String name,
    @Default('') String notes,
    @Default(false) bool isRecycleBin,
    @Default(<KdbxGroup>[]) List<KdbxGroup> groups,
    @Default(<KdbxEntry>[]) List<KdbxEntry> entries,
  }) = _KdbxGroup;

  const KdbxGroup._();

  factory KdbxGroup.fromJson(Map<String, dynamic> json) =>
      _$KdbxGroupFromJson(json);

  factory KdbxGroup.fromNative(
    native.KdbxGroup source, {
    String? recycleBinUuid,
  }) {
    return KdbxGroup(
      uuid: source.uuid.toString(),
      name: source.name.get() ?? 'Untitled Group',
      notes: source.notes.get() ?? '',
      isRecycleBin:
          recycleBinUuid != null && recycleBinUuid == source.uuid.toString(),
      groups: source.groups
          .map(
            (group) => KdbxGroup.fromNative(
              group,
              recycleBinUuid: recycleBinUuid,
            ),
          )
          .toList(growable: false),
      entries: source.entries
          .map(KdbxEntry.fromNative)
          .toList(growable: false),
    );
  }

  Iterable<KdbxEntry> flattenedEntries() sync* {
    yield* entries;
    for (final group in groups) {
      yield* group.flattenedEntries();
    }
  }

  Iterable<KdbxGroup> flattenedGroups() sync* {
    yield this;
    for (final group in groups) {
      yield* group.flattenedGroups();
    }
  }
}

extension KdbxGroupVisibleSubtree on KdbxGroup {
  /// Entries in this subtree, excluding the recycle bin group (desktop/mobile vault lists).
  Iterable<KdbxEntry> subtreeEntriesExcludingRecycleBin() sync* {
    if (isRecycleBin) {
      return;
    }
    yield* entries;
    for (final child in groups) {
      yield* child.subtreeEntriesExcludingRecycleBin();
    }
  }
}

