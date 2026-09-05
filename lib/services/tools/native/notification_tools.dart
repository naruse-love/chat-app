import 'package:uuid/uuid.dart';
import '../../../models/native/native_models.dart';
import '../../../models/tool/tool.dart';
import '../../native/notification_service.dart';
import '../../native/permission_manager_service.dart';

/// Local notification and alarm scheduling tool [Level 3 Privileged + HITL].
///
/// Schedules a future local notification or exact alarm,
/// checking [AppPermission.notification] permission beforehand.
class NotificationScheduleTool extends Tool {
  final INotificationService notificationService;
  final PermissionManagerService permissionService;

  NotificationScheduleTool({
    INotificationService? notificationService,
    PermissionManagerService? permissionService,
  })  : notificationService = notificationService ?? InMemoryNotificationService(),
        permissionService = permissionService ?? PermissionManagerService();

  @override
  String get name => 'notification_schedule';

  @override
  String get displayName => '设置通知';

  @override
  String get description =>
      'Schedules a local push notification or exact alarm with title, body, scheduled_time, and optional payload.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.privilegedNative;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'title',
          type: 'string',
          description: '通知提醒标题 (如 "喝水提醒", "会议开始通知")',
          required: true,
        ),
        ToolParameter(
          name: 'body',
          type: 'string',
          description: '通知提醒正文内容 (可选，未提供时默认使用标题)',
          required: false,
        ),
        ToolParameter(
          name: 'scheduled_time',
          type: 'string',
          description: '预定触发时间 (ISO 8601 格式或自然时间，如 "10分钟后", "明天 09:00", "明天上午9点")',
          required: true,
        ),
        ToolParameter(
          name: 'notification_id',
          type: 'string',
          description: '自定义通知 ID (可选，未指定时自动生成 UUID)',
          required: false,
        ),
        ToolParameter(
          name: 'payload',
          type: 'string',
          description: '点击通知时传递的附加数据或链接 (可选)',
          required: false,
        ),
        ToolParameter(
          name: 'is_exact_alarm',
          type: 'boolean',
          description: '是否使用精确闹钟模式触发 (默认为 true)',
          required: false,
          defaultValue: true,
        ),
      ];

  @override
  String? validateArguments(Map<String, dynamic> arguments) {
    for (final param in parameters) {
      if (param.name == 'body') continue;
      final value = arguments[param.name];
      final error = param.validate(value);
      if (error != null) return error;
    }
    return null;
  }

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    // 1. Permission check
    final hasPermission = await permissionService.hasPermission(AppPermission.notification);
    if (!hasPermission) {
      stopwatch.stop();
      final errorMsg = permissionService.getRejectionErrorMessage(AppPermission.notification);
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: errorMsg,
        content: errorMsg,
        executionDuration: stopwatch.elapsed,
        rawData: {'permission': 'notification', 'granted': false},
      );
    }

    try {
      final title = arguments['title']?.toString().trim() ?? '';
      if (title.isEmpty) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '通知标题不能为空',
          content: '设置通知失败: 缺少有效的通知标题 (title)',
          executionDuration: stopwatch.elapsed,
        );
      }

      var body = arguments['body']?.toString().trim();
      if (body == null) {
        final fallback = arguments['content']?.toString().trim() ??
            arguments['message']?.toString().trim() ??
            arguments['description']?.toString().trim();
        body = (fallback != null && fallback.isNotEmpty) ? fallback : title;
      }
      if (body.isEmpty) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '通知正文内容不能为空',
          content: '设置通知失败: 缺少有效的通知正文 (body)',
          executionDuration: stopwatch.elapsed,
        );
      }

      final rawScheduled = arguments['scheduled_time']?.toString().trim() ??
          arguments['trigger_time']?.toString().trim() ??
          arguments['time']?.toString().trim() ??
          '';
      final scheduledTime = _parseFlexibleScheduledTime(rawScheduled);
      if (scheduledTime == null) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '无效的预定触发时间格式: "$rawScheduled"',
          content: '设置通知失败: 预定触发时间无效，请提供合法的 ISO 8601 时间格式 (例如 "2026-08-30T18:00:00Z")',
          executionDuration: stopwatch.elapsed,
        );
      }

      final rawNotifId = arguments['notification_id']?.toString().trim();
      final notifId = (rawNotifId != null && rawNotifId.isNotEmpty)
          ? rawNotifId
          : const Uuid().v4();

      final payload = arguments['payload']?.toString().trim();
      final isExactAlarm = arguments['is_exact_alarm'] as bool? ?? true;

      await notificationService.scheduleNotification(
        id: notifId,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        payload: (payload != null && payload.isNotEmpty) ? payload : null,
        isExactAlarm: isExactAlarm,
      );

      stopwatch.stop();

      final notification = ScheduledNotification(
        id: notifId,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        payload: (payload != null && payload.isNotEmpty) ? payload : null,
        isExactAlarm: isExactAlarm,
      );

      final buffer = StringBuffer();
      buffer.writeln('✅ **定时通知设定成功**\n');
      buffer.writeln(notification.toMarkdown());

      return ToolExecutionResult.success(
        toolName: name,
        content: buffer.toString().trimRight(),
        rawData: notification.toJson(),
        executionDuration: stopwatch.elapsed,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '设定通知发生异常: $e',
        content: '设定通知发生异常: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'exception': e.toString(), 'stackTrace': stackTrace.toString()},
      );
    }
  }
}

