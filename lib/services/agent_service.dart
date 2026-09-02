import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import '../models/agent_step_telemetry.dart';
import 'search_service.dart';
import 'chat_service.dart';
import 'url_fetch_service.dart';
import 'tool_registry.dart';
import 'agent_loop_guard.dart';
import 'token_budget_manager.dart';
import 'agent_fault_tolerance.dart';
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

/// Yielded when a step telemetry record is generated during multi-step tool execution.
class AgentStepTelemetryEvent extends AgentStreamEvent {
  final AgentStepTelemetry telemetry;
  const AgentStepTelemetryEvent(this.telemetry);
}

/// Yielded when token budget evaluation or sliding window compaction occurs.
class TokenBudgetTelemetryEvent extends AgentStreamEvent {
  final TokenBudgetTelemetry telemetry;
  const TokenBudgetTelemetryEvent(this.telemetry);
}

/// Yielded when context size triggers the global circuit breaker threshold.
class CircuitBreakerTriggeredEvent extends AgentStreamEvent {
  final String reason;
  final int estimatedTokens;
  final int budgetCap;
  const CircuitBreakerTriggeredEvent(this.reason, this.estimatedTokens, this.budgetCap);
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
  final TokenBudgetManager _tokenBudgetManager;
  final AgentFaultTolerance _agentFaultTolerance;
  final AgentLoopGuard Function()? guardFactory;
  final Uuid _uuid;

  AgentService({
    ChatService? chatService,
    SearchService? searchService,
    UrlFetchService? urlFetchService,
    ToolRegistry? toolRegistry,
    TokenBudgetManager? tokenBudgetManager,
    AgentFaultTolerance? agentFaultTolerance,
    this.guardFactory,
  })  : _chatService = chatService ?? ChatService(),
        _searchService = searchService ?? SearchService(),
        _urlFetchService = urlFetchService ?? UrlFetchService(),
        _toolRegistry = toolRegistry ??
            ToolRegistry.defaultRegistry(
              searchService: searchService,
              urlFetchService: urlFetchService,
            ),
        _tokenBudgetManager = tokenBudgetManager ?? TokenBudgetManager(),
        _agentFaultTolerance = agentFaultTolerance ?? AgentFaultTolerance(),
        _uuid = const Uuid();

  ChatService get chatService => _chatService;
  SearchService get searchService => _searchService;
  UrlFetchService get urlFetchService => _urlFetchService;
  ToolRegistry get toolRegistry => _toolRegistry;
  TokenBudgetManager get tokenBudgetManager => _tokenBudgetManager;
  AgentFaultTolerance get agentFaultTolerance => _agentFaultTolerance;

