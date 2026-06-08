// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'kdbx_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

KdbxEntry _$KdbxEntryFromJson(Map<String, dynamic> json) {
  return _KdbxEntry.fromJson(json);
}

/// @nodoc
mixin _$KdbxEntry {
  String get uuid => throw _privateConstructorUsedError;
  String get groupUuid => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  String? get username => throw _privateConstructorUsedError;
  String? get url => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  String? get otpAuthUrl => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  List<String> get tags => throw _privateConstructorUsedError;
  List<EntryField> get fields => throw _privateConstructorUsedError;

  /// Base64-encoded PNG bytes cached in a hidden custom field on the
  /// entry. `null` ⇒ not attempted yet. [AppKdbxFieldKeys.faviconFailedSentinel]
  /// ⇒ we tried and the host has no usable favicon; skip future fetches.
  /// Any other value ⇒ a usable base64 PNG payload ready for
  /// `Image.memory` display with no network hop.
  String? get faviconPngBase64 => throw _privateConstructorUsedError;

  /// Serializes this KdbxEntry to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of KdbxEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $KdbxEntryCopyWith<KdbxEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $KdbxEntryCopyWith<$Res> {
  factory $KdbxEntryCopyWith(KdbxEntry value, $Res Function(KdbxEntry) then) =
      _$KdbxEntryCopyWithImpl<$Res, KdbxEntry>;
  @useResult
  $Res call(
      {String uuid,
      String groupUuid,
      String title,
      String? username,
      String? url,
      String? notes,
      String? otpAuthUrl,
      DateTime? createdAt,
      DateTime? updatedAt,
      List<String> tags,
      List<EntryField> fields,
      String? faviconPngBase64});
}