/// Notification cancellation tool [Level 3 Privileged].
///
/// Cancels a scheduled notification by ID or cancels all pending notifications,
/// checking [AppPermission.notification] permission beforehand.
class NotificationCancelTool extends Tool {
  final INotificationService notificationService;
  final PermissionManagerService permissionService;

  NotificationCancelTool({
    INotificationService? notificationService,
    PermissionManagerService? permissionService,
  })  : notificationService = notificationService ?? InMemoryNotificationService(),
        permissionService = permissionService ?? PermissionManagerService();

  @override
  String get name => 'notification_cancel';

  @override
  String get displayName => '取消通知';

  @override
  String get description =>
      'Cancels a pending scheduled notification by its ID, or cancels all pending notifications if cancel_all is true.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.privilegedNative;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'notification_id',
          type: 'string',
          description: '待取消的通知 ID (与 title, cancel_all 或 list_pending 至少选一)',
          required: false,
        ),
        ToolParameter(
          name: 'title',
          type: 'string',
          description: '待取消的通知标题关键词 (支持根据标题模糊匹配并取消)',
          required: false,
        ),
        ToolParameter(
          name: 'query',
          type: 'string',
          description: '通知关键词搜索并取消 (或配合 action: "list" 筛选)',
          required: false,
        ),
        ToolParameter(
          name: 'cancel_all',
          type: 'boolean',
          description: '是否清空取消所有待触发的定时通知 (默认为 false)',
          required: false,
          defaultValue: false,
        ),
        ToolParameter(
          name: 'list_pending',
          type: 'boolean',
          description: '是否查询并列出当前所有待触发的定时通知 (默认为 false)',
          required: false,
          defaultValue: false,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    // 1. Permission check
    final hasPermission = await permissionService.hasPermission(AppPermission.notification);
    if (!hasPermission) {
      stopwatch.stop();
      final errorMsg = permissionService.getRejectionErrorMessage(AppPermission.notification);
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: errorMsg,
        content: errorMsg,
        executionDuration: stopwatch.elapsed,
        rawData: {'permission': 'notification', 'granted': false},
      );
    }

    try {
      final listPending = arguments['list_pending'] == true ||
          arguments['list'] == true ||
          arguments['action'] == 'list' ||
          (arguments['query'] == true);

      if (listPending) {
        final pending = await notificationService.getPendingNotifications();
        stopwatch.stop();
        if (pending.isEmpty) {
          return ToolExecutionResult.success(
            toolName: name,
            content: 'ℹ️ **暂无待触发的系统定时通知**。',
            rawData: {'count': 0, 'notifications': []},
            executionDuration: stopwatch.elapsed,
          );
        }
        final buffer = StringBuffer();
        buffer.writeln('📋 **当前共有 ${pending.length} 条待触发的定时通知**：\n');
        for (int i = 0; i < pending.length; i++) {
          final item = pending[i];
          buffer.writeln('${i + 1}. **${item.title}** (ID: `${item.id}`)');
          buffer.writeln('   - 内容: ${item.body}');
          buffer.writeln('   - 预定时间: ${item.scheduledTime.toLocal().toString()}');
          buffer.writeln('   - 精确闹钟: ${item.isExactAlarm ? "是" : "否"}');
        }
        return ToolExecutionResult.success(
          toolName: name,
          content: buffer.toString().trimRight(),
          rawData: {
            'count': pending.length,
            'notifications': pending.map((e) => e.toJson()).toList(),
          },
          executionDuration: stopwatch.elapsed,
        );
      }

      final cancelAll = arguments['cancel_all'] as bool? ?? false;
      final rawId = arguments['notification_id']?.toString().trim();

      if (cancelAll) {
        await notificationService.cancelAllNotifications();
        stopwatch.stop();
        return ToolExecutionResult.success(
          toolName: name,
          content: '✅ **已成功取消所有待触发的系统定时通知**。',
          rawData: {'cancelAll': true, 'success': true},
          executionDuration: stopwatch.elapsed,
        );
      }

      if (rawId != null && rawId.isNotEmpty) {
        final removed = await notificationService.cancelNotification(rawId);
        stopwatch.stop();

        if (removed) {
          return ToolExecutionResult.success(
            toolName: name,
            content: '✅ **通知已成功取消** (通知ID: `$rawId`)',
            rawData: {'notificationId': rawId, 'cancelled': true},
            executionDuration: stopwatch.elapsed,
          );
        } else {
          return ToolExecutionResult.success(
            toolName: name,
            content: 'ℹ️ **未找到待取消通知**：ID 为 `$rawId` 的通知不存在或已被触发。',
            rawData: {'notificationId': rawId, 'cancelled': false, 'found': false},
            executionDuration: stopwatch.elapsed,
          );
        }
      }

      // If ID not provided, try title or keyword match
      final keyword = (arguments['title'] ?? arguments['query'] ?? arguments['keyword'] ?? arguments['name'])?.toString().trim();
      if (keyword != null && keyword.isNotEmpty) {
        final pending = await notificationService.getPendingNotifications();
        final match = pending.where((n) =>
            n.title.toLowerCase().contains(keyword.toLowerCase()) ||
            n.body.toLowerCase().contains(keyword.toLowerCase())).toList();
        if (match.isNotEmpty) {
          final target = match.first;
          await notificationService.cancelNotification(target.id);
          stopwatch.stop();
          return ToolExecutionResult.success(
            toolName: name,
            content: '✅ **已成功取消提醒通知**: "${target.title}" (通知ID: `${target.id}`)',
            rawData: {'notificationId': target.id, 'title': target.title, 'cancelled': true},
            executionDuration: stopwatch.elapsed,
          );
        } else {
          stopwatch.stop();
          return ToolExecutionResult.success(
            toolName: name,
            content: 'ℹ️ **未找到待取消通知**：未找到与 "$keyword" 匹配的待触发定时通知。',
            rawData: {'query': keyword, 'cancelled': false, 'found': false},
            executionDuration: stopwatch.elapsed,
          );
        }
      }

      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '请提供待取消的通知 ID (notification_id) 或标题关键词 (title)，或设置 cancel_all: true',
        content: '取消通知失败: 缺少通知 ID 或标题关键词',
        executionDuration: stopwatch.elapsed,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '取消通知发生异常: $e',
        content: '取消通知发生异常: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'exception': e.toString(), 'stackTrace': stackTrace.toString()},
      );
    }
  }
}

