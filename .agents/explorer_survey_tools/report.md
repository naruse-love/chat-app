# Codebase Tool System Survey Report (Comprehensive Analysis)

**Author**: Explorer Survey Tools (`teamwork_preview_explorer`)  
**Date**: 2026-08-28  
**Scope**: Full survey of existing tools, schema definitions, LLM function calling translation, Riverpod providers, model structures, and runtime dispatch pipelines in `D:\work\chat`.

---

## 1. Executive Summary

The existing chat application possesses a multi-layered tool calling and web search architecture developed across Milestones 1–22. The system currently supports:
1. **Four tool types**:
   - `web_search` (SearXNG JSON API, multi-page concurrent querying, URL deduplication)
   - `google_search` (Google Gemini Search Grounding API with AI summary + grounding chunks)
   - `bing_search` (Bing HTML scraping with account cookie forwarding, multi-hop redirect tracking, AI summary extraction, and FrontDoor WAF / CAPTCHA detection)
   - `url_fetch` (Intelligent webpage scraping with DOM cleanup, semantic container selection, noise stripping, metadata extraction, page type diagnosis, and Markdown formatting)
   - Dual search (`google_bing`): Concurrent Google Grounding + Bing HTML scraping with URL deduplication.
2. **Tool Schema and Function Calling**:
   - Defined as OpenAI-compatible JSON Schema maps in `AgentService`.
   - Converted to OpenAI `/v1/chat/completions` payload in `ChatService`.
   - Tool calling is supported via standard OpenAI SSE stream delta chunks (`delta['tool_calls']`) as well as a robust pseudo-XML `<tool_call>` / DeepSeek DSML (`<｜｜DSML｜｜tool_calls>`) fallback parser.
3. **Riverpod Provider Layer**:
   - `searchServiceProvider`, `urlFetchServiceProvider`, `chatServiceProvider`, `agentServiceProvider`, `agentProvider`, `settingsProvider`, and `chatProvider`.
4. **Data Structures**:
   - `ToolCall` in `lib/models/tool_call.dart` (JSON serializable, dual-format parser, OpenAI export).
   - `ChatMessage` in `lib/models/chat_message.dart` (holds `List<ToolCall>? toolCalls` and `String? toolCallId`).
   - `FetchResult` & `FetchMetadata` in `lib/models/fetch_result.dart`.
   - `SearchResult` in `lib/services/search_service.dart`.
   - `ModelInfo` in `lib/models/model_info.dart` (with heuristic `supportsTools` inference).

---

## 2. Existing Tool Implementations

### 2.1 `web_search` (SearXNG)
- **Location**: `lib/services/search_service.dart` (`_searchSearxng`, lines 130–224), `lib/services/agent_service.dart` (`webSearchTool`, lines 92–108).
- **Schema**:
  ```json
  {
    "type": "function",
    "function": {
      "name": "web_search",
      "description": "Search the web for up-to-date information on a given topic.",
      "parameters": {
        "type": "object",
        "properties": {
          "query": {
            "type": "string",
            "description": "The query to search for on the web."
          }
        },
        "required": ["query"]
      }
    }
  }
  ```
- **Mechanism**:
  - Normalizes base URL (`searxngUrl`), strips trailing slashes, appends `/search`.
  - Executes concurrent requests for `pageno: 1` and `pageno: 2` using `Future.wait([fetchPage(1), fetchPage(2)])`.
  - Requests JSON format (`format: 'json'`).
  - Catches HTTP 400/403 errors and generates an explanatory error message advising the user to enable `formats: [html, json]` in SearXNG's `settings.yml`.
  - Deduplicates results by URL across the combined pages.
  - Returns `List<SearchResult>`.

### 2.2 `google_search` (Google Gemini AI Studio Grounding)
- **Location**: `lib/services/search_service.dart` (`_searchGoogle`, lines 514–649), `lib/services/agent_service.dart` (`googleSearchTool`, lines 111–127).
- **Schema**:
  ```json
  {
    "type": "function",
    "function": {
      "name": "google_search",
      "description": "Search Google for up-to-date information on a given topic.",
      "parameters": {
        "type": "object",
        "properties": {
          "query": {
            "type": "string",
            "description": "The search query for Google."
          }
        },
        "required": ["query"]
      }
    }
  }
  ```
