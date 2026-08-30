import 'package:uuid/uuid.dart';

/// Represents a scheduled or immediate local notification.
class ScheduledNotification {
  final String id;
  final String title;
  final String body;
  final DateTime scheduledTime;
  final String? payload;
  final bool isExactAlarm;
  final String channelId;
  final DateTime createdAt;

  ScheduledNotification({
    String? id,
    required this.title,
    required this.body,
    required this.scheduledTime,
    this.payload,
    this.isExactAlarm = true,
    this.channelId = 'default_channel',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  /// Whether the notification has not yet been triggered.
  bool get isPending => scheduledTime.isAfter(DateTime.now());

  /// Time remaining until trigger.
  Duration get timeUntil => scheduledTime.difference(DateTime.now());

  /// Formatted relative trigger time (e.g. "10分钟后", "今天 15:30", "已触发").
  String toRelativeTimeString() {
    final now = DateTime.now();
    if (!isPending) return "已过预定时间";
    final diff = scheduledTime.difference(now);
    if (diff.inMinutes < 1) return "即将触发（不到1分钟）";
    if (diff.inHours < 1) return "${diff.inMinutes} 分钟后触发";
    if (diff.inHours < 24 && scheduledTime.day == now.day) {
      return "今天 ${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')} (${diff.inHours} 小时后)";
    }
    return "${scheduledTime.year}-${scheduledTime.month.toString().padLeft(2, '0')}-${scheduledTime.day.toString().padLeft(2, '0')} ${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}";
  }

  /// Formats the notification into a clean summary.
  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.write("🔔 [$title] - $body");
    buffer.write(" (预定: ${toRelativeTimeString()})");
    if (payload != null && payload!.isNotEmpty) {
      buffer.write(" [附加数据: $payload]");
    }
    return buffer.toString();
  }

  /// Formats the notification as Markdown for LLM output.
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln("- **通知标题**: $title");
    buffer.writeln("  - **通知内容**: $body");
    buffer.writeln("  - **预定时间**: ${_formatDateTime(scheduledTime)} (${toRelativeTimeString()})");
    buffer.writeln("  - **精确提醒**: ${isExactAlarm ? '是 (精确闹钟)' : '否 (普通通知)'}");
    if (payload != null && payload!.isNotEmpty) {
      buffer.writeln("  - **附加数据**: `$payload`");
    }
    buffer.writeln("  - **通知ID**: `$id`");
    return buffer.toString().trimRight();
  }

  ScheduledNotification copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? scheduledTime,
    String? payload,
    bool? isExactAlarm,
    String? channelId,
    DateTime? createdAt,
    bool clearPayload = false,
  }) {
    return ScheduledNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      payload: clearPayload ? null : (payload ?? this.payload),
      isExactAlarm: isExactAlarm ?? this.isExactAlarm,
      channelId: channelId ?? this.channelId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'scheduledTime': scheduledTime.toIso8601String(),
      if (payload != null) 'payload': payload,
      'isExactAlarm': isExactAlarm,
      'channelId': channelId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ScheduledNotification.fromJson(Map<String, dynamic> json) {
    return ScheduledNotification(
      id: json['id']?.toString(),
      title: json['title'] as String? ?? '未命名通知',
      body: json['body'] as String? ?? '',
      scheduledTime: DateTime.parse(json['scheduledTime'] as String),
      payload: json['payload'] as String?,
      isExactAlarm: json['isExactAlarm'] as bool? ?? true,
      channelId: json['channelId'] as String? ?? 'default_channel',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledNotification &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          body == other.body &&
          scheduledTime == other.scheduledTime &&
          payload == other.payload &&
          isExactAlarm == other.isExactAlarm &&
          channelId == other.channelId;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      body.hashCode ^
      scheduledTime.hashCode ^
      payload.hashCode ^
      isExactAlarm.hashCode ^
      channelId.hashCode;

  @override
  String toString() =>
      'ScheduledNotification(id: $id, title: $title, time: $scheduledTime)';

  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return "$y-$m-$d $h:$min";
  }
}

/// Helper preview model for HITL confirmation card rendering.
class NotificationPreview {
  final String id;
  final String title;
  final String body;
  final String scheduledTimeString;
  final String relativeTimeString;
  final bool isExactAlarm;
  final String? payload;

  const NotificationPreview({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledTimeString,
    required this.relativeTimeString,
    this.isExactAlarm = true,
    this.payload,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'scheduledTimeString': scheduledTimeString,
      'relativeTimeString': relativeTimeString,
      'isExactAlarm': isExactAlarm,
      if (payload != null) 'payload': payload,
    };
  }

  factory NotificationPreview.fromJson(Map<String, dynamic> json) {
    return NotificationPreview(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      scheduledTimeString: json['scheduledTimeString'] as String? ?? '',
      relativeTimeString: json['relativeTimeString'] as String? ?? '',
      isExactAlarm: json['isExactAlarm'] as bool? ?? true,
      payload: json['payload'] as String?,
    );
  }
}
