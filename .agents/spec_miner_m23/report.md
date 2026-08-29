# Milestone 23 Specification & Acceptance Criteria Report
# (Pluggable Tool Architecture, 4 Safe Built-in Tools, AgentLoopGuard & UI Pipeline Integration)

> **Document Version**: v1.0.0-FINAL  
> **Author**: Spec Miner M23 (`teamwork_preview_spec_miner`)  
> **Target Project**: Flutter AI Chat (chat-app)  
> **Working Directory**: `D:\work\chat`  
> **Date**: 2026-08-28  

---

## 1. Executive Summary & Architectural Scope

Milestone 23 establishes the modular, extensible, and secure **Pluggable Tool Architecture** for the Flutter AI Chat application. It transitions the existing hardcoded search and webpage scraping tools into a unified, contract-driven **`ToolRegistry`** ecosystem, introduces the first suite of **4 Safe Built-in Tools** (`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`), integrates an **`AgentLoopGuard`** to eliminate infinite tool loops and oscillations, and provides streamlined **UI collapsible cards** and **Riverpod state management**.

### Core Deliverables of Milestone 23:
1. **R1: Pluggable Tool Architecture & ToolRegistry**:
   - `Tool` abstract base class, `ToolParameter`, `ToolExecutionContext`, `ToolExecutionResult`, `ToolExecutionStatus`.
   - 4-level security model (`PermissionLevel`: `safe`, `readOnly`, `sensitiveConfirm`, `privilegedNative`).
   - Category model (`ToolCategory`: `search`, `web`, `utility`, `fileSystem`, `codeExecution`, `mcp`, `nativeDevice`, `customPlugin`).
   - OpenAI Function Calling JSON Schema exporter (`exportOpenAiTools`) and pseudo-XML / System Prompt description generator (`exportSystemPromptDescription`).
   - Legacy tool adapters (`WebSearchTool`, `GoogleSearchTool`, `BingSearchTool`, `UrlFetchTool`).
   - Riverpod `toolRegistryProvider`.
2. **R2: 4 Safe Built-in Tools (Level 0 - `safe`)**:
   - `math_eval`: High-precision arithmetic, trigonometry, logarithms, square roots, statistics, units, and syntax error feedback.
   - `time_calculator`: Global IANA timezone queries/conversions, date offsets (`+3d`, `-5h30m`, `+2w`), time differences, and relative dates.
   - `weather_query`: Free Open-Meteo API integration (geocoding + real-time conditions + 7-day daily forecast).
   - `wiki_lookup`: Chinese & English Wikipedia REST API integration (summary, sections, search, and disambiguation handling).
3. **R3: AgentLoopGuard Engine**:
   - Signature/hash deduplication (detecting identical tool calls with identical arguments >= 3 times).
   - Oscillation detection (detecting A->B->A->B cyclical patterns).
   - Hard round cap (`maxToolRounds = 8`).
   - Graceful fallback: Stripping tools from the request and injecting a concluding prompt to force a final synthesized answer.
4. **R4: UI & Pipeline Integration**:
   - `AgentService` dynamic dispatch integration with `ToolRegistry`.
   - `ChatBubble` collapsible cards with Chinese status labels, category icons, execution duration badges, and copy buttons.
   - Quality metrics: 100% test pass rate (173 existing + 25+ new tests >= 198 total), `flutter analyze` 0 issues, version bump to `1.08.0+9`, `WORK_LOG.md` and `context.md` updates.

---

## 2. Features Discovered