- **Mechanism**:
  - Sends a POST request to Google AI Studio REST API:
    `{googleSearchBaseUrl}/v1beta/models/{googleSearchModel}:generateContent?key={googleApiKey}`
    (Defaults: `https://generativelanguage.googleapis.com`, `gemini-2.5-flash`).
  - Request payload:
    `{"contents": [{"role": "user", "parts": [{"text": query}]}], "tools": [{"google_search": {}}]}`
  - Parses response:
    1. Extracts AI Grounding Summary from `candidates[0].content.parts[0].text` as a `SearchResult(title: 'Google 搜索总结 (AI)', url: '', content: text)`.
    2. Extracts grounding citations from `candidates[0].groundingMetadata.groundingChunks[*].web` as `SearchResult(title: web.title, url: web.uri, content: '来自 Google 搜索的网页来源。')`.

### 2.3 `bing_search` (Bing HTML Scraper with Account History Sync)
- **Location**: `lib/services/search_service.dart` (`_searchBing`, lines 260–387; `_parseBingResults`, lines 390–465), `lib/services/agent_service.dart` (`bingSearchTool`, lines 130–146).
- **Schema**:
  ```json
  {
    "type": "function",
    "function": {
      "name": "bing_search",
      "description": "Search Bing for up-to-date information on a given topic.",
      "parameters": {
        "type": "object",
        "properties": {
          "query": {
            "type": "string",
            "description": "The search query for Bing."
          }
        },
        "required": ["query"]
      }
    }
  }
  ```
- **Mechanism**:
  - Encodes query with `+` replacing `%20` for domestic keyword compatibility.
  - Appends `cc=us&setlang=zh-hans`, generates UUID `cvid` and `form=QBLH` parameters.
  - Injects sanitized desktop headers (`User-Agent`, `Sec-Ch-Ua`, `Sec-Fetch-*`) and user's `bingCookie` from secure storage.
  - Manual 5-hop redirect tracking (`followRedirects: false`) with `_mergeCookies` to ensure Cookie headers are retained across domain/subdomain hops.
  - Security & anti-bot checks: detects Azure FrontDoor WAF blocking (`The request is blocked`, `Ref A:`) and CAPTCHA challenge pages (`g-recaptcha`, `.b_captcha`, `验证码`).
  - DOM extraction using `package:html`:
    - Checks `.cht_root` / `[data-scenario="nrt"]` for Bing AI summary block.
    - Selects search result list items (`li.b_algo`, `.b_algo`, `ol#b_results > li`).
    - Decodes Bing tracking URLs (`_decodeBingUrl` stripping `/ck/a?!...&u=a1...` Base64 encoding).

### 2.4 Parallel Dual Search (`google_bing`)
- **Location**: `lib/services/search_service.dart` (lines 100–123).
- **Mechanism**: Concurrently queries Google Grounding and Bing HTML via `Future.wait([googleFuture, bingFuture])`, combines the results, and deduplicates by normalized URL.

### 2.5 `url_fetch` (Structured Webpage Scraper & Diagnostic Engine)
- **Location**: `lib/services/url_fetch_service.dart` (732 lines), `lib/models/fetch_result.dart` (175 lines), `lib/services/agent_service.dart` (`urlFetchTool`, lines 148–166).
- **Schema**:
  ```json
  {
    "type": "function",
    "function": {
      "name": "url_fetch",
      "description": "Fetch and extract structured content from a webpage URL. Returns metadata (title, author, published date, site name, language), page type diagnosis (article/doc/captcha/login_wall/nav_hub), truncation status & limits, link statistics, and cleaned main content in Markdown.",
      "parameters": {
        "type": "object",
        "properties": {
          "url": {
            "type": "string",
            "description": "The absolute HTTP or HTTPS URL of the webpage to fetch."
          }
        },
        "required": ["url"]
      }
    }
  }
  ```
