# Dispatch for Explorer M23.4

## Role
You are Explorer M23.4 (`teamwork_preview_explorer`).
Working directory: `D:\work\chat\.agents\explorer_m23_4\`

## Objective
Design the complete integration and UI enhancement for Milestone 23.4:
1. `lib/services/agent_service.dart`:
   - Inspect existing `AgentService` constructors, `toolRegistry`, `agentLoopGuard`.
   - Connect `ToolRegistry` for tool schema exports (`getEffectiveTools`) and execution (`toolRegistry.execute`).
   - Connect `AgentLoopGuard` in `_streamCompletionsLoop` (signature checking, duplicate detection, oscillation detection, `maxToolRounds = 8`, tool stripping, conclusion prompt injection).
   - Keep 100% backward compatibility with existing SSE events, pseudo-XML/DSML parsing, manual `@search`, and all existing 173 test cases.
2. `lib/widgets/chat_bubble.dart`:
   - Inspect `_buildIntermediateAssistantPanel` and `_buildToolOutputPanel`.
   - Add friendly Chinese tool names, category icons, status chips, and collapsible cards for `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`, `web_search`, `url_fetch`.
3. `test/services/agent_service_tool_integration_test.dart`:
   - Design E2E mock tests simulating multi-round tool calls with `MockChatService` and `ToolRegistry` (e.g. math calculation, loop guard triggering, max round limit fallback).
4. `pubspec.yaml`, `WORK_LOG.md`, `.agents/context.md` updates.
5. Write `report.md` and `handoff.md`.

## Required Reading
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\context.md`
- `D:\work\chat\TEST_INFRA.md`