DateTime? _parseFlexibleScheduledTime(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  // 1. Relative time patterns: e.g. "5分钟后", "10分钟", "10m", "10 mins", "1小时后", "2 hours"
  final minMatch = RegExp(r'^(\d+)\s*(?:分钟|分|mins?|minutes?)(?:后)?$', caseSensitive: false).firstMatch(trimmed);
  if (minMatch != null) {
    final mins = int.tryParse(minMatch.group(1)!);
    if (mins != null) {
      return DateTime.now().add(Duration(minutes: mins));
    }
  }

  final hourMatch = RegExp(r'^(\d+)\s*(?:小时|点钟|hours?|hrs?)(?:后)?$', caseSensitive: false).firstMatch(trimmed);
  if (hourMatch != null) {
    final hours = int.tryParse(hourMatch.group(1)!);
    if (hours != null) {
      return DateTime.now().add(Duration(hours: hours));
    }
  }

  final secMatch = RegExp(r'^(\d+)\s*(?:秒|seconds?|secs?)(?:后)?$', caseSensitive: false).firstMatch(trimmed);
  if (secMatch != null) {
    final secs = int.tryParse(secMatch.group(1)!);
    if (secs != null) {
      return DateTime.now().add(Duration(seconds: secs));
    }
  }

  // 2. Relative date keyword + optional time (e.g. "明天 09:00", "明天上午9点", "今天下午3点", "后天上午10点")
  final now = DateTime.now();
  final relDateMatch = RegExp(
    r'^(今天|今日|明天|次日|后天|大后天|today|tomorrow)\s*(.*)$',
    caseSensitive: false,
  ).firstMatch(trimmed);

  if (relDateMatch != null) {
    final kw = relDateMatch.group(1)!.toLowerCase();
    final timePart = relDateMatch.group(2)?.trim() ?? '';
    DateTime? baseDate;
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
    }
    if (baseDate != null) {
      if (timePart.isEmpty) {
        return baseDate.add(const Duration(hours: 9)); // Default to 9 AM
      }
      final parsed = _parseNotificationTime(baseDate, timePart);
      if (parsed != null) return parsed;
    }
  }

  // 3. Chinese date with 年月日 (e.g. "2026年9月5日 18:00" or "9月5日 18:00")
  final cnDateFull = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})[日号]?\s*(.*)$').firstMatch(trimmed);
  if (cnDateFull != null) {
    final y = int.parse(cnDateFull.group(1)!);
    final m = int.parse(cnDateFull.group(2)!);
    final d = int.parse(cnDateFull.group(3)!);
    final rest = cnDateFull.group(4)?.trim() ?? '';
    final base = DateTime(y, m, d);
    if (rest.isEmpty) return base.add(const Duration(hours: 9));
    final parsed = _parseNotificationTime(base, rest);
    if (parsed != null) return parsed;
  }

  final cnDateShort = RegExp(r'^(\d{1,2})月(\d{1,2})[日号]?\s*(.*)$').firstMatch(trimmed);
  if (cnDateShort != null) {
    final y = now.year;
    final m = int.parse(cnDateShort.group(1)!);
    final d = int.parse(cnDateShort.group(2)!);
    final rest = cnDateShort.group(3)?.trim() ?? '';
    final base = DateTime(y, m, d);
    if (rest.isEmpty) return base.add(const Duration(hours: 9));
    final parsed = _parseNotificationTime(base, rest);
    if (parsed != null) return parsed;
  }

  // 4. Standalone time today (e.g. "下午3点", "上午10点半", "18:00")
  final todayTime = _parseNotificationTime(DateTime(now.year, now.month, now.day), trimmed);
  if (todayTime != null) {
    return todayTime;
  }

  // 5. Standard ISO parse
  final parsed = DateTime.tryParse(trimmed);
  if (parsed != null) {
    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  // 6. Normalize "YYYY/MM/DD" or "YYYY.MM.DD" or "YYYY-MM-DD HH:mm:ss"
  var normalized = trimmed.replaceAll('/', '-').replaceAll('.', '-');
  if (normalized.contains(' ') && !normalized.contains('T')) {
    normalized = normalized.replaceFirst(' ', 'T');
  }
  final parsedNorm = DateTime.tryParse(normalized);
  if (parsedNorm != null) {
    return parsedNorm.isUtc ? parsedNorm.toLocal() : parsedNorm;
  }

  return null;
}

