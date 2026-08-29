# Project: Flutter AI Chat — Agent Tool Ecosystem

## Architecture Overview
The Agent Tool Ecosystem expands `chat-app` from simple text/search streaming into an autonomous multi-modal agent platform. It incorporates:
1. **Unified Pluggable Tool Registry (`ToolRegistry`)**: Centralized registration, model capability filtering, and OpenAI Function Calling schema export.
2. **Multi-tier Security & Human-in-the-Loop Framework**: 4 security tiers (`safe`, `readOnly`, `sensitiveConfirm`, `privilegedNative`) with interactive UI confirmation cards.
3. **Model Context Protocol (MCP) Client**: Full JSON-RPC 2.0 implementation over SSE, WebSocket, and Stdio transports with dynamic discovery, PID tracking, and timeout guards.
4. **Mobile Native Subsystem**: Android Calendar, Notifications/Alarms, Contacts, and Geolocation with declarative permissions, abstract service contracts, and PII sanitization.
5. **Token Management & Fault Tolerance**: Head/tail preserving `RuneSafeJsonTruncator`, `AgentLoopGuard` with MD5 cycle detection, and exponential backoff with jitter.

---

## Feature Inventory

| # | Feature | Category | Security Level | Milestone | Status |
|---|---|---|---|---|---|
| 1 | High-precision Math Calculator (`math_eval`) | Basic Utility | Safe | M23 | Planned |
| 2 | Timezone & Calendar Math (`time_calculator`) | Basic Utility | Safe | M23 | Planned |
| 3 | Real-time & Forecast Weather (`weather_query`) | Basic Utility | Safe | M23 | Planned |
| 4 | Encyclopedic Knowledge Lookup (`wiki_lookup`) | Basic Utility | Safe | M23 | Planned |
| 5 | Pluggable ToolRegistry & Lifecycle Provider | Core Engine | Safe | M23 | Planned |
| 6 | Existing Search & UrlFetch Tool Migration | Core Engine | Read-Only | M23 | Planned |
| 7 | AgentLoopGuard & Tool Cycle Detector | Core Engine | Safe | M23 | Planned |
| 8 | PathSanitizer & Workspace File Reader (`file_read`) | Local & Sandbox | Read-Only | M24 | Planned |
| 9 | Sandboxed File Writer with Diff (`file_write`) | Local & Sandbox | Sensitive-Confirm | M24 | Planned |
| 10| Workspace File Listing & Search (`file_list`/`search`) | Local & Sandbox | Read-Only | M24 | Planned |
| 11| Worker Isolate Sandboxed JS Interpreter (`code_eval`) | Local & Sandbox | Safe | M24 | Planned |
| 12| System Clipboard Read/Write (`clipboard_*`) | Local & Sandbox | Sensitive-Confirm | M24 | Planned |
| 13| Interactive Human-in-the-Loop Confirmation Card | UI & Security | Safe | M24 | Planned |
| 14| RuneSafeJsonTruncator Token Budget Engine | Engine | Safe | M24 | Planned |
| 15| Abstract Native Interfaces & Headless Test Mocks | Test Infra | Safe | M25 | Planned |
| 16| System Calendar Read/Write (`calendar_*`) | Mobile Native | Privileged-Native | M25 | Planned |
| 17| Scheduled Notifications & Alarms (`notification_*`) | Mobile Native | Privileged-Native | M25 | Planned |
| 18| ContactsSanitizer E.164 Query Tool (`contacts_search`)| Mobile Native | Privileged-Native | M25 | Planned |
| 19| GPS Geolocation & Reverse Geocoding (`geolocation_*`)| Mobile Native | Privileged-Native | M25 | Planned |
| 20| Unified Permission Manager & Manifest Updates | Native Layer | Safe | M25 | Planned |
| 21| MCP JSON-RPC 2.0 Multi-Transport (SSE/WS/Stdio) | MCP Protocol | Safe | M26 | Planned |
| 22| MCP Client State Machine, Handshake & Timeout Drain | MCP Protocol | Safe | M26 | Planned |
| 23| Dynamic Tool Discovery & Namespace Schema Mapper | MCP Protocol | Sensitive-Confirm | M26 | Planned |
| 24| SQLite Persistence (`McpServerDao`, Schema v4) | Data Layer | Safe | M26 | Planned |
| 25| MCP Server Management UI & Tool Inspector | UI Layer | Safe | M26 | Planned |
| 26| Multi-Tool E2E Adversarial Hardening Suite | Testing | Safe | M27 | Planned |
| 27| Release Packaging & Performance Benchmarking | DevOps | Safe | M27 | Planned |

---

## Milestones Summary

| Milestone | Name | Focus | Dependencies | Status |
|---|---|---|---|---|
| M23 | Core Tool Registry & Basic Built-in Tools | `math_eval`, `time_calc`, `weather_query`, `wiki_lookup`, `ToolRegistry`, `AgentLoopGuard` | None | PLANNED |
| M24 | Local Files & Sandboxed Code Execution | `PathSanitizer`, `file_*`, `code_eval` (Worker Isolate), `clipboard`, Human-in-the-loop, `RuneSafeJsonTruncator` | M23 | PLANNED |
| M25 | Mobile Native Capabilities & Permissions | `ICalendarService`, `IContactsService`, `ContactsSanitizer`, `INotificationService`, `ILocationService`, `MockNativeChannelHelper` | M23, M24 | PLANNED |
| M26 | Client-Side MCP Protocol & Management UI | SSE / WebSocket / Stdio Transports, Timeout Drainer, Dynamic Discovery, `McpServersScreen` | M23, M24 | PLANNED |
| M27 | Hardening, Adversarial Testing & Release | E2E Integration tests, Reconnect resilience, Release APK | M23-M26 | PLANNED |

---

## Interface Contracts

### 1. `Tool` Contract
```dart
abstract class Tool {
  String get name;
  String get displayName;
  String get description;
  ToolCategory get category;
  PermissionLevel get permissionLevel;
  List<ToolParameter> get parameters;
  ToolMetadata get metadata;
  bool get isBuiltIn;
  Duration get timeoutDuration;
  int get maxRetries;

  ToolValidationResult validateArguments(Map<String, dynamic> arguments);
  Map<String, dynamic> toOpenAiTool();
  Future<ToolExecutionResult> execute(ToolExecutionContext context, Map<String, dynamic> arguments);
}
```

### 2. `ToolRegistry` Contract
```dart
abstract class IToolRegistry {
  void register(Tool tool);
  void registerAll(List<Tool> tools);
  bool unregister(String toolName);
  Tool? getTool(String name);
  List<Tool> getAllTools();
  List<Tool> filterByCategory(ToolCategory category);
  List<Tool> getEffectiveTools({required ModelInfo model, required AppSettings settings, Set<String> disabledToolNames});
  List<Map<String, dynamic>> exportOpenAiTools(List<Tool> tools);
}
```

### 3. `McpTransport` & `McpClient` Contract
```dart
abstract class McpTransport {
  Stream<Map<String, dynamic>> get messageStream;
  Stream<McpTransportState> get stateStream;
  McpTransportState get currentState;
  Future<void> connect();
  Future<void> send(Map<String, dynamic> payload);
  Future<void> disconnect();
}
```
