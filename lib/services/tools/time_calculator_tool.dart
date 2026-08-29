import '../../models/tool/tool.dart';

/// Exception thrown when timezone or time calculation operations fail.
class TimeCalculatorException implements Exception {
  final String message;
  const TimeCalculatorException(this.message);

  @override
  String toString() => message;
}

/// Pure Dart timezone and datetime calculation tool.
class TimeCalculatorTool extends Tool {
  final DateTime Function()? nowProvider;

  TimeCalculatorTool({this.nowProvider});

  @override
  String get name => 'time_calculator';

  @override
  String get displayName => '时区与时间计算器';

  @override
  String get description =>
      'Calculate current time across global timezones, convert timestamps between timezones, perform relative date arithmetic (+3d, -5h30m), and calculate exact duration differences between timestamps.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.safe;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'operation',
      type: 'string',
      description:
          'The time operation to perform: "now" (current time in timezone), "convert" (convert datetime between timezones), "offset" (add/subtract relative duration), or "duration" (calculate difference between two datetimes).',
      required: true,
      enumValues: ['now', 'convert', 'offset', 'duration'],
    ),
    ToolParameter(
      name: 'timezone',
      type: 'string',
      description:
          'Target timezone name, city alias or offset (e.g. "Asia/Shanghai", "UTC", "America/New_York", "北京", "东京", "伦敦", "纽约", "PST", "EST", "CST", "JST", "GMT", "+08:00"). Default: "Asia/Shanghai".',
      required: false,
      defaultValue: 'Asia/Shanghai',
    ),
    ToolParameter(
      name: 'fromTimezone',
      type: 'string',
      description: 'Source timezone for "convert" operation (e.g. "Asia/Shanghai", "北京").',
      required: false,
    ),
    ToolParameter(
      name: 'toTimezone',
      type: 'string',
      description: 'Destination timezone for "convert" operation (e.g. "America/New_York", "纽约").',
      required: false,
    ),
    ToolParameter(
      name: 'datetime',
      type: 'string',
      description:
          'Input datetime string in ISO8601 or standard format (e.g. "2026-08-28T12:00:00", "2026-08-28 12:00:00", "2026-08-28") or Unix timestamp in seconds/milliseconds.',
      required: false,
    ),
    ToolParameter(
      name: 'offset',
      type: 'string',
      description:
          'Relative offset string to add or subtract (e.g. "+3d", "-5h30m", "+1w", "+2M", "-1y", "+45s", "+2d4h30m").',
      required: false,
    ),
    ToolParameter(
      name: 'time1',
      type: 'string',
      description: 'First datetime for "duration" calculation.',
      required: false,
    ),
    ToolParameter(
      name: 'time2',
      type: 'string',
      description: 'Second datetime for "duration" calculation.',
      required: false,
    ),
    ToolParameter(
      name: 'format',
      type: 'string',
      description: 'Output format style: "readable", "iso", or "timestamp". Default: "readable".',
      required: false,
      enumValues: ['readable', 'iso', 'timestamp'],
      defaultValue: 'readable',
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final operation = (arguments['operation'] as String? ?? 'now').trim().toLowerCase();

    try {
      final DateTime utcNow = (nowProvider != null) ? nowProvider!().toUtc() : DateTime.now().toUtc();

      switch (operation) {
        case 'now':
          return _handleNow(arguments, utcNow, stopwatch);
        case 'convert':
          return _handleConvert(arguments, utcNow, stopwatch);
        case 'offset':
          return _handleOffset(arguments, utcNow, stopwatch);
        case 'duration':
          return _handleDuration(arguments, stopwatch);
        default:
          throw TimeCalculatorException('不支持的时间计算操作: "$operation" (支持操作: now, convert, offset, duration)');
      }
    } on TimeCalculatorException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '时间计算失败: ${e.message}',
        executionDuration: stopwatch.elapsed,
        metadata: {'operation': operation},
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '时间计算异常: $e',
        content: '时间计算失败: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'operation': operation},
      );
    }
  }

  // --- Operation Handlers ---

  ToolExecutionResult _handleNow(Map<String, dynamic> arguments, DateTime utcNow, Stopwatch stopwatch) {
    final tzString = (arguments['timezone'] as String? ?? 'Asia/Shanghai').trim();
    final tzInfo = _resolveTimezone(tzString);

    final localTime = utcNow.add(Duration(minutes: tzInfo.offsetMinutes));
    final formatted = _formatDateTime(localTime);
    final iso = _formatIsoWithOffset(localTime, tzInfo.offsetMinutes);
    final weekday = _chineseWeekday(localTime.weekday);
    final offsetStr = _formatOffsetString(tzInfo.offsetMinutes);

    stopwatch.stop();

    final markdown = '''
### 🕒 当前时间 (${tzInfo.displayName})
- **标准时间**: `$formatted` ($weekday)
- **ISO 8601**: `$iso`
- **时区偏差**: `$offsetStr` (${tzInfo.canonicalName})
- **时间戳**: `${localTime.millisecondsSinceEpoch ~/ 1000}` (秒) / `${localTime.millisecondsSinceEpoch}` (毫秒)
'''.trim();

    return ToolExecutionResult.success(
      toolName: name,
      content: markdown,
      rawData: {
        'operation': 'now',
        'timezone': tzInfo.canonicalName,
        'timezoneDisplayName': tzInfo.displayName,
        'offsetMinutes': tzInfo.offsetMinutes,
        'offsetString': offsetStr,
        'datetime': formatted,
        'iso8601': iso,
        'weekday': weekday,
        'timestampSeconds': localTime.millisecondsSinceEpoch ~/ 1000,
        'timestampMs': localTime.millisecondsSinceEpoch,
      },
      executionDuration: stopwatch.elapsed,
      metadata: {'timezone': tzInfo.canonicalName},
    );
  }

  ToolExecutionResult _handleConvert(Map<String, dynamic> arguments, DateTime utcNow, Stopwatch stopwatch) {
    final fromTzStr = (arguments['fromTimezone'] as String? ?? arguments['timezone'] as String? ?? 'Asia/Shanghai').trim();
    final toTzStr = (arguments['toTimezone'] as String? ?? 'UTC').trim();
    final fromTz = _resolveTimezone(fromTzStr);
    final toTz = _resolveTimezone(toTzStr);

    final dtStr = arguments['datetime'] as String?;
    DateTime sourceLocalTime;
    if (dtStr == null || dtStr.trim().isEmpty) {
      sourceLocalTime = utcNow.add(Duration(minutes: fromTz.offsetMinutes));
    } else {
      sourceLocalTime = _parseDateTime(dtStr.trim());
    }

    // Convert source local time to UTC, then to target local time
    final sourceAsUtc = DateTime.utc(
      sourceLocalTime.year,
      sourceLocalTime.month,
      sourceLocalTime.day,
      sourceLocalTime.hour,
      sourceLocalTime.minute,
      sourceLocalTime.second,
      sourceLocalTime.millisecond,
    ).subtract(Duration(minutes: fromTz.offsetMinutes));

    final targetLocalTime = sourceAsUtc.add(Duration(minutes: toTz.offsetMinutes));

    final fromFormatted = _formatDateTime(sourceLocalTime);
    final toFormatted = _formatDateTime(targetLocalTime);
    final fromIso = _formatIsoWithOffset(sourceLocalTime, fromTz.offsetMinutes);
    final toIso = _formatIsoWithOffset(targetLocalTime, toTz.offsetMinutes);

    stopwatch.stop();

    final markdown = '''
### 🌐 时区转换结果
- **源时区 (${fromTz.displayName}, ${_formatOffsetString(fromTz.offsetMinutes)})**:
  `$fromFormatted` (${_chineseWeekday(sourceLocalTime.weekday)})
- **目标时区 (${toTz.displayName}, ${_formatOffsetString(toTz.offsetMinutes)})**:
  **`$toFormatted`** (${_chineseWeekday(targetLocalTime.weekday)})
- **ISO 8601**: `$toIso`
'''.trim();

    return ToolExecutionResult.success(
      toolName: name,
      content: markdown,
      rawData: {
        'operation': 'convert',
        'fromTimezone': fromTz.canonicalName,
        'fromOffsetMinutes': fromTz.offsetMinutes,
        'sourceDatetime': fromFormatted,
        'sourceIso8601': fromIso,
        'toTimezone': toTz.canonicalName,
        'toOffsetMinutes': toTz.offsetMinutes,
        'targetDatetime': toFormatted,
        'targetIso8601': toIso,
        'timestampMs': sourceAsUtc.millisecondsSinceEpoch,
      },
      executionDuration: stopwatch.elapsed,
      metadata: {'from': fromTz.canonicalName, 'to': toTz.canonicalName},
    );
  }

  ToolExecutionResult _handleOffset(Map<String, dynamic> arguments, DateTime utcNow, Stopwatch stopwatch) {
    final tzStr = (arguments['timezone'] as String? ?? 'Asia/Shanghai').trim();
    final tzInfo = _resolveTimezone(tzStr);

    final offsetStr = (arguments['offset'] as String? ?? '').trim();
    if (offsetStr.isEmpty) {
      throw const TimeCalculatorException('操作 "offset" 缺少必需的 "offset" 参数 (例如: "+3d", "-5h30m", "+1w")');
    }

    final dtStr = arguments['datetime'] as String?;
    DateTime baseLocalTime;
    if (dtStr == null || dtStr.trim().isEmpty) {
      baseLocalTime = utcNow.add(Duration(minutes: tzInfo.offsetMinutes));
    } else {
      baseLocalTime = _parseDateTime(dtStr.trim());
    }

    final resultLocalTime = _applyOffset(baseLocalTime, offsetStr);

    final baseFormatted = _formatDateTime(baseLocalTime);
    final resultFormatted = _formatDateTime(resultLocalTime);
    final resultIso = _formatIsoWithOffset(resultLocalTime, tzInfo.offsetMinutes);

    stopwatch.stop();

    final markdown = '''
### ⏳ 时间偏移计算
- **基准时间**: `$baseFormatted` (${tzInfo.displayName})
- **偏移量**: `$offsetStr`
- **计算结果**: **`$resultFormatted`** (${_chineseWeekday(resultLocalTime.weekday)})
- **ISO 8601**: `$resultIso`
'''.trim();

    return ToolExecutionResult.success(
      toolName: name,
      content: markdown,
      rawData: {
        'operation': 'offset',
        'timezone': tzInfo.canonicalName,
        'baseDatetime': baseFormatted,
        'offset': offsetStr,
        'resultDatetime': resultFormatted,
        'resultIso8601': resultIso,
        'resultTimestampMs': resultLocalTime.millisecondsSinceEpoch,
      },
      executionDuration: stopwatch.elapsed,
      metadata: {'offset': offsetStr},
    );
  }

  ToolExecutionResult _handleDuration(Map<String, dynamic> arguments, Stopwatch stopwatch) {
    final time1Str = (arguments['time1'] as String? ?? '').trim();
    final time2Str = (arguments['time2'] as String? ?? '').trim();

    if (time1Str.isEmpty || time2Str.isEmpty) {
      throw const TimeCalculatorException('操作 "duration" 需要提供 "time1" 和 "time2" 参数');
    }

    final dt1 = _parseDateTime(time1Str);
    final dt2 = _parseDateTime(time2Str);

    final diff = dt2.difference(dt1);
    final isNegative = diff.isNegative;
    final absDiff = diff.abs();

    final totalSeconds = absDiff.inSeconds;
    final totalMinutes = absDiff.inMinutes;
    final totalHours = absDiff.inHours;
    final totalDays = absDiff.inDays;
    final totalMs = absDiff.inMilliseconds;

    // Natural breakdown
    final days = absDiff.inDays;
    final hours = absDiff.inHours % 24;
    final minutes = absDiff.inMinutes % 60;
    final seconds = absDiff.inSeconds % 60;

    final parts = <String>[];
    if (days > 0) parts.add('$days天');
    if (hours > 0) parts.add('$hours小时');
    if (minutes > 0) parts.add('$minutes分钟');
    if (seconds > 0 || parts.isEmpty) parts.add('$seconds秒');

    final naturalText = (isNegative ? '负 ' : '') + parts.join(' ');

    stopwatch.stop();

    final markdown = '''
### ⏱️ 时间间隔计算
- **时间 1**: `${_formatDateTime(dt1)}`
- **时间 2**: `${_formatDateTime(dt2)}`
- **时间差**: **`$naturalText`**
- **详细统计**:
  - 总天数: `${isNegative ? -totalDays : totalDays}` 天
  - 总小时: `${isNegative ? -totalHours : totalHours}` 小时
  - 总分钟: `${isNegative ? -totalMinutes : totalMinutes}` 分钟
  - 总秒数: `${isNegative ? -totalSeconds : totalSeconds}` 秒
'''.trim();

    return ToolExecutionResult.success(
      toolName: name,
      content: markdown,
      rawData: {
        'operation': 'duration',
        'time1': _formatDateTime(dt1),
        'time2': _formatDateTime(dt2),
        'differenceText': naturalText,
        'isNegative': isNegative,
        'days': days,
        'hours': hours,
        'minutes': minutes,
        'seconds': seconds,
        'totalDays': isNegative ? -totalDays : totalDays,
        'totalHours': isNegative ? -totalHours : totalHours,
        'totalMinutes': isNegative ? -totalMinutes : totalMinutes,
        'totalSeconds': isNegative ? -totalSeconds : totalSeconds,
        'totalMilliseconds': isNegative ? -totalMs : totalMs,
      },
      executionDuration: stopwatch.elapsed,
      metadata: {'time1': time1Str, 'time2': time2Str},
    );
  }

  // --- Parsing & Formatting Helpers ---

  static DateTime _parseDateTime(String str) {
    // 1. Check if numeric timestamp
    final numVal = num.tryParse(str);
    if (numVal != null) {
      if (str.length >= 12) {
        // Milliseconds timestamp
        return DateTime.fromMillisecondsSinceEpoch(numVal.toInt(), isUtc: true);
      } else {
        // Seconds timestamp
        return DateTime.fromMillisecondsSinceEpoch((numVal * 1000).toInt(), isUtc: true);
      }
    }

    // 2. Standard ISO8601 or yyyy-MM-dd HH:mm:ss format
    final normalized = str.replaceAll('/', '-');
    final parsed = DateTime.tryParse(normalized);
    if (parsed != null) {
      return parsed;
    }

    // 3. Fallback date only regex (yyyy-MM-dd)
    final dateOnlyMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(normalized);
    if (dateOnlyMatch != null) {
      final y = int.parse(dateOnlyMatch.group(1)!);
      final m = int.parse(dateOnlyMatch.group(2)!);
      final d = int.parse(dateOnlyMatch.group(3)!);
      return DateTime(y, m, d);
    }

    // 4. Datetime with space (yyyy-MM-dd HH:mm:ss)
    final dtMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})[\sT](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(normalized);
    if (dtMatch != null) {
      final y = int.parse(dtMatch.group(1)!);
      final m = int.parse(dtMatch.group(2)!);
      final d = int.parse(dtMatch.group(3)!);
      final h = int.parse(dtMatch.group(4)!);
      final min = int.parse(dtMatch.group(5)!);
      final s = dtMatch.group(6) != null ? int.parse(dtMatch.group(6)!) : 0;
      return DateTime(y, m, d, h, min, s);
    }

    throw TimeCalculatorException('无法解析时间格式: "$str" (支持格式: "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", ISO8601, 时间戳)');
  }

  static DateTime _applyOffset(DateTime base, String offsetStr) {
    // Matches patterns like +3d, -5h, +1w, +2M, -1y, +30m, -45s, or compound +3d5h20m / -5h30m
    final tokenRegex = RegExp(r'([+-]?\d+)\s*([a-zA-Z\u4e00-\u9fa5]+)');
    final matches = tokenRegex.allMatches(offsetStr).toList();

    if (matches.isEmpty) {
      throw TimeCalculatorException('无法解析相对偏移量: "$offsetStr" (示例: "+3d", "-5h30m", "+1w", "+2M", "-1y")');
    }

    final overallNegative = offsetStr.trim().startsWith('-');
    DateTime current = base;

    for (final match in matches) {
      final rawNumStr = match.group(1)!;
      final rawVal = int.tryParse(rawNumStr);
      final rawUnit = match.group(2)!;

      if (rawVal == null) {
        throw TimeCalculatorException('偏移量数值无效: "$rawNumStr"');
      }

      int value = rawVal;
      final hasExplicitSign = rawNumStr.startsWith('+') || rawNumStr.startsWith('-');
      if (!hasExplicitSign && overallNegative) {
        value = -rawVal;
      }

      final unitLower = rawUnit.toLowerCase();

      if (rawUnit == 'M' || unitLower == 'mo' || unitLower == 'mon' || unitLower == 'month' || unitLower == 'months' || rawUnit == '月') {
        current = _addMonths(current, value);
      } else if (rawUnit == 'm' || unitLower == 'min' || unitLower == 'minute' || unitLower == 'minutes' || rawUnit == '分' || rawUnit == '分钟') {
        current = current.add(Duration(minutes: value));
      } else if (unitLower == 'y' || unitLower == 'year' || unitLower == 'years' || rawUnit == '年') {
        current = _addYears(current, value);
      } else if (unitLower == 'w' || unitLower == 'week' || unitLower == 'weeks' || rawUnit == '周' || rawUnit == '星期') {
        current = current.add(Duration(days: value * 7));
      } else if (unitLower == 'd' || unitLower == 'day' || unitLower == 'days' || rawUnit == '天' || rawUnit == '日') {
        current = current.add(Duration(days: value));
      } else if (unitLower == 'h' || unitLower == 'hr' || unitLower == 'hour' || unitLower == 'hours' || rawUnit == '小时' || rawUnit == '时') {
        current = current.add(Duration(hours: value));
      } else if (unitLower == 's' || unitLower == 'sec' || unitLower == 'second' || unitLower == 'seconds' || rawUnit == '秒') {
        current = current.add(Duration(seconds: value));
      } else {
        throw TimeCalculatorException('未知的偏移量单位: "$rawUnit" (支持单位: y, M, w, d, h, m/min, s)');
      }
    }

    return current;
  }

  static DateTime _addYears(DateTime dt, int years) {
    final targetYear = dt.year + years;
    final targetMonth = dt.month;
    final maxDays = _daysInMonth(targetYear, targetMonth);
    final targetDay = dt.day > maxDays ? maxDays : dt.day;
    return DateTime(targetYear, targetMonth, targetDay, dt.hour, dt.minute, dt.second, dt.millisecond);
  }

  static DateTime _addMonths(DateTime dt, int months) {
    int totalMonths = dt.year * 12 + (dt.month - 1) + months;
    int targetYear = totalMonths ~/ 12;
    int targetMonth = (totalMonths % 12) + 1;
    final maxDays = _daysInMonth(targetYear, targetMonth);
    final targetDay = dt.day > maxDays ? maxDays : dt.day;
    return DateTime(targetYear, targetMonth, targetDay, dt.hour, dt.minute, dt.second, dt.millisecond);
  }

  static int _daysInMonth(int year, int month) {
    if (month == 2) {
      final isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
      return isLeap ? 29 : 28;
    }
    const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return days[month - 1];
  }

  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  static String _formatIsoWithOffset(DateTime dt, int offsetMinutes) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final offsetStr = _formatOffsetString(offsetMinutes);
    return '$y-$m-${d}T$h:$min:$s$offsetStr';
  }

  static String _formatOffsetString(int offsetMinutes) {
    final sign = offsetMinutes >= 0 ? '+' : '-';
    final absMinutes = offsetMinutes.abs();
    final h = (absMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (absMinutes % 60).toString().padLeft(2, '0');
    return '$sign$h:$m';
  }

  static String _chineseWeekday(int weekday) {
    const days = ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    if (weekday >= 1 && weekday <= 7) return days[weekday];
    return '';
  }

  // --- Timezone Resolution ---

  static _TimezoneInfo _resolveTimezone(String raw) {
    final trimmed = raw.trim();
    final lower = trimmed.toLowerCase();

    // 1. Direct offset format (e.g. UTC+8, +08:00, -05:00, +8, -5)
    final offsetMatch = RegExp(r'^(?:utc|gmt)?\s*([+-])\s*(\d{1,2})(?::?(\d{2}))?$', caseSensitive: false).firstMatch(trimmed);
    if (offsetMatch != null) {
      final sign = offsetMatch.group(1) == '-' ? -1 : 1;
      final hours = int.parse(offsetMatch.group(2)!);
      final minutes = offsetMatch.group(3) != null ? int.parse(offsetMatch.group(3)!) : 0;
      final totalMinutes = sign * (hours * 60 + minutes);
      return _TimezoneInfo(
        canonicalName: 'UTC${_formatOffsetString(totalMinutes)}',
        displayName: 'UTC${_formatOffsetString(totalMinutes)}',
        offsetMinutes: totalMinutes,
      );
    }

    // 2. Check alias map
    final mappedName = _timezoneAliases[lower] ?? _timezoneAliases[trimmed] ?? trimmed;
    final mappedLower = mappedName.toLowerCase();

    // 3. Check canonical offset map
    final offset = _timezoneOffsetsInMinutes[mappedLower];
    if (offset != null) {
      return _TimezoneInfo(
        canonicalName: mappedName,
        displayName: trimmed,
        offsetMinutes: offset,
      );
    }

    throw TimeCalculatorException('未知时区或无法解析时区: "$raw" (支持时区如: "Asia/Shanghai", "UTC", "北京", "纽约", "东京", "伦敦", "+08:00")');
  }

  static const Map<String, int> _timezoneOffsetsInMinutes = {
    // Asia
    'asia/shanghai': 480, 'asia/beijing': 480, 'asia/chongqing': 480,
    'asia/hong_kong': 480, 'asia/taipei': 480, 'asia/singapore': 480,
    'asia/tokyo': 540, 'asia/seoul': 540, 'asia/bangkok': 420,
    'asia/dubai': 240, 'asia/kolkata': 330, 'asia/calcutta': 330,
    'asia/jakarta': 420, 'asia/manila': 480, 'asia/kuala_lumpur': 480,
    // Europe
    'europe/london': 0, 'europe/paris': 60, 'europe/berlin': 60,
    'europe/rome': 60, 'europe/madrid': 60, 'europe/amsterdam': 60,
    'europe/moscow': 180, 'europe/zurich': 60, 'europe/athens': 120,
    // America
    'america/new_york': -300, 'america/chicago': -360, 'america/denver': -420,
    'america/los_angeles': -480, 'america/toronto': -300, 'america/vancouver': -480,
    'america/sao_paulo': -180, 'america/mexico_city': -360, 'america/buenos_aires': -180,
    // Australia & Pacific
    'australia/sydney': 600, 'australia/melbourne': 600, 'australia/perth': 480,
    'australia/brisbane': 600, 'australia/adelaide': 570,
    'pacific/auckland': 720, 'pacific/honolulu': -600, 'pacific/fiji': 720,
    // UTC / GMT
    'utc': 0, 'gmt': 0,
  };

  static const Map<String, String> _timezoneAliases = {
    // Chinese aliases
    '北京': 'Asia/Shanghai', '北京时间': 'Asia/Shanghai', '中国': 'Asia/Shanghai', '中国标准时间': 'Asia/Shanghai',
    '上海': 'Asia/Shanghai', '香港': 'Asia/Hong_Kong', '台北': 'Asia/Taipei', '台湾': 'Asia/Taipei',
    '东京': 'Asia/Tokyo', '日本': 'Asia/Tokyo', '首尔': 'Asia/Seoul', '韩国': 'Asia/Seoul',
    '新加坡': 'Asia/Singapore', '曼谷': 'Asia/Bangkok', '迪拜': 'Asia/Dubai',
    '伦敦': 'Europe/London', '英国': 'Europe/London', '格林威治': 'UTC',
    '巴黎': 'Europe/Paris', '法国': 'Europe/Paris', '柏林': 'Europe/Berlin', '德国': 'Europe/Berlin',
    '罗马': 'Europe/Rome', '马德里': 'Europe/Madrid', '阿姆斯特丹': 'Europe/Amsterdam',
    '莫斯科': 'Europe/Moscow', '俄罗斯': 'Europe/Moscow',
    '纽约': 'America/New_York', '华盛顿': 'America/New_York', '美东': 'America/New_York',
    '芝加哥': 'America/Chicago', '美中': 'America/Chicago', '休斯顿': 'America/Chicago',
    '丹佛': 'America/Denver', '洛杉矶': 'America/Los_Angeles', '旧金山': 'America/Los_Angeles',
    '硅谷': 'America/Los_Angeles', '西雅图': 'America/Los_Angeles', '美西': 'America/Los_Angeles',
    '悉尼': 'Australia/Sydney', '墨尔本': 'Australia/Melbourne', '布里斯班': 'Australia/Brisbane',
    '奥克兰': 'Pacific/Auckland', '新西兰': 'Pacific/Auckland', '夏威夷': 'Pacific/Honolulu',
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
}

class _TimezoneInfo {
  final String canonicalName;
  final String displayName;
  final int offsetMinutes;

  const _TimezoneInfo({
    required this.canonicalName,
    required this.displayName,
    required this.offsetMinutes,
  });
}
