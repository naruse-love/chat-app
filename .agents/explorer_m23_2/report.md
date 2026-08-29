# Milestone 23.2 Technical Design Report: Four Safe Built-in Tools

## 1. Executive Summary

Milestone 23.2 designs and specifies the 4 Safe Built-in Tools for the Flutter AI Agent application (`chat-app`):
1. **`MathEvalTool` (`lib/services/tools/math_eval_tool.dart`)**:
   - Pure Dart recursive descent expression evaluator with zero external dependencies.
   - Supports arithmetic (`+`, `-`, `*`, `/`, `%`, `^`, `**`, parentheses), scientific/trigonometric functions (`sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sqrt`, `cbrt`, `exp`, `ln`, `log10`, `log2`, `abs`, `round`, `floor`, `ceil`, `pi`, `e`), statistical aggregations (`mean`, `median`, `mode`, `stddev`, `variance`, `sum`, `min`, `max`, `count` over arrays/lists), and multi-category unit conversions (`convert(val, 'from', 'to')` for temperature, length, weight, storage, speed, area, and time).
   - High-fidelity Chinese error reporting (division by zero, negative square root, non-positive logarithm, syntax error, unknown function/constant, unsupported unit conversion).
2. **`TimeCalculatorTool` (`lib/services/tools/time_calculator_tool.dart`)**:
   - Pure Dart timezone, date arithmetic, duration difference, and timestamp calculator.
   - Comprehensive IANA timezone mapping with global Chinese and English aliases (`北京`, `东京`, `伦敦`, `纽约`, `PST`, `EST`, `CST`, `JST`, `GMT`, `UTC+8`, `-05:00`).
   - Four core operations: `now` (current time in timezone), `convert` (cross-timezone conversion), `offset` (relative delta arithmetic like `+3d`, `-5h30m`, `+1w`, `+2M`, `+1y`), and `duration` (exact duration difference between two timestamps with human-readable Chinese breakdown).
3. **`WeatherQueryTool` (`lib/services/tools/weather_query_tool.dart`)**:
   - Open-Meteo free REST API client (no API key required).
   - Two-stage execution: Geocoding lookup (`geocoding-api.open-meteo.com`) to latitude/longitude, followed by Forecast query (`api.open-meteo.com/v1/forecast`).
   - Comprehensive WMO weather code mapping to Chinese descriptions and weather icons.
   - Rich Markdown output with current weather card and multi-day forecast table.
   - `Dio` dependency injection for deterministic offline unit testing.
4. **`WikiLookupTool` (`lib/services/tools/wiki_lookup_tool.dart`)**:
   - Wikipedia public REST and MediaWiki Search API client.
   - Supports Chinese (`zh`) and English (`en`) editions.
   - Two-stage lookup: Page summary lookup (`/api/rest_v1/page/summary/{title}`), with automatic fallback to OpenSearch/Search API (`/w/api.php?action=query&list=search`) upon 404 or disambiguation.
   - Disambiguation page detection with structured option formatting.
   - `Dio` dependency injection for deterministic offline unit testing.
5. **`ToolRegistry` Default Registry Integration (`lib/services/tool_registry.dart`)**:
   - Updates `ToolRegistry.defaultRegistry()` to register all 8 tools (`web_search`, `google_search`, `bing_search`, `url_fetch`, `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`).
6. **Comprehensive Test Suite (`test/services/basic_tools_test.dart`)**:
   - 35+ test cases covering parser grammar, mathematical functions, timezone conversions, duration math, HTTP mocks for Open-Meteo and Wikipedia, error diagnostics, and ToolRegistry execution dispatching.

---

## 2. Architecture & File Layout

```
lib/
├── models/
│   └── tool/
│       ├── tool.dart
│       ├── tool_parameter.dart
│       ├── tool_execution_result.dart
│       └── tool_security_level.dart
└── services/
    ├── tool_registry.dart             <-- Updated with 8 default registered tools
    └── tools/
        ├── legacy_tool_adapters.dart  <-- web_search, google_search, bing_search, url_fetch
        ├── math_eval_tool.dart        <-- NEW: MathEvalTool (Pure Dart Lexer + Parser + Stats + Units)
        ├── time_calculator_tool.dart  <-- NEW: TimeCalculatorTool (Pure Dart Timezone & Date Math)
        ├── weather_query_tool.dart    <-- NEW: WeatherQueryTool (Open-Meteo REST + WMO Decoder + Dio)
        └── wiki_lookup_tool.dart      <-- NEW: WikiLookupTool (Wikipedia REST + Search Fallback + Dio)

test/
└── services/
    ├── basic_tools_test.dart          <-- NEW: Comprehensive test suite for the 4 basic tools
    ├── tool_registry_test.dart        <-- ToolRegistry tests
    └── tool_registry_stress_test.dart <-- Stress & concurrency tests
```

