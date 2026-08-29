# Dispatch for Explorer M23.1

## Role
You are Explorer M23.1 (`teamwork_preview_explorer`).
Working directory: `D:\work\chat\.agents\explorer_m23_1\`

## Objective
Design the concrete file contents, class hierarchies, method signatures, and unit tests for Milestone 23.1 (Pluggable Tool Architecture & ToolRegistry):
1. Model layer: `lib/models/tool/tool_security_level.dart`, `lib/models/tool/tool_parameter.dart`, `lib/models/tool/tool_execution_result.dart`, `lib/models/tool/tool.dart`.
2. Registry layer: `lib/services/tool_registry.dart` (dynamic/static registration, lookup, schema export for OpenAI function calling JSON schema, enablement/disablement state, Riverpod provider `toolRegistryProvider`).
3. Legacy Tool Adapters: `lib/services/tools/legacy_tool_adapters.dart` wrapping `SearchService` (`web_search`, `google_search`, `bing_search`) and `UrlFetchService` (`url_fetch`) to maintain 100% backward compatibility with all existing tool parameters.
4. Comprehensive test plan for `test/models/tool_model_test.dart` and `test/services/tool_registry_test.dart`.
5. Provide a detailed design and test specification in `D:\work\chat\.agents\explorer_m23_1\report.md` and write `handoff.md`.

## Required Reading
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\context.md`
- `D:\work\chat\TEST_INFRA.md`

## 2026-08-28T12:55:41Z
You are Explorer M23.1.
Working directory: D:\work\chat\.agents\explorer_m23_1\
Read D:\work\chat\.agents\explorer_m23_1\DISPATCH.md, D:\work\chat\PROJECT.md, D:\work\chat\.agents\ORIGINAL_REQUEST.md, D:\work\chat\.agents\AGENTS.md, D:\work\chat\.agents\context.md, and D:\work\chat\TEST_INFRA.md.

Design the concrete file contents, class hierarchies, method signatures, and unit tests for Milestone 23.1:
1. Model layer: lib/models/tool/tool_security_level.dart, lib/models/tool/tool_parameter.dart, lib/models/tool/tool_execution_result.dart, lib/models/tool/tool.dart.
2. Registry layer: lib/services/tool_registry.dart (registration, lookup, schema export for OpenAI JSON schema, enablement/disablement state, Riverpod provider toolRegistryProvider).
3. Legacy Tool Adapters: lib/services/tools/legacy_tool_adapters.dart (web_search, google_search, bing_search, url_fetch adapters).
4. Unit tests in test/models/tool_model_test.dart and test/services/tool_registry_test.dart.
5. Write your detailed design to D:\work\chat\.agents\explorer_m23_1\report.md and your handoff to D:\work\chat\.agents\explorer_m23_1\handoff.md.
Send a completion message back to parent when done.