| # | Category | Feature | Description | Inputs | Outputs | Error Behavior | Discovered Via |
|---|---|---|---|---|---|---|---|
| 1 | R1: Architecture | `Tool` Abstract Class | Standard interface defining tool contracts, metadata, parameters, validation, and execution. | `ToolExecutionContext`, `Map<String, dynamic> arguments` | `Future<ToolExecutionResult>` | Throws/returns structured failure with `ToolExecutionStatus` | `ORIGINAL_REQUEST.md`, `explorer_engine_gen7` |
| 2 | R1: Architecture | `ToolParameter` & `ParameterType` | Strongly typed parameter schema definition with JSON schema converter. | `name`, `type`, `description`, `isRequired`, `enumValues`, `defaultValue`, `properties` | OpenAI-compatible parameter JSON schema map | Throws `ToolValidationResult.invalid` on missing required params or invalid enum values | `ORIGINAL_REQUEST.md`, `explorer_engine_gen7` |
| 3 | R1: Architecture | `ToolExecutionResult` & `Status` | Standardized result container holding LLM context string, raw JSON, formatted Markdown, error, duration, truncation metadata. | `status`, `output`, `rawJson`, `formattedMarkdown`, `error`, `duration`, `isTruncated`, `metadata` | Structured result object with helper factories (`success`, `failure`, `deniedByUser`) | Captures execution errors, timeouts, and user rejections gracefully | `ORIGINAL_REQUEST.md`, `explorer_engine_gen7` |
| 4 | R1: Architecture | `PermissionLevel` (4-Tier) | Security classification: `safe` (0), `readOnly` (1), `sensitiveConfirm` (2), `privilegedNative` (3). | Permission enum assigned per tool | Security policy enforcement | Blocks unauthorized execution; requires confirmation for level >= 2 | `ORIGINAL_REQUEST.md`, `AGENTS.md`, `explorer_engine_gen7` |
| 5 | R1: Architecture | `ToolCategory` | Categorical domain taxonomy with Chinese display names and Material Icon keys. | Category enum | Display names (`"基础实用"`, `"网络搜索"`, etc.) and icon names | Fallback to default icon | `ORIGINAL_REQUEST.md`, `explorer_engine_gen7` |
| 6 | R1: Architecture | `ToolRegistry` Service | Centralized catalog managing tool lifecycle, registration, lookup, filtering, and schema export. | Tools to register/unregister, `ModelInfo`, `AppSettings` | List of active tools, OpenAI `tools` JSON array, system prompt string | Returns empty list or skips disabled tools safely | `ORIGINAL_REQUEST.md`, `explorer_engine_gen7` |
| 7 | R1: Architecture | Legacy Tool Adapters | Adapters wrapping `SearchService` (`web_search`, `google_search`, `bing_search`) and `UrlFetchService` (`url_fetch`). | Standard tool arguments | `ToolExecutionResult` matching legacy output format | Wraps `SearchException` or `DioException` into `ToolExecutionResult.failure` | Existing `AgentService`, `SearchService`, `UrlFetchService` |
| 8 | R1: Architecture | `toolRegistryProvider` | Riverpod provider exposing `ToolRegistry` instance to the application widget tree. | Riverpod `ProviderRef` | `ToolRegistry` instance | N/A | `ORIGINAL_REQUEST.md`, `context.md` |
| 9 | R2: Built-in Tool | `math_eval` | Evaluates arithmetic, trigonometry, logs, sqrt, power, stats, factorial, and unit conversions. | `expression` (String), `angle_unit` (radian/degree), `precision` (int), `format` (decimal/scientific/fraction) | Formatted math result + calculation steps in Markdown and JSON | Returns friendly error on syntax error, division by zero, negative sqrt | `ORIGINAL_REQUEST.md`, `explorer_taxonomy_gen7` |
| 10 | R2: Built-in Tool | `time_calculator` | Computes IANA timezone conversions, current time, date offsets (`+3d`, `-5h30m`), time differences, and relative dates. | `operation`, `base_time`, `source_timezone`, `target_timezone`, `offset`, `end_time`, `relative_expression` | Structured time object + Chinese formatted Markdown string | Falls back to fuzzy timezone alias resolution (`Beijing` -> `Asia/Shanghai`) | `ORIGINAL_REQUEST.md`, `explorer_taxonomy_gen7` |
| 11 | R2: Built-in Tool | `weather_query` | Queries real-time weather, 7-day forecast, humidity, wind, and UV index via Open-Meteo. | `location` (city string) or `latitude`/`longitude` (num), `query_type`, `forecast_days`, `temperature_unit` | Weather condition data + 7-day forecast Markdown table | Returns location not found or network timeout error without crash | `ORIGINAL_REQUEST.md`, `explorer_taxonomy_gen7` |
| 12 | R2: Built-in Tool | `wiki_lookup` | Retrieves Wikipedia articles, summaries, section content, and disambiguation from `zh` and `en` Wikipedia. | `query` (topic string), `language` (zh/en), `mode` (summary/section/search/full_outline), `section_title`, `max_results` | Article summary + structured infobox + Markdown link | Auto-detects disambiguation pages; 404 auto-falls back to search suggestions | `ORIGINAL_REQUEST.md`, `explorer_taxonomy_gen7` |
| 13 | R3: Loop Guard | Duplicate Call Detection | Hashes tool name and arguments (canonical JSON / MD5) to detect repeated identical invocations. | Tool invocation stream | Detects consecutive count >= 3 or repetitive loops | Triggers loop warning and initiates loop break | `ORIGINAL_REQUEST.md`, `explorer_engine_gen7` |
| 14 | R3: Loop Guard | Oscillation Detection | Tracks tool call history sequence to detect alternating patterns (e.g. A -> B -> A -> B). | Tool call sequence history | Identifies cycle length 2 or 3 | Breaks cycle and initiates terminal synthesis | `ORIGINAL_REQUEST.md`, `explorer_engine_gen7` |
| 15 | R3: Loop Guard | Max Tool Rounds Cap | Enforces hard limit `maxToolRounds = 8` in the multi-turn agent loop. | Current round index `toolRound` | Permits execution if `toolRound < maxToolRounds - 1` | When `toolRound >= maxToolRounds - 1`, forces text-only completion | `ORIGINAL_REQUEST.md`, `context.md` |
| 16 | R3: Loop Guard | Graceful Synthesis Fallback | Strips `tools` from completion payload and injects a forced conclusion system prompt. | Context messages + accumulated tool responses | Direct synthesized answer stream | Prevents empty responses or infinite token consumption | `ORIGINAL_REQUEST.md`, `explorer_engine_gen7` |
| 17 | R4: Integration | Dynamic Dispatch Pipeline | Refactors `AgentService` to dispatch all tool executions through `ToolRegistry` and `AgentLoopGuard`. | Stream of SSE chunks / tool calls | Emits `AgentStreamEvent` sequence | Catches all tool execution exceptions without terminating stream | `ORIGINAL_REQUEST.md`, `AgentService` |
| 18 | R4: UI Rendering | Collapsible Tool Cards | `ChatBubble` rendering of tool execution with Chinese labels, category icons, duration badges, and copy buttons. | `ChatMessage.role == 'tool'` and intermediate `role == 'assistant'` | Expandable/collapsible UI widget | Collapsed by default; expands smoothly with `AnimatedCrossFade` | `ORIGINAL_REQUEST.md`, `chat_bubble.dart` |
| 19 | R4: Quality & Meta | Quality & Docs Update | All 173 + 25+ tests 100% pass, `flutter analyze` 0 issues, version bump to `1.08.0+9`, `WORK_LOG.md` and `context.md` updated. | Test and analyze commands | Clean verification output | Build/test failures block milestone completion | `AGENTS.md`, `pubspec.yaml` |