  /// Categorizes a tool into one of the 4 dimensions:
  /// 1: 基础实用, 2: 沙箱与代码, 3: 移动原生, 4: 动态MCP
  static String categorizeTool(String toolName) {
    if (toolName.startsWith('mcp_')) {
      return '动态MCP';
    }
    switch (toolName) {
      case 'math_eval':
      case 'time_calculator':
      case 'weather_query':
      case 'wiki_lookup':
      case 'web_search':
      case 'google_search':
      case 'bing_search':
      case 'url_fetch':
        return '基础实用';
      case 'file_read':
      case 'file_write':
      case 'file_list':
      case 'file_delete':
      case 'code_eval':
      case 'clipboard_read':
      case 'clipboard_write':
        return '沙箱与代码';
      case 'calendar_query_events':
      case 'calendar_create_event':
      case 'notification_schedule':
      case 'notification_cancel':
      case 'contacts_search':
      case 'geolocation_get':
      case 'reverse_geocode':
        return '移动原生';
      default:
        return '基础实用';
    }
  }

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
  static List<Map<String, dynamic>> parsePseudoXmlToolCalls(String content) {
    final results = <Map<String, dynamic>>[];

    // 1. Standard <tool_call> parsing
    final toolCallBlockRegex = RegExp(
      r'<tool_call>\s*<function=([\w\-]+)>([\s\S]*?)</function>\s*</tool_call>',
      multiLine: true,
    );
    for (final match in toolCallBlockRegex.allMatches(content)) {
      final name = match.group(1) ?? '';
      final blockContent = match.group(2) ?? '';
      final paramMap = <String, String>{};
      final paramRegex = RegExp(
        r'<parameter=([\w\-]+)>([\s\S]*?)</parameter>',
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
        r'<[|｜]{2}DSML[|｜]{2}invoke name="([\w\-]+)">([\s\S]*?)</[|｜]{2}DSML[|｜]{2}invoke>',
        multiLine: true,
      );
      for (final invokeMatch in invokeRegex.allMatches(blockContent)) {
        final funcName = invokeMatch.group(1) ?? '';
        final invokeContent = invokeMatch.group(2) ?? '';

        final paramMap = <String, String>{};
        final paramRegex = RegExp(
          r'<[|｜]{2}DSML[|｜]{2}parameter name="([\w\-]+)"[^>]*>([\s\S]*?)</[|｜]{2}DSML[|｜]{2}parameter>',
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
      r'<tool_call>\s*<function=[\w\-]+>[\s\S]*?</function>\s*</tool_call>',
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
    } else if (name == 'calendar_create_event') {
      return {
        'title': args['title']?.toString() ?? '',
        'start_time': args['start_time']?.toString() ?? '',
        'end_time': args['end_time']?.toString() ?? '',
        'location': args['location']?.toString(),
        'description': args['description']?.toString(),
        'reminder_minutes': args['reminder_minutes'] ?? args['remind_minutes_before'],
        'is_all_day': args['is_all_day'] == true,
      };
    } else if (name == 'notification_schedule') {
      return {
        'title': args['title']?.toString() ?? '',
        'body': args['body']?.toString() ?? '',
        'scheduled_time': args['scheduled_time']?.toString() ?? args['trigger_time']?.toString() ?? '',
        'notification_id': args['notification_id']?.toString(),
        'payload': args['payload']?.toString(),
        'is_exact_alarm': args['is_exact_alarm'] != false,
      };
    }
    return args;
  }

  /// Executes a tool with fault-tolerant exponential backoff retry and self-healing diagnostic error packaging.
  Future<ToolExecutionResult> _executeToolSafely(
    String name,
    Map<String, dynamic> args, {
    Map<String, dynamic>? context,
    CancelToken? cancelToken,
  }) async {
    final isExternalOrMcp = name == 'web_search' ||
        name == 'google_search' ||
        name == 'bing_search' ||
        name == 'url_fetch' ||
        name == 'weather_query' ||
        name == 'wiki_lookup' ||
        name.startsWith('mcp_');

    ToolExecutionResult result;
    try {
      if (isExternalOrMcp) {
        result = await _agentFaultTolerance.executeWithRetry<ToolExecutionResult>(
          () async {
            final res = await _toolRegistry.execute(name, args, context: context);
            if (!res.isSuccess && res.errorMessage != null) {
              final err = res.errorMessage!;
              if (err.contains('Timeout') ||
                  err.contains('timeout') ||
                  err.contains('连接') ||
                  err.contains('超时') ||
                  err.contains('SocketException') ||
                  err.contains('429') ||
                  err.contains('500') ||
                  err.contains('502') ||
                  err.contains('503') ||
                  err.contains('504')) {
                throw DioException(
                  requestOptions: RequestOptions(path: ''),
                  type: DioExceptionType.connectionTimeout,
                  error: err,
                );
              }
            }
            return res;
          },
          cancelToken: cancelToken,
        );
      } else {
        result = await _toolRegistry.execute(name, args, context: context);
      }
    } catch (e) {
      developer.log('Tool execution failed for $name: $e', name: 'AgentService');
      final feedback = _agentFaultTolerance.generateSelfHealingFeedback(
        toolName: name,
        arguments: args,
        errorMessage: e.toString(),
      );
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.toString(),
        content: feedback,
        rawData: {'error': e.toString(), 'selfHealingFeedback': feedback},
      );
    }

    if (!result.isSuccess && (result.content.isEmpty || !result.content.contains('【工具'))) {
      final feedback = _agentFaultTolerance.generateSelfHealingFeedback(
        toolName: name,
        arguments: args,
        errorMessage: result.errorMessage ?? '执行失败',
      );
      result = ToolExecutionResult.failure(
        toolName: name,
        errorMessage: result.errorMessage ?? '执行失败',
        content: feedback,
        rawData: result.rawData,
      );
    }

    return result;
  }

  /// Main entry point coordinating completion streaming, tool execution, token budgeting, and fault tolerance.
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

      final stopwatch = Stopwatch()..start();
      List<SearchResult> results;
      String? searchError;
      try {
        results = await _agentFaultTolerance.executeWithRetry<List<SearchResult>>(
          () => _searchService.search(
            query: query,
            searxngUrl: searxngUrl,
            searchBackend: searchBackend,
            googleApiKey: googleApiKey,
            googleBaseUrl: googleBaseUrl,
            googleSearchModel: googleSearchModel,
            bingCookie: bingCookie,
          ),
          cancelToken: cancelToken,
        );
      } catch (e) {
        results = [];
        searchError = e is SearchException ? e.message : e.toString();
        developer.log('Manual search failed: $searchError', name: 'AgentService');
      }
      stopwatch.stop();

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

      final stepTelemetry = AgentStepTelemetry(
        stepIndex: 1,
        toolName: searchToolName,
        toolCategory: '基础实用',
        durationMs: stopwatch.elapsedMilliseconds,
        intent: '用户指定手工搜索指令',
        arguments: {'query': query},
        outputPreview: formattedResults.length > 200 ? '${formattedResults.substring(0, 200)}...' : formattedResults,
        fullOutput: formattedResults,
        isSuccess: searchError == null,
        errorMessage: searchError,
        timestamp: DateTime.now(),
      );
      yield AgentStepTelemetryEvent(stepTelemetry);

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
        stepIndexOffset: 1,
      );
    } else {
      // 1. Pre-flight Token Budget & Sliding Window Compaction (Round 0)
      final budgetResult = _tokenBudgetManager.evaluateAndCompact(
        messages: effectiveMessages,
        tools: effectiveTools,
        currentRound: 0,
      );

      yield TokenBudgetTelemetryEvent(budgetResult.toTelemetry());

      if (budgetResult.status == BudgetActionStatus.circuitBreakerTriggered || budgetResult.shouldStripTools) {
        yield CircuitBreakerTriggeredEvent(
          '当前会话上下文已达 ${budgetResult.estimatedPromptTokens} Tokens（超出模型安全上限）',
          budgetResult.estimatedPromptTokens,
          budgetResult.maxContextTokens,
        );

        final forcedPrompt = budgetResult.forcedConclusionPrompt ??
            '【系统安全熔断】当前会话上下文已达 ${budgetResult.estimatedPromptTokens} Tokens（超出模型安全上限）。请立即基于前面已获得的全部工具执行数据与分析，为用户输出完整、详尽的最终总结性回答，禁止再次调用任何工具。';

        yield* _streamFinalConclusion(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: budgetResult.effectiveMessages,
          prompt: forcedPrompt,
          reasoningEffort: reasoningEffort,
          cancelToken: cancelToken,
        );
        return;
      }

      final activeMessages = budgetResult.effectiveMessages;
      final accumulatedToolCalls = <int, _ToolCallAccumulator>{};
      final contentBuffer = StringBuffer();
      final reasoningBuffer = StringBuffer();

      int? mainPromptTokens;
      int? mainCompletionTokens;

      await for (final chunk in _chatService.chatCompletionsStream(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: activeMessages,
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
        final conversationId = activeMessages.last.conversationId;
        int executedCount = 0;

        for (final entry in accumulatedToolCalls.values) {
          final name = entry.name;
          final rawArgsString = entry.argumentsBuffer.toString();
          final args = _agentFaultTolerance.repairAndParseArguments(rawArgsString);

          // Guard check before execution
          final verdict = activeGuard.checkBeforeExecution(name, args, currentRound: 0);
          if (verdict.isBlocked) {
            final prompt = activeGuard.getForcedConclusionPrompt(verdict: verdict);
            yield* _streamFinalConclusion(
              baseUrl: baseUrl,
              apiKey: apiKey,
              model: model,
              messages: activeMessages,
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
          final stopwatch = Stopwatch()..start();

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
                final url = args['url']?.toString() ?? '';
                yield UrlFetchStartedEvent(url);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = args['query']?.toString() ?? '';
                yield ToolCallStartedEvent(query);
              } else {
                final title = '${toolObj.displayName}: ${args.values.join(', ')}';
                yield ToolCallStartedEvent(title);
              }

              result = await _executeToolSafely(name, args, context: context, cancelToken: cancelToken);
              _checkCancellation(cancelToken);

              if (name == 'url_fetch') {
                final url = args['url']?.toString() ?? '';
                yield UrlFetchCompletedEvent(url, result.content);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = args['query']?.toString() ?? '';
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
              final url = args['url']?.toString() ?? '';
              yield UrlFetchStartedEvent(url);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = args['query']?.toString() ?? '';
              yield ToolCallStartedEvent(query);
            } else {
              final title = toolObj != null ? '${toolObj.displayName}: ${args.values.join(', ')}' : name;
              yield ToolCallStartedEvent(title);
            }

            result = await _executeToolSafely(name, args, context: context, cancelToken: cancelToken);
            _checkCancellation(cancelToken);

            if (name == 'url_fetch') {
              final url = args['url']?.toString() ?? '';
              yield UrlFetchCompletedEvent(url, result.content);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = args['query']?.toString() ?? '';
              final rawResults = (result.rawData is List<SearchResult>)
                  ? (result.rawData as List<SearchResult>)
                  : <SearchResult>[];
              yield ToolCallCompletedEvent(query, rawResults);
            } else {
              yield ToolCallCompletedEvent(name, []);
            }
          }
          stopwatch.stop();

          executedCount++;
          final stepTelemetry = AgentStepTelemetry(
            stepIndex: executedCount,
            toolName: name,
            toolCategory: categorizeTool(name),
            durationMs: stopwatch.elapsedMilliseconds,
            intent: reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : (contentBuffer.isNotEmpty ? contentBuffer.toString() : null),
            arguments: args,
            outputPreview: result.content.length > 200 ? '${result.content.substring(0, 200)}...' : result.content,
            fullOutput: result.content,
            isSuccess: result.isSuccess,
            errorMessage: result.errorMessage,
            promptTokens: mainPromptTokens,
            completionTokens: mainCompletionTokens,
            timestamp: DateTime.now(),
          );
          yield AgentStepTelemetryEvent(stepTelemetry);

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
          ...activeMessages,
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
          stepIndexOffset: executedCount,
        );
      } else {
        // --- First round: check for multi-format tool call / pseudo-XML fallback ---
        final fullContent = contentBuffer.toString();
        final multiFormatCalls = _agentFaultTolerance.parseToolCalls(fullContent);
        final pseudoCalls = multiFormatCalls.isNotEmpty
            ? multiFormatCalls.map((c) => {'name': c.toolName, 'params': c.arguments}).toList()
            : parsePseudoXmlToolCalls(fullContent);

        if (pseudoCalls.isNotEmpty && effectiveTools.isNotEmpty) {
          final cleanedContent = multiFormatCalls.isNotEmpty
              ? _agentFaultTolerance.stripToolCallBlocks(fullContent)
              : stripPseudoXmlToolCalls(fullContent);
          final conversationId = activeMessages.last.conversationId;
          final toolMessages = <ChatMessage>[];
          final toolCallList = <ToolCall>[];
          int executedCount = 0;

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
                messages: activeMessages,
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
            final stopwatch = Stopwatch()..start();

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
                  final url = params['url']?.toString() ?? '';
                  yield UrlFetchStartedEvent(url);
                } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                  final query = params['query']?.toString() ?? '';
                  yield ToolCallStartedEvent(query);
                } else {
                  final title = '${toolObj.displayName}: ${params.values.join(', ')}';
                  yield ToolCallStartedEvent(title);
                }

                result = await _executeToolSafely(name, params, context: context, cancelToken: cancelToken);
                _checkCancellation(cancelToken);

                if (name == 'url_fetch') {
                  final url = params['url']?.toString() ?? '';
                  yield UrlFetchCompletedEvent(url, result.content);
                } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                  final query = params['query']?.toString() ?? '';
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
                final url = params['url']?.toString() ?? '';
                yield UrlFetchStartedEvent(url);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = params['query']?.toString() ?? '';
                yield ToolCallStartedEvent(query);
              } else {
                final title = toolObj != null ? '${toolObj.displayName}: ${params.values.join(', ')}' : name;
                yield ToolCallStartedEvent(title);
              }

              result = await _executeToolSafely(name, params, context: context, cancelToken: cancelToken);
              _checkCancellation(cancelToken);

              if (name == 'url_fetch') {
                final url = params['url']?.toString() ?? '';
                yield UrlFetchCompletedEvent(url, result.content);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = params['query']?.toString() ?? '';
                final rawResults = (result.rawData is List<SearchResult>)
                    ? (result.rawData as List<SearchResult>)
                    : <SearchResult>[];
                yield ToolCallCompletedEvent(query, rawResults);
              } else {
                yield ToolCallCompletedEvent(name, []);
              }
            }
            stopwatch.stop();

            executedCount++;
            final stepTelemetry = AgentStepTelemetry(
              stepIndex: executedCount,
              toolName: name,
              toolCategory: categorizeTool(name),
              durationMs: stopwatch.elapsedMilliseconds,
              intent: reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : (contentBuffer.isNotEmpty ? contentBuffer.toString() : null),
              arguments: params,
              outputPreview: result.content.length > 200 ? '${result.content.substring(0, 200)}...' : result.content,
              fullOutput: result.content,
              isSuccess: result.isSuccess,
              errorMessage: result.errorMessage,
              promptTokens: mainPromptTokens,
              completionTokens: mainCompletionTokens,
              timestamp: DateTime.now(),
            );
            yield AgentStepTelemetryEvent(stepTelemetry);

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
              ...activeMessages,
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
              stepIndexOffset: executedCount,
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
    int stepIndexOffset = 0,
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
      stepIndexOffset: stepIndexOffset,
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

  /// Internal recursive loop that handles one round of streaming + tool execution with Token Budget & Fault Tolerance.
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
    int stepIndexOffset = 0,
  }) async* {
    final activeGuard = guard ?? guardFactory?.call() ?? AgentLoopGuard(maxToolRounds: maxToolRounds);

    // 1. Max total tool rounds or loop guard check
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

    // 2. Pre-flight Token Budget & Sliding Window Compaction
    final budgetResult = _tokenBudgetManager.evaluateAndCompact(
      messages: messages,
      tools: tools,
      currentRound: toolRound,
    );

    yield TokenBudgetTelemetryEvent(budgetResult.toTelemetry());

    if (budgetResult.status == BudgetActionStatus.circuitBreakerTriggered || budgetResult.shouldStripTools) {
      yield CircuitBreakerTriggeredEvent(
        '当前会话上下文已达 ${budgetResult.estimatedPromptTokens} Tokens（超出模型安全上限）',
        budgetResult.estimatedPromptTokens,
        budgetResult.maxContextTokens,
      );

      final forcedPrompt = budgetResult.forcedConclusionPrompt ??
          '【系统安全熔断】当前会话上下文已达 ${budgetResult.estimatedPromptTokens} Tokens（超出模型安全上限）。请立即基于前面已获得的全部工具执行数据与分析，为用户输出完整、详尽的最终总结性回答，禁止再次调用任何工具。';

      yield* _streamFinalConclusion(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: budgetResult.effectiveMessages,
        prompt: forcedPrompt,
        reasoningEffort: reasoningEffort,
        cancelToken: cancelToken,
      );
      return;
    }

    final activeMessages = budgetResult.effectiveMessages;
    final accumulatedToolCalls = <int, _ToolCallAccumulator>{};
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    int? promptTokens;
    int? completionTokens;

    await for (final chunk in _chatService.chatCompletionsStream(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: activeMessages,
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
            // Delay yielding content if tools are configured (might be multi-format tool call to strip)
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
      final conversationId = activeMessages.last.conversationId;
      final toolMessages = <ChatMessage>[];
      int executedCount = 0;

      for (final entry in accumulatedToolCalls.values) {
        final name = entry.name;
        final rawArgsString = entry.argumentsBuffer.toString();
        final args = _agentFaultTolerance.repairAndParseArguments(rawArgsString);

        // Guard check before execution
        final verdict = activeGuard.checkBeforeExecution(name, args, currentRound: toolRound + 1);
        if (verdict.isBlocked) {
          final prompt = activeGuard.getForcedConclusionPrompt(verdict: verdict);
          yield* _streamFinalConclusion(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            messages: activeMessages,
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
        final stopwatch = Stopwatch()..start();

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
              final url = args['url']?.toString() ?? '';
              yield UrlFetchStartedEvent(url);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = args['query']?.toString() ?? '';
              yield ToolCallStartedEvent(query);
            } else {
              final title = '${toolObj.displayName}: ${args.values.join(', ')}';
              yield ToolCallStartedEvent(title);
            }

            result = await _executeToolSafely(name, args, context: context, cancelToken: cancelToken);
            _checkCancellation(cancelToken);

            if (name == 'url_fetch') {
              final url = args['url']?.toString() ?? '';
              yield UrlFetchCompletedEvent(url, result.content);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = args['query']?.toString() ?? '';
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
            final url = args['url']?.toString() ?? '';
            yield UrlFetchStartedEvent(url);
          } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
            final query = args['query']?.toString() ?? '';
            yield ToolCallStartedEvent(query);
          } else {
            final title = toolObj != null ? '${toolObj.displayName}: ${args.values.join(', ')}' : name;
            yield ToolCallStartedEvent(title);
          }

          result = await _executeToolSafely(name, args, context: context, cancelToken: cancelToken);
          _checkCancellation(cancelToken);

          if (name == 'url_fetch') {
            final url = args['url']?.toString() ?? '';
            yield UrlFetchCompletedEvent(url, result.content);
          } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
            final query = args['query']?.toString() ?? '';
            final rawResults = (result.rawData is List<SearchResult>)
                ? (result.rawData as List<SearchResult>)
                : <SearchResult>[];
            yield ToolCallCompletedEvent(query, rawResults);
          } else {
            yield ToolCallCompletedEvent(name, []);
          }
        }
        stopwatch.stop();

        executedCount++;
        final stepTelemetry = AgentStepTelemetry(
          stepIndex: stepIndexOffset + executedCount,
          toolName: name,
          toolCategory: categorizeTool(name),
          durationMs: stopwatch.elapsedMilliseconds,
          intent: reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : (contentBuffer.isNotEmpty ? contentBuffer.toString() : null),
          arguments: args,
          outputPreview: result.content.length > 200 ? '${result.content.substring(0, 200)}...' : result.content,
          fullOutput: result.content,
          isSuccess: result.isSuccess,
          errorMessage: result.errorMessage,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          timestamp: DateTime.now(),
        );
        yield AgentStepTelemetryEvent(stepTelemetry);

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
        ...activeMessages,
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
        stepIndexOffset: stepIndexOffset + executedCount,
      );
    } else {
      // --- No standard tool_calls; check for multi-format tool call / pseudo-XML fallback ---
      final fullContent = contentBuffer.toString();
      final multiFormatCalls = _agentFaultTolerance.parseToolCalls(fullContent);
      final pseudoCalls = multiFormatCalls.isNotEmpty
          ? multiFormatCalls.map((c) => {'name': c.toolName, 'params': c.arguments}).toList()
          : parsePseudoXmlToolCalls(fullContent);

      if (pseudoCalls.isNotEmpty && tools != null && tools.isNotEmpty) {
        final cleanedContent = multiFormatCalls.isNotEmpty
            ? _agentFaultTolerance.stripToolCallBlocks(fullContent)
            : stripPseudoXmlToolCalls(fullContent);
        final conversationId = activeMessages.last.conversationId;
        final toolMessages = <ChatMessage>[];
        final toolCallList = <ToolCall>[];
        int executedCount = 0;

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
              messages: activeMessages,
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
          final stopwatch = Stopwatch()..start();

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
                final url = params['url']?.toString() ?? '';
                yield UrlFetchStartedEvent(url);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = params['query']?.toString() ?? '';
                yield ToolCallStartedEvent(query);
              } else {
                final title = '${toolObj.displayName}: ${params.values.join(', ')}';
                yield ToolCallStartedEvent(title);
              }

              result = await _executeToolSafely(name, params, context: context, cancelToken: cancelToken);
              _checkCancellation(cancelToken);

              if (name == 'url_fetch') {
                final url = params['url']?.toString() ?? '';
                yield UrlFetchCompletedEvent(url, result.content);
              } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
                final query = params['query']?.toString() ?? '';
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
              final url = params['url']?.toString() ?? '';
              yield UrlFetchStartedEvent(url);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = params['query']?.toString() ?? '';
              yield ToolCallStartedEvent(query);
            } else {
              final title = toolObj != null ? '${toolObj.displayName}: ${params.values.join(', ')}' : name;
              yield ToolCallStartedEvent(title);
            }

            result = await _executeToolSafely(name, params, context: context, cancelToken: cancelToken);
            _checkCancellation(cancelToken);

            if (name == 'url_fetch') {
              final url = params['url']?.toString() ?? '';
              yield UrlFetchCompletedEvent(url, result.content);
            } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
              final query = params['query']?.toString() ?? '';
              final rawResults = (result.rawData is List<SearchResult>)
                  ? (result.rawData as List<SearchResult>)
                  : <SearchResult>[];
              yield ToolCallCompletedEvent(query, rawResults);
            } else {
              yield ToolCallCompletedEvent(name, []);
            }
          }
          stopwatch.stop();

          executedCount++;
          final stepTelemetry = AgentStepTelemetry(
            stepIndex: stepIndexOffset + executedCount,
            toolName: name,
            toolCategory: categorizeTool(name),
            durationMs: stopwatch.elapsedMilliseconds,
            intent: reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : (contentBuffer.isNotEmpty ? contentBuffer.toString() : null),
            arguments: params,
            outputPreview: result.content.length > 200 ? '${result.content.substring(0, 200)}...' : result.content,
            fullOutput: result.content,
            isSuccess: result.isSuccess,
            errorMessage: result.errorMessage,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            timestamp: DateTime.now(),
          );
          yield AgentStepTelemetryEvent(stepTelemetry);

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
            ...activeMessages,
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
            stepIndexOffset: stepIndexOffset + executedCount,
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
