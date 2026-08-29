# Agent Tools Taxonomy & Inventory Architecture Specification (R1)
## Flutter AI Chat Application (`chat-app`)

> **Document Version**: v1.1.0-HARDENED  
> **Status**: Production-Ready Architectural Deliverable (Incorporating Adversarial Security Hardening)  
> **Target Platform**: Flutter (Android / iOS / Desktop)  
> **Scope**: 4 Capability Dimensions, 23 Specialized Tools, Strict OpenAPI 3.0 / JSON Schema, Multi-tier Security & Error Fallbacks

---

## 1. Executive Taxonomy Matrix

The Agent Tool Ecosystem in `chat-app` spans 4 core capability dimensions, establishing an enterprise-grade autonomous capability matrix:

| # | Tool Name (`snake_case`) | Dimension | Security Level | Primary Dependency & Interface | Max Output Budget | Side Effects |
|---|---|---|---|---|---|---|
| 1 | `math_eval` | Basic Utility | `Safe` | `math_expressions` / `decimal` | 1,000 chars | None |
| 2 | `time_calculator` | Basic Utility | `Safe` | `intl` / `timezone` | 1,200 chars | None |
| 3 | `weather_query` | Basic Utility | `Safe` | `dio` (Open-Meteo / QWeather) | 3,000 chars | Network Read |
| 4 | `wiki_lookup` | Basic Utility | `Safe` | `dio` (Wikipedia REST API) | 4,000 chars | Network Read |
| 5 | `file_read` | Local & Sandbox | `Read-Only` | `IFileSystemService` / `PathSanitizer` | 8,000 chars | Disk Read |
| 6 | `file_write` | Local & Sandbox | `Sensitive-Confirm`| `IFileSystemService` / `PathSanitizer` | 1,500 chars | Disk Write |
| 7 | `file_list` | Local & Sandbox | `Read-Only` | `IFileSystemService` / `PathSanitizer` | 4,000 chars | Disk Read |
| 8 | `file_search` | Local & Sandbox | `Read-Only` | `IFileSystemService` / `PathSanitizer` | 4,000 chars | Disk Read |
| 9 | `code_eval` | Local & Sandbox | `Safe` | `ICodeExecutionService` (Worker Isolate) | 4,000 chars | Sandboxed CPU |
| 10 | `clipboard_read` | Local & Sandbox | `Sensitive-Confirm`| `IClipboardService` | 2,000 chars | Device State Read |
| 11 | `clipboard_write` | Local & Sandbox | `Sensitive-Confirm`| `IClipboardService` | 1,000 chars | Clipboard Mutation |
| 12 | `mcp_discover_tools` | MCP Extensions | `Safe` | `McpClient` (SSE/WebSocket/Stdio) | 4,000 chars | Network Read |
| 13 | `mcp_call_tool` | MCP Extensions | `Sensitive-Confirm`*| `McpClient` (JSON-RPC 2.0) | 8,000 chars | Dynamic Remote |
| 14 | `mcp_read_resource` | MCP Extensions | `Read-Only` | `McpClient` (JSON-RPC 2.0) | 8,000 chars | Remote Resource Read |
| 15 | `mcp_get_prompt` | MCP Extensions | `Safe` | `McpClient` (JSON-RPC 2.0) | 4,000 chars | Template Read |
| 16 | `calendar_query_events`| Mobile Native | `Privileged-Native`| `ICalendarService` / `permission_handler` | 4,000 chars | Calendar Read |
| 17 | `calendar_create_event`| Mobile Native | `Privileged-Native`| `ICalendarService` / `permission_handler` | 1,500 chars | Calendar Mutation |
| 18 | `notification_schedule`| Mobile Native | `Privileged-Native`| `INotificationService` | 1,000 chars | Alarm/Push Mutation |
| 19 | `notification_cancel` | Mobile Native | `Privileged-Native`| `INotificationService` | 800 chars | Notification Dismiss |
| 20 | `alarm_set` | Mobile Native | `Privileged-Native`| `INotificationService` | 1,000 chars | OS Clock Mutation |
| 21 | `contacts_search` | Mobile Native | `Privileged-Native`| `IContactsService` / `ContactsSanitizer` | 3,000 chars | Address Book Read |
| 22 | `geolocation_get` | Mobile Native | `Privileged-Native`| `ILocationService` | 1,500 chars | GPS Location Read |
| 23 | `reverse_geocode` | Mobile Native | `Safe` | `ILocationService` (Nominatim / Geocoder)| 2,000 chars | Geo API Lookup |

