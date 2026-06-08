// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kdbx_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$KdbxGroupImpl _$$KdbxGroupImplFromJson(Map<String, dynamic> json) =>
    _$KdbxGroupImpl(
      uuid: json['uuid'] as String,
      name: json['name'] as String,
      notes: json['notes'] as String? ?? '',
      isRecycleBin: json['isRecycleBin'] as bool? ?? false,
      groups: (json['groups'] as List<dynamic>?)
              ?.map((e) => KdbxGroup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <KdbxGroup>[],
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => KdbxEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <KdbxEntry>[],
    );

Map<String, dynamic> _$$KdbxGroupImplToJson(_$KdbxGroupImpl instance) =>
    <String, dynamic>{
      'uuid': instance.uuid,
      'name': instance.name,
      'notes': instance.notes,
      'isRecycleBin': instance.isRecycleBin,
      'groups': instance.groups,
      'entries': instance.entries,
    };
