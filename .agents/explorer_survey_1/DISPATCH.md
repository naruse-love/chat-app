# DISPATCH — explorer_survey_1

## Objective
Investigate codebase for R1 and R2:
- R1: Disable sidebar session list swipe gestures by removing `Dismissible` wrapper in `lib/screens/home_screen.dart` while retaining the 3-dot popup menu (`PopupMenuButton`) for pin/archive/delete operations. Check existing tests in `test/` for home screen / sidebar list.
- R2: Add global web search control switch `enableAutoSearch` in `lib/screens/settings_screen.dart` and `lib/providers/settings_provider.dart`. Ensure when disabled, `lib/services/agent_service.dart` and `lib/providers/chat_provider.dart` do not send `web_search` / `google_search` / `bing_search` tool calls to LLM.

## Working Directory
`D:\work\chat\.agents\explorer_survey_1`

## Mandatory Input Files
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\context.md`

## Output Requirements
Write `handoff.md` in your working directory `D:\work\chat\.agents\explorer_survey_1` detailing:
1. Exact line locations and code structure in `home_screen.dart` for the `Dismissible` widget and 3-dot menu.
2. Exact structure in `settings_screen.dart` and `settings_provider.dart` for adding `enableAutoSearch` preference.
3. How `agent_service.dart` and `chat_provider.dart` currently pass tools to LLM and how to filter out `web_search`, `google_search`, `bing_search` when `enableAutoSearch == false`.
4. Affected test files in `test/` and recommended changes/additions for R1 and R2.