---

## 3. Edge Cases & Failure Modes

| # | Feature | Input / Scenario | Observed / Expected Behavior |
|---|---|---|---|
| 1 | `math_eval` | Division by zero: `"10 / 0"` or `"5 / (3 - 3)"` | Returns structured failure `{ "error": "除数不能为零 (Division by zero)" }` without throwing unhandled exception. |
| 2 | `math_eval` | Invalid syntax: `"2 * + / 3"`, unbalanced parentheses `"((3+4)*5"` | Returns structured failure `{ "error": "数学表达式语法错误: 括号不匹配或运算符不合法" }`. |
| 3 | `math_eval` | Negative square root or logarithm: `"sqrt(-16)"` or `"ln(0)"` | Returns error indicating domain violation for real numbers. |
| 4 | `math_eval` | Large expression or high power: `"9^999999"` | Detects numerical overflow and returns infinity or precision limit error safely within 500ms timeout. |
| 5 | `time_calculator` | Unrecognized timezone: `"Beijing"` or `"NewYork"` | Automatically resolves common aliases (`Beijing` -> `Asia/Shanghai`, `NewYork` -> `America/New_York`), or returns error with candidate list if unresolvable. |
| 6 | `time_calculator` | Leap year / Month end boundary: `"2024-02-28" + "+1d"` vs `"2025-02-28" + "+1d"` | Accurately handles leap year Feb 29 and standard month end roll-overs (Feb 28 -> Mar 1). |
| 7 | `time_calculator` | Malformed offset string: `"+abc"`, `"3days"` | Validates offset syntax regex `^[+-]?\d+[yMwdhms]$` and returns helpful usage error. |
| 8 | `weather_query` | Non-existent or ambiguous location: `"NonExistentCity12345"` | Geocoding API returns empty array; tool responds with `"未找到该城市或地理位置: NonExistentCity12345，请检查地名拼写"`. |
| 9 | `weather_query` | Network timeout or offline state | Catches `DioException` (connection timeout / socket exception) and returns `"天气查询网络超时，请检查网络连接"`. |
| 10 | `weather_query` | Extreme coordinates: `latitude: 95.0`, `longitude: -200.0` | Parameter validator rejects out-of-range latitude ([-90, 90]) and longitude ([-180, 180]). |
| 11 | `wiki_lookup` | Disambiguation page (e.g. query `"Mercury"`) | Detects `type == "disambiguation"` and returns list of candidate articles (e.g. Mercury (planet), Mercury (element)). |
| 12 | `wiki_lookup` | Article not found (404) | Automatically falls back to Wikipedia search API to return top 3-5 related topic titles. |
| 13 | `wiki_lookup` | Massive article content exceeding token limits | Truncates summary/sections to maximum 4000 characters and appends `"...\n\n[内容已截断以适应上下文限制]"`. |
| 14 | `AgentLoopGuard` | Consecutive identical tool calls: `weather_query(location: "Beijing")` x 3 | Detects duplicate argument hash on 3rd attempt; interrupts execution and warns the model. |
| 15 | `AgentLoopGuard` | Oscillating tool calls: `math_eval("1+1")` -> `time_calculator("current_time")` -> `math_eval("1+1")` -> `time_calculator("current_time")` | Detects cycle period 2; halts loop and triggers graceful summary fallback. |
| 16 | `AgentLoopGuard` | Max rounds reached (`toolRound == 7` when `maxToolRounds = 8`) | Strips `tools` array completely, injects Chinese concluding prompt, and forces final assistant text answer. |
| 17 | `ToolRegistry` | Non-tool-supporting model (e.g. `supportsTools == false`) | Generates pseudo-XML `<tool_call>` instruction prompt via `exportSystemPromptDescription` and injects into system messages. |
| 18 | `ChatBubble` | Tool returns massive text or empty content | Markdown renderer safely handles empty string or renders truncated text with copy button. |