---

## 2. Dimension 1: Basic Utility Tools

### 2.1 Tool: `math_eval`
- **Description**: High-precision formula and calculus evaluator.
- **Security Level**: `Safe` (auto-execute).
- **JSON Schema**:
```json
{
  "type": "function",
  "function": {
    "name": "math_eval",
    "description": "Evaluate high-precision mathematical expressions, statistics, calculus, unit conversions, and algebraic equations. Returns exact and decimal approximations.",
    "parameters": {
      "type": "object",
      "properties": {
        "expression": {
          "type": "string",
          "description": "The mathematical expression to evaluate (e.g. '2 * sin(pi / 4) + sqrt(144)', 'mean([12, 15, 23, 42, 56])', 'convert(100, \"km\", \"miles\")')."
        },
        "angle_unit": {
          "type": "string",
          "enum": ["radian", "degree"],
          "default": "radian",
          "description": "Angular unit for trigonometric functions."
        },
        "precision": {
          "type": "integer",
          "minimum": 1,
          "maximum": 50,
          "default": 10,
          "description": "Number of decimal places for floating-point rounding."
        },
        "format": {
          "type": "string",
          "enum": ["decimal", "scientific", "fraction", "engineering"],
          "default": "decimal",
          "description": "Formatting representation of the numerical result."
        }
      },
      "required": ["expression"]
    }
  }
}
```
- **Error & Fallback**: Returns `SYNTAX_ERROR` or `DIVISION_BY_ZERO` with precise token offset; 500ms CPU timeout guard.

---

### 2.2 Tool: `time_calculator`
- **Description**: Timezone conversion, relative time parsing, timestamp diff, and business day calculations.
- **Security Level**: `Safe` (auto-execute).
- **JSON Schema**:
```json
{
  "type": "function",
  "function": {
    "name": "time_calculator",
    "description": "Calculate time, dates, timezone conversions, time differences, and relative dates (e.g. 'next Friday 3pm', business days, countdowns).",
    "parameters": {
      "type": "object",
      "properties": {
        "operation": {
          "type": "string",
          "enum": ["current_time", "convert_timezone", "date_offset", "time_difference", "parse_relative", "business_days"],
          "description": "The specific temporal calculation to execute."
        },
        "base_time": {
          "type": "string",
          "description": "Base ISO8601 string or Unix timestamp. Defaults to current system time if omitted."
        },
        "source_timezone": {
          "type": "string",
          "default": "UTC",
          "description": "IANA timezone name of the source time (e.g. 'UTC', 'Asia/Shanghai', 'America/New_York')."
        },
        "target_timezone": {
          "type": "string",
          "description": "Target IANA timezone name for conversion."
        },
        "offset": {
          "type": "string",
          "description": "Offset duration string (e.g. '+3d', '-5h30m', '+2w', '+1M'). Required for 'date_offset'."
        },
        "end_time": {
          "type": "string",
          "description": "Target timestamp for 'time_difference' or 'business_days' calculation."
        },
        "relative_expression": {
          "type": "string",
          "description": "Natural relative time expression to parse (e.g. 'next Monday at 09:00', 'last day of this month')."
        }
      },
      "required": ["operation"]
    }
  }
}
```

---

### 2.3 Tool: `weather_query`
- **Description**: Real-time conditions, 1-14 day forecast, air quality (AQI), and severe alerts.
- **Security Level**: `Safe` (auto-execute, public open data).
- **JSON Schema**:
```json
{
  "type": "function",
  "function": {
    "name": "weather_query",
    "description": "Query real-time weather conditions, 1-14 day weather forecasts, hourly predictions, air quality (AQI), and severe weather alerts by city name or GPS coordinates.",
    "parameters": {
      "type": "object",
      "properties": {
        "location": {
          "type": "string",
          "description": "City name, district, or landmark (e.g. 'Beijing', 'Shanghai', 'London', 'Tokyo')."
        },
        "latitude": {
          "type": "number",
          "minimum": -90.0,
          "maximum": 90.0,
          "description": "Latitude in decimal degrees."
        },
        "longitude": {
          "type": "number",
          "minimum": -180.0,
          "maximum": 180.0,
          "description": "Longitude in decimal degrees."
        },
        "query_type": {
          "type": "string",
          "enum": ["current", "forecast_daily", "forecast_hourly", "air_quality", "severe_alerts", "all"],
          "default": "all",
          "description": "Type of weather information required."
        },
        "forecast_days": {
          "type": "integer",
          "minimum": 1,
          "maximum": 14,
          "default": 7
        },
        "temperature_unit": {
          "type": "string",
          "enum": ["celsius", "fahrenheit"],
          "default": "celsius"
        }
      }
    }
  }
}
```

