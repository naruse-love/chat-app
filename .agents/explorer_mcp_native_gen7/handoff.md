# Handoff Report — explorer_mcp_native_gen7

## Executive Summary
Completed the comprehensive architectural investigation and technical specification for (1) **Model Context Protocol (MCP) Client Architecture in Flutter/Dart** and (2) **Mobile Native Device Capabilities on Android/Flutter**, together with a complete, structured **Milestones 23–27+ Implementation Roadmap**. All specifications, schemas, DAO models, transport implementations, safety barriers, and test mock strategies have been finalized in `D:\work\chat\.agents\explorer_mcp_native_gen7\report.md`.

---

## 1. Observation

1. **Existing Application Architecture**:
   - `lib/services/agent_service.dart` (lines 91–183, 263–450, 613–800) implements multi-turn tool calling hardcoded for `web_search`, `google_search`, `bing_search`, and `url_fetch`.
   - `lib/data/database_helper.dart` (lines 27–49, 127–139) is currently at SQLite schema `version: 3` with automatic corruption recovery.
   - `pubspec.yaml` (lines 30–61) contains core dependencies (`flutter_riverpod: ^2.5.0`, `dio: ^5.4.0`, `sqflite: ^2.3.0`, `flutter_secure_storage: ^9.0.0`, `uuid: ^4.3.0`).
   - `android/app/src/main/AndroidManifest.xml` (lines 1–50) currently declares only `INTERNET` and `CAMERA` permissions.
   - Test suite across `test/` contains 23 test files (173 test cases), passing 100% cleanly.

2. **Protocol & Transport Requirements**:
   - Standard MCP protocol requires JSON-RPC 2.0 message envelope (`id`, `jsonrpc: "2.0"`, `method`, `params`, `result`, `error`).
   - Remote servers require HTTP GET `/sse` + HTTP POST to dynamic session endpoint.
   - Local and bidirectional servers require WebSocket (`ws://` / `wss://`) and Stdio (`Process.start`) transports.
   - Dynamic tool discovery via MCP `tools/list` requires namespace isolation (`mcp__<serverId>__<toolName>`) to map cleanly to OpenAI Function Calling parameters.

3. **Android Native Capabilities**:
   - Device capabilities require specific plugins: `device_calendar: ^4.3.2`, `flutter_local_notifications: ^17.2.2`, `android_alarm_manager_plus: ^3.0.4`, `flutter_contacts: ^1.1.9+2`, `geolocator: ^12.0.0`, `geocoding: ^3.0.0`, `permission_handler: ^11.3.1`.
   - Android 12+ (API 31) requires `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`.
   - Android 13+ (API 33) requires `POST_NOTIFICATIONS`.

---

## 2. Logic Chain

1. **Observation**: MCP servers expose variable capabilities and tools across distinct network environments (remote SaaS, local daemon, bundled CLI).
   - **Reasoning**: A modular `McpTransport` abstraction with concrete implementations (`SseMcpTransport`, `WebSocketMcpTransport`, `StdioMcpTransport`) cleanly decouples the transport layer from JSON-RPC 2.0 message parsing and `McpClient` lifecycle management.
2. **Observation**: Multiple MCP servers can register tools with identical names (e.g. `read_file` from two servers).
   - **Reasoning**: Prefixing tool names with `mcp__<serverId>__<toolName>` prevents collisions in the LLM's function list and allows O(1) reverse routing when the LLM triggers a tool call.
3. **Observation**: Android 12+ and 13+ enforce granular runtime permissions for notifications, exact alarms, calendar, and contacts.
   - **Reasoning**: Implementing a declarative permission service with pre-request explanation dialogs and fallback to `openAppSettings()` ensures compliance and prevents unexpected app crashes.
4. **Observation**: Automated CI (`flutter test`) runs in headless environments without real Android devices or hardware sensors.
   - **Reasoning**: Defining a centralized `MockNativeChannelHelper` using `TestDefaultBinaryMessengerBinding` intercepts all native plugin method calls, guaranteeing 100% pass rates across unit and widget tests.
5. **Observation**: Tool calling involves mutating user state (creating calendar events, scheduling alarms, writing files).
   - **Reasoning**: Classifying tools into Risk Tiers (Tier 0 to Tier 3) and introducing interactive Human-in-the-Loop confirmation cards protects user privacy and device state integrity.

---

## 3. Caveats

1. **Stdio Subprocess Execution on Mobile**: `StdioMcpTransport` (`Process.start`) is fully supported on Desktop (Windows/macOS/Linux) and Android environments with executable support (Termux, proot, or pre-bundled native binaries). On standard unrooted Android devices without bundled binaries, SSE and WebSocket transports serve as the primary communication channels.
2. **Geocoding Availability**: Android's native `Geocoder` backend depends on Google Play Services; offline devices or AOSP ROMs without Play Services will fallback gracefully to raw GPS coordinate display.
3. **No Direct Code Changes**: In accordance with the Explorer role, no application source files in `lib/` or `test/` were modified directly during this analysis.

---

## 4. Conclusion

The Model Context Protocol (MCP) and Mobile Native Device Capabilities subsystems have been completely designed, specifying:
- Full JSON-RPC 2.0 and MCP protocol lifecycle implementation in Dart.
- SSE, WebSocket, and Stdio transport drivers.
- Dynamic tool discovery, namespace isolation, and SQLite persistence via `McpServerDao`.
- Hardened Android native services for Calendar, Notifications, Contacts, and Geolocation with runtime permission handling.
- A 5-phase roadmap (Milestones 23–27+) with complete quality gates, risk mitigations, and 100% mock test coverage strategies.

Detailed report generated at: `D:\work\chat\.agents\explorer_mcp_native_gen7\report.md`.

---

## 5. Verification Method

To verify the design documents and validate existing project integrity:

```bash
# 1. Inspect architectural report
cat D:\work\chat\.agents\explorer_mcp_native_gen7\report.md

# 2. Run static analysis
D:\work\flutter-sdk\flutter\bin\flutter.bat analyze

# 3. Run full automated test suite
D:\work\flutter-sdk\flutter\bin\flutter.bat test
```
