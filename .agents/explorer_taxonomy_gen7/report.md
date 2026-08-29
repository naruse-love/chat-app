# Flutter AI Chat (chat-app) Agent Tools Taxonomy & Inventory Architecture Specification

> **Document Version**: v1.0.0-PROD  
> **Target Platform**: Flutter (Android / iOS / Desktop)  
> **Status**: Production-Ready Architectural Blueprint  
> **Author**: Tools Taxonomy & Schema Architect  
> **Date**: 2026-08-28  

---

## 1. Executive Summary & Architecture Overview

### 1.1 Architectural Vision
In the evolution of the Flutter AI Chat application (`chat-app`), transitioning from basic text completions with hardcoded search to an autonomous multi-modal agent requires a unified, extensible, and secure **Agent Tools Taxonomy & Inventory**. 

This specification establishes a production-grade catalog of 20+ specialized tools across four fundamental capability dimensions:
1. **Basic Utility Tools**: Deterministic computation, temporal reasoning, meteorological queries, and structured factual knowledge retrieval.
2. **Local Files & Sandboxed Code Execution Tools**: Safe workspace manipulation, sandboxed scripting (JavaScript/Lua/Dart), and clipboard interaction with strict zero-escape guarantees.
3. **Model Context Protocol (MCP) Dynamic Extensions**: Real-time integration with external MCP servers via SSE/WebSocket/Stdio, featuring dynamic tool discovery, bidirectional schema translation, and streaming execution.
4. **Mobile Native Device Capability Tools**: Direct integration with mobile OS primitives (Calendar, Alarms, Notifications, Contacts, Geolocation) guarded by a multi-tier runtime permission and interactive user confirmation system.

```
+-----------------------------------------------------------------------------------+
|                            LLM / Reasoning Engine                                |
|        (OpenAI Function Calling / DSML / Pseudo-XML Fallback Protocols)           |
+-----------------------------------------+-----------------------------------------+
                                          | Tool Calls
                                          v
+-----------------------------------------------------------------------------------+
|                         Agent Tool Execution Engine                               |
|   +-------------------+  +---------------------+  +---------------------------+   |
|   | Schema Validation |->| Security Permission |->| Dispatcher & Orchestration|   |
|   |   & Auto-Repair   |  |   Review & Prompt   |  | (Retry/Timeout/Cancel)    |   |
|   +-------------------+  +---------------------+  +---------------------------+   |
+-----------------------------------------+-----------------------------------------+
                                          |
        +------------------+--------------+----------------+------------------+
        |                  |                               |                  |
        v                  v                               v                  v
+---------------+  +---------------+               +---------------+  +---------------+
| Dimension 1   |  | Dimension 2   |               | Dimension 3   |  | Dimension 4   |
| Basic Utility |  | Local Files & |               | Model Context |  | Mobile Native |
| Tools         |  | Sandbox Eval  |               | Protocol(MCP) |  | Device Tools  |
|               |  |               |               |               |  |               |
| - math_eval   |  | - file_read   |               | - mcp_discover|  | - cal_query   |
| - time_calc   |  | - file_write  |               | - mcp_call    |  | - cal_create  |
| - weather_qry |  | - file_list   |               | - mcp_resource|  | - notif_sched |
| - wiki_lookup |  | - file_search |               | - mcp_prompt  |  | - notif_cancel|
|               |  | - code_eval   |               |               |  | - alarm_set   |
|               |  | - clip_read   |               |               |  | - contacts_qry|
|               |  | - clip_write  |               |               |  | - geoloc_get  |
|               |  |               |               |               |  | - rev_geocode |
+---------------+  +---------------+               +---------------+  +---------------+
```

---

### 1.2 Comprehensive Tool Inventory Matrix

| # | Tool Name (`snake_case`) | Dimension | Security Level | Primary Flutter / Engine Dependency | Max Output Budget | Side Effects |
|---|---|---|---|---|---|---|
| 1 | `math_eval` | Basic Utility | `Safe` | `math_expressions` / `decimal` | 1,000 chars | None |
| 2 | `time_calculator` | Basic Utility | `Safe` | `intl` / `timezone` | 1,200 chars | None |
| 3 | `weather_query` | Basic Utility | `Safe` | `dio` (Open-Meteo / QWeather) | 3,000 chars | Network Read |
| 4 | `wiki_lookup` | Basic Utility | `Safe` | `dio` (Wikipedia REST API) | 4,000 chars | Network Read |
| 5 | `file_read` | Local & Sandbox | `Read-Only` | `path_provider` / `dart:io` | 8,000 chars | Disk Read |
| 6 | `file_write` | Local & Sandbox | `Sensitive-Confirm`| `path_provider` / `dart:io` | 1,500 chars | Disk Write |
| 7 | `file_list` | Local & Sandbox | `Read-Only` | `dart:io` | 4,000 chars | Disk Read |
| 8 | `file_search` | Local & Sandbox | `Read-Only` | `dart:io` | 4,000 chars | Disk Read |
| 9 | `code_eval` | Local & Sandbox | `Safe` | `flutter_js` (QuickJS isolate) | 4,000 chars | Sandboxed CPU |
| 10 | `clipboard_read` | Local & Sandbox | `Sensitive-Confirm`| `flutter/services` | 2,000 chars | Device State Read |
| 11 | `clipboard_write` | Local & Sandbox | `Sensitive-Confirm`| `flutter/services` | 1,000 chars | Clipboard Mutation |
| 12 | `mcp_discover_tools` | MCP Extensions | `Safe` | `mcp_client` (SSE/WebSocket) | 4,000 chars | Network Read |
| 13 | `mcp_call_tool` | MCP Extensions | `Sensitive-Confirm`*| `mcp_client` (JSON-RPC 2.0) | 8,000 chars | Dynamic Remote |
| 14 | `mcp_read_resource` | MCP Extensions | `Read-Only` | `mcp_client` (JSON-RPC 2.0) | 8,000 chars | Remote Resource Read |
| 15 | `mcp_get_prompt` | MCP Extensions | `Safe` | `mcp_client` (JSON-RPC 2.0) | 4,000 chars | Template Read |
| 16 | `calendar_query_events`| Mobile Native | `Privileged-Native`| `device_calendar` / `permission_handler` | 4,000 chars | Calendar Read |
| 17 | `calendar_create_event`| Mobile Native | `Privileged-Native`| `device_calendar` / `permission_handler` | 1,500 chars | Calendar Mutation |
| 18 | `notification_schedule`| Mobile Native | `Privileged-Native`| `flutter_local_notifications` | 1,000 chars | Alarm/Push Mutation |
| 19 | `notification_cancel` | Mobile Native | `Privileged-Native`| `flutter_local_notifications` | 800 chars | Notification Dismiss |
| 20 | `alarm_set` | Mobile Native | `Privileged-Native`| `android_intent_plus` / Platform Channel | 1,000 chars | OS Clock Mutation |
| 21 | `contacts_search` | Mobile Native | `Privileged-Native`| `flutter_contacts` / Privacy Mask | 3,000 chars | Address Book Read |
| 22 | `geolocation_get` | Mobile Native | `Privileged-Native`| `geolocator` | 1,500 chars | GPS Location Read |
| 23 | `reverse_geocode` | Mobile Native | `Safe` | `geocoding` / `dio` (Nominatim) | 2,000 chars | Geo API Lookup |

