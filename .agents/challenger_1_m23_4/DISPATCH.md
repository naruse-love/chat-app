# Dispatch for Challenger 1 (M23.4)

## Role
You are Challenger 1 for Milestone 23.4 (`teamwork_preview_challenger`).
Working directory: `D:\work\chat\.agents\challenger_1_m23_4\`

## Objective
Empirically stress-test the integrated agent pipeline:
1. Multi-round tool chains (e.g. `weather_query` followed by `math_eval` followed by `time_calculator`).
2. Concurrent tool invocations in a single assistant response.
3. Edge cases in tool failure recovery and loop guard termination.
4. Run `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` and `D:\work\flutter-sdk\flutter\bin\flutter.bat test`.
5. Give an explicit verdict: `APPROVE` or `REQUEST_CHANGES`.
6. Write `handoff.md` and send a message.

## Required Reading
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\worker_m23_4\handoff.md`
