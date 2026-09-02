import 'package:flutter_test/flutter_test.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/native/calendar_service.dart';
import 'package:chat/services/native/notification_service.dart';

void main() {
  group('ToolRegistry Parameter Normalization Tests', () {
    late ToolRegistry registry;
    late InMemoryCalendarService calendarService;
    late InMemoryNotificationService notificationService;

    setUp(() {
      calendarService = InMemoryCalendarService();
      notificationService = InMemoryNotificationService();
      registry = ToolRegistry.defaultRegistry(
        calendarService: calendarService,
        notificationService: notificationService,
      );
    });

    test('calendar_create_event normalizes summary/name/start aliases to title and start_time', () async {
      final result = await registry.execute('calendar_create_event', {
        'summary': 'Team Sync Meeting',
        'start': '2026-09-02 15:00:00',
        'end': '2026-09-02 16:00:00',
      });

      expect(result.isSuccess, isTrue);
      expect(result.content, contains('Team Sync Meeting'));
      final events = await calendarService.queryEvents();
      expect(events.any((e) => e.title == 'Team Sync Meeting'), isTrue);
    });

    test('notification_schedule normalizes message/trigger_time aliases to body and scheduled_time', () async {
      final result = await registry.execute('notification_schedule', {
        'title': 'Reminder',
        'message': 'Time to take a break',
        'trigger_time': '2026-09-02 16:00:00',
      });

      expect(result.isSuccess, isTrue);
      expect(result.content, contains('Reminder'));
      final notifications = await notificationService.getPendingNotifications();
      expect(notifications.any((n) => n.body == 'Time to take a break'), isTrue);
    });

    test('file_read normalizes file_path alias to path', () async {
      final result = await registry.execute('file_read', {
        'file_path': 'non_existent_file.txt',
      });

      // Even if file not found, parameter validation succeeded without 'Missing required parameter: path' error
      expect(result.errorMessage, isNot(contains('参数校验失败: 缺少必填参数: "path"')));
      expect(result.errorMessage, contains('文件未找到'));
    });
  });
}