- **Mechanism**:
  - Fetches page via Dio (bytes response decoded with UTF-8 `allowMalformed: true`).
  - P0 Truncation: limits content to `maxCharacters` (default 15,000 chars), sets `truncated` boolean, records `originalLength`, appends truncation warning.
  - P0 Page Type Diagnostics: detects `captcha`, `login_wall`, `error_page`, `nav_hub`, `doc`, `article`.
  - P0 Rich Metadata: extracts `<title>`, `<meta>` (description, author, date, site, language, keywords), OpenGraph (`og:*`), Twitter cards, and JSON-LD (`<script type="application/ld+json">`).
  - P1 Noise Stripping & Semantic Prioritization: prioritizes `<article>`, `<main>`, `[role="main"]`, `.markdown-body`, `.post-content`, etc. Strips `<script>`, `<style>`, `<noscript>`, `<svg>`, `<iframe>`, `<canvas>`, and boilerplate UI elements (`<nav>`, `<header>`, `<footer>`, `<aside>`, `.sidebar`, `.ad`, `.cookie-banner`, etc.).
  - P1 Link Statistics: calculates total, internal, and external links.
  - P1 HTML-to-Markdown Converter (`_parseHtmlToStructuredMarkdown`): transforms headings, tables (`| col | col |`), blockquotes, code blocks, lists, links, and text formatting.
  - Generates structured Markdown via `FetchResult.toStructuredMarkdown()` containing title, metadata header, diagnostics, warnings, and formatted content.

---

## 3. Tool Schemas, Conversion, and Dispatch Pipeline

### 3.1 Tool Schema Export & Configuration
In `AgentService.getEffectiveTools(searchBackend, {enableAutoSearch = true})`:
- If `enableAutoSearch == false`: returns `[urlFetchTool]`.
- If `enableAutoSearch == true`:
  - `google` -> `[googleSearchTool, urlFetchTool]`
  - `bing` -> `[bingSearchTool, urlFetchTool]`
  - `google_bing` -> `[googleSearchTool, bingSearchTool, urlFetchTool]`
  - `searxng` -> `[webSearchTool, urlFetchTool]`

### 3.2 Conversion for OpenAI Function Calling (`ChatService`)
- In `ChatService.chatCompletionsStream(...)`:
  - Request body includes:
    ```dart
    final body = {
      'model': model,
      'messages': apiMessages,
      'stream': true,
      'stream_options': {'include_usage': true},
      if (reasoningEffort != null && reasoningEffort.isNotEmpty && reasoningEffort != 'none')
        'reasoning_effort': reasoningEffort,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };
    ```
- In `ChatService._convertMessageToApiFormat(ChatMessage)`:
  - If `message.toolCalls` is non-empty, maps each `ToolCall` via `tc.toOpenAiJson()`:
    ```dart
    {
      'id': tc.id,
      'type': tc.type,
      'function': {
        'name': tc.functionName,
        'arguments': tc.arguments,
      }
    }
    ```
  - If `message.toolCallId` is present (for `role: 'tool'`), adds `'tool_call_id': message.toolCallId`.
  - If `message.imagePath` is present, encodes image to Base64 data URI in `content: [{'type': 'text', 'text': ...}, {'type': 'image_url', 'image_url': {'url': ...}}]`.

### 3.3 Streaming Tool Call Accumulation & Execution Loop
1. **Delta Chunk Accumulation**:
   - `SseParser` parses SSE chunks.
   - `AgentService` maintains `Map<int, _ToolCallAccumulator> accumulatedToolCalls`.
   - Merges delta parts: `id`, `type`, `function.name`, `function.arguments` (streamed chunks).
2. **Tool Execution Dispatch**:
   - When stream ends and `accumulatedToolCalls` is not empty:
     - For `url_fetch`: calls `_urlFetchService.fetchUrlContent(url)` (emitting `UrlFetchStartedEvent` and `UrlFetchCompletedEvent`).
     - For search tools (`web_search`, `google_search`, `bing_search`): calls `_searchService.search(...)` (emitting `ToolCallStartedEvent` and `ToolCallCompletedEvent`).
     - Formats results into tool message: `ChatMessage(role: 'tool', toolCallId: entry.id, content: formattedResult)`.
   - Packages assistant message: `ChatMessage(role: 'assistant', toolCalls: [...], promptTokens: ..., completionTokens: ...)`.
   - Emits `ToolCallExecutedMessageEvent(assistantMessage, toolMessages)`.
   - Appends assistant message and tool response messages to the conversation history.
   - Recurses into `_streamCompletionsLoop` with `toolRound: toolRound + 1`.
3. **Manual Trigger (`@search <query>`)**:
   - Intercepts user prompt starting with `@search`.
   - Runs search directly, synthesizes `ToolCall(id: 'manual_search_<timestamp>', functionName: ..., arguments: '{"query": "..."}')` and tool message, then continues standard completion stream.
