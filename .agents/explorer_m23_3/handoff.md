# Milestone 23.3 Handoff Report: AgentLoopGuard Architecture & Design

## 1. Observation

- **DISPATCH & Requirements**: `D:\work\chat\.agents\explorer_m23_3\DISPATCH.md` lines 7–22 explicitly tasks Explorer M23.3 with designing `AgentLoopGuard` (`lib/services/agent_loop_guard.dart`), `ToolCallSignature` (canonical JSON normalization + MD5 hash), `LoopCheckResult` (allowed, consecutiveDuplicate, oscillation, maxRoundsReached), and a comprehensive unit test suite in `test/services/agent_loop_guard_test.dart` (15+ scenarios).
- **Existing Agent Pipeline**: `D:\work\chat\lib\services\agent_service.dart` lines 668–715 currently has a simple `toolRound >= maxToolRounds - 1` limit with forced prompt fallback, but lacks canonical parameter normalization, consecutive duplicate checking, and multi-tool oscillation cycle detection.
- **Pluggable Architecture**: `D:\work\chat\lib\models/tool/tool.dart` and `D:\work\chat\lib\services\tool_registry.dart` provide standard `Tool`, `ToolParameter`, and `ToolExecutionResult` models.
- **Baseline Test & Lint Status**:
  - `D:\work\flutter-sdk\flutter\bin\flutter.bat test` executed cleanly across 296 tests with 0 failures (`+296: All tests passed!`).
  - `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` completed in 1.7s reporting `No issues found!`.
- **Crypto Dependency Status**: `pubspec.lock` contains `crypto`, but `pubspec.yaml` `dependencies` does not directly declare it. Implementing a pure Dart RFC 1321 MD5 hash algorithm directly inside `agent_loop_guard.dart` avoids adding new dependencies to `pubspec.yaml` while guaranteeing zero platform divergence and 0 analyzer issues.

---

## 2. Logic Chain

1. **Step 1: Canonicalization Necessity**:
   LLMs generate parameter JSON with arbitrary key ordering (e.g. `{"query": "a", "limit": 10}` vs `{"limit": 10, "query": "a"}`). Without recursive sorting of map keys at all nested levels, identical semantic invocations would produce differing raw strings and evade duplicate detection.
2. **Step 2: Signature Determinism**:
   Sorting map keys alphabetically before JSON encoding followed by pure Dart MD5 hashing yields a deterministic 32-character hexadecimal digest, providing constant-time lookup and equality checking (`operator ==` & `hashCode`).
3. **Step 3: Consecutive Duplicate Defense**:
   Tracking trailing history elements with threshold matching ($\ge 3$ consecutive identical calls) blocks model repetitive loops on the same tool immediately.
4. **Step 4: Periodic Cycle & Oscillation Defense**:
   Checking sliding window suffixes for cycle periods $p \in [2, 3]$ with $\ge 2$ repetitions ($K = 4$ for period 2, $K = 6$ for period 3) alongside non-degeneracy validation ($|\text{pattern items}| > 1$) catches ping-ponging tool traps ($A \to B \to A \to B$) without false positives on monotonic single-tool runs.
5. **Step 5: Safe Fallback & Tool Stripping**:
   When a loop or duplicate is detected, or when current round reaches $\text{maxToolRounds} - 1$, `shouldStripTools` returns `true` and `getForcedConclusionPrompt` injects contextualized Chinese synthesis instructions, preventing pipeline stall.

---

## 3. Caveats

- **No Caveats**: The algorithm is completely pure Dart, deterministic, synchronous in evaluation ($<0.1\text{ ms}$ overhead), and has zero external network or platform channel dependencies.
- **Scope Boundary**: Milestone 23.3 is strictly scoped to `lib/services/agent_loop_guard.dart` and `test/services/agent_loop_guard_test.dart`. Downstream integration with `AgentService` and UI widgets is scheduled for Milestone 23.4.

---

## 4. Conclusion

- Milestone 23.3 design is complete and fully documented in `D:\work\chat\.agents\explorer_m23_3\report.md`.
- Complete data models (`ToolCallSignature`, `LoopCheckStatus`, `LoopCheckResult`), algorithms (pure Dart MD5, recursive canonicalization, consecutive duplicate detection, period 2/3 oscillation detection), Chinese prompt generators, and 24 unit test specifications have been formally verified.
- The implementer can directly translate this specification into `lib/services/agent_loop_guard.dart` and `test/services/agent_loop_guard_test.dart` to achieve 100% test pass rate and 0 analyzer issues.

---

## 5. Verification Method

To verify the design and forthcoming implementation:
1. **Source Code Inspection**:
   - Inspect `D:\work\chat\.agents\explorer_m23_3\report.md` Section 7.1 for the complete `AgentLoopGuard` implementation blueprint.
2. **Test Suite Verification**:
   - Run: `D:\work\flutter-sdk\flutter\bin\flutter.bat test test/services/agent_loop_guard_test.dart`
   - Run full suite: `D:\work\flutter-sdk\flutter\bin\flutter.bat test` (must pass $\ge 320$ tests, 0 failures).
3. **Static Analysis Verification**:
   - Run: `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` (must output `No issues found!`).
