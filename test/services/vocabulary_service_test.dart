import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/vocabulary_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/vocabulary_entry.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/model_provider.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/services/weblio_service.dart';
import 'package:chat/services/vocabulary_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FakeChatService extends ChatService {
  String nextResponse = '';

  FakeChatService() : super(dio: Dio());

  @override
  Future<String> getCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    CancelToken? cancelToken,
  }) async {
    return nextResponse;
  }
}

class MockApiConfigNotifier extends ApiConfigNotifier {
  MockApiConfigNotifier(super.apiConfigDao, ApiConfig config) {
    state = ApiConfigState(configs: [config], activeConfig: config);
  }
}

class MockModelNotifier extends ModelNotifier {
  MockModelNotifier(
    super.chatService,
    super.apiConfigDao,
    super.activeConfig,
    ModelInfo model,
  ) {
    state = ModelState(models: [model], selectedModel: model);
  }
}

final testRefProvider = Provider<Ref>((ref) => ref);

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
  Future<WeblioResult> lookupWord(
    String rawWord, {
    int maxDepth = 2,
    Set<String>? visited,
  }) async {
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
    if (rawWord == '講じる') {
      return const WeblioResult(
        word: '講じる',
        reading: 'こうじる',
        definition: '「こう（講）ずる」（サ変）の上一段化。\n１ 講義をする。\n２ 問題を解決するために、考えをめぐらして適当な方法をとる。',
        partOfSpeech: '動ザ上一',
        examples: [
          WeblioExample(kanji: '適切な処置を講じる', furigana: '適切な処置を講じる'),
        ],
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/%E8%AC%9B%E3%81%98%E3%82%8B',
      );
    }
    if (rawWord == '問題単語') {
      // 模拟释义有缺陷的死胡同重定向
      return const WeblioResult(
        word: '問題単語',
        reading: 'もんだいたんご',
        definition: '「未定義語」（サ変）の上一段化。',
        partOfSpeech: '名',
        sourceDict: 'デジタル大辞泉',
        sourceUrl: '',
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

    test('lookupWord with forceRefresh: true bypasses cache and refetches without duplicating rows', () async {
      await vocabService.lookupWord('食べる');
      expect(fakeWeblio.lookupCallCount, 1);
      expect(await vocabDao.count(), 1);

      // Force refresh
      final refreshed = await vocabService.lookupWord('食べる', forceRefresh: true);
      expect(refreshed.vocabKanji, '食べる');
      expect(fakeWeblio.lookupCallCount, 2); // Refetched

      // Database should still contain exactly 1 entry for this word
      expect(await vocabDao.count(), 1);
      final allEntries = await vocabDao.getAll();
      expect(allEntries.length, 1);
      expect(allEntries.first.vocabKanji, '食べる');
    });

    test('lookupWord throws WeblioException for empty string', () async {
      expect(
        () => vocabService.lookupWord('  '),
        throwsA(isA<WeblioException>()),
      );
    });

    test('parseTranslationJson correctly handles markdown JSON code blocks with conversational preamble and edge cases', () {
      const conversationalResponse = '''
好的，这是为您翻译的日语单词释义与例句：
```json
{
  "definitionSc": "吃，咀嚼并吞咽食物",
  "exampleSc1": "生吃",
  "exampleSc2": ""
}
```
如有其他需要，请随时告诉我！''';

      final parsed = vocabService.parseTranslationJson(conversationalResponse);
      expect(parsed['definitionSc'], '吃，咀嚼并吞咽食物');
      expect(parsed['exampleSc1'], '生吃');
      expect(parsed['exampleSc2'], '');

      // Plain text fallback
      final plain = vocabService.parseTranslationJson('普通文本释义');
      expect(plain['definitionSc'], '普通文本释义');
    });

    test('lookupWord for 講じる preserves merged dictionary definition text (保持原文)', () async {
      final result = await vocabService.lookupWord('講じる');

      expect(result.vocabKanji, '講じる');
      expect(result.vocabFurigana, 'こうじる');
      expect(result.vocabPoS, '動ザ上一');
      expect(result.sourceDict, 'デジタル大辞泉');
      // Must preserve the grammatical note from dictionary
      expect(result.vocabDefJa, contains('「こう（講）ずる」（サ変）の上一段化。'));
      // Must preserve the root word definitions from dictionary
      expect(result.vocabDefJa, contains('１ 講義をする。'));
      expect(result.vocabDefJa, contains('２ 問題を解決するために'));
      // Preserves original example
      expect(result.sentKanji1, '適切な処置を講じる');

      // Verify persisted in DB
      final inDb = await vocabDao.findByKanji('講じる');
      expect(inDb, isNotNull);
      expect(inDb!.vocabDefJa, contains('「こう（講）ずる」（サ変）の上一段化。'));
    });

    test('parseTranslationJson extracts definitionJa, definitionSc, exampleSc and supplement sentences', () {
      const richJson = '''
```json
{
  "definitionJa": "１ 講義をする。２ 対策を立てる。",
  "definitionSc": "1. 讲学；2. 采取对策",
  "exampleSc1": "采取适当的措施",
  "exampleSc2": "讲授近代经济学",
  "supplementSentKanji1": "策を講じる",
  "supplementSentFurigana1": "策[さく]を 講[こう]じる",
  "supplementDefSc1": "想办法采取对策"
}
```''';

      final parsed = vocabService.parseTranslationJson(richJson);
      expect(parsed['definitionJa'], '１ 講義をする。２ 対策を立てる。');
      expect(parsed['definitionSc'], '1. 讲学；2. 采取对策');
      expect(parsed['exampleSc1'], '采取适当的措施');
      expect(parsed['exampleSc2'], '讲授近代经济学');
      expect(parsed['supplementSentKanji1'], '策を講じる');
      expect(parsed['supplementSentFurigana1'], '策[さく]を 講[こう]じる');
      expect(parsed['supplementDefSc1'], '想办法采取对策');
    });

    test('parseFallbackEntryJson parses complete fallback JSON into VocabularyEntry with Anki ruby format', () {
      const fallbackJson = '''
{
  "furigana": "しんぞうご",
  "partOfSpeech": "［名］",
  "definitionJa": "新しく作られた言葉。新語。",
  "definitionSc": "新造的词语，新词。",
  "sentKanji1": "若者が新造語を使う",
  "sentFurigana1": "若者[わかもの]が 新造語[しんぞうご]を 使[つか]う",
  "sentDefSc1": "年轻人使用新造词",
  "sentKanji2": "",
  "sentFurigana2": "",
  "sentDefSc2": ""
}''';

      final entry = vocabService.parseFallbackEntryJson(fallbackJson, '新造語');
      expect(entry.vocabKanji, '新造語');
      expect(entry.vocabFurigana, 'しんぞうご');
      expect(entry.vocabPoS, '［名］');
      expect(entry.vocabDefJa, '新しく作られた言葉。新語。');
      expect(entry.vocabDefSc, '新造的词语，新词。');
      expect(entry.sentKanji1, '若者が新造語を使う');
      expect(entry.sentFurigana1, '若者[わかもの]が 新造語[しんぞうご]を 使[つか]う');
      expect(entry.sentDefSc1, '年轻人使用新造词');
      expect(entry.sentKanji2, isNull);
      expect(entry.sourceDict, 'AI兜底生成');

      // Edge case: malformed plain text fallback
      final plainEntry = vocabService.parseFallbackEntryJson('单纯解释文本', 'テスト語');
      expect(plainEntry.vocabKanji, 'テスト語');
      expect(plainEntry.vocabDefSc, '单纯解释文本');
      expect(plainEntry.sourceDict, 'AI兜底生成');
    });

    test('lookupWord uses LLM fallback when word is not in Weblio and LLM is configured', () async {
      final testConfig = ApiConfig(
        id: 'cfg_1',
        name: 'OpenAI Test',
        baseUrl: 'https://api.openai.com/v1',
        apiKeyRef: 'sec_key_1',
        isDefault: true,
        createdAt: DateTime.now(),
      );
      final testModel = ModelInfo(
        id: 'gpt-4o',
        provider: 'openai',
        modelName: 'gpt-4o',
        supportsVision: true,
        supportsTools: true,
      );

      final fakeChat = FakeChatService();
      fakeChat.nextResponse = '''
```json
{
  "furigana": "しんぞうご",
  "partOfSpeech": "［名］",
  "definitionJa": "新しく作られた言葉。新語。",
  "definitionSc": "新造的词语，新词。",
  "sentKanji1": "若者が新造語を使う",
  "sentFurigana1": "若者[わかもの]が 新造語[しんぞうご]を 使[つか]う",
  "sentDefSc1": "年轻人使用新词",
  "sentKanji2": "",
  "sentFurigana2": "",
  "sentDefSc2": ""
}
```''';

      final container = ProviderContainer(
        overrides: [
          apiConfigProvider.overrideWith((ref) => MockApiConfigNotifier(apiConfigDao, testConfig)),
          modelProvider.overrideWith((ref) => MockModelNotifier(fakeChat, apiConfigDao, null, testModel)),
        ],
      );

      final ref = container.read(testRefProvider);

      final serviceWithLlm = VocabularyService(
        vocabularyDao: vocabDao,
        weblioService: fakeWeblio,
        chatService: fakeChat,
        apiConfigDao: apiConfigDao,
        ref: ref,
      );

      expect(serviceWithLlm.hasLlmConfigured, isTrue);

      // '新造語' throws WeblioException in fakeWeblio, so it triggers AI fallback
      final result = await serviceWithLlm.lookupWord('新造語');

      expect(result.vocabKanji, '新造語');
      expect(result.vocabFurigana, 'しんぞうご');
      expect(result.vocabDefJa, '新しく作られた言葉。新語。');
      expect(result.vocabDefSc, '新造的词语，新词。');
      expect(result.sourceDict, 'AI兜底生成');
      expect(result.sentKanji1, '若者が新造語を使う');

      // Verify persisted in DB
      final inDb = await vocabDao.findByKanji('新造語');
      expect(inDb, isNotNull);
      expect(inDb!.sourceDict, 'AI兜底生成');

      container.dispose();
    });

    test('lookupWord rewrites definitionJa using LLM when dictionary definition is problematic/dead-end', () async {
      final testConfig = ApiConfig(
        id: 'cfg_1',
        name: 'OpenAI Test',
        baseUrl: 'https://api.openai.com/v1',
        apiKeyRef: 'sec_key_1',
        isDefault: true,
        createdAt: DateTime.now(),
      );
      final testModel = ModelInfo(
        id: 'gpt-4o',
        provider: 'openai',
        modelName: 'gpt-4o',
        supportsVision: true,
        supportsTools: true,
      );

      final fakeChat = FakeChatService();
      // When definition is problematic, LLM generates a complete definitionJa
      fakeChat.nextResponse = '''
```json
{
  "definitionJa": "論理的または実質的な欠陥を含む問題のある語句。",
  "definitionSc": "有问题的词语，包含逻辑或实质缺陷的词。",
  "exampleSc1": "",
  "exampleSc2": ""
}
```''';

      final container = ProviderContainer(
        overrides: [
          apiConfigProvider.overrideWith((ref) => MockApiConfigNotifier(apiConfigDao, testConfig)),
          modelProvider.overrideWith((ref) => MockModelNotifier(fakeChat, apiConfigDao, null, testModel)),
        ],
      );

      final ref = container.read(testRefProvider);

      final serviceWithLlm = VocabularyService(
        vocabularyDao: vocabDao,
        weblioService: fakeWeblio,
        chatService: fakeChat,
        apiConfigDao: apiConfigDao,
        ref: ref,
      );

      // '問題単語' returns a dead-end redirect without substantive definition
      final result = await serviceWithLlm.lookupWord('問題単語');

      expect(result.vocabKanji, '問題単語');
      // vocabDefJa should be rewritten by AI
      expect(result.vocabDefJa, '論理的または実質的な欠陥を含む問題のある語句。');
      expect(result.vocabDefSc, '有问题的词语，包含逻辑或实质缺陷的词。');

      container.dispose();
    });

    test('sanitizeDefinitionSc strips unwanted meta-syntactic preamble when substantive translation follows', () {
      expect(
        VocabularyService.sanitizeDefinitionSc('“講ずる”的上一段活用。1. 讲授；2. 采取对策'),
        '1. 讲授；2. 采取对策',
      );
      expect(
        VocabularyService.sanitizeDefinitionSc('是講ずる的上一段化；采取措施'),
        '采取措施',
      );
      expect(
        VocabularyService.sanitizeDefinitionSc('1. 讲座；2. 采取措施'),
        '1. 讲座；2. 采取措施',
      );
    });

    test('lookupWord automatically heals defective cached entry lacking substantive definition', () async {
      // Pre-seed a defective cache entry in DB (as might have been saved before the fix)
      final defective = VocabularyEntry(
        vocabKanji: '講じる',
        vocabFurigana: 'こうじる',
        vocabDefJa: '「こう（講）ずる」（サ変）の上一段化。', // Lacks substantive definition
        vocabDefSc: '是講ずる的上一段活用',
        vocabPoS: '動ザ上一',
        createdAt: DateTime.now(),
      );
      await vocabDao.insert(defective);

      // lookupWord without forceRefresh should detect that the cache is defective and re-fetch to heal it
      final healed = await vocabService.lookupWord('講じる');
      expect(healed.vocabKanji, '講じる');
      expect(healed.vocabDefJa, contains('１ 講義をする。'));
      expect(healed.vocabDefJa, contains('２ 問題を解決するために'));

      // Confirm DB is updated with healed entry
      final inDb = await vocabDao.findByKanji('講じる');
      expect(inDb, isNotNull);
      expect(inDb!.vocabDefJa, contains('１ 講義をする。'));
    });
  });
}
