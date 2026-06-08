import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kdbx/kdbx.dart' as native;

import '../constants/kdbx_field_keys.dart';

part 'entry_field.freezed.dart';
part 'entry_field.g.dart';

/// Immutable representation of a single entry field from a KeePass record.
@freezed
class EntryField with _$EntryField {
  const factory EntryField({
    required String key,
    required String value,
    @Default(false) bool isProtected,
    @Default(false) bool isStandard,
  }) = _EntryField;

  factory EntryField.fromJson(Map<String, dynamic> json) =>
      _$EntryFieldFromJson(json);

  factory EntryField.fromNative(
    MapEntry<native.KdbxKey, native.StringValue?> source,
  ) {
    final key = source.key.key;
    final value = source.value?.getText() ?? '';

    return EntryField(
      key: key,
      value: value,
      isProtected: source.value is native.ProtectedValue ||
          AppKdbxFieldKeys.isProtectedKey(key),
      isStandard: AppKdbxFieldKeys.isStandardKey(key),
    );
  }
}

