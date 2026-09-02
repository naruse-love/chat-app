import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/url_fetch_service.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/agent_service.dart';

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
      SearchResult(title: 'Search Result', url: 'https://example.com', content: 'Snippet for $query'),
    ]);
  }
}

void main() {
  group('Milestone 23.4: AgentService & ToolRegistry End-to-End Integration Tests', () {
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
        // Open-Meteo Geocoding
        if (uri.contains('geocoding-api.open-meteo.com')) {
          return {
            'statusCode': 200,
            'data': {
              'results': [
                {
                  'name': 'Beijing',
                  'latitude': 39.9042,
                  'longitude': 116.4074,
                  'country': 'China',
                  'admin1': 'Beijing',
                }
              ]
            }
          };
        }
        // Open-Meteo Forecast
        if (uri.contains('api.open-meteo.com/v1/forecast')) {
          return {
            'statusCode': 200,
            'data': {
              'latitude': 39.9,
              'longitude': 116.4,
              'timezone': 'Asia/Shanghai',
              'current_weather': {
                'time': '2026-08-28T21:00',
                'temperature': 26.5,
                'windspeed': 12.0,
                'winddirection': 0,
                'weathercode': 1,
              },
              'hourly': {
                'time': ['2026-08-28T21:00'],
                'apparent_temperature': [27.2],
                'relative_humidity_2m': [60],
              },
              'daily': {
                'time': ['2026-08-28', '2026-08-29'],
                'weathercode': [1, 2],
                'temperature_2m_max': [30.0, 31.0],
                'temperature_2m_min': [22.0, 23.0],
                'precipitation_sum': [0.0, 0.0],
                'windspeed_10m_max': [12.0, 15.0],
              }
            }
          };
        }
        // Wikipedia Summary
        if (uri.contains('wikipedia.org/api/rest_v1/page/summary/')) {
          return {
            'statusCode': 200,
            'data': {
              'type': 'standard',
              'title': 'Flutter',
              'displaytitle': 'Flutter (software)',
              'extract': 'Flutter is an open-source UI software development kit created by Google.',
              'lang': 'en',
              'content_urls': {
                'desktop': {'page': 'https://en.wikipedia.org/wiki/Flutter_(software)'}
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

    group('Group 1: Safe Basic Tools Multi-round Integration', () {
      test('1.1 math_eval single-round tool execution and response generation', () async {
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
                          'id': 'call_math_1',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "sqrt(144) + pow(2, 5)"}'
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
                    'delta': {'content': '计算结果是 44。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Calculate sqrt(144) + 2^5',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
        ).toList();

        expect(events.any((e) => e is ToolCallStartedEvent && e.query.contains('数学计算')), isTrue);
        expect(events.any((e) => e is ToolCallCompletedEvent), isTrue);

        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(1));
        final toolMsg = execEvents.first.toolMessages.first;
        expect(toolMsg.role, 'tool');
        expect(toolMsg.content, contains('44'));

        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', '计算结果是 44。'));
      });

      test('1.2 time_calculator tool execution with timezone query', () async {
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
                          'id': 'call_time_1',
                          'type': 'function',
                          'function': {
                            'name': 'time_calculator',
                            'arguments': '{"operation": "now", "timezone": "Asia/Tokyo"}'
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
                    'delta': {'content': '当前东京时间已获取。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'What time is it in Tokyo?',
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
        expect(toolMsg.content, contains('Asia/Tokyo'));
        expect(toolMsg.content, contains('当前时间'));
      });

      test('1.3 weather_query tool execution with mocked Open-Meteo REST API', () async {
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
                          'id': 'call_weather_1',
                          'type': 'function',
                          'function': {
                            'name': 'weather_query',
                            'arguments': '{"city": "Beijing"}'
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
                    'delta': {'content': '北京当前气温 26.5°C。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: '北京天气怎么样？',
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
        expect(toolMsg.content, contains('Beijing'));
        expect(toolMsg.content, contains('26.5'));
      });

      test('1.4 weather_query tool execution with mocked weather API', () async {
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
                          'id': 'call_weather_1',
                          'type': 'function',
                          'function': {
                            'name': 'weather_query',
                            'arguments': '{"city": "Beijing"}'
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
                    'delta': {'content': '北京当前天气晴朗。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Check weather in Beijing',
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
        expect(toolMsg.content, contains('Beijing'));
      });

      test('1.5 Multi-tool sequential chain (math_eval -> weather_query -> final summary)', () async {
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
                          'id': 'call_math_seq',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "2026 - 2017"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else if (callCount == 2) {
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_weather_seq',
                          'type': 'function',
                          'function': {
                            'name': 'weather_query',
                            'arguments': '{"city": "Tokyo"}'
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
                    'delta': {'content': 'Tokyo天气良好。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Check weather in Tokyo',
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
        expect(execEvents[0].toolMessages.first.toolCallId, 'call_math_seq');
        expect(execEvents[0].toolMessages.first.content, contains('9'));
        expect(execEvents[1].toolMessages.first.toolCallId, 'call_weather_seq');
        expect(execEvents[1].toolMessages.first.content, contains('Tokyo'));
        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Tokyo天气良好。'));
      });
    });

    group('Group 2: AgentLoopGuard Defenses & Safety Ceilings', () {
      test('2.1 Consecutive duplicate tool invocation defense (>=3 duplicate calls stripped)', () async {
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
            // Guard stripped tools and forced conclusion
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {'content': '已根据计算结果给出最终回答。'}
                  }
                ]
              }
            ]);
          } else {
            // Model keeps returning identical tool call
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_dup_$callCount',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "42 * 2"}'
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
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Calculate repeatedly',
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

        // Round 1 (call 1): executes tool
        // Round 2 (call 2): executes tool
        // Round 3 (call 3): guard detects consecutive duplicate (3rd duplicate), strips tools & triggers final conclusion
        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(2));
        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', '已根据计算结果给出最终回答。'));
      });

      test('2.2 Cyclic oscillation detection (period 2 cycle A->B->A->B stripped & conclusion prompt injected)', () async {
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
                    'delta': {'content': '检测到循环后直接给出的综合回答。'}
                  }
                ]
              }
            ]);
          } else {
            // Oscillates between math_eval (odd) and time_calculator (even)
            if (callCount % 2 == 1) {
              return Stream.fromIterable([
                {
                  'choices': [
                    {
                      'delta': {
                        'tool_calls': [
                          {
                            'index': 0,
                            'id': 'call_osc_$callCount',
                            'type': 'function',
                            'function': {
                              'name': 'math_eval',
                              'arguments': '{"expression": "10 + 10"}'
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
                            'id': 'call_osc_$callCount',
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
            }
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Trigger oscillation cycle',
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

        // 1st: math_eval (executed)
        // 2nd: time_calculator (executed)
        // 3rd: math_eval (executed)
        // 4th: time_calculator (blocked by oscillation detector) -> triggers conclusion
        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(3));
        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', '检测到循环后直接给出的综合回答。'));
      });

      test('2.3 Max tool rounds ceiling enforcement (forced conclusion at maxToolRounds - 1)', () async {
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
                    'delta': {'content': '已达轮次上限，最终总结回答。'}
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
                          'id': 'call_round_$callCount',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "$callCount + 100"}'
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
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Test ceiling with maxToolRounds=4',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.test.com',
          apiKey: 'key',
          model: 'test-model',
          messages: messages,
          maxToolRounds: 4,
        ).toList();

        // maxToolRounds = 4:
        // Round 0 (call 1): math_eval (executed)
        // Round 1 (call 2): math_eval (executed)
        // Round 2 (call 3): math_eval (executed)
        // Round 3 (call 4): toolRound >= maxToolRounds - 1 (3 >= 3) -> forced conclusion
        final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
        expect(execEvents, hasLength(4));
        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', '已达轮次上限，最终总结回答。'));
      });
    });

    group('Group 3: Error Resilience & Fault Tolerance', () {
      test('3.1 Tool argument validation failure handled gracefully without crashing', () async {
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
                          'id': 'call_bad_args',
                          'type': 'function',
                          'function': {
                            'name': 'time_calculator',
                            'arguments': '{"invalid_param": "xyz"}'
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
                    'delta': {'content': '参数错误已捕获。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Invalid time call',
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
        expect(toolMsg.content, contains('参数校验失败'));
      });

      test('3.2 Runtime math divide-by-zero handled and reported to model', () async {
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
                          'id': 'call_div_zero',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "100 / 0"}'
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
                    'delta': {'content': '除数为零错误已反馈。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: '100 / 0',
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
        expect(toolMsg.content, contains('除数不能为零'));
      });

      test('3.3 Disabled tool in ToolRegistry returns descriptive Chinese error', () async {
        toolRegistry.setToolEnabled('weather_query', false);

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
                          'id': 'call_disabled',
                          'type': 'function',
                          'function': {
                            'name': 'weather_query',
                            'arguments': '{"city": "Tokyo"}'
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
                    'delta': {'content': '工具禁用提示已捕获。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Query disabled tool',
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
        expect(toolMsg.content, contains('已被禁用'));
      });

      test('3.4 Cancellation token aborts active multi-round tool loop cleanly', () async {
        final cancelToken = CancelToken();

        mockChatService.chatCompletionsStreamHandler = ({
          required String baseUrl,
          required String apiKey,
          required String model,
          required List<ChatMessage> messages,
          List<Map<String, dynamic>>? tools,
          String? reasoningEffort,
          CancelToken? cancelToken,
        }) {
          // Cancel immediately
          cancelToken?.cancel('User stopped execution');
          throw cancelToken?.cancelError ??
              DioException(
                requestOptions: RequestOptions(path: ''),
                type: DioExceptionType.cancel,
              );
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Cancel test',
            timestamp: DateTime.now(),
          ),
        ];

        expect(
          () => agentService.chatAndSearchStream(
            baseUrl: 'https://api.test.com',
            apiKey: 'key',
            model: 'test-model',
            messages: messages,
            cancelToken: cancelToken,
          ).toList(),
          throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
        );
      });
    });

    group('Group 4: Pseudo-XML & DSML Fallback with Basic Tools', () {
      test('4.1 Pseudo-XML <tool_call><function=math_eval>... parsed and executed in follow-up', () async {
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
            // Round 1: Standard tool call to enter follow-up loop
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_init_1',
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
          } else if (callCount == 2) {
            // Round 2: Model outputs pseudo-XML in content
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'content': '<tool_call>\n<function=math_eval>\n<parameter=expression>3 * 7 + 4</parameter>\n</function>\n</tool_call>'
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
                    'delta': {'content': '伪 XML 计算结果为 25。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Calculate via pseudo XML',
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
        final round2ToolMsg = execEvents[1].toolMessages.first;
        expect(round2ToolMsg.content, contains('25'));
        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', '伪 XML 计算结果为 25。'));
      });

      test('4.2 DSML <｜｜DSML｜｜tool_calls> parsed and dispatched to ToolRegistry in follow-up', () async {
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
            // Round 1: Standard tool call to enter loop
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call_init_2',
                          'type': 'function',
                          'function': {
                            'name': 'math_eval',
                            'arguments': '{"expression": "2 + 2"}'
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            ]);
          } else if (callCount == 2) {
            // Round 2: Model outputs DSML format
            return Stream.fromIterable([
              {
                'choices': [
                  {
                    'delta': {
                      'content': '<｜｜DSML｜｜tool_calls>\n'
                          '<｜｜DSML｜｜invoke name="time_calculator">\n'
                          '<｜｜DSML｜｜parameter name="operation">now</｜｜DSML｜｜parameter>\n'
                          '</｜｜DSML｜｜invoke>\n'
                          '</｜｜DSML｜｜tool_calls>'
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
                    'delta': {'content': 'DSML 时间调用已完成。'}
                  }
                ]
              }
            ]);
          }
        };

        final messages = [
          ChatMessage(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: 'user',
            content: 'Calculate time via DSML',
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
        final round2ToolMsg = execEvents[1].toolMessages.first;
        expect(round2ToolMsg.content, contains('当前时间'));
        expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'DSML 时间调用已完成。'));
      });
    });
  });
}