4. **Pseudo-XML and DSML Fallback**:
   - If the LLM generates plain text tool calls rather than standard OpenAI delta `tool_calls`:
     - Regular pseudo-XML format: `<tool_call><function=web_search><parameter=query>...</parameter></function></tool_call>`
     - DeepSeek DSML format: `<｜｜DSML｜｜tool_calls><｜｜DSML｜｜invoke name="web_search"><｜｜DSML｜｜parameter name="query">...</parameter></invoke></tool_calls>`
   - `AgentService.parsePseudoXmlToolCalls(content)` extracts function names and parameter maps.
   - `AgentService.stripPseudoXmlToolCalls(content)` strips the XML markup from assistant text.
   - Synthesizes `ToolCall(id: 'pseudo_<uuid>', ...)` and executes tools identically to standard tool calling.
5. **Loop Guard & Round Limit**:
   - `maxToolRounds` defaults to `100` (in `chatAndSearchStream` / `_streamCompletionsLoop`).
   - When `toolRound >= maxToolRounds - 1`: strips `tools` parameter and executes one final summary completion with an injected system message:
     `"请根据上述已获取的搜索结果和网页内容，直接给出最终的总结回答，绝对不要再尝试使用任何工具或输出形如 <tool_call> 的工具调用格式。"`

---

## 4. Riverpod Provider Architecture

| Provider | Type | Responsibilities |
|---|---|---|
| `searchServiceProvider` | `Provider<SearchService>` | Instantiates `SearchService`. |
| `urlFetchServiceProvider` | `Provider<UrlFetchService>` | Instantiates `UrlFetchService`. |
| `chatServiceProvider` | `Provider<ChatService>` | Instantiates `ChatService` for HTTP/SSE communication. |
| `agentServiceProvider` | `Provider<AgentService>` | Combines `chatService`, `searchService`, and `urlFetchService` into `AgentService`. |
| `agentProvider` | `StateNotifierProvider<AgentNotifier, AgentState>` | Reactive state for UI indicators: `isSearching`, `searchQuery`, `searchResults`, `isFetchingUrl`, `fetchingUrl`. |
| `settingsProvider` | `StateNotifierProvider<SettingsNotifier, AppSettings>` | Persistent settings: `searxngUrl`, `searchBackend`, `enableAutoSearch`, `googleSearchApiKey`, `googleSearchBaseUrl`, `googleSearchModel`, `bingCookie`, `reasoningEffort`, `defaultSystemPrompt`. |
| `chatProvider` | `StateNotifierProvider<ChatNotifier, ChatState>` | Main conversation and streaming lifecycle manager. Connects UI actions (`sendMessage`, `editAndResendMessage`, `regenerateLastResponse`, `rollbackToMessage`) to `AgentService.chatAndSearchStream`, persists messages to SQLite via `MessageDao`, feeds status into `agentProvider`, and manages cancellation via `CancelToken`. |

### UI Rendering of Tools & Reasoning:
- **`HomeScreen` (`lib/screens/home_screen.dart`)**:
  - Watches `agentProvider`.
  - When `isSearching` or `isFetchingUrl` is active, renders bottom status chip: `"正在搜索: \"<query>\"..."` or `"正在读取网页: <url>..."`.
- **`ChatBubble` (`lib/widgets/chat_bubble.dart`)**:
  - `ChatMessage` with `role == 'tool'`: renders collapsible `_buildToolOutputPanel` with `Icons.build_circle_outlined` and "工具执行结果" header.
  - `ChatMessage` with `role == 'assistant'` and `toolCalls != null`: renders collapsible `_buildIntermediateAssistantPanel` with `Icons.auto_awesome` and "思考与工具调用 [<tool_names>]" header. Displays tool invocation arguments and reasoning process.
  - `ChatMessage` with `reasoningContent != null`: renders collapsible `_buildReasoningPanel` with `Icons.psychology`, "思考过程", copy button, and selectable reasoning text.

---

## 5. Data Structures and Models

### 5.1 `ToolCall` (`lib/models/tool_call.dart`)
```dart
@JsonSerializable()
class ToolCall {
  final String id;
  final String type; // "function"
  final String functionName;
  final String arguments; // JSON string

  ToolCall({
    required this.id,
    required this.type,
    required this.functionName,
    required this.arguments,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('function') && json['function'] is Map) {
      final functionMap = json['function'] as Map<String, dynamic>;
      return ToolCall(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? 'function',
        functionName: functionMap['name'] as String? ?? '',
        arguments: functionMap['arguments'] as String? ?? '',
      );
    }
    return _$ToolCallFromJson(json);
  }

  Map<String, dynamic> toJson() => _$ToolCallToJson(this);

  Map<String, dynamic> toOpenAiJson() {
    return {
      'id': id,
      'type': type,
      'function': {
        'name': functionName,
        'arguments': arguments,
      }
    };
  }
}
```

