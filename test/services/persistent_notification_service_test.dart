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

class DelayedFakeVocabularyService extends FakeVocabularyService {
  @override
  Future<VocabularyEntry> lookupWord(
    String rawWord, {
    bool forceRefresh = false,
    bool allowLlmFallback = true,
  }) async {
    lastLookedUpWord = rawWord;
    if (rawWord == 'slow_word') {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return VocabularyEntry(
      vocabKanji: rawWord,
      vocabFurigana: rawWord,
      vocabDefJa: '$rawWord 日文释义',
      vocabDefSc: '$rawWord 释义',
      vocabPoS: '［名］',
      createdAt: DateTime.now(),
    );
  }
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

    test('getPendingInlineQueries returns and drains queued queries', () async {
      service.addPendingQuery('猫');
      service.addPendingQuery('桜');

      expect(await service.getPendingInlineQueries(), ['猫', '桜']);
      expect(await service.getPendingInlineQueries(), isEmpty);
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

    test('getPendingInlineQueries handles channel responses', () async {
      const channel = MethodChannel('test_pending_queries_channel');
      final service = MethodChannelPersistentNotificationService(channel: channel);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'getPendingInlineQueries') {
            return [
              {'query': '富士山'},
              '東京',
            ];
          }
          return null;
        },
      );

      final queries = await service.getPendingInlineQueries();
      expect(queries, ['富士山', '東京']);

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

    test('consumes pending inline queries on initialization without overwriting notification', () async {
      final fakeVocabService = FakeVocabularyService();
      service.addPendingQuery('猫');

      SharedPreferences.setMockInitialValues({
        PersistentNotificationNotifier.prefKey: true,
      });

      final notifier = PersistentNotificationNotifier(
        service,
        vocabularyService: fakeVocabService,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(fakeVocabService.lastLookedUpWord, '猫');
      expect(notifier.state.lastSearchedWord, '猫');
      final notifData = service.getNotificationData(PersistentNotificationNotifier.notificationId);
      expect(notifData, isNotNull);
      expect(notifData!.title, '📖 猫【ねこ】');

      notifier.dispose();
    });

    test('discards out-of-order search results when newer search finishes first', () async {
      final fakeVocabService = DelayedFakeVocabularyService();
      final notifier = PersistentNotificationNotifier(
        service,
        vocabularyService: fakeVocabService,
      );

      // 启动慢查询 slow_word (60ms)
      final future1 = notifier.handleInlineSearch('slow_word');

      // 稍后启动快查询 fast_word (10ms)
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final future2 = notifier.handleInlineSearch('fast_word');

      await Future.wait([future1, future2]);

      // 最终状态与通知栏必须展示较新的 fast_word，而非被慢查询覆盖
      expect(notifier.state.lastSearchedWord, 'fast_word');
      expect(notifier.state.lastSearchResult, 'fast_word 释义');
      final notifData = service.getNotificationData(PersistentNotificationNotifier.notificationId);
      expect(notifData, isNotNull);
      expect(notifData!.word, 'fast_word');

      notifier.dispose();
    });

    test('invokes onWordSaved with VocabularyEntry upon successful lookup', () async {
      final fakeVocabService = FakeVocabularyService();
      VocabularyEntry? savedEntry;

      final notifier = PersistentNotificationNotifier(
        service,
        vocabularyService: fakeVocabService,
        onWordSaved: (entry) {
          savedEntry = entry;
        },
      );

      await notifier.handleInlineSearch('猫');

      expect(savedEntry, isNotNull);
      expect(savedEntry!.vocabKanji, '猫');

      notifier.dispose();
    });
  });

  group('condenseNotificationDefinition Tests', () {
    test('returns empty string for null or empty text', () {
      expect(condenseNotificationDefinition(null), '');
      expect(condenseNotificationDefinition(''), '');
      expect(condenseNotificationDefinition('   '), '');
    });

    test('preserves short definitions with 1 or 2 items without hint', () {
      const shortDef = '1. 食用；进食。\n2. 过日子，生活。';
      final condensed = condenseNotificationDefinition(shortDef);
      expect(condensed, shortDef);
      expect(condensed.contains('(更多可在App内查看)'), isFalse);
    });

    test('condenses polysemous definitions like 君 (9+ meanings) to top 3 and appends hint', () {
      const longKimiDef =
          '1. （古代称呼）君主，帝王。\n'
          '2. 贵人，长辈。\n'
          '3. （女性对男性恋人或丈夫的亲昵称呼）你，君。\n'
          '4. （平辈或对晚辈、后辈的第二人称代词）你。\n'
          '5. （接尾词）...君（尊称或同辈称呼）。\n'
          '6. 神明或敬仰的对象。\n'
          '7. 封建时代对领主的尊称。\n'
          '8. 艺妓、游女的雅称。\n'
          '9. （下接语）若君、小君。';

      final condensed = condenseNotificationDefinition(longKimiDef, maxItems: 3);
      expect(condensed.contains('1. （古代称呼）君主，帝王。'), isTrue);
      expect(condensed.contains('2. 贵人，长辈。'), isTrue);
      expect(condensed.contains('3. （女性对男性恋人或丈夫的亲昵称呼）你，君。'), isTrue);
      expect(condensed.contains('4. （平辈或对晚辈'), isFalse);
      expect(condensed.endsWith('(更多可在App内查看)'), isTrue);
    });

    test('truncates overly long single-line definition if exceeding maxLength', () {
      final veryLong = 'A' * 200;
      final condensed = condenseNotificationDefinition(veryLong, maxLength: 80);
      expect(condensed.length, lessThanOrEqualTo(100));
      expect(condensed.endsWith('(更多可在App内查看)'), isTrue);
    });
  });
}


