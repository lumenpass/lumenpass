// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'kdbx_database.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

KdbxDatabase _$KdbxDatabaseFromJson(Map<String, dynamic> json) {
  return _KdbxDatabase.fromJson(json);
}

/// @nodoc
mixin _$KdbxDatabase {
  String get name => throw _privateConstructorUsedError;
  String get path => throw _privateConstructorUsedError;
  KdbxGroup get rootGroup => throw _privateConstructorUsedError;
  DateTime get openedAt => throw _privateConstructorUsedError;
  bool get isDirty => throw _privateConstructorUsedError;
  int get groupCount => throw _privateConstructorUsedError;
  int get entryCount => throw _privateConstructorUsedError;
  List<KdbxEntry> get entries => throw _privateConstructorUsedError;

  /// Serializes this KdbxDatabase to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of KdbxDatabase
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $KdbxDatabaseCopyWith<KdbxDatabase> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $KdbxDatabaseCopyWith<$Res> {
  factory $KdbxDatabaseCopyWith(
          KdbxDatabase value, $Res Function(KdbxDatabase) then) =
      _$KdbxDatabaseCopyWithImpl<$Res, KdbxDatabase>;
  @useResult
  $Res call(
      {String name,
      String path,
      KdbxGroup rootGroup,
      DateTime openedAt,
      bool isDirty,
      int groupCount,
      int entryCount,
      List<KdbxEntry> entries});

  $KdbxGroupCopyWith<$Res> get rootGroup;
}

/// @nodoc
class _$KdbxDatabaseCopyWithImpl<$Res, $Val extends KdbxDatabase>
    implements $KdbxDatabaseCopyWith<$Res> {
  _$KdbxDatabaseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of KdbxDatabase
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? path = null,
    Object? rootGroup = null,
    Object? openedAt = null,
    Object? isDirty = null,
    Object? groupCount = null,
    Object? entryCount = null,
    Object? entries = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      path: null == path
          ? _value.path
          : path // ignore: cast_nullable_to_non_nullable
              as String,
      rootGroup: null == rootGroup
          ? _value.rootGroup
          : rootGroup // ignore: cast_nullable_to_non_nullable
              as KdbxGroup,
      openedAt: null == openedAt
          ? _value.openedAt
          : openedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      isDirty: null == isDirty
          ? _value.isDirty
          : isDirty // ignore: cast_nullable_to_non_nullable
              as bool,
      groupCount: null == groupCount
          ? _value.groupCount
          : groupCount // ignore: cast_nullable_to_non_nullable
              as int,
      entryCount: null == entryCount
          ? _value.entryCount
          : entryCount // ignore: cast_nullable_to_non_nullable
              as int,
      entries: null == entries
          ? _value.entries
          : entries // ignore: cast_nullable_to_non_nullable
              as List<KdbxEntry>,
    ) as $Val);
  }

  /// Create a copy of KdbxDatabase
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $KdbxGroupCopyWith<$Res> get rootGroup {
    return $KdbxGroupCopyWith<$Res>(_value.rootGroup, (value) {
      return _then(_value.copyWith(rootGroup: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$KdbxDatabaseImplCopyWith<$Res>
    implements $KdbxDatabaseCopyWith<$Res> {
  factory _$$KdbxDatabaseImplCopyWith(
          _$KdbxDatabaseImpl value, $Res Function(_$KdbxDatabaseImpl) then) =
      __$$KdbxDatabaseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name,
      String path,
      KdbxGroup rootGroup,
      DateTime openedAt,
      bool isDirty,
      int groupCount,
      int entryCount,
      List<KdbxEntry> entries});

  @override
  $KdbxGroupCopyWith<$Res> get rootGroup;
}

/// @nodoc
class __$$KdbxDatabaseImplCopyWithImpl<$Res>
    extends _$KdbxDatabaseCopyWithImpl<$Res, _$KdbxDatabaseImpl>
    implements _$$KdbxDatabaseImplCopyWith<$Res> {
  __$$KdbxDatabaseImplCopyWithImpl(
      _$KdbxDatabaseImpl _value, $Res Function(_$KdbxDatabaseImpl) _then)
      : super(_value, _then);

  /// Create a copy of KdbxDatabase
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? path = null,
    Object? rootGroup = null,
    Object? openedAt = null,
    Object? isDirty = null,
    Object? groupCount = null,
    Object? entryCount = null,
    Object? entries = null,
  }) {
    return _then(_$KdbxDatabaseImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      path: null == path
          ? _value.path
          : path // ignore: cast_nullable_to_non_nullable
              as String,
      rootGroup: null == rootGroup
          ? _value.rootGroup
          : rootGroup // ignore: cast_nullable_to_non_nullable
              as KdbxGroup,
      openedAt: null == openedAt
          ? _value.openedAt
          : openedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      isDirty: null == isDirty
          ? _value.isDirty
          : isDirty // ignore: cast_nullable_to_non_nullable
              as bool,
      groupCount: null == groupCount
          ? _value.groupCount
          : groupCount // ignore: cast_nullable_to_non_nullable
              as int,
      entryCount: null == entryCount
          ? _value.entryCount
          : entryCount // ignore: cast_nullable_to_non_nullable
              as int,
      entries: null == entries
          ? _value._entries
          : entries // ignore: cast_nullable_to_non_nullable
              as List<KdbxEntry>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$KdbxDatabaseImpl implements _KdbxDatabase {
  const _$KdbxDatabaseImpl(
      {required this.name,
      required this.path,
      required this.rootGroup,
      required this.openedAt,
      this.isDirty = false,
      this.groupCount = 0,
      this.entryCount = 0,
      final List<KdbxEntry> entries = const <KdbxEntry>[]})
      : _entries = entries;

  factory _$KdbxDatabaseImpl.fromJson(Map<String, dynamic> json) =>
      _$$KdbxDatabaseImplFromJson(json);

  @override
  final String name;
  @override
  final String path;
  @override
  final KdbxGroup rootGroup;
  @override
  final DateTime openedAt;
  @override
  @JsonKey()
  final bool isDirty;
  @override
  @JsonKey()
  final int groupCount;
  @override
  @JsonKey()
  final int entryCount;
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
    return 'KdbxDatabase(name: $name, path: $path, rootGroup: $rootGroup, openedAt: $openedAt, isDirty: $isDirty, groupCount: $groupCount, entryCount: $entryCount, entries: $entries)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$KdbxDatabaseImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.path, path) || other.path == path) &&
            (identical(other.rootGroup, rootGroup) ||
                other.rootGroup == rootGroup) &&
            (identical(other.openedAt, openedAt) ||
                other.openedAt == openedAt) &&
            (identical(other.isDirty, isDirty) || other.isDirty == isDirty) &&
            (identical(other.groupCount, groupCount) ||
                other.groupCount == groupCount) &&
            (identical(other.entryCount, entryCount) ||
                other.entryCount == entryCount) &&
            const DeepCollectionEquality().equals(other._entries, _entries));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      name,
      path,
      rootGroup,
      openedAt,
      isDirty,
      groupCount,
      entryCount,
      const DeepCollectionEquality().hash(_entries));

  /// Create a copy of KdbxDatabase
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$KdbxDatabaseImplCopyWith<_$KdbxDatabaseImpl> get copyWith =>
      __$$KdbxDatabaseImplCopyWithImpl<_$KdbxDatabaseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$KdbxDatabaseImplToJson(
      this,
    );
  }
}

abstract class _KdbxDatabase implements KdbxDatabase {
  const factory _KdbxDatabase(
      {required final String name,
      required final String path,
      required final KdbxGroup rootGroup,
      required final DateTime openedAt,
      final bool isDirty,
      final int groupCount,
      final int entryCount,
      final List<KdbxEntry> entries}) = _$KdbxDatabaseImpl;

  factory _KdbxDatabase.fromJson(Map<String, dynamic> json) =
      _$KdbxDatabaseImpl.fromJson;

  @override
  String get name;
  @override
  String get path;
  @override
  KdbxGroup get rootGroup;
  @override
  DateTime get openedAt;
  @override
  bool get isDirty;
  @override
  int get groupCount;
  @override
  int get entryCount;
  @override
  List<KdbxEntry> get entries;

  /// Create a copy of KdbxDatabase
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$KdbxDatabaseImplCopyWith<_$KdbxDatabaseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
