// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_call.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ToolCall _$ToolCallFromJson(Map<String, dynamic> json) => ToolCall(
  id: json['id'] as String,
  type: json['type'] as String,
  functionName: json['functionName'] as String,
  arguments: json['arguments'] as String,
);

Map<String, dynamic> _$ToolCallToJson(ToolCall instance) => <String, dynamic>{
  'id': instance.id,
  'type': instance.type,
  'functionName': instance.functionName,
  'arguments': instance.arguments,
};
