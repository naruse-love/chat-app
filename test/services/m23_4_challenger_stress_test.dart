import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool/tool.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/url_fetch_service.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/agent_service.dart';
import 'package:chat/services/agent_loop_guard.dart';

class MockHttpClientAdapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(RequestOptions options) handler;

  MockHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = handler(options);
    final statusCode = result['statusCode'] as int? ?? 200;
    final data = result['data'];
    final jsonString = data is String ? data : jsonEncode(data);
    final responseBytes = utf8.encode(jsonString);

    return ResponseBody.fromBytes(
      responseBytes,
      statusCode,
      headers: {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

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
  Future<List<SearchResult>> Function({
    required String query,
    String? searxngUrl,
    required String searchBackend,
  })? searchHandler;

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
    if (searchHandler != null) {
      return searchHandler!(
        query: query,
        searxngUrl: searxngUrl,
        searchBackend: searchBackend,
      );
    }
    return Future.value([
      SearchResult(title: 'Result for $query', url: 'https://example.com/$query', content: 'Snippet for $query'),
    ]);
  }
}

/// Custom test tool that can throw arbitrary exceptions on demand.
class BuggyCustomTool extends Tool {
  final bool shouldThrow;
  final String errorMessage;

  const BuggyCustomTool({
    this.shouldThrow = false,
    this.errorMessage = 'Custom tool internal crash',
  });

  @override
  String get name => 'buggy_tool';
  @override
  String get displayName => '故障测试工具';
  @override
  String get description => '用于测试异常处理的工具';
  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.safe;

