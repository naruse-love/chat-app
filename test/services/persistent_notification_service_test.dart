import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chat/models/vocabulary_entry.dart';
import 'package:chat/services/vocabulary_service.dart';
import 'package:chat/services/weblio_service.dart';
import 'package:chat/services/native/persistent_notification_service.dart';
import 'package:chat/providers/persistent_notification_provider.dart';

class FakeVocabularyService implements VocabularyService {
  VocabularyEntry? resultToReturn;
  Exception? exceptionToThrow;
  String? lastLookedUpWord;

  @override
  Future<VocabularyEntry> lookupWord(
    String rawWord, {
    bool forceRefresh = false,
    bool allowLlmFallback = true,
  }) async {
    lastLookedUpWord = rawWord;
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    return resultToReturn ??
        VocabularyEntry(
          vocabKanji: rawWord,
          vocabFurigana: 'ねこ',
          vocabDefJa: 'ネコ科の小型の哺乳類',
          vocabDefSc: '猫。一种家畜。',
          vocabPoS: '［名］',
          createdAt: DateTime.now(),
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
      final notif = service.getNotificationData('vocab_1');
      expect(notif?.title, '📚 日语查词');
      expect(notif?.body, '点击随时查词');

      await service.cancelPersistentNotification('vocab_1');
      expect(await service.isNotificationActive('vocab_1'), isFalse);
      expect(service.getNotificationData('vocab_1'), isNull);
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

    test('simulateInlineQuery emits query to onInlineQuerySubmitted stream', () async {
      final queries = <String>[];
      final sub = service.onInlineQuerySubmitted.listen((q) => queries.add(q));

      service.simulateInlineQuery('猫');
      service.simulateInlineQuery('桜');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(queries, ['猫', '桜']);

      await sub.cancel();
    });

    test('updateSearchResultNotification records loading, success, and error states', () async {
      // 1. Loading state
      await service.updateSearchResultNotification(
        id: 'vocab_search',
        word: '猫',
        isLoading: true,
      );

      var data = service.getNotificationData('vocab_search');
      expect(data, isNotNull);
      expect(data!.isLoading, isTrue);
      expect(data.title, contains('正在查询「猫」'));

      // 2. Success state
      await service.updateSearchResultNotification(
        id: 'vocab_search',
        word: '猫',
        reading: 'ねこ',
        definitionJa: 'ネコ科の動物',
        definitionSc: '家猫',
        partOfSpeech: '［名］',
        isLoading: false,
      );

      data = service.getNotificationData('vocab_search');
      expect(data, isNotNull);
      expect(data!.isLoading, isFalse);
      expect(data.title, '📖 猫【ねこ】');
      expect(data.body, '家猫');
      expect(data.partOfSpeech, '［名］');

      // 3. Error state
      await service.updateSearchResultNotification(
        id: 'vocab_search',
        word: '未知词',
        error: '未找到该词释义',
        isLoading: false,
      );

      data = service.getNotificationData('vocab_search');
      expect(data, isNotNull);
      expect(data!.isLoading, isFalse);
      expect(data.title, contains('未找到「未知词」的释义'));
      expect(data.body, '未找到该词释义');
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
      expect(service.getFallbackNotification('fallback_id')?.title, '标题');

      await service.updateSearchResultNotification(
        id: 'fallback_id',
        word: '犬',
        reading: 'いぬ',
        definitionSc: '狗',
      );
      expect(service.getFallbackNotification('fallback_id')?.title, '📖 犬【いぬ】');

      await service.cancelPersistentNotification('fallback_id');
      expect(await service.isNotificationActive('fallback_id'), isFalse);

      await service.dispose();
    });

    test('receives method calls on channel and emits to streams', () async {
      const channel = MethodChannel('test_persistent_notification_channel');
      final service = MethodChannelPersistentNotificationService(channel: channel);

      final tapEvents = <String>[];
      final queryEvents = <String>[];
      final tapSub = service.onNotificationTapped.listen((p) => tapEvents.add(p));
      final querySub = service.onInlineQuerySubmitted.listen((q) => queryEvents.add(q));

      // Simulate native calling onNotificationTapped
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'test_persistent_notification_channel',
        channel.codec.encodeMethodCall(const MethodCall('onNotificationTapped', '/vocabulary')),
        (ByteData? data) {},
      );

      // Simulate native calling onInlineQuerySubmitted with Map
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'test_persistent_notification_channel',
        channel.codec.encodeMethodCall(const MethodCall('onInlineQuerySubmitted', {'query': '青空'})),
        (ByteData? data) {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(tapEvents, ['/vocabulary']);
      expect(queryEvents, ['青空']);

      await tapSub.cancel();
      await querySub.cancel();
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
      notifier.dispose();
    });

    test('restores enabled state and shows notification when saved as true', () async {
      SharedPreferences.setMockInitialValues({
        PersistentNotificationNotifier.prefKey: true,
      });

      final notifier = PersistentNotificationNotifier(service);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.isEnabled, isTrue);
      expect(await service.isNotificationActive(PersistentNotificationNotifier.notificationId), isTrue);
      notifier.dispose();
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
      notifier.dispose();
    });

    test('handles inline search and updates notification with Weblio / LLM lookup result', () async {
      final fakeVocabService = FakeVocabularyService();
      bool wordSavedCalled = false;

      final notifier = PersistentNotificationNotifier(
        service,
        vocabularyService: fakeVocabService,
        onWordSaved: () {
          wordSavedCalled = true;
        },
      );

      // Simulate inline search directly
      await notifier.handleInlineSearch('猫');

      expect(fakeVocabService.lastLookedUpWord, '猫');
      expect(notifier.state.isSearching, isFalse);
      expect(notifier.state.lastSearchedWord, '猫');
      expect(notifier.state.lastSearchResult, '猫。一种家畜。');
      expect(notifier.state.lastSearchError, isNull);
      expect(wordSavedCalled, isTrue);

      final notifData = service.getNotificationData(PersistentNotificationNotifier.notificationId);
      expect(notifData, isNotNull);
      expect(notifData!.title, '📖 猫【ねこ】');
      expect(notifData.body, '猫。一种家畜。');
      expect(notifData.partOfSpeech, '［名］');

      notifier.dispose();
    });

    test('handles inline query stream event automatically', () async {
      final fakeVocabService = FakeVocabularyService();

      final notifier = PersistentNotificationNotifier(
        service,
        vocabularyService: fakeVocabService,
      );

      // Trigger via stream simulation
      service.simulateInlineQuery('桜');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(fakeVocabService.lastLookedUpWord, '桜');
      expect(notifier.state.lastSearchedWord, '桜');

      final notifData = service.getNotificationData(PersistentNotificationNotifier.notificationId);
      expect(notifData, isNotNull);
      expect(notifData!.word, '桜');

      notifier.dispose();
    });

    test('handles lookup error gracefully and updates notification with error message', () async {
      final fakeVocabService = FakeVocabularyService();
      fakeVocabService.exceptionToThrow = WeblioException('网络连接超时');

      final notifier = PersistentNotificationNotifier(
        service,
        vocabularyService: fakeVocabService,
      );

      await notifier.handleInlineSearch('未知词');

      expect(notifier.state.isSearching, isFalse);
      expect(notifier.state.lastSearchError, '网络连接超时');

      final notifData = service.getNotificationData(PersistentNotificationNotifier.notificationId);
      expect(notifData, isNotNull);
      expect(notifData!.title, contains('未找到「未知词」的释义'));
      expect(notifData.body, '网络连接超时');

      notifier.dispose();
    });

    test('ignores empty query in handleInlineSearch', () async {
      final fakeVocabService = FakeVocabularyService();
      final notifier = PersistentNotificationNotifier(
        service,
        vocabularyService: fakeVocabService,
      );

      await notifier.handleInlineSearch('   ');

      expect(fakeVocabService.lastLookedUpWord, isNull);
      expect(notifier.state.isSearching, isFalse);

      notifier.dispose();
    });
  });
}

