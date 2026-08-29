# Milestone 23.4: Complete Integration & UI Enhancement Design Report

## Executive Summary
This report provides the comprehensive architecture, integration specifications, UI enhancements, and E2E verification plan for **Milestone 23.4** (Agent Pipeline Integration, UI Enhancement & Final Hardening).
Milestone 23 introduces a pluggable `ToolRegistry`, four safe built-in tools (`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`), and an `AgentLoopGuard` anti-loop defense engine. Milestone 23.4 completes the end-to-end connection across the pipeline, provides rich visual components in `ChatBubble`, provides extensive E2E integration tests, and bumps the application version to `1.08.0+9`.

---

## 1. System Architecture & Component Interactions

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             ChatProvider / UI                               │
│  (Manages ConversationState, streaming events, DB persistence, UI rendering) │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                               AgentService                                  │
│  - Tool schema resolution via ToolRegistry                                  │
│  - Multi-round completion streaming loop                                     │
│  - Guard enforcement via AgentLoopGuard (duplicate, oscillation, max rounds) │
│  - Execution dispatch via ToolRegistry.execute()                             │
│  - Pseudo-XML / DSML fallback parsing                                       │
└──────────────┬───────────────────────┬───────────────────────┬──────────────┘
               │                       │                       │
               ▼                       ▼                       ▼
┌────────────────────────┐  ┌────────────────────┐  ┌─────────────────────────┐
│     AgentLoopGuard     │  │    ToolRegistry    │  │       ChatService       │
│  - Signature MD5 hash  │  │  - Built-in tools  │  │  - SSE stream parser    │
│  - Duplicate check     │  │  - Legacy adapters │  │  - /v1/chat/completions │
│  - Oscillation cycle   │  │  - Schema export   │  │  - Token usage parser   │
│  - Tool strip fallback │  │  - Safe dispatch   │  │  - CancelToken check    │
└────────────────────────┘  └─────────┬──────────┘  └─────────────────────────┘
                                      │
           ┌──────────────────────────┼──────────────────────────┐
           ▼                          ▼                          ▼
┌───────────────────────┐  ┌───────────────────────┐  ┌───────────────────────┐
│  Safe Built-in Tools  │  │ Legacy Search & Web   │  │   Future Ext. Tools   │
│ - math_eval           │  │ - web_search (SearX)  │  │ - MCP Tools           │
│ - time_calculator     │  │ - google_search       │  │ - Local File / Device │
│ - weather_query       │  │ - bing_search         │  │                       │
│ - wiki_lookup         │  │ - url_fetch           │  │                       │
└───────────────────────┘  └───────────────────────┘  └───────────────────────┘
```

---

## 2. Component Design & Code Modifications

### 2.1 `lib/services/agent_service.dart`

#### Design Objectives:
1. Accept `ToolRegistry` and `AgentLoopGuard` in constructors with robust default fallbacks.
2. In `getEffectiveTools`, support dynamic schema export from `ToolRegistry` while maintaining 100% backward compatibility for existing unit tests.
3. In `_streamCompletionsLoop`, protect every tool invocation round with `AgentLoopGuard`:
   - Consecutive duplicate signatures (>=3 times) -> strip tools & inject conclusion prompt.
   - Periodic oscillation cycles (period 2/3) -> strip tools & inject conclusion prompt.
   - Max tool round limit reached (`toolRound >= maxToolRounds - 1`) -> strip tools & inject conclusion prompt.
4. Unify tool execution via `ToolRegistry.execute(name, arguments, context: context)`.
5. Support all safe built-in tools (`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`) alongside legacy adapters (`web_search`, `google_search`, `bing_search`, `url_fetch`).
6. Retain full support for manual `@search`, pseudo-XML `<tool_call>`, DSML `<｜｜DSML｜｜tool_calls>`, token usage parsing, and cancellation tokens.

#### Detailed Code Specification:
```dart
class AgentService {
  final ChatService _chatService;
  final SearchService _searchService;
  final UrlFetchService _urlFetchService;
  final ToolRegistry _toolRegistry;
  final AgentLoopGuard Function()? _guardFactory;
  final Uuid _uuid;

  AgentService({
    ChatService? chatService,
    SearchService? searchService,
    UrlFetchService? urlFetchService,
    ToolRegistry? toolRegistry,
    AgentLoopGuard Function()? guardFactory,
  })  : _chatService = chatService ?? ChatService(),
        _searchService = searchService ?? SearchService(),
        _urlFetchService = urlFetchService ?? UrlFetchService(),
        _toolRegistry = toolRegistry ??
            ToolRegistry.defaultRegistry(
              searchService: searchService,
              urlFetchService: urlFetchService,
            ),
        _guardFactory = guardFactory,
        _uuid = const Uuid();