---

## 3. Concrete Design: `MathEvalTool` (`lib/services/tools/math_eval_tool.dart`)

### 3.1 Tool Metadata & JSON Schema

- **`name`**: `math_eval`
- **`displayName`**: `数学计算器`
- **`description`**: `High-precision mathematical expression evaluator. Supports arithmetic (+, -, *, /, %, ^, **), scientific/trigonometric functions (sqrt, sin, cos, tan, asin, acos, atan, ln, log10, log2, exp, abs, round, floor, ceil), statistics (mean, median, mode, stddev, variance, sum, min, max, count), and unit conversions (convert(val, 'from', 'to') for temperature, length, weight, storage, speed, area, time).`
- **`securityLevel`**: `ToolSecurityLevel.safe` (Level 0)
- **Parameters**:
  - `expression` (type: `string`, required: `true`, description: `The mathematical expression, statistical formula, or unit conversion function to evaluate (e.g. '(3 + 5) * 2 ^ 3', 'sqrt(16) + sin(pi / 2)', 'mean([1, 2, 3, 4, 5])', 'stddev([2, 4, 4, 4, 5, 5, 7, 9])', 'convert(100, "km", "mi")', 'convert(37, "C", "F")').`)

### 3.2 Tokenizer / Lexer Specification

Tokens recognized by `_MathLexer`:
- `TokenType.number`: `123`, `3.14159`, `.5`, `1e5`, `2.5e-3`
- `TokenType.string`: `'km'`, `'mi'`, `'C'`, `'F'`, `"kg"`, `"bytes"`
- `TokenType.identifier`: Function/constant names e.g. `sin`, `cos`, `tan`, `sqrt`, `cbrt`, `pi`, `e`, `mean`, `median`, `mode`, `stddev`, `variance`, `sum`, `min`, `max`, `count`, `convert`, `round`, `floor`, `ceil`, `abs`, `exp`, `ln`, `log`, `log10`, `log2`, `pow`
- `TokenType.plus`: `+`
- `TokenType.minus`: `-`
- `TokenType.multiply`: `*`
- `TokenType.divide`: `/`
- `TokenType.modulo`: `%`
- `TokenType.power`: `^` or `**`
- `TokenType.lparen`: `(`
- `TokenType.rparen`: `)`
- `TokenType.lbracket`: `[`
- `TokenType.rbracket`: `]`
- `TokenType.comma`: `,`
- `TokenType.eof`: End of input

### 3.3 Grammar & Recursive Descent Parser

```
Expression   := AddSub
AddSub       := MulDiv ( ('+' | '-') MulDiv )*
MulDiv       := Power ( ('*' | '/' | '%') Power )*
Power        := Unary ( ('^' | '**') Power )?         // Right-associative exponentiation
Unary        := ('+' | '-') Unary | Primary
Primary      := Number
              | StringLiteral
              | ArrayLiteral: '[' ( Expression (',' Expression)* )? ']'
              | FunctionCall: Identifier '(' ( Expression (',' Expression)* )? ')'
              | Constant: Identifier
              | '(' Expression ')'
```

### 3.4 Math & Statistical Functions Implementation

1. **Constants**:
   - `pi` = `3.1415926535897932`
   - `e` = `2.718281828459045`
   - `tau` = `6.283185307179586`
   - `phi` = `1.618033988749895`

2. **Scientific & Trigonometric Functions**:
   - `sqrt(x)`: if `x < 0` -> throws `MathEvalException('负数不能在实数范围内开平方根: $x')`
   - `cbrt(x)`: `x >= 0 ? math.pow(x, 1/3) : -math.pow(-x, 1/3)`
   - `sin(x)`, `cos(x)`, `tan(x)`: standard trigonometric functions in radians.
   - `asin(x)`, `acos(x)`: `x` must be in `[-1.0, 1.0]`, else throws exception.
   - `atan(x)`, `atan2(y, x)`: standard inverse tangent.
   - `exp(x)`: `math.exp(x)`
   - `ln(x)` / `log(x)`: if `x <= 0` -> throws `MathEvalException('对数真数必须大于零: $x')`.
   - `log10(x)`: `math.log(x) / math.ln10`
   - `log2(x)`: `math.log(x) / math.ln2`
   - `log(x, base)`: `math.log(x) / math.log(base)`
   - `pow(base, exp)`: `math.pow(base, exp)`
   - `abs(x)`: `x.abs()`
   - `round(x)` or `round(x, decimals)`: rounded to `decimals` decimal places.
   - `floor(x)`: `x.floorToDouble()`
   - `ceil(x)`: `x.ceilToDouble()`
   - `deg2rad(x)`: `x * math.pi / 180.0`
   - `rad2deg(x)`: `x * 180.0 / math.pi`
   - `factorial(n)` / `fact(n)`: non-negative integer factorial.

