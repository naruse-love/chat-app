# Model Context Protocol (MCP) & Mobile Native Integration Specification
## Flutter AI Chat Application (`chat-app`)

> **Document Version**: v1.1.0-HARDENED  
> **Status**: Production-Ready Architectural Deliverable (Incorporating Adversarial Security Hardening)  
> **Target Platform**: Flutter (Android / iOS / Desktop)  
> **Scope**: MCP Client Protocol (SSE / WebSocket / Stdio), Dynamic Tool Discovery, McpServerDao Persistence, Mobile Native Android Permissions, Services, and Platform Channel Mocking

---

## 1. Model Context Protocol (MCP) Client Architecture

### 1.1 JSON-RPC 2.0 Compliance
All communication strictly follows the open Model Context Protocol JSON-RPC 2.0 specification:
- **Requests**: `JsonRpcRequest(id, method, params)`
- **Responses**: `JsonRpcResponse(id, result, error)`
- **Notifications**: `JsonRpcNotification(method, params)`

### 1.2 Multi-Transport Implementations

1. **`SseMcpTransport` (Server-Sent Events)**:
   - Connects to remote endpoint via HTTP GET `Accept: text/event-stream`.
   - Receives POST endpoint URI from initial `event: endpoint` message.
   - Sends client commands via HTTP POST; receives streaming responses asynchronously over SSE.
   - Ideal for cloud-hosted MCP servers.

2. **`WebSocketMcpTransport`**:
   - Full-duplex persistent socket (`ws://` / `wss://`).
   - Ping/pong heartbeat frames to monitor latency.
   - Lowest latency for LAN / remote microservices.

3. **`StdioMcpTransport`**:
   - Spawns local CLI subprocesses via `Process.start()` (Desktop / local terminal).
   - Communicates via newline-delimited JSON on stdin/stdout.
   - Tracks child PIDs; automatically terminates subprocess trees on app lifecycle `AppLifecycleState.detached` to prevent zombie processes.

### 1.3 `McpClient` Resilience & Completer Lifecycle (Hardened against RES-04)
- **Per-Request Timeout**: Strict 15s timeout on every pending `Completer<JsonRpcResponse>`.
- **Disconnect Drainer**: On transport disconnect or socket error, immediately flushes and rejects all pending request completers with `McpTransportDisconnectedException()`, preventing chat pipeline hangs.

### 1.4 SQLite Storage: `McpServerDao` (Schema v4 Migration)
```sql
CREATE TABLE mcp_servers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  transportType TEXT NOT NULL, -- 'sse', 'websocket', 'stdio'
  endpointOrCommand TEXT NOT NULL,
  commandArgsJson TEXT,
  headersJson TEXT,
  environmentJson TEXT,
  isEnabled INTEGER NOT NULL DEFAULT 1,
  autoConnect INTEGER NOT NULL DEFAULT 1,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);
```

### 1.5 Dynamic Namespace Routing
- Incoming tool names are namespaced: `mcp__<serverId>__<toolName>`.
- Tool calls from LLM are automatically un-prefixed and routed to the corresponding `McpClient` instance.

---

## 2. Mobile Native Device Capabilities on Android

### 2.1 Abstract Service Interfaces (Hardened against RES-01)
To ensure 100% testability in headless CI environments without real Android devices, all native functionality is defined through pure Dart abstract interfaces:
- `abstract class ICalendarService` (Production: `CalendarNativeService`, Test: `MockCalendarService`)
- `abstract class INotificationService` (Production: `NotificationNativeService`, Test: `MockNotificationService`)
- `abstract class IContactsService` (Production: `ContactsNativeService`, Test: `MockContactsService`)
- `abstract class ILocationService` (Production: `LocationNativeService`, Test: `MockLocationService`)
- `abstract class ICodeExecutionService` (Production: `CodeExecutionService`, Test: `MockCodeExecutionService`)
- `abstract class IFileSystemService` (Production: `FileSystemService`, Test: `MockFileSystemService`)

### 2.2 Android Manifest Declarations
```xml
<!-- Calendar -->
<uses-permission android:name="android.permission.READ_CALENDAR"/>
<uses-permission android:name="android.permission.WRITE_CALENDAR"/>

<!-- Notifications & Alarms -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>

<!-- Contacts -->
<uses-permission android:name="android.permission.READ_CONTACTS"/>

<!-- Location -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

### 2.3 Contacts Privacy & Prompt Injection Sanitizer (Hardened against SEC-03)
- `ContactsSanitizer` enforces:
  1. Field Whitelist: `{ "name": String, "phone_masked": String }` (all notes, addresses, relations stripped).
  2. International E.164 phone masking (`+86 138****5678`, `+1 (***) ***-1234`).
  3. Max 5 results per query; rejects empty queries.
  4. Escapes prompt injection markers (`\n`, `System:`, markdown headers).

---

## 3. Platform Channel Mocking Strategy (`MockNativeChannelHelper`)

To ensure `flutter test` executes with **100% pass rate in headless CI/CD**, `MockNativeChannelHelper` and `TestEnvironmentHelper` mock:
- `flutter.baseflow.com/permissions/methods` (`permission_handler`)
- `flutter.baseflow.com/geolocator` (`geolocator`)
- `dexterous.com/flutter/local_notifications` (`flutter_local_notifications`)
- `plugins.builttoroam.com/device_calendar` (`device_calendar`)
- `github.com/Quis/flutter_contacts` (`flutter_contacts`)
