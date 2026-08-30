import '../../models/native/scheduled_notification.dart';

/// Abstract contract for local and scheduled notification services.
abstract class INotificationService {
  /// Immediately posts a local notification to the system notification center.
  Future<void> showLocalNotification({
    required String id,
    required String title,
    required String body,
    String? payload,
  });

  /// Schedules a future local notification or exact alarm.
  Future<void> scheduleNotification({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
    bool isExactAlarm = true,
  });

  /// Cancels a scheduled notification by [id]. Returns true if found and cancelled.
  Future<bool> cancelNotification(String id);

  /// Cancels all pending scheduled notifications.
  Future<void> cancelAllNotifications();

  /// Retrieves a list of all currently pending (untriggered) scheduled notifications.
  Future<List<ScheduledNotification>> getPendingNotifications();

  /// Retrieves history/triggered notifications.
  Future<List<ScheduledNotification>> getHistoryNotifications();

  /// Clears in-memory notification queue and history.
  Future<void> reset();
}

/// In-memory mock implementation of [INotificationService].
class InMemoryNotificationService implements INotificationService {
  final Map<String, ScheduledNotification> _pendingNotifications = {};
  final List<ScheduledNotification> _historyNotifications = [];

  @override
  Future<void> showLocalNotification({
    required String id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final notification = ScheduledNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: DateTime.now(),
      payload: payload,
      isExactAlarm: false,
    );
    _historyNotifications.add(notification);
  }

  @override
  Future<void> scheduleNotification({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
    bool isExactAlarm = true,
  }) async {
    final notification = ScheduledNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      payload: payload,
      isExactAlarm: isExactAlarm,
    );
    _pendingNotifications[id] = notification;
  }

  @override
  Future<bool> cancelNotification(String id) async {
    return _pendingNotifications.remove(id) != null;
  }

  @override
  Future<void> cancelAllNotifications() async {
    _pendingNotifications.clear();
  }

  @override
  Future<List<ScheduledNotification>> getPendingNotifications() async {
    final list = _pendingNotifications.values.toList();
    list.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return list;
  }

  @override
  Future<List<ScheduledNotification>> getHistoryNotifications() async {
    return List.unmodifiable(_historyNotifications);
  }

  @override
  Future<void> reset() async {
    _pendingNotifications.clear();
    _historyNotifications.clear();
  }
}
