// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApiConfig _$ApiConfigFromJson(Map<String, dynamic> json) => ApiConfig(
  id: json['id'] as String,
  name: json['name'] as String,
  baseUrl: json['baseUrl'] as String,
  apiKeyRef: json['apiKeyRef'] as String,
  isDefault: json['isDefault'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$ApiConfigToJson(ApiConfig instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'baseUrl': instance.baseUrl,
  'apiKeyRef': instance.apiKeyRef,
  'isDefault': instance.isDefault,
  'createdAt': instance.createdAt.toIso8601String(),
};