  @override
  List<ToolParameter> get parameters => [
        const ToolParameter(
          name: 'payload',
          type: 'string',
          description: '测试载荷',
          required: true,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(
    Map<String, dynamic> arguments, {
    Map<String, dynamic>? context,
  }) async {
    if (shouldThrow) {
      throw StateError(errorMessage);
    }
    return ToolExecutionResult.success(
      toolName: name,
      content: '成功执行载荷: ${arguments['payload']}',
    );
  }
}

void main() {
  group('Empirical Challenger Stress Testing — Milestone 23.4', () {
    late MockChatService mockChatService;
    late MockSearchService mockSearchService;
    late Dio mockDio;
    late ToolRegistry toolRegistry;
    late AgentService agentService;

    setUp(() {
      mockChatService = MockChatService();
      mockSearchService = MockSearchService();

      mockDio = Dio()..httpClientAdapter = MockHttpClientAdapter((options) {
        final uri = options.uri.toString();
        if (uri.contains('geocoding-api.open-meteo.com')) {
          return {
            'statusCode': 200,
            'data': {
              'results': [
                {
                  'name': 'Shanghai',
                  'latitude': 31.2304,
                  'longitude': 121.4737,
                  'country': 'China',
                  'admin1': 'Shanghai',
                }
              ]
            }
          };
        }
        if (uri.contains('api.open-meteo.com/v1/forecast')) {
          return {
            'statusCode': 200,
            'data': {
              'latitude': 31.23,
              'longitude': 121.47,
              'timezone': 'Asia/Shanghai',
              'current_weather': {
                'time': '2026-08-28T21:00',
                'temperature': 28.0,
                'windspeed': 10.0,
                'winddirection': 90,
                'weathercode': 0,
              },
              'hourly': {
                'time': ['2026-08-28T21:00'],
                'apparent_temperature': [29.5],
                'relative_humidity_2m': [70],
              },
              'daily': {
                'time': ['2026-08-28'],
                'weathercode': [0],
                'temperature_2m_max': [32.0],
                'temperature_2m_min': [25.0],
                'precipitation_sum': [0.0],
                'windspeed_10m_max': [10.0],
              }
            }
          };
        }
        if (uri.contains('wikipedia.org/api/rest_v1/page/summary/')) {
          return {
            'statusCode': 200,
            'data': {
              'type': 'standard',
              'title': 'Dart',
              'displaytitle': 'Dart (programming language)',
              'extract': 'Dart is a client-optimized language by Google.',
              'lang': 'en',
              'content_urls': {
                'desktop': {'page': 'https://en.wikipedia.org/wiki/Dart_(programming_language)'}
              }
            }
          };
        }
        return {'statusCode': 404, 'data': {}};
      });

      toolRegistry = ToolRegistry.defaultRegistry(
        searchService: mockSearchService,
        urlFetchService: UrlFetchService(dio: mockDio),
        dio: mockDio,
      );

      agentService = AgentService(
        chatService: mockChatService,
        searchService: mockSearchService,
        toolRegistry: toolRegistry,
      );
    });

    group('Stress Suite 1: Multi-round Heterogeneous Tool Chains', () {
      test('1.1 4-Step Heterogeneous Chain: weather_query -> math_eval -> time_calculator -> wiki_lookup -> final summary', () async {
        int callCount = 0;
        final messageHistoryLengths = <int>[];

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
          messageHistoryLengths.add(messages.length);

          if (callCount == 1) {
            // Round 1: Weather query
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_weather_step1',
                          'type': 'function',
                          'function': {
                            'name': 'weather_query',
                            'arguments': '{"city": "Shanghai"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else if (callCount == 2) {
            // Round 2: Math eval based on temperature
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_math_step2',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "28.0 * 9 / 5 + 32"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else if (callCount == 3) {
            // Round 3: Time query
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_time_step3',
                          'type': 'function',
                          'function': {
                            'name': 'time_calculator',
                            'arguments': '{"operation": "now", "timezone": "Asia/Shanghai"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else if (callCount == 4) {
            // Round 4: Wiki lookup
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_wiki_step4',
                          'type': 'function',
                          'function': {
                            'name': 'wiki_lookup',
                            'arguments': '{"query": "Dart", "language": "en"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else {
            // Round 5: Final response
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {'content': '上海天气 28°C (82.4°F)，已查询当前时间与 Dart 百科。'}
                  }
                ],
                'usage': {'prompt_tokens': 450, 'completion_tokens': 60}
              }
            ]);
          }
        };

        final initialMessages = [
          ChatMessage(
            id: 'msg_user_1',
            conversationId: 'conv_stress_1',
            role: 'user',
            content: 'Shanghai weather, F conversion, time, and Dart wiki info please',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: initialMessages,
        ).toList();

        expect(callCount, 5);
        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(4));

        expect(execEvents[0].assistantMessage.toolCalls?.first.functionName, 'weather_query');
        expect(execEvents[0].toolMessages.first.content, contains('Shanghai'));

        expect(execEvents[1].assistantMessage.toolCalls?.first.functionName, 'math_eval');
        expect(execEvents[1].toolMessages.first.content, contains('82.4'));

        expect(execEvents[2].assistantMessage.toolCalls?.first.functionName, 'time_calculator');
        expect(execEvents[2].toolMessages.first.content, contains('Asia/Shanghai'));

        expect(execEvents[3].assistantMessage.toolCalls?.first.functionName, 'wiki_lookup');
        expect(execEvents[3].toolMessages.first.content, contains('Dart'));

        final usageEvents = events.whereType<UsageEvent>().toList();
        expect(usageEvents, hasLength(1));
        expect(usageEvents.first.promptTokens, 450);
        expect(usageEvents.first.completionTokens, 60);

        final lastContent = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
        expect(lastContent, contains('上海天气 28°C (82.4°F)'));
      });
    });

    group('Stress Suite 2: Concurrent Multi-Tool Invocations in Single Response', () {
      test('2.1 Concurrent execution of 3 tools (math_eval + time_calculator + wiki_lookup) in single turn', () async {
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
            // Emit 3 parallel tool calls in one response
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_math_p0',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "100 + 200"}'
                          }
                        },
                        {
                          'index': 1,
                          'id': 'call_time_p1',
                          'type': 'function',
                          'function': {
                            'name': 'time_calculator',
                            'arguments': '{"operation": "now", "timezone": "UTC"}'
                          }
                        },
                        {
                          'index': 2,
                          'id': 'call_wiki_p2',
                          'type': 'function',
                          'function': {
                            'name': 'wiki_lookup',
                            'arguments': '{"query": "Dart", "language": "en"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else {
            // Next round: check that messages contains all 3 tool response messages with correct IDs
            expect(messages.any((m) => m.role == 'tool' && m.toolCallId == 'call_math_p0'), isTrue);
            expect(messages.any((m) => m.role == 'tool' && m.toolCallId == 'call_time_p1'), isTrue);
            expect(messages.any((m) => m.role == 'tool' && m.toolCallId == 'call_wiki_p2'), isTrue);

            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {'content': '并行三大工具全部执行完毕。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_concurrent_1',
            conversationId: 'conv_concurrent',
            role: 'user',
            content: 'Execute 3 tools in parallel',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
        ).toList();

        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(1));
        final singleExecEvent = execEvents.first;
        expect(singleExecEvent.assistantMessage.toolCalls, hasLength(3));
        expect(singleExecEvent.toolMessages, hasLength(3));
        expect(singleExecEvent.toolMessages[0].content, contains('300'));
        expect(singleExecEvent.toolMessages[1].content, contains('UTC'));
        expect(singleExecEvent.toolMessages[2].content, contains('Dart'));
      });
    });

