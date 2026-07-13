import 'dart:async';
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
    required String baseUrl,
    required String apiKey,
    String? searxngUrl,
  })? searchHandler;

  @override
  Future<List<SearchResult>> search({
    required String query,
    required String baseUrl,
    required String apiKey,
    String? searxngUrl,
  }) {
    searchCallCount++;
    if (searchHandler != null) {
      return searchHandler!(
        query: query,
        baseUrl: baseUrl,
        apiKey: apiKey,
        searxngUrl: searxngUrl,
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
          expect(tools, isNull);
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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

      expect(events, hasLength(5));
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

      expect(events[3], isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Search shows'));
      expect(events[4], isA<ContentDeltaEvent>().having((e) => e.content, 'content', ' that...'));

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
        expect(tools, isNull);
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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
                        'arguments': '{"query": "flutter'
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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

      expect(events, hasLength(3));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', '{"query": "flutter'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', '{"query": "flutter'));
      expect(events[2], isA<ToolCallExecutedMessageEvent>());
    });

    test('Malformed Tool Call Arguments - Invalid Type (TypeError)', () async {
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
      };

      searchService.searchHandler = ({
        required String query,
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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

      expect(events, hasLength(3));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', '{"query": 123}'));
    });

    test('Malformed Tool Call Arguments - Missing Query Property', () async {
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
      };

      searchService.searchHandler = ({
        required String query,
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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

      expect(events, hasLength(3));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', ''));
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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

      chatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
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
      };

      searchService.searchHandler = ({
        required String query,
        required String baseUrl,
        required String apiKey,
        String? searxngUrl,
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

      expect(events, hasLength(3));
      expect(events[0], isA<ToolCallStartedEvent>().having((e) => e.query, 'query', 'flutter'));
      expect(events[1], isA<ToolCallCompletedEvent>().having((e) => e.query, 'query', 'flutter'));

      final execEvent = events[2] as ToolCallExecutedMessageEvent;
      // Tool message content should contain the search error
      expect(execEvent.toolMessages[0].content, '搜索失败：SearXNG 拒绝了 JSON 接口（HTTP 403）。');
    });
  });
}
