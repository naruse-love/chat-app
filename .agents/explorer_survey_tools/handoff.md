# Handoff Report - Explorer Survey Tools

**Agent**: Explorer Survey Tools (`teamwork_preview_explorer`)  
**Target Recipient**: Parent Orchestrator (`242c8313-c481-4c27-9224-aa6147e81293`)  
**Date**: 2026-08-28  
**Mission**: Investigate all existing tool mechanisms in the codebase (`lib/services/`, `lib/models/`, `lib/providers/`, `test/`).

---

## 1. Observation

Direct observations from the codebase inspection:

1. **Tool Definitions & Schemas**:
   - `lib/services/agent_service.dart:92-108`: `webSearchTool` defines `web_search` with string `query` parameter.
   - `lib/services/agent_service.dart:111-127`: `googleSearchTool` defines `google_search` with string `query` parameter.
   - `lib/services/agent_service.dart:130-146`: `bingSearchTool` defines `bing_search` with string `query` parameter.
   - `lib/services/agent_service.dart:148-166`: `urlFetchTool` defines `url_fetch` with string `url` parameter.
   - `lib/services/agent_service.dart:168-183`: `getEffectiveTools(searchBackend, {enableAutoSearch = true})` switches available tools dynamically based on backend choice and search enable flag.

2. **Tool Execution Services**:
   - `lib/services/search_service.dart:64-712`: `SearchService` executes `_searchSearxng` (concurrent dual-page pageno 1 & 2 + URL deduplication), `_searchGoogle` (Google Gemini Grounding API via `gemini-2.5-flash` with AI summary + grounding chunks), `_searchBing` (desktop headers + Bing cookie forwarding + 5-hop redirect tracking + WAF/CAPTCHA detection + AI summary extraction), and `google_bing` (parallel combined search).
   - `lib/services/url_fetch_service.dart:18-723`: `UrlFetchService` fetches and parses HTML with 15,000 char truncation, page type diagnostics (`captcha`, `login_wall`, `error_page`, `nav_hub`, `doc`, `article`), rich metadata extraction (HTML, OG, JSON-LD), noise stripping (`<nav>`, `<footer>`, `<aside>`, ads), link stats, and HTML-to-Markdown table/structure conversion.

3. **Tool Dispatch, Streaming, and Multi-Turn Loop**:
   - `lib/services/agent_service.dart:263-608`: `chatAndSearchStream` entry point handles system prompt injection (with dynamic current date/time), manual `@search` interception, and streaming SSE delta accumulation via `_ToolCallAccumulator`.
   - `lib/services/agent_service.dart:613-1072`: `_streamCompletionsLoop` handles multi-round tool recursion (`toolRound + 1`), standard OpenAI tool call execution, pseudo-XML (`<tool_call>`) and DSML (`<｜｜DSML｜｜tool_calls>`) parsing and stripping, and round limit protection (`toolRound >= maxToolRounds - 1`, defaulting to 100 rounds) where tools are stripped and a final text summary is forced.

4. **Data Models and Serialization**:
   - `lib/models/tool_call.dart:6-44`: `ToolCall` has `id`, `type`, `functionName`, `arguments`. `fromJson` supports both flat maps and nested OpenAI `{'function': {'name': ..., 'arguments': ...}}`. `toOpenAiJson()` converts to OpenAI tool_calls structure.
   - `lib/models/chat_message.dart:7-72`: `ChatMessage` includes `toolCalls` (`List<ToolCall>?`) and `toolCallId` (`String?`).
   - `lib/models/fetch_result.dart:55-174`: `FetchResult` and `FetchMetadata` models with `toStructuredMarkdown()`.
   - `lib/models/model_info.dart:6-214`: `ModelInfo` includes heuristic tool calling capability detection (`_inferToolsSupport`) for OpenAI, Anthropic, Google, Mistral, DeepSeek, Llama-3, Qwen, etc.
   - `lib/data/message_dao.dart:44-121`: `MessageDao` encodes `toolCalls` to JSON strings on insert and decodes them on read.

