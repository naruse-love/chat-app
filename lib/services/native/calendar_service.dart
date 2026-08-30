import '../../models/native/calendar_event.dart';

/// Abstract contract for calendar services.
abstract class ICalendarService {
  /// Queries calendar events within an optional time range and/or keyword filter.
  Future<List<CalendarEvent>> queryEvents({
    DateTime? startTime,
    DateTime? endTime,
    String? query,
  });

  /// Finds all existing events that have a time conflict (interval overlap) with [startTime, endTime).
  /// Overlap condition: S1 < E2 && E1 > S2.
  Future<List<CalendarEvent>> checkConflict(
    DateTime startTime,
    DateTime endTime, {
    String? excludeId,
  });

  /// Checks if any existing event conflicts with the given time window.
  Future<bool> hasConflict(
    DateTime startTime,
    DateTime endTime, {
    String? excludeId,
  });

  /// Creates a new calendar event.
  Future<CalendarEvent> createEvent(CalendarEvent event);

  /// Deletes a calendar event by [id]. Returns true if found and deleted.
  Future<bool> deleteEvent(String id);

  /// Retrieves an event by its [id], or null if not found.
  Future<CalendarEvent?> getEventById(String id);

  /// Resets calendar storage to the initial sample seed data.
  Future<void> resetToDefaultSeed();
}

/// In-memory mock implementation of [ICalendarService] with pre-seeded realistic sample events.
class InMemoryCalendarService implements ICalendarService {
  final Map<String, CalendarEvent> _events = {};

  InMemoryCalendarService({bool seedDefaults = true}) {
    if (seedDefaults) {
      _seedDefaultEvents();
    }
  }

  void _seedDefaultEvents() {
    _events.clear();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final seedEvents = [
      CalendarEvent(
        id: 'seed-cal-1',
        title: '团队产品与架构周例会',
        startTime: today.add(const Duration(hours: 10)),
        endTime: today.add(const Duration(hours: 11, minutes: 30)),
        location: '3号会议室 (线上腾讯会议同步)',
        description: '讨论 Milestone 25 原生能力与隐私脱敏工具生态进展',
        reminderMinutes: 15,
      ),
      CalendarEvent(
        id: 'seed-cal-2',
        title: 'AI Agent 生态演进技术评审',
        startTime: today.add(const Duration(hours: 14, minutes: 30)),
        endTime: today.add(const Duration(hours: 16)),
        location: '总部A座 801 大会议室',
        description: '评审 ToolRegistry、HITL 确认机制与多模态扩展方案',
        reminderMinutes: 30,
      ),
      CalendarEvent(
        id: 'seed-cal-3',
        title: '季度业务规划与OKR对齐研讨',
        startTime: today.add(const Duration(days: 1, hours: 9, minutes: 30)),
        endTime: today.add(const Duration(days: 1, hours: 11, minutes: 30)),
        location: '创新工场 报告厅',
        description: '对齐 Q3/Q4 产品核心交付目标',
        reminderMinutes: 20,
      ),
      CalendarEvent(
        id: 'seed-cal-4',
        title: 'Flutter 与跨平台高性能技术沙龙',
        startTime: today.add(const Duration(days: 2, hours: 15)),
        endTime: today.add(const Duration(days: 2, hours: 17)),
        location: '线上直播间 / 极客空间',
        description: '分享 Flutter 3.x 隔离沙箱与原生特权交互最佳实践',
        reminderMinutes: 10,
      ),
    ];

    for (final ev in seedEvents) {
      _events[ev.id] = ev;
    }
  }

  @override
  Future<List<CalendarEvent>> queryEvents({
    DateTime? startTime,
    DateTime? endTime,
    String? query,
  }) async {
    var list = _events.values.toList();

    if (startTime != null && endTime != null) {
      // Overlap with [startTime, endTime)
      list = list.where((e) => e.overlapsWith(startTime, endTime)).toList();
    } else if (startTime != null) {
      list = list.where((e) => e.endTime.isAfter(startTime)).toList();
    } else if (endTime != null) {
      list = list.where((e) => e.startTime.isBefore(endTime)).toList();
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim().toLowerCase();
      list = list.where((e) {
        final matchTitle = e.title.toLowerCase().contains(q);
        final matchLoc = e.location?.toLowerCase().contains(q) ?? false;
        final matchDesc = e.description?.toLowerCase().contains(q) ?? false;
        return matchTitle || matchLoc || matchDesc;
      }).toList();
    }

    // Sort by startTime ascending
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    return list;
  }

  @override
  Future<List<CalendarEvent>> checkConflict(
    DateTime startTime,
    DateTime endTime, {
    String? excludeId,
  }) async {
    final conflicts = <CalendarEvent>[];
    for (final event in _events.values) {
      if (excludeId != null && event.id == excludeId) continue;
      if (event.overlapsWith(startTime, endTime)) {
        conflicts.add(event);
      }
    }
    conflicts.sort((a, b) => a.startTime.compareTo(b.startTime));
    return conflicts;
  }

  @override
  Future<bool> hasConflict(
    DateTime startTime,
    DateTime endTime, {
    String? excludeId,
  }) async {
    final conflicts = await checkConflict(startTime, endTime, excludeId: excludeId);
    return conflicts.isNotEmpty;
  }

  @override
  Future<CalendarEvent> createEvent(CalendarEvent event) async {
    _events[event.id] = event;
    return event;
  }

  @override
  Future<bool> deleteEvent(String id) async {
    return _events.remove(id) != null;
  }

  @override
  Future<CalendarEvent?> getEventById(String id) async {
    return _events[id];
  }

  @override
  Future<void> resetToDefaultSeed() async {
    _seedDefaultEvents();
  }
}
