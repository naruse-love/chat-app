import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/native/scheduled_notification.dart';
import 'package:chat/services/native/notification_service.dart';

void main() {
  group('ScheduledNotification Model Tests', () {
    test('Constructor and relative time formatting', () {
      final scheduledTime = DateTime.now().add(const Duration(minutes: 15));
      final notif = ScheduledNotification(
        id: 'notif-1',
        title: '会议提醒',
        body: '15分钟后参加产品例会',
        scheduledTime: scheduledTime,
        payload: '{"meetingId": "123"}',
        isExactAlarm: true,
      );

      expect(notif.id, 'notif-1');
      expect(notif.title, '会议提醒');
      expect(notif.body, '15分钟后参加产品例会');
      expect(notif.isPending, isTrue);
      expect(notif.toRelativeTimeString(), contains('分钟后'));
      expect(notif.toFormattedString(), contains('🔔 [会议提醒]'));
      expect(notif.toMarkdown(), contains('**通知标题**: 会议提醒'));
    });

    test('Json Serialization & Deserialization', () {
      final scheduledTime = DateTime(2026, 8, 30, 18, 0);
      final notif = ScheduledNotification(
        id: 'notif-2',
        title: '下班打卡',
        body: '记得提交日报与打卡',
        scheduledTime: scheduledTime,
        payload: 'punch_clock',
        isExactAlarm: false,
        channelId: 'reminder_channel',
      );

      final json = notif.toJson();
      final restored = ScheduledNotification.fromJson(json);

      expect(restored.id, 'notif-2');
      expect(restored.title, '下班打卡');
      expect(restored.body, '记得提交日报与打卡');
      expect(restored.scheduledTime, scheduledTime);
      expect(restored.payload, 'punch_clock');
      expect(restored.isExactAlarm, isFalse);
      expect(restored.channelId, 'reminder_channel');
    });

    test('NotificationPreview serialization', () {
      const preview = NotificationPreview(
        id: 'p-1',
        title: '喝水提醒',
        body: '保持健康水分',
        scheduledTimeString: '2026-08-30 15:00',
        relativeTimeString: '30分钟后',
        isExactAlarm: true,
      );

      final json = preview.toJson();
      final restored = NotificationPreview.fromJson(json);

      expect(restored.id, 'p-1');
      expect(restored.title, '喝水提醒');
      expect(restored.body, '保持健康水分');
      expect(restored.relativeTimeString, '30分钟后');
      expect(restored.isExactAlarm, isTrue);
    });
  });

  group('InMemoryNotificationService Tests', () {
    late InMemoryNotificationService service;

    setUp(() {
      service = InMemoryNotificationService();
    });

    test('showLocalNotification records in history', () async {
      await service.showLocalNotification(
        id: 'immediate-1',
        title: '新消息',
        body: '收到一条新通知',
        payload: 'chat_msg_1',
      );

      final history = await service.getHistoryNotifications();
      expect(history.length, 1);
      expect(history.first.id, 'immediate-1');
      expect(history.first.title, '新消息');
    });

    test('scheduleNotification, getPendingNotifications, cancelNotification and cancelAll', () async {
      final time1 = DateTime.now().add(const Duration(minutes: 10));
      final time2 = DateTime.now().add(const Duration(minutes: 30));

      await service.scheduleNotification(
        id: 'alarm-1',
        title: '站会',
        body: '晨会准备',
        scheduledTime: time1,
      );

      await service.scheduleNotification(
        id: 'alarm-2',
        title: '茶歇',
        body: '下午茶时间',
        scheduledTime: time2,
      );

      var pending = await service.getPendingNotifications();
      expect(pending.length, 2);
      expect(pending.first.id, 'alarm-1');

      final cancelled = await service.cancelNotification('alarm-1');
      expect(cancelled, isTrue);

      pending = await service.getPendingNotifications();
      expect(pending.length, 1);
      expect(pending.first.id, 'alarm-2');

      await service.cancelAllNotifications();
      pending = await service.getPendingNotifications();
      expect(pending.isEmpty, isTrue);
    });

    test('reset clears pending and history notifications', () async {
      await service.showLocalNotification(id: '1', title: 'A', body: 'B');
      await service.scheduleNotification(
        id: '2',
        title: 'C',
        body: 'D',
        scheduledTime: DateTime.now().add(const Duration(hours: 1)),
      );

      await service.reset();
      expect((await service.getHistoryNotifications()).isEmpty, isTrue);
      expect((await service.getPendingNotifications()).isEmpty, isTrue);
    });
  });
}
