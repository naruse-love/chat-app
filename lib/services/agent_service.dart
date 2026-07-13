import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import 'search_service.dart';
import 'chat_service.dart';

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

/// Yielded after search results are packaged into assistant/tool messages.
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
  final Uuid _uuid;

  AgentService({
    ChatService? chatService,
    SearchService? searchService,
  })  : _chatService = chatService ?? ChatService(),
        _searchService = searchService ?? SearchService(),
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

  /// Main entry point coordinating completion streaming, tool execution, and manual trigger.
  Stream<AgentStreamEvent> chatAndSearchStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    String? searxngUrl,
    CancelToken? cancelToken,
  }) async* {
    if (messages.isEmpty) return;

    final lastMessage = messages.last;
    final isManualSearch = lastMessage.role == 'user' &&
        lastMessage.content.trim().startsWith('@search');

    if (isManualSearch) {
      final query = lastMessage.content.trim().substring(7).trim();
      if (query.isEmpty) {
        throw ArgumentError('Search query cannot be empty');
      }

      _checkCancellation(cancelToken);

      yield ToolCallStartedEvent(query);

      final results = await _searchService.search(
        query: query,
        baseUrl: baseUrl,
        apiKey: apiKey,
        searxngUrl: searxngUrl,
      );

      _checkCancellation(cancelToken);

      yield ToolCallCompletedEvent(query, results);

      final formattedResults = _searchService.formatSearchResultsForContext(results);

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
        ...messages.sublist(0, messages.length - 1),
        cleanUserMessage,
        assistantMessage,
        toolMessage,
      ];

      yield* _streamCompletions(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: nextMessages,
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
        messages: messages,
        tools: [webSearchTool],
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
          String query = '';
          try {
            final parsedArgs = json.decode(entry.argumentsBuffer.toString()) as Map<String, dynamic>;
            query = parsedArgs['query'] as String? ?? '';
          } catch (_) {
            query = entry.argumentsBuffer.toString();
          }

          _checkCancellation(cancelToken);

          yield ToolCallStartedEvent(query);

          final results = await _searchService.search(
            query: query,
            baseUrl: baseUrl,
            apiKey: apiKey,
            searxngUrl: searxngUrl,
          );

          _checkCancellation(cancelToken);

          yield ToolCallCompletedEvent(query, results);

          final formattedResults = _searchService.formatSearchResultsForContext(results);

          final conversationId = messages.last.conversationId;

          toolMessages.add(ChatMessage(
            id: _uuid.v4(),
            conversationId: conversationId,
            role: 'tool',
            toolCallId: entry.id,
            content: formattedResults,
            timestamp: DateTime.now(),
          ));
        }

        final conversationId = messages.last.conversationId;

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
          ...messages,
          assistantMessage,
          ...toolMessages,
        ];

        yield* _streamCompletions(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: nextMessages,
          cancelToken: cancelToken,
        );
      }
    }
  }

  Stream<AgentStreamEvent> _streamCompletions({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    int? promptTokens;
    int? completionTokens;

    await for (final chunk in _chatService.chatCompletionsStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
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
            yield ReasoningDeltaEvent(reasoning);
          }

          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield ContentDeltaEvent(content);
          }
        }
      }
    }

    // Yield usage info if available
    if (promptTokens != null && completionTokens != null) {
      yield UsageEvent(promptTokens, completionTokens);
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
