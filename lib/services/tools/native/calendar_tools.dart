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
  })  : calendarService = calendarService ?? InMemoryCalendarService(),
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
          description: '查询起始时间 (ISO 8601 格式，如 "2026-08-30T00:00:00Z" 或 "2026-08-30")',
          required: false,
        ),
        ToolParameter(
          name: 'end_time',
          type: 'string',
          description: '查询结束时间 (ISO 8601 格式，如 "2026-08-31T23:59:59Z" 或 "2026-08-31")',
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
      final rawStart = arguments['start_time']?.toString().trim();
      if (rawStart != null && rawStart.isNotEmpty) {
        startTime = DateTime.tryParse(rawStart);
      }

      DateTime? endTime;
      final rawEnd = arguments['end_time']?.toString().trim();
      if (rawEnd != null && rawEnd.isNotEmpty) {
        endTime = DateTime.tryParse(rawEnd);
      }

      final query = arguments['query']?.toString().trim();

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
  })  : calendarService = calendarService ?? InMemoryCalendarService(),
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
          description: '日程起始时间 (ISO 8601 格式，如 "2026-08-30T14:00:00Z")',
          required: true,
        ),
        ToolParameter(
          name: 'end_time',
          type: 'string',
          description: '日程结束时间 (ISO 8601 格式，如 "2026-08-30T15:30:00Z")',
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
      final startTime = DateTime.tryParse(rawStart);
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
      final endTime = DateTime.tryParse(rawEnd);
      if (endTime == null) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '无效的结束时间格式: "$rawEnd"',
          content: '创建日程失败: 结束时间格式无效，请提供合法的 ISO 8601 时间格式 (例如 "2026-08-30T15:30:00Z")',
          executionDuration: stopwatch.elapsed,
        );
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
