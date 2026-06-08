// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'kdbx_group.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

KdbxGroup _$KdbxGroupFromJson(Map<String, dynamic> json) {
  return _KdbxGroup.fromJson(json);
}

/// @nodoc
mixin _$KdbxGroup {
  String get uuid => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get notes => throw _privateConstructorUsedError;
  bool get isRecycleBin => throw _privateConstructorUsedError;
  List<KdbxGroup> get groups => throw _privateConstructorUsedError;
  List<KdbxEntry> get entries => throw _privateConstructorUsedError;

  /// Serializes this KdbxGroup to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of KdbxGroup
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $KdbxGroupCopyWith<KdbxGroup> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $KdbxGroupCopyWith<$Res> {
  factory $KdbxGroupCopyWith(KdbxGroup value, $Res Function(KdbxGroup) then) =
      _$KdbxGroupCopyWithImpl<$Res, KdbxGroup>;
  @useResult
  $Res call(
      {String uuid,
      String name,
      String notes,
      bool isRecycleBin,
      List<KdbxGroup> groups,
      List<KdbxEntry> entries});
}

/// @nodoc
class _$KdbxGroupCopyWithImpl<$Res, $Val extends KdbxGroup>
    implements $KdbxGroupCopyWith<$Res> {
  _$KdbxGroupCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of KdbxGroup
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uuid = null,
    Object? name = null,
    Object? notes = null,
    Object? isRecycleBin = null,
    Object? groups = null,
    Object? entries = null,
  }) {
    return _then(_value.copyWith(
      uuid: null == uuid
          ? _value.uuid
          : uuid // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      notes: null == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String,
      isRecycleBin: null == isRecycleBin
          ? _value.isRecycleBin
          : isRecycleBin // ignore: cast_nullable_to_non_nullable
              as bool,
      groups: null == groups
          ? _value.groups
          : groups // ignore: cast_nullable_to_non_nullable
              as List<KdbxGroup>,
      entries: null == entries
          ? _value.entries
          : entries // ignore: cast_nullable_to_non_nullable
              as List<KdbxEntry>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$KdbxGroupImplCopyWith<$Res>
    implements $KdbxGroupCopyWith<$Res> {
  factory _$$KdbxGroupImplCopyWith(
          _$KdbxGroupImpl value, $Res Function(_$KdbxGroupImpl) then) =
      __$$KdbxGroupImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String uuid,
      String name,
      String notes,
      bool isRecycleBin,
      List<KdbxGroup> groups,
      List<KdbxEntry> entries});
}

/// @nodoc
class __$$KdbxGroupImplCopyWithImpl<$Res>
    extends _$KdbxGroupCopyWithImpl<$Res, _$KdbxGroupImpl>
    implements _$$KdbxGroupImplCopyWith<$Res> {
  __$$KdbxGroupImplCopyWithImpl(
      _$KdbxGroupImpl _value, $Res Function(_$KdbxGroupImpl) _then)
      : super(_value, _then);

  /// Create a copy of KdbxGroup
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uuid = null,
    Object? name = null,
    Object? notes = null,
    Object? isRecycleBin = null,
    Object? groups = null,
    Object? entries = null,
  }) {
    return _then(_$KdbxGroupImpl(
      uuid: null == uuid
          ? _value.uuid
          : uuid // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      notes: null == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String,
      isRecycleBin: null == isRecycleBin
          ? _value.isRecycleBin
          : isRecycleBin // ignore: cast_nullable_to_non_nullable
              as bool,
      groups: null == groups
          ? _value._groups
          : groups // ignore: cast_nullable_to_non_nullable
              as List<KdbxGroup>,
      entries: null == entries
          ? _value._entries
          : entries // ignore: cast_nullable_to_non_nullable
              as List<KdbxEntry>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$KdbxGroupImpl extends _KdbxGroup {
  const _$KdbxGroupImpl(
      {required this.uuid,
      required this.name,
      this.notes = '',
      this.isRecycleBin = false,
      final List<KdbxGroup> groups = const <KdbxGroup>[],
      final List<KdbxEntry> entries = const <KdbxEntry>[]})
      : _groups = groups,
        _entries = entries,
        super._();

  factory _$KdbxGroupImpl.fromJson(Map<String, dynamic> json) =>
      _$$KdbxGroupImplFromJson(json);

  @override
  final String uuid;
  @override
  final String name;
  @override
  @JsonKey()
  final String notes;
  @override
  @JsonKey()
  final bool isRecycleBin;
  final List<KdbxGroup> _groups;
  @override
  @JsonKey()
  List<KdbxGroup> get groups {
    if (_groups is EqualUnmodifiableListView) return _groups;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_groups);
  }

  final List<KdbxEntry> _entries;
  @override
  @JsonKey()
  List<KdbxEntry> get entries {
    if (_entries is EqualUnmodifiableListView) return _entries;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_entries);
  }

  @override
  String toString() {
    return 'KdbxGroup(uuid: $uuid, name: $name, notes: $notes, isRecycleBin: $isRecycleBin, groups: $groups, entries: $entries)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$KdbxGroupImpl &&
            (identical(other.uuid, uuid) || other.uuid == uuid) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.isRecycleBin, isRecycleBin) ||
                other.isRecycleBin == isRecycleBin) &&
            const DeepCollectionEquality().equals(other._groups, _groups) &&
            const DeepCollectionEquality().equals(other._entries, _entries));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uuid,
      name,
      notes,
      isRecycleBin,
      const DeepCollectionEquality().hash(_groups),
      const DeepCollectionEquality().hash(_entries));

  /// Create a copy of KdbxGroup
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$KdbxGroupImplCopyWith<_$KdbxGroupImpl> get copyWith =>
      __$$KdbxGroupImplCopyWithImpl<_$KdbxGroupImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$KdbxGroupImplToJson(
      this,
    );
  }
}

abstract class _KdbxGroup extends KdbxGroup {
  const factory _KdbxGroup(
      {required final String uuid,
      required final String name,
      final String notes,
      final bool isRecycleBin,
      final List<KdbxGroup> groups,
      final List<KdbxEntry> entries}) = _$KdbxGroupImpl;
  const _KdbxGroup._() : super._();

  factory _KdbxGroup.fromJson(Map<String, dynamic> json) =
      _$KdbxGroupImpl.fromJson;

  @override
  String get uuid;
  @override
  String get name;
  @override
  String get notes;
  @override
  bool get isRecycleBin;
  @override
  List<KdbxGroup> get groups;
  @override
  List<KdbxEntry> get entries;

  /// Create a copy of KdbxGroup
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$KdbxGroupImplCopyWith<_$KdbxGroupImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