3. **Statistical Functions**:
   All statistical functions accept either a list literal `[1, 2, 3, 4]` or multiple arguments `1, 2, 3, 4`.
   - `sum(data)`: $\sum x_i$
   - `count(data)`: $n$
   - `min(data)`: minimum value
   - `max(data)`: maximum value
   - `mean(data)`: $\mu = \frac{\sum x_i}{n}$
   - `median(data)`: sorted middle element (or average of two middle elements).
   - `mode(data)`: most frequent value(s).
   - `variance(data)`: population variance $\sigma^2 = \frac{1}{n}\sum_{i=1}^n (x_i - \mu)^2$.
   - `stddev(data)`: standard deviation $\sigma = \sqrt{\text{variance}}$.
     - For example: `stddev([2, 4, 4, 4, 5, 5, 7, 9])` -> $\mu = 5.0$, sum of sq diff = $9+1+1+1+0+0+4+16 = 32$, variance = $32/8 = 4.0$, $\sigma = \sqrt{4.0} = 2.0$.

4. **Unit Conversion (`convert(val, 'from', 'to')`)**:
   Supported Unit Categories:
   - **Temperature**: `C` (`℃`, `celsius`, `摄氏度`), `F` (`℉`, `fahrenheit`, `华氏度`), `K` (`kelvin`, `开尔文`).
     - Conversion formulas:
       - $C \to F$: $C \times \frac{9}{5} + 32$
       - $F \to C$: $(F - 32) \times \frac{5}{9}$
       - $C \to K$: $C + 273.15$
       - $K \to C$: $K - 273.15$
       - $F \to K$: $(F - 32) \times \frac{5}{9} + 273.15$
       - $K \to F$: $(K - 273.15) \times \frac{9}{5} + 32$
   - **Length**: Base: `m` (Meter)
     - `m` (1.0), `km` (1000.0), `cm` (0.01), `mm` (0.001), `mi`/`mile` (1609.344), `yd`/`yard` (0.9144), `ft`/`foot`/`feet` (0.3048), `in`/`inch` (0.0254), `nm`/`nautical_mile` (1852.0).
   - **Weight / Mass**: Base: `g` (Gram)
     - `g` (1.0), `kg` (1000.0), `mg` (0.001), `t`/`ton` (1000000.0), `lb`/`pound` (453.59237), `oz`/`ounce` (28.349523125), `jin`/`斤` (500.0), `liang`/`两` (50.0).
   - **Data Storage**: Base: `B` (Bytes, 1024-based binary standards)
     - `B` (1.0), `KB` (1024.0), `MB` ($1024^2$), `GB` ($1024^3$), `TB` ($1024^4$), `PB` ($1024^5$), `bit` (0.125).
   - **Speed**: Base: `m/s`
     - `m/s` (1.0), `km/h`/`kph` ($1 / 3.6$), `mph` (0.44704), `knot` (0.514444).
   - **Area**: Base: `m2`
     - `m2`/`sqm` (1.0), `km2`/`sqkm` (1000000.0), `ha`/`公顷` (10000.0), `mu`/`亩` (666.666666667), `sqft` (0.09290304), `acre`/`英亩` (4046.8564224).
   - **Time**: Base: `s` (Seconds)
     - `s` (1.0), `ms` (0.001), `min` (60.0), `h`/`hr` (3600.0), `d`/`day` (86400.0), `w`/`week` (604800.0).

### 3.5 Chinese Error Diagnostics

- Division by zero: `计算错误: 除数不能为零`
- Negative square root: `计算错误: 负数不能在实数范围内开平方根: -16`
- Logarithm of non-positive: `计算错误: 对数真数必须大于零: 0`
- Empty expression: `表达式不能为空`
- Syntax error: `语法错误: 缺少操作数或表达式不完整` / `语法错误: 缺少闭合括号 ')'`
- Unknown function / constant: `未知函数或常量: 'unknown_func'`
- Unsupported unit: `不支持的单位: 'xyz'`
- Cross-category unit mismatch: `无法在不同类别单位间转换: 从 'km' (长度) 到 'kg' (质量)`

### 3.6 Output Format

- **Success Output Content**:
  ```markdown
  **计算表达式**: `(3 + 5) * 2 ^ 3`
  **计算结果**: **`64`**
  ```
- **RawData Map**:
  ```json
  {
    "expression": "(3 + 5) * 2 ^ 3",
    "result": 64,
    "formattedResult": "64"
  }
  ```

