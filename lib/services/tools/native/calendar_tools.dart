import '../../../models/native/native_models.dart';
import '../../../models/tool/tool.dart';
import '../../native/calendar_service.dart';
import '../../native/permission_manager_service.dart';

/// Calendar query tool [Level 3 Privileged].
///
/// Queries calendar events in a specified time window and/or keyword match,
/// checking [AppPermission.calendar] permission beforehand.
class CalendarQueryEventsTool extends Tool {
  final ICalendarService calendarService;
  final PermissionManagerService permissionService;

  CalendarQueryEventsTool({
    ICalendarService? calendarService,
    PermissionManagerService? permissionService,
  })  : calendarService = calendarService ?? InMemoryCalendarService(seedDefaults: false),
        permissionService = permissionService ?? PermissionManagerService();

  @override
  String get name => 'calendar_query_events';

  @override
  String get displayName => '查询日程';

  @override
  String get description =>
      'Queries calendar events within a specified time range or keyword. Checks calendar permission and returns formatted event list with conflict detection.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.privilegedNative;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'start_time',
          type: 'string',
          description: '查询起始时间或目标日期 (ISO 8601 格式，如 "2026-09-05T00:00:00Z" 或日期 "2026-09-05")',
          required: false,
        ),
        ToolParameter(
          name: 'end_time',
          type: 'string',
          description: '查询结束时间 (ISO 8601 格式，如 "2026-09-05T23:59:59Z" 或日期 "2026-09-05")',
          required: false,
        ),
        ToolParameter(
          name: 'query',
          type: 'string',
          description: '日程关键词过滤 (可选，匹配标题、地点或描述备注)',
          required: false,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    // 1. Permission check
    final hasPermission = await permissionService.hasPermission(AppPermission.calendar);
    if (!hasPermission) {
      stopwatch.stop();
      final errorMsg = permissionService.getRejectionErrorMessage(AppPermission.calendar);
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: errorMsg,
        content: errorMsg,
        executionDuration: stopwatch.elapsed,
        rawData: {'permission': 'calendar', 'granted': false},
      );
    }

    try {
      DateTime? startTime;
      final rawStart = arguments['start_time']?.toString().trim() ??
          arguments['date']?.toString().trim() ??
          arguments['start_date']?.toString().trim() ??
          arguments['day']?.toString().trim() ??
          arguments['time']?.toString().trim();
      if (rawStart != null && rawStart.isNotEmpty) {
        startTime = _parseFlexibleDateTime(rawStart);
      }

      DateTime? endTime;
      final rawEnd = arguments['end_time']?.toString().trim() ??
          arguments['end_date']?.toString().trim();
      if (rawEnd != null && rawEnd.isNotEmpty) {
        endTime = _parseFlexibleDateTime(rawEnd, isEnd: true);
      } else if (startTime != null && rawStart != null && _isDateOnly(rawStart)) {
        // If query was for a specific date (e.g. "2026-09-05"), auto-bound the whole day
        endTime = DateTime(startTime.year, startTime.month, startTime.day, 23, 59, 59, 999);
      }

      final rawQuery = arguments['query']?.toString().trim();
      // If query is generic like '会议', '日程', '安排', '全部', '所有', do not restrict by literal keyword
      final isGeneric = rawQuery != null &&
          const {'会议', '日程', '安排', '全部', '所有', 'meeting', 'meetings', 'events', 'schedule'}
              .contains(rawQuery.toLowerCase());
      final query = isGeneric ? null : rawQuery;

      final events = await calendarService.queryEvents(
        startTime: startTime,
        endTime: endTime,
        query: (query != null && query.isNotEmpty) ? query : null,
      );

      stopwatch.stop();

      final buffer = StringBuffer();
      if (events.isEmpty) {
        buffer.writeln('📅 **日历日程查询结果**');
        buffer.writeln('在指定的时间范围及条件下未找到任何日程安排。');
      } else {
        buffer.writeln('📅 **日历日程查询结果** (共找到 ${events.length} 项日程)：\n');
        for (final ev in events) {
          buffer.writeln(ev.toMarkdown());
          buffer.writeln();
        }
      }

      return ToolExecutionResult.success(
        toolName: name,
        content: buffer.toString().trimRight(),
        rawData: {
          'count': events.length,
          'events': events.map((e) => e.toJson()).toList(),
          'startTime': startTime?.toIso8601String(),
          'endTime': endTime?.toIso8601String(),
          'query': query,
        },
        executionDuration: stopwatch.elapsed,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '查询日历日程发生异常: $e',
        content: '查询日历日程发生异常: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'exception': e.toString(), 'stackTrace': stackTrace.toString()},
      );
    }
  }
}

