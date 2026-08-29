# Handoff Report — Spec Miner M23

> **Agent**: `spec_miner_m23` (`teamwork_preview_spec_miner`)  
> **Milestone**: Milestone 23  
> **Date**: 2026-08-28T20:55:00+08:00  
> **Working Directory**: `D:\work\chat\.agents\spec_miner_m23`  

---

## 1. Observation

1. **`ORIGINAL_REQUEST.md` (lines 242-286)**:
   - "Follow-up — 2026-08-28T20:52:04+08:00: 在 Flutter AI 聊天应用中完整实现 Milestone 23：构建统一可插拔的 ToolRegistry 架构底座，实现首批四大基础实用工具（数学计算、时区时间、天气查询、维基百科知识检索），集成 AgentLoopGuard 防死循环机制，并与现有 Agent 调度链路无缝集成。"
   - Defines R1 (Pluggable Tool Architecture & ToolRegistry), R2 (4 Safe Built-in Tools: `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`), R3 (`AgentLoopGuard` with maxToolRounds = 8), and R4 (UI & Pipeline integration, 173 + 25+ tests, version bump to `1.08.0+9`, `WORK_LOG.md`).
2. **`AGENTS.md` (lines 10-38)**:
   - "1. 测试必须 100% 通过: 运行 D:\work\flutter-sdk\flutter\bin\flutter.bat test"
   - "2. 静态分析必须 0 问题: 运行 D:\work\flutter-sdk\flutter\bin\flutter.bat analyze"
   - "5. 错误信息使用中文"
   - "6. 版本号递增规范: 每次新增功能（feat）、修 bug（fix）或变更代码，必须给项目版本号增加 0.01（在 pubspec.yaml 的 version 字段，以及 WORK_LOG.md / context.md 等相关版本标注处同步递增）"
3. **`pubspec.yaml` (lines 19-20, lines 30-53)**:
   - `version: 1.07.0+8` (needs increment to `1.08.0+9`).
   - Dependencies: `flutter_riverpod: ^2.5.0`, `dio: ^5.4.0`, `sqflite: ^2.3.0`, `path_provider: ^2.1.0`, `flutter_secure_storage: ^9.0.0`, `flutter_markdown: ^0.7.0`, `highlight: ^0.7.0`, `uuid: ^4.3.0`, `shared_preferences: ^2.2.0`, `html: ^0.15.4`.
4. **Current Test & Analysis Status**:
   - Running `D:\work\flutter-sdk\flutter\bin\flutter.bat test`: Output `00:05 +173: All tests passed!`.
   - Running `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`: Output `No issues found! (ran in 2.0s)`.
5. **Existing Agent & UI Codebase**:
   - `lib/services/agent_service.dart` (lines 91-167): Hardcoded tool definitions for `webSearchTool`, `googleSearchTool`, `bingSearchTool`, `urlFetchTool`.
   - `lib/widgets/chat_bubble.dart` (lines 481-704): Custom panels for `_buildIntermediateAssistantPanel` and `_buildToolOutputPanel`.
   - `lib/providers/agent_provider.dart` (lines 4-34): Contains specialized flags (`isSearching`, `isFetchingUrl`).

---

## 2. Logic Chain

1. **Architecture Requirements (R1)**:
   - The current codebase directly branches on `entry.name == 'url_fetch'` and `entry.name == 'web_search'` inside `AgentService`.
   - To make tools pluggable and maintainable, a unified `Tool` base class must be established with structured `ToolParameter` definitions and `ToolExecutionResult` outputs.
   - The security model must support 4 distinct levels (`safe`, `readOnly`, `sensitiveConfirm`, `privilegedNative`) so that built-in computational tools run without risk while destructive tools can be confirmed.
   - Existing tools (`web_search`, `google_search`, `bing_search`, `url_fetch`) must be encapsulated as `Tool` instances to ensure 100% backwards compatibility with existing 173 test cases.
2. **Built-in Tools (R2)**:
   - `math_eval` should be implemented in pure Dart (using recursive descent parsing) with zero network/file permissions (Level 0 - `safe`), supporting full arithmetic, trigonometry, logs, sqrt, power, statistics, and unit conversion, with robust error catching for divide-by-zero.
   - `time_calculator` should handle IANA timezone resolution (with Chinese/English alias mappings like `Beijing` -> `Asia/Shanghai`), date offsets (`+3d`, `-5h30m`), durations, and relative natural dates.
   - `weather_query` should query the free Open-Meteo REST API (`https://api.open-meteo.com/v1/forecast`) and geocoding endpoint without requiring an API key.
   - `wiki_lookup` should query Wikipedia's public REST APIs for `zh` and `en`, cleanly extracting summaries and detecting disambiguation pages.
3. **AgentLoopGuard (R3)**:
   - In multi-turn LLM reasoning, models can repeat identical queries or oscillate between two tools indefinitely (e.g. A->B->A->B).
   - An `AgentLoopGuard` tracking tool call signatures (MD5 / canonical JSON arguments) can detect consecutive duplicate calls (>=3) or oscillations (period 2/3 cycles) and enforce `maxToolRounds = 8`.
   - When triggered, it strips the `tools` parameter and injects a concluding prompt to force the model into a final synthesized answer.
4. **UI & Pipeline Integration (R4)**:
   - `AgentService` delegates all tool executions to `ToolRegistry.getTool(name).execute(...)` guarded by `AgentLoopGuard`.
   - `ChatBubble` renders collapsible cards with Chinese labels, category icons, duration badges, and copy buttons.
   - Quality gates: 173 + 25+ new tests (>= 198 tests), 0 analyzer issues, version `1.08.0+9`, `WORK_LOG.md` and `context.md` updated.

---

## 3. Caveats

- **No External Paid APIs**: `weather_query` and `wiki_lookup` must strictly use free, public, keyless APIs (Open-Meteo and Wikipedia REST API).
- **Pure Dart Execution for Math/Time**: `math_eval` and `time_calculator` do not require third-party native binaries or shell subprocesses, ensuring complete safety and cross-platform compatibility across Android, iOS, Windows, macOS, and Linux.
- **Backwards Compatibility**: Existing SSE stream formats, pseudo-XML `<tool_call>` handling, DSML parsing, and manual `@search` prefix must remain 100% functional.

---

## 4. Conclusion

The specification and acceptance criteria for Milestone 23 are completely mined, synthesized, and documented in `D:\work\chat\.agents\spec_miner_m23\report.md`. The design is fully compatible with the existing Flutter/Riverpod/SQLite architecture and satisfies all AGENTS.md quality constraints.

---

## 5. Verification Method

1. **Verify Report Existence**: Inspect `D:\work\chat\.agents\spec_miner_m23\report.md`.
2. **Verify Baseline Tests**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat test
   ```
   (Must pass 173/173 tests).
3. **Verify Baseline Analyzer**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat analyze
   ```
   (Must report `No issues found!`).
4. **Milestone 23 Verification Command**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat test test/tool_registry_test.dart test/agent_loop_guard_test.dart test/basic_tools_test.dart
   ```
   (Target: 25+ new tests, all passing).