---

## 4. Concrete Design: `TimeCalculatorTool` (`lib/services/tools/time_calculator_tool.dart`)

### 4.1 Tool Metadata & JSON Schema

- **`name`**: `time_calculator`
- **`displayName`**: `时区与时间计算器`
- **`description`**: `Calculate current time across global timezones, convert timestamps between timezones, perform relative date arithmetic (+3d, -5h30m), and calculate exact duration differences between timestamps.`
- **`securityLevel`**: `ToolSecurityLevel.safe` (Level 0)
- **Parameters**:
  - `operation` (type: `string`, required: `true`, enum: `['now', 'convert', 'offset', 'duration']`, description: `The time operation to perform: 'now' (get current time in timezone), 'convert' (convert datetime between timezones), 'offset' (add/subtract relative duration), or 'duration' (calculate difference between two datetimes).`)
  - `timezone` (type: `string`, required: `false`, defaultValue: `'Asia/Shanghai'`, description: `Target timezone name or alias (e.g. 'Asia/Shanghai', 'UTC', 'America/New_York', '北京', '东京', '伦敦', '纽约', 'PST', 'EST', 'CST', 'JST', 'GMT', '+08:00'). Default: 'Asia/Shanghai'.`)
  - `fromTimezone` (type: `string`, required: `false`, description: `Source timezone for 'convert' operation (e.g. 'Asia/Shanghai', '北京').`)
  - `toTimezone` (type: `string`, required: `false`, description: `Destination timezone for 'convert' operation (e.g. 'America/New_York', '纽约').`)
  - `datetime` (type: `string`, required: `false`, description: `Input datetime string in ISO8601 or standard format (e.g. '2026-08-28T12:00:00', '2026-08-28 12:00:00', '2026-08-28') or Unix timestamp (seconds/ms).`)
  - `offset` (type: `string`, required: `false`, description: `Relative offset string to add or subtract (e.g. '+3d', '-5h30m', '+1w', '+2M', '-1y', '+45s', '+2d4h30m').`)
  - `time1` (type: `string`, required: `false`, description: `First datetime for 'duration' calculation.`)
  - `time2` (type: `string`, required: `false`, description: `Second datetime for 'duration' calculation.`)
  - `format` (type: `string`, required: `false`, enum: `['readable', 'iso', 'timestamp']`, defaultValue: `'readable'`, description: `Output format representation.`)

### 4.2 Timezone Resolution Engine

Pure Dart timezone offset lookup table in minutes from UTC:
```dart
const Map<String, int> _timezoneOffsetsInMinutes = {
  // Asia
  'asia/shanghai': 480, 'asia/beijing': 480, 'asia/chongqing': 480,
  'asia/hong_kong': 480, 'asia/taipei': 480, 'asia/singapore': 480,
  'asia/tokyo': 540, 'asia/seoul': 540, 'asia/bangkok': 420,
  'asia/dubai': 240, 'asia/kolkata': 330, 'asia/calcutta': 330,
  // Europe
  'europe/london': 0, 'europe/paris': 60, 'europe/berlin': 60,
  'europe/rome': 60, 'europe/madrid': 60, 'europe/amsterdam': 60,
  'europe/moscow': 180,
  // America
  'america/new_york': -300, 'america/chicago': -360, 'america/denver': -420,
  'america/los_angeles': -480, 'america/toronto': -300, 'america/vancouver': -480,
  'america/sao_paulo': -180,
  // Australia & Pacific
  'australia/sydney': 600, 'australia/melbourne': 600, 'australia/perth': 480,
  'pacific/auckland': 720, 'pacific/honolulu': -600,
  // UTC / GMT
  'utc': 0, 'gmt': 0,
};
```