/// Calendar event creation tool [Level 3 Privileged + HITL].
///
/// Creates a new calendar event with conflict detection,
/// checking [AppPermission.calendar] permission beforehand.
class CalendarCreateEventTool extends Tool {
  final ICalendarService calendarService;
  final PermissionManagerService permissionService;

  CalendarCreateEventTool({
    ICalendarService? calendarService,
    PermissionManagerService? permissionService,
  })  : calendarService = calendarService ?? InMemoryCalendarService(seedDefaults: false),
        permissionService = permissionService ?? PermissionManagerService();

  @override
  String get name => 'calendar_create_event';

  @override
  String get displayName => '创建日程';

  @override
  String get description =>
      'Creates a new calendar event with title, start_time, end_time, optional location, description, and reminder minutes. Checks for schedule conflicts.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.privilegedNative;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'title',
          type: 'string',
          description: '日程标题/主题 (如 "团队周例会", "产品技术方案评审")',
          required: true,
        ),
        ToolParameter(
          name: 'start_time',
          type: 'string',
          description: '日程起始时间 (ISO 8601 格式，或自然时间如 "明天 10:00", "今天下午3点")',
          required: true,
        ),
        ToolParameter(
          name: 'end_time',
          type: 'string',
          description: '日程结束时间 (ISO 8601 格式，如 "2026-09-05T11:00:00Z" 或自然时间)',
          required: true,
        ),
        ToolParameter(
          name: 'location',
          type: 'string',
          description: '日程地点或线上会议链接 (可选)',
          required: false,
        ),
        ToolParameter(
          name: 'description',
          type: 'string',
          description: '日程详细说明、会议议程或备注 (可选)',
          required: false,
        ),
        ToolParameter(
          name: 'reminder_minutes',
          type: 'integer',
          description: '提前提醒分钟数 (默认 15 分钟)',
          required: false,
          defaultValue: 15,
        ),
        ToolParameter(
          name: 'is_all_day',
          type: 'boolean',
          description: '是否为全天日程 (默认为 false)',
          required: false,
          defaultValue: false,
        ),
      ];

  @override
  String? validateArguments(Map<String, dynamic> arguments) {
    final action = arguments['action']?.toString().trim().toLowerCase();
    final deleteId = (arguments['delete_id'] ?? arguments['event_id'])?.toString().trim();
    if (action == 'delete' || action == 'cancel' || (deleteId != null && deleteId.isNotEmpty)) {
      final idToRemove = (deleteId != null && deleteId.isNotEmpty) ? deleteId : arguments['id']?.toString().trim();
      final titleToRemove = arguments['title']?.toString().trim() ?? arguments['query']?.toString().trim();
      if ((idToRemove == null || idToRemove.isEmpty) && (titleToRemove == null || titleToRemove.isEmpty)) {
        return "取消或删除日程请提供日程 ID (event_id) 或标题关键词 (title)";
      }
      return null;
    }
    for (final param in parameters) {
      if (param.name == 'end_time' && (arguments['end_time'] == null || arguments['end_time'].toString().trim().isEmpty)) {
        continue;
      }
      final value = arguments[param.name];
      final error = param.validate(value);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    // 1. Permission check
    final hasPermission = await permissionService.hasPermission(AppPermission.calendar);
    if (!hasPermission) {
      stopwatch.stop();
      final errorMsg = permissionService.getRejectionErrorMessage(AppPermission.calendar);
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: errorMsg,
        content: errorMsg,
        executionDuration: stopwatch.elapsed,
        rawData: {'permission': 'calendar', 'granted': false},
      );
    }

    try {
      final action = arguments['action']?.toString().trim().toLowerCase();
      final deleteId = (arguments['delete_id'] ?? arguments['event_id'])?.toString().trim();
      if (action == 'delete' || action == 'cancel' || (deleteId != null && deleteId.isNotEmpty)) {
        final idToRemove = (deleteId != null && deleteId.isNotEmpty) ? deleteId : arguments['id']?.toString().trim();
        if (idToRemove != null && idToRemove.isNotEmpty) {
          final removed = await calendarService.deleteEvent(idToRemove);
          stopwatch.stop();
          if (removed) {
            return ToolExecutionResult.success(
              toolName: name,
              content: '✅ **日程已成功取消/删除** (事件ID: `$idToRemove`)',
              rawData: {'eventId': idToRemove, 'deleted': true},
              executionDuration: stopwatch.elapsed,
            );
          } else {
            return ToolExecutionResult.success(
              toolName: name,
              content: 'ℹ️ **未找到待删除日程**：ID 为 `$idToRemove` 的日程不存在。',
              rawData: {'eventId': idToRemove, 'deleted': false, 'found': false},
              executionDuration: stopwatch.elapsed,
            );
          }
        }

        final titleKeyword = arguments['title']?.toString().trim() ?? arguments['query']?.toString().trim();
        if (titleKeyword != null && titleKeyword.isNotEmpty) {
          final matched = await calendarService.queryEvents(query: titleKeyword);
          if (matched.isNotEmpty) {
            final target = matched.first;
            await calendarService.deleteEvent(target.id);
            stopwatch.stop();
            return ToolExecutionResult.success(
              toolName: name,
              content: '✅ **日程已成功取消/删除**: "${target.title}" (事件ID: `${target.id}`)',
              rawData: {'eventId': target.id, 'title': target.title, 'deleted': true},
              executionDuration: stopwatch.elapsed,
            );
          } else {
            stopwatch.stop();
            return ToolExecutionResult.success(
              toolName: name,
              content: 'ℹ️ **未找到待删除日程**：未找到与 "$titleKeyword" 相关的日程安排。',
              rawData: {'query': titleKeyword, 'deleted': false, 'found': false},
              executionDuration: stopwatch.elapsed,
            );
          }
        }
      }

      final title = arguments['title']?.toString().trim() ?? '';
      if (title.isEmpty) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '日程标题不能为空',
          content: '创建日程失败: 缺少有效的日程标题 (title)',
          executionDuration: stopwatch.elapsed,
        );
      }

      final rawStart = arguments['start_time']?.toString().trim() ?? '';
      final startTime = _parseFlexibleDateTime(rawStart);
      if (startTime == null) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '无效的起始时间格式: "$rawStart"',
          content: '创建日程失败: 起始时间格式无效，请提供合法的 ISO 8601 时间格式 (例如 "2026-08-30T14:00:00Z")',
          executionDuration: stopwatch.elapsed,
        );
      }

      final rawEnd = arguments['end_time']?.toString().trim() ?? '';
      DateTime? endTime;
      if (rawEnd.isNotEmpty) {
        endTime = _parseFlexibleDateTime(rawEnd, isEnd: true);
        if (endTime == null) {
          stopwatch.stop();
          return ToolExecutionResult.failure(
            toolName: name,
            errorMessage: '无效的结束时间格式: "$rawEnd"',
            content: '创建日程失败: 结束时间格式无效，请提供合法的 ISO 8601 时间格式 (例如 "2026-08-30T15:30:00Z")',
            executionDuration: stopwatch.elapsed,
          );
        }
      } else {
        // Default to 1 hour after start
        final durationMinutes = (arguments['duration_minutes'] as num?)?.toInt() ?? 60;
        endTime = startTime.add(Duration(minutes: durationMinutes));
      }

      if (startTime.isAfter(endTime)) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '日程起始时间不能晚于结束时间',
          content: '创建日程失败: 起始时间 ($rawStart) 晚于结束时间 ($rawEnd)',
          executionDuration: stopwatch.elapsed,
        );
      }

      final location = arguments['location']?.toString().trim();
      final description = arguments['description']?.toString().trim();
      final reminderMinutes = (arguments['reminder_minutes'] as num?)?.toInt() ??
          (arguments['remind_minutes_before'] as num?)?.toInt() ??
          15;
      final isAllDay = arguments['is_all_day'] as bool? ?? false;

      // 2. Conflict detection
      final conflicts = await calendarService.checkConflict(startTime, endTime);

      // 3. Create event
      final event = CalendarEvent(
        title: title,
        startTime: startTime,
        endTime: endTime,
        location: (location != null && location.isNotEmpty) ? location : null,
        description: (description != null && description.isNotEmpty) ? description : null,
        reminderMinutes: reminderMinutes,
        isAllDay: isAllDay,
      );

      final createdEvent = await calendarService.createEvent(event);
      stopwatch.stop();

      final buffer = StringBuffer();
      buffer.writeln('✅ **日程创建成功**\n');
      buffer.writeln(createdEvent.toMarkdown());

      if (conflicts.isNotEmpty) {
        buffer.writeln('\n⚠️ **时间冲突提醒**：该时间段与以下 ${conflicts.length} 个现有日程存在冲突：');
        for (final c in conflicts) {
          buffer.writeln('  - **${c.title}** (${c.toTimeRangeString()})');
        }
      }

      return ToolExecutionResult.success(
        toolName: name,
        content: buffer.toString().trimRight(),
        rawData: {
          'created': createdEvent.toJson(),
          'hasConflict': conflicts.isNotEmpty,
          'conflictCount': conflicts.length,
          'conflicts': conflicts.map((c) => c.toJson()).toList(),
        },
        executionDuration: stopwatch.elapsed,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '创建日历日程发生异常: $e',
        content: '创建日历日程发生异常: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'exception': e.toString(), 'stackTrace': stackTrace.toString()},
      );
    }
  }
}