### 5.2 `ChatMessage` (`lib/models/chat_message.dart`)
- Contains:
  - `String id`
  - `String conversationId`
  - `String role` (`'user' | 'assistant' | 'system' | 'tool'`)
  - `String content`
  - `String? reasoningContent`
  - `String? imagePath`
  - `List<ToolCall>? toolCalls`
  - `String? toolCallId`
  - `DateTime timestamp`
  - `int? promptTokens`
  - `int? completionTokens`
- SQLite Persistence (`MessageDao`):
  - Serializes `toolCalls` list to JSON string in `messages.toolCalls` column.
  - Deserializes `messages.toolCalls` JSON string into `List<ToolCall>` on retrieval.

### 5.3 `SearchResult` (`lib/services/search_service.dart`)
- Fields: `String title`, `String url`, `String content`.
- Methods: `fromJson`, `toJson`.

### 5.4 `FetchResult` & `FetchMetadata` (`lib/models/fetch_result.dart`)
- `FetchMetadata`: `title`, `description`, `author`, `publishedAt`, `language`, `siteName`, `keywords`, `ogType`, `ogImage`.
- `FetchResult`: `url`, `status`, `pageType`, `truncated`, `originalLength`, `maxLength`, `contentRatio`, `metadata`, `mainContent`, `totalLinks`, `internalLinks`, `externalLinks`, `warnings`.
- Formatter: `toStructuredMarkdown()`.

### 5.5 `ModelInfo` (`lib/models/model_info.dart`)
- Heuristic tool calling capability inference:
  - Checks explicit `supports_tools` / `supportsTools` from API response.
  - Uses `_inferToolsSupport(provider, modelName)`:
    - Automatically enables tools for known providers (`openai`, `anthropic`, `google`, `mistral`, `deepseek`).
    - Automatically enables tools for model families matching `gpt-4`, `gpt-3.5`, `claude-3`, `gemini`, `llama-3`, `qwen`, `mistral`, `mixtral`, `deepseek`.
    - Filters out non-chat models (`embedding`, `rerank`, `whisper`, `tts`, `dall-e`).

---

## 6. Structural Strengths and Extensibility Opportunities for Milestone 23

### Existing Strengths:
1. **Multi-round tool looping**: Recursive `_streamCompletionsLoop` already supports arbitrary chain depth with round limit guard and prompt fallback.
2. **Dual execution paths**: Seamless support for standard OpenAI `tool_calls` delta streaming as well as fallback pseudo-XML / DSML text parsing.
3. **Database persistence**: Complete schema and DAO support for storing tool calls and tool results without data loss.
4. **Rich UI integration**: Specialized collapsible UI panels in `ChatBubble` for tool calls, tool results, and reasoning traces, with copy support.

### Opportunities / Requirements for Milestone 23 (`ToolRegistry`):
1. **Decouple Hardcoded Tools from `AgentService`**:
   - Currently, `webSearchTool`, `googleSearchTool`, `bingSearchTool`, `urlFetchTool` and their execution logic (`if (entry.name == 'url_fetch') ... else ...`) are hardcoded directly in `AgentService`.
   - Milestone 23 should introduce an abstract `Tool` interface and a centralized `ToolRegistry` where tools (including the existing search & fetch tools, plus new tools like `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`) register their schemas and async execute handlers.
2. **Standardize Tool Execution Results**:
   - Existing search results return `SearchResult` formatted as markdown strings, and `url_fetch` returns `FetchResult.toStructuredMarkdown()`.
   - Introducing `ToolExecutionResult` (holding structured data + formatted markdown text + success/error flags) will provide a unified interface for all tools.
3. **Enhanced Loop & Oscillation Guard (`AgentLoopGuard`)**:
   - Current guard only checks `toolRound >= maxToolRounds - 1`.
   - Milestone 23 should introduce `AgentLoopGuard` detecting repeated query hashing (MD5 signatures) and alternating tool oscillation (e.g. A -> B -> A -> B) to prevent waste and deadlock.
4. **Permissions & Security Model**:
   - Establish standard tool security levels (e.g., Level 0: Safe/Read-only, Level 1: Network/Safe, Level 2: Device/Read, Level 3: Device/Write with confirmation).
