import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/agent_service.dart';

class MockChatService extends ChatService {
  Stream<Map<String, dynamic>> Function({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    String? reasoningEffort,
    CancelToken? cancelToken,
  })? chatCompletionsStreamHandler;

  @override
  Stream<Map<String, dynamic>> chatCompletionsStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    String? reasoningEffort,
    CancelToken? cancelToken,
  }) {
    if (chatCompletionsStreamHandler != null) {
      return chatCompletionsStreamHandler!(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
        tools: tools,
        reasoningEffort: reasoningEffort,
        cancelToken: cancelToken,
      );
    }
    return const Stream.empty();
  }
}

class MockSearchService extends SearchService {
  @override
  Future<List<SearchResult>> search({
    required String query,
    String? searxngUrl,
    String searchBackend = 'searxng',
    String? googleApiKey,
    String? googleBaseUrl,
    String? googleSearchModel,
    String? bingCookie,
  }) {
    return Future.value([
      SearchResult(title: 'Result for $query', url: 'https://example.com/search?q=$query', content: 'Snippet for $query'),
    ]);
  }
}

void main() {
  group('Pseudo-XML & DSML Parser Unit Stress Tests', () {
    test('Standard <tool_call> with single & multiple parameters', () {
      const xml1 = '''
I will calculate this expression:
<tool_call>
<function=math_eval>
<parameter=expression>2 * (15 + 3.5)</parameter>
</function>
</tool_call>
''';
      final calls1 = AgentService.parsePseudoXmlToolCalls(xml1);
      expect(calls1, hasLength(1));
      expect(calls1[0]['name'], 'math_eval');
      expect(calls1[0]['params'], {'expression': '2 * (15 + 3.5)'});

      const xmlMultiParam = '''
<tool_call>
<function=time_calculator>
<parameter=operation>convert</parameter>
<parameter=fromTimezone>UTC</parameter>
<parameter=toTimezone>Asia/Shanghai</parameter>
<parameter=datetime>2026-08-28 12:00:00</parameter>
</function>
</tool_call>
''';
      final callsMulti = AgentService.parsePseudoXmlToolCalls(xmlMultiParam);
      expect(callsMulti, hasLength(1));
      expect(callsMulti[0]['name'], 'time_calculator');
      expect(callsMulti[0]['params'], {
        'operation': 'convert',
        'fromTimezone': 'UTC',
        'toTimezone': 'Asia/Shanghai',
        'datetime': '2026-08-28 12:00:00',
      });
    });

    test('DSML with full-width Chinese pipe symbols (｜｜)', () {
      const dsmlZh = '''
<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="weather_query">
<｜｜DSML｜｜parameter name="city">Beijing</｜｜DSML｜｜parameter>
</｜｜DSML｜｜invoke>
</｜｜DSML｜｜tool_calls>
''';
      final calls = AgentService.parsePseudoXmlToolCalls(dsmlZh);
      expect(calls, hasLength(1));
      expect(calls[0]['name'], 'weather_query');
      expect(calls[0]['params'], {'city': 'Beijing'});
    });

    test('DSML with ASCII pipe symbols (||) and multiple invokes', () {
      const dsmlAscii = '''
<||DSML||tool_calls>
<||DSML||invoke name="math_eval">
<||DSML||parameter name="expression">100 / 4</||DSML||parameter>
</||DSML||invoke>
<||DSML||invoke name="wiki_lookup">
<||DSML||parameter name="query">Dart</||DSML||parameter>
<||DSML||parameter name="language">zh</||DSML||parameter>
</||DSML||invoke>
</||DSML||tool_calls>
''';
      final calls = AgentService.parsePseudoXmlToolCalls(dsmlAscii);
      expect(calls, hasLength(2));
      expect(calls[0]['name'], 'math_eval');
      expect(calls[0]['params'], {'expression': '100 / 4'});
      expect(calls[1]['name'], 'wiki_lookup');
      expect(calls[1]['params'], {'query': 'Dart', 'language': 'zh'});
    });

    test('Malformed and broken pseudo-XML handling', () {
      // Unclosed tag
      const broken1 = '<tool_call><function=math_eval><parameter=expression>1+1';
      expect(AgentService.parsePseudoXmlToolCalls(broken1), isEmpty);

      // Missing function name
      const broken2 = '<tool_call><parameter=expression>1+1</parameter></tool_call>';
      expect(AgentService.parsePseudoXmlToolCalls(broken2), isEmpty);

      // Non-XML plain text
      const plain = 'The answer is <tool_call> not really a call';
      expect(AgentService.parsePseudoXmlToolCalls(plain), isEmpty);
    });

    test('stripPseudoXmlToolCalls removes all variations cleanly', () {
      const mixed = '''
Let me calculate that for you:
<tool_call>
<function=math_eval>
<parameter=expression>50 + 50</parameter>
</function>
</tool_call>
Done calculating.
<||DSML||tool_calls>
<||DSML||invoke name="time_calculator">
<||DSML||parameter name="operation">now</||DSML||parameter>
</||DSML||invoke>
</||DSML||tool_calls>
Finished all operations.
''';
      final stripped = AgentService.stripPseudoXmlToolCalls(mixed);
      expect(stripped, contains('Let me calculate that for you:'));
      expect(stripped, contains('Done calculating.'));
      expect(stripped, contains('Finished all operations.'));
      expect(stripped, isNot(contains('<tool_call>')));
      expect(stripped, isNot(contains('<||DSML||tool_calls>')));
    });
  });

  group('AgentService Pseudo-XML & DSML Streaming Fallback E2E Tests', () {
    late MockChatService mockChatService;
    late MockSearchService mockSearchService;
    late ToolRegistry toolRegistry;
    late AgentService agentService;

    setUp(() {
      mockChatService = MockChatService();
      mockSearchService = MockSearchService();
      toolRegistry = ToolRegistry.defaultRegistry(
        searchService: mockSearchService,
      );
      agentService = AgentService(
        chatService: mockChatService,
        searchService: mockSearchService,
        toolRegistry: toolRegistry,
      );
    });

    test('Single-round pseudo-XML fallback for math_eval', () async {
      int callCount = 0;

      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) {
        callCount++;
        if (callCount == 1) {
          // Model emits content containing pseudo-XML without tool_calls structure
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': '我将使用数学计算工具进行运算：\n<tool_call>\n<function=math_eval>\n<parameter=expression>sqrt(144) + 10</parameter>\n</function>\n</tool_call>'
                  }
                }
              ]
            }
          ]);
        } else {
          // Follow-up receives the assistant message (with pseudo tool call) and tool result message
          expect(messages.any((m) => m.role == 'assistant' && m.toolCalls != null && m.toolCalls!.first.functionName == 'math_eval'), isTrue);
          expect(messages.any((m) => m.role == 'tool' && m.content.contains('22')), isTrue);

          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': '计算结果是 22。'}
                }
              ]
            }
          ]);
        }
      };

      final messages = [
        ChatMessage(
          id: 'm1',
          conversationId: 'c1',
          role: 'user',
          content: 'Calculate sqrt(144) + 10',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.test.com',
        apiKey: 'key',
        model: 'test-model',
        messages: messages,
      ).toList();

      expect(callCount, 2);
      final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(execEvents, hasLength(1));
      expect(execEvents.first.assistantMessage.toolCalls?.first.functionName, 'math_eval');
      expect(execEvents.first.toolMessages.first.content, contains('22'));

      final finalContent = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
      expect(finalContent, contains('计算结果是 22'));
    });

    test('DSML streaming fallback for time_calculator', () async {
      int callCount = 0;

      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': '<||DSML||tool_calls>\n<||DSML||invoke name="time_calculator">\n<||DSML||parameter name="operation">now</||DSML||parameter>\n<||DSML||parameter name="timezone">UTC</||DSML||parameter>\n</||DSML||invoke>\n</||DSML||tool_calls>'
                  }
                }
              ]
            }
          ]);
        } else {
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': '已成功获取当前 UTC 时间。'}
                }
              ]
            }
          ]);
        }
      };

      final messages = [
        ChatMessage(
          id: 'm_dsml',
          conversationId: 'c_dsml',
          role: 'user',
          content: 'What time is it in UTC?',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.test.com',
        apiKey: 'key',
        model: 'test-model',
        messages: messages,
      ).toList();

      expect(callCount, 2);
      final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(execEvents, hasLength(1));
      expect(execEvents.first.assistantMessage.toolCalls?.first.functionName, 'time_calculator');
      expect(execEvents.first.toolMessages.first.content, contains('UTC'));

      final finalContent = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
      expect(finalContent, contains('已成功获取当前 UTC 时间。'));
    });

    test('Multi-round pseudo-XML chaining with state preservation', () async {
      int callCount = 0;

      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) {
        callCount++;
        if (callCount == 1) {
          // Round 1 pseudo-XML math
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': '<tool_call><function=math_eval><parameter=expression>10 + 20</parameter></function></tool_call>'
                  }
                }
              ]
            }
          ]);
        } else if (callCount == 2) {
          // Round 2 pseudo-XML time offset
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': '<tool_call><function=time_calculator><parameter=operation>offset</parameter><parameter=datetime>2026-08-28 12:00:00</parameter><parameter=offset>+30m</parameter><parameter=timezone>UTC</parameter></function></tool_call>'
                  }
                }
              ]
            }
          ]);
        } else {
          // Final summary
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': '两轮多步伪 XML 工具调用全部完成。'}
                }
              ]
            }
          ]);
        }
      };

      final messages = [
        ChatMessage(
          id: 'm_chain',
          conversationId: 'c_chain',
          role: 'user',
          content: 'Run math then time',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.test.com',
        apiKey: 'key',
        model: 'test-model',
        messages: messages,
      ).toList();

      expect(callCount, 3);
      final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(execEvents, hasLength(2));
      expect(execEvents[0].assistantMessage.toolCalls?.first.functionName, 'math_eval');
      expect(execEvents[0].toolMessages.first.content, contains('30'));
      expect(execEvents[1].assistantMessage.toolCalls?.first.functionName, 'time_calculator');
      expect(execEvents[1].toolMessages.first.content, contains('12:30:00'));

      final finalContent = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
      expect(finalContent, contains('两轮多步伪 XML 工具调用全部完成。'));
    });

    test('Loop guard blocks repeated pseudo-XML tool calls', () async {
      int callCount = 0;

      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) {
        callCount++;
        if (tools == null || tools.isEmpty) {
          // Intercepted by loop guard
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': '死循环已被防护机制拦截并终止。'}
                }
              ]
            }
          ]);
        }

        // Loop generating identical pseudo-XML call
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {
                  'content': '<tool_call><function=math_eval><parameter=expression>42 * 42</parameter></function></tool_call>'
                }
              }
            ]
          }
        ]);
      };

      final messages = [
        ChatMessage(
          id: 'm_loop',
          conversationId: 'c_loop',
          role: 'user',
          content: 'Infinite loop XML test',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.test.com',
        apiKey: 'key',
        model: 'test-model',
        messages: messages,
      ).toList();

      // Guard defaults to duplicateThreshold = 3
      // Call 1: exec
      // Call 2: exec
      // Call 3: blocked before exec!
      final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(execEvents, hasLength(2));

      final finalContent = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
      expect(finalContent, contains('死循环已被防护机制拦截并终止。'));
      expect(callCount, greaterThan(0));
    });

    test('Pseudo-XML with unknown tool name returns friendly error and does not crash', () async {
      int callCount = 0;

      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) {
        callCount++;
        if (callCount == 1) {
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': '<tool_call><function=non_existent_tool><parameter=arg>123</parameter></function></tool_call>'
                  }
                }
              ]
            }
          ]);
        } else {
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': '已获知工具不存在并安全降级。'}
                }
              ]
            }
          ]);
        }
      };

      final messages = [
        ChatMessage(
          id: 'm_unknown',
          conversationId: 'c_unknown',
          role: 'user',
          content: 'Call non-existent tool',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.test.com',
        apiKey: 'key',
        model: 'test-model',
        messages: messages,
      ).toList();

      expect(callCount, 2);
      final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(execEvents, hasLength(1));
      expect(execEvents.first.toolMessages.first.content, contains("未找到工具 'non_existent_tool'"));

      final finalContent = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
      expect(finalContent, contains('已获知工具不存在并安全降级。'));
    });
  });
}
