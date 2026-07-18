import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/services/agent_service.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/models/chat_message.dart';

class MockChatService extends ChatService {
  Stream<Map<String, dynamic>> Function({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  })? chatCompletionsStreamHandler;

  @override
  Stream<Map<String, dynamic>> chatCompletionsStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  }) {
    if (chatCompletionsStreamHandler != null) {
      return chatCompletionsStreamHandler!(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
        tools: tools,
        cancelToken: cancelToken,
      );
    }
    return const Stream.empty();
  }
}

class MockSearchService extends SearchService {
  int searchCallCount = 0;
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
  }) {
    searchCallCount++;
    if (searchHandler != null) {
      return searchHandler!(
        query: query,
        searxngUrl: searxngUrl,
        searchBackend: searchBackend,
      );
    }
    return Future.value([]);
  }
}

void main() {
  group('AgentService Tests', () {
    test('Standard Streaming Chat (No Tool Call)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {'content': 'Hello'}
              }
            ]
          },
          {
            'choices': [
              {
                'delta': {'content': ' world!'}
              }
            ]
          }
        ]);
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      );

      final events = await stream.toList();

      expect(events, hasLength(2));
      expect(events[0], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Hello'));
      expect(events[1], isA<ContentDeltaEvent>().having((e) => e.content, 'content', ' world!'));
      expect(searchService.searchCallCount, 0);
    });

    test('System Prompt is injected as first system message and replaces existing system messages', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      List<ChatMessage>? capturedMessages;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        capturedMessages = messages;
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {'content': 'OK'}
              }
            ]
          }
        ]);
      };

      // Messages already contain an old system message
      final messages = [
        ChatMessage(
          id: 'sys_old',
          conversationId: 'c1',
          role: 'system',
          content: 'Old system prompt',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
        systemPrompt: 'New system prompt',
      );

      await stream.toList();

      // First message should be the new system prompt with appended date/time
      expect(capturedMessages!.first.role, 'system');
      expect(capturedMessages!.first.content, startsWith('New system prompt'));
      expect(capturedMessages!.first.content, contains('当前日期与时间:'));
      // Old system message should be removed (replaced)
      expect(capturedMessages!.where((m) => m.role == 'system'), hasLength(1));
      // User message should still be there
      expect(capturedMessages!.last.role, 'user');
      expect(capturedMessages!.last.content, 'Hi');
    });

    test('System Prompt is null, no injection happens', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      List<ChatMessage>? capturedMessages;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        capturedMessages = messages;
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {'content': 'OK'}
              }
            ]
          }
        ]);
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      );

      await stream.toList();

      expect(capturedMessages, isNotNull);
      expect(capturedMessages!.length, 1);
      expect(capturedMessages!.first.role, 'user');
    });

    test('Automatic Tool Calling (Search Execution & Follow-up Chat)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int completionsCallCount = 0;
      late List<ChatMessage> secondCallMessages;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        completionsCallCount++;
        if (completionsCallCount == 1) {
          expect(tools, isNotNull);
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_abc',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query":'
                        }
                      }
                    ]
                  }
                }
              ]
            },
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'function': {
                          'arguments': '"flutter agent"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else {
          expect(tools, isNotNull);
          secondCallMessages = messages;
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': 'Search shows'}
                }
              ]
            },
            {
              'choices': [
                {
                  'delta': {'content': ' that...'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        expect(query, 'flutter agent');
        return [SearchResult(title: 'Flutter Agent', url: 'https://flutter.dev', content: 'Agent details')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Search for flutter agent',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      );

      final events = await stream.toList();

      // Follow-up content is buffered and yielded as a single event when tools are active
      expect(events, hasLength(4));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'flutter agent'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'flutter agent'));

      final execEvent = events[2] as ToolCallExecutedMessageEvent;
      expect(execEvent.assistantMessage.role, 'assistant');
      expect(execEvent.assistantMessage.toolCalls, hasLength(1));
      expect(execEvent.assistantMessage.toolCalls![0].id, 'call_abc');
      expect(execEvent.assistantMessage.toolCalls![0].functionName, 'web_search');
      expect(execEvent.assistantMessage.toolCalls![0].arguments, '{"query":"flutter agent"}');

      expect(execEvent.toolMessages, hasLength(1));
      expect(execEvent.toolMessages[0].role, 'tool');
      expect(execEvent.toolMessages[0].toolCallId, 'call_abc');
      expect(execEvent.toolMessages[0].content, contains('Flutter Agent'));

      // Content is buffered into a single event when tools are active
      expect(events[3], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Search shows that...'));

      expect(completionsCallCount, 2);
      expect(secondCallMessages, hasLength(3));
      expect(secondCallMessages[0].content, 'Search for flutter agent');
      expect(secondCallMessages[1], execEvent.assistantMessage);
      expect(secondCallMessages[2], execEvent.toolMessages[0]);
    });

    test('Manual Trigger with @search Prefix', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int completionsCallCount = 0;
      late List<ChatMessage> chatMessages;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        completionsCallCount++;
        expect(tools, isNotNull);
        chatMessages = messages;
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {'content': 'Manual search reply'}
              }
            ]
          }
        ]);
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        expect(query, 'flutter components');
        return [SearchResult(title: 'Components', url: 'https://flutter.dev', content: 'Flutter UI components')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: '@search flutter components',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      );

      final events = await stream.toList();

      expect(events, hasLength(4));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'flutter components'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'flutter components'));

      final execEvent = events[2] as ToolCallExecutedMessageEvent;
      expect(execEvent.assistantMessage.role, 'assistant');
      expect(execEvent.assistantMessage.toolCalls, hasLength(1));
      expect(execEvent.assistantMessage.toolCalls![0].functionName, 'web_search');
      expect(execEvent.assistantMessage.toolCalls![0].arguments, contains('flutter components'));

      expect(execEvent.toolMessages, hasLength(1));
      expect(execEvent.toolMessages[0].role, 'tool');
      expect(execEvent.toolMessages[0].content, contains('Components'));

      expect(events[3], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Manual search reply'));

      expect(completionsCallCount, 1);
      expect(chatMessages, hasLength(3));
      expect(chatMessages[0].content, 'flutter components');
      expect(chatMessages[1], execEvent.assistantMessage);
      expect(chatMessages[2], execEvent.toolMessages[0]);
    });

    test('SearchException is caught and returns Chinese error message (manual search)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.fromIterable([
          {'choices': [{'delta': {'content': 'Reply'}}]}
        ]);
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        throw SearchException(message: '拒绝了 JSON 格式', source: 'MockSearch');
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: '@search test error',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      );

      final events = await stream.toList();
      final execEvent = events[2] as ToolCallExecutedMessageEvent;
      expect(execEvent.toolMessages[0].content, '搜索失败：拒绝了 JSON 格式');
    });

    test('SearchException is caught and returns Chinese error message (auto tool call)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_err',
                      'function': {
                        'name': 'web_search',
                        'arguments': '{"query": "error test"}'
                      }
                    }
                  ]
                }
              }
            ]
          }
        ]);
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        throw SearchException(message: '网络连接超时', source: 'MockSearch');
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Search for error',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      );

      final events = await stream.toList();
      final execEvent = events[2] as ToolCallExecutedMessageEvent;
      // Tool message content should contain the search error
      expect(execEvent.toolMessages[0].content, '搜索失败：网络连接超时');
    });

    test('Cancellation propagation (Dio cancellation)', () async {
      final cancelToken = CancelToken();
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      final controller = StreamController<Map<String, dynamic>>();

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        cancelToken?.whenCancel.then((_) {
          if (!controller.isClosed) {
            controller.addError(DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.cancel,
              error: 'User requested cancellation',
            ));
          }
        });
        controller.add({
          'choices': [
            {
              'delta': {'content': 'Hello'}
            }
          ]
        });
        return controller.stream;
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
        cancelToken: cancelToken,
      );

      final events = <AgentStreamEvent>[];
      final completer = Completer<void>();

      stream.listen(
        (event) {
          events.add(event);
          cancelToken.cancel();
        },
        onError: (e) {
          completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await expectLater(
        completer.future,
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
      );

      await controller.close();
    });

    test('Cancellation during search execution', () async {
      final cancelToken = CancelToken();
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int firstCompletionsCallCount = 0;
      int secondCompletionsCallCount = 0;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        if (tools != null) {
          firstCompletionsCallCount++;
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_abc',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "flutter"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else {
          secondCompletionsCallCount++;
          return const Stream.empty();
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        cancelToken.cancel();
        await Future.delayed(const Duration(milliseconds: 10));
        return [SearchResult(title: 'Flutter', url: 'https://flutter.dev', content: 'Flutter info')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
        cancelToken: cancelToken,
      );

      final completer = Completer<void>();
      final events = <AgentStreamEvent>[];

      stream.listen(
        (event) {
          events.add(event);
        },
        onError: (e) {
          completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await expectLater(
        completer.future,
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
      );

      expect(firstCompletionsCallCount, 1);
      expect(secondCompletionsCallCount, 0);
    });

    test('Malformed Tool Call Arguments - Incomplete JSON', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int callCount = 0;
      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
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
                        'id': 'call_abc',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "flutter'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else {
          // Follow-up returns content to avoid infinite loop
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': 'Follow-up response'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        // Query falls back to raw buffer since JSON is incomplete
        expect(query, '{"query": "flutter');
        return [SearchResult(title: 'Flutter', url: 'https://flutter.dev', content: 'Flutter info')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      // Follow-up content is buffered as a single event when tools are active
      expect(events, hasLength(4));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', '{"query": "flutter'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', '{"query": "flutter'));
      expect(events[2], isA<ToolCallExecutedMessageEvent>());
      expect(events[3], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Follow-up response'));
    });

    test('Malformed Tool Call Arguments - Invalid Type (TypeError)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int callCount = 0;
      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
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
                        'id': 'call_abc',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": 123}'
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
                  'delta': {'content': 'Follow-up response'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        // TypeError falls back to raw buffer
        expect(query, '{"query": 123}');
        return [];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      expect(events, hasLength(4));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', '{"query": 123}'));
      expect(events[3], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Follow-up response'));
    });

    test('Malformed Tool Call Arguments - Missing Query Property', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int callCount = 0;
      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
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
                        'id': 'call_abc',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{}'
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
                  'delta': {'content': 'Follow-up response'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        // Decodes successfully, query is null, falls back to ''
        expect(query, '');
        return [];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Hi',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      expect(events, hasLength(4));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', ''));
      expect(events[3], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Follow-up response'));
    });

    test('Immediate Cancellation - Before Listening (Manual)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      final cancelToken = CancelToken()..cancel();

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: '@search flutter',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
        cancelToken: cancelToken,
      );

      await expectLater(
        stream.toList(),
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
      );
    });

    test('Cancellation During Search - Auto Search Flow', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);
      final cancelToken = CancelToken();

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_abc',
                      'type': 'function',
                      'function': {
                        'name': 'web_search',
                        'arguments': '{"query": "flutter"}'
                      }
                    }
                  ]
                }
              }
            ]
          }
        ]);
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        cancelToken.cancel(); // cancel during search execution
        return [SearchResult(title: 'Flutter', url: 'https://flutter.dev', content: 'Flutter info')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Search for flutter',
          timestamp: DateTime.now(),
        ),
      ];

      final stream = agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
        cancelToken: cancelToken,
      );

      final completer = Completer<void>();
      final events = <AgentStreamEvent>[];

      stream.listen(
        (event) {
          events.add(event);
        },
        onError: (e) {
          completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await expectLater(
        completer.future,
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
      );

      // ToolCallStartedEvent is yielded before search.
      // ToolCallCompletedEvent is NOT yielded because cancellation is checked immediately after search returns.
      expect(events, hasLength(1));
      expect(events[0], isA<ToolCallStartedEvent>());
    });

    test('Empty Messages List', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: [],
      ).toList();

      expect(events, isEmpty);
    });

    test('Last Message Content Empty', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {'content': 'Response to empty content'}
              }
            ]
          }
        ]);
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: '',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      expect(events, hasLength(1));
      expect(events[0], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Response to empty content'));
    });

    test('Concurrency - Running Multiple Streams in Parallel', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      // We'll configure handlers to simulate latency and verify results stay separate
      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) async* {
        final query = messages.last.content;
        await Future.delayed(Duration(milliseconds: (10 + (query.hashCode % 50))));
        yield {
          'choices': [
            {
              'delta': {'content': 'Response for: $query'}
            }
          ]
        };
      };

      final futures = List.generate(10, (index) async {
        final messages = [
          ChatMessage(
            id: 'id_$index',
            conversationId: 'conv_$index',
            role: 'user',
            content: 'Query $index',
            timestamp: DateTime.now(),
          ),
        ];
        final events = await agentService.chatAndSearchStream(
          baseUrl: 'http://api.com',
          apiKey: 'key',
          model: 'model',
          messages: messages,
        ).toList();

        expect(events, hasLength(1));
        expect(
          events[0],
          isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Response for: Query $index'),
        );
      });

      await Future.wait(futures);
    });

    test('Reasoning and Content preserved in Assistant Message before Tool Call', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int completionsCallCount = 0;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        completionsCallCount++;
        if (completionsCallCount == 1) {
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'reasoning_content': 'Thinking about the best approach...',
                  }
                }
              ]
            },
            {
              'choices': [
                {
                  'delta': {
                    'content': 'I will search for the weather.',
                  }
                }
              ]
            },
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_weather',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "weather today"}'
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
                  'delta': {'content': 'The weather is sunny.'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        return [SearchResult(title: 'Weather', url: 'https://weather.com', content: 'Sunny')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'What is the weather today?',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      expect(events, hasLength(6));
      expect(events[0], isA<ReasoningDeltaEvent>().having((e) => e.reasoning, 'reasoning', 'Thinking about the best approach...'));
      expect(events[1], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'I will search for the weather.'));
      expect(events[2], isA<ToolCallStartedEvent>());
      expect(events[3], isA<ToolCallCompletedEvent>());
      
      final execEvent = events[4] as ToolCallExecutedMessageEvent;
      expect(execEvent.assistantMessage.reasoningContent, 'Thinking about the best approach...');
      expect(execEvent.assistantMessage.content, 'I will search for the weather.');
      expect(execEvent.assistantMessage.toolCalls, hasLength(1));
      expect(execEvent.assistantMessage.toolCalls![0].id, 'call_weather');
      
      expect(execEvent.toolMessages, hasLength(1));
      expect(execEvent.toolMessages[0].content, contains('Sunny'));
      expect(events[5], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'The weather is sunny.'));
    });

    test('Parallel/Multiple Tool Calling (Multiple Search Execution)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int completionsCallCount = 0;
      late List<ChatMessage> secondCallMessages;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        completionsCallCount++;
        if (completionsCallCount == 1) {
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "flutter docs"}'
                        }
                      },
                      {
                        'index': 1,
                        'id': 'call_2',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "dart docs"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else {
          secondCallMessages = messages;
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': 'Results found.'}
                }
              ]
            }
          ]);
        }
      };

      final queriesSearched = <String>[];
      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        queriesSearched.add(query);
        if (query == 'flutter docs') {
          return [SearchResult(title: 'Flutter Documentation', url: 'https://docs.flutter.dev', content: 'Flutter info')];
        } else {
          return [SearchResult(title: 'Dart Documentation', url: 'https://dart.dev', content: 'Dart info')];
        }
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Search both flutter and dart docs',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      expect(events, hasLength(6));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'flutter docs'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'flutter docs'));
      expect(events[2], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'dart docs'));
      expect(events[3], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'dart docs'));

      final execEvent = events[4] as ToolCallExecutedMessageEvent;
      expect(execEvent.assistantMessage.role, 'assistant');
      expect(execEvent.assistantMessage.toolCalls, hasLength(2));
      expect(execEvent.assistantMessage.toolCalls![0].id, 'call_1');
      expect(execEvent.assistantMessage.toolCalls![0].arguments, '{"query": "flutter docs"}');
      expect(execEvent.assistantMessage.toolCalls![1].id, 'call_2');
      expect(execEvent.assistantMessage.toolCalls![1].arguments, '{"query": "dart docs"}');

      expect(execEvent.toolMessages, hasLength(2));
      expect(execEvent.toolMessages[0].toolCallId, 'call_1');
      expect(execEvent.toolMessages[0].content, contains('Flutter Documentation'));
      expect(execEvent.toolMessages[1].toolCallId, 'call_2');
      expect(execEvent.toolMessages[1].content, contains('Dart Documentation'));

      expect(events[5], isA<ContentDeltaEvent>());

      expect(completionsCallCount, 2);
      expect(secondCallMessages, hasLength(4));
      expect(secondCallMessages[0].content, 'Search both flutter and dart docs');
      expect(secondCallMessages[1], execEvent.assistantMessage);
      expect(secondCallMessages[2], execEvent.toolMessages[0]);
      expect(secondCallMessages[3], execEvent.toolMessages[1]);
    });

    test('Empty manual search query throws ArgumentError', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      final messages1 = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: '@search',
          timestamp: DateTime.now(),
        ),
      ];

      expect(
        () => agentService.chatAndSearchStream(
          baseUrl: 'http://api.com',
          apiKey: 'key',
          model: 'model',
          messages: messages1,
        ).toList(),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', 'Search query cannot be empty')),
      );

      final messages2 = [
        ChatMessage(
          id: '2',
          conversationId: 'c1',
          role: 'user',
          content: '@search   ',
          timestamp: DateTime.now(),
        ),
      ];

      expect(
        () => agentService.chatAndSearchStream(
          baseUrl: 'http://api.com',
          apiKey: 'key',
          model: 'model',
          messages: messages2,
        ).toList(),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', 'Search query cannot be empty')),
      );
    });

    test('SearchException is caught and returns Chinese empty results message (manual search)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {'content': '搜索失败后的回复'}
              }
            ]
          }
        ]);
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        throw SearchException(
          source: 'SearXNG',
          statusCode: 403,
          message: 'SearXNG 拒绝了 JSON 接口（HTTP 403）。请在服务器 settings.yml 中启用 formats 的 json。',
        );
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: '@search flutter',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      // Should produce ToolCallStarted, ToolCallCompleted, ToolCallExecutedMessage, then streaming
      expect(events, hasLength(4));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'flutter'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'flutter'));

      final execEvent = events[2] as ToolCallExecutedMessageEvent;
      // Tool message content should contain the search error
      expect(execEvent.toolMessages[0].content, '搜索失败：SearXNG 拒绝了 JSON 接口（HTTP 403）。请在服务器 settings.yml 中启用 formats 的 json。');

      expect(events[3], isA<ContentDeltaEvent>().having((e) => e.content, 'content', '搜索失败后的回复'));
    });

    test('SearchException is caught and returns Chinese empty results message (auto tool call)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int callCount = 0;
      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        callCount++;
        if (callCount == 1) {
          // First call: tool calls triggered
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_abc',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query":"flutter"}'
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
                  'delta': {'content': 'Follow-up response'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        throw SearchException(
          source: 'SearXNG',
          statusCode: 403,
          message: 'SearXNG 拒绝了 JSON 接口（HTTP 403）。',
        );
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: '搜索一下',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      expect(events, hasLength(4));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'flutter'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'flutter'));

      final execEvent = events[2] as ToolCallExecutedMessageEvent;
      // Tool message content should contain the search error
      expect(execEvent.toolMessages[0].content, '搜索失败：SearXNG 拒绝了 JSON 接口（HTTP 403）。');
      expect(events[3], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Follow-up response'));
    });

    test('Multi-round tool calling (standard tool_calls in follow-up)', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int completionsCallCount = 0;
      int searchCallCount = 0;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        completionsCallCount++;
        // Every round has tools passed
        expect(tools, isNotNull);
        if (completionsCallCount <= 2) {
          // Round 1 and 2: return tool_calls
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_$completionsCallCount',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "round $completionsCallCount search"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else {
          // Round 3: return final content
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': 'Final answer after two searches.'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        searchCallCount++;
        return [SearchResult(title: 'Result $searchCallCount', url: 'https://example.com', content: 'Content for $query')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Search multiple times',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      // Expect: ToolCallStarted(1), ToolCallCompleted(1), ToolCallExecutedMessage(1),
      //         ToolCallStarted(2), ToolCallCompleted(2), ToolCallExecutedMessage(2),
      //         ContentDelta (final answer)
      // = 7 events
      expect(events, hasLength(7));

      // First round
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'round 1 search'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'round 1 search'));
      expect(events[2], isA<ToolCallExecutedMessageEvent>());
      final exec1 = events[2] as ToolCallExecutedMessageEvent;
      expect(exec1.assistantMessage.toolCalls, hasLength(1));
      expect(exec1.assistantMessage.toolCalls![0].id, 'call_1');

      // Second round
      expect(events[3], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'round 2 search'));
      expect(events[4], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'round 2 search'));
      expect(events[5], isA<ToolCallExecutedMessageEvent>());
      final exec2 = events[5] as ToolCallExecutedMessageEvent;
      expect(exec2.assistantMessage.toolCalls, hasLength(1));
      expect(exec2.assistantMessage.toolCalls![0].id, 'call_2');

      // Final content
      expect(events[6], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Final answer after two searches.'));

      expect(completionsCallCount, 3);
      expect(searchCallCount, 2);
    });

    test('Pseudo-XML tool_call fallback in follow-up', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int completionsCallCount = 0;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        completionsCallCount++;
        if (completionsCallCount == 1) {
          // First call: auto-tool with proper tool_calls
          expect(tools, isNotNull);
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_first',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "first search"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else if (completionsCallCount == 2) {
          // Second call: model outputs pseudo-XML instead of proper tool_calls (with tools still passed)
          expect(tools, isNotNull);
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': '<tool_call>\n<function=web_search>\n<parameter=query>second search from XML</parameter>\n</function>\n</tool_call>'
                  }
                }
              ]
            }
          ]);
        } else {
          // Third call: final content
          expect(tools, isNotNull);
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': 'Final answer after pseudo-XML fallback.'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        return [SearchResult(title: 'Search Result', url: 'https://example.com', content: 'Content for $query')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Search something',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      // Events (pseudo-XML content is NOT yielded as ContentDeltaEvent because tools are active):
      // 0: ToolCallStarted (first search)
      // 1: ToolCallCompleted (first search)
      // 2: ToolCallExecutedMessage (first)
      // 3: ToolCallStarted (pseudo-XML search)
      // 4: ToolCallCompleted (pseudo-XML search)
      // 5: ToolCallExecutedMessage (pseudo-XML)
      // 6: ContentDelta (final answer)
      expect(events, hasLength(7));

      // First round: standard tool_calls
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'first search'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'first search'));
      expect(events[2], isA<ToolCallExecutedMessageEvent>());
      final exec1 = events[2] as ToolCallExecutedMessageEvent;
      expect(exec1.assistantMessage.toolCalls![0].id, 'call_first');

      // Second round: pseudo-XML detected and executed (no ContentDeltaEvent for the XML)
      expect(events[3], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'second search from XML'));
      expect(events[4], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'second search from XML'));
      expect(events[5], isA<ToolCallExecutedMessageEvent>());
      final exec2 = events[5] as ToolCallExecutedMessageEvent;
      // The assistant message should have cleaned content (empty since only XML was output)
      expect(exec2.assistantMessage.content, isEmpty);
      // Should have a pseudo-XML generated tool call
      expect(exec2.assistantMessage.toolCalls, hasLength(1));
      expect(exec2.assistantMessage.toolCalls![0].functionName, 'web_search');
      final parsedArgs = json.decode(exec2.assistantMessage.toolCalls![0].arguments) as Map<String, dynamic>;
      expect(parsedArgs['query'], 'second search from XML');
      expect(exec2.assistantMessage.toolCalls![0].id, startsWith('pseudo_'));

      // Third round: final content
      expect(events[6], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Final answer after pseudo-XML fallback.'));

      expect(completionsCallCount, 3);
    });

    test('Pseudo-XML tool_call with multiple blocks and mixed content', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int completionsCallCount = 0;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        completionsCallCount++;
        if (completionsCallCount == 1) {
          // First call: auto-tool
          expect(tools, isNotNull);
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_first',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "initial query"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else if (completionsCallCount == 2) {
          // Second call: mixed content with pseudo-XML
          expect(tools, isNotNull);
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': 'Let me search for that. <tool_call>\n<function=web_search>\n<parameter=query>specific topic</parameter>\n</function>\n</tool_call>'
                  }
                }
              ]
            }
          ]);
        } else {
          // Third call: final answer
          expect(tools, isNotNull);
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': 'Here is the answer about specific topic.'}
                }
              ]
            }
          ]);
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        return [SearchResult(title: 'Result', url: 'https://example.com', content: 'Details for $query')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Find info',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      expect(events, hasLength(7));

      // First round
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'initial query'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'initial query'));
      expect(events[2], isA<ToolCallExecutedMessageEvent>());

      // Second round: pseudo-XML with mixed content (no ContentDeltaEvent for the XML because tools are active)
      expect(events[3], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'specific topic'));
      expect(events[4], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'specific topic'));
      expect(events[5], isA<ToolCallExecutedMessageEvent>());
      final exec2 = events[5] as ToolCallExecutedMessageEvent;
      // Assistant content should have the XML stripped, leaving only "Let me search for that."
      expect(exec2.assistantMessage.content, 'Let me search for that.');
      expect(exec2.assistantMessage.toolCalls, hasLength(1));
      expect(exec2.assistantMessage.toolCalls![0].functionName, 'web_search');

      // Third round: final content
      expect(events[6], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Here is the answer about specific topic.'));
      expect(completionsCallCount, 3);
    });

    test('Max tool rounds (10) prevents infinite loop', () async {
      final chatService = MockChatService();
      final searchService = MockSearchService();
      final agentService = AgentService(chatService: chatService, searchService: searchService);

      int completionsCallCount = 0;

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) async* {
        completionsCallCount++;
        if (tools == null || tools.isEmpty) {
          yield {
            'choices': [
              {
                'delta': {
                  'content': 'Final summary response'
                }
              }
            ]
          };
        } else {
          // Always return tool_calls to test the max rounds limit
          yield {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_$completionsCallCount',
                      'type': 'function',
                      'function': {
                        'name': 'web_search',
                        'arguments': '{"query": "search $completionsCallCount"}'
                      }
                    }
                  ]
                }
              }
            ]
          };
        }
      };

      searchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
        String? googleApiKey,
        String? googleBaseUrl,
      }) async {
        return [SearchResult(title: 'Result', url: 'https://example.com', content: 'Data for $query')];
      };

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c1',
          role: 'user',
          content: 'Search repeatedly',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'http://api.com',
        apiKey: 'key',
        model: 'model',
        messages: messages,
      ).toList();

      // Max 10 total tool rounds: 1 from chatAndSearchStream + 9 from _streamCompletionsLoop
      // Each round yields 3 events (ToolCallStarted, ToolCallCompleted, ToolCallExecutedMessage) -> 30 events
      // plus the 11th final round which yields 1 event (ContentDeltaEvent)
      // Total = 30 + 1 = 31 events
      expect(events, hasLength(31));

      // Check that 10 rounds of tool calls happened
      final toolCallIds = <String>{};
      for (final event in events) {
        if (event is ToolCallExecutedMessageEvent) {
          for (final tc in event.assistantMessage.toolCalls ?? []) {
            toolCallIds.add(tc.id);
          }
        }
      }
      expect(toolCallIds, hasLength(10));

      // Total completions calls: 10 tool rounds + 1 final round = 11 API calls
      expect(completionsCallCount, 11);
    });

    test('parsePseudoXmlToolCalls unit test', () async {
      // Test the static parsing method directly
      // Single tool_call
      final singleResult = AgentService.parsePseudoXmlToolCalls(
        '<tool_call>\n<function=web_search>\n<parameter=query>今日新闻</parameter>\n</function>\n</tool_call>'
      );
      expect(singleResult, hasLength(1));
      expect(singleResult[0]['name'], 'web_search');
      expect((singleResult[0]['params'] as Map)['query'], '今日新闻');

      // Multiple tool_calls
      final multiResult = AgentService.parsePseudoXmlToolCalls(
        '<tool_call>\n<function=web_search>\n<parameter=query>query1</parameter>\n</function>\n</tool_call>\n'
        '<tool_call>\n<function=web_search>\n<parameter=query>query2</parameter>\n</function>\n</tool_call>'
      );
      expect(multiResult, hasLength(2));
      expect(multiResult[0]['name'], 'web_search');
      expect((multiResult[0]['params'] as Map)['query'], 'query1');
      expect(multiResult[1]['name'], 'web_search');
      expect((multiResult[1]['params'] as Map)['query'], 'query2');

      // No match
      final noResult = AgentService.parsePseudoXmlToolCalls('Normal text without XML');
      expect(noResult, isEmpty);

      // stripPseudoXmlToolCalls
      final stripped = AgentService.stripPseudoXmlToolCalls(
        'Some text <tool_call>\n<function=web_search>\n<parameter=query>test</parameter>\n</function>\n</tool_call> more text'
      );
      expect(stripped, 'Some text more text');

      // Empty after stripping
      final emptyStripped = AgentService.stripPseudoXmlToolCalls(
        '<tool_call>\n<function=web_search>\n<parameter=query>test</parameter>\n</function>\n</tool_call>'
      );
      expect(emptyStripped, isEmpty);
    });
  });
}
