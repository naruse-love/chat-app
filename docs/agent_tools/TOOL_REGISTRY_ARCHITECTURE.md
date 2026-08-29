# Pluggable Tool Registry Architecture & Execution Engine Specification (R2)
## Flutter AI Chat Application (`chat-app`)

> **Document Version**: v1.1.0-HARDENED  
> **Status**: Production-Ready Architectural Deliverable (Incorporating Adversarial Security Hardening)  
> **Target Platform**: Flutter (Android / iOS / Desktop)  
> **Scope**: Unified Tool Interface, Lifecycle, Security & Human-in-the-Loop, Streaming Pipeline, UI Collapsible Cards, Fault Tolerance

---

## 1. System Architecture Overview

The **Pluggable Tool Registry Architecture** decouples tool execution from the conversational LLM loop, transforming `chat-app` into a scalable, multi-modal agent platform:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                  ToolRegistry                                   │
│  - register(Tool) / unregister(name)                                            │
│  - getTool(name) / getAllTools()                                                │
│  - getEffectiveTools(ModelInfo, AppSettings, disabledTools)                     │
│  - exportOpenAiTools() / exportSystemPromptDescription()                        │
└───────────────────────┬─────────────────────────────────┬───────────────────────┘
                        │ 1 : N                           │ 1 : N
                        ▼                                 ▼
         ┌──────────────────────────────┐  ┌──────────────────────────────┐
         │     Static Built-in Tools    │  │    Dynamic External Tools    │
         ├──────────────────────────────┤  ├──────────────────────────────┤
         │ • WebSearchTool (SearXNG/Bing│  │ • McpTool (Stdio/SSE/WS)     │
         │ • UrlFetchTool (HTML Parser) │  │ • ScriptEvalTool (QuickJS)   │
         │ • MathEvalTool (Calculator)  │  │ • CustomPluginTool (REST API)│
         │ • TimeTool (Timezone/Clock)  │  │ • NativeCalendarTool (Mobile)│
         └──────────────┬───────────────┘  └──────────────┬───────────────┘
                        └────────────────┬────────────────┘
                                         ▼
                     ┌───────────────────────────────────────┐
                     │          abstract class Tool          │
                     ├───────────────────────────────────────┤
                     │ + name: String                        │
                     │ + displayName: String                 │
                     │ + description: String                 │
                     │ + category: ToolCategory              │
                     │ + permissionLevel: PermissionLevel    │
                     │ + parameters: List<ToolParameter>     │
                     │ + isBuiltIn: bool                     │
                     │ + isEnabled: bool                     │
                     │ + timeoutDuration: Duration           │
                     │ + maxRetries: int                     │
                     │ + execute(context, args): Future<Res> │
                     └───────────────────────────────────────┘
```

---

## 2. Core Class Hierarchies & Contracts

### 2.1 Enums & Data Types

```dart
enum PermissionLevel {
  safe,             // Pure local compute, auto-execute (math, time)
  readOnly,         // External read, no side effects (search, url_fetch, file_read)
  sensitiveConfirm, // Mutating changes (file_write, clipboard, mcp_call) -> Interactive UI Prompt
  privilegedNative, // Native OS hardware/PII (calendar, notifications, contacts, GPS) -> OS Permission + UI Prompt
}

enum ToolCategory {
  search,
  web,
  utility,
  fileSystem,
  codeExecution,
  mcp,
  nativeDevice,
  customPlugin,
}
```

### 2.2 Tool Base Class (`abstract class Tool`)

```dart
abstract class Tool {
  String get name;
  String get displayName;
  String get description;
  ToolCategory get category;
  PermissionLevel get permissionLevel;
  List<ToolParameter> get parameters;
  ToolMetadata get metadata;
  bool get isBuiltIn => true;
  Duration get timeoutDuration => const Duration(seconds: 15);
  int get maxRetries => 2;

  ToolValidationResult validateArguments(Map<String, dynamic> arguments);
  Map<String, dynamic> toOpenAiTool();
  Future<ToolExecutionResult> execute(ToolExecutionContext context, Map<String, dynamic> arguments);
}
```

### 2.3 Execution Context & Structured Result

```dart
class ToolExecutionContext {
  final String conversationId;
  final String messageId;
  final String toolCallId;
  final CancelToken? cancelToken;
  final void Function(double progress, String statusMessage)? onProgress;
}

class ToolExecutionResult {
  final ToolExecutionStatus status; // success, failure, deniedByUser, timeout, schemaError
  final String output;              // Text returned to LLM context
  final dynamic rawJson;            // Structured data for UI
  final String? formattedMarkdown;  // Formatted presentation for ChatBubble
  final String? error;              // Diagnostic error
  final Duration executionDuration; // Timing benchmark
  final bool isTruncated;
  final int originalLength;
  final Map<String, dynamic> metadata;
}
```

---

## 3. Human-in-the-Loop Security & Confirmation Workflow

When an executing tool possesses `sensitiveConfirm` or `privilegedNative` classification:

```
[Agent LLM Loop] ──► Decides to call `file_write`
        │
        ▼
[ToolRegistry Engine] ──► Checks permissionLevel == `sensitiveConfirm`
        │
        ├─► If already granted in session whitelist ──► Execute directly
        │
        └─► If not granted:
                │
                ├─► Emit `ToolConfirmationRequiredEvent`
                ├─► Pause Stream via `Completer<ConfirmationDecision>` (with CancelToken integration)
                ├─► UI Renders Interactive Confirmation Card in ChatBubble
                │
                ▼
      [User Taps Decision Button]
        ├── "允许本次 (Allow Once)" ──► Resume stream & Execute
        ├── "本会话始终允许 (Always Allow)" ──► Add to session whitelist, Resume & Execute
        └── "拒绝执行 (Deny)" ──► Resume stream with `ToolExecutionResult.deniedByUser()`
                                   (LLM receives rejection and self-heals)
```

---

## 4. Streaming Event Pipeline & Riverpod State Model

### 4.1 Event Pipeline Hierarchy

```dart
abstract class AgentStreamEvent {}

class TextDeltaEvent extends AgentStreamEvent {
  final String delta;
}

class ReasoningDeltaEvent extends AgentStreamEvent {
  final String delta;
}

class ToolCallStartedEvent extends AgentStreamEvent {
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final ToolCategory category;
}

class ToolConfirmationPendingEvent extends AgentStreamEvent {
  final String toolCallId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final PermissionLevel permissionLevel;
  final Completer<ConfirmationDecision> completer;
}

class ToolCallExecutingEvent extends AgentStreamEvent {
  final String toolCallId;
  final double progress;
  final String statusText;
}

class ToolCallCompletedEvent extends AgentStreamEvent {
  final String toolCallId;
  final String toolName;
  final ToolExecutionResult result;
}

class ToolCallErrorEvent extends AgentStreamEvent {
  final String toolCallId;
  final String error;
}
```

### 4.2 UI Collapsible Card Rendering (`ChatBubble`)

All intermediate tool calling steps are rendered as collapsible process cards:
- **Header**: Icon (by `ToolCategory`), Tool Name, Execution Time Badge (`142ms`), Status Spinner / Checkmark / Error Cross.
- **Body**: Expandable JSON parameter inspector + Formatted Markdown result + One-click "Copy Result" button.
- **Collapsed by Default**: Preserves chat vertical rhythm; expands with a single tap.

---

## 5. Token Budget, Truncation & Fault Tolerance Engine (Hardened)

### 5.1 `RuneSafeJsonTruncator` Engine (Hardened against RES-03)
- **Rune-Safe Boundaries**: Employs `Characters` to eliminate invalid UTF-8 surrogate pair splits.
- **JSON Structure Preservation**: Detects structured JSON payloads; retains top-level keys and truncates intermediate array items while preserving valid JSON syntax.
- **Max Payload**: 15,000 characters (~3,750 tokens) per tool output.

### 5.2 Exponential Backoff with Jitter
- For transient network errors (`SocketException`, HTTP `502/503/504`, `429 RateLimit`):
  `delay = min(initialDelay * 2^attempt + randomJitter(0, 500ms), maxDelay)`

### 5.3 `AgentLoopGuard` & Cycle Detection (Hardened against RES-02)
- **Default Loop Limit**: Set to `maxToolRounds = 8` (configurable up to 15).
- **Cycle Detection**: Hashes `toolName + canonicalJson(arguments)` into a sliding window. Aborts with `DUPLICATE_CALL_BLOCKED` upon repeated oscillations.
- **Strict Summary Phase**: Enforces `isFinalSummaryTurn = true` during degraded turn, stripping `tools` parameter and disabling pseudo-XML tool calls.