Common Chinese and English alias mapping:
```dart
const Map<String, String> _timezoneAliases = {
  // Chinese aliases
  '北京': 'Asia/Shanghai', '北京时间': 'Asia/Shanghai', '中国': 'Asia/Shanghai', '中国标准时间': 'Asia/Shanghai',
  '上海': 'Asia/Shanghai', '香港': 'Asia/Hong_Kong', '台北': 'Asia/Taipei', '台湾': 'Asia/Taipei',
  '东京': 'Asia/Tokyo', '日本': 'Asia/Tokyo', '首尔': 'Asia/Seoul', '韩国': 'Asia/Seoul',
  '新加坡': 'Asia/Singapore', '曼谷': 'Asia/Bangkok', '迪拜': 'Asia/Dubai',
  '伦敦': 'Europe/London', '英国': 'Europe/London', '格林威治': 'UTC',
  '巴黎': 'Europe/Paris', '法国': 'Europe/Paris', '柏林': 'Europe/Berlin', '德国': 'Europe/Berlin',
  '莫斯科': 'Europe/Moscow', '俄罗斯': 'Europe/Moscow',
  '纽约': 'America/New_York', '华盛顿': 'America/New_York', '美东': 'America/New_York',
  '芝加哥': 'America/Chicago', '美中': 'America/Chicago',
  '洛杉矶': 'America/Los_Angeles', '旧金山': 'America/Los_Angeles', '硅谷': 'America/Los_Angeles', '美西': 'America/Los_Angeles',
  '悉尼': 'Australia/Sydney', '墨尔本': 'Australia/Melbourne', '奥克兰': 'Pacific/Auckland', '新西兰': 'Pacific/Auckland',
  '夏威夷': 'Pacific/Honolulu',
  // Standard abbreviations
  'cst': 'Asia/Shanghai', // China Standard Time
  'jst': 'Asia/Tokyo',
  'kst': 'Asia/Seoul',
  'sgt': 'Asia/Singapore',
  'hkt': 'Asia/Hong_Kong',
  'gmt': 'UTC',
  'utc': 'UTC',
  'cet': 'Europe/Paris',
  'msk': 'Europe/Moscow',
  'est': 'America/New_York',
  'edt': 'America/New_York',
  'cdt': 'America/Chicago',
  'mst': 'America/Denver',
  'pst': 'America/Los_Angeles',
  'pdt': 'America/Los_Angeles',
  'aest': 'Australia/Sydney',
  'nzst': 'Pacific/Auckland',
  'hst': 'Pacific/Honolulu',
};
```

Direct Offset Regex Support:
- Matches strings like `UTC+8`, `UTC+08:00`, `GMT-5`, `+08:00`, `-05:00`, `+8`, `-5`.

### 4.3 Operations & Execution Logic

1. **`now` Operation**:
   - Resolves target timezone offset in minutes.
   - Calculates target local `DateTime` from UTC `nowProvider()`.
   - Computes: formatted string (`yyyy-MM-dd HH:mm:ss`), ISO8601 string, Chinese weekday (`星期一` ~ `星期日`), timestamp in milliseconds, and timezone offset description (`UTC+08:00`).

2. **`convert` Operation**:
   - Takes `datetime`, `fromTimezone` (defaults to `Asia/Shanghai` or inferred), and `toTimezone` (defaults to `UTC` or specified).
   - Converts source local time to UTC, then translates from UTC to destination local time.
   - Returns both source and target formatted timestamps with timezone headers.

3. **`offset` Operation**:
   - Takes base `datetime` (defaults to current time if omitted), `timezone`, and `offset` string.
   - Parses offset units via regex:
     - `y` / `years` / `年`: adds N calendar years.
     - `M` / `months` / `月`: adds N calendar months (with day clamping for end-of-month dates e.g. Jan 31 + 1 month -> Feb 28).
     - `w` / `weeks` / `周`: adds $N \times 7$ days.
     - `d` / `days` / `天` / `日`: adds N days.
     - `h` / `hours` / `小时`: adds N hours.
     - `m` / `minutes` / `分` / `分钟`: adds N minutes.
     - `s` / `seconds` / `秒`: adds N seconds.
   - Returns starting time, applied offset formula, and resulting target time.

4. **`duration` Operation**:
   - Takes `time1` and `time2`.
   - Parses both timestamps into UTC.
   - Computes delta: `time2.difference(time1)`.
   - Breaks down delta into total milliseconds, total seconds, total minutes, total hours, total days, and a structured Chinese human-readable string: e.g. `3天 4小时 15分钟 30秒` (or `-2天 5小时` if time2 < time1).

### 4.4 Chinese Error Diagnostics

- Unsupported operation: `不支持的时间计算操作: 'invalid_op'`
- Missing duration arguments: `操作 'duration' 需要提供 'time1' 和 'time2' 参数`
- Unknown timezone: `未知时区或无法解析时区: 'Atlantis/Unknown'`
- Invalid datetime string: `无法解析时间格式: 'not_a_date'`
- Invalid offset string: `无法解析相对偏移量: 'bad_offset'`

---

## 5. Concrete Design: `WeatherQueryTool` (`lib/services/tools/weather_query_tool.dart`)

### 5.1 Tool Metadata & JSON Schema

- **`name`**: `weather_query`
- **`displayName`**: `天气查询`
- **`description`**: `Query real-time weather conditions and 1 to 7 days forecast for any city or region worldwide via Open-Meteo API.`
- **`securityLevel`**: `ToolSecurityLevel.readOnly` (Level 1)
- **Parameters**:
  - `city` (type: `string`, required: `true`, description: `City name in Chinese or English (e.g. '北京', 'Shanghai', 'Tokyo', 'New York', 'London').`)
  - `forecastDays` (type: `integer`, required: `false`, defaultValue: 3, description: `Number of forecast days (1 to 7). Default: 3.`)

