# Project: Milestone 23 — Pluggable Tool Architecture & Built-in Tools

## Architecture
- **Model Layer** (`lib/models/tool/`):
  - `tool.dart`: Abstract `Tool` class defining `name`, `description`, `parameters`, `securityLevel`, `execute(Map<String, dynamic> arguments)`.
  - `tool_parameter.dart`: Structured definition for tool parameters (type, description, required, enum values, default value).
  - `tool_execution_result.dart`: Structured execution output (success, content, rawData, errorMessage, executionDuration).
  - `tool_security_level.dart`: 4-level security model (`safe` Level 0, `readOnly` Level 1, `sensitiveConfirm` Level 2, `privilegedNative` Level 3).
- **Registry Layer** (`lib/services/tool_registry.dart`):
  - `ToolRegistry`: Dynamic/static registration, lookup, schema export for OpenAI Function Calling JSON format, dynamic enable/disable state, lifecycle management.
  - Riverpod provider: `toolRegistryProvider`.
  - Built-in adapters: `WebSearchTool`, `GoogleSearchTool`, `BingSearchTool`, `UrlFetchTool` wrapping `SearchService` and `UrlFetchService`.
- **Built-in Safe Tools** (`lib/services/tools/`):
  - `math_eval`: Pure Dart recursive descent expression evaluator with arithmetic, trigonometry, logs, sqrt, power, statistics (mean/median/stddev), unit conversion (temp, length, weight, storage), divide-by-zero protection.
  - `time_calculator`: Timezone resolution (IANA & common Chinese/English aliases), relative date math (`+3d`, `-5h`), duration between timestamps, timestamp formatting.
  - `weather_query`: Free Open-Meteo REST API (`https://api.open-meteo.com/v1/forecast`) and geocoding endpoint, current conditions + 7-day forecast.
  - `wiki_lookup`: Wikipedia public REST API (`zh` and `en`), summary extraction, search fallback, disambiguation handling.
- **Guard Layer** (`lib/services/agent_loop_guard.dart`):
  - `AgentLoopGuard`: Tool call history tracker, signature calculation (canonical JSON / MD5), consecutive duplicate argument detection (>=3 repetitions), oscillation detection (cycles like A->B->A->B of period 2 or 3), `maxToolRounds` enforcement (default 8).
  - Fallback mechanism: strips tools and injects conclusion prompt when threshold or loop triggered.
- **Pipeline & UI Layer** (`lib/services/agent_service.dart`, `lib/widgets/chat_bubble.dart`, `lib/providers/chat_provider.dart`):
  - `AgentService`: Invokes tools via `ToolRegistry.execute()` and protects multi-round loops with `AgentLoopGuard`.
  - `ChatBubble`: Rich collapsible panels with Chinese labels, icons, duration badges, and status chips for all tool types.
  - `chatProvider`: Seamlessly manages streaming events, persisting messages and tool executions.

