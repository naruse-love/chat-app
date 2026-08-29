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
import 'tool_registry.dart';
import 'agent_loop_guard.dart';
import 'tools/math_eval_tool.dart';
import 'tools/time_calculator_tool.dart';
import 'tools/weather_query_tool.dart';
import 'tools/wiki_lookup_tool.dart';
import 'tools/file_write_tool.dart';
import '../models/tool/tool.dart';
import '../models/tool/tool_confirmation.dart';

/// Base class for all events yielded during agent execution.
abstract class AgentStreamEvent {
  const AgentStreamEvent();
}

/// Yielded when a Level 2 (or higher) sensitive tool execution requires user confirmation.
class ToolConfirmationPendingEvent extends AgentStreamEvent {
  final ToolConfirmationRequest request;
  const ToolConfirmationPendingEvent(this.request);
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
  final ToolRegistry _toolRegistry;
  final AgentLoopGuard Function()? guardFactory;
  final Uuid _uuid;

  AgentService({
    ChatService? chatService,
    SearchService? searchService,
    UrlFetchService? urlFetchService,
    ToolRegistry? toolRegistry,
    this.guardFactory,
  })  : _chatService = chatService ?? ChatService(),
        _searchService = searchService ?? SearchService(),
        _urlFetchService = urlFetchService ?? UrlFetchService(),
        _toolRegistry = toolRegistry ??
            ToolRegistry.defaultRegistry(
              searchService: searchService,
              urlFetchService: urlFetchService,
            ),
        _uuid = const Uuid();

  ChatService get chatService => _chatService;
  SearchService get searchService => _searchService;
  UrlFetchService get urlFetchService => _urlFetchService;
  ToolRegistry get toolRegistry => _toolRegistry;

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