### 5.2 API Architecture & Workflow

```
[User / LLM] ---> weather_query(city: "北京", forecastDays: 3)
                       │
                       ▼
        1. Geocoding Search (Open-Meteo)
        GET https://geocoding-api.open-meteo.com/v1/search?name=北京&count=1&language=zh&format=json
                       │
                       ▼ (Extracted: lat: 39.9075, lng: 116.3972, name: "北京", country: "中国")
        2. Weather Forecast Query (Open-Meteo)
        GET https://api.open-meteo.com/v1/forecast?latitude=39.9075&longitude=116.3972&current_weather=true&hourly=relative_humidity_2m,apparent_temperature&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_sum,windspeed_10m_max&timezone=auto
                       │
                       ▼
        3. WMO Weather Code Mapping & Markdown Formatting
                       │
                       ▼
             ToolExecutionResult.success(...)
```

### 5.3 Complete WMO Weather Code Interpretation Table

| WMO Code | Chinese Description | Weather Icon | Condition Type |
| :--- | :--- | :--- | :--- |
| `0` | `晴天` | ☀️ | Clear |
| `1` | `大部晴朗` | 🌤️ | Mainly clear |
| `2` | `局部多云` | ⛅ | Partly cloudy |
| `3` | `阴天` | ☁️ | Overcast |
| `45` | `大雾` | 🌫️ | Fog |
| `48` | `沉积雾凇 / 冰雾` | 🌫️❄️ | Rime fog |
| `51` | `轻度毛毛雨` | 🌧️ | Light drizzle |
| `53` | `中度毛毛雨` | 🌧️ | Moderate drizzle |
| `55` | `高密度毛毛雨` | 🌧️ | Dense drizzle |
| `56` | `轻度冻毛毛雨` | 🌧️❄️ | Light freezing drizzle |
| `57` | `重度冻毛毛雨` | 🌧️❄️ | Dense freezing drizzle |
| `61` | `小雨` | 🌦️ | Slight rain |
| `63` | `中雨` | 🌧️ | Moderate rain |
| `65` | `大雨` | 🌧️🌧️ | Heavy rain |
| `66` | `轻度冻雨` | 🌧️❄️ | Light freezing rain |
| `67` | `重度冻雨` | 🌧️❄️ | Heavy freezing rain |
| `71` | `小雪` | 🌨️ | Slight snow fall |
| `73` | `中雪` | 🌨️❄️ | Moderate snow fall |
| `75` | `大雪` | ❄️❄️ | Heavy snow fall |
| `77` | `雪粒` | 🌨️ | Snow grains |
| `80` | `微弱阵雨` | 🌦️ | Slight rain showers |
| `81` | `中度阵雨` | 🌧️ | Moderate rain showers |
| `82` | `强暴阵雨` | ⛈️ | Violent rain showers |
| `85` | `微弱阵雪` | 🌨️ | Slight snow showers |
| `86` | `强阵雪` | 🌨️❄️ | Heavy snow showers |
| `95` | `雷暴` | ⛈️ | Thunderstorm |
| `96` | `雷暴伴有轻度冰雹` | ⛈️🌨️ | Thunderstorm with slight hail |
| `99` | `雷暴伴有强冰雹` | ⛈️🌨️ | Thunderstorm with heavy hail |

### 5.4 Output Schema & Markdown Format

```markdown
### 📍 北京 (中国, 北京) 实时天气与预报

**当前天气 (2026-08-28 12:00)**:
- **天气状况**: 🌤️ 大部晴朗
- **实时气温**: 25.4 °C (体感温度: 26.1 °C)
- **相对湿度**: 55 %
- **风速风向**: 12.5 km/h (南风 180°)

#### 📅 未来 3 天天气预报:
| 日期 | 天气状况 | 气温范围 | 降水量 | 最大风速 |
| :--- | :--- | :--- | :--- | :--- |
| 2026-08-28 (今天) | 🌤️ 大部晴朗 | 20.1°C ~ 30.5°C | 0.0 mm | 15.2 km/h |
| 2026-08-29 (明天) | ⛅ 局部多云 | 19.5°C ~ 28.2°C | 5.2 mm | 18.0 km/h |
| 2026-08-30 (后天) | 🌧️ 小雨 | 18.0°C ~ 24.0°C | 12.0 mm | 14.5 km/h |
```

---

## 6. Concrete Design: `WikiLookupTool` (`lib/services/tools/wiki_lookup_tool.dart`)