*\*Note: MCP tools default to `Sensitive-Confirm` unless declared safe in local server configuration.*

---

## 2. Dimension 1: Basic Utility Tools

---

### 2.1 Tool: `math_eval`
#### 2.1.1 Overview & Capabilities
High-precision mathematical expression evaluator supporting:
- Arithmetic: `+`, `-`, `*`, `/`, `^`, `%`, `//` (integer division).
- Trigonometry & Inverse: `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2` (degree & radian modes).
- Logarithmic & Exponential: `log` (base 10), `ln` (natural), `log2`, `exp`, `sqrt`, `cbrt`.
- Statistical & Combinatorics: `mean`, `median`, `variance`, `stddev`, `nCr` (combinations), `nPr` (permutations), `factorial` (`!`).
- Algebraic Solvers & Derivatives: Polynomial roots, first-order symbolic differentiation `d/dx`, definite numerical integrals via Simpson's rule.
- Arbitrary Precision (Big Numbers): Decimal precision up to 100 digits for financial/scientific calculations.
- Unit Conversions: Length (`m`, `km`, `mi`, `ft`), Mass (`kg`, `lb`, `oz`), Temperature (`celsius`, `fahrenheit`, `kelvin`), Data storage (`B`, `KB`, `MB`, `GB`, `TB`).

#### 2.1.2 OpenAI Function Calling JSON Schema
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
          "description": "The mathematical expression to evaluate (e.g. '2 * sin(pi / 4) + sqrt(144)', 'mean([12, 15, 23, 42, 56])', 'derivative(x^3 + 2*x, x, 2)', 'convert(100, \"km\", \"miles\")')."
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

#### 2.1.3 Parameter Specifications & Constraints
- `expression` (String, required): Valid mathematical formula. Must not contain shell characters, system calls, or script blocks. Max length: 500 characters.
- `angle_unit` (String, optional, default: `"radian"`): When `"degree"`, inputs to `sin/cos/tan` are converted from degrees to radians, and results of `asin/acos/atan` are returned in degrees.
- `precision` (Integer, optional, default: 10, range: 1–50): Enforces `Decimal.toStringAsFixed(precision)`.
- `format` (String, optional): Controls output string rendering (`1.234e+5` vs `123400` vs `1234/10`).

#### 2.1.4 Structured Output Format
**JSON Output**:
```json
{
  "status": "success",
  "expression": "2 * sin(pi / 4) + sqrt(144)",
  "raw_result": "13.4142135623730950488",
  "formatted_result": "13.4142135624",
  "result_type": "float",
  "fraction_representation": "335355339/25000000",
  "steps": [
    "pi / 4 = 0.7853981634",
    "sin(0.7853981634) = 0.7071067812",
    "2 * 0.7071067812 = 1.4142135624",
    "sqrt(144) = 12",
    "1.4142135624 + 12 = 13.4142135624"
  ]
}
```

**Markdown Template**:
```markdown
### 🧮 计算结果: `13.4142135624`
- **原始表达式**: `2 * sin(pi / 4) + sqrt(144)`
- **分数近似**: `335355339 / 25000000`
- **计算步骤**:
  1. `sin(π / 4) ≈ 0.7071067812`
  2. `2 * 0.7071067812 ≈ 1.4142135624`
  3. `sqrt(144) = 12`
  4. `1.4142135624 + 12 = 13.4142135624`
```

#### 2.1.5 Security & Permission Classification
- **Classification**: `Safe`
- **Execution Mode**: Auto-execute without user confirmation.
- **Sandboxing**: Runs in pure Dart memory space (`package:math_expressions` & `package:decimal`), zero IO, zero network, zero side effects. CPU evaluation timeout: 500ms.

#### 2.1.6 Error & Fallback Strategies
- **Syntax Errors**: If the parser encounters malformed brackets or syntax (e.g. `2*(3+)`), returns structured error `{ "status": "error", "error_code": "SYNTAX_ERROR", "message": "Unexpected token at position 4. Expected operand." }`.
- **Division by Zero / Domain Errors**: Handled cleanly with `{ "status": "error", "error_code": "DIVISION_BY_ZERO", "message": "Cannot divide by zero or evaluate log of non-positive number." }`.
- **Overflow / Large Matrix Cap**: Max vector/matrix size capped at 10,000 elements to prevent OOM.

---

### 2.2 Tool: `time_calculator`
#### 2.2.1 Overview & Capabilities
Comprehensive temporal reasoning and calendar computation engine:
- Current Time & Timezones: Resolve exact current time in UTC, device local timezone, or any IANA timezone (e.g. `Asia/Shanghai`, `America/New_York`, `Europe/London`).
- Relative Date Resolution: Parse natural relative phrases like `"next Monday"`, `"in 3 business days"`, `"first Friday of next month"`, `"2 weeks ago"`.
- Difference & Duration: Compute exact elapsed time, working days, calendar days, hours, minutes between two timestamps.
- Timestamp & ISO8601 Conversions: Unix epoch milliseconds/seconds to RFC3339 / ISO8601 strings and vice-versa.
- Recurring Calendar Schedules: Compute next N occurrences of a cron expression or recurrence rule.

#### 2.2.2 OpenAI Function Calling JSON Schema
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

#### 2.2.3 Parameter Specifications & Constraints
- `operation` (String, required): Operation type selector.
- `base_time` (String, optional): ISO8601 (`2026-08-28T20:40:00+08:00`) or Unix epoch timestamp (`1787920800`).
- `source_timezone` / `target_timezone` (String): Must match standard IANA timezone database entries or UTC offsets (`+08:00`, `EST`, `CST`).
- `offset` (String): Formatted as `[+-]\d+[yMwdhms]` (e.g. `+2w3d`).

#### 2.2.4 Structured Output Format
**JSON Output**:
```json
{
  "status": "success",
  "operation": "convert_timezone",
  "source_time": "2026-08-28T20:40:23+08:00",
  "source_timezone": "Asia/Shanghai",
  "target_time": "2026-08-28T08:40:23-04:00",
  "target_timezone": "America/New_York",
  "utc_timestamp": "2026-08-28T12:40:23.000Z",
  "epoch_seconds": 1787920823,
  "day_of_week": "Friday",
  "is_dst": true,
  "human_readable": "2026年8月28日 星期五 08:40:23 (EDT, UTC-4)"
}
```

**Markdown Template**:
```markdown
### ⏰ 时区转换结果
- **源时区 (Asia/Shanghai)**: `2026-08-28 20:40:23 (CST, UTC+8)`
- **目标时区 (America/New_York)**: `2026-08-28 08:40:23 (EDT, UTC-4)`
- **时差**: 慢 12 个小时 (夏令时生效中)
- **Unix 时间戳**: `1787920823`
```