---

### 2.4 Tool: `wiki_lookup`
- **Description**: Encyclopedic summary extraction, section retrieval, and disambiguation handling.
- **Security Level**: `Safe` (auto-execute).
- **JSON Schema**:
```json
{
  "type": "function",
  "function": {
    "name": "wiki_lookup",
    "description": "Retrieve factual encyclopedic knowledge, summaries, section content, and disambiguations from Wikipedia across multiple languages.",
    "parameters": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Article title or search topic (e.g. 'Quantum computing', '人工智能')."
        },
        "language": {
          "type": "string",
          "default": "zh",
          "description": "Wikipedia language code ('zh', 'en', 'ja', 'fr', 'de')."
        },
        "mode": {
          "type": "string",
          "enum": ["summary", "section", "search", "full_outline"],
          "default": "summary"
        },
        "section_title": {
          "type": "string",
          "description": "Required when mode is 'section'."
        },
        "max_results": {
          "type": "integer",
          "default": 5
        }
      },
      "required": ["query"]
    }
  }
}
```

---

## 3. Dimension 2: Local Files & Sandboxed Code Execution Tools

### 3.1 Tools: `file_read`, `file_write`, `file_list`, `file_search`
- **Sandbox Root**: Locked strictly to `<AppDocumentsDir>/workspace/`.
- **PathSanitizer Defense (Hardened against SEC-01)**:
  1. Pre-checks: Instant rejection of inputs containing `..`, `%2f`, `%5c`, `\0`, drive letters (`C:`), or leading `/` and `\`.
  2. Symlink Resolution: Resolves canonical path using `File.resolveSymbolicLinksSync()`.
  3. Boundary Verification: Asserts `path.isWithin(canonicalWorkspace, resolvedPath)`.
  4. Quota Enforcement: Hard 50MB workspace quota and 5MB per-file write limit.
- **Schemas**:
  - `file_read` (`Read-Only`): Supports line-range pagination (`start_line`, `end_line`, `encoding`).
  - `file_write` (`Sensitive-Confirm`): Supports `overwrite`, `append`, `patch` (search & replace). Requires interactive UI confirmation.
  - `file_list` (`Read-Only`): Recursive tree traversal with size and modification dates.
  - `file_search` (`Read-Only`): Glob and regex content grep across workspace files.

---

### 3.2 Tool: `code_eval` (Hardened against SEC-02)
- **Description**: Sandboxed JavaScript (ES2020) script execution via an isolated worker isolate.
- **Security Level**: `Safe` (isolated memory).
- **Worker Isolate Architecture (`CodeExecutionService`)**:
  1. **Spawned Background Isolate**: Evaluator executes in a dedicated `Isolate.spawn()`, completely off the main UI thread.
  2. **Forced Preemption**: If execution exceeds 3,000ms, the host immediately executes `workerIsolate.kill(priority: Isolate.immediate)`, terminating infinite loops (`while(true)`) and microtask recursion.
  3. **Stateless Runtime**: QuickJS runtime is initialized with a 32MB heap limit and completely disposed (`jsRuntime.dispose()`) after every run to prevent prototype poisoning.
  4. **Host Channel Stripping**: All host FFI bindings (`fetch`, `XMLHttpRequest`, OS channels) are disabled.
- **JSON Schema**:
```json
{
  "type": "function",
  "function": {
    "name": "code_eval",
    "description": "Execute JavaScript code in a secure, isolated background worker sandbox with strict CPU, memory, and timeout bounds. Zero OS/network access.",
    "parameters": {
      "type": "object",
      "properties": {
        "code": {
          "type": "string",
          "description": "The JavaScript (ES2020) script to evaluate."
        },
        "timeout_ms": {
          "type": "integer",
          "default": 3000,
          "maximum": 5000
        }
      },
      "required": ["code"]
    }
  }
}
```

---

### 3.3 Tool: `clipboard_read` & `clipboard_write`
- `clipboard_read`: `Sensitive-Confirm` (prevents background credential scraping).
- `clipboard_write`: `Sensitive-Confirm` (UI Toast feedback).

---

## 4. Dimension 3: Model Context Protocol (MCP) Dynamic Tools

### 4.1 Tools: `mcp_discover_tools`, `mcp_call_tool`, `mcp_read_resource`, `mcp_get_prompt`
- **Protocol**: JSON-RPC 2.0 over SSE, WebSocket, and Stdio.
- **Dynamic Namespacing**: Tools are namespaced as `mcp__<serverId>__<toolName>` to prevent collision across multiple servers.
- **Resilience (Hardened against RES-04)**:
  - 15s per-request timeout on pending JSON-RPC completers.
  - On transport disconnect, immediately drains all pending requests with `McpTransportDisconnectedException()`.
  - Child subprocess PID tracking with cleanup hooks on `AppLifecycleState.detached`.
- **Security**: Discovered tools default to `Sensitive-Confirm` unless server is marked as trusted in local SQLite config (`McpServerConfig`).

---

## 5. Dimension 4: Mobile Native Device Capability Tools

### 5.1 Tools: `calendar_query_events` & `calendar_create_event`
- **Plugin**: `ICalendarService` (`device_calendar` / `MockCalendarService`).
- **Security**: `Privileged-Native` (Android `READ_CALENDAR` / `WRITE_CALENDAR`). Creating events requires interactive confirmation.

### 5.2 Tools: `notification_schedule`, `notification_cancel`, `alarm_set`
- **Plugin**: `INotificationService` (`flutter_local_notifications` / `MockNotificationService`).
- **Security**: `Privileged-Native` (Android 13+ `POST_NOTIFICATIONS`, Android 12+ `SCHEDULE_EXACT_ALARM`).

### 5.3 Tool: `contacts_search` (Hardened against SEC-03)
- **Plugin**: `IContactsService` (`flutter_contacts` / `MockContactsService`).
- **Privacy & Prompt Injection Defense**:
  1. **Strict Field Whitelist**: Returns ONLY `{"name": String, "phone_masked": String}`. Strips all `notes`, `emails`, `addresses`, `photos`, and `custom_fields`.
  2. **International E.164 Phone Masking**: Retains country code and last 4 digits only (e.g. `+86 138****5678`, `+1 (***) ***-1234`).
  3. **Query Bounds**: Max 5 results per query. Empty query `""` is strictly rejected with `QUERY_TOO_BROAD`.
  4. **Prompt Injection Escaping**: Sanitize contact names against prompt injection characters (`\n`, markdown headers, system tags).

### 5.4 Tools: `geolocation_get` & `reverse_geocode`
- **Plugin**: `ILocationService` (`geolocator` / `MockLocationService`).
- **Security**: `Privileged-Native` (GPS permission prompt).

---

## 6. Token Budget, Truncation & Loop Defense (Hardened against RES-02 & RES-03)

### 6.1 `RuneSafeJsonTruncator` Engine
- **Rune/Characters Boundary Preservation**: Uses `Characters` to prevent splitting multi-byte Unicode/surrogate pairs into invalid UTF-8.
- **JSON-Aware Truncator**: When truncating JSON arrays, omits intermediate items while preserving top-level keys and valid JSON syntax.
- **Payload Budget**: Capped at 15,000 characters (~3,750 tokens) per tool result.

### 6.2 `AgentLoopGuard` & Cycle Detection
- **Default Loop Limit**: Set to `maxToolRounds = 8` (configurable max 15, eliminating 100-round cost explosion).
- **Cycle & Duplicate Detection**: MD5 hash tracking of `toolName + canonicalJson(arguments)`. Aborts with `DUPLICATE_CALL_BLOCKED` if identical call repeats.
- **Strict Summary Phase**: Enforces `isFinalSummaryTurn = true` during degraded final turn, completely disabling tool calls.
