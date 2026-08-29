# Milestone Evolution Roadmap & Implementation Work List (R3)
## Flutter AI Chat Application (`chat-app`)

> **Document Version**: v1.1.0-HARDENED  
> **Status**: Production-Ready Architectural Deliverable (Incorporating Adversarial Security Hardening)  
> **Target Release**: Milestones 23 – 27+  
> **Quality Constraint**: 0 Analyzer Warnings, 100% Test Pass Rate, Version Bump (+0.01 per milestone), Full Chinese UI Localization

---

## 1. Roadmap Evolution Overview

```
Milestone 23 ──► Milestone 24 ──► Milestone 25 ──► Milestone 26 ──► Milestone 27
[Core Tool]     [File & Code]   [Native Device]   [MCP Protocol]   [Hardening &]
[Registry &]    [Execution  ]   [Capabilities ]   [Client & UI ]   [Release Pkg]
[Basic Tools]   [Sandboxing ]   [Permissions  ]   [Transports  ]   [Token Opt  ]
```

---

## 2. Milestone 23: Core Tool Registry Foundation & Basic Built-in Tools

### 2.1 Objectives
- Establish the pluggable `ToolRegistry` and `Tool` abstraction architecture.
- Decouple tool execution from hardcoded `AgentService` logic.
- Implement the first suite of deterministic, zero-permission utility tools (`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`).
- Integrate `AgentLoopGuard` with cycle detection (`maxToolRounds = 8`).
- Integrate tool category icons and collapsible result cards in `ChatBubble`.

### 2.2 Tool Inventory & Deliverables
1. `lib/models/tool/tool.dart`: Abstract base classes `Tool`, `ToolParameter`, `ToolExecutionResult`, `ToolMetadata`.
2. `lib/services/tool_registry.dart`: Centralized `ToolRegistry` service with dynamic discovery, filtering, and OpenAI Schema export.
3. `lib/services/tools/math_eval_tool.dart`: High-precision math & formula calculator.
4. `lib/services/tools/time_calculator_tool.dart`: Timezone conversion and relative date calculator.
5. `lib/services/tools/weather_query_tool.dart`: Real-time and 7-day weather forecast query (Open-Meteo).
6. `lib/services/tools/wiki_lookup_tool.dart`: Wikipedia knowledge and summary retrieval.
7. `lib/services/tools/web_search_tool.dart` & `url_fetch_tool.dart`: Migration of existing search and fetch services into the `Tool` class hierarchy.
8. `lib/services/agent_loop_guard.dart`: Loop detector with MD5 tool call signature hashing.
9. `lib/providers/tool_registry_provider.dart`: Riverpod provider wrapping `ToolRegistry`.

### 2.3 Dependencies & Database Migrations
- **New Dependencies**: `math_expressions: ^2.0.0`, `decimal: ^3.0.0`, `timezone: ^0.9.4`, `intl: ^0.19.0`.
- **Database Schema**: Upgrade `DatabaseHelper` to `version: 4` (create `tool_configs` table for per-tool user toggles).

### 2.4 Testing Strategy
- Unit tests for all 4 new tools (`test/math_eval_tool_test.dart`, `test/time_calculator_tool_test.dart`, `test/weather_query_tool_test.dart`, `test/wiki_lookup_tool_test.dart`).
- Unit tests for `ToolRegistry` (`test/tool_registry_test.dart`) and `AgentLoopGuard` (`test/agent_loop_guard_test.dart`).
- Regression check on existing 173 tests ensuring 100% pass rate.

### 2.5 Quality Gates
- `flutter analyze` 0 issues.
- `flutter test` passes 100% (target: ~200 passing test cases).
- Bump `pubspec.yaml` version from `1.07.0+8` to `1.08.0+9`.
- Append entry to `WORK_LOG.md` and update `.agents/context.md`.

---

## 3. Milestone 24: Local File System & Sandboxed Code Execution

### 3.1 Objectives
- Provide secure local workspace file operations with `PathSanitizer` (symlink and absolute path defense).
- Implement sandboxed script execution via dedicated worker isolate (`CodeExecutionService`).
- Implement the Human-in-the-Loop interactive confirmation card framework for mutating actions (`file_write`, `clipboard_write`).
- Implement the `RuneSafeJsonTruncator` to protect LLM context windows without breaking JSON syntax or Unicode surrogate pairs.

### 3.2 Tool Inventory & Deliverables
1. `lib/services/path_sanitizer.dart`: Canonical symlink resolution, traversal rejection, 50MB quota check.
2. `lib/services/tools/file_read_tool.dart`: Secure workspace file reader with line pagination.
3. `lib/services/tools/file_write_tool.dart`: Sandboxed file writer (overwrite/append/patch) with diff preview.
4. `lib/services/tools/file_list_tool.dart` & `file_search_tool.dart`: Workspace directory listing and regex grep.
5. `lib/services/code_execution_service.dart` & `code_eval_tool.dart`: Spawned worker isolate evaluator with `isolate.kill` preemption.
6. `lib/services/tools/clipboard_tools.dart`: `clipboard_read` and `clipboard_write` tools.
7. `lib/services/token_truncation_engine.dart`: Rune-safe and JSON-aware truncation engine.
8. `lib/widgets/tool_confirmation_card.dart`: Interactive confirmation dialog and inline card.