#### 2.2.5 Security & Permission Classification
- **Classification**: `Safe`
- **Execution Mode**: Auto-execute. Zero OS side effects. Local `timezone` / `intl` library execution.

#### 2.2.6 Error & Fallback Strategies
- **Invalid Timezone String**: If timezone is unrecognized (e.g. `"Beijing"` instead of `"Asia/Shanghai"`), engine uses a fuzzy alias dictionary to automatically map common names (`Beijing` -> `Asia/Shanghai`, `NY` -> `America/New_York`). If unresolvable, returns list of valid candidates.
- **Leap Year & Month Boundary**: Correctly handles February 29th and daylight saving transitions (DST spring-forward / fall-back jumps).

---

### 2.3 Tool: `weather_query`
#### 2.3.1 Overview & Capabilities
Global real-time and forecast weather query engine:
- Current Conditions: Temperature, apparent temperature, relative humidity, wind speed & direction, precipitation, UV index, atmospheric pressure, cloud cover.
- Multi-Day Forecast: Up to 14 days daily high/low, precipitation probability, weather codes (WMO standard).
- Hourly Forecast: Hourly breakdown for next 24 to 72 hours.
- Air Quality Index (AQI): PM2.5, PM10, O3, NO2, SO2, CO, US-AQI / European AQI.
- Severe Weather Alerts: Storm, typhoon, heatwave, blizzard, flood government alerts.
- Location Resolution: Support both city/district names (e.g. `"Beijing"`, `"San Francisco"`, `"Tokyo"`) and exact coordinates (`latitude`, `longitude`).

#### 2.3.2 OpenAI Function Calling JSON Schema
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
          "description": "City name, district, or landmark (e.g. 'Beijing', 'Shanghai', 'London', 'Tokyo', 'Haidian, Beijing')."
        },
        "latitude": {
          "type": "number",
          "minimum": -90.0,
          "maximum": 90.0,
          "description": "Latitude in decimal degrees (e.g. 39.9042)."
        },
        "longitude": {
          "type": "number",
          "minimum": -180.0,
          "maximum": 180.0,
          "description": "Longitude in decimal degrees (e.g. 116.4074)."
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
          "default": 7,
          "description": "Number of days for daily forecast (1-14)."
        },
        "temperature_unit": {
          "type": "string",
          "enum": ["celsius", "fahrenheit"],
          "default": "celsius",
          "description": "Temperature measurement unit."
        }
      },
      "required": []
    }
  }
}
```

#### 2.3.3 Parameter Specifications & Constraints
- Either `location` OR (`latitude` AND `longitude`) MUST be supplied. If both are omitted, tool attempts to read current cached location or errors.
- `location` (String): Geocoded via Open-Meteo Geocoding API / Nominatim / QWeather lookup.
- `forecast_days` (Integer, 1–14, default 7).

#### 2.3.4 Structured Output Format
**JSON Output**:
```json
{
  "status": "success",
  "location": {
    "name": "Beijing",
    "country": "China",
    "admin1": "Beijing",
    "latitude": 39.9042,
    "longitude": 116.4074,
    "timezone": "Asia/Shanghai"
  },
  "current": {
    "temperature": 28.4,
    "apparent_temperature": 30.1,
    "unit": "°C",
    "humidity": 62,
    "weather_code": 1,
    "weather_condition": "晴间多云 (Partly Cloudy)",
    "wind_speed": 12.6,
    "wind_direction": "SE",
    "uv_index": 6.2,
    "precipitation": 0.0
  },
  "air_quality": {
    "aqi": 42,
    "category": "优 (Good)",
    "pm2_5": 11.2,
    "pm10": 24.5,
    "dominant_pollutant": "PM10"
  },
  "daily_forecast": [
    {
      "date": "2026-08-28",
      "temp_max": 31.0,
      "temp_min": 21.0,
      "condition": "晴 (Clear)",
      "precipitation_probability": 10
    },
    {
      "date": "2026-08-29",
      "temp_max": 29.5,
      "temp_min": 22.0,
      "condition": "雷阵雨 (Thunderstorm)",
      "precipitation_probability": 75
    }
  ],
  "alerts": []
}
```

**Markdown Template**:
```markdown
### 🌤️ 北京 (Beijing) 实时天气与预报
- **当前温度**: `28.4°C` (体感 `30.1°C`) | **天气**: 晴间多云
- **空气质量**: `42` (优，PM2.5: 11.2 μg/m³) | **湿度**: `62%` | **紫外线**: `6.2` (中等)
- **未来 7 天天气概览**:
| 日期 | 天气状况 | 最高/最低气温 | 降水概率 |
|---|---|---|---|
| 08-28 (今天) | ☀️ 晴 | 31°C / 21°C | 10% |
| 08-29 (明天) | ⛈️ 雷阵雨 | 29.5°C / 22°C | 75% |
| 08-30 (后天) | ⛅ 多云 | 28°C / 20°C | 20% |
```

#### 2.3.5 Security & Permission Classification
- **Classification**: `Safe`
- **Execution Mode**: Auto-execute. Pure HTTP network query to public Open-Meteo / QWeather endpoints with zero API keys required for public tier.

#### 2.3.6 Error & Fallback Strategies
- **Primary Backend**: Open-Meteo REST API (`https://api.open-meteo.com/v1/forecast`, no API key required, 10,000 req/day free, open data).
- **Secondary Backend**: QWeather (和风天气) / WeatherAPI fallback if Open-Meteo is unreachable.
- **Geocoding Ambiguity**: If query is ambiguous (e.g. `"Springfield"` which exists in 30 US states), the tool picks the highest-population match and includes a disambiguation note with alternative coordinates.
- **Offline / Network Timeout**: 5-second HTTP timeout with cached response degradation (TTL: 30 minutes).

---

### 2.4 Tool: `wiki_lookup` / `knowledge_retrieval`
#### 2.4.1 Overview & Capabilities
Structured encyclopedic and factual knowledge retrieval engine:
- Summary Extraction: Retrieves verified introductory extract, infobox data, and thumbnail image URL.
- Section-Specific Retrieval: Allows extracting specific subsections of long articles (e.g. `"History"`, `"Architecture"`, `"Controversy"`).
- Full Text & Keyword Search: Searches article titles and snippets across Wikipedia databases.
- Disambiguation Handling: Detects disambiguation pages and returns structured alternative topic choices.
- Multi-Language Support: Supports `zh`, `en`, `ja`, `de`, `fr`, `es`, etc.

