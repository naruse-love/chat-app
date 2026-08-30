import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/native/calendar_event.dart';
import 'package:chat/services/native/calendar_service.dart';

void main() {
  group('CalendarEvent Model Tests', () {
    test('Constructor generates UUID and initializes fields', () {
      final start = DateTime(2026, 8, 30, 10, 0);
      final end = DateTime(2026, 8, 30, 11, 30);
      final event = CalendarEvent(
        title: '产品评审会',
        startTime: start,
        endTime: end,
        location: '3号会议室',
        description: '评审Milestone 25',
        reminderMinutes: 15,
      );

      expect(event.id.isNotEmpty, isTrue);
      expect(event.title, '产品评审会');
      expect(event.startTime, start);
      expect(event.endTime, end);
      expect(event.duration, const Duration(minutes: 90));
      expect(event.location, '3号会议室');
      expect(event.description, '评审Milestone 25');
      expect(event.isAllDay, isFalse);
      expect(event.reminderMinutes, 15);
    });

    test('Interval Overlap logic (S1 < E2 && E1 > S2)', () {
      final event = CalendarEvent(
        id: 'ev-1',
        title: '会议',
        startTime: DateTime(2026, 8, 30, 10, 0),
        endTime: DateTime(2026, 8, 30, 11, 0),
      );

      // Overlap case 1: Enclosing
      expect(event.overlapsWith(DateTime(2026, 8, 30, 9, 30), DateTime(2026, 8, 30, 11, 30)), isTrue);
      // Overlap case 2: Inside
      expect(event.overlapsWith(DateTime(2026, 8, 30, 10, 15), DateTime(2026, 8, 30, 10, 45)), isTrue);
      // Overlap case 3: Left overlap
      expect(event.overlapsWith(DateTime(2026, 8, 30, 9, 30), DateTime(2026, 8, 30, 10, 30)), isTrue);
      // Overlap case 4: Right overlap
      expect(event.overlapsWith(DateTime(2026, 8, 30, 10, 30), DateTime(2026, 8, 30, 11, 30)), isTrue);

      // Boundary touch: [9:00, 10:00) does NOT overlap [10:00, 11:00)
      expect(event.overlapsWith(DateTime(2026, 8, 30, 9, 0), DateTime(2026, 8, 30, 10, 0)), isFalse);
      // Boundary touch: [11:00, 12:00) does NOT overlap [10:00, 11:00)
      expect(event.overlapsWith(DateTime(2026, 8, 30, 11, 0), DateTime(2026, 8, 30, 12, 0)), isFalse);
      // Completely disjoint
      expect(event.overlapsWith(DateTime(2026, 8, 30, 14, 0), DateTime(2026, 8, 30, 15, 0)), isFalse);
    });

    test('conflictsWith ignores self id', () {
      final ev1 = CalendarEvent(
        id: 'ev-1',
        title: '会议1',
        startTime: DateTime(2026, 8, 30, 10, 0),
        endTime: DateTime(2026, 8, 30, 11, 0),
      );
      final ev2 = CalendarEvent(
        id: 'ev-2',
        title: '会议2',
        startTime: DateTime(2026, 8, 30, 10, 30),
        endTime: DateTime(2026, 8, 30, 11, 30),
      );
      expect(ev1.conflictsWith(ev1), isFalse);
      expect(ev1.conflictsWith(ev2), isTrue);
    });

    test('Json Serialization & Deserialization', () {
      final event = CalendarEvent(
        id: 'test-id',
        title: '战略研讨',
        startTime: DateTime(2026, 8, 30, 14, 0),
        endTime: DateTime(2026, 8, 30, 15, 30),
        location: '总部大厦',
        description: '季度规划',
        isAllDay: false,
        reminderMinutes: 30,
        metadata: {'tag': 'important'},
      );

      final json = event.toJson();
      final restored = CalendarEvent.fromJson(json);

      expect(restored.id, 'test-id');
      expect(restored.title, '战略研讨');
      expect(restored.startTime, DateTime(2026, 8, 30, 14, 0));
      expect(restored.endTime, DateTime(2026, 8, 30, 15, 30));
      expect(restored.location, '总部大厦');
      expect(restored.description, '季度规划');
      expect(restored.reminderMinutes, 30);
      expect(restored.metadata?['tag'], 'important');
    });

    test('toMarkdown and toFormattedString produce expected outputs', () {
      final event = CalendarEvent(
        id: 'test-id',
        title: '全天战略会议',
        startTime: DateTime(2026, 8, 30, 0, 0),
        endTime: DateTime(2026, 8, 30, 23, 59),
        location: '海滨酒店',
        description: '全员参会',
        isAllDay: true,
        reminderMinutes: 60,
      );

      expect(event.toTimeRangeString(), contains('全天'));
      expect(event.toFormattedString(), contains('📅 全天战略会议'));
      expect(event.toFormattedString(), contains('📍 海滨酒店'));
      expect(event.toFormattedString(), contains('⏰ 提前 60 分钟提醒'));

      final md = event.toMarkdown();
      expect(md, contains('**全天战略会议**'));
      expect(md, contains('海滨酒店'));
      expect(md, contains('`test-id`'));
    });

    test('CalendarEventPreview model serialization', () {
      const preview = CalendarEventPreview(
        title: '架构评审',
        timeRangeString: '2026-08-30 14:00 ~ 15:00',
        location: '会议室A',
        hasConflict: true,
        conflictingEventTitles: ['周例会'],
      );

      final json = preview.toJson();
      final restored = CalendarEventPreview.fromJson(json);

      expect(restored.title, '架构评审');
      expect(restored.timeRangeString, '2026-08-30 14:00 ~ 15:00');
      expect(restored.location, '会议室A');
      expect(restored.hasConflict, isTrue);
      expect(restored.conflictingEventTitles, ['周例会']);
    });
  });

  group('InMemoryCalendarService Tests', () {
    late InMemoryCalendarService service;

    setUp(() {
      service = InMemoryCalendarService(seedDefaults: true);
    });

    test('Loads default seeds', () async {
      final events = await service.queryEvents();
      expect(events.length, greaterThanOrEqualTo(4));
      expect(events.any((e) => e.title.contains('周例会')), isTrue);
    });

    test('queryEvents with time filter and keyword filter', () async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 0, 0);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59);

      final todayEvents = await service.queryEvents(startTime: todayStart, endTime: todayEnd);
      expect(todayEvents.isNotEmpty, isTrue);

      final searchResults = await service.queryEvents(query: '评审');
      expect(searchResults.any((e) => e.title.contains('评审')), isTrue);
    });

    test('checkConflict and hasConflict detect overlaps correctly', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Seed 1 is 10:00 to 11:30
      final conflicts = await service.checkConflict(
        today.add(const Duration(hours: 10, minutes: 15)),
        today.add(const Duration(hours: 11, minutes: 0)),
      );
      expect(conflicts.isNotEmpty, isTrue);
      expect(conflicts.first.id, 'seed-cal-1');

      final hasConf = await service.hasConflict(
        today.add(const Duration(hours: 10, minutes: 15)),
        today.add(const Duration(hours: 11, minutes: 0)),
      );
      expect(hasConf, isTrue);

      // Exclude seed-cal-1
      final noConf = await service.hasConflict(
        today.add(const Duration(hours: 10, minutes: 15)),
        today.add(const Duration(hours: 11, minutes: 0)),
        excludeId: 'seed-cal-1',
      );
      expect(noConf, isFalse);
    });

    test('createEvent, getEventById, deleteEvent and resetToDefaultSeed', () async {
      final newEvent = CalendarEvent(
        id: 'custom-event-1',
        title: '新功能发布会',
        startTime: DateTime(2026, 9, 1, 10, 0),
        endTime: DateTime(2026, 9, 1, 12, 0),
        location: '多功能厅',
      );

      await service.createEvent(newEvent);
      final fetched = await service.getEventById('custom-event-1');
      expect(fetched?.title, '新功能发布会');

      final deleted = await service.deleteEvent('custom-event-1');
      expect(deleted, isTrue);
      final afterDelete = await service.getEventById('custom-event-1');
      expect(afterDelete, isNull);

      await service.resetToDefaultSeed();
      final reseeded = await service.queryEvents();
      expect(reseeded.length, greaterThanOrEqualTo(4));
    });
  });
}
