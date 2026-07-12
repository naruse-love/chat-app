// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system_prompt_template.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SystemPromptTemplate _$SystemPromptTemplateFromJson(
  Map<String, dynamic> json,
) => SystemPromptTemplate(
  id: json['id'] as String,
  title: json['title'] as String,
  content: json['content'] as String,
  description: json['description'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$SystemPromptTemplateToJson(
  SystemPromptTemplate instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'content': instance.content,
  'description': instance.description,
  'createdAt': instance.createdAt.toIso8601String(),
};
