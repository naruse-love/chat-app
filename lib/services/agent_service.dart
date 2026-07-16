import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import 'search_service.dart';
import 'chat_service.dart';
import 'url_fetch_service.dart';

/// Base class for all events yielded during agent execution.
abstract class AgentStreamEvent {
  const AgentStreamEvent();
}

/// Yielded when the model emits streaming reasoning text.
class ReasoningDeltaEvent extends AgentStreamEvent {
  final String reasoning;
  const ReasoningDeltaEvent(this.reasoning);
}

/// Yielded when the model emits standard streaming message content.
class ContentDeltaEvent extends AgentStreamEvent {
  final String content;
  const ContentDeltaEvent(this.content);
}

/// Yielded when a tool call has been detected and search starts executing.
class ToolCallStartedEvent extends AgentStreamEvent {
  final String query;
  const ToolCallStartedEvent(this.query);
}

/// Yielded when the search execution has finished and returned results.
class ToolCallCompletedEvent extends AgentStreamEvent {
  final String query;
  final List<SearchResult> results;
  const ToolCallCompletedEvent(this.query, this.results);
}

/// Yielded when url_fetch starts fetching a webpage.
class UrlFetchStartedEvent extends AgentStreamEvent {
  final String url;
  const UrlFetchStartedEvent(this.url);
}

/// Yielded when url_fetch finishes fetching content.
class UrlFetchCompletedEvent extends AgentStreamEvent {
  final String url;
  final String content;
  const UrlFetchCompletedEvent(this.url, this.content);
}

/// Yielded after search/url_fetch results are packaged into assistant/tool messages.
class ToolCallExecutedMessageEvent extends AgentStreamEvent {
  final ChatMessage assistantMessage;
  final List<ChatMessage> toolMessages;
  const ToolCallExecutedMessageEvent(this.assistantMessage, this.toolMessages);
}

/// Yielded when token usage information is available from the API response.
class UsageEvent extends AgentStreamEvent {
  final int promptTokens;
  final int completionTokens;
  const UsageEvent(this.promptTokens, this.completionTokens);
}

class _ToolCallAccumulator {
  String id = '';
  String name = '';
  String type = 'function';
  final StringBuffer argumentsBuffer = StringBuffer();
}

class AgentService {
  final ChatService _chatService;
  final SearchService _searchService;
  final UrlFetchService _urlFetchService;
  final Uuid _uuid;

  AgentService({
    ChatService? chatService,
    SearchService? searchService,
    UrlFetchService? urlFetchService,
  })  : _chatService = chatService ?? ChatService(),
        _searchService = searchService ?? SearchService(),
        _urlFetchService = urlFetchService ?? UrlFetchService(),
        _uuid = const Uuid();

