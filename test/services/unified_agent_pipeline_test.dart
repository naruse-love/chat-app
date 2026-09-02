import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool_call.dart';
import 'package:chat/models/agent_step_telemetry.dart';
import 'package:chat/models/tool/tool_confirmation.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/services/agent_service.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/token_budget_manager.dart';
import 'package:chat/services/agent_fault_tolerance.dart';
import 'package:chat/providers/agent_provider.dart';

class MockChatService extends ChatService {
  Stream<Map<String, dynamic>> Function({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    String? reasoningEffort,
    CancelToken? cancelToken,
  })? streamHandler;

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
    if (streamHandler != null) {
      return streamHandler!(
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
  int searchCalls = 0;
  Future<List<SearchResult>> Function(String query)? onSearch;

  @override
  Future<List<SearchResult>> search({
    required String query,
    String? searxngUrl,
    String searchBackend = 'searxng',
    String? googleApiKey,
    String? googleBaseUrl,
    String? googleSearchModel,
    String? bingCookie,
  }) async {
    searchCalls++;
    if (onSearch != null) {
      return await onSearch!(query);
    }
    return [
      SearchResult(title: 'Search: $query', url: 'https://example.com', content: 'Content for $query'),
    ];
  }
}

void main() {
  group('Milestone 27.2: Unified Agent Pipeline Integration Tests', () {
    late MockChatService mockChatService;
    late MockSearchService mockSearchService;
    late ToolRegistry toolRegistry;
    late AgentService agentService;

    setUp(() {
      mockChatService = MockChatService();
      mockSearchService = MockSearchService();
      toolRegistry = ToolRegistry.defaultRegistry(searchService: mockSearchService);
      agentService = AgentService(
        chatService: mockChatService,
        searchService: mockSearchService,
        toolRegistry: toolRegistry,
      );
    });

    test('1. 4-Dimensional Tool Categorization in AgentService', () {
      // 1. 基础实用
      expect(AgentService.categorizeTool('math_eval'), '基础实用');
      expect(AgentService.categorizeTool('time_calculator'), '基础实用');
      expect(AgentService.categorizeTool('weather_query'), '基础实用');
      expect(AgentService.categorizeTool('web_search'), '基础实用');
      expect(AgentService.categorizeTool('google_search'), '基础实用');
      expect(AgentService.categorizeTool('bing_search'), '基础实用');
      expect(AgentService.categorizeTool('url_fetch'), '基础实用');

      // 2. 沙箱与代码
      expect(AgentService.categorizeTool('file_read'), '沙箱与代码');
      expect(AgentService.categorizeTool('file_write'), '沙箱与代码');
      expect(AgentService.categorizeTool('file_list'), '沙箱与代码');
      expect(AgentService.categorizeTool('file_delete'), '沙箱与代码');
      expect(AgentService.categorizeTool('code_eval'), '沙箱与代码');
      expect(AgentService.categorizeTool('clipboard_read'), '沙箱与代码');
      expect(AgentService.categorizeTool('clipboard_write'), '沙箱与代码');

      // 3. 移动原生
      expect(AgentService.categorizeTool('calendar_query_events'), '移动原生');
      expect(AgentService.categorizeTool('calendar_create_event'), '移动原生');
      expect(AgentService.categorizeTool('notification_schedule'), '移动原生');
      expect(AgentService.categorizeTool('notification_cancel'), '移动原生');
      expect(AgentService.categorizeTool('contacts_search'), '移动原生');
      expect(AgentService.categorizeTool('geolocation_get'), '移动原生');
      expect(AgentService.categorizeTool('reverse_geocode'), '移动原生');

      // 4. 动态MCP
      expect(AgentService.categorizeTool('mcp_github_issues'), '动态MCP');
      expect(AgentService.categorizeTool('mcp_postgres_query'), '动态MCP');
      expect(AgentService.categorizeTool('mcp_filesystem_read'), '动态MCP');

      // Default fallback
      expect(AgentService.categorizeTool('custom_unknown_tool'), '基础实用');
    });

    test('2. Pre-flight Token Budget & Sliding Window Compaction in AgentService Loop', () async {
      int completionsCalls = 0;
      List<ChatMessage>? capturedSecondRoundMessages;

      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        completionsCalls++;
        if (completionsCalls == 1) {
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_math',
                      'type': 'function',
                      'function': {
                        'name': 'math_eval',
                        'arguments': '{"expression": "40 + 2"}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        } else {
          capturedSecondRoundMessages = messages;
          yield {
            'choices': [
              {
                'delta': {'content': 'The calculation result is 42.'},
              },
            ],
          };
        }
      };

      // Construct a long history where intermediate tool result exceeds compaction threshold
      final longToolOutput = 'START_${'A' * 2000}_END';
      final history = [
        ChatMessage(
          id: 'msg_u1',
          conversationId: 'c1',
          role: 'user',
          content: 'Initial user query that must be preserved',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'msg_a1',
          conversationId: 'c1',
          role: 'assistant',
          content: 'Calling old tool',
          toolCalls: [
            ToolCall(id: 'old_call_1', type: 'function', functionName: 'web_search', arguments: '{"query":"old"}'),
          ],
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'msg_t1',
          conversationId: 'c1',
          role: 'tool',
          toolCallId: 'old_call_1',
          content: longToolOutput,
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: 'msg_u2',
          conversationId: 'c1',
          role: 'user',
          content: 'Calculate 40 + 2',
          timestamp: DateTime.now(),
        ),
      ];

      // Use a custom TokenBudgetManager with calibrated context cap to trigger compaction
      final customBudgetManager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 8000,
          maxOutputTokens: 500,
          compressionThresholdRatio: 0.20,
          preserveRecentRounds: 0,
          compressedHeadRunes: 50,
          compressedTailRunes: 50,
        ),
      );

      final customAgentService = AgentService(
        chatService: mockChatService,
        searchService: mockSearchService,
        toolRegistry: toolRegistry,
        tokenBudgetManager: customBudgetManager,
      );

      final stream = customAgentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: history,
      );

      final events = await stream.toList();

      // Check that TokenBudgetTelemetryEvent was emitted
      final budgetEvents = events.whereType<TokenBudgetTelemetryEvent>().toList();
      expect(budgetEvents, isNotEmpty);
      final budget = budgetEvents.first.telemetry;
      expect(budget.compressionCount, greaterThanOrEqualTo(1));
      expect(budget.tokensSaved, greaterThan(0));

      // Check that AgentStepTelemetryEvent was emitted for math_eval
      final stepEvents = events.whereType<AgentStepTelemetryEvent>().toList();
      expect(stepEvents, hasLength(1));
      expect(stepEvents.first.telemetry.toolName, 'math_eval');
      expect(stepEvents.first.telemetry.toolCategory, '基础实用');
      expect(stepEvents.first.telemetry.isSuccess, isTrue);

      // Verify that second round messages preserved Message 0 while compressing intermediate tool output
      expect(capturedSecondRoundMessages, isNotNull);
      expect(capturedSecondRoundMessages!.first.content, 'Initial user query that must be preserved');
      final intermediateTool = capturedSecondRoundMessages!.firstWhere((m) => m.id == 'msg_t1');
      expect(intermediateTool.content, contains('[中间执行结果已压缩，关键输出摘要:'));
    });

    test('3. Global Circuit Breaker Strips Tools & Forces Chinese Summary', () async {
      int completionsCalls = 0;
      List<Map<String, dynamic>>? capturedToolsInFinalCall;

      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        completionsCalls++;
        capturedToolsInFinalCall = tools;
        yield {
          'choices': [
            {
              'delta': {'content': '由于会话上下文已达安全上限，以下是最终总结回答。'},
            },
          ],
        };
      };

      final history = [
        ChatMessage(
          id: 'msg_u1',
          conversationId: 'c1',
          role: 'user',
          content: 'Huge payload ${'内容 ' * 2000}',
          timestamp: DateTime.now(),
        ),
      ];

      // Strict budget manager that trips circuit breaker immediately
      final strictBudgetManager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 500,
          maxOutputTokens: 100,
          circuitBreakerThresholdRatio: 0.80,
        ),
      );