### 6.1 Tool Metadata & JSON Schema

- **`name`**: `wiki_lookup`
- **`displayName`**: `维基百科检索`
- **`description`**: `Search and retrieve summaries, encyclopedia descriptions, facts, and disambiguation links from Chinese and English Wikipedia.`
- **`securityLevel`**: `ToolSecurityLevel.readOnly` (Level 1)
- **Parameters**:
  - `query` (type: `string`, required: `true`, description: `The topic, concept, term, or person to look up in Wikipedia (e.g. '人工智能', '量子力学', 'Flutter', 'Albert Einstein').`)
  - `language` (type: `string`, required: `false`, enum: `['zh', 'en']`, defaultValue: `'zh'`, description: `Language edition of Wikipedia ('zh' for Chinese, 'en' for English). Default: 'zh'.`)
  - `extractLength` (type: `integer`, required: `false`, defaultValue: 1000, description: `Maximum character length of the summary extract. Default: 1000.`)

### 6.2 API Architecture & Workflow

```
[User / LLM] ---> wiki_lookup(query: "人工智能", language: "zh")
                       │
                       ▼
        1. Query Summary REST API
        GET https://zh.wikipedia.org/api/rest_v1/page/summary/人工智能
                       │
        ┌──────────────┴──────────────┐
   (HTTP 200)                    (HTTP 404 or disambiguation)
        │                                     │
   Check type                                 ▼
   ├─ type == "standard"         2. Query Search API (MediaWiki)
   │     │                       GET https://zh.wikipedia.org/w/api.php?action=query&list=search&srsearch=...
   │     ▼                                    │
   │  Format summary                          ▼
   │                             3. If top match found: fetch top match summary
   │                                If multiple disambiguations: format options list
   │                                If no results: return Chinese "未找到相关词条"
   └─────────────────────────────┬────────────┘
                                 ▼
                      ToolExecutionResult
```

### 6.3 Disambiguation & Fallback Formatting

1. **Standard Page Summary**:
   ```markdown
   ### 📚 维基百科：人工智能 (Artificial Intelligence)

   > **描述**: 由人造机器呈现的人类智能
   > **词条链接**: [查看完整词条](https://zh.wikipedia.org/wiki/%E4%BA%BA%E5%B7%A5%E6%99%BA%E8%83%BD)

   人工智能（英语：Artificial Intelligence，缩写为AI）亦称智械、机器智能，指由人制造出来的机器所表现出来的智能。通常是指通过普通计算机程序来呈现人类智能的技术...
   ```

2. **Disambiguation Page List**:
   ```markdown
   ### 📚 维基百科消歧义 / 相关词条: "苹果"

   该词条可能指代多个主题，请参考以下相关词条：
   1. **[苹果 (水果)](https://zh.wikipedia.org/wiki/苹果)**: 蔷薇科苹果属植物及其果实。
   2. **[苹果公司](https://zh.wikipedia.org/wiki/苹果公司)**: 美国跨国科技企业，主营消费电子与软件。
   3. **[苹果 (电影)](https://zh.wikipedia.org/wiki/苹果_(电影))**: 李玉导演，范冰冰主演的中国剧情电影。
   ```

---

## 7. Integration Design: `ToolRegistry.defaultRegistry()`

Update `ToolRegistry.defaultRegistry()` in `lib/services/tool_registry.dart`:

```dart
  /// Pre-populates a default registry containing built-in search, fetch, and safe basic tools.
  factory ToolRegistry.defaultRegistry({
    SearchService? searchService,
    UrlFetchService? urlFetchService,
    Dio? dio,
  }) {
    final registry = ToolRegistry();
    registry.registerTools([
      // Legacy network adapters
      WebSearchTool(searchService: searchService),
      GoogleSearchTool(searchService: searchService),
      BingSearchTool(searchService: searchService),
      UrlFetchTool(urlFetchService: urlFetchService),
      // Safe built-in tools (Milestone 23.2)
      MathEvalTool(),
      TimeCalculatorTool(),
      WeatherQueryTool(dio: dio),
      WikiLookupTool(dio: dio),
    ]);
    return registry;
  }
```

---

## 8. Test Specification: `test/services/basic_tools_test.dart`

The test suite will contain 35+ comprehensive test cases divided into 5 groups:

