# Dispatch for Worker M23.3

## Role
You are Worker M23.3 (`teamwork_preview_worker`).
Working directory: `D:\work\chat\.agents\worker_m23_3\`

## Objective
Implement Milestone 23.3 (AgentLoopGuard):
1. `lib/services/agent_loop_guard.dart`:
   - Pure Dart implementation with zero extra dependencies.
   - `ToolCallSignature`: canonical recursive key sorting, pure Dart MD5 hash calculation, formatted representation.
   - `LoopCheckStatus`: `allowed`, `consecutiveDuplicate`, `oscillation`, `maxRoundsReached`.
   - `LoopCheckResult`: status, isTerminated, reason (in Chinese), toolName, signature, cycleLength.
   - `AgentLoopGuard`:
     - `maxToolRounds` (default 8).
     - `duplicateThreshold` (default 3 consecutive duplicates).
     - `oscillationHistoryDepth` (default 12).
     - `recordToolCall(toolName, arguments)`
     - `checkNextCall(toolName, arguments, currentRound)`
     - `recordAndCheck(toolName, arguments, currentRound)`
     - `shouldStripTools(currentRound)`
     - `getForcedConclusionPrompt(status or reason)` (in Chinese)
     - `reset()`
2. `test/services/agent_loop_guard_test.dart`:
   - Comprehensive unit test suite (24+ scenarios covering all normal and loop edge cases).
3. Run `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` and `D:\work\flutter-sdk\flutter\bin\flutter.bat test`.
4. Ensure 0 analyzer issues and 100% test pass.
5. Write `handoff.md` and report.

## Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. An auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Reference Files
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\explorer_m23_3\report.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\TEST_INFRA.md`