  /// OpenAI-compatible Tool definition for Google search.
  static const Map<String, dynamic> googleSearchTool = {
    'type': 'function',
    'function': {
      'name': 'google_search',
      'description': 'Search Google for up-to-date information on a given topic.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query for Google.',
          },
        },
        'required': ['query'],
      },
    },
  };

  /// OpenAI-compatible Tool definition for Bing search.
  static const Map<String, dynamic> bingSearchTool = {
    'type': 'function',
    'function': {
      'name': 'bing_search',
      'description': 'Search Bing for up-to-date information on a given topic.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query for Bing.',
          },
        },
        'required': ['query'],
      },
    },
  };

  /// OpenAI-compatible Tool definition for fetching structured webpage content.
  static const Map<String, dynamic> urlFetchTool = {
    'type': 'function',
    'function': {
      'name': 'url_fetch',
      'description':
          'Fetch and extract structured content from a webpage URL. Returns metadata (title, author, published date, site name, language), page type diagnosis (article/doc/captcha/login_wall/nav_hub), truncation status & limits, link statistics, and cleaned main content in Markdown.',
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

  /// Returns effective tool schemas passed to the LLM.
  ///
  /// When [toolRegistry] is provided:
  /// - Filters search tools based on [enableAutoSearch] and [searchBackend].
  /// - Includes all other enabled tools from the registry.
  ///
  /// When [toolRegistry] is null:
  /// - Preserves exact legacy tool list for 100% backward compatibility.
  /// - If [includeBasicTools] is true, also appends 4 basic tools.
  static List<Map<String, dynamic>> getEffectiveTools(
    String searchBackend, {
    bool enableAutoSearch = true,
    ToolRegistry? toolRegistry,
    bool includeBasicTools = false,
  }) {
    if (toolRegistry != null) {
      final allowedSearchNames = <String>{};
      if (enableAutoSearch) {
        switch (searchBackend) {
          case 'google':
            allowedSearchNames.add('google_search');
            break;
          case 'bing':
            allowedSearchNames.add('bing_search');
            break;
          case 'google_bing':
            allowedSearchNames.addAll(['google_search', 'bing_search']);
            break;
          case 'searxng':
          default:
            allowedSearchNames.add('web_search');
            break;
        }
      }

      return toolRegistry.exportOpenAiSchemas().where((schema) {
        final name = schema['function']?['name'] as String?;
        if (name == null) return false;
        if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
          return allowedSearchNames.contains(name);
        }
        return true;
      }).toList();
    }

    final base = <Map<String, dynamic>>[];
    if (enableAutoSearch) {
      switch (searchBackend) {
        case 'google':
          base.add(googleSearchTool);
          break;
        case 'bing':
          base.add(bingSearchTool);
          break;
        case 'google_bing':
          base.addAll([googleSearchTool, bingSearchTool]);
          break;
        case 'searxng':
        default:
          base.add(webSearchTool);
          break;
      }
    }
    base.add(urlFetchTool);

    if (includeBasicTools) {
      base.addAll([
        const MathEvalTool().toOpenAiSchema(),
        TimeCalculatorTool().toOpenAiSchema(),
        WeatherQueryTool().toOpenAiSchema(),
        WikiLookupTool().toOpenAiSchema(),
      ]);
    }

    return base;
  }

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
  /// Supports both standard <tool_call> and DSML (<｜｜DSML｜｜tool_calls> or <||DSML||tool_calls>) formats.
  /// Returns a list of maps with 'name' (String) and 'params' (Map<String, String>).
  static List<Map<String, dynamic>> parsePseudoXmlToolCalls(String content) {
    final results = <Map<String, dynamic>>[];

    // 1. Standard <tool_call> parsing
    final toolCallBlockRegex = RegExp(
      r'<tool_call>\s*<function=(\w+)>([\s\S]*?)</function>\s*</tool_call>',
      multiLine: true,
    );
    for (final match in toolCallBlockRegex.allMatches(content)) {
      final name = match.group(1) ?? '';
      final blockContent = match.group(2) ?? '';
      final paramMap = <String, String>{};
      final paramRegex = RegExp(
        r'<parameter=(\w+)>([\s\S]*?)</parameter>',
        multiLine: true,
      );
      for (final paramMatch in paramRegex.allMatches(blockContent)) {
        final paramName = paramMatch.group(1) ?? '';
        final paramValue = paramMatch.group(2)?.trim() ?? '';
        paramMap[paramName] = paramValue;
      }
      results.add({
        'name': name,
        'params': paramMap,
      });
    }

    // 2. DSML tool calls parsing (DeepSeek Model Language)
    final dsmlBlockRegex = RegExp(
      r'<[|｜]{2}DSML[|｜]{2}tool_calls>([\s\S]*?)</[|｜]{2}DSML[|｜]{2}tool_calls>',
      multiLine: true,
    );
    for (final blockMatch in dsmlBlockRegex.allMatches(content)) {
      final blockContent = blockMatch.group(1) ?? '';

      final invokeRegex = RegExp(
        r'<[|｜]{2}DSML[|｜]{2}invoke name="(\w+)">([\s\S]*?)</[|｜]{2}DSML[|｜]{2}invoke>',
        multiLine: true,
      );
      for (final invokeMatch in invokeRegex.allMatches(blockContent)) {
        final funcName = invokeMatch.group(1) ?? '';
        final invokeContent = invokeMatch.group(2) ?? '';

        final paramMap = <String, String>{};
        final paramRegex = RegExp(
          r'<[|｜]{2}DSML[|｜]{2}parameter name="(\w+)"[^>]*>([\s\S]*?)</[|｜]{2}DSML[|｜]{2}parameter>',
          multiLine: true,
        );
        for (final paramMatch in paramRegex.allMatches(invokeContent)) {
          final paramName = paramMatch.group(1) ?? '';
          final paramValue = paramMatch.group(2)?.trim() ?? '';
          paramMap[paramName] = paramValue;
        }
        results.add({
          'name': funcName,
          'params': paramMap,
        });
      }
    }

    return results;
  }

  /// Removes pseudo-XML and DSML tool_call blocks from [content].
  static String stripPseudoXmlToolCalls(String content) {
    var cleaned = content.replaceAll(_pseudoXmlToolCallRegex, '');
    final genericToolCallRegex = RegExp(
      r'<tool_call>\s*<function=\w+>[\s\S]*?</function>\s*</tool_call>',
      multiLine: true,
    );
    cleaned = cleaned.replaceAll(genericToolCallRegex, '');
    final dsmlBlockRegex = RegExp(
      r'<[|｜]{2}DSML[|｜]{2}tool_calls>[\s\S]*?</[|｜]{2}DSML[|｜]{2}tool_calls>',
      multiLine: true,
    );
    cleaned = cleaned.replaceAll(dsmlBlockRegex, '');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Generates tool preview metadata for Level 2 confirmation cards.
  dynamic _buildToolPreviewData(String name, Tool? toolObj, Map<String, dynamic> args) {
    if (name == 'file_write' && toolObj is FileWriteTool) {
      final rawPath = args['path']?.toString() ?? '';
      final content = args['content']?.toString() ?? '';
      final mode = args['mode']?.toString() ?? 'overwrite';
      return toolObj.generateDiffPreview(rawPath, content, mode: mode);
    } else if (name == 'file_delete') {
      return {
        'path': args['path']?.toString() ?? '',
        'recursive': args['recursive'] == true,
      };
    } else if (name == 'code_eval') {
      return {
        'code': args['code']?.toString() ?? '',
        'timeout_ms': args['timeout_ms'] ?? 3000,
      };
    } else if (name == 'clipboard_write') {
      return {
        'text': args['text']?.toString() ?? '',
      };
    }
    return args;
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
    String? googleApiKey,
    String? googleBaseUrl,
    String? googleSearchModel,
    String? bingCookie,
    String? reasoningEffort,
    bool enableAutoSearch = true,
    CancelToken? cancelToken,
    int maxToolRounds = 100,
    AgentLoopGuard? guard,
    Future<ToolConfirmationDecision> Function(ToolConfirmationRequest)? onConfirmTool,
  }) async* {
    // Inject system prompt if provided (prepend after removing any existing system messages)
    List<ChatMessage> effectiveMessages;
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      final conversationId = messages.isNotEmpty ? messages.first.conversationId : '';
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final enrichedPrompt = '$systemPrompt\n\n当前日期与时间: $dateStr $timeStr';
      effectiveMessages = [
        ChatMessage(
          id: _uuid.v4(),
          conversationId: conversationId,
          role: 'system',
          content: enrichedPrompt,
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

    final effectiveTools = getEffectiveTools(searchBackend, enableAutoSearch: enableAutoSearch, toolRegistry: _toolRegistry);
    final activeGuard = guard ?? guardFactory?.call() ?? AgentLoopGuard(maxToolRounds: maxToolRounds);

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
          googleApiKey: googleApiKey,
          googleBaseUrl: googleBaseUrl,
          googleSearchModel: googleSearchModel,
          bingCookie: bingCookie,
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
      final searchToolName = searchBackend == 'google'
          ? 'google_search'
          : (searchBackend == 'bing' ? 'bing_search' : 'web_search');

      activeGuard.recordToolCall(searchToolName, {'query': query});

      final assistantMessage = ChatMessage(
        id: _uuid.v4(),
        conversationId: lastMessage.conversationId,
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(
            id: toolCallId,
            type: 'function',
            functionName: searchToolName,
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
        tools: effectiveTools,
        searxngUrl: searxngUrl,
        searchBackend: searchBackend,
        googleApiKey: googleApiKey,
        googleBaseUrl: googleBaseUrl,
        googleSearchModel: googleSearchModel,
        bingCookie: bingCookie,
        reasoningEffort: reasoningEffort,
        cancelToken: cancelToken,
        maxToolRounds: maxToolRounds,
        guard: activeGuard,
        onConfirmTool: onConfirmTool,
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
        tools: effectiveTools,
        reasoningEffort: reasoningEffort,
        cancelToken: cancelToken,
      )) {
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
        final conversationId = effectiveMessages.last.conversationId;

        for (final entry in accumulatedToolCalls.values) {
          final name = entry.name;
          Map<String, dynamic> args;
          try {
            final decoded = json.decode(entry.argumentsBuffer.toString());
            if (decoded is Map<String, dynamic>) {
              if (decoded.containsKey('query') && decoded['query'] != null && decoded['query'] is! String) {
                args = {'query': entry.argumentsBuffer.toString()};
              } else if (decoded.containsKey('url') && decoded['url'] != null && decoded['url'] is! String) {
                args = {'url': entry.argumentsBuffer.toString()};
              } else {
                args = decoded;
              }
            } else {
              args = {'query': entry.argumentsBuffer.toString()};
            }
          } catch (_) {
            args = {'query': entry.argumentsBuffer.toString()};
          }

          // Guard check before execution
          final verdict = activeGuard.checkBeforeExecution(name, args, currentRound: 0);
          if (verdict.isBlocked) {
            final prompt = activeGuard.getForcedConclusionPrompt(verdict: verdict);
            yield* _streamFinalConclusion(
              baseUrl: baseUrl,
              apiKey: apiKey,
              model: model,
              messages: effectiveMessages,
              prompt: prompt,
              reasoningEffort: reasoningEffort,
              cancelToken: cancelToken,
            );
            return;
          }

          activeGuard.recordToolCall(name, args);

          final context = {
            'searxngUrl': searxngUrl,
            'searchBackend': searchBackend,
            'googleApiKey': googleApiKey,
            'googleBaseUrl': googleBaseUrl,
            'googleSearchModel': googleSearchModel,
            'bingCookie': bingCookie,
            'cancelToken': cancelToken,
          };

          _checkCancellation(cancelToken);

          final toolObj = _toolRegistry.getTool(name);
          final requiresConfirmation =
              toolObj != null && toolObj.securityLevel.requiresConfirmation && onConfirmTool != null;

          ToolExecutionResult result;

          if (requiresConfirmation) {
            final confirmationRequest = ToolConfirmationRequest(
              confirmationId: _uuid.v4(),
              toolCallId: entry.id,
              toolName: name,
              displayName: toolObj.displayName,
              securityLevel: toolObj.securityLevel,
              arguments: args,
              description: toolObj.description,
              previewData: _buildToolPreviewData(name, toolObj, args),
              status: ToolConfirmationStatus.pending,
            );

            yield ToolConfirmationPendingEvent(confirmationRequest);

            final decision = await onConfirmTool(confirmationRequest);
            _checkCancellation(cancelToken);

            if (decision.isCancelled) {
              return;
            }

            if (decision.isRejected) {
              final reason = decision.rejectionReason ?? '用户拒绝了执行权限';
              result = ToolExecutionResult.failure(
                toolName: name,
                errorMessage: '用户已拒绝执行此操作',
                content: '【用户已拒绝执行此操作】原因：$reason',
                rawData: {'rejected': true, 'rejectionReason': reason},
              );
            } else {
              // Approved
              if (name == 'url_fetch') {
                final url = args['url'] as String? ?? '';
                yield UrlFetchStartedEvent(url);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = args['query'] as String? ?? '';
                yield ToolCallStartedEvent(query);
              } else {
                final title = '${toolObj.displayName}: ${args.values.join(', ')}';
                yield ToolCallStartedEvent(title);
              }

              result = await _toolRegistry.execute(name, args, context: context);
              _checkCancellation(cancelToken);

              if (name == 'url_fetch') {
                final url = args['url'] as String? ?? '';
                yield UrlFetchCompletedEvent(url, result.content);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = args['query'] as String? ?? '';
                final rawResults = (result.rawData is List<SearchResult>)
                    ? (result.rawData as List<SearchResult>)
                    : <SearchResult>[];
                yield ToolCallCompletedEvent(query, rawResults);
              } else {
                yield ToolCallCompletedEvent(name, []);
              }
            }
          } else {
            if (name == 'url_fetch') {
              final url = args['url'] as String? ?? '';
              yield UrlFetchStartedEvent(url);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = args['query'] as String? ?? '';
              yield ToolCallStartedEvent(query);
            } else {
              final title = toolObj != null ? '${toolObj.displayName}: ${args.values.join(', ')}' : name;
              yield ToolCallStartedEvent(title);
            }

            result = await _toolRegistry.execute(name, args, context: context);
            _checkCancellation(cancelToken);

            if (name == 'url_fetch') {
              final url = args['url'] as String? ?? '';
              yield UrlFetchCompletedEvent(url, result.content);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = args['query'] as String? ?? '';
              final rawResults = (result.rawData is List<SearchResult>)
                  ? (result.rawData as List<SearchResult>)
                  : <SearchResult>[];
              yield ToolCallCompletedEvent(query, rawResults);
            } else {
              yield ToolCallCompletedEvent(name, []);
            }
          }

          toolMessages.add(ChatMessage(
            id: _uuid.v4(),
            conversationId: conversationId,
            role: 'tool',
            toolCallId: entry.id,
            content: result.content.isNotEmpty ? result.content : (result.errorMessage ?? '执行完成'),
            timestamp: DateTime.now(),
          ));
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
          tools: effectiveTools,
          searxngUrl: searxngUrl,
          searchBackend: searchBackend,
          googleApiKey: googleApiKey,
          googleBaseUrl: googleBaseUrl,
          googleSearchModel: googleSearchModel,
          bingCookie: bingCookie,
          reasoningEffort: reasoningEffort,
          cancelToken: cancelToken,
          maxToolRounds: maxToolRounds,
          guard: activeGuard,
          onConfirmTool: onConfirmTool,
        );
      } else {
        // --- First round: check for pseudo-XML fallback ---
        final fullContent = contentBuffer.toString();
        final pseudoCalls = parsePseudoXmlToolCalls(fullContent);
        if (pseudoCalls.isNotEmpty && effectiveTools.isNotEmpty) {
          final cleanedContent = stripPseudoXmlToolCalls(fullContent);
          final conversationId = effectiveMessages.last.conversationId;
          final toolMessages = <ChatMessage>[];
          final toolCallList = <ToolCall>[];

          for (final call in pseudoCalls) {
            final name = call['name'] as String? ?? '';
            final params = Map<String, dynamic>.from(call['params'] as Map? ?? {});

            // Guard check before execution
            final verdict = activeGuard.checkBeforeExecution(name, params, currentRound: 0);
            if (verdict.isBlocked) {
              final prompt = activeGuard.getForcedConclusionPrompt(verdict: verdict);
              yield* _streamFinalConclusion(
                baseUrl: baseUrl,
                apiKey: apiKey,
                model: model,
                messages: effectiveMessages,
                prompt: prompt,
                reasoningEffort: reasoningEffort,
                cancelToken: cancelToken,
              );
              return;
            }

            activeGuard.recordToolCall(name, params);

            final context = {
              'searxngUrl': searxngUrl,
              'searchBackend': searchBackend,
              'googleApiKey': googleApiKey,
              'googleBaseUrl': googleBaseUrl,
              'googleSearchModel': googleSearchModel,
              'bingCookie': bingCookie,
              'cancelToken': cancelToken,
            };

            _checkCancellation(cancelToken);

            final toolCallId = 'pseudo_${_uuid.v4()}';
            final toolObj = _toolRegistry.getTool(name);
            final requiresConfirmation =
                toolObj != null && toolObj.securityLevel.requiresConfirmation && onConfirmTool != null;

            ToolExecutionResult result;

            if (requiresConfirmation) {
              final confirmationRequest = ToolConfirmationRequest(
                confirmationId: _uuid.v4(),
                toolCallId: toolCallId,
                toolName: name,
                displayName: toolObj.displayName,
                securityLevel: toolObj.securityLevel,
                arguments: params,
                description: toolObj.description,
                previewData: _buildToolPreviewData(name, toolObj, params),
                status: ToolConfirmationStatus.pending,
              );

              yield ToolConfirmationPendingEvent(confirmationRequest);

              final decision = await onConfirmTool(confirmationRequest);
              _checkCancellation(cancelToken);

              if (decision.isCancelled) {
                return;
              }

              if (decision.isRejected) {
                final reason = decision.rejectionReason ?? '用户拒绝了执行权限';
                result = ToolExecutionResult.failure(
                  toolName: name,
                  errorMessage: '用户已拒绝执行此操作',
                  content: '【用户已拒绝执行此操作】原因：$reason',
                  rawData: {'rejected': true, 'rejectionReason': reason},
                );
              } else {
                // Approved
                if (name == 'url_fetch') {
                  final url = params['url'] as String? ?? '';
                  yield UrlFetchStartedEvent(url);
                } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                  final query = params['query'] as String? ?? '';
                  yield ToolCallStartedEvent(query);
                } else {
                  final title = '${toolObj.displayName}: ${params.values.join(', ')}';
                  yield ToolCallStartedEvent(title);
                }

                result = await _toolRegistry.execute(name, params, context: context);
                _checkCancellation(cancelToken);

                if (name == 'url_fetch') {
                  final url = params['url'] as String? ?? '';
                  yield UrlFetchCompletedEvent(url, result.content);
                } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                  final query = params['query'] as String? ?? '';
                  final rawResults = (result.rawData is List<SearchResult>)
                      ? (result.rawData as List<SearchResult>)
                      : <SearchResult>[];
                  yield ToolCallCompletedEvent(query, rawResults);
                } else {
                  yield ToolCallCompletedEvent(name, []);
                }
              }
            } else {
              if (name == 'url_fetch') {
                final url = params['url'] as String? ?? '';
                yield UrlFetchStartedEvent(url);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = params['query'] as String? ?? '';
                yield ToolCallStartedEvent(query);
              } else {
                final title = toolObj != null ? '${toolObj.displayName}: ${params.values.join(', ')}' : name;
                yield ToolCallStartedEvent(title);
              }

              result = await _toolRegistry.execute(name, params, context: context);
              _checkCancellation(cancelToken);

              if (name == 'url_fetch') {
                final url = params['url'] as String? ?? '';
                yield UrlFetchCompletedEvent(url, result.content);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = params['query'] as String? ?? '';
                final rawResults = (result.rawData is List<SearchResult>)
                    ? (result.rawData as List<SearchResult>)
                    : <SearchResult>[];
                yield ToolCallCompletedEvent(query, rawResults);
              } else {
                yield ToolCallCompletedEvent(name, []);
              }
            }

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
              content: result.content.isNotEmpty ? result.content : (result.errorMessage ?? '执行完成'),
              timestamp: DateTime.now(),
            ));
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
              promptTokens: mainPromptTokens,
              completionTokens: mainCompletionTokens,
            );

            yield ToolCallExecutedMessageEvent(assistantMessage, toolMessages);

            final nextMessages = [
              ...effectiveMessages,
              assistantMessage,
              ...toolMessages,
            ];

            yield* _streamCompletionsLoop(
              baseUrl: baseUrl,
              apiKey: apiKey,
              model: model,
              messages: nextMessages,
              tools: effectiveTools,
              searxngUrl: searxngUrl,
              searchBackend: searchBackend,
              googleApiKey: googleApiKey,
              googleBaseUrl: googleBaseUrl,
              googleSearchModel: googleSearchModel,
              bingCookie: bingCookie,
              reasoningEffort: reasoningEffort,
              cancelToken: cancelToken,
              toolRound: 1,
              maxToolRounds: maxToolRounds,
              guard: activeGuard,
              onConfirmTool: onConfirmTool,
            );
          }
        }
      }
    }
  }

  /// Follow-up streaming with multi-turn tool calling support.
  Stream<AgentStreamEvent> _streamCompletions({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    String? searxngUrl,
    String searchBackend = 'searxng',
    String? googleApiKey,
    String? googleBaseUrl,
    String? googleSearchModel,
    String? bingCookie,
    String? reasoningEffort,
    bool enableAutoSearch = true,
    CancelToken? cancelToken,
    int maxToolRounds = 100,
    AgentLoopGuard? guard,
    Future<ToolConfirmationDecision> Function(ToolConfirmationRequest)? onConfirmTool,
  }) async* {
    yield* _streamCompletionsLoop(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      tools: tools ?? getEffectiveTools(searchBackend, enableAutoSearch: enableAutoSearch, toolRegistry: _toolRegistry),
      searxngUrl: searxngUrl,
      searchBackend: searchBackend,
      googleApiKey: googleApiKey,
      googleBaseUrl: googleBaseUrl,
      googleSearchModel: googleSearchModel,
      bingCookie: bingCookie,
      reasoningEffort: reasoningEffort,
      cancelToken: cancelToken,
      toolRound: 0,
      maxToolRounds: maxToolRounds,
      guard: guard,
      onConfirmTool: onConfirmTool,
    );
  }

  /// Helper that generates final conclusion text after stripping tools.
  Stream<AgentStreamEvent> _streamFinalConclusion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    required String prompt,
    String? reasoningEffort,
    CancelToken? cancelToken,
  }) async* {
    int? finalPromptTokens;
    int? finalCompletionTokens;
    final finalMessages = [
      ...messages,
      ChatMessage(
        id: _uuid.v4(),
        conversationId: messages.isNotEmpty ? messages.first.conversationId : '',
        role: 'system',
        content: prompt,
        timestamp: DateTime.now(),
      ),
    ];
    await for (final chunk in _chatService.chatCompletionsStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: finalMessages,
      reasoningEffort: reasoningEffort,
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
    String? googleApiKey,
    String? googleBaseUrl,
    String? googleSearchModel,
    String? bingCookie,
    String? reasoningEffort,
    CancelToken? cancelToken,
    int toolRound = 0,
    int maxToolRounds = 100,
    AgentLoopGuard? guard,
    Future<ToolConfirmationDecision> Function(ToolConfirmationRequest)? onConfirmTool,
  }) async* {
    final activeGuard = guard ?? guardFactory?.call() ?? AgentLoopGuard(maxToolRounds: maxToolRounds);

    // Max total tool rounds or loop guard check
    if (activeGuard.shouldStripTools(toolRound) || toolRound >= maxToolRounds - 1) {
      final conclusionPrompt = activeGuard.getForcedConclusionPrompt();
      yield* _streamFinalConclusion(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
        prompt: conclusionPrompt,
        reasoningEffort: reasoningEffort,
        cancelToken: cancelToken,
      );
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
      reasoningEffort: reasoningEffort,
      cancelToken: cancelToken,
    )) {
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
      final conversationId = messages.last.conversationId;
      final toolMessages = <ChatMessage>[];

      for (final entry in accumulatedToolCalls.values) {
        final name = entry.name;
        Map<String, dynamic> args;
        try {
          final decoded = json.decode(entry.argumentsBuffer.toString());
          if (decoded is Map<String, dynamic>) {
            if (decoded.containsKey('query') && decoded['query'] != null && decoded['query'] is! String) {
              args = {'query': entry.argumentsBuffer.toString()};
            } else if (decoded.containsKey('url') && decoded['url'] != null && decoded['url'] is! String) {
              args = {'url': entry.argumentsBuffer.toString()};
            } else {
              args = decoded;
            }
          } else {
            args = {'query': entry.argumentsBuffer.toString()};
          }
        } catch (_) {
          args = {'query': entry.argumentsBuffer.toString()};
        }

        // Guard check before execution
        final verdict = activeGuard.checkBeforeExecution(name, args, currentRound: toolRound + 1);
        if (verdict.isBlocked) {
          final prompt = activeGuard.getForcedConclusionPrompt(verdict: verdict);
          yield* _streamFinalConclusion(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: messages,
            prompt: prompt,
            reasoningEffort: reasoningEffort,
            cancelToken: cancelToken,
          );
          return;
        }

        activeGuard.recordToolCall(name, args);

        final context = {
          'searxngUrl': searxngUrl,
          'searchBackend': searchBackend,
          'googleApiKey': googleApiKey,
          'googleBaseUrl': googleBaseUrl,
          'googleSearchModel': googleSearchModel,
          'bingCookie': bingCookie,
          'cancelToken': cancelToken,
        };

        _checkCancellation(cancelToken);

        final toolObj = _toolRegistry.getTool(name);
        final requiresConfirmation =
            toolObj != null && toolObj.securityLevel.requiresConfirmation && onConfirmTool != null;

        ToolExecutionResult result;

        if (requiresConfirmation) {
          final confirmationRequest = ToolConfirmationRequest(
            confirmationId: _uuid.v4(),
            toolCallId: entry.id,
            toolName: name,
            displayName: toolObj.displayName,
            securityLevel: toolObj.securityLevel,
            arguments: args,
            description: toolObj.description,
            previewData: _buildToolPreviewData(name, toolObj, args),
            status: ToolConfirmationStatus.pending,
          );

          yield ToolConfirmationPendingEvent(confirmationRequest);

          final decision = await onConfirmTool(confirmationRequest);
          _checkCancellation(cancelToken);

          if (decision.isCancelled) {
            return;
          }

          if (decision.isRejected) {
            final reason = decision.rejectionReason ?? '用户拒绝了执行权限';
            result = ToolExecutionResult.failure(
              toolName: name,
              errorMessage: '用户已拒绝执行此操作',
              content: '【用户已拒绝执行此操作】原因：$reason',
              rawData: {'rejected': true, 'rejectionReason': reason},
            );
          } else {
            // Approved
            if (name == 'url_fetch') {
              final url = args['url'] as String? ?? '';
              yield UrlFetchStartedEvent(url);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = args['query'] as String? ?? '';
              yield ToolCallStartedEvent(query);
            } else {
              final title = '${toolObj.displayName}: ${args.values.join(', ')}';
              yield ToolCallStartedEvent(title);
            }

            result = await _toolRegistry.execute(name, args, context: context);
            _checkCancellation(cancelToken);

            if (name == 'url_fetch') {
              final url = args['url'] as String? ?? '';
              yield UrlFetchCompletedEvent(url, result.content);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = args['query'] as String? ?? '';
              final rawResults = (result.rawData is List<SearchResult>)
                  ? (result.rawData as List<SearchResult>)
                  : <SearchResult>[];
              yield ToolCallCompletedEvent(query, rawResults);
            } else {
              yield ToolCallCompletedEvent(name, []);
            }
          }
        } else {
          if (name == 'url_fetch') {
            final url = args['url'] as String? ?? '';
            yield UrlFetchStartedEvent(url);
          } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
            final query = args['query'] as String? ?? '';
            yield ToolCallStartedEvent(query);
          } else {
            final title = toolObj != null ? '${toolObj.displayName}: ${args.values.join(', ')}' : name;
            yield ToolCallStartedEvent(title);
          }

          result = await _toolRegistry.execute(name, args, context: context);
          _checkCancellation(cancelToken);

          if (name == 'url_fetch') {
            final url = args['url'] as String? ?? '';
            yield UrlFetchCompletedEvent(url, result.content);
          } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
            final query = args['query'] as String? ?? '';
            final rawResults = (result.rawData is List<SearchResult>)
                ? (result.rawData as List<SearchResult>)
                : <SearchResult>[];
            yield ToolCallCompletedEvent(query, rawResults);
          } else {
            yield ToolCallCompletedEvent(name, []);
          }
        }

        toolMessages.add(ChatMessage(
          id: _uuid.v4(),
          conversationId: conversationId,
          role: 'tool',
          toolCallId: entry.id,
          content: result.content.isNotEmpty ? result.content : (result.errorMessage ?? '执行完成'),
          timestamp: DateTime.now(),
        ));
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
        googleApiKey: googleApiKey,
        googleBaseUrl: googleBaseUrl,
        googleSearchModel: googleSearchModel,
        bingCookie: bingCookie,
        reasoningEffort: reasoningEffort,
        cancelToken: cancelToken,
        toolRound: toolRound + 1,
        maxToolRounds: maxToolRounds,
        guard: activeGuard,
        onConfirmTool: onConfirmTool,
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
          final params = Map<String, dynamic>.from(call['params'] as Map? ?? {});

          // Guard check before execution
          final verdict = activeGuard.checkBeforeExecution(name, params, currentRound: toolRound + 1);
          if (verdict.isBlocked) {
            final prompt = activeGuard.getForcedConclusionPrompt(verdict: verdict);
            yield* _streamFinalConclusion(
              baseUrl: baseUrl,
              apiKey: apiKey,
              model: model,
              messages: messages,
              prompt: prompt,
              reasoningEffort: reasoningEffort,
              cancelToken: cancelToken,
            );
            return;
          }

          activeGuard.recordToolCall(name, params);

          final context = {
            'searxngUrl': searxngUrl,
            'searchBackend': searchBackend,
            'googleApiKey': googleApiKey,
            'googleBaseUrl': googleBaseUrl,
            'googleSearchModel': googleSearchModel,
            'bingCookie': bingCookie,
            'cancelToken': cancelToken,
          };

          _checkCancellation(cancelToken);

          final toolCallId = 'pseudo_${_uuid.v4()}';
          final toolObj = _toolRegistry.getTool(name);
          final requiresConfirmation =
              toolObj != null && toolObj.securityLevel.requiresConfirmation && onConfirmTool != null;

          ToolExecutionResult result;

          if (requiresConfirmation) {
            final confirmationRequest = ToolConfirmationRequest(
              confirmationId: _uuid.v4(),
              toolCallId: toolCallId,
              toolName: name,
              displayName: toolObj.displayName,
              securityLevel: toolObj.securityLevel,
              arguments: params,
              description: toolObj.description,
              previewData: _buildToolPreviewData(name, toolObj, params),
              status: ToolConfirmationStatus.pending,
            );

            yield ToolConfirmationPendingEvent(confirmationRequest);

            final decision = await onConfirmTool(confirmationRequest);
            _checkCancellation(cancelToken);

            if (decision.isCancelled) {
              return;
            }

            if (decision.isRejected) {
              final reason = decision.rejectionReason ?? '用户拒绝了执行权限';
              result = ToolExecutionResult.failure(
                toolName: name,
                errorMessage: '用户已拒绝执行此操作',
                content: '【用户已拒绝执行此操作】原因：$reason',
                rawData: {'rejected': true, 'rejectionReason': reason},
              );
            } else {
              // Approved
              if (name == 'url_fetch') {
                final url = params['url'] as String? ?? '';
                yield UrlFetchStartedEvent(url);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = params['query'] as String? ?? '';
                yield ToolCallStartedEvent(query);
              } else {
                final title = '${toolObj.displayName}: ${params.values.join(', ')}';
                yield ToolCallStartedEvent(title);
              }

              result = await _toolRegistry.execute(name, params, context: context);
              _checkCancellation(cancelToken);

              if (name == 'url_fetch') {
                final url = params['url'] as String? ?? '';
                yield UrlFetchCompletedEvent(url, result.content);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = params['query'] as String? ?? '';
                final rawResults = (result.rawData is List<SearchResult>)
                    ? (result.rawData as List<SearchResult>)
                    : <SearchResult>[];
                yield ToolCallCompletedEvent(query, rawResults);
              } else {
                yield ToolCallCompletedEvent(name, []);
              }
            }
          } else {
            if (name == 'url_fetch') {
              final url = params['url'] as String? ?? '';
              yield UrlFetchStartedEvent(url);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = params['query'] as String? ?? '';
              yield ToolCallStartedEvent(query);
            } else {
              final title = toolObj != null ? '${toolObj.displayName}: ${params.values.join(', ')}' : name;
              yield ToolCallStartedEvent(title);
            }

            result = await _toolRegistry.execute(name, params, context: context);
            _checkCancellation(cancelToken);

            if (name == 'url_fetch') {
              final url = params['url'] as String? ?? '';
              yield UrlFetchCompletedEvent(url, result.content);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = params['query'] as String? ?? '';
              final rawResults = (result.rawData is List<SearchResult>)
                  ? (result.rawData as List<SearchResult>)
                  : <SearchResult>[];
              yield ToolCallCompletedEvent(query, rawResults);
            } else {
              yield ToolCallCompletedEvent(name, []);
            }
          }

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
            content: result.content.isNotEmpty ? result.content : (result.errorMessage ?? '执行完成'),
            timestamp: DateTime.now(),
          ));
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
            googleApiKey: googleApiKey,
            googleBaseUrl: googleBaseUrl,
            googleSearchModel: googleSearchModel,
            bingCookie: bingCookie,
            reasoningEffort: reasoningEffort,
            cancelToken: cancelToken,
            toolRound: toolRound + 1,
            maxToolRounds: maxToolRounds,
            guard: activeGuard,
            onConfirmTool: onConfirmTool,
          );
          return; // Prevent fall-through to buffered content yield
        }
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