  /// OpenAI-compatible Tool definition for web search.
  static const Map<String, dynamic> webSearchTool = {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': 'Search the web for up-to-date information on a given topic.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The query to search for on the web.',
          },
        },
        'required': ['query'],
      },
    },
  };

  /// OpenAI-compatible Tool definition for fetching full-text webpage content.
  static const Map<String, dynamic> urlFetchTool = {
    'type': 'function',
    'function': {
      'name': 'url_fetch',
      'description': 'Fetch and extract plain text body content from a specified webpage URL.',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'The absolute HTTP or HTTPS URL of the webpage to fetch.',
          },
        },
        'required': ['url'],
      },
    },
  };

  static const List<Map<String, dynamic>> defaultTools = [
    webSearchTool,
    urlFetchTool,
  ];

  /// Regex for matching pseudo-XML tool_call blocks like:
  /// <tool_call>\n<function=web_search>\n<parameter=query>...</parameter>\n</function>\n</tool_call>
  static final RegExp _pseudoXmlToolCallRegex = RegExp(
    r'<tool_call>\s*<function=(\w+)>\s*(?:<parameter=(\w+)>([\s\S]*?)</parameter>\s*)?</function>\s*</tool_call>',
    multiLine: true,
  );

  /// Extracts pseudo-XML tool calls from [content].
  /// Returns a list of maps with 'name' (String) and 'params' (Map<String, String>).
  static List<Map<String, dynamic>> parsePseudoXmlToolCalls(String content) {
    final results = <Map<String, dynamic>>[];
    for (final match in _pseudoXmlToolCallRegex.allMatches(content)) {
      final name = match.group(1) ?? '';
      final paramName = match.group(2) ?? '';
      final paramValue = match.group(3)?.trim() ?? '';
      results.add({
        'name': name,
        'params': {paramName: paramValue},
      });
    }
    return results;
  }

  /// Removes pseudo-XML tool_call blocks from [content].
  static String stripPseudoXmlToolCalls(String content) {
    return content.replaceAll(_pseudoXmlToolCallRegex, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Main entry point coordinating completion streaming, tool execution, and manual trigger.
  Stream<AgentStreamEvent> chatAndSearchStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    String? systemPrompt,
    String? searxngUrl,
    String searchBackend = 'searxng',
    CancelToken? cancelToken,
  }) async* {
    // Inject system prompt if provided (prepend after removing any existing system messages)
    List<ChatMessage> effectiveMessages;
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      final conversationId = messages.isNotEmpty ? messages.first.conversationId : '';
      effectiveMessages = [
        ChatMessage(
          id: _uuid.v4(),
          conversationId: conversationId,
          role: 'system',
          content: systemPrompt,
          timestamp: DateTime.now(),
        ),
        ...messages.where((m) => m.role != 'system'),
      ];
    } else {
      effectiveMessages = messages;
    }

    if (effectiveMessages.isEmpty) return;

    final lastMessage = effectiveMessages.last;
    final isManualSearch = lastMessage.role == 'user' &&
        lastMessage.content.trim().startsWith('@search');

    if (isManualSearch) {
      final query = lastMessage.content.trim().substring(7).trim();
      if (query.isEmpty) {
        throw ArgumentError('Search query cannot be empty');
      }

      _checkCancellation(cancelToken);

      yield ToolCallStartedEvent(query);

      List<SearchResult> results;
      String? searchError;
      try {
        results = await _searchService.search(
          query: query,
          searxngUrl: searxngUrl,
          searchBackend: searchBackend,
        );
      } on SearchException catch (e) {
        results = [];
        searchError = e.message;
        developer.log('Manual search failed: ${e.message}', name: 'AgentService');
      }

      _checkCancellation(cancelToken);

      yield ToolCallCompletedEvent(query, results);

      final formattedResults = searchError != null
          ? '搜索失败：$searchError'
          : _searchService.formatSearchResultsForContext(results);

      final cleanUserMessage = lastMessage.copyWith(content: query);

      final toolCallId = 'manual_search_${DateTime.now().millisecondsSinceEpoch}';

      final assistantMessage = ChatMessage(
        id: _uuid.v4(),
        conversationId: lastMessage.conversationId,
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(
            id: toolCallId,
            type: 'function',
            functionName: 'web_search',
            arguments: json.encode({'query': query}),
          ),
        ],
        timestamp: DateTime.now(),
      );

      final toolMessage = ChatMessage(
        id: _uuid.v4(),
        conversationId: lastMessage.conversationId,
        role: 'tool',
        toolCallId: toolCallId,
        content: formattedResults,
        timestamp: DateTime.now(),
      );

      yield ToolCallExecutedMessageEvent(assistantMessage, [toolMessage]);

      final nextMessages = [
        ...effectiveMessages.sublist(0, effectiveMessages.length - 1),
        cleanUserMessage,
        assistantMessage,
        toolMessage,
      ];

      yield* _streamCompletions(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: nextMessages,
        tools: defaultTools,
        searxngUrl: searxngUrl,
        searchBackend: searchBackend,
        cancelToken: cancelToken,
      );
    } else {
      final accumulatedToolCalls = <int, _ToolCallAccumulator>{};
      final contentBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();

      int? mainPromptTokens;
      int? mainCompletionTokens;

      await for (final chunk in _chatService.chatCompletionsStream(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: effectiveMessages,
        tools: defaultTools,
        cancelToken: cancelToken,
      )) {
        // Capture usage from chunks where choices is empty
        if (chunk.containsKey('usage') && chunk['usage'] is Map) {
          final usage = chunk['usage'] as Map<String, dynamic>;
          mainPromptTokens = usage['prompt_tokens'] as int? ?? usage['promptTokens'] as int?;
          mainCompletionTokens = usage['completion_tokens'] as int? ?? usage['completionTokens'] as int?;
        }

        final choices = chunk['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta != null) {
            final reasoning = delta['reasoning_content'] as String? ?? delta['reasoning'] as String?;
            if (reasoning != null && reasoning.isNotEmpty) {
              reasoningBuffer.write(reasoning);
              yield ReasoningDeltaEvent(reasoning);
            }

            final content = delta['content'] as String?;
            if (content != null && content.isNotEmpty) {
              contentBuffer.write(content);
              yield ContentDeltaEvent(content);
            }

            final toolCalls = delta['tool_calls'] as List<dynamic>?;
            if (toolCalls != null) {
              for (final tc in toolCalls) {
                if (tc is Map<String, dynamic>) {
                  final index = tc['index'] as int? ?? 0;
                  final acc = accumulatedToolCalls.putIfAbsent(index, () => _ToolCallAccumulator());

                  final id = tc['id'] as String?;
                  if (id != null) acc.id = id;

                  final type = tc['type'] as String?;
                  if (type != null) acc.type = type;

                  final functionObj = tc['function'];
                  if (functionObj is Map<String, dynamic>) {
                    final name = functionObj['name'] as String?;
                    if (name != null) acc.name = name;

                    final arguments = functionObj['arguments'] as String?;
                    if (arguments != null) acc.argumentsBuffer.write(arguments);
                  }
                }
              }
            }
          }
        }
      }

      // Yield usage from the first API call if tool calls were not triggered
      if (accumulatedToolCalls.isEmpty &&
          mainPromptTokens != null &&
          mainCompletionTokens != null) {
        yield UsageEvent(mainPromptTokens, mainCompletionTokens);
      }

      if (accumulatedToolCalls.isNotEmpty) {
        final toolMessages = <ChatMessage>[];

        for (final entry in accumulatedToolCalls.values) {
          final conversationId = effectiveMessages.last.conversationId;
          if (entry.name == 'url_fetch') {
            String url = '';
            try {
              final parsedArgs = json.decode(entry.argumentsBuffer.toString()) as Map<String, dynamic>;
              url = parsedArgs['url'] as String? ?? '';
            } catch (_) {
              url = entry.argumentsBuffer.toString();
            }

            _checkCancellation(cancelToken);
            yield UrlFetchStartedEvent(url);
            final content = await _urlFetchService.fetchUrlContent(url, cancelToken: cancelToken);
            _checkCancellation(cancelToken);
            yield UrlFetchCompletedEvent(url, content);

            toolMessages.add(ChatMessage(
              id: _uuid.v4(),
              conversationId: conversationId,
              role: 'tool',
              toolCallId: entry.id,
              content: content,
              timestamp: DateTime.now(),
            ));
          } else {
            String query = '';
            try {
              final parsedArgs = json.decode(entry.argumentsBuffer.toString()) as Map<String, dynamic>;
              query = parsedArgs['query'] as String? ?? '';
            } catch (_) {
              query = entry.argumentsBuffer.toString();
            }

            _checkCancellation(cancelToken);

            yield ToolCallStartedEvent(query);

            List<SearchResult> results;
            String? searchError;
            try {
              results = await _searchService.search(
                query: query,
                searxngUrl: searxngUrl,
                searchBackend: searchBackend,
              );
            } on SearchException catch (e) {
              results = [];
              searchError = e.message;
              developer.log('Auto search failed: ${e.message}', name: 'AgentService');
            }

            _checkCancellation(cancelToken);

            yield ToolCallCompletedEvent(query, results);

            final formattedResults = searchError != null
                ? '搜索失败：$searchError'
                : _searchService.formatSearchResultsForContext(results);

            toolMessages.add(ChatMessage(
              id: _uuid.v4(),
              conversationId: conversationId,
              role: 'tool',
              toolCallId: entry.id,
              content: formattedResults,
              timestamp: DateTime.now(),
            ));
          }
        }

        final conversationId = effectiveMessages.last.conversationId;

        final assistantMessage = ChatMessage(
          id: _uuid.v4(),
          conversationId: conversationId,
          role: 'assistant',
          content: contentBuffer.toString(),
          reasoningContent: reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : null,
          toolCalls: accumulatedToolCalls.values.map((acc) => ToolCall(
            id: acc.id,
            type: acc.type,
            functionName: acc.name,
            arguments: acc.argumentsBuffer.toString(),
          )).toList(),
          timestamp: DateTime.now(),
          promptTokens: mainPromptTokens,
          completionTokens: mainCompletionTokens,
        );

        yield ToolCallExecutedMessageEvent(assistantMessage, toolMessages);

        final nextMessages = [
          ...effectiveMessages,
          assistantMessage,
          ...toolMessages,
        ];

        yield* _streamCompletions(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: nextMessages,
          tools: defaultTools,
          searxngUrl: searxngUrl,
          searchBackend: searchBackend,
          cancelToken: cancelToken,
        );
      }
    }
  }

  /// Follow-up streaming with multi-turn tool calling support.
  /// Accumulates tool_calls, executes searches, and loops up to 5 rounds.
  /// Falls back to pseudo-XML parsing when the model emits XML instead of proper tool_calls.
  Stream<AgentStreamEvent> _streamCompletions({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    String? searxngUrl,
    String searchBackend = 'searxng',
    CancelToken? cancelToken,
  }) async* {
    yield* _streamCompletionsLoop(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      tools: tools ?? defaultTools,
      searxngUrl: searxngUrl,
      searchBackend: searchBackend,
      cancelToken: cancelToken,
      toolRound: 0,
    );
  }

  /// Internal recursive loop that handles one round of streaming + tool execution.
  Stream<AgentStreamEvent> _streamCompletionsLoop({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    String? searxngUrl,
    String searchBackend = 'searxng',
    CancelToken? cancelToken,
    int toolRound = 0,
  }) async* {
    // Max 5 total tool rounds: 1 from chatAndSearchStream + 4 follow-up rounds
    if (toolRound >= 4) {
      int? finalPromptTokens;
      int? finalCompletionTokens;
      await for (final chunk in _chatService.chatCompletionsStream(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
        cancelToken: cancelToken,
      )) {
        if (chunk.containsKey('usage') && chunk['usage'] is Map) {
          final usage = chunk['usage'] as Map<String, dynamic>;
          finalPromptTokens = usage['prompt_tokens'] as int? ?? usage['promptTokens'] as int?;
          finalCompletionTokens = usage['completion_tokens'] as int? ?? usage['completionTokens'] as int?;
        }

        final choices = chunk['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta != null) {
            final reasoning = delta['reasoning_content'] as String? ?? delta['reasoning'] as String?;
            if (reasoning != null && reasoning.isNotEmpty) {
              yield ReasoningDeltaEvent(reasoning);
            }

            final content = delta['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yield ContentDeltaEvent(content);
            }
          }
        }
      }
      if (finalPromptTokens != null && finalCompletionTokens != null) {
        yield UsageEvent(finalPromptTokens, finalCompletionTokens);
      }
      return;
    }

    final accumulatedToolCalls = <int, _ToolCallAccumulator>{};
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    int? promptTokens;
    int? completionTokens;

    await for (final chunk in _chatService.chatCompletionsStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      tools: tools,
      cancelToken: cancelToken,
    )) {
      // Capture usage from chunks where choices is empty
      if (chunk.containsKey('usage') && chunk['usage'] is Map) {
        final usage = chunk['usage'] as Map<String, dynamic>;
        promptTokens = usage['prompt_tokens'] as int? ?? usage['promptTokens'] as int?;
        completionTokens = usage['completion_tokens'] as int? ?? usage['completionTokens'] as int?;
      }

      final choices = chunk['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        if (delta != null) {
          final reasoning = delta['reasoning_content'] as String? ?? delta['reasoning'] as String?;
          if (reasoning != null && reasoning.isNotEmpty) {
            reasoningBuffer.write(reasoning);
            yield ReasoningDeltaEvent(reasoning);
          }

          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            contentBuffer.write(content);
            // Delay yielding content if tools are configured (might be pseudo-XML to strip)
            if (tools == null || tools.isEmpty) {
              yield ContentDeltaEvent(content);
            }
          }

          final toolCalls = delta['tool_calls'] as List<dynamic>?;
          if (toolCalls != null) {
            for (final tc in toolCalls) {
              if (tc is Map<String, dynamic>) {
                final index = tc['index'] as int? ?? 0;
                final acc = accumulatedToolCalls.putIfAbsent(index, () => _ToolCallAccumulator());

                final id = tc['id'] as String?;
                if (id != null) acc.id = id;

                final type = tc['type'] as String?;
                if (type != null) acc.type = type;

                final functionObj = tc['function'];
                if (functionObj is Map<String, dynamic>) {
                  final name = functionObj['name'] as String?;
                  if (name != null) acc.name = name;

                  final arguments = functionObj['arguments'] as String?;
                  if (arguments != null) acc.argumentsBuffer.write(arguments);
                }
              }
            }
          }
        }
      }
    }

    // Yield usage from this API call if no tool calls were triggered
    if (accumulatedToolCalls.isEmpty &&
        promptTokens != null &&
        completionTokens != null) {
      yield UsageEvent(promptTokens, completionTokens);
    }

    if (accumulatedToolCalls.isNotEmpty) {
      // --- Standard tool_calls detected: execute search or url_fetch and loop ---
      final conversationId = messages.last.conversationId;
      final toolMessages = <ChatMessage>[];

      for (final entry in accumulatedToolCalls.values) {
        if (entry.name == 'url_fetch') {
          String url = '';
          try {
            final parsedArgs = json.decode(entry.argumentsBuffer.toString()) as Map<String, dynamic>;
            url = parsedArgs['url'] as String? ?? '';
          } catch (_) {
            url = entry.argumentsBuffer.toString();
          }

          _checkCancellation(cancelToken);
          yield UrlFetchStartedEvent(url);
          final content = await _urlFetchService.fetchUrlContent(url, cancelToken: cancelToken);
          _checkCancellation(cancelToken);
          yield UrlFetchCompletedEvent(url, content);

          toolMessages.add(ChatMessage(
            id: _uuid.v4(),
            conversationId: conversationId,
            role: 'tool',
            toolCallId: entry.id,
            content: content,
            timestamp: DateTime.now(),
          ));
        } else {
          String query = '';
          try {
            final parsedArgs = json.decode(entry.argumentsBuffer.toString()) as Map<String, dynamic>;
            query = parsedArgs['query'] as String? ?? '';
          } catch (_) {
            query = entry.argumentsBuffer.toString();
          }

          _checkCancellation(cancelToken);

          yield ToolCallStartedEvent(query);

          List<SearchResult> results;
          String? searchError;
          try {
            results = await _searchService.search(
              query: query,
              searxngUrl: searxngUrl,
              searchBackend: searchBackend,
            );
          } on SearchException catch (e) {
            results = [];
            searchError = e.message;
            developer.log('Auto search (follow-up) failed: ${e.message}', name: 'AgentService');
          }

          _checkCancellation(cancelToken);

          yield ToolCallCompletedEvent(query, results);

          final formattedResults = searchError != null
              ? '搜索失败：$searchError'
              : _searchService.formatSearchResultsForContext(results);

          toolMessages.add(ChatMessage(
            id: _uuid.v4(),
            conversationId: conversationId,
            role: 'tool',
            toolCallId: entry.id,
            content: formattedResults,
            timestamp: DateTime.now(),
          ));
        }
      }

      final assistantMessage = ChatMessage(
        id: _uuid.v4(),
        conversationId: conversationId,
        role: 'assistant',
        content: contentBuffer.toString(),
        reasoningContent: reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : null,
        toolCalls: accumulatedToolCalls.values.map((acc) => ToolCall(
          id: acc.id,
          type: acc.type,
          functionName: acc.name,
          arguments: acc.argumentsBuffer.toString(),
        )).toList(),
        timestamp: DateTime.now(),
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );

      yield ToolCallExecutedMessageEvent(assistantMessage, toolMessages);

      final nextMessages = [
        ...messages,
        assistantMessage,
        ...toolMessages,
      ];

      yield* _streamCompletionsLoop(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: nextMessages,
        tools: tools,
        searxngUrl: searxngUrl,
        searchBackend: searchBackend,
        cancelToken: cancelToken,
        toolRound: toolRound + 1,
      );
    } else {
      // --- No standard tool_calls; check for pseudo-XML fallback ---
      final fullContent = contentBuffer.toString();
      final pseudoCalls = parsePseudoXmlToolCalls(fullContent);
      if (pseudoCalls.isNotEmpty && tools != null && tools.isNotEmpty) {
        final cleanedContent = stripPseudoXmlToolCalls(fullContent);
        final conversationId = messages.last.conversationId;
        final toolMessages = <ChatMessage>[];
        final toolCallList = <ToolCall>[];

        for (final call in pseudoCalls) {
          final name = call['name'] as String? ?? '';
          final params = call['params'] as Map<String, String>? ?? {};
          final query = params['query'] ?? '';
          final url = params['url'] ?? '';

          if (name == 'url_fetch' && url.isNotEmpty) {
            _checkCancellation(cancelToken);

            yield UrlFetchStartedEvent(url);

            final content = await _urlFetchService.fetchUrlContent(url, cancelToken: cancelToken);

            _checkCancellation(cancelToken);

            yield UrlFetchCompletedEvent(url, content);

            final toolCallId = 'pseudo_${_uuid.v4()}';
            toolCallList.add(ToolCall(
              id: toolCallId,
              type: 'function',
              functionName: name,
              arguments: json.encode(params),
            ));

            toolMessages.add(ChatMessage(
              id: _uuid.v4(),
              conversationId: conversationId,
              role: 'tool',
              toolCallId: toolCallId,
              content: content,
              timestamp: DateTime.now(),
            ));
          } else if (name == 'web_search' && query.isNotEmpty) {
            _checkCancellation(cancelToken);

            yield ToolCallStartedEvent(query);

            List<SearchResult> results;
            String? searchError;
            try {
              results = await _searchService.search(
                query: query,
                searxngUrl: searxngUrl,
                searchBackend: searchBackend,
              );
            } on SearchException catch (e) {
              results = [];
              searchError = e.message;
              developer.log('Pseudo-XML search failed: ${e.message}', name: 'AgentService');
            }

            _checkCancellation(cancelToken);

            yield ToolCallCompletedEvent(query, results);

            final formattedResults = searchError != null
                ? '搜索失败：$searchError'
                : _searchService.formatSearchResultsForContext(results);

            final toolCallId = 'pseudo_${_uuid.v4()}';
            toolCallList.add(ToolCall(
              id: toolCallId,
              type: 'function',
              functionName: name,
              arguments: json.encode(params),
            ));

            toolMessages.add(ChatMessage(
              id: _uuid.v4(),
              conversationId: conversationId,
              role: 'tool',
              toolCallId: toolCallId,
              content: formattedResults,
              timestamp: DateTime.now(),
            ));
          }
        }

        if (toolMessages.isNotEmpty) {
          final assistantMessage = ChatMessage(
            id: _uuid.v4(),
            conversationId: conversationId,
            role: 'assistant',
            content: cleanedContent,
            reasoningContent: reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : null,
            toolCalls: toolCallList,
            timestamp: DateTime.now(),
            promptTokens: promptTokens,
            completionTokens: completionTokens,
          );

          yield ToolCallExecutedMessageEvent(assistantMessage, toolMessages);

          final nextMessages = [
            ...messages,
            assistantMessage,
            ...toolMessages,
          ];

          yield* _streamCompletionsLoop(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: nextMessages,
            tools: tools,
            searxngUrl: searxngUrl,
            searchBackend: searchBackend,
            cancelToken: cancelToken,
            toolRound: toolRound + 1,
          );
          return; // Prevent fall-through to buffered content yield
        }
        // If no valid pseudo-XML calls, fall through
      }
      // No pseudo-XML; yield buffered content if it was delayed by tool-aware streaming
      if (tools != null && tools.isNotEmpty && fullContent.isNotEmpty) {
        yield ContentDeltaEvent(fullContent);
      }
    }
  }

  void _checkCancellation(CancelToken? cancelToken) {
    if (cancelToken != null && cancelToken.isCancelled) {
      throw cancelToken.cancelError ??
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
            error: 'User requested cancellation',
          );
    }
  }
}