---

## 4. Detailed Specification Breakdown

### 4.1 R1: Pluggable Tool Architecture & ToolRegistry

#### 4.1.1 Core Domain Models (`lib/models/tool/`)
- **`PermissionLevel` Enum**:
  - `safe`: Pure computational/local read without side effects. Auto-executes.
  - `readOnly`: External read-only operations (search, URL fetch). Auto-executes.
  - `sensitiveConfirm`: Workspace file write, clipboard change. Prompts for user confirmation.
  - `privilegedNative`: OS calendar, notifications, alarms, contacts. Requires OS permission and user confirmation.
- **`ToolCategory` Enum & Extension**:
  - Values: `search`, `web`, `utility`, `fileSystem`, `codeExecution`, `mcp`, `nativeDevice`, `customPlugin`.
  - Properties: `displayName` (Chinese), `iconName` (Material Icon string).
- **`ParameterType` Enum**:
  - Values: `string`, `integer`, `number`, `boolean`, `array`, `object`.
- **`ToolParameter` Class**:
  - Fields: `name` (String), `type` (ParameterType), `description` (String), `isRequired` (bool, default true), `defaultValue` (dynamic?), `enumValues` (List<dynamic>?), `itemSchema` (Map<String, dynamic>?), `properties` (Map<String, ToolParameter>?).
  - Method: `Map<String, dynamic> toOpenAiPropertySchema()`.
