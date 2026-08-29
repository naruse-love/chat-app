# Dispatch for Explorer Survey Pipeline

## Role
You are Explorer Survey Pipeline (`teamwork_preview_explorer`).
Working directory: `D:\work\chat\.agents\explorer_survey_pipeline\`

## Objective
Investigate the existing Agent pipeline, UI, loop management, and test suite:
1. `lib/services/agent_service.dart`: how agent execution, multi-round tool execution, event streams, and LLM calls are orchestrated.
2. `lib/models/agent_event.dart` (or similar): what event types exist (`AgentEvent`, `ToolCallStartedEvent`, `ToolCallCompletedEvent`, etc.), how they are emitted and consumed.
3. `lib/widgets/chat_bubble.dart` (or related UI in `lib/widgets/` or `lib/screens/`): how tool execution status, tool calling events, reasoning/thinking, and results are displayed in the chat interface.
4. Test setup: how agent tests and tool tests are structured in `test/`, how mocks (`MockLLMService`, `MockFlutterSecureStorage`, etc.) are written and executed.
5. Provide a detailed report in `D:\work\chat\.agents\explorer_survey_pipeline\report.md` and write `handoff.md`.

## Required Reading
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\context.md`
- Relevant files in `lib/` and `test/`
