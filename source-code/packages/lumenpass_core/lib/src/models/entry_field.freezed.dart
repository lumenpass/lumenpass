// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'entry_field.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

EntryField _$EntryFieldFromJson(Map<String, dynamic> json) {
  return _EntryField.fromJson(json);
}

/// @nodoc
mixin _$EntryField {
  String get key => throw _privateConstructorUsedError;
  String get value => throw _privateConstructorUsedError;
  bool get isProtected => throw _privateConstructorUsedError;
  bool get isStandard => throw _privateConstructorUsedError;

  /// Serializes this EntryField to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of EntryField
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EntryFieldCopyWith<EntryField> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EntryFieldCopyWith<$Res> {
  factory $EntryFieldCopyWith(
          EntryField value, $Res Function(EntryField) then) =
      _$EntryFieldCopyWithImpl<$Res, EntryField>;
  @useResult
  $Res call({String key, String value, bool isProtected, bool isStandard});
}

/// @nodoc
class _$EntryFieldCopyWithImpl<$Res, $Val extends EntryField>
    implements $EntryFieldCopyWith<$Res> {
  _$EntryFieldCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EntryField
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? key = null,
    Object? value = null,
    Object? isProtected = null,
    Object? isStandard = null,
  }) {
    return _then(_value.copyWith(
      key: null == key
          ? _value.key
          : key // ignore: cast_nullable_to_non_nullable
              as String,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as String,
      isProtected: null == isProtected
          ? _value.isProtected
          : isProtected // ignore: cast_nullable_to_non_nullable
              as bool,
      isStandard: null == isStandard
          ? _value.isStandard
          : isStandard // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$EntryFieldImplCopyWith<$Res>
    implements $EntryFieldCopyWith<$Res> {
  factory _$$EntryFieldImplCopyWith(
          _$EntryFieldImpl value, $Res Function(_$EntryFieldImpl) then) =
      __$$EntryFieldImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String key, String value, bool isProtected, bool isStandard});
}

/// @nodoc
class __$$EntryFieldImplCopyWithImpl<$Res>
    extends _$EntryFieldCopyWithImpl<$Res, _$EntryFieldImpl>
    implements _$$EntryFieldImplCopyWith<$Res> {
  __$$EntryFieldImplCopyWithImpl(
      _$EntryFieldImpl _value, $Res Function(_$EntryFieldImpl) _then)
      : super(_value, _then);

  /// Create a copy of EntryField
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? key = null,
    Object? value = null,
    Object? isProtected = null,
    Object? isStandard = null,
  }) {
    return _then(_$EntryFieldImpl(
      key: null == key
          ? _value.key
          : key // ignore: cast_nullable_to_non_nullable
              as String,
      value: null == value
          ? _value.value
          : value // ignore: cast_nullable_to_non_nullable
              as String,
      isProtected: null == isProtected
          ? _value.isProtected
          : isProtected // ignore: cast_nullable_to_non_nullable
              as bool,
      isStandard: null == isStandard
          ? _value.isStandard
          : isStandard // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$EntryFieldImpl implements _EntryField {
  const _$EntryFieldImpl(
      {required this.key,
      required this.value,
      this.isProtected = false,
      this.isStandard = false});

  factory _$EntryFieldImpl.fromJson(Map<String, dynamic> json) =>
      _$$EntryFieldImplFromJson(json);

  @override
  final String key;
  @override
  final String value;
  @override
  @JsonKey()
  final bool isProtected;
  @override
  @JsonKey()
  final bool isStandard;

  @override
  String toString() {
    return 'EntryField(key: $key, value: $value, isProtected: $isProtected, isStandard: $isStandard)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EntryFieldImpl &&
            (identical(other.key, key) || other.key == key) &&
            (identical(other.value, value) || other.value == value) &&
            (identical(other.isProtected, isProtected) ||
                other.isProtected == isProtected) &&
            (identical(other.isStandard, isStandard) ||
                other.isStandard == isStandard));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, key, value, isProtected, isStandard);

  /// Create a copy of EntryField
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EntryFieldImplCopyWith<_$EntryFieldImpl> get copyWith =>
      __$$EntryFieldImplCopyWithImpl<_$EntryFieldImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$EntryFieldImplToJson(
      this,
    );
  }
}

abstract class _EntryField implements EntryField {
  const factory _EntryField(
      {required final String key,
      required final String value,
      final bool isProtected,
      final bool isStandard}) = _$EntryFieldImpl;

  factory _EntryField.fromJson(Map<String, dynamic> json) =
      _$EntryFieldImpl.fromJson;

  @override
  String get key;
  @override
  String get value;
  @override
  bool get isProtected;
  @override
  bool get isStandard;

  /// Create a copy of EntryField
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EntryFieldImplCopyWith<_$EntryFieldImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