- **`ToolExecutionContext` Class**:
  - Fields: `conversationId` (String), `messageId` (String), `toolCallId` (String), `cancelToken` (CancelToken?), `environmentVariables` (Map<String, dynamic>), `onProgress` (Function(double progress, String statusMessage)?).
- **`ToolExecutionStatus` Enum**:
  - Values: `success`, `failure`, `deniedByUser`, `timeout`, `cancelled`, `schemaError`.
- **`ToolExecutionResult` Class**:
  - Fields: `status` (ToolExecutionStatus), `output` (String), `rawJson` (dynamic?), `formattedMarkdown` (String?), `error` (String?), `executionDuration` (Duration), `isTruncated` (bool), `originalLength` (int), `metadata` (Map<String, dynamic>).
  - Factories: `ToolExecutionResult.success(...)`, `ToolExecutionResult.failure(...)`, `ToolExecutionResult.deniedByUser(...)`.
- **`Tool` Abstract Base Class**:
  - Getters: `name`, `displayName`, `description`, `category`, `permissionLevel`, `parameters`, `metadata`, `isBuiltIn` (default true), `timeoutDuration` (default 15s), `maxRetries` (default 2).
  - Methods: `ToolValidationResult validateArguments(Map<String, dynamic> arguments)`, `Map<String, dynamic> toOpenAiTool()`, `Future<ToolExecutionResult> execute(ToolExecutionContext context, Map<String, dynamic> arguments)`.

#### 4.1.2 `ToolRegistry` (`lib/services/tool_registry.dart`)
- **State & Registration**:
  - Internal storage: `Map<String, Tool> _tools`.
  - Methods: `void register(Tool tool)`, `void registerAll(List<Tool> tools)`, `bool unregister(String toolName)`, `Tool? getTool(String name)`, `List<Tool> getAllTools()`, `List<Tool> filterByCategory(ToolCategory category)`.
- **Filtering & Export**:
  - `List<Tool> getEffectiveTools({required ModelInfo model, required AppSettings settings, Set<String> disabledToolNames})`: Respects `enableTools`, `enableAutoSearch`, and search backend settings (`searxng`, `google`, `bing`, `google_bing`).
  - `List<Map<String, dynamic>> exportOpenAiTools(List<Tool> tools)`: Produces `[{ "type": "function", "function": { ... } }]`.
  - `String exportSystemPromptDescription(List<Tool> tools)`: Generates pseudo-XML specification prompt for models without native tool calling.

#### 4.1.3 Legacy Adapters
- `WebSearchTool`: Wraps `SearchService.search(searchBackend: 'searxng')`.
- `GoogleSearchTool`: Wraps `SearchService.search(searchBackend: 'google')`.
- `BingSearchTool`: Wraps `SearchService.search(searchBackend: 'bing')`.
- `UrlFetchTool`: Wraps `UrlFetchService.fetchUrlContent(url)`.

#### 4.1.4 Riverpod State Provider (`lib/providers/tool_registry_provider.dart`)
- `final toolRegistryProvider = Provider<ToolRegistry>((ref) => ...)` initialized with all default tools.

---

### 4.2 R2: 4 Safe Built-in Tools Specification