#### 2.4.2 OpenAI Function Calling JSON Schema
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
          "description": "Article title or search topic (e.g. 'Quantum computing', '人工智能', 'Albert Einstein')."
        },
        "language": {
          "type": "string",
          "default": "zh",
          "description": "Wikipedia language edition code (e.g. 'zh', 'en', 'ja', 'fr', 'de')."
        },
        "mode": {
          "type": "string",
          "enum": ["summary", "section", "search", "full_outline"],
          "default": "summary",
          "description": "Retrieval mode: 'summary' for lead paragraph, 'section' for specific heading, 'search' for matching titles, 'full_outline' for table of contents."
        },
        "section_title": {
          "type": "string",
          "description": "Required when mode is 'section'. Title or index of the section to retrieve."
        },
        "max_results": {
          "type": "integer",
          "minimum": 1,
          "maximum": 10,
          "default": 5,
          "description": "Number of search results when mode is 'search'."
        }
      },
      "required": ["query"]
    }
  }
}
```

#### 2.4.3 Parameter Specifications & Constraints
- `query` (String, required): Max 200 chars. Strips special control characters.
- `language` (String, optional, default `"zh"`): ISO 639-1 language code.
- `mode` (String, optional, default `"summary"`).

#### 2.4.4 Structured Output Format
**JSON Output**:
```json
{
  "status": "success",
  "title": "Quantum computing",
  "page_id": 24523,
  "language": "en",
  "url": "https://en.wikipedia.org/wiki/Quantum_computing",
  "is_disambiguation": false,
  "summary": "Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics to solve problems too complex for classical computers...",
  "infobox": {
    "Field": "Computer science, Quantum physics",
    "First proposed": "Richard Feynman (1981), Paul Benioff (1980)"
  },
  "sections": ["History", "Principles", "Qubits", "Quantum algorithms", "Physical implementations"]
}
```

**Markdown Template**:
```markdown
### 📖 维基百科: [Quantum computing](https://en.wikipedia.org/wiki/Quantum_computing)
> **摘要**: Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics to solve problems too complex for classical computers...

- **核心字段**:
  - **研究领域**: 计算机科学、量子物理学
  - **首提学者**: Richard Feynman (1981)
- **文章目录结构**: `History` | `Principles` | `Qubits` | `Quantum algorithms` | `Physical implementations`
```

#### 2.4.5 Security & Permission Classification
- **Classification**: `Safe`
- **Execution Mode**: Auto-execute. Direct HTTPS calls to `https://{lang}.wikipedia.org/api/rest_v1/page/summary/{title}` and `action=query` API.

#### 2.4.6 Error & Fallback Strategies
- **Disambiguation Page Detected**: If `type == "disambiguation"`, the tool returns `{ "status": "disambiguation", "candidates": [...] }`, allowing the LLM to choose the exact topic or ask the user.
- **Article Not Found (404)**: Automatically triggers `mode: "search"` fallback to find close spelling variants and returns top 3 suggestions.
- **Content Truncation**: Extracts capped at 3,500 characters to protect LLM context window.

---

## 3. Dimension 2: Local Files & Sandboxed Code Execution Tools

---

