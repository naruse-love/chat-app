import 'package:chat/models/mcp/mcp_tool_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('McpToolInfo Model Tests', () {
    test('Constructs, serializes and deserializes McpToolInfo with inputSchema', () {
      const tool = McpToolInfo(
        name: 'database_query',
        description: 'Execute SQL read query',
        inputSchema: {
          'type': 'object',
          'properties': {
            'sql': {'type': 'string', 'description': 'SQL query string'},
            'limit': {'type': 'integer', 'default': 100},
          },
          'required': ['sql'],
        },
      );

      expect(tool.name, 'database_query');
      expect(tool.description, 'Execute SQL read query');
      expect(tool.inputSchema['type'], 'object');
      expect(tool.inputSchema['properties']['sql']['type'], 'string');

      final json = tool.toJson();
      expect(json['name'], 'database_query');
      expect(json['description'], 'Execute SQL read query');

      final reconstructed = McpToolInfo.fromJson(json);
      expect(reconstructed.name, tool.name);
      expect(reconstructed.description, tool.description);
      expect(reconstructed.inputSchema, equals(tool.inputSchema));
      expect(reconstructed.toString(), contains('database_query'));
    });

    test('McpToolInfo equality and hashCode', () {
      const t1 = McpToolInfo(name: 'calc', description: 'Calculator');
      const t2 = McpToolInfo(name: 'calc', description: 'Calculator');
      const t3 = McpToolInfo(name: 'calc_v2', description: 'Calculator');

      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1, isNot(equals(t3)));
    });
  });

  group('McpContentBlock & McpToolCallResult Model Tests', () {
    test('McpContentBlock text block toDisplayText', () {
      const block = McpContentBlock(
        type: 'text',
        text: 'Sample plain output text',
      );

      expect(block.type, 'text');
      expect(block.text, 'Sample plain output text');
      expect(block.toDisplayText(), 'Sample plain output text');

      final json = block.toJson();
      expect(json['type'], 'text');
      expect(json['text'], 'Sample plain output text');

      final restored = McpContentBlock.fromJson(json);
      expect(restored.type, 'text');
      expect(restored.text, 'Sample plain output text');
    });

    test('McpContentBlock image block toDisplayText', () {
      const block = McpContentBlock(
        type: 'image',
        data: 'iVBORw0KGgoAAAANSUhEUg==',
        mimeType: 'image/png',
      );

      expect(block.toDisplayText(), '[图片内容: image/png]');
      expect(block.toString(), contains('image/png'));
    });

    test('McpContentBlock resource block toDisplayText', () {
      const blockWithText = McpContentBlock(
        type: 'resource',
        uri: 'file:///data.json',
        text: '{"key": "value"}',
      );
      expect(blockWithText.toDisplayText(), '{"key": "value"}');

      const blockWithoutText = McpContentBlock(
        type: 'resource',
        uri: 'file:///image.bin',
      );
      expect(blockWithoutText.toDisplayText(), '[资源内容: file:///image.bin]');
    });

    test('McpToolCallResult factories and helpers', () {
      final successResult = McpToolCallResult.text('Computation completed: 42');
      expect(successResult.isError, isFalse);
      expect(successResult.content.length, 1);
      expect(successResult.content.first.text, 'Computation completed: 42');
      expect(successResult.toDisplayText(), 'Computation completed: 42');

      final errorResult = McpToolCallResult.error('Syntax error in expression');
      expect(errorResult.isError, isTrue);
      expect(errorResult.content.first.text, 'Syntax error in expression');
      expect(errorResult.toDisplayText(), 'Syntax error in expression');
    });

    test('McpToolCallResult toJson and fromJson round-trip', () {
      const result = McpToolCallResult(
        content: [
          McpContentBlock(type: 'text', text: 'Line 1'),
          McpContentBlock(type: 'text', text: 'Line 2'),
        ],
        isError: false,
        meta: {'executionTime': 24},
      );

      final json = result.toJson();
      expect(json['content'], isList);
      expect(json['isError'], isFalse);
      expect(json['_meta']['executionTime'], 24);

      final restored = McpToolCallResult.fromJson(json);
      expect(restored.content.length, 2);
      expect(restored.isError, isFalse);
      expect(restored.toDisplayText(), 'Line 1\nLine 2');
    });
  });

  group('McpResourceInfo & McpPromptInfo Model Tests', () {
    test('McpResourceInfo toJson and fromJson', () {
      const resource = McpResourceInfo(
        uri: 'file:///workspace/project.yaml',
        name: 'Project Spec',
        description: 'YAML specification of project',
        mimeType: 'text/yaml',
        size: 2048,
      );

      expect(resource.uri, 'file:///workspace/project.yaml');
      expect(resource.name, 'Project Spec');
      expect(resource.size, 2048);

      final json = resource.toJson();
      expect(json['uri'], 'file:///workspace/project.yaml');
      expect(json['size'], 2048);

      final restored = McpResourceInfo.fromJson(json);
      expect(restored.uri, resource.uri);
      expect(restored.name, resource.name);
      expect(restored.description, resource.description);
      expect(restored.mimeType, resource.mimeType);
      expect(restored.size, resource.size);
    });

    test('McpResourceContent text and binary blob toJson and fromJson', () {
      const textContent = McpResourceContent(
        uri: 'file:///notes.txt',
        mimeType: 'text/plain',
        text: 'Meeting notes',
      );
      expect(textContent.text, 'Meeting notes');
      expect(textContent.blob, isNull);

      final textJson = textContent.toJson();
      final restoredText = McpResourceContent.fromJson(textJson);
      expect(restoredText.text, 'Meeting notes');

      const blobContent = McpResourceContent(
        uri: 'file:///binary.dat',
        blob: 'SGVsbG8gV29ybGQ=',
      );
      expect(blobContent.blob, 'SGVsbG8gV29ybGQ=');

      final blobJson = blobContent.toJson();
      final restoredBlob = McpResourceContent.fromJson(blobJson);
      expect(restoredBlob.blob, 'SGVsbG8gV29ybGQ=');
    });

    test('McpPromptInfo and McpPromptArgument serialization', () {
      const prompt = McpPromptInfo(
        name: 'refactor_code',
        description: 'Refactor code to improve readability',
        arguments: [
          McpPromptArgument(
            name: 'target_file',
            description: 'Path of target code file',
            required: true,
          ),
          McpPromptArgument(
            name: 'style_guide',
            description: 'Preferred coding style',
            required: false,
          ),
        ],
      );

      expect(prompt.name, 'refactor_code');
      expect(prompt.arguments.length, 2);
      expect(prompt.arguments.first.name, 'target_file');
      expect(prompt.arguments.first.required, isTrue);

      final json = prompt.toJson();
      expect(json['name'], 'refactor_code');
      expect(json['arguments'], isList);

      final restored = McpPromptInfo.fromJson(json);
      expect(restored.name, prompt.name);
      expect(restored.description, prompt.description);
      expect(restored.arguments.length, 2);
      expect(restored.arguments.first.name, 'target_file');
      expect(restored.arguments.last.name, 'style_guide');
    });
  });

  group('McpInitializeResult & Capabilities Model Tests', () {
    test('McpInitializeResult parsing with capabilities and serverInfo', () {
      final rawMap = {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'tools': {'listChanged': true},
          'resources': {'subscribe': true, 'listChanged': true},
          'prompts': {'listChanged': false},
          'logging': {},
        },
        'serverInfo': {
          'name': 'filesystem-mcp',
          'version': '3.4.1',
        },
        'instructions': 'Server usage guidelines',
      };

      final initResult = McpInitializeResult.fromJson(rawMap);
      expect(initResult.protocolVersion, '2024-11-05');
      expect(initResult.serverInfo.name, 'filesystem-mcp');
      expect(initResult.serverInfo.version, '3.4.1');
      expect(initResult.instructions, 'Server usage guidelines');
      expect(initResult.capabilities.supportsTools, isTrue);
      expect(initResult.capabilities.supportsResources, isTrue);
      expect(initResult.capabilities.supportsPrompts, isTrue);
      expect(initResult.capabilities.supportsLogging, isTrue);

      final exported = initResult.toJson();
      expect(exported['protocolVersion'], '2024-11-05');
      expect(exported['serverInfo']['name'], 'filesystem-mcp');
    });

    test('McpServerCapabilities with empty capabilities', () {
      const caps = McpServerCapabilities();
      expect(caps.supportsTools, isFalse);
      expect(caps.supportsResources, isFalse);
      expect(caps.supportsPrompts, isFalse);
      expect(caps.supportsLogging, isFalse);
      expect(caps.toJson(), isEmpty);
    });
  });
}