#### 4.2.1 `math_eval` (`lib/tools/math_eval_tool.dart`)
- **Identifier**: `math_eval` (`ToolCategory.utility`, `PermissionLevel.safe`)
- **Capabilities**:
  - Arithmetic: `+`, `-`, `*`, `/`, `^`, `%`, `//` (integer division).
  - Trigonometry: `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2` with `angle_unit` (`radian` vs `degree`).
  - Logs & Exponents: `log` (base 10), `ln` (natural), `log2`, `exp`, `sqrt`, `cbrt`.
  - Statistics: `mean([1,2,3])`, `median([1,2,3])`, `variance([1,2,3])`, `stddev([1,2,3])`, `nCr(n,r)`, `nPr(n,r)`, `factorial(n)` / `n!`.
  - Unit Conversions: `convert(100, "km", "miles")`, `convert(30, "celsius", "fahrenheit")`, `convert(1024, "MB", "GB")`.
- **JSON Schema**:
  - `expression` (String, required): Formula string.
  - `angle_unit` (String, enum: `["radian", "degree"]`, default: `"radian"`).
  - `precision` (int, 1-50, default: 10).
  - `format` (String, enum: `["decimal", "scientific", "fraction", "engineering"]`, default: `"decimal"`).
- **Execution & Output**:
  - Pure Dart recursive descent / tokenized evaluation without spawning external processes.
  - Returns `rawJson: { "expression": "...", "result": 42.0 }` and `formattedMarkdown: "**计算结果**: \`2 + 2\` = **\`4\`**"`.

#### 4.2.2 `time_calculator` (`lib/tools/time_calculator_tool.dart`)
- **Identifier**: `time_calculator` (`ToolCategory.utility`, `PermissionLevel.safe`)
- **Capabilities**:
  - `current_time`: Returns current timestamp in UTC, local, or designated IANA timezone.
  - `convert_timezone`: Converts timestamp from `source_timezone` to `target_timezone`.
  - `date_offset`: Adds/subtracts offset (`+3d`, `-5h30m`, `+2w`, `+1M`, `+1y`) from `base_time`.
  - `time_difference`: Calculates exact duration (days, hours, minutes, seconds) between `base_time` and `end_time`.
  - `parse_relative`: Computes relative dates (e.g. `"tomorrow"`, `"next Monday"`, `"yesterday"`).
  - `business_days`: Calculates working days excluding weekends between two dates.
- **JSON Schema**:
  - `operation` (String, required, enum: `["current_time", "convert_timezone", "date_offset", "time_difference", "parse_relative", "business_days"]`).
  - `base_time` (String, optional, ISO8601 or Unix timestamp).
  - `source_timezone` (String, default: `"UTC"`).
  - `target_timezone` (String, optional).
  - `offset` (String, optional, e.g. `"+3d"`).
  - `end_time` (String, optional).
  - `relative_expression` (String, optional).
- **Timezone Resolution**:
  - Built-in map of standard IANA zones (`Asia/Shanghai`, `America/New_York`, `Europe/London`, `UTC`, etc.) and common city aliases (`Beijing`, `Tokyo`, `London`, `New York`, `Paris`).

#### 4.2.3 `weather_query` (`lib/tools/weather_query_tool.dart`)
- **Identifier**: `weather_query` (`ToolCategory.utility`, `PermissionLevel.safe`)
- **Endpoints**:
  - Geocoding: `https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1&language=zh&format=json`
  - Weather Forecast: `https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days={days}`
- **JSON Schema**:
  - `location` (String, optional, city name, e.g. `"Beijing"`, `"Shanghai"`, `"Tokyo"`).
  - `latitude` (number, optional, -90.0 to 90.0).
  - `longitude` (number, optional, -180.0 to 180.0).
  - `query_type` (String, enum: `["current", "forecast_daily", "all"]`, default: `"all"`).
  - `forecast_days` (int, 1-14, default: 7).
  - `temperature_unit` (String, enum: `["celsius", "fahrenheit"]`, default: `"celsius"`).
- **Execution & Output**:
  - Queries Open-Meteo REST API using `Dio`.
  - Parses WMO weather codes (0 -> `"晴"`, 1-3 -> `"多云"`, 45/48 -> `"雾"`, 51-67 -> `"雨"`, 71-77 -> `"雪"`, 95-99 -> `"雷暴"`).
  - Formats output as structured JSON and Markdown table showing current temperature, humidity, wind speed, and 7-day forecast.

