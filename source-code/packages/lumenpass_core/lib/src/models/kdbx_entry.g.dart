// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'kdbx_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$KdbxEntryImpl _$$KdbxEntryImplFromJson(Map<String, dynamic> json) =>
    _$KdbxEntryImpl(
      uuid: json['uuid'] as String,
      groupUuid: json['groupUuid'] as String,
      title: json['title'] as String,
      username: json['username'] as String?,
      url: json['url'] as String?,
      notes: json['notes'] as String?,
      otpAuthUrl: json['otpAuthUrl'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const <String>[],
      fields: (json['fields'] as List<dynamic>?)
              ?.map((e) => EntryField.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <EntryField>[],
      faviconPngBase64: json['faviconPngBase64'] as String?,
    );

Map<String, dynamic> _$$KdbxEntryImplToJson(_$KdbxEntryImpl instance) =>
    <String, dynamic>{
      'uuid': instance.uuid,
      'groupUuid': instance.groupUuid,
      'title': instance.title,
      'username': instance.username,
      'url': instance.url,
      'notes': instance.notes,
      'otpAuthUrl': instance.otpAuthUrl,
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'tags': instance.tags,
      'fields': instance.fields,
      'faviconPngBase64': instance.faviconPngBase64,
    };
