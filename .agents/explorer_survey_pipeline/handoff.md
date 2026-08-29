# Handoff Report — Explorer Survey Pipeline

## 1. Observation

1. **`lib/services/agent_service.dart` Structure**:
   - Lines 12-68 define `AgentStreamEvent` hierarchy: `ReasoningDeltaEvent`, `ContentDeltaEvent`, `ToolCallStartedEvent(query)`, `ToolCallCompletedEvent(query, results)`, `UrlFetchStartedEvent(url)`, `UrlFetchCompletedEvent(url, content)`, `ToolCallExecutedMessageEvent(assistantMessage, toolMessages)`, `UsageEvent(promptTokens, completionTokens)`.
   - Lines 91-183 define tool schemas (`webSearchTool`, `googleSearchTool`, `bingSearchTool`, `urlFetchTool`) and `getEffectiveTools(searchBackend, {enableAutoSearch})`.
   - Lines 190-260 define pseudo-XML and DSML parsers (`parsePseudoXmlToolCalls`, `stripPseudoXmlToolCalls`).
   - Lines 263-608 define `chatAndSearchStream(...)`: prepends system prompt with `$systemPrompt\n\n当前日期与时间: $dateStr $timeStr`, handles `@search` manual trigger, and streams initial LLM completion.
   - Lines 650-1072 define recursive `_streamCompletionsLoop(...)`:
     - Checks `if (toolRound >= maxToolRounds - 1)` (lines 668-715) and appends a final prompt forcing a textual summary without tools.
     - Hardcodes tool execution for `url_fetch` vs search tools (lines 798-879).
     - Handles pseudo-XML / DSML fallback execution (lines 924-1064).
2. **`lib/providers/chat_provider.dart` & `agent_provider.dart`**:
   - `ChatNotifier._startStreaming` (lines 280-442) consumes `AgentStreamEvent` stream, updates `streamReasoning` / `streamContent`, calls `_ref.read(agentProvider.notifier)`, persists `assistantMessage` and `toolMessages` via `_messageDao.insert`, and handles error categorization and cancellation.
   - `AgentNotifier` / `AgentState` (`lib/providers/agent_provider.dart:4-34`) tracks `isSearching`, `searchQuery`, `searchResults`, `isFetchingUrl`, `fetchingUrl`.
3. **`lib/widgets/chat_bubble.dart` & `lib/screens/home_screen.dart`**:
   - `ChatBubble` (lines 185-299) differentiates:
     - `message.role == 'tool'`: renders `_buildToolOutputPanel` with `Icons.build_circle_outlined` and copy action.
     - `message.role == 'assistant'` with `toolCalls.isNotEmpty`: renders `_buildIntermediateAssistantPanel` with `Icons.auto_awesome`, collapsible command preview `${tc.functionName}(${tc.arguments})`, reasoning, and process output.
     - `reasoningContent.isNotEmpty`: renders `_buildReasoningPanel` with `Icons.psychology` and copy button.
   - `HomeScreen` (lines 240-273) renders live status progress card at bottom of list when `isSearching` or `isFetchingUrl` is active.
4. **Test Suite Execution & Mocking (`test/`)**:
   - Ran `D:\work\flutter-sdk\flutter\bin\flutter.bat test --no-pub`: exited with code 0, 173/173 tests passed.
   - Ran `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze --no-pub`: exited with code 0, `No issues found!`.
   - Mock patterns: `MockChatService` overriding `chatCompletionsStream` with dynamic stream handler; `MockFlutterSecureStorage` via `noSuchMethod`; `sqflite_common_ffi` in-memory database setup with `databaseFactory = databaseFactoryFfi`.

---

## 2. Logic Chain

1. From Observation 1 (`agent_service.dart`), tool execution is currently hardcoded using `if (entry.name == 'url_fetch')` vs `else (search)` and tool definitions are static maps in `AgentService`. To scale the Agent capabilities cleanly in Milestone 23, these need to be extracted into a polymorphic `Tool` interface and a `ToolRegistry`.
2. From Observation 1 (`_streamCompletionsLoop`), loop termination currently only counts `toolRound >= maxToolRounds - 1`. It does not detect immediate duplicate calls (e.g. calling `math_eval` with identical expression repeatedly) or oscillation (A -> B -> A). Therefore, `AgentLoopGuard` with MD5 signature tracking and cycle detection is necessary.
3. From Observation 2 and 3 (`chat_provider.dart`, `agent_provider.dart`, `chat_bubble.dart`, `home_screen.dart`), the UI already has dedicated components for intermediate assistant tool calls (`_buildIntermediateAssistantPanel`) and tool output (`_buildToolOutputPanel`). As long as `Tool` execution emits standard `ChatMessage(role: 'tool', toolCallId: ..., content: ...)` and `ChatMessage(role: 'assistant', toolCalls: [...])`, the existing UI will render all new tools (`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`) seamlessly.
4. From Observation 4, the test suite relies on `MockChatService` and specific event streams. Any refactoring of `AgentService` must preserve backward compatibility with existing tests and event structures so that all 173 tests remain green while adding 25+ new tests for Milestone 23.

---

## 3. Caveats

- **Network-dependent tools**: `weather_query` (Open-Meteo) and `wiki_lookup` (Wikipedia API) require HTTP calls in real usage, but must be safely unit-tested with mock HTTP adapters / handlers in `test/` so tests never depend on external internet access.
- **Pseudo-XML / DSML compatibility**: When new tools are added, the pseudo-XML and DSML parsers should support arbitrary function names and key-value parameters.

---

## 4. Conclusion

The Agent pipeline is solid, modular, and ready for the Milestone 23 upgrade:
1. Create `lib/models/tool/tool.dart`, `tool_parameter.dart`, `tool_execution_result.dart`.
2. Create `lib/services/tool_registry.dart` with Riverpod provider `toolRegistryProvider`.
3. Wrap existing `web_search`, `google_search`, `bing_search`, and `url_fetch` as `Tool` implementations.
4. Implement the 4 built-in basic tools: `MathEvalTool`, `TimeCalculatorTool`, `WeatherQueryTool`, `WikiLookupTool`.
5. Implement `AgentLoopGuard` in `lib/services/agent_loop_guard.dart`.
6. Refactor `AgentService` to dispatch tool calls via `ToolRegistry` and guard execution via `AgentLoopGuard`.
7. Write unit tests for all new tools and registry (targeting 25+ new tests, reaching 198+ tests total).

---

## 5. Verification Method

To independently verify the current baseline:
1. Run static analysis:
   ```powershell
   D:\work\flutter-sdk\flutter\bin\flutter.bat analyze --no-pub
   ```
   *Expected result*: `No issues found!`
2. Run automated test suite:
   ```powershell
   D:\work\flutter-sdk\flutter\bin\flutter.bat test --no-pub
   ```
   *Expected result*: `All tests passed! (173 / 173)`
3. Inspect detailed survey report:
   - File: `D:\work\chat\.agents\explorer_survey_pipeline\report.md`