#### 4.2.4 `wiki_lookup` (`lib/tools/wiki_lookup_tool.dart`)
- **Identifier**: `wiki_lookup` (`ToolCategory.utility`, `PermissionLevel.safe`)
- **Endpoints**:
  - Page Summary: `https://{lang}.wikipedia.org/api/rest_v1/page/summary/{title}`
  - Keyword Search: `https://{lang}.wikipedia.org/w/api.php?action=query&list=search&srsearch={query}&format=json&utf8=1`
- **JSON Schema**:
  - `query` (String, required, topic title).
  - `language` (String, default: `"zh"`, enum/string: `["zh", "en", "ja", "fr", "de"]`).
  - `mode` (String, enum: `["summary", "search", "section"]`, default: `"summary"`).
  - `section_title` (String, optional).
  - `max_results` (int, 1-10, default: 5).
- **Execution & Output**:
  - Disambiguation detection: If response `type == 'disambiguation'`, extracts candidate list and returns structured candidates.
  - Clean summary: Extracts clean plain text without HTML markup or references, capped at 3,500 characters.
  - Formatted Markdown with title, link, summary, and article metadata.

---

### 4.3 R3: AgentLoopGuard Specification

#### 4.3.1 Loop Guard Structure (`lib/services/agent_loop_guard.dart`)
```dart
class AgentLoopGuard {
  final int maxToolRounds;
  final int maxConsecutiveDuplicates;
  final List<ToolCallRecord> _history = [];

  AgentLoopGuard({
    this.maxToolRounds = 8,
    this.maxConsecutiveDuplicates = 3,
  });

  /// Evaluates whether the agent should continue executing tools or halt immediately.
  LoopGuardDecision recordAndCheck({
    required int currentRound,
    required String toolName,
    required Map<String, dynamic> arguments,
  });
}
```

#### 4.3.2 Detection Algorithms
1. **Argument Hash / Signature Deduplication**:
   - Computes canonical signature: `String signature = "$toolName:${jsonEncode(_canonicalizeMap(arguments))}"`.
   - Generates hash or compares canonical signature strings.
   - If the exact same signature appears consecutively `>= maxConsecutiveDuplicates` (3 times), trigger `LoopGuardDecision.abortDuplicate`.
2. **Oscillation Detection**:
   - Checks historical tool name sequence for periodic 2-cycles (A->B->A->B) or 3-cycles (A->B->C->A->B->C).
   - If period is repeated `>= 2` full cycles, trigger `LoopGuardDecision.abortOscillation`.
3. **Round Cap**:
   - If `currentRound >= maxToolRounds - 1` (default round 7 of 8), trigger `LoopGuardDecision.abortMaxRounds`.

#### 4.3.3 Fallback & Terminal Synthesis Behavior
- When `LoopGuardDecision` indicates an abort/halt condition:
  - `AgentService` intercepts the loop immediately.
  - Emits no further tool execution requests.
  - Prepares final completion request with `tools: null` (stripped).
  - Injects terminal Chinese system prompt:
    > `“请根据上述已获取的全部工具执行结果与上下文信息，直接给出最终的总结回答，绝对不要再尝试使用任何工具或输出工具调用格式。”`
  - Streams final assistant completion to the user.

---

### 4.4 R4: UI & Pipeline Integration, Quality & Verification

#### 4.4.1 `AgentService` Pipeline Integration (`lib/services/agent_service.dart`)
- Replace hardcoded `if (entry.name == 'url_fetch') ... else ...` dispatch logic with:
  ```dart
  final tool = _toolRegistry.getTool(entry.name);
  if (tool != null) {
    final validation = tool.validateArguments(args);
    if (!validation.isValid) {
      // Return schema error to model for self-correction
      result = ToolExecutionResult.failure(error: validation.errorMessage!, duration: Duration.zero);
    } else {
      final guardDecision = loopGuard.recordAndCheck(
        currentRound: toolRound,
        toolName: entry.name,
        arguments: args,
      );
      if (guardDecision.shouldHalt) {
        // Trigger fallback terminal synthesis
        break;
      }
      result = await tool.execute(context, args);
    }
  }
  ```