## Code Layout
- `lib/models/tool/tool.dart` — Abstract tool interface
- `lib/models/tool/tool_parameter.dart` — Tool parameter descriptor
- `lib/models/tool/tool_execution_result.dart` — Tool result model
- `lib/models/tool/tool_security_level.dart` — Security permission level enum
- `lib/services/tool_registry.dart` — Central tool registry and riverpod provider
- `lib/services/tools/math_eval_tool.dart` — math_eval implementation
- `lib/services/tools/time_calculator_tool.dart` — time_calculator implementation
- `lib/services/tools/weather_query_tool.dart` — weather_query implementation
- `lib/services/tools/wiki_lookup_tool.dart` — wiki_lookup implementation
- `lib/services/tools/legacy_tool_adapters.dart` — Adapters for web_search, google_search, bing_search, url_fetch
- `lib/services/agent_loop_guard.dart` — AgentLoopGuard implementation
- `lib/services/agent_service.dart` — Agent pipeline integrated with ToolRegistry & AgentLoopGuard
- `lib/widgets/chat_bubble.dart` — Enhanced UI rendering for tool calls
- `test/models/tool_model_test.dart` — Tests for tool data models and serialization
- `test/services/tool_registry_test.dart` — Tests for tool registration, schema export, and dispatch
- `test/services/basic_tools_test.dart` — Comprehensive tests for 4 safe basic tools
- `test/services/agent_loop_guard_test.dart` — Tests for loop, oscillation, duplicate, and max rounds guard
- `test/services/agent_service_tool_integration_test.dart` — End-to-end agent pipeline tool integration tests

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Tool Base Class & Models | Abstract `Tool`, `ToolParameter`, `ToolExecutionResult`, `ToolSecurityLevel` | M23.1 | ORIGINAL_REQUEST §R1 |
| 2 | Tool Registry Core | Registration, deregistration, lookup, schema export for OpenAI JSON Schema | M23.1 | ORIGINAL_REQUEST §R1 |
| 3 | Legacy Search & Fetch Adapters | Adapters for `web_search`, `google_search`, `bing_search`, `url_fetch` | M23.1 | ORIGINAL_REQUEST §R1 |
| 4 | Riverpod toolRegistryProvider | Global reactive tool registry provider | M23.1 | ORIGINAL_REQUEST §R1 |
| 5 | math_eval Tool | Pure Dart high-precision math, stats, trig, logs, units, error handling | M23.2 | ORIGINAL_REQUEST §R2 |
| 6 | time_calculator Tool | IANA timezone queries, relative dates, timestamp durations, formatting | M23.2 | ORIGINAL_REQUEST §R2 |
| 7 | weather_query Tool | Open-Meteo API integration, geocoding, current weather & 7-day forecast | M23.2 | ORIGINAL_REQUEST §R2 |
| 8 | wiki_lookup Tool | Wikipedia API (zh & en), summary lookup, disambiguation handling | M23.2 | ORIGINAL_REQUEST §R2 |
| 9 | AgentLoopGuard Core | Consecutive duplicate signature detection (MD5 / canonical JSON) | M23.3 | ORIGINAL_REQUEST §R3 |
| 10 | Oscillation & Cycle Detection | Detection of cyclic calls (e.g. A->B->A->B period 2/3) | M23.3 | ORIGINAL_REQUEST §R3 |
| 11 | Safe Max Tool Rounds Limit | Safe limit `maxToolRounds = 8` with forced text fallback | M23.3 | ORIGINAL_REQUEST §R3 |
| 12 | AgentService Pipeline Integration | Execute tools via `ToolRegistry` and guard with `AgentLoopGuard` | M23.4 | ORIGINAL_REQUEST §R4 |
| 13 | ChatBubble UI Enhancement | Collapsible cards, status chips, Chinese titles, duration badges | M23.4 | ORIGINAL_REQUEST §R4 |
| 14 | E2E & Unit Test Coverage | Add 25+ comprehensive new tests, verify 100% test pass (>=198 tests) | M23.4 | AGENTS.md §1 |
| 15 | Static Analysis & Lint | Ensure `flutter analyze` produces 0 issues | M23.4 | AGENTS.md §2 |
| 16 | Version Bump & Log Update | Bump `pubspec.yaml` to `1.08.0+9`, update `WORK_LOG.md` and `.agents/context.md` | M23.4 | AGENTS.md §4, §6 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M23.1 | Pluggable Tool Architecture & ToolRegistry | `lib/models/tool/*`, `lib/services/tool_registry.dart`, `legacy_tool_adapters.dart`, `toolRegistryProvider`, model/registry unit tests | none | DONE |
| M23.2 | Four Safe Built-in Tools | `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup` in `lib/services/tools/`, basic tools unit tests | M23.1 | DONE |
| M23.3 | AgentLoopGuard & Invocation Guard | `lib/services/agent_loop_guard.dart`, loop/oscillation/duplicate detection, guard unit tests | M23.1 | DONE |
| M23.4 | Agent Pipeline Integration, UI & Final Hardening | `AgentService` integration, `ChatBubble` rendering, E2E tests, version bump to `1.08.0+9`, `WORK_LOG.md`, `context.md`, `flutter analyze` 0 issues, 100% tests pass | M23.1, M23.2, M23.3 | PLANNED |

## Interface Contracts
### Tool ↔ ToolRegistry
```dart
abstract class Tool {
  String get name;
  String get displayName;
  String get description;
  ToolSecurityLevel get securityLevel;
  List<ToolParameter> get parameters;
  Map<String, dynamic> toOpenAiSchema();
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments);
}
```

### AgentLoopGuard ↔ AgentService
```dart
class AgentLoopGuard {
  final int maxToolRounds;
  AgentLoopGuard({this.maxToolRounds = 8});
  void recordToolCall(String toolName, Map<String, dynamic> arguments);
  LoopCheckResult checkNextCall(String toolName, Map<String, dynamic> arguments, int currentRound);
  bool shouldTerminate(int currentRound);
  String getTerminationReason();
}
```
