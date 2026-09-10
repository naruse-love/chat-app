import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/vocabulary_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/services/weblio_service.dart';
import 'package:chat/services/vocabulary_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MockFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #write) {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value != null) {
        data[key] = value;
      } else {
        data.remove(key);
      }
      return Future<void>.value();
    }
    if (invocation.memberName == #read) {
      final key = invocation.namedArguments[#key] as String;
      return Future<String?>.value(data[key]);
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeWeblioService extends WeblioService {
  int lookupCallCount = 0;

  @override
  Future<WeblioResult> lookupWord(String rawWord) async {
    lookupCallCount++;
    if (rawWord == '食べる') {
      return const WeblioResult(
        word: '食べる',
        reading: 'たべる',
        definition: '食物をかんで、のみこむ。',
        partOfSpeech: '動バ下一',
        examples: [
          WeblioExample(kanji: '生で食べる', furigana: '生[なま]で食べる'),
        ],
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/%E9%A3%9F%E3%81%B9%E3%82%8B',
      );
    }
    throw WeblioException('未在 Weblio 找到「$rawWord」的相关释义');
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
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('vocab_service_test_');
    final dbPath = p.join(tempDir.path, 'vocab_service.db');

    db = await openDatabase(
      dbPath,
      version: 5,
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
    chatService = ChatService(dio: Dio());

    vocabService = VocabularyService(
      vocabularyDao: vocabDao,
      weblioService: fakeWeblio,
      chatService: chatService,
      apiConfigDao: apiConfigDao,
      ref: null, // No LLM configured in this test suite
    );
  });

  tearDown(() async {
    await db.close();
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('VocabularyService Tests', () {
    test('lookupWord fetches from Weblio, saves to DB, and falls back gracefully when LLM is unconfigured', () async {
      final result = await vocabService.lookupWord('食べる');

      expect(result.id, isNotNull);
      expect(result.vocabKanji, '食べる');
      expect(result.vocabFurigana, 'たべる');
      expect(result.vocabDefJa, '食物をかんで、のみこむ。');
      expect(result.vocabDefSc, isEmpty); // LLM unconfigured fallback
      expect(result.sentKanji1, '生で食べる');
      expect(result.sentFurigana1, '生[なま]で食べる');
      expect(result.sourceDict, 'デジタル大辞泉');
      expect(fakeWeblio.lookupCallCount, 1);

      // Verify it was saved to DB
      final inDb = await vocabDao.findByKanji('食べる');
      expect(inDb, isNotNull);
      expect(inDb!.id, result.id);
    });

    test('lookupWord directly returns cached entry on subsequent calls (deduplication)', () async {
      // First call fetches and saves
      await vocabService.lookupWord('食べる');
      expect(fakeWeblio.lookupCallCount, 1);

      // Second call hits cache
      final cached = await vocabService.lookupWord('食べる');
      expect(cached.vocabKanji, '食べる');
      expect(fakeWeblio.lookupCallCount, 1); // No new network call
    });

    test('lookupWord with forceRefresh: true bypasses cache and refetches', () async {
      await vocabService.lookupWord('食べる');
      expect(fakeWeblio.lookupCallCount, 1);

      // Force refresh
      final refreshed = await vocabService.lookupWord('食べる', forceRefresh: true);
      expect(refreshed.vocabKanji, '食べる');
      expect(fakeWeblio.lookupCallCount, 2); // Refetched
    });

    test('lookupWord throws WeblioException for empty string', () async {
      expect(
        () => vocabService.lookupWord('  '),
        throwsA(isA<WeblioException>()),
      );
    });

    test('parseTranslationJson correctly handles markdown JSON code blocks and edge cases', () {
      const codeBlockJson = '''```json
{
  "definitionSc": "吃，咀嚼并吞咽食物",
  "exampleSc1": "生吃",
  "exampleSc2": ""
}
```''';

      final parsed = vocabService.parseTranslationJson(codeBlockJson);
      expect(parsed['definitionSc'], '吃，咀嚼并吞咽食物');
      expect(parsed['exampleSc1'], '生吃');
      expect(parsed['exampleSc2'], '');

      // Plain text fallback
      final plain = vocabService.parseTranslationJson('普通文本释义');
      expect(plain['definitionSc'], '普通文本释义');
    });
  });
}