### 8.1 `group('MathEvalTool Tests')`
1. Basic arithmetic operations with precedence: `(3 + 5) * 2 ^ 3`, `10 + 20 / 4 - 3 * 2`, `100 % 7`.
2. Unary operators, decimals, scientific notation: `-5 + +3`, `0.1 + 0.2`, `1e3 * 2.5e-2`.
3. Trigonometric and exponential functions: `sqrt(16)`, `cbrt(27)`, `sin(pi / 2)`, `cos(0)`, `tan(pi / 4)`, `exp(1)`, `ln(e)`, `log10(100)`, `log2(8)`.
4. Statistical functions on array literals and arguments: `mean([1, 2, 3, 4, 5])`, `stddev([2, 4, 4, 4, 5, 5, 7, 9])`, `variance([1, 2, 3])`, `median([5, 1, 3])`, `mode([1, 2, 2, 3])`, `sum([10, 20, 30])`, `min([4, 2, 8])`, `max([4, 2, 8])`, `count([1, 2, 3])`.
5. Unit conversions:
   - Temperature: `convert(37, 'C', 'F')` -> 98.6, `convert(212, 'F', 'C')` -> 100.0, `convert(0, 'C', 'K')` -> 273.15.
   - Length: `convert(100, 'km', 'mi')`, `convert(1, 'mi', 'km')`, `convert(1, 'm', 'cm')`.
   - Weight: `convert(1, 'kg', 'lb')`, `convert(1000, 'g', 'kg')`.
   - Storage: `convert(1024, 'MB', 'GB')` -> 1.0, `convert(1, 'TB', 'GB')` -> 1024.0.
6. Error diagnostics:
   - Division by zero: `10 / 0` -> error `除数不能为零`.
   - Negative square root: `sqrt(-4)` -> error `负数不能在实数范围内开平方根`.
   - Non-positive logarithm: `ln(0)` -> error `对数真数必须大于零`.
   - Syntax errors: `(3 + 5 *`, `10 + + * 2` -> error `语法错误`.
   - Unknown function/constant: `foo(123)` -> error `未知函数或常量`.
   - Incompatible units: `convert(10, 'km', 'kg')` -> error `无法在不同类别单位间转换`.

### 8.2 `group('TimeCalculatorTool Tests')`
1. `now` operation for various timezones: `Asia/Shanghai`, `America/New_York`, `UTC`, `北京`, `东京`, `伦敦`, `PST`, `EST`, `JST`, `+08:00`.
2. `convert` operation between timezones: `2026-08-28 12:00:00` from `Asia/Shanghai` to `America/New_York` and `UTC`.
3. `offset` operation:
   - Positive offsets: `2026-08-28 12:00:00` + `+3d` -> `2026-08-31 12:00:00`.
   - Negative compound offsets: `2026-08-28 12:00:00` + `-5h30m` -> `2026-08-28 06:30:00`.
   - Weeks, months, years: `+1w`, `+2M`, `-1y`.
4. `duration` operation: difference between `2026-08-25 10:00:00` and `2026-08-28 14:30:00` -> `3天 4小时 30分钟 0秒`.
5. Chinese timezone alias resolution (`北京时间`, `纽约`, `东京`, `旧金山`, `伦敦`).
6. Error handling: invalid operation, invalid datetime, unknown timezone, invalid offset string.

### 8.3 `group('WeatherQueryTool Tests')`
1. Successful geocoding and forecast lookup with `MockHttpClientAdapter` for `北京`.
2. WMO code interpretation to Chinese string and icons (0 -> `晴天` ☀️, 61 -> `小雨` 🌦️, 95 -> `雷暴` ⛈️).
3. 7-day forecast parsing and table structure verification.
4. City not found handling (mock empty geocoding result).
5. Network / Dio error handling (mock 500 error and connection timeout).

### 8.4 `group('WikiLookupTool Tests')`
1. Successful summary lookup in Chinese (`zh`) for `人工智能` and English (`en`) for `Flutter`.
2. 404 summary fallback to search API and top match resolution.
3. Disambiguation page detection and option list formatting.
4. Search not found handling (mock empty search results).
5. Network / Dio error handling.

### 8.5 `group('ToolRegistry Integration Tests')`
1. Default registry initializes with all 8 tools (`web_search`, `google_search`, `bing_search`, `url_fetch`, `math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`).
2. Dispatch and execution of all 4 safe basic tools via `ToolRegistry.execute()`.
3. Security level filtering and OpenAI Schema generation for all 8 tools.

---

## 9. Quality, Safety & Compliance Verification

1. **Deterministic Execution**: Zero real network requests during unit tests; Open-Meteo and Wikipedia use mock adapters or injected Dio instances.
2. **Precision & Memory Safety**: Pure Dart recursive descent parser avoids regex vulnerabilities and stack overflow for reasonable expression depths.
3. **Chinese Localization**: All user-facing error messages, descriptions, weather codes, and time outputs adhere to standard Chinese naming conventions.
4. **Analyzer & Test Constraints**: All code must produce `0 issues` on `flutter analyze` and maintain `100% pass` on `flutter test`.
