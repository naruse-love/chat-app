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
          description: '通知提醒正文内容',
          required: true,
        ),
        ToolParameter(
          name: 'scheduled_time',
          type: 'string',
          description: '预定触发时间 (ISO 8601 格式，如 "2026-08-30T18:00:00Z")',
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

      final body = arguments['body']?.toString().trim() ?? '';
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
          '';
      final scheduledTime = DateTime.tryParse(rawScheduled);
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
          description: '待取消的通知 ID (与 cancel_all 至少二选一)',
          required: false,
        ),
        ToolParameter(
          name: 'cancel_all',
          type: 'boolean',
          description: '是否清空取消所有待触发的定时通知 (默认为 false)',
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

      if (rawId == null || rawId.isEmpty) {
        stopwatch.stop();
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '请提供待取消的通知 ID (notification_id) 或设置 cancel_all: true',
          content: '取消通知失败: 缺少通知 ID 或清空指令',
          executionDuration: stopwatch.elapsed,
        );
      }

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