bool _isDateOnly(String input) {
  final trimmed = input.trim();
  return RegExp(r'^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}$').hasMatch(trimmed) ||
      RegExp(r'^(?:今天|今日|明天|次日|后天|大后天|昨天|today|tomorrow)$', caseSensitive: false).hasMatch(trimmed) ||
      RegExp(r'^\d{4}年\d{1,2}月\d{1,2}[日号]?$').hasMatch(trimmed);
}

DateTime? _parseFlexibleDateTime(String input, {bool isEnd = false}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final now = DateTime.now();

  // 1. Relative duration: "10分钟后", "1小时后", "半小时后"
  if (trimmed == '半小时后' || trimmed == '30分钟后') {
    return now.add(const Duration(minutes: 30));
  }
  final minDurMatch = RegExp(r'^(\d+)\s*(?:分钟|分|mins?|minutes?)(?:后)?$', caseSensitive: false).firstMatch(trimmed);
  if (minDurMatch != null) {
    final m = int.tryParse(minDurMatch.group(1)!);
    if (m != null) return now.add(Duration(minutes: m));
  }
  final hrDurMatch = RegExp(r'^(\d+)\s*(?:小时|点钟|hours?|hrs?)(?:后)?$', caseSensitive: false).firstMatch(trimmed);
  if (hrDurMatch != null) {
    final h = int.tryParse(hrDurMatch.group(1)!);
    if (h != null) return now.add(Duration(hours: h));
  }

  // 2. Relative date keyword + optional time (e.g. "明天 10:00", "明天上午10点", "今天", "后天下午3点半")
  DateTime? baseDate;
  String remainingTimeStr = '';

  final relDateMatch = RegExp(
    r'^(今天|今日|明天|次日|后天|大后天|昨天|today|tomorrow)\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(trimmed);

  if (relDateMatch != null) {
    final kw = relDateMatch.group(1)!.toLowerCase();
    remainingTimeStr = relDateMatch.group(2)?.trim() ?? '';

    switch (kw) {
      case '今天':
      case '今日':
      case 'today':
        baseDate = DateTime(now.year, now.month, now.day);
        break;
      case '明天':
      case '次日':
      case 'tomorrow':
        baseDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        break;
      case '后天':
        baseDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 2));
        break;
      case '大后天':
        baseDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 3));
        break;
      case '昨天':
      case 'yesterday':
        baseDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
        break;
    }

    if (baseDate != null) {
      if (remainingTimeStr.isEmpty) {
        return isEnd
            ? DateTime(baseDate.year, baseDate.month, baseDate.day, 23, 59, 59, 999)
            : DateTime(baseDate.year, baseDate.month, baseDate.day, 0, 0, 0);
      }
      final parsedTime = _parseTimeOnDate(baseDate, remainingTimeStr);
      if (parsedTime != null) return parsedTime;
    }
  }

  // 3. Chinese date with 年月日 (e.g. "2026年9月5日 14:00" or "9月5日 10:00")
  final cnDateFullMatch = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})[日号]?\s*(.*)$').firstMatch(trimmed);
  if (cnDateFullMatch != null) {
    final y = int.parse(cnDateFullMatch.group(1)!);
    final m = int.parse(cnDateFullMatch.group(2)!);
    final d = int.parse(cnDateFullMatch.group(3)!);
    final rest = cnDateFullMatch.group(4)?.trim() ?? '';
    final base = DateTime(y, m, d);
    if (rest.isEmpty) {
      return isEnd ? DateTime(y, m, d, 23, 59, 59, 999) : base;
    }
    final parsedTime = _parseTimeOnDate(base, rest);
    if (parsedTime != null) return parsedTime;
  }

  final cnDateShortMatch = RegExp(r'^(\d{1,2})月(\d{1,2})[日号]?\s*(.*)$').firstMatch(trimmed);
  if (cnDateShortMatch != null) {
    final y = now.year;
    final m = int.parse(cnDateShortMatch.group(1)!);
    final d = int.parse(cnDateShortMatch.group(2)!);
    final rest = cnDateShortMatch.group(3)?.trim() ?? '';
    final base = DateTime(y, m, d);
    if (rest.isEmpty) {
      return isEnd ? DateTime(y, m, d, 23, 59, 59, 999) : base;
    }
    final parsedTime = _parseTimeOnDate(base, rest);
    if (parsedTime != null) return parsedTime;
  }

  // 4. Standard ISO parsing
  final parsed = DateTime.tryParse(trimmed);
  if (parsed != null) {
    if (_isDateOnly(trimmed)) {
      return isEnd
          ? DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59, 999)
          : DateTime(parsed.year, parsed.month, parsed.day, 0, 0, 0);
    }
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  // 5. Handle YYYY/MM/DD or YYYY.MM.DD or space delimited datetime
  var normalized = trimmed.replaceAll('/', '-').replaceAll('.', '-');
  if (normalized.contains(' ') && !normalized.contains('T')) {
    normalized = normalized.replaceFirst(' ', 'T');
  }
  final parsedNorm = DateTime.tryParse(normalized);
  if (parsedNorm != null) {
    if (_isDateOnly(normalized)) {
      return isEnd
          ? DateTime(parsedNorm.year, parsedNorm.month, parsedNorm.day, 23, 59, 59, 999)
          : DateTime(parsedNorm.year, parsedNorm.month, parsedNorm.day, 0, 0, 0);
    }
    return parsedNorm.isUtc ? parsedNorm.toLocal() : parsedNorm;
  }

  // 6. Standalone time string (e.g. "14:00", "下午3点", "上午10点半") defaulting to today
  final standaloneTime = _parseTimeOnDate(DateTime(now.year, now.month, now.day), trimmed);
  if (standaloneTime != null) {
    return standaloneTime;
  }

  return null;
}