  /// Legacy static schema definitions retained for backward compatibility.
  static const Map<String, dynamic> webSearchTool = ...;
  static const Map<String, dynamic> googleSearchTool = ...;
  static const Map<String, dynamic> bingSearchTool = ...;
  static const Map<String, dynamic> urlFetchTool = ...;

  /// Returns effective tool schemas passed to the LLM.
  /// 
  /// When [toolRegistry] is provided:
  /// - Filters search tools based on [enableAutoSearch] and [searchBackend].
  /// - Includes all other enabled tools from the registry.
  /// 
  /// When [toolRegistry] is null and [includeBasicTools] is false:
  /// - Preserves exact legacy tool list for 100% backward compatibility.
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
```

#### Execution & Guard Loop Specification:
```dart
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
    int maxToolRounds = 8,
    AgentLoopGuard? guard,
  }) async* {
    final activeGuard = guard ?? _guardFactory?.call() ?? AgentLoopGuard(maxToolRounds: maxToolRounds);

    // 1. Check if tool round limit reached
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

    // 2. Stream completions with tools
    ...
    // 3. When tool calls are received (accumulatedToolCalls or pseudoCalls):
    for (final entry in accumulatedToolCalls.values) {
      final name = entry.name;
      Map<String, dynamic> args;
      try {
        args = json.decode(entry.argumentsBuffer.toString()) as Map<String, dynamic>;
      } catch (_) {
        args = {'query': entry.argumentsBuffer.toString()};
      }

      // Check Guard before execution
      final verdict = activeGuard.checkBeforeExecution(name, args, currentRound: toolRound);
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

      // Record invocation
      activeGuard.recordToolCall(name, args);

      // Context parameters for execution
      final context = {
        'searxngUrl': searxngUrl,
        'searchBackend': searchBackend,
        'googleApiKey': googleApiKey,
        'googleBaseUrl': googleBaseUrl,
        'googleSearchModel': googleSearchModel,
        'bingCookie': bingCookie,
        'cancelToken': cancelToken,
      };

      // Emit UI started event
      if (name == 'url_fetch') {
        yield UrlFetchStartedEvent(args['url'] as String? ?? '');
      } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
        yield ToolCallStartedEvent(args['query'] as String? ?? '');
      } else {
        final toolObj = _toolRegistry.getTool(name);
        final title = toolObj != null ? '${toolObj.displayName}: ${args.values.join(', ')}' : name;
        yield ToolCallStartedEvent(title);
      }

      // Execute tool via registry
      final result = await _toolRegistry.execute(name, args, context: context);

      // Emit UI completed event
      if (name == 'url_fetch') {
        yield UrlFetchCompletedEvent(args['url'] as String? ?? '', result.content ?? '');
      } else if (name == 'web_search' || name == 'google_search' || name == 'bing_search') {
        final rawResults = (result.rawData is List<SearchResult>) ? (result.rawData as List<SearchResult>) : <SearchResult>[];
        yield ToolCallCompletedEvent(args['query'] as String? ?? '', rawResults);
      } else {
        yield ToolCallCompletedEvent(name, []);
      }

      toolMessages.add(ChatMessage(
        id: _uuid.v4(),
        conversationId: conversationId,
        role: 'tool',
        toolCallId: entry.id,
        content: result.content ?? result.errorMessage ?? '执行完成',
        timestamp: DateTime.now(),
      ));
    }