### 3.3 Dependencies
- **New Dependencies**: `flutter_js: ^0.8.0`, `path: ^1.9.0`, `characters: ^1.3.0`.

### 3.4 Testing Strategy
- Path traversal attack penetration tests (`../../etc/passwd` injection and symlink jailbreak tests).
- Worker isolate `while(true)` preemption & microtask termination tests (`test/code_eval_sandbox_test.dart`).
- File write confirmation accept/deny flow tests.

### 3.5 Quality Gates
- 0 analyzer warnings, 100% test pass rate, version bump to `1.09.0+10`.

---

## 4. Milestone 25: Mobile Native Device Capabilities & Permission Layer

### 4.1 Objectives
- Enable mobile native capabilities (Calendar, Exact Reminders/Alarms, Contacts search, Geolocation) via pure Dart abstract interfaces (`ICalendarService`, `IContactsService`, `ILocationService`, `INotificationService`).
- Implement `ContactsSanitizer` with E.164 phone masking, strict field whitelisting, and prompt injection escaping.
- Provide `MockNativeChannelHelper` and `TestEnvironmentHelper` for headless CI testability.

### 4.2 Tool Inventory & Deliverables
1. `lib/services/native/calendar_native_service.dart` & `calendar_tools.dart`: System calendar query & event scheduling.
2. `lib/services/native/notification_native_service.dart` & `notification_tools.dart`: Push notification and exact alarm scheduling.
3. `lib/services/native/contacts_sanitizer.dart` & `contacts_tool.dart`: Address book query with privacy sanitization.
4. `lib/services/native/location_native_service.dart` & `geolocation_tools.dart`: GPS coordinates and reverse geocoding.
5. `lib/services/permission_manager_service.dart`: Unified permission check/request layer.
6. `test/mocks/mock_native_channel_helper.dart` & `test_environment_helper.dart`: Complete headless Platform Channel mock suite.

### 4.3 Dependencies & Android Manifest
- **Dependencies**: `device_calendar: ^4.3.2`, `flutter_local_notifications: ^17.2.2`, `flutter_contacts: ^1.1.9+2`, `geolocator: ^12.0.0`, `geocoding: ^3.0.0`, `permission_handler: ^11.3.1`.
- **AndroidManifest.xml**: Add `READ_CALENDAR`, `WRITE_CALENDAR`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `READ_CONTACTS`, `ACCESS_FINE_LOCATION`.

### 4.4 Testing Strategy
- Headless mock tests ensuring all tests run cleanly with 0 failures in CI.
- Permission denial fallback tests.

### 4.5 Quality Gates
- 0 analyzer warnings, 100% test pass rate, version bump to `1.10.0+11`.

---

## 5. Milestone 26: Client-Side MCP Protocol Integration & Management UI

### 5.1 Objectives
- Implement the Model Context Protocol (MCP) JSON-RPC 2.0 client supporting SSE, WebSocket, and Stdio transports.
- Implement per-request 15s timeout and disconnect flusher on pending completers.
- Dynamic tool discovery (`tools/list`), namespace routing (`mcp__<serverId>__<toolName>`), and OpenAI schema conversion.
- Build the `McpServersScreen` and Tool Inspector Drawer.

### 5.2 Deliverables
1. `lib/models/mcp/mcp_json_rpc.dart`: JSON-RPC 2.0 request/response/notification models.
2. `lib/models/mcp/mcp_server_config.dart`: MCP Server data model with transport configurations.
3. `lib/data/mcp_server_dao.dart`: SQLite persistence for user-configured MCP servers.
4. `lib/services/mcp/mcp_transport.dart`: `SseMcpTransport`, `WebSocketMcpTransport`, `StdioMcpTransport` (with child PID tracking).
5. `lib/services/mcp/mcp_client.dart`: MCP client state machine, handshake, ping, timeout, and tool execution.
6. `lib/services/mcp/mcp_schema_converter.dart`: Bidirectional schema mapper.
7. `lib/screens/mcp_servers_screen.dart`: Server management UI, latency indicators, and tool inspector drawer.

### 5.3 Testing Strategy
- Mock SSE streaming server test, mock WebSocket test, JSON-RPC error handling test, disconnect completer drain test.

### 5.4 Quality Gates
- 0 analyzer warnings, 100% test pass rate, version bump to `1.11.0+12`.

---

## 6. Milestone 27: Ecosystem Hardening, Adversarial Testing & Release Packaging

### 6.1 Objectives
- End-to-end multi-tool integration testing and token optimization.
- Adversarial error handling: MCP server crash recovery, corrupted payloads, timeout cascading.
- Release APK compilation and signature configuration.

### 6.2 Deliverables
1. `test/agent_tools_e2e_stress_test.dart`: 50+ adversarial scenarios.
2. `test/mcp_resilience_test.dart`: Network drop and reconnect resilience.
3. Release build script and keystore verification.
4. Complete project documentation update (`README.md`, `WORK_LOG.md`, `context.md`).

### 6.3 Quality Gates
- All 250+ unit and integration tests passing 100%.
- `flutter build apk --debug` and `flutter build apk --release` compile successfully.
- Version bump to `1.12.0+13`.