5. **Riverpod Providers and UI Integration**:
   - `lib/providers/chat_provider.dart:18-38`: Declares `searchServiceProvider`, `urlFetchServiceProvider`, `chatServiceProvider`, `agentServiceProvider`.
   - `lib/providers/agent_provider.dart:4-80`: `agentProvider` tracks tool execution status (`isSearching`, `searchQuery`, `searchResults`, `isFetchingUrl`, `fetchingUrl`).
   - `lib/providers/settings_provider.dart:10-179`: `settingsProvider` exposes `searxngUrl`, `searchBackend`, `enableAutoSearch`, `googleSearchApiKey`, `bingCookie`, etc.
   - `lib/screens/home_screen.dart:53, 187, 240-242`: Displays dynamic status cards `"正在搜索: ..."` or `"正在读取网页: ..."`.
   - `lib/widgets/chat_bubble.dart:184-269, 481-704`: Renders collapsible panels for tool outputs (`_buildToolOutputPanel`), intermediate tool call instructions and reasoning (`_buildIntermediateAssistantPanel`), and thinking process (`_buildReasoningPanel`).

---

## 2. Logic Chain

1. **Observations 1 & 2** establish that all existing tool definitions (`webSearchTool`, `googleSearchTool`, `bingSearchTool`, `urlFetchTool`) are written as static raw JSON maps directly in `AgentService`, and their execution is handled by two dedicated services (`SearchService` and `UrlFetchService`).
2. **Observation 3** establishes that tool dispatch is hardcoded via `if (entry.name == 'url_fetch') ... else ...` inside `AgentService._streamCompletionsLoop` and `AgentService.chatAndSearchStream`. Both standard OpenAI function calling and fallback pseudo-XML/DSML are supported.
3. **Observation 4** establishes that the underlying data layer (`ToolCall`, `ChatMessage`, SQLite `messages` table, `MessageDao`) is already fully designed to persist and reload multi-tool invocations and structured outputs without loss.
4. **Observation 5** establishes that Riverpod providers (`agentServiceProvider`, `agentProvider`, `chatProvider`) and UI widgets (`HomeScreen`, `ChatBubble`) already react to streaming events (`ToolCallStartedEvent`, `ToolCallCompletedEvent`, `UrlFetchStartedEvent`, `UrlFetchCompletedEvent`, `ToolCallExecutedMessageEvent`) and provide user-friendly Chinese status and collapsible foldouts.
5. **Synthesis**: To implement Milestone 23 (`ToolRegistry`, `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`, `AgentLoopGuard`):
   - We need an abstract `Tool` interface and a unified `ToolRegistry` to register tools, extract JSON Schemas dynamically, and dispatch executions asynchronously.
   - Existing tools (`web_search`, `google_search`, `bing_search`, `url_fetch`) can be wrapped as standard `Tool` subclasses.
   - The hardcoded execution dispatch in `AgentService` can be replaced with a single call to `toolRegistry.execute(toolName, arguments)`.
   - `AgentLoopGuard` can enhance the current simple round count check with hash-based duplicate call detection and oscillation prevention.

---

## 3. Caveats

- **No Caveats**: All relevant files in `lib/services/`, `lib/models/`, `lib/providers/`, `lib/data/`, `lib/screens/`, `lib/widgets/`, and `test/` have been directly viewed, analyzed, and cross-referenced.
- The investigation was purely read-only; no code files in `lib/` or `test/` were modified.

---

## 4. Conclusion

1. The existing codebase has a complete and robust tool execution engine, but tool registration and dispatch are currently tightly coupled inside `AgentService`.
2. The data layer (`ToolCall`, `ChatMessage`, `MessageDao`) and UI layer (`ChatBubble`, `agentProvider`) already fully support multi-turn tool calling and collapsible rendering.
3. Milestone 23 can be implemented cleanly by introducing a pluggable `ToolRegistry` architecture, wrapping existing search/fetch tools into `Tool` instances, implementing the 4 new Level 0 basic tools (`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`), upgrading loop protection via `AgentLoopGuard`, and integrating `toolRegistryProvider` with `AgentService` and `ChatProvider`.

---

## 5. Verification Method

To verify the survey findings independently:
1. Inspect report: `D:\work\chat\.agents\explorer_survey_tools\report.md`
2. Run static analysis:
   ```powershell
   D:\work\flutter-sdk\flutter\bin\flutter.bat analyze
   ```
3. Run existing tests to verify baseline test integrity:
   ```powershell
   D:\work\flutter-sdk\flutter\bin\flutter.bat test
   ```
