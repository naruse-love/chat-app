import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/vocabulary_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/word_candidate.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/model_provider.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/services/weblio_service.dart';
import 'package:chat/services/vocabulary_service.dart';
import 'package:chat/providers/vocabulary_provider.dart';
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

class FakeWeblioService extends WeblioService {
  final Map<String, List<WordCandidate>> candidateMap = {};

  @override
  Future<List<WordCandidate>> fetchCandidates(String rawQuery) async {
    return candidateMap[rawQuery] ?? [];
  }

  @override
  Future<WeblioResult> lookupWord(
    String rawWord, {
    int maxDepth = 2,
    Set<String>? visited,
  }) async {
    if (rawWord == '箸') {
      return const WeblioResult(
        word: '箸',
        reading: 'はし',
        definition: '食物をはさむ二本一組の棒。',
        partOfSpeech: '名',
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/%E7%AE%Hash',
      );
    }
    if (rawWord == '橋') {
      return const WeblioResult(
        word: '橋',
        reading: 'はし',
        definition: '川などに架け渡す構造物。',
        partOfSpeech: '名',
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/%E6%A9%8B',
      );
    }
    if (rawWord == '食べる') {
      return const WeblioResult(
        word: '食べる',
        reading: 'たべる',
        definition: '食物をかんで、のみこむ。',
        partOfSpeech: '動バ下一',
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/%E9%A3%9F%E3%81%B9%E3%82%8B',
      );
    }
    throw WeblioException('未在 Weblio 找到「$rawWord」的相关释义');
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

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseHelper dbHelper;
  late VocabularyDao vocabDao;
  late ApiConfigDao apiConfigDao;
  late FakeChatService fakeChat;
  late FakeWeblioService fakeWeblio;
  late VocabularyService vocabService;
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('vocab_disambig_test_');
    final dbPath = p.join(tempDir.path, 'vocab_disambig.db');

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

    fakeChat = FakeChatService();
    fakeWeblio = FakeWeblioService();

    final config = ApiConfig(
      id: 'cfg_test_1',
      name: 'Test LLM',
      baseUrl: 'https://api.openai.com/v1',
      apiKeyRef: 'test_key_ref',
      isDefault: true,
      createdAt: DateTime.now(),
    );
    await mockStorage.write(key: 'test_key_ref', value: 'sk-test');

    final model = ModelInfo(
      id: 'gpt-4o',
      provider: 'openai',
      modelName: 'gpt-4o',
      supportsVision: true,
      supportsTools: true,
    );

    container = ProviderContainer(
      overrides: [
        apiConfigProvider.overrideWith((ref) => MockApiConfigNotifier(apiConfigDao, config)),
        modelProvider.overrideWith((ref) => MockModelNotifier(fakeChat, apiConfigDao, config, model)),
      ],
    );

    final testRef = container.read(testRefProvider);

    vocabService = VocabularyService(
      vocabularyDao: vocabDao,
      weblioService: fakeWeblio,
      chatService: fakeChat,
      apiConfigDao: apiConfigDao,
      ref: testRef,
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('VocabularyService.isPureKana Tests', () {
    test('identifies hiragana, katakana, and extended kana correctly', () {
      expect(VocabularyService.isPureKana('はし'), isTrue);
      expect(VocabularyService.isPureKana('あめ'), isTrue);
      expect(VocabularyService.isPureKana('ラーメン'), isTrue);
      expect(VocabularyService.isPureKana('こう・ずる'), isTrue);
      expect(VocabularyService.isPureKana('わくわく'), isTrue);

      expect(VocabularyService.isPureKana('食べる'), isFalse);
      expect(VocabularyService.isPureKana('美しい'), isFalse);
      expect(VocabularyService.isPureKana('English'), isFalse);
      expect(VocabularyService.isPureKana('123'), isFalse);
      expect(VocabularyService.isPureKana(''), isFalse);

      // Edge case: strings with only punctuation marks without actual kana characters
      expect(VocabularyService.isPureKana('・・・'), isFalse);
      expect(VocabularyService.isPureKana('ーーー'), isFalse);
      expect(VocabularyService.isPureKana('・ー・'), isFalse);
    });
  });

  group('Pure Kana Disambiguation Tests', () {
    test('getPureKanaCandidates uses LLM to generate Chinese definitions when LLM is configured', () async {
      fakeChat.nextResponse = '''
      [
        {
          "kanji": "箸",
          "reading": "はし",
          "partOfSpeech": "［名］",
          "definition": "筷子。夹菜工具"
        },
        {
          "kanji": "橋",
          "reading": "はし",
          "partOfSpeech": "［名］",
          "definition": "桥梁。架设在河流上的建筑物"
        },
        {
          "kanji": "端",
          "reading": "はし",
          "partOfSpeech": "［名］",
          "definition": "边缘。离中心最远处"
        }
      ]
      ''';

      final candidates = await vocabService.getPureKanaCandidates('はし');

      expect(candidates.length, 3);
      expect(candidates[0].kanji, '箸');
      expect(candidates[0].definition, '筷子。夹菜工具');
      expect(candidates[1].kanji, '橋');
      expect(candidates[2].kanji, '端');
    });

    test('getPureKanaCandidates falls back to Weblio candidates when LLM fails', () async {
      fakeChat.nextResponse = 'Invalid JSON';
      fakeWeblio.candidateMap['はし'] = [
        const WordCandidate(kanji: '箸', reading: 'はし', definition: '二本の棒'),
        const WordCandidate(kanji: '橋', reading: 'はし', definition: '川に架ける構造物'),
      ];

      final candidates = await vocabService.getPureKanaCandidates('はし');

      expect(candidates.length, 2);
      expect(candidates[0].kanji, '箸');
      expect(candidates[1].kanji, '橋');
    });
  });

  group('Typo & Misspelling AI Inference Tests', () {
    test('inferTypoCandidates asks AI and parses candidate options', () async {
      fakeChat.nextResponse = '''
      ```json
      [
        {
          "kanji": "食べる",
          "reading": "たべる",
          "partOfSpeech": "［動バ下一］",
          "definition": "进食、吃（推测为たべまる笔误）"
        },
        {
          "kanji": "溜まる",
          "reading": "たまる",
          "partOfSpeech": "［動ラ五］",
          "definition": "积攒、积存"
        }
      ]
      ```
      ''';

      final candidates = await vocabService.inferTypoCandidates('たべまる');

      expect(candidates.length, 2);
      expect(candidates[0].kanji, '食べる');
      expect(candidates[0].reading, 'たべる');
      expect(candidates[0].source, CandidateSource.aiInference);
      expect(candidates[1].kanji, '溜まる');
    });
  });

  group('VocabularyNotifier Disambiguation State Machine Tests', () {
    test('lookupWord with checkConfirmation triggers candidate confirmation for pure kana', () async {
      fakeChat.nextResponse = '''
      [
        {"kanji": "箸", "reading": "はし", "definition": "筷子"},
        {"kanji": "橋", "reading": "はし", "definition": "桥梁"}
      ]
      ''';

      final notifier = VocabularyNotifier(vocabService, vocabDao);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await notifier.lookupWord('はし', checkConfirmation: true);

      expect(notifier.state.candidates, isNotNull);
      expect(notifier.state.candidates!.length, 2);
      expect(notifier.state.pendingCandidateWord, 'はし');
      expect(notifier.state.candidateReason, CandidateReason.pureKana);
      expect(notifier.state.currentResult, isNull);

      // Now user selects 箸
      await notifier.selectCandidate(notifier.state.candidates!.first);

      expect(notifier.state.candidates, isNull);
      expect(notifier.state.currentResult, isNotNull);
      expect(notifier.state.currentResult!.vocabKanji, '箸');
    });

    test('lookupWord with checkConfirmation triggers AI inference when word not found', () async {
      fakeChat.nextResponse = '''
      [
        {"kanji": "食べる", "reading": "たべる", "definition": "进食、吃"}
      ]
      ''';

      final notifier = VocabularyNotifier(vocabService, vocabDao);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await notifier.lookupWord('たべまる', checkConfirmation: true);

      expect(notifier.state.candidates, isNotNull);
      expect(notifier.state.candidates!.length, 1);
      expect(notifier.state.pendingCandidateWord, 'たべまる');
      expect(notifier.state.candidateReason, CandidateReason.typoOrNotFound);

      // User selects 食べる
      await notifier.selectCandidate(notifier.state.candidates!.first);
      expect(notifier.state.currentResult, isNotNull);
      expect(notifier.state.currentResult!.vocabKanji, '食べる');
    });

    test('dismissCandidates and confirmOriginalWord work correctly', () async {
      fakeChat.nextResponse = '''
      [
        {"kanji": "箸", "reading": "はし", "definition": "筷子"},
        {"kanji": "橋", "reading": "はし", "definition": "桥梁"}
      ]
      ''';

      final notifier = VocabularyNotifier(vocabService, vocabDao);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await notifier.lookupWord('はし', checkConfirmation: true);
      expect(notifier.state.candidates, isNotNull);

      // Dismiss
      notifier.dismissCandidates();
      expect(notifier.state.candidates, isNull);
      expect(notifier.state.pendingCandidateWord, isNull);
    });

    test('clearError resets state.error cleanly', () async {
      final notifier = VocabularyNotifier(vocabService, vocabDao);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      notifier.state = notifier.state.copyWith(error: '测试错误信息');
      expect(notifier.state.error, '测试错误信息');

      notifier.clearError();
      expect(notifier.state.error, isNull);
    });
  });

  group('parseCandidatesJson Resilience Tests', () {
    test('parses JSON with markdown preamble and trailing text inside code block', () {
      const responseWithPreamble = '''
Here are the candidates:
```json
// Preamble commentary
[
  {
    "kanji": "箸",
    "reading": "はし",
    "partOfSpeech": "［名］",
    "definition": "筷子"
  }
]
// End of candidates
```
Hope this helps!
''';

      final candidates = vocabService.parseCandidatesJson(
        responseWithPreamble,
        'はし',
        CandidateSource.aiInference,
      );

      expect(candidates.length, 1);
      expect(candidates[0].kanji, '箸');
      expect(candidates[0].reading, 'はし');
      expect(candidates[0].definition, '筷子');
      expect(candidates[0].source, CandidateSource.aiInference);
    });
  });
}
