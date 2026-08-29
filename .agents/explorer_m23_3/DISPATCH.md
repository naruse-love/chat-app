# Dispatch for Explorer M23.3

## Role
You are Explorer M23.3 (`teamwork_preview_explorer`).
Working directory: `D:\work\chat\.agents\explorer_m23_3\`

## Objective
Design the complete architecture, data models, loop/oscillation/signature detection algorithms, and test specifications for Milestone 23.3 (AgentLoopGuard):
1. `lib/services/agent_loop_guard.dart`:
   - `ToolCallSignature`: normalization of arguments to canonical JSON (sorted keys) and MD5/hash signature.
   - `LoopCheckResult`: enum/class for `allowed`, `consecutiveDuplicate`, `oscillation`, `maxRoundsReached`.
   - `AgentLoopGuard`:
     - `maxToolRounds` (default 8).
     - `duplicateThreshold` (default 3 consecutive duplicates).
     - `oscillationHistoryDepth` (e.g. last 10 calls, checking cycle lengths 2 and 3).
     - `recordToolCall(...)` / `checkBeforeExecution(...)` / `recordAndCheck(...)`.
     - `shouldStripTools(int currentRound)`
     - `getForcedConclusionPrompt()` (Chinese)
     - `reset()`
2. `test/services/agent_loop_guard_test.dart`:
   - 15+ comprehensive unit test scenarios.
3. Write `report.md` and `handoff.md`.

## Required Reading
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\TEST_INFRA.md`
