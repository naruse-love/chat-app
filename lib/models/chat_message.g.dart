// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => ChatMessage(
  id: json['id'] as String,
  conversationId: json['conversationId'] as String,
  role: json['role'] as String,
  content: json['content'] as String,
  reasoningContent: json['reasoningContent'] as String?,
  imagePath: json['imagePath'] as String?,
  toolCalls: (json['toolCalls'] as List<dynamic>?)
      ?.map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
      .toList(),
  toolCallId: json['toolCallId'] as String?,
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$ChatMessageToJson(ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'conversationId': instance.conversationId,
      'role': instance.role,
      'content': instance.content,
      'reasoningContent': instance.reasoningContent,
      'imagePath': instance.imagePath,
      'toolCalls': instance.toolCalls?.map((e) => e.toJson()).toList(),
      'toolCallId': instance.toolCallId,
      'timestamp': instance.timestamp.toIso8601String(),
    };
