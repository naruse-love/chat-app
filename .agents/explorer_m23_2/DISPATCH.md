# Dispatch for Explorer M23.2

## Role
You are Explorer M23.2 (`teamwork_preview_explorer`).
Working directory: `D:\work\chat\.agents\explorer_m23_2\`

## Objective
Design the concrete architecture, class hierarchies, mathematical parser algorithms, timezone/datetime logic, Open-Meteo & Wikipedia API clients, and mock test suites for the 4 Built-in Safe Tools (Level 0 / Safe):
1. `lib/services/tools/math_eval_tool.dart`:
   - Recursive descent parser in pure Dart (supporting expressions like `(3 + 5) * 2 ^ 3`, `sqrt(16) + sin(pi / 2)`, `mean([1, 2, 3, 4, 5])`, `stddev([2, 4, 4, 4, 5, 5, 7, 9])`, `convert(100, 'km', 'mi')`, `convert(37, 'C', 'F')`).
   - Clear error diagnostics in Chinese (syntax error, unknown function, division by zero, invalid unit).
2. `lib/services/tools/time_calculator_tool.dart`:
   - Support `operation`: `now` (current time in timezone), `convert` (convert datetime between timezones), `offset` (add/subtract duration like `+3d`, `-5h30m`), `duration` (calculate duration between time1 and time2).
   - Timezone alias dictionary (e.g. `北京` -> `Asia/Shanghai`, `纽约` -> `America/New_York`, `东京` -> `Asia/Tokyo`, `伦敦` -> `Europe/London`, `UTC`, `PST`, `EST`, `CST`, `JST`, `GMT`).
3. `lib/services/tools/weather_query_tool.dart`:
   - Uses `Dio` (already in `pubspec.yaml`).
   - Geocoding lookup (`https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1&language=zh`) -> lat/lng.
   - Forecast lookup (`https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lng}&current_weather=true&hourly=temperature_2m,relative_humidity_2m&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=auto`).
   - Mapping WMO weather codes to descriptive Chinese strings and weather icons.
   - Optional `Dio` injection for mock testing.
4. `lib/services/tools/wiki_lookup_tool.dart`:
   - Uses `Dio`.
   - Supports `language`: `zh` (default) and `en`.
   - Fetches summary `/api/rest_v1/page/summary/{title}`. If 404, queries OpenSearch / search API `/w/api.php?action=query&list=search&srsearch={query}&format=json` and fetches top match.
   - Detects `type: 'disambiguation'` and formats disambiguation options.
   - Optional `Dio` injection for mock testing.
5. Integration with `ToolRegistry.defaultRegistry()`:
   - Ensure all 4 tools are registered in `ToolRegistry.defaultRegistry()` alongside existing legacy tools.
6. Comprehensive test specification for `test/services/basic_tools_test.dart`.
7. Write `report.md` and `handoff.md`.

## Required Reading
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\TEST_INFRA.md`