/// @nodoc
class _$KdbxEntryCopyWithImpl<$Res, $Val extends KdbxEntry>
    implements $KdbxEntryCopyWith<$Res> {
  _$KdbxEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of KdbxEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uuid = null,
    Object? groupUuid = null,
    Object? title = null,
    Object? username = freezed,
    Object? url = freezed,
    Object? notes = freezed,
    Object? otpAuthUrl = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? tags = null,
    Object? fields = null,
    Object? faviconPngBase64 = freezed,
  }) {
    return _then(_value.copyWith(
      uuid: null == uuid
          ? _value.uuid
          : uuid // ignore: cast_nullable_to_non_nullable
              as String,
      groupUuid: null == groupUuid
          ? _value.groupUuid
          : groupUuid // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      username: freezed == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String?,
      url: freezed == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      otpAuthUrl: freezed == otpAuthUrl
          ? _value.otpAuthUrl
          : otpAuthUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      tags: null == tags
          ? _value.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      fields: null == fields
          ? _value.fields
          : fields // ignore: cast_nullable_to_non_nullable
              as List<EntryField>,
      faviconPngBase64: freezed == faviconPngBase64
          ? _value.faviconPngBase64
          : faviconPngBase64 // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$KdbxEntryImplCopyWith<$Res>
    implements $KdbxEntryCopyWith<$Res> {
  factory _$$KdbxEntryImplCopyWith(
          _$KdbxEntryImpl value, $Res Function(_$KdbxEntryImpl) then) =
      __$$KdbxEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uuid,
      String groupUuid,
      String title,
      String? username,
      String? url,
      String? notes,
      String? otpAuthUrl,
      DateTime? createdAt,
      DateTime? updatedAt,
      List<String> tags,
      List<EntryField> fields,
      String? faviconPngBase64});
}

/// @nodoc
class __$$KdbxEntryImplCopyWithImpl<$Res>
    extends _$KdbxEntryCopyWithImpl<$Res, _$KdbxEntryImpl>
    implements _$$KdbxEntryImplCopyWith<$Res> {
  __$$KdbxEntryImplCopyWithImpl(
      _$KdbxEntryImpl _value, $Res Function(_$KdbxEntryImpl) _then)
      : super(_value, _then);

  /// Create a copy of KdbxEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uuid = null,
    Object? groupUuid = null,
    Object? title = null,
    Object? username = freezed,
    Object? url = freezed,
    Object? notes = freezed,
    Object? otpAuthUrl = freezed,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? tags = null,
    Object? fields = null,
    Object? faviconPngBase64 = freezed,
  }) {
    return _then(_$KdbxEntryImpl(
      uuid: null == uuid
          ? _value.uuid
          : uuid // ignore: cast_nullable_to_non_nullable
              as String,
      groupUuid: null == groupUuid
          ? _value.groupUuid
          : groupUuid // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      username: freezed == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String?,
      url: freezed == url
          ? _value.url
          : url // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      otpAuthUrl: freezed == otpAuthUrl
          ? _value.otpAuthUrl
          : otpAuthUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      tags: null == tags
          ? _value._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      fields: null == fields
          ? _value._fields
          : fields // ignore: cast_nullable_to_non_nullable
              as List<EntryField>,
      faviconPngBase64: freezed == faviconPngBase64
          ? _value.faviconPngBase64
          : faviconPngBase64 // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$KdbxEntryImpl extends _KdbxEntry {
  const _$KdbxEntryImpl(
      {required this.uuid,
      required this.groupUuid,
      required this.title,
      this.username,
      this.url,
      this.notes,
      this.otpAuthUrl,
      this.createdAt,
      this.updatedAt,
      final List<String> tags = const <String>[],
      final List<EntryField> fields = const <EntryField>[],
      this.faviconPngBase64})
      : _tags = tags,
        _fields = fields,
        super._();

  factory _$KdbxEntryImpl.fromJson(Map<String, dynamic> json) =>
      _$$KdbxEntryImplFromJson(json);

  @override
  final String uuid;
  @override
  final String groupUuid;
  @override
  final String title;
  @override
  final String? username;
  @override
  final String? url;
  @override
  final String? notes;
  @override
  final String? otpAuthUrl;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;
  final List<String> _tags;
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  final List<EntryField> _fields;
  @override
  @JsonKey()
  List<EntryField> get fields {
    if (_fields is EqualUnmodifiableListView) return _fields;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_fields);
  }

  /// Base64-encoded PNG bytes cached in a hidden custom field on the
  /// entry. `null` ⇒ not attempted yet. [AppKdbxFieldKeys.faviconFailedSentinel]
  /// ⇒ we tried and the host has no usable favicon; skip future fetches.
  /// Any other value ⇒ a usable base64 PNG payload ready for
  /// `Image.memory` display with no network hop.
  @override
  final String? faviconPngBase64;

  @override
  String toString() {
    return 'KdbxEntry(uuid: $uuid, groupUuid: $groupUuid, title: $title, username: $username, url: $url, notes: $notes, otpAuthUrl: $otpAuthUrl, createdAt: $createdAt, updatedAt: $updatedAt, tags: $tags, fields: $fields, faviconPngBase64: $faviconPngBase64)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$KdbxEntryImpl &&
            (identical(other.uuid, uuid) || other.uuid == uuid) &&
            (identical(other.groupUuid, groupUuid) ||
                other.groupUuid == groupUuid) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.username, username) ||
                other.username == username) &&
            (identical(other.url, url) || other.url == url) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.otpAuthUrl, otpAuthUrl) ||
                other.otpAuthUrl == otpAuthUrl) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            const DeepCollectionEquality().equals(other._fields, _fields) &&
            (identical(other.faviconPngBase64, faviconPngBase64) ||
                other.faviconPngBase64 == faviconPngBase64));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uuid,
      groupUuid,
      title,
      username,
      url,
      notes,
      otpAuthUrl,
      createdAt,
      updatedAt,
      const DeepCollectionEquality().hash(_tags),
      const DeepCollectionEquality().hash(_fields),
      faviconPngBase64);

  /// Create a copy of KdbxEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$KdbxEntryImplCopyWith<_$KdbxEntryImpl> get copyWith =>
      __$$KdbxEntryImplCopyWithImpl<_$KdbxEntryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$KdbxEntryImplToJson(
      this,
    );
  }
}

abstract class _KdbxEntry extends KdbxEntry {
  const factory _KdbxEntry(
      {required final String uuid,
      required final String groupUuid,
      required final String title,
      final String? username,
      final String? url,
      final String? notes,
      final String? otpAuthUrl,
      final DateTime? createdAt,
      final DateTime? updatedAt,
      final List<String> tags,
      final List<EntryField> fields,
      final String? faviconPngBase64}) = _$KdbxEntryImpl;
  const _KdbxEntry._() : super._();

  factory _KdbxEntry.fromJson(Map<String, dynamic> json) =
      _$KdbxEntryImpl.fromJson;

  @override
  String get uuid;
  @override
  String get groupUuid;
  @override
  String get title;
  @override
  String? get username;
  @override
  String? get url;
  @override
  String? get notes;
  @override
  String? get otpAuthUrl;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;
  @override
  List<String> get tags;
  @override
  List<EntryField> get fields;

  /// Base64-encoded PNG bytes cached in a hidden custom field on the
  /// entry. `null` ⇒ not attempted yet. [AppKdbxFieldKeys.faviconFailedSentinel]
  /// ⇒ we tried and the host has no usable favicon; skip future fetches.
  /// Any other value ⇒ a usable base64 PNG payload ready for
  /// `Image.memory` display with no network hop.
  @override
  String? get faviconPngBase64;

  /// Create a copy of KdbxEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$KdbxEntryImplCopyWith<_$KdbxEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
