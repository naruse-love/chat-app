# Dispatch for Worker M23.2

## Role
You are Worker M23.2 (`teamwork_preview_worker`).
Working directory: `D:\work\chat\.agents\worker_m23_2\`

## Objective
Implement Milestone 23.2 (4 Safe Built-in Tools):
1. `lib/services/tools/math_eval_tool.dart`:
   - Pure Dart recursive descent parser.
   - Operators: `+`, `-`, `*`, `/`, `%`, `^` (power), parentheses.
   - Constants: `pi`, `e`.
   - Math functions: `sqrt`, `cbrt`, `abs`, `ceil`, `floor`, `round`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sinh`, `cosh`, `tanh`, `ln`, `log10`, `log2`, `exp`, `factorial` (`fact` or `n!`).
   - Statistical functions: `mean([..])` or `mean(1,2,3)`, `median`, `mode`, `stddev`, `variance`, `min`, `max`, `sum`.
   - Unit conversion: `convert(value, from, to)` (temperature: C/F/K; length: m/km/cm/mm/in/ft/yd/mi; weight: g/kg/mg/lb/oz; data storage: B/KB/MB/GB/TB/PB).
   - Robust Chinese error messages for division by zero, invalid characters, negative square roots, logarithm domain errors.
2. `lib/services/tools/time_calculator_tool.dart`:
   - Supported operations: `now`, `convert`, `offset`, `duration`.
   - Timezone alias dictionary (Chinese & English aliases: `北京`, `上海`, `中国`, `东京`, `纽约`, `伦敦`, `巴黎`, `悉尼`, `UTC`, `GMT`, `CST`, `EST`, `PST`, `JST`, `Asia/Shanghai`, `America/New_York`, etc.).
   - Duration / offset parser (`+3d`, `-5h30m`, `+2w`, `-45s`, `+1y`).
   - Natural duration formatting in Chinese (e.g. `2天 3小时 15分钟`).
3. `lib/services/tools/weather_query_tool.dart`:
   - Free Open-Meteo REST API (`https://geocoding-api.open-meteo.com/v1/search` and `https://api.open-meteo.com/v1/forecast`).
   - WMO weather code mapping to Chinese descriptions and emoji icons.
   - Optional `Dio` injection for deterministic unit testing.
4. `lib/services/tools/wiki_lookup_tool.dart`:
   - Public Wikipedia REST APIs (`https://zh.wikipedia.org` and `https://en.wikipedia.org`).
   - Summary lookup (`/api/rest_v1/page/summary/{title}`).
   - Search fallback (`/w/api.php?action=query&list=search&srsearch={query}`).
   - Disambiguation detection and alternatives formatting.
   - Optional `Dio` injection for deterministic unit testing.
5. Register all 4 tools in `lib/services/tool_registry.dart` `ToolRegistry.defaultRegistry()`.
6. Unit tests:
   - `test/services/basic_tools_test.dart` (35+ test cases covering math, time, weather, wiki, error cases, and registry integration).
7. Run `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` and `D:\work\flutter-sdk\flutter\bin\flutter.bat test`. Ensure 0 issues and 100% test pass.
8. Write `handoff.md` and report.

## Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. An auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Reference Files
- `D:\work\chat\PROJECT.md`
- `D:\work\chat\.agents\explorer_m23_2\report.md`
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\TEST_INFRA.md`