    group('Stress Suite 3: Loop Guard Edge Cases & Complex Cycles', () {
      test('3.1 Period-3 cyclic oscillation (A -> B -> C -> A -> B -> C) intercepted by AgentService', () async {
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
            // Guard triggered forced conclusion
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {'content': '周期 3 循环振荡拦截成功。'}
                  }
                ]
              }
            ]);
          }

          // Generate pattern A (math_eval) -> B (time_calculator) -> C (wiki_lookup)
          final mod = (callCount - 1) % 3;
          if (mod == 0) {
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_p3_$callCount',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "1 + 1"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else if (mod == 1) {
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_p3_$callCount',
                          'type': 'function',
                          'function': {
                            'name': 'time_calculator',
                            'arguments': '{"operation": "now"}'
                          }
                        }
                      ]
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
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_p3_$callCount',
                          'type': 'function',
                          'function': {
                            'name': 'wiki_lookup',
                            'arguments': '{"query": "Dart"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_osc3',
            conversationId: 'conv_osc3',
            role: 'user',
            content: 'Trigger period 3 oscillation',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
          maxToolRounds: 15,
        ).toList();

        // 1: A (exec)
        // 2: B (exec)
        // 3: C (exec)
        // 4: A (exec)
        // 5: B (exec)
        // 6: C (blocked by oscillation detection - period 3 cycle complete!)
        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(5));

        final contentDeltas = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
        expect(contentDeltas, contains('周期 3 循环振荡拦截成功'));
      });

      test('3.2 Consecutive duplicate detection on Round 0 (initial call) vs Follow-up call', () async {
        final customGuard = AgentLoopGuard(duplicateThreshold: 2);
        // Pre-fill history in guard to simulate existing call
        customGuard.recordToolCall('math_eval', {'expression': '42'});

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
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {'content': '初始调用即被连续重复拦截。'}
                  }
                ]
              }
            ]);
          }
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_round0_dup',
                        'type': 'function',
                        'function': {
                          'name': 'math_eval',
                          'arguments': '{"expression": "42"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        };

        final messages = [
          ChatMessage(
            id: 'msg_round0',
            conversationId: 'conv_round0',
            role: 'user',
            content: 'Calculate duplicate',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
          guard: customGuard,
        ).toList();

        // Should be blocked immediately at round 0 without executing tool
        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, isEmpty);
        expect(callCount, greaterThan(0));
        final contentDeltas = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
        expect(contentDeltas, contains('初始调用即被连续重复拦截'));
      });
    });

    group('Stress Suite 4: Error Resilience, Custom Tools & Dynamic Enablement', () {
      test('4.1 Unhandled tool internal exception is caught by ToolRegistry and reported in tool message', () async {
        toolRegistry.register(const BuggyCustomTool(shouldThrow: true));

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
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_buggy_1',
                          'type': 'function',
                          'function': {
                            'name': 'buggy_tool',
                            'arguments': '{"payload": "test_crash"}'
                          }
                        }
                      ]
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
                    'delta': {'content': '已妥善处理工具故障。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_buggy',
            conversationId: 'conv_buggy',
            role: 'user',
            content: 'Run buggy tool',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
        ).toList();

        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(1));
        final toolMsg = execEvents.first.toolMessages.first;
        expect(toolMsg.content, contains('执行失败'));
        expect(toolMsg.content, contains('Custom tool internal crash'));
        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', '已妥善处理工具故障。'));
      });

      test('4.2 Partial failure in concurrent tool calls: one fails, one succeeds', () async {
        toolRegistry.register(const BuggyCustomTool(shouldThrow: true));

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
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_ok',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "50 + 50"}'
                          }
                        },
                        {
                          'index': 1,
                          'id': 'call_fail',
                          'type': 'function',
                          'function': {
                            'name': 'buggy_tool',
                            'arguments': '{"payload": "partial_fail"}'
                          }
                        }
                      ]
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
                    'delta': {'content': '部分成功，部分失败。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_partial',
            conversationId: 'conv_partial',
            role: 'user',
            content: 'Parallel partial fail test',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
        ).toList();

        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(1));
        final toolMessages = execEvents.first.toolMessages;
        expect(toolMessages, hasLength(2));
        expect(toolMessages[0].content, contains('100'));
        expect(toolMessages[1].content, contains('执行失败'));
        expect(toolMessages[1].content, contains('Custom tool internal crash'));
      });
    });

    group('Stress Suite 5: Schema Filtering & Effective Tools Conformance', () {
      test('5.1 getEffectiveTools correctly filters based on autoSearch and backend type', () {
        // 1. autoSearch: true, backend: searxng
        final searxngTools = AgentService.getEffectiveTools('searxng', enableAutoSearch: true, toolRegistry: toolRegistry);
        final searxngNames = searxngTools.map((t) => t['function']['name']).toList();
        expect(searxngNames, contains('web_search'));
        expect(searxngNames, isNot(contains('google_search')));
        expect(searxngNames, isNot(contains('bing_search')));
        expect(searxngNames, contains('math_eval'));
        expect(searxngNames, contains('time_calculator'));
        expect(searxngNames, contains('weather_query'));
        expect(searxngNames, contains('wiki_lookup'));

        // 2. autoSearch: false
        final noSearchTools = AgentService.getEffectiveTools('searxng', enableAutoSearch: false, toolRegistry: toolRegistry);
        final noSearchNames = noSearchTools.map((t) => t['function']['name']).toList();
        expect(noSearchNames, isNot(contains('web_search')));
        expect(noSearchNames, isNot(contains('google_search')));
        expect(noSearchNames, isNot(contains('bing_search')));
        expect(noSearchNames, contains('url_fetch'));
        expect(noSearchNames, contains('math_eval'));

        // 3. autoSearch: true, backend: google_bing
        final dualSearchTools = AgentService.getEffectiveTools('google_bing', enableAutoSearch: true, toolRegistry: toolRegistry);
        final dualSearchNames = dualSearchTools.map((t) => t['function']['name']).toList();
        expect(dualSearchNames, contains('google_search'));
        expect(dualSearchNames, contains('bing_search'));
        expect(dualSearchNames, isNot(contains('web_search')));
      });
    });

    group('Stress Suite 6: DSML Loops & Dynamic Runtime Adaptations', () {
      test('6.1 Repetitive DSML tool calls intercepted by consecutive duplicate guard in follow-up', () async {
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
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {'content': 'DSML 重复调用被成功拦截并总结。'}
                  }
                ]
              }
            ]);
          } else if (callCount == 1) {
            // Initial call emits standard tool call to enter follow-up loop
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_seed_1',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "7 * 7"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else {
            // Follow-up rounds emit identical DSML tool calls
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'content': '<｜｜DSML｜｜tool_calls>\n'
                          '<｜｜DSML｜｜invoke name="math_eval">\n'
                          '<｜｜DSML｜｜parameter name="expression">100 / 2</｜｜DSML｜｜parameter>\n'
                          '</｜｜DSML｜｜invoke>\n'
                          '</｜｜DSML｜｜tool_calls>'
                    }
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_dsml_loop',
            conversationId: 'conv_dsml_loop',
            role: 'user',
            content: 'Calculate repeated DSML',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
          maxToolRounds: 10,
        ).toList();

        // Round 1: seed math_eval (executed)
        // Round 2 (follow-up 1): DSML math_eval (100 / 2) (executed - 1st)
        // Round 3 (follow-up 2): DSML math_eval (100 / 2) (executed - 2nd)
        // Round 4 (follow-up 3): DSML math_eval (100 / 2) (3rd duplicate -> blocked!)
        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(3));

        final contentDeltas = events.whereType<ContentDeltaEvent>().map((e) => e.content).join();
        expect(contentDeltas, contains('DSML 重复调用被成功拦截并总结'));
      });

      test('6.2 Tool dynamically disabled between round 1 and round 2 handles gracefully', () async {
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
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_round1_time',
                          'type': 'function',
                          'function': {
                            'name': 'time_calculator',
                            'arguments': '{"operation": "now"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else if (callCount == 2) {
            // Before round 2 executes, time_calculator gets disabled in toolRegistry
            toolRegistry.setToolEnabled('time_calculator', false);

            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_round2_time',
                          'type': 'function',
                          'function': {
                            'name': 'time_calculator',
                            'arguments': '{"operation": "now"}'
                          }
                        }
                      ]
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
                    'delta': {'content': '已处理工具动态禁用。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_dyn_disable',
            conversationId: 'conv_dyn_disable',
            role: 'user',
            content: 'Dynamic disable test',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
        ).toList();

        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(2));
        // Round 1 succeeded
        expect(execEvents[0].toolMessages.first.content, contains('当前时间'));
        // Round 2 reported tool disabled
        expect(execEvents[1].toolMessages.first.content, contains('已被禁用'));
        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', '已处理工具动态禁用。'));
      });
    });
  });
}

