# Dispatch for Forensic Auditor (M23.2)

## Role
You are Forensic Auditor for Milestone 23.2 (`teamwork_preview_auditor`).
Working directory: `D:\work\chat\.agents\auditor_m23_2\`

## Objective
Perform strict forensic integrity audit on Milestone 23.2:
1. Verify that `math_eval_tool.dart`, `time_calculator_tool.dart`, `weather_query_tool.dart`, and `wiki_lookup_tool.dart` implement real, genuine parsing and execution logic (no dummy mocks in production code, no hardcoded expected results, no fake math/time calculations).
2. Check that unit tests genuinely execute the production code.
3. Check for any cheats, shortcuts, or fabricated outputs.
4. Run `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` and `D:\work\flutter-sdk\flutter\bin\flutter.bat test`.
5. Provide a binary verdict: `CLEAN` or `INTEGRITY VIOLATION`.
6. Write `handoff.md` and send a message.

## Required Reading
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\worker_m23_2\handoff.md`

## 2026-08-28T13:13:41Z
<USER_REQUEST>
You are Forensic Auditor for Milestone 23.2.
Working directory: D:\work\chat\.agents\auditor_m23_2\
Read D:\work\chat\.agents\auditor_m23_2\DISPATCH.md, D:\work\chat\PROJECT.md, D:\work\chat\.agents\worker_m23_2\handoff.md, D:\work\chat\.agents\ORIGINAL_REQUEST.md, D:\work\chat\.agents\AGENTS.md.

Perform integrity audit: verify genuine math/time/weather/wiki logic, authentic tests, no hardcoded cheating. Run flutter analyze and flutter test.
Write your handoff report with explicit verdict CLEAN or INTEGRITY VIOLATION to D:\work\chat\.agents\auditor_m23_2\handoff.md and send a completion message.
</USER_REQUEST>

