import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/vocabulary_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/models/vocabulary_entry.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/services/weblio_service.dart';
import 'package:chat/services/vocabulary_service.dart';
import 'package:chat/services/anki_export_service.dart';
import 'package:chat/providers/vocabulary_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MockFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return Future<void>.value();
  }
}

class FakeWeblioService extends WeblioService {
  @override
  Future<WeblioResult> lookupWord(
    String rawWord, {
    int maxDepth = 2,
    Set<String>? visited,
  }) async {
    if (rawWord == '美しい') {
      return const WeblioResult(
        word: '美しい',
        reading: 'うつくしい',
        definition: '色・形・音などの調和がとれていて快く感じられるさま。',
        partOfSpeech: '形',
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/%E7%BE%8E%E3%81%97%E3%81%84',
      );
    }
    throw WeblioException('未在 Weblio 找到「$rawWord」的相关释义');
  }
}

class FakeAnkiExportService implements AnkiExportServiceInterface {
  bool available = true;
  bool permission = true;
  List<VocabularyEntry> lastExported = [];
  bool throwError = false;

  @override
  Future<bool> isAnkiDroidAvailable() async => available;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<AnkiExportResult> exportEntries(
    List<VocabularyEntry> entries, {
    String? deckName,
    String? modelName,
  }) async {
    if (throwError) {
      throw Exception('导出异常');
    }
    lastExported = List.from(entries);
    return AnkiExportResult(
      successCount: entries.length,
      skipCount: 0,
    );
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseHelper dbHelper;
  late VocabularyDao vocabDao;
  late ApiConfigDao apiConfigDao;
  late FakeWeblioService fakeWeblio;
  late ChatService chatService;
  late VocabularyService vocabService;
  late FakeAnkiExportService fakeAnkiExport;
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('vocab_provider_test_');
    final dbPath = p.join(tempDir.path, 'vocab_provider.db');

    db = await openDatabase(
      dbPath,
      version: 6,
      onCreate: (db, version) async {
        await DatabaseHelper.instance.testOnCreate(db, version);
      },
    );

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(db);
    vocabDao = VocabularyDao(dbHelper: dbHelper);

    final mockStorage = MockFlutterSecureStorage();
    final secService = SecureStorageService(storage: mockStorage);
    apiConfigDao = ApiConfigDao(dbHelper, secService);

    fakeWeblio = FakeWeblioService();
    fakeAnkiExport = FakeAnkiExportService();
    chatService = ChatService(dio: Dio());

    vocabService = VocabularyService(
      vocabularyDao: vocabDao,
      weblioService: fakeWeblio,
      chatService: chatService,
      apiConfigDao: apiConfigDao,
      ref: null,
    );

    container = ProviderContainer(
      overrides: [
        vocabularyDaoProvider.overrideWithValue(vocabDao),
        weblioServiceProvider.overrideWithValue(fakeWeblio),
        vocabularyServiceProvider.overrideWithValue(vocabService),
        ankiExportServiceProvider.overrideWithValue(fakeAnkiExport),
      ],
    );

    // Allow initial loadEntries() to settle
    await Future.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('VocabularyNotifier Tests', () {
    test('initial state has empty entries and no error', () {
      final state = container.read(vocabularyProvider);
      expect(state.entries, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.currentResult, isNull);
    });

    test('lookupWord updates state with currentResult and updates entries list', () async {
      final notifier = container.read(vocabularyProvider.notifier);

      await notifier.lookupWord('美しい');

      final state = container.read(vocabularyProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.currentResult, isNotNull);
      expect(state.currentResult!.vocabKanji, '美しい');
      expect(state.entries.length, 1);
      expect(state.entries.first.vocabKanji, '美しい');
    });

    test('lookupWord on failure sets state.error and stops loading', () async {
      final notifier = container.read(vocabularyProvider.notifier);

      await notifier.lookupWord('unknownword');

      final state = container.read(vocabularyProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, contains('未在 Weblio 找到「unknownword」的相关释义'));
    });

    test('deleteEntry removes entry and clears currentResult if currently selected', () async {
      final notifier = container.read(vocabularyProvider.notifier);
      await notifier.lookupWord('美しい');

      var state = container.read(vocabularyProvider);
      final entryId = state.currentResult!.id!;
      expect(state.entries.length, 1);

      await notifier.deleteEntry(entryId);

      state = container.read(vocabularyProvider);
      expect(state.entries, isEmpty);
      expect(state.currentResult, isNull);
    });

    test('selectEntry and clearCurrentResult toggle currentResult', () {
      final notifier = container.read(vocabularyProvider.notifier);
      final dummy = VocabularyEntry(
        id: 99,
        vocabKanji: 'テスト',
        createdAt: DateTime.now(),
      );

      notifier.selectEntry(dummy);
      expect(container.read(vocabularyProvider).currentResult?.id, 99);

      notifier.clearCurrentResult();
      expect(container.read(vocabularyProvider).currentResult, isNull);
    });

    test('setSearchQuery updates searchQuery and reloads entries', () async {
      await vocabDao.insert(VocabularyEntry(
        vocabKanji: '走る',
        vocabDefSc: '跑步',
        createdAt: DateTime.now(),
      ));
      await vocabDao.insert(VocabularyEntry(
        vocabKanji: '食べる',
        vocabDefSc: '吃',
        createdAt: DateTime.now(),
      ));

      final notifier = container.read(vocabularyProvider.notifier);
      await notifier.loadEntries();
      expect(container.read(vocabularyProvider).entries.length, 2);

      notifier.setSearchQuery('跑步');
      await Future.delayed(const Duration(milliseconds: 50));

      final filteredState = container.read(vocabularyProvider);
      expect(filteredState.searchQuery, '跑步');
      expect(filteredState.entries.length, 1);
      expect(filteredState.entries.first.vocabKanji, '走る');
    });

    test('unexportedCount tracks new words and exportToAnki marks them exported', () async {
      final notifier = container.read(vocabularyProvider.notifier);
      expect(container.read(vocabularyProvider).unexportedCount, 0);

      // 查询单词入库
      await notifier.lookupWord('美しい');
      expect(container.read(vocabularyProvider).unexportedCount, 1);
      expect(container.read(vocabularyProvider).entries.first.exportedToAnki, isFalse);

      // 执行导出到 Anki
      final result = await notifier.exportToAnki(deckName: '测试牌组', modelName: '测试模型');
      expect(result.successCount, 1);
      expect(result.skipCount, 0);
      expect(result.failedEntries, isEmpty);

      // 导出后未导出计数归零且列表项被标记为已导出
      final stateAfter = container.read(vocabularyProvider);
      expect(stateAfter.unexportedCount, 0);
      expect(stateAfter.isExporting, isFalse);
      expect(stateAfter.entries.first.exportedToAnki, isTrue);

      // 重置导出状态
      await notifier.resetExportStatus();
      final stateReset = container.read(vocabularyProvider);
      expect(stateReset.unexportedCount, 1);
      expect(stateReset.entries.first.exportedToAnki, isFalse);
    });

    test('exportToAnki handles empty unexported list without calling service', () async {
      final notifier = container.read(vocabularyProvider.notifier);
      final result = await notifier.exportToAnki();
      expect(result.totalProcessed, 0);
      expect(fakeAnkiExport.lastExported, isEmpty);
    });

    test('exportToAnki handles service failure gracefully and sets error', () async {
      fakeAnkiExport.throwError = true;
      final notifier = container.read(vocabularyProvider.notifier);
      await notifier.lookupWord('美しい');

      final result = await notifier.exportToAnki();
      expect(result.isSuccess, isFalse);
      expect(result.errors.first, contains('导出异常'));
      expect(container.read(vocabularyProvider).isExporting, isFalse);
      expect(container.read(vocabularyProvider).error, contains('导出异常'));
    });
  });
}