DateTime? _parseNotificationTime(DateTime base, String timeStr) {
  final s = timeStr.trim();
  if (s.isEmpty) return null;

  final isPm = s.contains('下午') || s.contains('晚上') || s.contains('傍晚') || s.contains('夜间') || s.toLowerCase().contains('pm');
  final isAm = s.contains('上午') || s.contains('早上') || s.contains('早晨') || s.contains('清晨') || s.toLowerCase().contains('am');

  final clean = s
      .replaceAll(RegExp(r'(?:上午|下午|早上|早晨|清晨|晚上|傍晚|夜间|am|pm)', caseSensitive: false), '')
      .trim();

  // "14:30" or "14:30:00"
  final colonMatch = RegExp(r'^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(clean);
  if (colonMatch != null) {
    var hour = int.parse(colonMatch.group(1)!);
    final minute = int.parse(colonMatch.group(2)!);
    final second = colonMatch.group(3) != null ? int.parse(colonMatch.group(3)!) : 0;
    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;
    return DateTime(base.year, base.month, base.day, hour, minute, second);
  }

  // "10点30分", "10点半", "10点", "10时"
  final cnMatch = RegExp(r'^(\d{1,2})\s*(?:点|时)\s*(?:(\d{1,2})\s*分?|(半))?$').firstMatch(clean);
  if (cnMatch != null) {
    var hour = int.parse(cnMatch.group(1)!);
    int minute = 0;
    if (cnMatch.group(3) == '半') {
      minute = 30;
    } else if (cnMatch.group(2) != null) {
      minute = int.parse(cnMatch.group(2)!);
    }
    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  return null;
}


