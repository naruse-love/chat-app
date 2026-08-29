## 2026-08-28T12:53:02Z
# Dispatch for Explorer Survey Tools

## Role
You are Explorer Survey Tools (`teamwork_preview_explorer`).
Working directory: `D:\work\chat\.agents\explorer_survey_tools\`

## Objective
Investigate all existing tool mechanisms in the codebase (`d:\work\chat`):
1. How `web_search`, `google_search`, `bing_search`, `url_fetch`, and any other existing tools are implemented in `lib/services/` or `lib/models/`.
2. How tool schemas are defined, converted for OpenAI / other LLM function calling formats, and executed.
3. How Riverpod providers provide tools or tool execution services.
4. What data structures (`ToolCall`, `ToolResult`, etc.) exist in `lib/models/` and how they are serialized/deserialized.
5. Provide a detailed report in `D:\work\chat\.agents\explorer_survey_tools\report.md` and write `handoff.md`.

## Required Reading
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\context.md`
- Relevant files in `lib/` and `test/`
