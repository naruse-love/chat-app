import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool/tool_confirmation.dart';
import 'package:chat/services/agent_service.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/url_fetch_service.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/path_sanitizer.dart';
import 'package:chat/services/tools/file_write_tool.dart';
import 'package:path/path.dart' as p;

/// Mock ChatService to simulate LLM responses with function calling and pseudo-XML.
class MockChatServiceForHitl extends ChatService {
  final List<List<Map<String, dynamic>>> responseRounds;
  int currentRound = 0;

  MockChatServiceForHitl(this.responseRounds);

  @override
  Stream<Map<String, dynamic>> chatCompletionsStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    String? reasoningEffort,
    dynamic cancelToken,
  }) async* {
    if (currentRound < responseRounds.length) {
      final chunks = responseRounds[currentRound++];
      for (final chunk in chunks) {
        yield chunk;
      }
    }
  }
}

void main() {
  late Directory tempDir;
  late PathSanitizer sanitizer;
  late ToolRegistry registry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hitl_test_');
    sanitizer = PathSanitizer(sandboxDir: tempDir);
    registry = ToolRegistry();
    registry.register(FileWriteTool(pathSanitizer: sanitizer));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AgentService HITL Confirmation Tests', () {
    test('Standard tool call triggers confirmation event and executes on approval', () async {
      // Round 0: LLM requests file_write
      final round0 = [
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_123',
                    'type': 'function',
                    'function': {
                      'name': 'file_write',
                      'arguments': '{"path": "hello.txt", "content": "Hello World"}',
                    },
                  }
                ]
              }
            }
          ]
        }
      ];

      // Round 1: LLM responds to tool result
      final round1 = [
        {
          'choices': [
            {
              'delta': {'content': '已成功写入文件。'}
            }
          ]
        }
      ];

      final mockChatService = MockChatServiceForHitl([round0, round1]);
      final agentService = AgentService(
        chatService: mockChatService,
        searchService: SearchService(),
        urlFetchService: UrlFetchService(),
        toolRegistry: registry,
      );

      ToolConfirmationRequest? capturedRequest;

      final events = <AgentStreamEvent>[];
      await for (final event in agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4',
        messages: [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'c1',
            role: 'user',
            content: 'Write hello.txt',
            timestamp: DateTime.now(),
          ),
        ],
        onConfirmTool: (req) async {
          capturedRequest = req;
          return ToolConfirmationDecision.approve();
        },
      )) {
        events.add(event);
      }

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.toolName, equals('file_write'));
      expect(capturedRequest!.previewData, isA<FileWritePreview>());

      // File was actually written
      final createdFile = File(p.join(tempDir.path, 'hello.txt'));
      expect(await createdFile.exists(), isTrue);
      expect(await createdFile.readAsString(), equals('Hello World'));

      // ToolConfirmationPendingEvent was yielded
      expect(events.any((e) => e is ToolConfirmationPendingEvent), isTrue);

      // ToolCallExecutedMessageEvent was yielded
      final executedEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(executedEvents.isNotEmpty, isTrue);

      // Content was yielded in round 1
      final contentEvents = events.whereType<ContentDeltaEvent>().toList();
      expect(contentEvents.map((e) => e.content).join(), contains('已成功写入文件'));
    });

    test('Standard tool call handles user rejection with custom reason', () async {
      final round0 = [
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_reject_1',
                    'type': 'function',
                    'function': {
                      'name': 'file_write',
                      'arguments': '{"path": "secret.txt", "content": "Sensitive Data"}',
                    },
                  }
                ]
              }
            }
          ]
        }
      ];

      // Round 1: LLM observes rejection message
      final round1 = [
        {
          'choices': [
            {
              'delta': {'content': '好的，我已知晓您拒绝了写入权限。'}
            }
          ]
        }
      ];

      final mockChatService = MockChatServiceForHitl([round0, round1]);
      final agentService = AgentService(
        chatService: mockChatService,
        searchService: SearchService(),
        urlFetchService: UrlFetchService(),
        toolRegistry: registry,
      );

      final events = <AgentStreamEvent>[];
      await for (final event in agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4',
        messages: [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'c1',
            role: 'user',
            content: 'Write secret.txt',
            timestamp: DateTime.now(),
          ),
        ],
        onConfirmTool: (req) async {
          return ToolConfirmationDecision.reject('用户明确拒绝敏感文件修改');
        },
      )) {
        events.add(event);
      }

      // File was NOT written
      final secretFile = File(p.join(tempDir.path, 'secret.txt'));
      expect(await secretFile.exists(), isFalse);

      // Check tool messages yielded in ToolCallExecutedMessageEvent
      final executedEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(executedEvents.isNotEmpty, isTrue);
      final toolMsg = executedEvents.first.toolMessages.first;
      expect(toolMsg.content, contains('【用户已拒绝执行此操作】'));
      expect(toolMsg.content, contains('用户明确拒绝敏感文件修改'));

      // Final response produced
      final contentEvents = events.whereType<ContentDeltaEvent>().toList();
      expect(contentEvents.map((e) => e.content).join(), contains('好的，我已知晓您拒绝了写入权限'));
    });

    test('Standard tool call aborts stream safely when cancelled', () async {
      final round0 = [
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_cancel_1',
                    'type': 'function',
                    'function': {
                      'name': 'file_write',
                      'arguments': '{"path": "cancel.txt", "content": "Cancel"}',
                    },
                  }
                ]
              }
            }
          ]
        }
      ];

      final mockChatService = MockChatServiceForHitl([round0]);
      final agentService = AgentService(
        chatService: mockChatService,
        searchService: SearchService(),
        urlFetchService: UrlFetchService(),
        toolRegistry: registry,
      );

      final events = <AgentStreamEvent>[];
      await for (final event in agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4',
        messages: [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'c1',
            role: 'user',
            content: 'Write cancel.txt',
            timestamp: DateTime.now(),
          ),
        ],
        onConfirmTool: (req) async {
          return ToolConfirmationDecision.cancel();
        },
      )) {
        events.add(event);
      }

      // File was not written
      expect(await File(p.join(tempDir.path, 'cancel.txt')).exists(), isFalse);

      // Tool execution did not finish and stream closed early
      expect(events.whereType<ToolCallExecutedMessageEvent>().isEmpty, isTrue);
    });

    test('Pseudo-XML tool call triggers confirmation and handles rejection', () async {
      final round0 = [
        {
          'choices': [
            {
              'delta': {
                'content': '<tool_call>\n<function=file_write>\n<parameter=path>pseudo.txt</parameter>\n<parameter=content>XML Data</parameter>\n</function>\n</tool_call>'
              }
            }
          ]
        }
      ];

      final round1 = [
        {
          'choices': [
            {
              'delta': {'content': '已处理拒绝情况。'}
            }
          ]
        }
      ];

      final mockChatService = MockChatServiceForHitl([round0, round1]);
      final agentService = AgentService(
        chatService: mockChatService,
        searchService: SearchService(),
        urlFetchService: UrlFetchService(),
        toolRegistry: registry,
      );

      final events = <AgentStreamEvent>[];
      await for (final event in agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4',
        messages: [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'c1',
            role: 'user',
            content: 'Pseudo call write',
            timestamp: DateTime.now(),
          ),
        ],
        onConfirmTool: (req) async {
          return ToolConfirmationDecision.reject('禁止 XML 模式写入');
        },
      )) {
        events.add(event);
      }

      // File not written
      expect(await File(p.join(tempDir.path, 'pseudo.txt')).exists(), isFalse);

      final executedEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(executedEvents.isNotEmpty, isTrue);
      expect(executedEvents.first.toolMessages.first.content, contains('【用户已拒绝执行此操作】原因：禁止 XML 模式写入'));
    });
  });
}
