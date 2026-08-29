# E2E Test Infra: Milestone 23 Pluggable Tool Architecture & Built-in Tools

## Test Philosophy
- Opaque-box, requirement-driven, deterministic unit & integration tests.
- High test reliability without external network flakiness (mock HTTP adapters for Open-Meteo & Wikipedia).
- Pure Dart algorithm verification for `math_eval`, `time_calculator`, and `AgentLoopGuard`.
- 100% pass requirement on `flutter test` (173 baseline + 25+ new tests = >=198 tests).
- 0 analyzer warnings / errors on `flutter analyze`.

## Feature Inventory & Test Mapping
| # | Feature | Target Test File | Tier 1 (Coverage) | Tier 2 (Boundary/Error) | Tier 3 (Cross-Feature) | Tier 4 (E2E Scenario) |
|---|---------|------------------|:-----------------:|:-----------------------:|:----------------------:|:---------------------:|
| 1 | Tool Models & Schema | `test/models/tool_model_test.dart` | 5 | 5 | ✓ | ✓ |
| 2 | ToolRegistry Core | `test/services/tool_registry_test.dart` | 5 | 5 | ✓ | ✓ |
| 3 | Legacy Search/Fetch Adapters | `test/services/tool_registry_test.dart` | 4 | 4 | ✓ | ✓ |
| 4 | math_eval Tool | `test/services/basic_tools_test.dart` | 6 | 6 | ✓ | ✓ |
| 5 | time_calculator Tool | `test/services/basic_tools_test.dart` | 5 | 5 | ✓ | ✓ |
| 6 | weather_query Tool | `test/services/basic_tools_test.dart` | 4 | 4 | ✓ | ✓ |
| 7 | wiki_lookup Tool | `test/services/basic_tools_test.dart` | 4 | 4 | ✓ | ✓ |
| 8 | AgentLoopGuard Loop/Oscillation/Duplication | `test/services/agent_loop_guard_test.dart` | 5 | 5 | ✓ | ✓ |
| 9 | AgentService Tool Pipeline Integration | `test/services/agent_service_tool_integration_test.dart` | 4 | 4 | ✓ | ✓ |

## Test Architecture
- Test Runner: `D:\work\flutter-sdk\flutter\bin\flutter.bat test`
- Static Analysis: `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`
- Zero external network dependency: HTTP mock handlers for network-based tools.
- SQLite FFI in-memory testing for persistence compatibility.
