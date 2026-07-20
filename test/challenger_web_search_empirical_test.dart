import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:chat/services/agent_service.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/url_fetch_service.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/providers/agent_provider.dart';
import 'package:chat/screens/home_screen.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/data/message_dao.dart';
import 'package:chat/data/api_config_dao.dart';

class MockChatService extends ChatService {
  dynamic chatCompletionsStreamHandler;

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
      dynamic res;
      try {
        res = (chatCompletionsStreamHandler as Function)(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          tools: tools,
          reasoningEffort: reasoningEffort,
          cancelToken: cancelToken,
        );
      } catch (_) {
        res = (chatCompletionsStreamHandler as Function)(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          tools: tools,
          cancelToken: cancelToken,
        );
      }
      if (res is Stream<Map<String, dynamic>>) {
        return res;
      } else if (res is Stream) {
        return res.cast<Map<String, dynamic>>();
      }
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
    return Future.value([]);
  }
}

class MockUrlFetchService extends UrlFetchService {
  Future<String> Function(String url, {CancelToken? cancelToken})? urlFetchHandler;

  @override
  Future<String> fetchUrlContent(String url, {CancelToken? cancelToken}) {
    if (urlFetchHandler != null) {
      return urlFetchHandler!(url, cancelToken: cancelToken);
    }
    return Future.value('Default content for $url');
  }
}

class MockMessageDao implements MessageDao {
  final List<ChatMessage> storedMessages = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getMessagesForConversation) {
      return Future.value([...storedMessages]);
    }
    if (invocation.memberName == #insert) {
      final msg = invocation.positionalArguments[0] as ChatMessage;
      storedMessages.add(msg);
      return Future.value(1);
    }
    if (invocation.memberName == #clearConversation) {
      storedMessages.clear();
      return Future.value(0);
    }
    return super.noSuchMethod(invocation);
  }
}

