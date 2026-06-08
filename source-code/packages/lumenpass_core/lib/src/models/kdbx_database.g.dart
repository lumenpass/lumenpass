// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kdbx_database.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$KdbxDatabaseImpl _$$KdbxDatabaseImplFromJson(Map<String, dynamic> json) =>
    _$KdbxDatabaseImpl(
      name: json['name'] as String,
      path: json['path'] as String,
      rootGroup: KdbxGroup.fromJson(json['rootGroup'] as Map<String, dynamic>),
      openedAt: DateTime.parse(json['openedAt'] as String),
      isDirty: json['isDirty'] as bool? ?? false,
      groupCount: (json['groupCount'] as num?)?.toInt() ?? 0,
      entryCount: (json['entryCount'] as num?)?.toInt() ?? 0,
      entries: (json['entries'] as List<dynamic>?)
              ?.map((e) => KdbxEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <KdbxEntry>[],
    );

Map<String, dynamic> _$$KdbxDatabaseImplToJson(_$KdbxDatabaseImpl instance) =>
    <String, dynamic>{
      'name': instance.name,
      'path': instance.path,
      'rootGroup': instance.rootGroup,
      'openedAt': instance.openedAt.toIso8601String(),
      'isDirty': instance.isDirty,
      'groupCount': instance.groupCount,
      'entryCount': instance.entryCount,
      'entries': instance.entries,
    };
