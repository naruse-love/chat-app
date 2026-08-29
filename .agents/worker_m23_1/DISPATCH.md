# Dispatch for Worker M23.1

## Role
You are Worker M23.1 (`teamwork_preview_worker`).
Working directory: `D:\work\chat\.agents\worker_m23_1\`

## Objective
Implement Milestone 23.1 (Pluggable Tool Architecture & ToolRegistry) and write comprehensive unit tests:
1. `lib/models/tool/tool_security_level.dart`: 4-level security model (`safe` Level 0, `readOnly` Level 1, `sensitiveConfirm` Level 2, `privilegedNative` Level 3).
2. `lib/models/tool/tool_parameter.dart`: Structured parameter descriptor with type, description, required, enum, default, and `toOpenAiSchema()`.
3. `lib/models/tool/tool_execution_result.dart`: Result model with success, content, rawData, errorMessage, executionDuration.
4. `lib/models/tool/tool.dart`: Abstract `Tool` base class and exports for companion files.
5. `lib/services/tool_registry.dart`: Registration, deregistration, lookup, schema export, enable/disable toggle, Riverpod `toolRegistryProvider`.
6. `lib/services/tools/legacy_tool_adapters.dart`: Adapters for `web_search`, `google_search`, `bing_search`, `url_fetch` wrapping `SearchService` and `UrlFetchService`.
7. Unit tests:
   - `test/models/tool_model_test.dart`
   - `test/services/tool_registry_test.dart`
8. Run `flutter analyze` and `flutter test` to ensure 0 analyzer issues and 100% test pass.
9. Write `handoff.md` with complete verification outputs.

## Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Reference Files
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\explorer_m23_1\report.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\context.md`
