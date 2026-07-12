import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool_call.dart';

// Helper for stack-safe deep equality comparison to avoid recursion stack overflow
bool isDeeplyEqual(dynamic a, dynamic b) {
  final stack = [<dynamic>[a, b]];
  while (stack.isNotEmpty) {
    final pair = stack.removeLast();
    final x = pair[0];
    final y = pair[1];
    if (identical(x, y)) continue;
    if (x is Map && y is Map) {
      if (x.length != y.length) return false;
      for (final key in x.keys) {
        if (!y.containsKey(key)) return false;
        stack.add(<dynamic>[x[key], y[key]]);
      }
    } else if (x is List && y is List) {
      if (x.length != y.length) return false;
      for (int i = 0; i < x.length; i++) {
        stack.add(<dynamic>[x[i], y[i]]);
      }
    } else {
      if (x != y) return false;
    }
  }
  return true;
}

void main() {
  group('ChatMessage Stress Tests', () {
    test('Serialization and deserialization with extremely large reasoning_content (10MB)', () {
      // Generate a 10MB string with diverse characters (alphanumeric, unicode, emojis, control characters)
      final buffer = StringBuffer();
      const baseString = "ChatMessage reasoning content stress test. Unicode: \u03B1\u03B2\u03B3. Emoji: 🚀🔥💡. Control: \n\t\\\"'\r\n";
      const repetitions = (10 * 1024 * 1024) ~/ baseString.length;
      
      for (int i = 0; i < repetitions; i++) {
        buffer.write(baseString);
        // Add dynamic variation
        buffer.write("[$i]");
      }
      
      final largeReasoningContent = buffer.toString();
      
      final message = ChatMessage(
        id: 'msg_stress_test_123',
        conversationId: 'conv_stress_test_456',
        role: 'assistant',
        content: 'Short content here.',
        reasoningContent: largeReasoningContent,
        timestamp: DateTime.utc(2026, 7, 11, 12, 0, 0),
      );

      // Serialize to Map
      final stopwatchEncode = Stopwatch()..start();
      final jsonMap = message.toJson();
      
      // Convert to JSON String
      final jsonString = jsonEncode(jsonMap);
      stopwatchEncode.stop();
      print('10MB ChatMessage JSON encoding took ${stopwatchEncode.elapsedMilliseconds} ms'); // ignore: avoid_print

      // Verify the size of the serialized string
      expect(jsonString.length, greaterThan(10 * 1024 * 1024));

      // Deserialize from JSON String
      final stopwatchDecode = Stopwatch()..start();
      final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final deserializedMessage = ChatMessage.fromJson(decodedMap);
      stopwatchDecode.stop();
      print('10MB ChatMessage JSON decoding took ${stopwatchDecode.elapsedMilliseconds} ms'); // ignore: avoid_print

      // Assertions
      expect(deserializedMessage.id, message.id);
      expect(deserializedMessage.conversationId, message.conversationId);
      expect(deserializedMessage.role, message.role);
      expect(deserializedMessage.content, message.content);
      expect(deserializedMessage.reasoningContent, largeReasoningContent);
      expect(deserializedMessage.timestamp, message.timestamp);
      expect(deserializedMessage.imagePath, isNull);
      expect(deserializedMessage.toolCalls, isNull);
      expect(deserializedMessage.toolCallId, isNull);
    });
  });

  group('ToolCall Stress Tests', () {
    // Helper to generate deeply nested JSON Map
    Map<String, dynamic> generateNestedMap(int depth) {
      if (depth <= 1) {
        return {'value': 'leaf_node'};
      }
      return {'nest': generateNestedMap(depth - 1)};
    }

    test('Serialization and deserialization of ToolCall with deeply nested JSON arguments (500 levels)', () {
      final nestedMap = generateNestedMap(500);
      final argumentsJsonString = jsonEncode(nestedMap);

      final toolCall = ToolCall(
        id: 'call_deep_123',
        type: 'function',
        functionName: 'deeply_nested_func',
        arguments: argumentsJsonString,
      );

      // 1. Test standard serialization
      final standardJsonMap = toolCall.toJson();
      final standardJsonStr = jsonEncode(standardJsonMap);
      
      final decodedStandard = jsonDecode(standardJsonStr) as Map<String, dynamic>;
      final deserializedStandard = ToolCall.fromJson(decodedStandard);

      expect(deserializedStandard.id, toolCall.id);
      expect(deserializedStandard.type, toolCall.type);
      expect(deserializedStandard.functionName, toolCall.functionName);
      expect(deserializedStandard.arguments, toolCall.arguments);

      // Verify arguments deserialization works back to the identical map
      final parsedArguments = jsonDecode(deserializedStandard.arguments) as Map<String, dynamic>;
      expect(isDeeplyEqual(parsedArguments, nestedMap), isTrue);

      // 2. Test OpenAI format serialization
      final openAiJsonMap = toolCall.toOpenAiJson();
      final openAiJsonStr = jsonEncode(openAiJsonMap);

      final decodedOpenAi = jsonDecode(openAiJsonStr) as Map<String, dynamic>;
      final deserializedOpenAi = ToolCall.fromJson(decodedOpenAi);

      expect(deserializedOpenAi.id, toolCall.id);
      expect(deserializedOpenAi.type, toolCall.type);
      expect(deserializedOpenAi.functionName, toolCall.functionName);
      expect(deserializedOpenAi.arguments, toolCall.arguments);
    });

    test('Serialization and deserialization of ToolCall with massive wide JSON arguments (50,000 keys)', () {
      final wideMap = <String, dynamic>{};
      for (int i = 0; i < 50000; i++) {
        wideMap['key_$i'] = 'value_$i';
      }
      final argumentsJsonString = jsonEncode(wideMap);

      final toolCall = ToolCall(
        id: 'call_wide_123',
        type: 'function',
        functionName: 'wide_arguments_func',
        arguments: argumentsJsonString,
      );

      // Test standard serialization
      final stopwatchEncode = Stopwatch()..start();
      final jsonMap = toolCall.toJson();
      final jsonString = jsonEncode(jsonMap);
      stopwatchEncode.stop();
      print('50,000 key ToolCall JSON encoding took ${stopwatchEncode.elapsedMilliseconds} ms'); // ignore: avoid_print

      final stopwatchDecode = Stopwatch()..start();
      final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final deserialized = ToolCall.fromJson(decodedMap);
      stopwatchDecode.stop();
      print('50,000 key ToolCall JSON decoding took ${stopwatchDecode.elapsedMilliseconds} ms'); // ignore: avoid_print

      expect(deserialized.id, toolCall.id);
      expect(deserialized.type, toolCall.type);
      expect(deserialized.functionName, toolCall.functionName);
      expect(deserialized.arguments, toolCall.arguments);

      // Verify the map content
      final parsedArguments = jsonDecode(deserialized.arguments) as Map<String, dynamic>;
      expect(parsedArguments.length, 50000);
      expect(parsedArguments['key_0'], 'value_0');
      expect(parsedArguments['key_49999'], 'value_49999');
    });

    test('ToolCall with invalid JSON string in arguments does not crash serialization', () {
      const invalidJsonString = "{invalid json: 'no quotes',}";
      final toolCall = ToolCall(
        id: 'call_invalid_123',
        type: 'function',
        functionName: 'invalid_json_func',
        arguments: invalidJsonString,
      );

      final jsonMap = toolCall.toJson();
      final jsonString = jsonEncode(jsonMap);

      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final deserialized = ToolCall.fromJson(decoded);

      expect(deserialized.arguments, invalidJsonString);
    });
  });

  group('Combined Stress Test: ChatMessage with both Large reasoning_content and Massive ToolCalls', () {
    test('Should handle complex message with multiple massive ToolCalls and large reasoning_content', () {
      final buffer = StringBuffer();
      const baseString = "Large reasoning block... ";
      const repetitions = (2 * 1024 * 1024) ~/ baseString.length; // 2MB reasoning
      for (int i = 0; i < repetitions; i++) {
        buffer.write(baseString);
      }
      final largeReasoning = buffer.toString();

      // Generate a massive nested arguments map for a tool call
      final nestedMap = <String, dynamic>{};
      var current = nestedMap;
      for (int i = 0; i < 200; i++) {
        current['step_$i'] = <String, dynamic>{};
        current = current['step_$i'] as Map<String, dynamic>;
      }
      current['terminal_value'] = 'verified';
      final nestedArgsString = jsonEncode(nestedMap);

      final toolCall1 = ToolCall(
        id: 'call_1',
        type: 'function',
        functionName: 'nested_params_func',
        arguments: nestedArgsString,
      );

      final toolCall2 = ToolCall(
        id: 'call_2',
        type: 'function',
        functionName: 'plain_func',
        arguments: '{"simple": true}',
      );

      final message = ChatMessage(
        id: 'msg_combined_123',
        conversationId: 'conv_combined_456',
        role: 'assistant',
        content: 'Here is the combined stress test message.',
        reasoningContent: largeReasoning,
        toolCalls: [toolCall1, toolCall2],
        timestamp: DateTime.utc(2026, 7, 11, 13, 0, 0),
      );

      final jsonMap = message.toJson();
      final jsonStr = jsonEncode(jsonMap);

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deserialized = ChatMessage.fromJson(decoded);

      expect(deserialized.id, message.id);
      expect(deserialized.reasoningContent, largeReasoning);
      expect(deserialized.toolCalls, hasLength(2));
      
      final deserializedToolCall1 = deserialized.toolCalls![0];
      expect(deserializedToolCall1.id, 'call_1');
      expect(deserializedToolCall1.arguments, nestedArgsString);
      
      final parsedArgs1 = jsonDecode(deserializedToolCall1.arguments) as Map<String, dynamic>;
      expect(isDeeplyEqual(parsedArgs1, nestedMap), isTrue);
    });
  });
}