class MockApiConfigDao implements ApiConfigDao {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getApiKey) {
      return Future.value('mock-key');
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('Challenger 2 Empirical Verification: Web Search & Stream Tools', () {
    late MockChatService mockChatService;
    late MockSearchService mockSearchService;
    late MockUrlFetchService mockUrlFetchService;
    late AgentService agentService;

    setUp(() {
      mockChatService = MockChatService();
      mockSearchService = MockSearchService();
      mockUrlFetchService = MockUrlFetchService();
      agentService = AgentService(
        chatService: mockChatService,
        searchService: mockSearchService,
        urlFetchService: mockUrlFetchService,
      );
    });

    test('1a. AgentService Standard JSON multi-tool calling (web_search + url_fetch in same turn)', () async {
      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        if (messages.length == 1) {
          // Emit tool_calls for web_search AND url_fetch simultaneously
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_search_1',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "flutter release notes"}'
                        }
                      },
                      {
                        'index': 1,
                        'id': 'call_fetch_1',
                        'type': 'function',
                        'function': {
                          'name': 'url_fetch',
                          'arguments': '{"url": "https://flutter.dev/docs/release"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else {
          // Follow-up API call returns answer based on fetched results
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': 'Based on search and url fetch content...'}
                }
              ]
            }
          ]);
        }
      };

      mockSearchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        expect(query, 'flutter release notes');
        return [SearchResult(title: 'Release Notes', url: 'https://flutter.dev/docs/release', content: 'Flutter 3.29 released')];
      };

      mockUrlFetchService.urlFetchHandler = (url, {cancelToken}) async {
        expect(url, 'https://flutter.dev/docs/release');
        return 'Full HTML Page Content: Flutter 3.29 adds new web search engine features.';
      };

      final messages = [
        ChatMessage(
          id: 'msg_1',
          conversationId: 'conv_1',
          role: 'user',
          content: 'Check latest release and read full page',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.test.com',
        apiKey: 'key',
        model: 'model-1',
        messages: messages,
      ).toList();

      expect(events.any((e) => e is ToolCallStartedEvent && e.query == 'flutter release notes'), isTrue);
      expect(events.any((e) => e is ToolCallCompletedEvent && e.query == 'flutter release notes'), isTrue);
      expect(events.any((e) => e is UrlFetchStartedEvent && e.url == 'https://flutter.dev/docs/release'), isTrue);
      expect(events.any((e) => e is UrlFetchCompletedEvent && e.url == 'https://flutter.dev/docs/release'), isTrue);

      final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(execEvents, hasLength(1));
      final assistantMsg = execEvents.first.assistantMessage;
      final toolMsgs = execEvents.first.toolMessages;

      expect(assistantMsg.toolCalls, hasLength(2));
      expect(assistantMsg.toolCalls![0].functionName, 'web_search');
      expect(assistantMsg.toolCalls![1].functionName, 'url_fetch');

      expect(toolMsgs, hasLength(2));
      expect(toolMsgs[0].toolCallId, 'call_search_1');
      expect(toolMsgs[0].content, contains('Release Notes'));
      expect(toolMsgs[1].toolCallId, 'call_fetch_1');
      expect(toolMsgs[1].content, contains('Full HTML Page Content'));

      expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Based on search and url fetch content...'));
    });

    test('1b. AgentService Pseudo-XML fallback multi-tool calling in follow-up loops (url_fetch + web_search)', () async {
      int apiCallCount = 0;
      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        apiCallCount++;
        if (apiCallCount == 1) {
          // Round 1: standard tool_calls to enter follow-up loop
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call_init',
                        'type': 'function',
                        'function': {
                          'name': 'web_search',
                          'arguments': '{"query": "initial search"}'
                        }
                      }
                    ]
                  }
                }
              ]
            }
          ]);
        } else if (apiCallCount == 2) {
          // Round 2 (follow-up loop): return pseudo-XML tool call for url_fetch
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': '<tool_call>\n<function=url_fetch>\n<parameter=url>https://example.com/details</parameter>\n</function>\n</tool_call>'
                  }
                }
              ]
            }
          ]);
        } else if (apiCallCount == 3) {
          // Round 3 (follow-up loop): return pseudo-XML tool call for web_search
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {
                    'content': '<tool_call>\n<function=web_search>\n<parameter=query>secondary query</parameter>\n</function>\n</tool_call>'
                  }
                }
              ]
            }
          ]);
        } else {
          // Round 4: return final answer text
          return Stream.fromIterable([
            {
              'choices': [
                {
                  'delta': {'content': 'Final answer after initial search and pseudo-XML fetch/search.'}
                }
              ]
            }
          ]);
        }
      };

      mockUrlFetchService.urlFetchHandler = (url, {cancelToken}) async {
        expect(url, 'https://example.com/details');
        return 'Extracted detail text from page';
      };

      mockSearchService.searchHandler = ({
        required String query,
        String? searxngUrl,
        required String searchBackend,
      }) async {
        if (query == 'initial search') {
          return [SearchResult(title: 'Initial Title', url: 'https://init.com', content: 'Init content')];
        } else {
          expect(query, 'secondary query');
          return [SearchResult(title: 'Secondary Title', url: 'https://sec.com', content: 'Sec content')];
        }
      };

      final messages = [
        ChatMessage(
          id: 'msg_2',
          conversationId: 'conv_1',
          role: 'user',
          content: 'Search and read url',
          timestamp: DateTime.now(),
        ),
      ];

      final events = await agentService.chatAndSearchStream(
        baseUrl: 'https://api.test.com',
        apiKey: 'key',
        model: 'model-1',
        messages: messages,
      ).toList();

      expect(apiCallCount, 4);
      expect(events.any((e) => e is UrlFetchStartedEvent && e.url == 'https://example.com/details'), isTrue);
      expect(events.any((e) => e is UrlFetchCompletedEvent && e.url == 'https://example.com/details'), isTrue);
      expect(events.any((e) => e is ToolCallStartedEvent && e.query == 'secondary query'), isTrue);
      expect(events.any((e) => e is ToolCallCompletedEvent && e.query == 'secondary query'), isTrue);

      final execEvents = events.whereType<ToolCallExecutedMessageEvent>().toList();
      expect(execEvents, hasLength(3));

      // Standard initial tool call
      expect(execEvents[0].assistantMessage.toolCalls![0].functionName, 'web_search');
      expect(execEvents[0].assistantMessage.toolCalls![0].id, 'call_init');

      // First pseudo-XML execution: url_fetch
      expect(execEvents[1].assistantMessage.toolCalls![0].functionName, 'url_fetch');
      expect(execEvents[1].toolMessages[0].content, 'Extracted detail text from page');

      // Second pseudo-XML execution: web_search
      expect(execEvents[2].assistantMessage.toolCalls![0].functionName, 'web_search');
      expect(execEvents[2].toolMessages[0].content, contains('Secondary Title'));

      expect(events.last, isA<ContentDeltaEvent>().having((e) => e.content, 'content', 'Final answer after initial search and pseudo-XML fetch/search.'));
    });

    test('2. Search result context prompt formatting verification', () {
      final searchService = SearchService();

      final results = [
        SearchResult(
          title: 'Dart Overview',
          url: 'https://dart.dev/overview',
          content: 'Dart is a client-optimized language.',
        ),
        SearchResult(
          title: 'Flutter Framework',
          url: 'https://flutter.dev',
          content: 'Flutter transforms the app development process.',
        ),
      ];

      final formattedContext = searchService.formatSearchResultsForContext(results);

      // Verify that instructions are removed
      expect(formattedContext, isNot(contains('以下是网络搜索结果。')));
      expect(formattedContext, isNot(contains('如果需要更详细的信息')));
      expect(formattedContext, isNot(contains('回答时请引用来源 URL。')));

      // Verify numbering format 1. [Title](URL)
      expect(formattedContext, contains('1. [Dart Overview](https://dart.dev/overview)'));
      expect(formattedContext, contains('   摘要: Dart is a client-optimized language.'));
      expect(formattedContext, contains('2. [Flutter Framework](https://flutter.dev)'));
      expect(formattedContext, contains('   摘要: Flutter transforms the app development process.'));

      // Empty search results check
      final emptyContext = searchService.formatSearchResultsForContext([]);
      expect(emptyContext, '未找到相关网络搜索结果。');
    });

    testWidgets('3a. UI status card rendering for "正在搜索: [Query]..."', (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          apiConfigProvider.overrideWith((ref) => ApiConfigNotifier(MockApiConfigDao())),
        ],
      );

      // Set active agent state: searching
      container.read(agentProvider.notifier).startSearch('flutter Riverpod');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('正在搜索: "flutter Riverpod"...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('3b. UI status card rendering for "正在读取网页: [URL]..."', (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          apiConfigProvider.overrideWith((ref) => ApiConfigNotifier(MockApiConfigDao())),
        ],
      );

      // Set active agent state: url fetching
      container.read(agentProvider.notifier).startUrlFetch('https://flutter.dev/docs');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('正在读取网页: https://flutter.dev/docs...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
