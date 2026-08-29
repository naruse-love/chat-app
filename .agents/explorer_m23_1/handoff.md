# Handoff Report: Milestone 23.1 Design Specification

## 1. Observation

1. **Current Codebase State**:
   - `D:\work\chat\lib\services\agent_service.dart`: Lines 92–189 define hardcoded static tool maps `webSearchTool`, `googleSearchTool`, `bingSearchTool`, `urlFetchTool`, and `getEffectiveTools`.
   - `D:\work\chat\lib\services\agent_service.dart`: Lines 479–561 manually inspect tool name strings (`'url_fetch'`, `'web_search'`, `'google_search'`, `'bing_search'`), extract JSON/string arguments, call `_urlFetchService` or `_searchService`, and build `toolMessages`.
   - `D:\work\chat\lib\services\search_service.dart`: Lines 81–127 implement `search(...)` supporting backends `searxng`, `bing`, `google`, and `google_bing`, throwing `SearchException`.
   - `D:\work\chat\lib\services\url_fetch_service.dart`: Lines 26–39 implement `fetchUrlContent(...)` and `fetchUrl(...)` returning `FetchResult` and structured Markdown.
   - `D:\work\chat\lib\models\tool_call.dart`: Defines `ToolCall` model serialized from OpenAI streaming tool calls.
   - `D:\work\chat\lib\providers\settings_provider.dart`: Lines 10–60 define `AppSettings` with fields `searxngUrl`, `searchBackend`, `enableAutoSearch`, etc.
   - `flutter analyze`: Output `No issues found! (ran in 1.7s)`.
   - `flutter test`: Output `All tests passed! (173 / 173 passed)`.

2. **Milestone 23.1 Objectives**:
   - Model layer: `lib/models/tool/tool_security_level.dart`, `lib/models/tool/tool_parameter.dart`, `lib/models/tool/tool_execution_result.dart`, `lib/models/tool/tool.dart`.
   - Registry layer: `lib/services/tool_registry.dart` with Riverpod provider `toolRegistryProvider`.
   - Legacy tool adapters: `lib/services/tools/legacy_tool_adapters.dart` (`WebSearchTool`, `GoogleSearchTool`, `BingSearchTool`, `UrlFetchTool`).
   - Unit test suites in `test/models/tool_model_test.dart` and `test/services/tool_registry_test.dart`.

---

## 2. Logic Chain

1. **Decoupling and Extensibility (from Observation 1 & 2)**:
   - Moving from hardcoded maps and `if (name == 'url_fetch')` branches in `AgentService` to an abstract `Tool` interface and `ToolRegistry` allows dynamic addition of new tools (M23.2 `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`, and future MCP/plugins) without modifying `AgentService` routing logic.
2. **Standardization & OpenAI Compatibility**:
   - `ToolParameter.toOpenAiSchema()` and `Tool.toOpenAiSchema()` produce the exact JSON schema dictionary required by OpenAI Function Calling (`type: 'function', function: {name, description, parameters: {type: 'object', properties, required}}`).
   - `WebSearchTool`, `GoogleSearchTool`, `BingSearchTool`, and `UrlFetchTool` output identical schemas to the legacy constants in `AgentService`.
3. **Execution Safety and Defensive Programming**:
   - `ToolRegistry.execute()` coordinates validation (`Tool.validateArguments`), enablement checks (`isToolEnabled`), execution timing (`Stopwatch`), context forwarding (`effectiveArgs`), and comprehensive error handling (`catch (e)`), ensuring that no tool failure crashes the agent pipeline.
4. **4-Level Security Hierarchy**:
   - `ToolSecurityLevel` categorizes tools from `safe` (Level 0: zero permission, pure math/time computation) to `privilegedNative` (Level 3: native OS access), providing a clean interface for permission checks and UI confirmation dialogs in subsequent milestones.
5. **Full Backward Compatibility**:
   - Legacy adapters wrap `SearchService` and `UrlFetchService` without altering their internal logic, preserving 100% test compatibility for existing search and fetch test suites.

---

## 3. Caveats

- **Scope Boundary**: This design specifies Milestone 23.1 architecture, models, registry, legacy adapters, and test suites. Implementation of the 4 basic safe tools (`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`) is scheduled for Milestone 23.2, and `AgentLoopGuard` for Milestone 23.3.
- **Provider Architecture**: `toolRegistryProvider` is designed as `Provider<ToolRegistry>` initializing `ToolRegistry.defaultRegistry()`. If reactive UI toggles are needed in future settings UI, a dedicated `StateNotifier` or state wrapper can easily observe and emit registry states without breaking this foundation.
- **No caveats** regarding backward compatibility or schema divergence.

---

## 4. Conclusion

The complete architectural blueprint and test suite for Milestone 23.1 is finalized and documented in `D:\work\chat\.agents\explorer_m23_1\report.md`.
The design includes:
1. Complete source code designs for `tool_security_level.dart`, `tool_parameter.dart`, `tool_execution_result.dart`, `tool.dart`, `tool_registry.dart`, and `legacy_tool_adapters.dart`.
2. Detailed unit test designs for `test/models/tool_model_test.dart` (14 tests) and `test/services/tool_registry_test.dart` (16 tests).
3. Zero breaking changes to existing codebase, preserving 100% pass on all 173 baseline tests and 0 analyzer issues.

---

## 5. Verification Method

To verify the implementation of this design when implemented:
1. **Model Layer Verification**:
   - Verify all 4 model files exist in `lib/models/tool/` and `tool.dart` exports all companion models.
   - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat test test/models/tool_model_test.dart`.
2. **Registry & Legacy Adapter Verification**:
   - Verify `lib/services/tool_registry.dart` and `lib/services/tools/legacy_tool_adapters.dart` compile cleanly.
   - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat test test/services/tool_registry_test.dart`.
3. **Full Suite Regression & Linter Verification**:
   - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` -> Must report `No issues found!`.
   - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat test` -> All tests must pass (>=203 tests, 0 failures).