DateTime? _parseTimeOnDate(DateTime base, String timeStr) {
  final s = timeStr.trim();
  if (s.isEmpty) return null;

  // Check AM/PM indicators
  final isPm = s.contains('下午') || s.contains('晚上') || s.contains('傍晚') || s.contains('夜间') || s.toLowerCase().contains('pm');
  final isAm = s.contains('上午') || s.contains('早上') || s.contains('早晨') || s.contains('清晨') || s.toLowerCase().contains('am');

  final cleanTime = s
      .replaceAll(RegExp(r'(?:上午|下午|早上|早晨|清晨|晚上|傍晚|夜间|am|pm)', caseSensitive: false), '')
      .trim();

  // Pattern: "14:30" or "14:30:00"
  final colonMatch = RegExp(r'^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(cleanTime);
  if (colonMatch != null) {
    var hour = int.parse(colonMatch.group(1)!);
    final minute = int.parse(colonMatch.group(2)!);
    final second = colonMatch.group(3) != null ? int.parse(colonMatch.group(3)!) : 0;
    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;
    return DateTime(base.year, base.month, base.day, hour, minute, second);
  }

  // Pattern: "10点30分", "10点半", "10点", "10时"
  final cnTimeMatch = RegExp(r'^(\d{1,2})\s*(?:点|时)\s*(?:(\d{1,2})\s*分?|(半))?$').firstMatch(cleanTime);
  if (cnTimeMatch != null) {
    var hour = int.parse(cnTimeMatch.group(1)!);
    int minute = 0;
    if (cnTimeMatch.group(3) == '半') {
      minute = 30;
    } else if (cnTimeMatch.group(2) != null) {
      minute = int.parse(cnTimeMatch.group(2)!);
    }
    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  return null;
}

