import 'package:json_annotation/json_annotation.dart';
import 'tool_call.dart';

part 'chat_message.g.dart';

@JsonSerializable(explicitToJson: true)
class ChatMessage {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final String? reasoningContent;
  final String? imagePath;
  final List<ToolCall>? toolCalls;
  final String? toolCallId;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.reasoningContent,
    this.imagePath,
    this.toolCalls,
    this.toolCallId,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);
  Map<String, dynamic> toJson() => _$ChatMessageToJson(this);

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? role,
    String? content,
    String? reasoningContent,
    String? imagePath,
    List<ToolCall>? toolCalls,
    String? toolCallId,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      imagePath: imagePath ?? this.imagePath,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
