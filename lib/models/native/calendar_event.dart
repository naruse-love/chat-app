import 'package:uuid/uuid.dart';

/// Represents a calendar event with time interval, location, description, and reminder.
class CalendarEvent {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final String? description;
  final bool isAllDay;
  final int? reminderMinutes;
  final Map<String, dynamic>? metadata;

  CalendarEvent({
    String? id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.location,
    this.description,
    this.isAllDay = false,
    this.reminderMinutes,
    this.metadata,
  }) : id = id ?? const Uuid().v4();

  /// Total duration of the event.
  Duration get duration => endTime.difference(startTime);

  /// Checks if this event's time interval overlaps with another time window [otherStart, otherEnd).
  /// Overlap condition: S1 < E2 && E1 > S2.
  bool overlapsWith(DateTime otherStart, DateTime otherEnd) {
    return startTime.isBefore(otherEnd) && endTime.isAfter(otherStart);
  }

  /// Checks if this event conflicts with another event.
  bool conflictsWith(CalendarEvent other) {
    if (id == other.id) return false;
    return overlapsWith(other.startTime, other.endTime);
  }

  /// Formatted time range string (e.g. "2026-08-30 10:00 ~ 11:30" or "全天").
  String toTimeRangeString() {
    if (isAllDay) {
      final startStr = "${startTime.year.toString().padLeft(4, '0')}-${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')}";
      return "$startStr (全天)";
    }
    final startStr = _formatDateTime(startTime);
    final endStr = (startTime.year == endTime.year && startTime.month == endTime.month && startTime.day == endTime.day)
        ? _formatTimeOnly(endTime)
        : _formatDateTime(endTime);
    return "$startStr ~ $endStr";
  }

  /// Formats the event into a clean human-readable summary.
  String toFormattedString() {
    final buffer = StringBuffer();
    buffer.write("📅 $title (${toTimeRangeString()})");
    if (location != null && location!.trim().isNotEmpty) {
      buffer.write(" | 📍 $location");
    }
    if (reminderMinutes != null && reminderMinutes! > 0) {
      buffer.write(" | ⏰ 提前 $reminderMinutes 分钟提醒");
    }
    if (description != null && description!.trim().isNotEmpty) {
      buffer.write("\n   📝 备注: $description");
    }
    return buffer.toString();
  }

  /// Formats the event as Markdown for LLM responses and chat UI.
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln("- **$title**");
    buffer.writeln("  - **时间**: ${toTimeRangeString()}");
    if (location != null && location!.trim().isNotEmpty) {
      buffer.writeln("  - **地点**: $location");
    }
    if (reminderMinutes != null && reminderMinutes! > 0) {
      buffer.writeln("  - **提醒**: 提前 $reminderMinutes 分钟");
    }
    if (description != null && description!.trim().isNotEmpty) {
      buffer.writeln("  - **描述**: $description");
    }
    buffer.writeln("  - **事件ID**: `$id`");
    return buffer.toString().trimRight();
  }

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? location,
    String? description,
    bool? isAllDay,
    int? reminderMinutes,
    Map<String, dynamic>? metadata,
    bool clearLocation = false,
    bool clearDescription = false,
    bool clearReminder = false,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: clearLocation ? null : (location ?? this.location),
      description: clearDescription ? null : (description ?? this.description),
      isAllDay: isAllDay ?? this.isAllDay,
      reminderMinutes: clearReminder ? null : (reminderMinutes ?? this.reminderMinutes),
      metadata: metadata ?? (this.metadata != null ? Map.from(this.metadata!) : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      if (location != null) 'location': location,
      if (description != null) 'description': description,
      'isAllDay': isAllDay,
      if (reminderMinutes != null) 'reminderMinutes': reminderMinutes,
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String?,
      title: json['title'] as String? ?? '未命名日程',
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      location: json['location'] as String?,
      description: json['description'] as String?,
      isAllDay: json['isAllDay'] as bool? ?? false,
      reminderMinutes: (json['reminderMinutes'] as num?)?.toInt() ??
          (json['reminderMinutesBefore'] as num?)?.toInt(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarEvent &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          location == other.location &&
          description == other.description &&
          isAllDay == other.isAllDay &&
          reminderMinutes == other.reminderMinutes;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      startTime.hashCode ^
      endTime.hashCode ^
      location.hashCode ^
      description.hashCode ^
      isAllDay.hashCode ^
      reminderMinutes.hashCode;

  @override
  String toString() =>
      'CalendarEvent(id: $id, title: $title, time: ${toTimeRangeString()}, location: $location)';

  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return "$y-$m-$d $h:$min";
  }

  static String _formatTimeOnly(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return "$h:$min";
  }
}

/// Helper preview model for HITL confirmation card rendering.
class CalendarEventPreview {
  final String title;
  final String timeRangeString;
  final String? location;
  final String? description;
  final int? reminderMinutes;
  final bool hasConflict;
  final List<String> conflictingEventTitles;

  const CalendarEventPreview({
    required this.title,
    required this.timeRangeString,
    this.location,
    this.description,
    this.reminderMinutes,
    this.hasConflict = false,
    this.conflictingEventTitles = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'timeRangeString': timeRangeString,
      if (location != null) 'location': location,
      if (description != null) 'description': description,
      if (reminderMinutes != null) 'reminderMinutes': reminderMinutes,
      'hasConflict': hasConflict,
      'conflictingEventTitles': conflictingEventTitles,
    };
  }

  factory CalendarEventPreview.fromJson(Map<String, dynamic> json) {
    return CalendarEventPreview(
      title: json['title'] as String? ?? '',
      timeRangeString: json['timeRangeString'] as String? ?? '',
      location: json['location'] as String?,
      description: json['description'] as String?,
      reminderMinutes: (json['reminderMinutes'] as num?)?.toInt(),
      hasConflict: json['hasConflict'] as bool? ?? false,
      conflictingEventTitles: (json['conflictingEventTitles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}
