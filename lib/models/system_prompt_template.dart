import 'package:json_annotation/json_annotation.dart';

part 'system_prompt_template.g.dart';

@JsonSerializable()
class SystemPromptTemplate {
  final String id;
  final String title;
  final String content;
  final String? description;
  final DateTime createdAt;

  SystemPromptTemplate({
    required this.id,
    required this.title,
    required this.content,
    this.description,
    required this.createdAt,
  });

  factory SystemPromptTemplate.fromJson(Map<String, dynamic> json) => _$SystemPromptTemplateFromJson(json);
  Map<String, dynamic> toJson() => _$SystemPromptTemplateToJson(this);

  SystemPromptTemplate copyWith({
    String? id,
    String? title,
    String? content,
    String? description,
    DateTime? createdAt,
  }) {
    return SystemPromptTemplate(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
