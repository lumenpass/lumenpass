// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry_field.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$EntryFieldImpl _$$EntryFieldImplFromJson(Map<String, dynamic> json) =>
    _$EntryFieldImpl(
      key: json['key'] as String,
      value: json['value'] as String,
      isProtected: json['isProtected'] as bool? ?? false,
      isStandard: json['isStandard'] as bool? ?? false,
    );

Map<String, dynamic> _$$EntryFieldImplToJson(_$EntryFieldImpl instance) =>
    <String, dynamic>{
      'key': instance.key,
      'value': instance.value,
      'isProtected': instance.isProtected,
      'isStandard': instance.isStandard,
    };