### 3.1 Tool: `file_read`
#### 3.1.1 Overview & Capabilities
Strictly sandboxed file reading engine within the app workspace directory (`/data/user/0/.../app_flutter/workspace/` on Android, `Documents/workspace/` on iOS/Desktop):
- Path Traversal Guard: Sanitizes and rejects any path containing `../`, `..\\`, absolute root escapes (`/etc/`, `C:\Windows\`), or symbolic links pointing outside the sandbox.
- Pagination & Byte Slicing: Supports reading large files by line ranges (`start_line`, `end_line`) or byte chunks (`byte_offset`, `byte_limit`) to avoid token overflow.
- Encoding Detection: Supports UTF-8 plain text, JSON, Markdown, YAML, CSV, and Base64 encoding for binary inspection.

#### 3.1.2 OpenAI Function Calling JSON Schema
```json
{
  "type": "function",
  "function": {
    "name": "file_read",
    "description": "Read contents of a file within the secure app workspace directory. Supports line-range pagination and encoding selection. Path traversal outside sandbox is strictly blocked.",
    "parameters": {
      "type": "object",
      "properties": {
        "file_path": {
          "type": "string",
          "description": "Relative file path inside the workspace (e.g. 'notes/todo.txt', 'data/sales.json', 'scripts/main.js')."
        },
        "start_line": {
          "type": "integer",
          "minimum": 1,
          "description": "1-based starting line number to read (for pagination)."
        },
        "end_line": {
          "type": "integer",
          "minimum": 1,
          "description": "1-based ending line number to read (inclusive)."
        },
        "encoding": {
          "type": "string",
          "enum": ["utf-8", "base64"],
          "default": "utf-8",
          "description": "File decoding format."
        },
        "max_bytes": {
          "type": "integer",
          "minimum": 100,
          "maximum": 500000,
          "default": 32768,
          "description": "Maximum bytes to read in one call."
        }
      },
      "required": ["file_path"]
    }
  }
}
```

#### 3.1.3 Parameter Specifications & Constraints
- `file_path` (String, required): Normalized via `path.normalize(file_path)`. If normalized path starts with `/` or contains `..`, path resolver throws `SecurityException: Path traversal detected`.
- Sandbox Root: strictly locked to `<AppDocumentsDir>/workspace/`.
- File Size Guard: Files > 5MB are refused for full read; caller must supply `start_line`/`end_line` or `max_bytes`.

#### 3.1.4 Structured Output Format
**JSON Output**:
```json
{
  "status": "success",
  "file_path": "notes/todo.txt",
  "file_size_bytes": 1024,
  "total_lines": 35,
  "start_line": 1,
  "end_line": 35,
  "is_truncated": false,
  "content": "1. Review Milestone 23 Architecture\n2. Verify JSON Schema compliance\n3. Run Flutter analyzer tests"
}
```

**Markdown Template**:
```markdown
### 📄 文件读取: `notes/todo.txt` (共 35 行, 1.0 KB)
```text
1. Review Milestone 23 Architecture
2. Verify JSON Schema compliance
3. Run Flutter analyzer tests
```
```

#### 3.1.5 Security & Permission Classification
- **Classification**: `Read-Only`
- **Execution Mode**: Auto-execute within the workspace boundary. No side effects. Blocked from accessing app private database (`chat_database.db`) or secure storage (`flutter_secure_storage`).

#### 3.1.6 Error & Fallback Strategies
- **Path Traversal Escape**: Immediate abort with `{ "status": "permission_denied", "error": "SECURITY_VIOLATION: Access outside sandbox directory is forbidden." }`.
- **File Not Found**: Suggests available files in directory via `{ "status": "error", "error_code": "FILE_NOT_FOUND", "similar_files": [...] }`.

---

### 3.2 Tool: `file_write`
#### 3.2.1 Overview & Capabilities
Sandboxed file modification and creation engine:
- Modes: `overwrite` (full rewrite), `append` (add to tail), `patch` (search & replace targeted substring/chunk).
- Atomic Transactions: Writes to `<filename>.tmp` first, flushes to disk, and renames atomically to prevent file corruption upon sudden power loss or app background kill.
- Directory Auto-Creation: Recursively creates intermediate folders if they do not exist.
- Quota Management: Enforces a workspace storage quota (e.g. max 50MB total workspace size, max 2MB per file).

#### 3.2.2 OpenAI Function Calling JSON Schema
```json
{
  "type": "function",
  "function": {
    "name": "file_write",
    "description": "Create, overwrite, append, or patch files inside the secure app workspace directory. Requires interactive user confirmation.",
    "parameters": {
      "type": "object",
      "properties": {
        "file_path": {
          "type": "string",
          "description": "Relative file path inside the workspace directory (e.g. 'reports/summary.md', 'code/utils.dart')."
        },
        "content": {
          "type": "string",
          "description": "The text content to write or append."
        },
        "mode": {
          "type": "string",
          "enum": ["overwrite", "append", "patch"],
          "default": "overwrite",
          "description": "Write mode: 'overwrite' replaces file, 'append' appends to end, 'patch' replaces targeted block."
        },
        "target_content": {
          "type": "string",
          "description": "Required when mode is 'patch'. The exact contiguous string to find and replace."
        },
        "create_directories": {
          "type": "boolean",
          "default": true,
          "description": "Automatically create parent directories if missing."
        }
      },
      "required": ["file_path", "content"]
    }
  }
}
```

#### 3.2.3 Parameter Specifications & Constraints
- `file_path` (String, required): Workspace relative path.
- `content` (String, required): Max length per call: 200,000 characters.
- `mode` (String, default `"overwrite"`).

#### 3.2.4 Structured Output Format
**JSON Output**:
```json
{
  "status": "success",
  "file_path": "reports/summary.md",
  "mode": "overwrite",
  "bytes_written": 2480,
  "total_file_size": 2480,
  "checksum_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

**Markdown Template**:
```markdown
### ✍️ 文件写入成功: `reports/summary.md`
- **操作模式**: `overwrite` (覆盖写入)
- **写入字节**: `2.48 KB`
- **SHA-256 校验码**: `e3b0c44298fc...`
```

#### 3.2.5 Security & Permission Classification
- **Classification**: `Sensitive-Confirm`
- **Execution Mode**: **Requires Explicit Interactive User Confirmation**.
- **UI Confirmation Card**: Displays Diff / Preview card:
  - Header: `"AI 正在请求写入文件: reports/summary.md"`
  - Body: Shows side-by-side or unified Diff of changes, file size impact.
  - Buttons: `[拒绝 (Reject)]` and `[允许写入 (Confirm)]`.

#### 3.2.6 Error & Fallback Strategies
- **User Rejection**: If user taps "Reject", returns `{ "status": "user_cancelled", "message": "User rejected the file write request." }`.
- **Patch Target Not Found**: In `patch` mode, if `target_content` does not match, returns detailed error with context line numbers without modifying the file.

---

### 3.3 Tool: `file_list` & `file_search`
#### 3.3.1 Overview & Capabilities
- `file_list`: Recursive or shallow directory tree traversal with metadata (size, modified time, extension, file vs directory flag).
- `file_search`: Fast regex and glob pattern search across workspace filenames and file contents (similar to grep/find).

#### 3.3.2 OpenAI Function Calling JSON Schema (`file_list` & `file_search`)
```json
{
  "type": "function",
  "function": {
    "name": "file_list",
    "description": "List files and folders within the app workspace with size, modified dates, and directory tree structure.",
    "parameters": {
      "type": "object",
      "properties": {
        "directory_path": {
          "type": "string",
          "default": "",
          "description": "Relative directory path (empty string for workspace root)."
        },
        "recursive": {
          "type": "boolean",
          "default": false,
          "description": "Whether to list subdirectories recursively."
        },
        "max_depth": {
          "type": "integer",
          "minimum": 1,
          "maximum": 10,
          "default": 3,
          "description": "Maximum recursive traversal depth."
        },
        "extension_filter": {
          "type": "array",
          "items": { "type": "string" },
          "description": "List of file extensions to include (e.g. ['md', 'txt', 'json'])."
        }
      }
    }
  }
}
```

```json
{
  "type": "function",
  "function": {
    "name": "file_search",
    "description": "Search for files by filename pattern (glob) or text content (regex/grep) inside the workspace.",
    "parameters": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Text pattern or regex to search for."
        },
        "search_type": {
          "type": "string",
          "enum": ["filename_glob", "content_grep", "both"],
          "default": "both",
          "description": "Search target mode."
        },
        "case_sensitive": {
          "type": "boolean",
          "default": false,
          "description": "Whether search is case-sensitive."
        },
        "max_results": {
          "type": "integer",
          "minimum": 1,
          "maximum": 50,
          "default": 20,
          "description": "Maximum number of search results to return."
        }
      },
      "required": ["query"]
    }
  }
}
```

#### 3.3.3 Security & Fallback
- **Classification**: `Read-Only` (Auto-execute, sandboxed).
- Output capped at 4,000 characters; excess results summarized with counts.

---

### 3.4 Tool: `code_eval`
#### 3.4.1 Overview & Capabilities
Sandboxed script interpreter for dynamic algorithmic execution:
- Supported Engine: Embedded QuickJS via `flutter_js` (or pure Dart headless isolate evaluator).
- Supported Languages: JavaScript (ES2020), Lua 5.4, or Python-subset.
- Safe Sandbox Constraints:
  - **No Network Access**: `fetch`, `XMLHttpRequest`, `WebSocket` disabled.
  - **No Filesystem Access**: `fs`, `require`, `import` disabled.
  - **No OS / FFI Bridge**: Platform channels and C-pointers inaccessible.
  - **CPU Execution Timeout**: Hard cap at 3000ms. If execution exceeds 3 seconds, isolate is terminated.
  - **Memory Cap**: 32MB max heap.
  - **Infinite Loop Guard**: Instruction count limit (max 10,000,000 bytecode ops).
  - Standard IO capture: Redirects `console.log`, `console.error`, and captures return value.

#### 3.4.2 OpenAI Function Calling JSON Schema
```json
{
  "type": "function",
  "function": {
    "name": "code_eval",
    "description": "Execute JavaScript code in a secure, isolated sandbox with strict CPU, memory, and timeout bounds. Zero OS/network access.",
    "parameters": {
      "type": "object",
      "properties": {
        "code": {
          "type": "string",
          "description": "The JavaScript (ES2020) script to evaluate (e.g. 'function fib(n){return n<=1?n:fib(n-1)+fib(n-2)}; fib(20);')."
        },
        "timeout_ms": {
          "type": "integer",
          "minimum": 100,
          "maximum": 5000,
          "default": 3000,
          "description": "Maximum execution time in milliseconds before forced termination."
        }
      },
      "required": ["code"]
    }
  }
}
```

#### 3.4.3 Structured Output Format
**JSON Output**:
```json
{
  "status": "success",
  "return_value": 6765,
  "value_type": "number",
  "stdout": ["Calculating Fibonacci(20)...", "Completed in 4ms"],
  "stderr": [],
  "execution_time_ms": 4,
  "memory_used_kb": 320
}
```

**Markdown Template**:
```markdown
### ⚡ 代码执行结果 (耗时: 4ms)
- **返回值**: `6765` (`number`)
- **标准输出 (stdout)**:
```text
Calculating Fibonacci(20)...
Completed in 4ms
```
```

#### 3.4.4 Security & Fallback
- **Classification**: `Safe` (auto-execute in memory isolate).
- **Infinite Loop / Timeout**: If script hangs (e.g. `while(true){}`), isolate is killed after `timeout_ms` and returns `{ "status": "timeout", "error": "EXECUTION_TIMEOUT: Code execution exceeded 3000ms limit." }`.

---

### 3.5 Tool: `clipboard_read` & `clipboard_write`
#### 3.5.1 Overview & Capabilities
- `clipboard_read`: Reads text from system clipboard, checking for clipboard change timestamps and notifying user.
- `clipboard_write`: Writes formatted text/code to system clipboard with a SnackBar notification.

#### 3.5.2 OpenAI Function Calling JSON Schema
```json
{
  "type": "function",
  "function": {
    "name": "clipboard_read",
    "description": "Read the current text content from the system clipboard. Requires interactive user confirmation for privacy.",
    "parameters": {
      "type": "object",
      "properties": {}
    }
  }
}
```

```json
{
  "type": "function",
  "function": {
    "name": "clipboard_write",
    "description": "Copy specified text or code snippet to the system clipboard.",
    "parameters": {
      "type": "object",
      "properties": {
        "text": {
          "type": "string",
          "description": "The string content to copy to clipboard."
        },
        "label": {
          "type": "string",
          "description": "Optional human-readable label or description for the copied content."
        }
      },
      "required": ["text"]
    }
  }
}
```

#### 3.5.3 Security Classification
- `clipboard_read`: `Sensitive-Confirm` (prevents malicious background scraping of user password/bank data).
- `clipboard_write`: `Sensitive-Confirm` (user confirmation toast/dialog).

---

## 4. Dimension 3: Model Context Protocol (MCP) Dynamic Extensions

---

### 4.1 MCP Architecture Overview & Flutter Integration
The **Model Context Protocol (MCP)**, authored by Anthropic, provides an open standard for LLMs to dynamically discover and invoke external tools, resources, and prompt templates over standardized transports.

In this architecture, `chat-app` acts as an **MCP Client**, connecting to:
1. **Remote MCP Servers**: Over Server-Sent Events (`SSE`) with HTTP POST, or bidirectional `WebSocket`.
2. **Local MCP Servers**: (On Desktop / Local Host) via `Stdio` subprocess pipes.

```
+-----------------------------------------------------------------------------------+
|                                MCP Client Engine                                  |
|  +---------------------+  +----------------------+  +-------------------------+   |
|  | Server Registry &   |  | Protocol Negotiator  |  | JSON-RPC 2.0 Transport  |   |
|  | Config (SQLite DAO) |  | (Capabilities/Version|  | (SSE / WebSocket/Stdio) |   |
|  +---------------------+  +----------------------+  +-------------------------+   |
+-----------------------------------------+-----------------------------------------+
                                          |
        +---------------------------------+---------------------------------+
        |                                 |                                 |
        v                                 v                                 v
+------------------+             +------------------+              +------------------+
| MCP Server (SSE) |             | MCP Server (WS)  |              | MCP Server(Stdio)|
| e.g. Remote CRM  |             | e.g. PostgreSQL  |              | e.g. Local Git   |
| https://mcp...   |             | wss://mcp...     |              | /usr/bin/mcp-git |
+------------------+             +------------------+              +------------------+
```

---

### 4.2 Dynamic Schema Mapping (MCP -> OpenAI Function Calling)
The MCP specification defines tools with JSON Schema parameters. The `McpSchemaMapper` dynamically translates MCP tool definitions into OpenAI Function Calling format:

```dart
Map<String, dynamic> mapMcpToolToOpenAi(McpTool mcpTool, String serverId) {
  // Namespace tool name to prevent collisions: mcp_{serverId}_{toolName}
  final namespacedName = 'mcp_${serverId}_${mcpTool.name}';
  return {
    'type': 'function',
    'function': {
      'name': namespacedName,
      'description': '[MCP Server: $serverId] ${mcpTool.description ?? ""}',
      'parameters': mcpTool.inputSchema ?? {
        'type': 'object',
        'properties': {},
      },
    },
  };
}
```

---

### 4.3 MCP Protocol Tools Specification

#### 4.3.1 Tool: `mcp_discover_tools`
```json
{
  "type": "function",
  "function": {
    "name": "mcp_discover_tools",
    "description": "Query connected MCP servers for available dynamic tools, their schemas, and server capabilities.",
    "parameters": {
      "type": "object",
      "properties": {
        "server_id": {
          "type": "string",
          "description": "Optional specific server ID to query. If omitted, queries all active MCP servers."
        }
      }
    }
  }
}
```

#### 4.3.2 Tool: `mcp_call_tool`
```json
{
  "type": "function",
  "function": {
    "name": "mcp_call_tool",
    "description": "Invoke a dynamic tool on a connected MCP server with structured arguments.",
    "parameters": {
      "type": "object",
      "properties": {
        "server_id": {
          "type": "string",
          "description": "The unique identifier of the target MCP server."
        },
        "tool_name": {
          "type": "string",
          "description": "The raw name of the tool as defined on the MCP server."
        },
        "arguments": {
          "type": "object",
          "description": "Arbitrary key-value JSON parameters required by the MCP tool."
        }
      },
      "required": ["server_id", "tool_name", "arguments"]
    }
  }
}
```

#### 4.3.3 Tool: `mcp_read_resource` & `mcp_get_prompt`
```json
{
  "type": "function",
  "function": {
    "name": "mcp_read_resource",
    "description": "Read content of an MCP resource via its URI scheme (e.g. 'postgres://schema/users', 'file:///docs/readme.md').",
    "parameters": {
      "type": "object",
      "properties": {
        "server_id": { "type": "string", "description": "Target MCP server ID." },
        "uri": { "type": "string", "description": "Resource URI identifier." }
      },
      "required": ["server_id", "uri"]
    }
  }
}
```

```json
{
  "type": "function",
  "function": {
    "name": "mcp_get_prompt",
    "description": "Retrieve a pre-configured prompt template from an MCP server with variable substitutions.",
    "parameters": {
      "type": "object",
      "properties": {
        "server_id": { "type": "string", "description": "Target MCP server ID." },
        "prompt_name": { "type": "string", "description": "Name of the prompt template." },
        "arguments": { "type": "object", "description": "Template variables to fill." }
      },
      "required": ["server_id", "prompt_name"]
    }
  }
}
```

#### 4.3.4 Security & Degradation
- Dynamic tools discovered via MCP default to `Sensitive-Confirm` unless server is marked as trusted in user settings.
- If MCP server drops connection during execution, timeout is enforced at 10 seconds with automatic reconnection backoff.

---

## 5. Dimension 4: Mobile Native Device Capability Tools

---

### 5.1 Tool: `calendar_query_events` & `calendar_create_event`
#### 5.1.1 Overview & Capabilities
- `calendar_query_events`: Queries system calendar across given time intervals with keyword filtering and attendee status.
- `calendar_create_event`: Creates new calendar events with start/end time, all-day flag, location, reminder notifications (e.g. 15 minutes before), and RFC5545 recurrence rules (RRULE).

#### 5.1.2 OpenAI Function Calling JSON Schema (`calendar_query_events` & `calendar_create_event`)
```json
{
  "type": "function",
  "function": {
    "name": "calendar_query_events",
    "description": "Search and query upcoming or past events in the device system calendar.",
    "parameters": {
      "type": "object",
      "properties": {
        "start_time": {
          "type": "string",
          "description": "ISO8601 string for beginning of search range (e.g. '2026-08-28T00:00:00Z')."
        },
        "end_time": {
          "type": "string",
          "description": "ISO8601 string for end of search range."
        },
        "query": {
          "type": "string",
          "description": "Optional keyword to search in event title, description, or location."
        },
        "max_results": {
          "type": "integer",
          "minimum": 1,
          "maximum": 50,
          "default": 20
        }
      },
      "required": ["start_time", "end_time"]
    }
  }
}
```

```json
{
  "type": "function",
  "function": {
    "name": "calendar_create_event",
    "description": "Schedule and add a new event to the device system calendar. Requires interactive user confirmation.",
    "parameters": {
      "type": "object",
      "properties": {
        "title": {
          "type": "string",
          "description": "Event title or summary (e.g. 'Project Review Meeting')."
        },
        "start_time": {
          "type": "string",
          "description": "ISO8601 start time (e.g. '2026-08-29T14:30:00+08:00')."
        },
        "end_time": {
          "type": "string",
          "description": "ISO8601 end time (e.g. '2026-08-29T15:30:00+08:00')."
        },
        "description": {
          "type": "string",
          "description": "Detailed event description or notes."
        },
        "location": {
          "type": "string",
          "description": "Event location (physical address or meeting link URL)."
        },
        "all_day": {
          "type": "boolean",
          "default": false,
          "description": "Whether this is an all-day event."
        },
        "reminders_minutes_before": {
          "type": "array",
          "items": { "type": "integer" },
          "default": [15],
          "description": "Reminder alarms in minutes before start time (e.g. [15, 60])."
        },
        "recurrence_rule": {
          "type": "string",
          "description": "RFC5545 RRULE string for recurring events (e.g. 'FREQ=WEEKLY;BYDAY=MO,WE')."
        }
      },
      "required": ["title", "start_time", "end_time"]
    }
  }
}
```

#### 5.1.3 Structured Output & UI Confirmation
**Confirmation Card**:
```
+-------------------------------------------------------+
| 📅 日历事件创建确认                                    |
+-------------------------------------------------------+
| 标题:   项目评审会议 (Project Review Meeting)         |
| 时间:   2026-08-29 14:30 - 15:30 (CST)                |
| 地点:   会议室 A (或 Zoom 链接)                       |
| 提醒:   提前 15 分钟                                  |
+-------------------------------------------------------+
|       [ 拒绝 / 取消 ]           [ 确认添加到日历 ]    |
+-------------------------------------------------------+
```

#### 5.1.4 Security & Permissions
- **Classification**: `Privileged-Native`
- Requires Android permission `android.permission.READ_CALENDAR` / `WRITE_CALENDAR` and iOS `NSCalendarsUsageDescription`.
- If permission is denied, fallback displays a downloadable `.ics` calendar file for manual import.

---

### 5.2 Tool: `notification_schedule`, `notification_cancel` & `alarm_set`
#### 5.2.1 Overview & Capabilities
- `notification_schedule`: Schedules local push notifications at a future date/time with title, body, and payload.
- `notification_cancel`: Cancels scheduled notifications by ID or all pending notifications.
- `alarm_set`: Invokes system alarm clock (via `android.intent.action.SET_ALARM` on Android or Local Notifications on iOS).

#### 5.2.2 OpenAI Function Calling JSON Schema
```json
{
  "type": "function",
  "function": {
    "name": "notification_schedule",
    "description": "Schedule a local reminder or push notification to pop up on the device at a specific time.",
    "parameters": {
      "type": "object",
      "properties": {
        "notification_id": {
          "type": "integer",
          "description": "Unique integer ID for this notification. If omitted, auto-generated."
        },
        "title": {
          "type": "string",
          "description": "Notification title header."
        },
        "body": {
          "type": "string",
          "description": "Notification body content."
        },
        "scheduled_time": {
          "type": "string",
          "description": "ISO8601 timestamp when notification should trigger (e.g. '2026-08-28T21:30:00+08:00')."
        },
        "repeat_interval": {
          "type": "string",
          "enum": ["none", "daily", "weekly"],
          "default": "none",
          "description": "Repetition frequency."
        }
      },
      "required": ["title", "body", "scheduled_time"]
    }
  }
}
```

```json
{
  "type": "function",
  "function": {
    "name": "alarm_set",
    "description": "Set a native system clock alarm for a specified hour and minute.",
    "parameters": {
      "type": "object",
      "properties": {
        "hour": {
          "type": "integer",
          "minimum": 0,
          "maximum": 23,
          "description": "Hour of the day (0-23)."
        },
        "minute": {
          "type": "integer",
          "minimum": 0,
          "maximum": 59,
          "description": "Minute of the hour (0-59)."
        },
        "message": {
          "type": "string",
          "description": "Alarm label or reminder message."
        },
        "days": {
          "type": "array",
          "items": { "type": "integer", "minimum": 1, "maximum": 7 },
          "description": "Days of the week to repeat (1=Monday ... 7=Sunday)."
        },
        "skip_ui": {
          "type": "boolean",
          "default": false,
          "description": "Set alarm without opening the clock app UI."
        }
      },
      "required": ["hour", "minute"]
    }
  }
}
```

#### 5.2.3 Security Classification
- `Privileged-Native` (OS notification/alarm permission check + interactive confirmation).

---

### 5.3 Tool: `contacts_search`
#### 5.3.1 Overview & Capabilities
Privacy-preserving address book query:
- Search by name, phone number fragment, or email address.
- **Privacy Masking**: Returns masked phone numbers (`138****1234`) and masked emails (`j***@example.com`) by default to prevent LLM prompt leakage. Unmasked access requires explicit user toggle.

#### 5.3.2 OpenAI Function Calling JSON Schema
```json
{
  "type": "function",
  "function": {
    "name": "contacts_search",
    "description": "Search device address book contacts by name, phone, or email with privacy masking. Requires user permission.",
    "parameters": {
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "Contact name, phone number snippet, or company name."
        },
        "max_results": {
          "type": "integer",
          "minimum": 1,
          "maximum": 20,
          "default": 5
        }
      },
      "required": ["query"]
    }
  }
}
```

#### 5.3.3 Security Classification
- `Privileged-Native`: Requires runtime `READ_CONTACTS` OS permission + Confirmation card.

---

### 5.4 Tool: `geolocation_get` & `reverse_geocode`
#### 5.4.1 Overview & Capabilities
- `geolocation_get`: Obtains device current latitude, longitude, altitude, accuracy radius, and speed via GPS / Network.
- `reverse_geocode`: Converts coordinates to physical address (Country, State/Province, City, District, Street, Postal Code) or address to coordinates.

#### 5.4.2 OpenAI Function Calling JSON Schema
```json
{
  "type": "function",
  "function": {
    "name": "geolocation_get",
    "description": "Get current physical location coordinates (latitude, longitude) of the device. Requires runtime GPS permission.",
    "parameters": {
      "type": "object",
      "properties": {
        "accuracy": {
          "type": "string",
          "enum": ["high", "balanced", "low", "coarse"],
          "default": "balanced",
          "description": "Desired accuracy level."
        },
        "timeout_seconds": {
          "type": "integer",
          "minimum": 2,
          "maximum": 30,
          "default": 10
        }
      }
    }
  }
}
```

```json
{
  "type": "function",
  "function": {
    "name": "reverse_geocode",
    "description": "Convert latitude and longitude coordinates into a human-readable street address, city, and country.",
    "parameters": {
      "type": "object",
      "properties": {
        "latitude": { "type": "number", "minimum": -90.0, "maximum": 90.0 },
        "longitude": { "type": "number", "minimum": -180.0, "maximum": 180.0 },
        "locale": { "type": "string", "default": "zh-CN" }
      },
      "required": ["latitude", "longitude"]
    }
  }
}
```

#### 5.4.3 Security Classification
- `geolocation_get`: `Privileged-Native` (OS Location runtime permission dialog + confirmation).
- `reverse_geocode`: `Safe` (Pure HTTP / geocoding lookup).

---

## 6. Universal Tool Execution Engine & Security Architecture

### 6.1 Four-Tier Security & Permission Model

To guarantee user privacy and device safety across all tools, the execution engine enforces four distinct security tiers:

```
+-----------------------------------------------------------------------------------+
|                           Security Permission Tiers                               |
+-----------------------------------------------------------------------------------+
| Tier 0: Safe              | Auto-execute without confirmation. Zero side effects. |
|                           | (math_eval, time_calc, weather_query, wiki_lookup)    |
+---------------------------+-------------------------------------------------------+
| Tier 1: Read-Only         | Auto-execute within strict sandbox. Read-only data.   |
|                           | (file_read, file_list, file_search)                   |
+---------------------------+-------------------------------------------------------+
| Tier 2: Sensitive-Confirm | Interactive UI confirmation dialog required before    |
|                           | execution. Side effects on disk/clipboard/MCP.        |
|                           | (file_write, clipboard_read/write, mcp_call_tool)     |
+---------------------------+-------------------------------------------------------+
| Tier 3: Privileged-Native | OS Runtime Permission check + Interactive UI prompt.  |
|                           | (calendar_*, notification_*, contacts_*, geolocation) |
+-----------------------------------------------------------------------------------+
```

### 6.2 Token Budget & Output Truncation Pipeline
To protect the LLM context window from being flooded by large tool outputs (e.g. 100KB HTML or 10,000 lines of logs), the tool engine implements a multi-stage **Truncation & Token Protection Pipeline**:

1. **Hard Byte Cap**: Tool outputs are capped at a maximum payload threshold (default: 15,000 characters / ~3,750 tokens).
2. **Head + Tail Preservation**: For truncated text, the engine retains the top 70% and bottom 20% of the budget with an explicit truncation notice in the middle:
   ```
   [... Truncated 14,250 characters. Showing top 3,000 and bottom 1,000 characters ...]
   ```
3. **Structured Truncation Metadata**: The tool response JSON explicitly includes `is_truncated: true`, `original_length`, `max_length`, and `content_ratio` (matching the existing `FetchResult` pattern in `url_fetch_service.dart`).

---

### 6.3 Universal Error Handling, Auto-Repair & Degradation

| Failure Mode | Auto-Repair / Fallback Strategy |
|---|---|
| **JSON Argument Parse Error** | Engine applies lenient regex cleanup (stripping trailing commas, fixing unescaped newlines). If unparseable, returns schema repair prompt to LLM. |
| **Missing Required Parameter** | Returns `{ "error": "MISSING_PARAM", "required_fields": [...], "suggestion": "..." }` to guide LLM self-correction in next turn. |
| **Network Timeout / Rate Limit** | Retries 1 time with exponential backoff (1.5s), falls back to secondary provider or cached offline results. |
| **Permission Denied by User** | Cleanly yields message: `用户已取消/拒绝该操作`, allowing LLM to adapt and propose alternatives. |
| **Tool Loop Count Exceeded** | When multi-turn tool calling reaches round 10 (or configured max), `AgentService` strips `tools` parameter and forces a final text summary response (as established in Milestone 11/12). |

---

### 6.4 Flutter Ecosystem & Plugin Mapping Matrix

| Functional Area | Recommended Flutter Package | Version Constraint | Platform Channel Requirement |
|---|---|---|---|
| Math & Decimal Calculation | `math_expressions` + `decimal` | `^2.0.0` / `^3.0.0` | Pure Dart |
| Timezone & Localization | `timezone` + `intl` | `^0.9.0` / `^0.19.0`| Pure Dart + tzdata asset |
| Sandboxed Script Interpreter| `flutter_js` (QuickJS) | `^0.8.0` | C/C++ FFI native isolate |
| Device Calendar Read/Write | `device_calendar` | `^4.3.0` | Android Calendar Provider / iOS EventKit |
| Local Notifications & Alerts| `flutter_local_notifications` | `^17.0.0` | Android NotificationManager / iOS UNUserNotificationCenter |
| Contacts & Address Book | `flutter_contacts` | `^1.1.0` | Android ContactsContract / iOS Contacts |
| GPS Geolocation & Geocoding | `geolocator` + `geocoding` | `^11.0.0` / `^3.0.0` | Android FusedLocationProvider / iOS CoreLocation |
| Native Alarm Setting | `android_intent_plus` | `^4.0.0` | Android Intent `AlarmClock.ACTION_SET_ALARM` |
| Runtime Permissions | `permission_handler` | `^11.0.0` | Android runtime permissions / iOS info.plist |

---

## 7. Conclusion & Next Steps

This **Agent Tools Taxonomy & Inventory Specification** provides a complete, hardened, production-ready technical design for the Flutter AI Chat application. Every tool is strictly specified with OpenAI Function Calling JSON Schema, precise parameter constraints, structured dual-format outputs (JSON + Markdown), four-tier security classifications, and robust error/degradation mechanisms.

This document serves as the foundational blueprint for Milestone 23 and subsequent implementation phases.
