import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chat/services/native/persistent_notification_service.dart';
import 'package:chat/providers/persistent_notification_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InMemoryPersistentNotificationService Tests', () {
    late InMemoryPersistentNotificationService service;

    setUp(() {
      service = InMemoryPersistentNotificationService();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('shows, activates and cancels persistent notification', () async {
      expect(await service.isNotificationActive('vocab_1'), isFalse);

      await service.showPersistentNotification(
        id: 'vocab_1',
        title: '📚 日语查词',
        body: '点击随时查词',
        payload: '/vocabulary',
      );

      expect(await service.isNotificationActive('vocab_1'), isTrue);

      await service.cancelPersistentNotification('vocab_1');
      expect(await service.isNotificationActive('vocab_1'), isFalse);
    });

    test('getLaunchPayload returns and consumes payload', () async {
      await service.showPersistentNotification(
        id: 'vocab_1',
        title: '查词',
        body: '详情',
        payload: '/vocabulary',
      );

      expect(await service.getLaunchPayload(), '/vocabulary');
      // Should be consumed
      expect(await service.getLaunchPayload(), isNull);
    });

    test('simulateTap emits payload to onNotificationTapped stream', () async {
      final tappedEvents = <String>[];
      final sub = service.onNotificationTapped.listen((p) => tappedEvents.add(p));

      service.simulateTap('/vocabulary');
      service.simulateTap('/settings');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(tappedEvents, ['/vocabulary', '/settings']);

      await sub.cancel();
    });
  });

  group('MethodChannelPersistentNotificationService Fallback Tests', () {
    test('safely falls back without native platform crash in headless environment', () async {
      final service = MethodChannelPersistentNotificationService();

      // In unit test environment, platform channel is missing
      await service.showPersistentNotification(
        id: 'fallback_id',
        title: '标题',
        body: '内容',
        payload: '/vocabulary',
      );

      expect(await service.isNotificationActive('fallback_id'), isTrue);
      expect(await service.getLaunchPayload(), '/vocabulary');

      await service.cancelPersistentNotification('fallback_id');
      expect(await service.isNotificationActive('fallback_id'), isFalse);

      await service.dispose();
    });
  });

  group('PersistentNotificationNotifier Tests', () {
    late InMemoryPersistentNotificationService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = InMemoryPersistentNotificationService();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('defaults to false when SharedPreferences is empty', () async {
      final notifier = PersistentNotificationNotifier(service);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.isEnabled, isFalse);
      expect(notifier.state.isInitializing, isFalse);
      expect(await service.isNotificationActive(PersistentNotificationNotifier.notificationId), isFalse);
    });

    test('restores enabled state and shows notification when saved as true', () async {
      SharedPreferences.setMockInitialValues({
        PersistentNotificationNotifier.prefKey: true,
      });

      final notifier = PersistentNotificationNotifier(service);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.isEnabled, isTrue);
      expect(await service.isNotificationActive(PersistentNotificationNotifier.notificationId), isTrue);
    });

    test('togglePersistentNotification enables and disables correctly', () async {
      final notifier = PersistentNotificationNotifier(service);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Enable
      await notifier.togglePersistentNotification(true);
      expect(notifier.state.isEnabled, isTrue);
      expect(await service.isNotificationActive(PersistentNotificationNotifier.notificationId), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PersistentNotificationNotifier.prefKey), isTrue);

      // Disable
      await notifier.togglePersistentNotification(false);
      expect(notifier.state.isEnabled, isFalse);
      expect(await service.isNotificationActive(PersistentNotificationNotifier.notificationId), isFalse);
      expect(prefs.getBool(PersistentNotificationNotifier.prefKey), isFalse);
    });
  });
}
