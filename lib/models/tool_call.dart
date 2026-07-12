import 'package:json_annotation/json_annotation.dart';

part 'tool_call.g.dart';

@JsonSerializable()
class ToolCall {
  final String id;
  final String type;            // "function"
  final String functionName;
  final String arguments;       // JSON 字符串

  ToolCall({
    required this.id,
    required this.type,
    required this.functionName,
    required this.arguments,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('function') && json['function'] is Map) {
      final functionMap = json['function'] as Map<String, dynamic>;
      return ToolCall(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'function',
        functionName: functionMap['name'] as String? ?? '',
        arguments: functionMap['arguments'] as String? ?? '',
      );
    }
    return _$ToolCallFromJson(json);
  }

  Map<String, dynamic> toJson() => _$ToolCallToJson(this);

  Map<String, dynamic> toOpenAiJson() {
    return {
      'id': id,
      'type': type,
      'function': {
        'name': functionName,
        'arguments': arguments,
      }
    };
  }
}