```

---

### 2.2 `lib/widgets/chat_bubble.dart` UI Enhancements

#### Visual Design Features:
1. **Tool Categorization & Chinese Metadata Mapping**:
   | Tool Name | Display Name | Category | Icon | Security Badge |
   |-----------|--------------|----------|------|----------------|
   | `math_eval` | 数学计算 | 基础计算 | `Icons.calculate` | `安全 Level 0` |
   | `time_calculator` | 时间/时区计算 | 时间工具 | `Icons.schedule` | `安全 Level 0` |
   | `weather_query` | 天气查询 | 生活服务 | `Icons.cloud` | `安全 Level 0` |
   | `wiki_lookup` | 维基百科检索 | 知识检索 | `Icons.menu_book` | `安全 Level 0` |
   | `web_search` | 网络搜索 | 搜索引擎 | `Icons.travel_explore` | `只读 Level 1` |
   | `google_search` | Google 搜索 | 搜索引擎 | `Icons.travel_explore` | `只读 Level 1` |
   | `bing_search` | Bing 搜索 | 搜索引擎 | `Icons.travel_explore` | `只读 Level 1` |
   | `url_fetch` | 网页抓取 | 网页内容 | `Icons.language` | `只读 Level 1` |

2. **Intermediate Assistant Panel (`_buildIntermediateAssistantPanel`)**:
   - Header with `Icons.auto_awesome`, Chinese summarized tool names, and collapsible animation toggle.
   - Structured Tool Calling Cards:
     - Card container with themed surface background and subtle border.
     - Top row displaying Tool Icon, Chinese Display Name, English identifier chip, and Level chip.
     - Monospace code container displaying arguments clearly formatted.
   - Collapsible thinking process (`reasoningContent`) with italic typography.
   - Streaming markdown intermediate content preview.

3. **Tool Output Panel (`_buildToolOutputPanel`)**:
   - Header with `Icons.build_circle_outlined`, `'工具执行结果'` title (preserving widget test compatibility), completion status chip, and copy button.
   - Collapsible container rendering formatted Markdown output from the tool result.

---

### 2.3 `lib/providers/chat_provider.dart`

Connect Riverpod `toolRegistryProvider` to `agentServiceProvider`:
```dart
final agentServiceProvider = Provider<AgentService>((ref) {
  final chatSvc = ref.watch(chatServiceProvider);
  final searchSvc = ref.watch(searchServiceProvider);
  final urlFetchSvc = ref.watch(urlFetchServiceProvider);
  final toolRegistry = ref.watch(toolRegistryProvider);
  return AgentService(
    chatService: chatSvc,
    searchService: searchSvc,
    urlFetchService: urlFetchSvc,
    toolRegistry: toolRegistry,
  );
});
```

---

## 3. End-to-End Test Suite: `test/services/agent_service_tool_integration_test.dart`

### Test Structure & Coverage:

```
agent_service_tool_integration_test.dart
├── Group 1: Safe Basic Tools Multi-round Integration
│   ├── Test 1.1: math_eval single-round tool execution and response generation
│   ├── Test 1.2: time_calculator tool execution with timezone and relative date
│   ├── Test 1.3: weather_query tool execution with mocked Open-Meteo REST API
│   ├── Test 1.4: wiki_lookup tool execution with mocked Wikipedia REST API
│   └── Test 1.5: Multi-tool sequential chain (math_eval -> wiki_lookup -> final summary)
│
├── Group 2: AgentLoopGuard Defenses & Safety Ceilings
│   ├── Test 2.1: Consecutive duplicate tool invocation defense (>=3 duplicate calls stripped)
│   ├── Test 2.2: Cyclic oscillation detection (period 2 cycle A->B->A->B stripped & conclusion prompt injected)
│   ├── Test 2.3: Max tool rounds ceiling enforcement (forced conclusion at maxToolRounds - 1)
│   └── Test 2.4: Termination prompt verifies no further tool calls are permitted
│
├── Group 3: Error Resilience & Fault Tolerance
│   ├── Test 3.1: Tool argument validation failure handled gracefully without crashing
│   ├── Test 3.2: Runtime math divide-by-zero handled and reported to model
│   ├── Test 3.3: Disabled tool in ToolRegistry returns descriptive Chinese error
│   └── Test 3.4: Cancellation token aborts active multi-round tool loop cleanly
│
└── Group 4: Pseudo-XML & DSML Fallback with Basic Tools
    ├── Test 4.1: Pseudo-XML <tool_call><function=math_eval>...</tool_call> parsed and executed
    └── Test 4.2: DSML <｜｜DSML｜｜tool_calls> parsed and dispatched to ToolRegistry
```

---

## 4. Version Bump & Metadata Update Plan

1. **`pubspec.yaml`**:
   - Bump version to `1.08.0+9`
2. **`WORK_LOG.md`**:
   - Prepend Milestone 23 complete entry (M23.1 to M23.4) at the top of the file.
3. **`.agents/context.md`**:
   - Update Milestone table: Milestone 23 (Pluggable Tool Architecture & Safe Tools) marked as ✅ 完成.
   - Update version string to `1.08.0+9` and test count to 100% passing.

---

## 5. Quality & Acceptance Verification Matrix

| Check | Target | Command | Verification Standard |
|-------|--------|---------|-----------------------|
| 1. Unit Tests | All tests pass | `flutter test` | 0 failures, 100% pass (>=198 tests) |
| 2. Static Analysis | Clean analysis | `flutter analyze` | `No issues found!` (0 warnings/errors) |
| 3. Localization | UI strings | Manual inspection | 100% Chinese UI, tool names, and error feedback |
| 4. Versioning | Consistency | `pubspec.yaml`, `WORK_LOG.md`, `context.md` | `1.08.0+9` |