- Retain backwards-compatible manual `@search` prefix and pseudo-XML / DSML `<tool_call>` parsing.

#### 4.4.2 `ChatBubble` Rendering (`lib/widgets/chat_bubble.dart`)
- **Tool Output Panel**:
  - Displays Category Icon (e.g. `Icons.calculate` for math, `Icons.access_time` for time, `Icons.wb_sunny` for weather, `Icons.menu_book` for wiki).
  - Chinese Title: `"工具执行结果 [工具名称]"`
  - Execution Duration Badge: `"[耗时 Xms]"`
  - Collapsible container via `AnimatedCrossFade`.
  - Tool result copy button: `"已复制工具执行结果"`.
- **Intermediate Assistant Panel**:
  - Collapsible reasoning + tool call commands list.
  - Monospace argument preview.

#### 4.4.3 Quality Metrics & Constraints
- **Test Target**:
  - Baseline: 173 passing tests.
  - New Tests: >= 25 tests covering `ToolRegistry`, `AgentLoopGuard`, `MathEvalTool`, `TimeCalculatorTool`, `WeatherQueryTool`, `WikiLookupTool`, and integration scenarios.
  - Total Target: >= 198 tests with 100% pass rate (0 failures).
- **Static Analysis**: `flutter analyze` must output `No issues found!`.
- **Version Number**: Bump `pubspec.yaml` to `1.08.0+9`.
- **Work Log**: Prepend Milestone 23 documentation in `WORK_LOG.md` and update `context.md`.

---

## 5. Acceptance Criteria Checklist

### 5.1 Architecture & Registry (A1)
- [ ] `Tool` base class, `ToolParameter`, `ToolExecutionContext`, `ToolExecutionResult` contracts defined with full type safety.
- [ ] 4-level security model (`PermissionLevel`) and domain categories (`ToolCategory`) implemented.
- [ ] `ToolRegistry` manages registration, dynamic filtering, and OpenAI JSON Schema / System Prompt export.
- [ ] Legacy search tools (`web_search`, `google_search`, `bing_search`) and `url_fetch` adapted into `Tool` instances.
- [ ] Riverpod `toolRegistryProvider` provides global reactive access.

### 5.2 4 Safe Built-in Tools (A2)
- [ ] `math_eval`: Evaluates standard arithmetic, trigonometry, logs, sqrt, power, statistics, and units with division-by-zero protection.
- [ ] `time_calculator`: Handles IANA timezones, conversions, date offsets (`+3d`), time differences, and relative dates.
- [ ] `weather_query`: Open-Meteo REST API queries for real-time conditions and 7-day forecast with geocoding.
- [ ] `wiki_lookup`: Chinese & English Wikipedia REST API queries with summary extraction and disambiguation detection.

### 5.3 AgentLoopGuard (A3)
- [ ] Duplicate argument detection (identical signature >= 3 times) triggers loop break.
- [ ] Oscillation detection (A->B->A->B) triggers cycle break.
- [ ] Hard round cap (`maxToolRounds = 8`) halts further tool calls.
- [ ] Fallback mechanism strips tools and forces final summary text generation.

### 5.4 UI & Pipeline Integration (A4)
- [ ] `AgentService` seamlessly dispatches tools through `ToolRegistry` and `AgentLoopGuard`.
- [ ] `ChatBubble` renders collapsible tool cards with Chinese labels, category icons, duration badges, and copy buttons.
- [ ] Pseudo-XML fallback and manual `@search` prefix continue to work seamlessly.

### 5.5 Code Quality & Deliverables (A5)
- [ ] All 173 existing tests + 25+ new tests pass 100% cleanly (>= 198 tests total).
- [ ] `flutter analyze` reports `No issues found!`.
- [ ] `pubspec.yaml` version bumped to `1.08.0+9`.
- [ ] `WORK_LOG.md` top entry and `.agents/context.md` updated with Milestone 23 details.