      final strictAgentService = AgentService(
        chatService: mockChatService,
        searchService: mockSearchService,
        toolRegistry: toolRegistry,
        tokenBudgetManager: strictBudgetManager,
      );

      final events = await strictAgentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: history,
      ).toList();

      // Check that CircuitBreakerTriggeredEvent was emitted
      final breakerEvents = events.whereType<CircuitBreakerTriggeredEvent>().toList();
      expect(breakerEvents, hasLength(1));
      expect(breakerEvents.first.reason, contains('超出模型安全上限'));

      // Check that tools were stripped in final call
      expect(capturedToolsInFinalCall, isNull);
      expect(completionsCalls, 1);

      // Check final content
      final contentEvents = events.whereType<ContentDeltaEvent>().toList();
      expect(contentEvents.map((e) => e.content).join(), contains('最终总结回答'));
    });

    test('4. Multi-Format Tool Invocations (DeepSeek DSML v2, DSML v1, Qwen XML, Llama 3, Hermes)', () async {
      final formatsToTest = [
        {
          'name': 'DeepSeek DSML v2',
          'content': '<｜tool calls begin｜><｜tool call begin｜>function<｜tool sep｜>math_eval\n```json\n{"expression": "100 * 3"}\n```<｜tool call end｜><｜tool calls end｜>',
          'expectedOutput': '300',
        },
        {
          'name': 'DeepSeek DSML v1 XML',
          'content': '<｜｜DSML｜｜tool_calls><｜｜DSML｜｜invoke name="math_eval"><｜｜DSML｜｜parameter name="expression">50 + 25</｜｜DSML｜｜parameter></｜｜DSML｜｜invoke></｜｜DSML｜｜tool_calls>',
          'expectedOutput': '75',
        },
        {
          'name': 'Qwen XML with JSON',
          'content': '<tool_call>\n{"name": "math_eval", "arguments": {"expression": "20 * 4"}}\n</tool_call>',
          'expectedOutput': '80',
        },
        {
          'name': 'Qwen Tagged XML',
          'content': '<tool_call>\n<function=math_eval>\n<parameter=expression>99 - 9</parameter>\n</function>\n</tool_call>',
          'expectedOutput': '90',
        },
        {
          'name': 'Llama 3 Tool Calls',
          'content': '[TOOL_CALLS] [{"name": "math_eval", "arguments": {"expression": "7 * 8"}}]',
          'expectedOutput': '56',
        },
        {
          'name': 'Hermes Function Call',
          'content': '<functioncall> {"name": "math_eval", "arguments": {"expression": "12 * 12"}} </functioncall>',
          'expectedOutput': '144',
        },
      ];

      for (final format in formatsToTest) {
        int callCount = 0;
        mockChatService.streamHandler = ({
          required String baseUrl,
          required String apiKey,
          required String model,
          required List<ChatMessage> messages,
          List<Map<String, dynamic>>? tools,
          String? reasoningEffort,
          CancelToken? cancelToken,
        }) async* {
          callCount++;
          if (callCount == 1) {
            yield {
              'choices': [
                {
                  'delta': {
                    'content': format['content']!,
                  },
                },
              ],
            };
          } else {
            yield {
              'choices': [
                {
                  'delta': {'content': 'Result is ${format['expectedOutput']}.'},
                },
              ],
            };
          }
        };

        final messages = [
          ChatMessage(
            id: 'u_${format['name']}',
            conversationId: 'c1',
            role: 'user',
            content: 'Calculate using ${format['name']}',
            timestamp: DateTime.now(),
          ),
        ];

        final events = await agentService.chatAndSearchStream(
          baseUrl: 'https://api.example.com',
          apiKey: 'sk-test',
          model: 'test-model',
          messages: messages,
        ).toList();

        final stepEvents = events.whereType<AgentStepTelemetryEvent>().toList();
        expect(stepEvents, hasLength(1), reason: 'Failed for format: ${format['name']}');
        expect(stepEvents.first.telemetry.toolName, 'math_eval');
        expect(stepEvents.first.telemetry.isSuccess, isTrue);
        expect(stepEvents.first.telemetry.fullOutput, contains(format['expectedOutput']!));
      }
    });

    test('5. 8-Glitch JSON Repair in AgentService Argument Decoding', () async {
      int callCount = 0;

      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        callCount++;
        if (callCount == 1) {
          // Send deformed JSON: unquoted keys, single quotes, trailing commas, unclosed bracket
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_deformed',
                      'type': 'function',
                      'function': {
                        'name': 'math_eval',
                        'arguments': "{expression: '50 + 50',",
                      },
                    },
                  ],
                },
              },
            ],
          };
        } else {
          yield {
            'choices': [
              {
                'delta': {'content': 'Answer is 100.'},
              },
            ],
          };
        }
      };

      final messages = [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: 'user',
          content: 'Compute',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: messages,
      ).toList();

      final stepEvents = events.whereType<AgentStepTelemetryEvent>().toList();
      expect(stepEvents, hasLength(1));
      expect(stepEvents.first.telemetry.toolName, 'math_eval');
      expect(stepEvents.first.telemetry.isSuccess, isTrue);
      expect(stepEvents.first.telemetry.fullOutput, contains('100'));
    });

    test('6. Exponential Backoff Retry on Transient Network Errors', () async {
      int searchAttempts = 0;

      mockSearchService.onSearch = (query) async {
        searchAttempts++;
        if (searchAttempts < 3) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionTimeout,
            error: 'Connection timeout',
          );
        }
        return [
          SearchResult(title: 'Recovered Search', url: 'https://recovered.com', content: 'Success after retry'),
        ];
      };

      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        if (messages.length == 1) {
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_retry',
                      'type': 'function',
                      'function': {
                        'name': 'web_search',
                        'arguments': '{"query": "retry test"}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        } else {
          yield {
            'choices': [
              {
                'delta': {'content': 'Final response after retry.'},
              },
            ],
          };
        }
      };

      final customFaultTolerance = AgentFaultTolerance(
        retryPolicy: const RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(milliseconds: 10),
          maxDelay: Duration(milliseconds: 50),
        ),
      );

      final retryAgentService = AgentService(
        chatService: mockChatService,
        searchService: mockSearchService,
        toolRegistry: toolRegistry,
        agentFaultTolerance: customFaultTolerance,
      );

      final messages = [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: 'user',
          content: 'Perform resilient search',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await retryAgentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: messages,
      ).toList();

      expect(searchAttempts, 3); // Retried twice and succeeded on 3rd attempt
      final stepEvents = events.whereType<AgentStepTelemetryEvent>().toList();
      expect(stepEvents, hasLength(1));
      expect(stepEvents.first.telemetry.isSuccess, isTrue);
      expect(stepEvents.first.telemetry.fullOutput, contains('Success after retry'));
    });

    test('7. Tool Failure Generates Structured Chinese Self-Healing Diagnostics for LLM', () async {
      List<ChatMessage>? capturedSecondRoundMessages;

      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        if (messages.length == 1) {
          // Model invokes math_eval with illegal syntax
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_fail',
                      'type': 'function',
                      'function': {
                        'name': 'math_eval',
                        'arguments': '{"expression": "invalid_math_xyz++"}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        } else {
          capturedSecondRoundMessages = messages;
          yield {
            'choices': [
              {
                'delta': {'content': '已根据自愈引导修正计算。'},
              },
            ],
          };
        }
      };

      final messages = [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: 'user',
          content: 'Calculate with error',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: messages,
      ).toList();

      // Check that step telemetry captured the failure
      final stepEvents = events.whereType<AgentStepTelemetryEvent>().toList();
      expect(stepEvents, hasLength(1));
      expect(stepEvents.first.telemetry.isSuccess, isFalse);
      expect(stepEvents.first.telemetry.fullOutput, contains('【工具执行异常与自愈引导】'));

      // Check that in the second round, tool message contains structured Chinese feedback
      expect(capturedSecondRoundMessages, isNotNull);
      final toolMsg = capturedSecondRoundMessages!.firstWhere((m) => m.role == 'tool');
      expect(toolMsg.content, contains('【工具执行异常与自愈引导】'));
      expect(toolMsg.content, contains('调用的工具: `math_eval`'));
      expect(toolMsg.content, contains('修复建议:'));
    });

    test('8. Manual Search (@search) Telemetry and Token Flow', () async {
      mockSearchService.onSearch = (query) async {
        return [
          SearchResult(title: 'Flutter Guide', url: 'https://flutter.dev', content: 'Flutter SDK docs'),
        ];
      };

      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        yield {
          'choices': [
            {
              'delta': {'content': 'Here are the search results for Flutter.'},
            },
          ],
        };
      };

      final messages = [
        ChatMessage(
          id: 'u_search',
          conversationId: 'c1',
          role: 'user',
          content: '@search Flutter state management',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: messages,
      ).toList();

      // Check tool started and completed events
      final startedEvents = events.whereType<ToolCallStartedEvent>().toList();
      expect(startedEvents, isNotEmpty);
      expect(startedEvents.first.query, 'Flutter state management');

      final completedEvents = events.whereType<ToolCallCompletedEvent>().toList();
      expect(completedEvents, isNotEmpty);
      expect(completedEvents.first.results, hasLength(1));

      // Check step telemetry
      final stepEvents = events.whereType<AgentStepTelemetryEvent>().toList();
      expect(stepEvents, hasLength(1));
      expect(stepEvents.first.telemetry.toolName, 'web_search');
      expect(stepEvents.first.telemetry.toolCategory, '基础实用');
      expect(stepEvents.first.telemetry.isSuccess, isTrue);

      // Check final content
      final contentEvents = events.whereType<ContentDeltaEvent>().toList();
      expect(contentEvents.map((e) => e.content).join(), contains('Here are the search results'));
    });

    test('9. Level 2 Tool Confirmation (HITL) Decision Flow in Pipeline', () async {
      // 1. Approved case
      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        if (messages.length == 1) {
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_write',
                      'type': 'function',
                      'function': {
                        'name': 'file_write',
                        'arguments': '{"path": "test.txt", "content": "hello world"}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        } else {
          yield {
            'choices': [
              {
                'delta': {'content': 'File written successfully.'},
              },
            ],
          };
        }
      };

      bool confirmationTriggered = false;
      final eventsApproved = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: [
          ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Write file', timestamp: DateTime.now()),
        ],
        onConfirmTool: (request) async {
          confirmationTriggered = true;
          expect(request.toolName, 'file_write');
          expect(request.securityLevel, ToolSecurityLevel.sensitiveConfirm);
          return ToolConfirmationDecision.approve();
        },
      ).toList();

      expect(confirmationTriggered, isTrue);
      final pendingEvents = eventsApproved.whereType<ToolConfirmationPendingEvent>().toList();
      expect(pendingEvents, hasLength(1));

      // 2. Rejected case
      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        if (messages.length == 1) {
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_write_reject',
                      'type': 'function',
                      'function': {
                        'name': 'file_write',
                        'arguments': '{"path": "secret.txt", "content": "blocked"}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        } else {
          yield {
            'choices': [
              {
                'delta': {'content': 'Understood, file write was rejected.'},
              },
            ],
          };
        }
      };

      final eventsRejected = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: [
          ChatMessage(id: 'u2', conversationId: 'c1', role: 'user', content: 'Write file 2', timestamp: DateTime.now()),
        ],
        onConfirmTool: (request) async {
          return ToolConfirmationDecision.reject('安全受限，禁止写入此目录');
        },
      ).toList();

      final stepEvents = eventsRejected.whereType<AgentStepTelemetryEvent>().toList();
      expect(stepEvents, hasLength(1));
      expect(stepEvents.first.telemetry.isSuccess, isFalse);
      expect(stepEvents.first.telemetry.fullOutput, contains('用户已拒绝'));
    });

    test('10. Multi-Round Chained Tool Execution with Cumulative Step Telemetry', () async {
      int round = 0;

      mockChatService.streamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        String? reasoningEffort,
        CancelToken? cancelToken,
      }) async* {
        round++;
        if (round == 1) {
          // Step 1: math_eval
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_step_1',
                      'type': 'function',
                      'function': {
                        'name': 'math_eval',
                        'arguments': '{"expression": "10 * 10"}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        } else if (round == 2) {
          // Step 2: time_calculator
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_step_2',
                      'type': 'function',
                      'function': {
                        'name': 'time_calculator',
                        'arguments': '{"operation": "now"}',
                      },
                    },
                  ],
                },
              },
            ],
          };
        } else {
          // Final answer
          yield {
            'choices': [
              {
                'delta': {'content': 'Calculated 100 and fetched current time.'},
              },
            ],
          };
        }
      };

      final messages = [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: 'user',
          content: 'Calculate and get time',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        model: 'gpt-4o',
        messages: messages,
      ).toList();

      final stepEvents = events.whereType<AgentStepTelemetryEvent>().toList();
      expect(stepEvents, hasLength(2));

      // Step 1 check
      expect(stepEvents[0].telemetry.stepIndex, 1);
      expect(stepEvents[0].telemetry.toolName, 'math_eval');
      expect(stepEvents[0].telemetry.toolCategory, '基础实用');
      expect(stepEvents[0].telemetry.isSuccess, isTrue);

      // Step 2 check
      expect(stepEvents[1].telemetry.stepIndex, 2);
      expect(stepEvents[1].telemetry.toolName, 'time_calculator');
      expect(stepEvents[1].telemetry.toolCategory, '基础实用');
      expect(stepEvents[1].telemetry.isSuccess, isTrue);
    });

    test('11. Riverpod AgentProvider & AgentState Telemetry Propagation and Lifecycle', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final agentNotifier = container.read(agentProvider.notifier);

      expect(container.read(agentProvider).stepTelemetries, isEmpty);
      expect(container.read(agentProvider).latestTokenBudget, isNull);
      expect(container.read(agentProvider).circuitBreakerReason, isNull);

      // 1. Add step 1 telemetry
      final step1 = AgentStepTelemetry(
        stepIndex: 1,
        toolName: 'math_eval',
        toolCategory: '基础实用',
        durationMs: 15,
        arguments: {'expression': '1+1'},
        fullOutput: '2',
        isSuccess: true,
      );
      agentNotifier.addStepTelemetry(step1);

      // 2. Add step 2 telemetry
      final step2 = AgentStepTelemetry(
        stepIndex: 2,
        toolName: 'file_read',
        toolCategory: '沙箱与代码',
        durationMs: 25,
        arguments: {'path': 'test.txt'},
        fullOutput: 'content',
        isSuccess: true,
      );
      agentNotifier.addStepTelemetry(step2);

      expect(container.read(agentProvider).stepTelemetries, hasLength(2));
      expect(container.read(agentProvider).stepTelemetries[0].toolName, 'math_eval');
      expect(container.read(agentProvider).stepTelemetries[1].toolName, 'file_read');

      // 3. Update token budget
      const budget1 = TokenBudgetTelemetry(
        currentEstimatedTokens: 500,
        budgetCap: 32000,
        usageRatio: 0.015,
        tokensSaved: 120,
        compressionCount: 1,
      );
      agentNotifier.updateTokenBudget(budget1);

      expect(container.read(agentProvider).latestTokenBudget?.currentEstimatedTokens, 500);
      expect(container.read(agentProvider).latestTokenBudget?.tokensSaved, 120);

      // 4. Trigger circuit breaker
      agentNotifier.triggerCircuitBreaker('上下文超限');
      expect(container.read(agentProvider).circuitBreakerReason, '上下文超限');

      // 5. Test clearTransientState: preserves step telemetries & token budget, clears search/fetch
      agentNotifier.startSearch('query');
      expect(container.read(agentProvider).isSearching, isTrue);

      agentNotifier.clearTransientState();
      expect(container.read(agentProvider).isSearching, isFalse);
      expect(container.read(agentProvider).stepTelemetries, hasLength(2));
      expect(container.read(agentProvider).latestTokenBudget, isNotNull);

      // 6. Test clearTelemetry: resets telemetries
      agentNotifier.clearTelemetry();
      expect(container.read(agentProvider).stepTelemetries, isEmpty);
      expect(container.read(agentProvider).latestTokenBudget, isNull);
      expect(container.read(agentProvider).circuitBreakerReason, isNull);
    });
  });
}
