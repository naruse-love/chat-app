# Handoff Report — Agent Tools Taxonomy & Inventory Architecture

## 1. Observation
- **Codebase Context**:
  - `lib/services/agent_service.dart`: Currently supports multi-turn streaming tool execution, pseudo-XML / DSML fallback parsing (`<tool_call>`, `<｜｜DSML｜｜tool_calls>`), dynamic tool filtering via `getEffectiveTools`, and round-limit fallback at 100/4 rounds.
  - `lib/services/search_service.dart`: Supports SearXNG, Bing HTML scraping with cookie management, and Google Grounding with dual-page concurrent retrieval and URL deduplication.
  - `lib/services/url_fetch_service.dart`: Implements rich structured web scraping (`FetchResult`), metadata extraction (OpenGraph, JSON-LD), link analysis, and 15,000-char truncation management.
  - `pubspec.yaml`: Contains Flutter 3.12+, Riverpod 2.5, Dio 5.4, sqflite 2.3, flutter_secure_storage 9.0, html 0.15.4, path_provider 2.1.
- **Requirement Analysis**:
  - Requires exhaustive requirements analysis and technical design across 4 dimensions: Basic Utility, Local Files & Sandboxed Execution, Model Context Protocol (MCP) Extensions, and Mobile Native Device Capabilities.
  - Every tool requires: Snake_case name, OpenAPI 3.0 / JSON Schema parameter definition, detailed constraints, structured I/O (JSON + Markdown), 4-tier security classification (`Safe`, `Read-Only`, `Sensitive-Confirm`, `Privileged-Native`), and error/fallback strategies.

## 2. Logic Chain
1. **Tool Classification & Taxonomy**: Designed a 23-tool matrix covering all requested functionality (math, time/timezone, weather, wikipedia, sandboxed file I/O, quickjs code evaluation, clipboard, MCP client protocols, calendar, notifications, alarms, contacts with privacy masks, and geolocation).
2. **OpenAPI / JSON Schema Standardization**: Defined strict JSON Schemas for each tool, specifying types, required parameters, enums, defaults, and boundary constraints (`minimum`, `maximum`, format).
3. **Multi-Tier Security & Zero-Escape Isolation**:
   - `Safe`: Pure compute/public network query with zero local state mutation (e.g. `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`).
   - `Read-Only`: Isolated read operations within sandbox directory (e.g. `file_read`, `file_list`, `file_search`).
   - `Sensitive-Confirm`: User interactive UI confirmation modal with Diff/Preview before execution (e.g. `file_write`, `clipboard_*`, `mcp_call_tool`).
   - `Privileged-Native`: Mobile OS runtime permission prompt + interactive confirmation dialog (e.g. `calendar_*`, `notification_*`, `alarm_set`, `contacts_search`, `geolocation_get`).
4. **Token Budget & Truncation**: Standardized a 15,000 character maximum output cap with head-70% / tail-20% preservation and explicit truncation indicators.
5. **MCP Integration**: Designed translation layer from MCP JSON-RPC 2.0 (`tools/list`, `tools/call`, `resources/read`, `prompts/get`) to OpenAI Function Calling formats.

## 3. Caveats
- No code in `lib/` was modified during this investigation (strictly following the read-only exploration constraint).
- Mobile native plugins (`device_calendar`, `flutter_local_notifications`, `geolocator`, `flutter_contacts`, `flutter_js`) require adding corresponding dependencies to `pubspec.yaml` and platform manifest permissions (`AndroidManifest.xml`, `Info.plist`) during implementation milestones.

## 4. Conclusion
The comprehensive requirements analysis, tool schemas, structured output formats, security frameworks, and architectural blueprints have been finalized and documented in `D:\work\chat\.agents\explorer_taxonomy_gen7\report.md`. The design is completely aligned with the existing Riverpod + SQLite + AgentService architecture of `chat-app`.

## 5. Verification Method
- **Report Verification**: Inspect `D:\work\chat\.agents\explorer_taxonomy_gen7\report.md` for completeness across all 4 dimensions and 23 tool definitions.
- **Existing Suite Verification**:
  - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` (0 issues).
  - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat test` (all 173 tests pass cleanly).
