import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/vocabulary_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/vocabulary_entry.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/services/weblio_service.dart';
import 'package:chat/services/vocabulary_service.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/model_provider.dart';
import 'package:chat/providers/vocabulary_config_provider.dart';

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

class RecordingChatService extends ChatService {
  String? lastBaseUrl;
  String? lastApiKey;
  String? lastModel;
  String nextResponse = '';

  RecordingChatService() : super(dio: Dio());

  @override
  Future<String> getCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    CancelToken? cancelToken,
  }) async {
    lastBaseUrl = baseUrl;
    lastApiKey = apiKey;
    lastModel = model;
    return nextResponse;
  }
}

class FakeWeblioService extends WeblioService {
  @override
  Future<WeblioResult> lookupWord(
    String rawWord, {
    int maxDepth = 2,
    Set<String>? visited,
  }) async {
    return WeblioResult(
      word: rawWord,
      reading: 'よみ',
      definition: '日本語の釈義内容',
      partOfSpeech: '名',
      examples: const [
        WeblioExample(kanji: '日本語の例文', furigana: '日本語[にほんご]の例文'),
      ],
      sourceDict: '大辞泉',
      sourceUrl: 'https://weblio.jp/test',
    );
  }
}

final testRefProvider = Provider<Ref>((ref) => ref);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;
  late DatabaseHelper dbHelper;
  late VocabularyDao vocabDao;
  late ApiConfigDao apiConfigDao;
  late RecordingChatService recordingChat;
  late FakeWeblioService fakeWeblio;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('vocab_sel_test_');
    final dbPath = p.join(tempDir.path, 'test_vocab_sel.db');
    db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await DatabaseHelper.instance.testOnCreate(db, version);
        },
      ),
    );

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(db);

    final mockStorage = MockFlutterSecureStorage();
    final secService = SecureStorageService(storage: mockStorage);
    apiConfigDao = ApiConfigDao(dbHelper, secService);
    vocabDao = VocabularyDao(dbHelper: dbHelper);
    fakeWeblio = FakeWeblioService();
    recordingChat = RecordingChatService();
  });

  tearDown(() async {
    await db.close();
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('VocabularyService uses dedicated vocabulary model independent of chat model', () async {
    // 1. Setup Chat Provider with Provider A and Model A
    final chatConfig = ApiConfig(
      id: 'provider_chat',
      name: 'Chat Provider',
      baseUrl: 'https://chat-api.com/v1',
      apiKeyRef: 'key_chat',
      isDefault: true,
      createdAt: DateTime.now(),
    );
    await apiConfigDao.insert(chatConfig, 'secret-chat-key');

    // 2. Setup Vocabulary Provider with Provider B and Model B
    final vocabConfig = ApiConfig(
      id: 'provider_vocab',
      name: 'Vocab Provider',
      baseUrl: 'https://vocab-api.com/v1',
      apiKeyRef: 'key_vocab',
      isDefault: false,
      createdAt: DateTime.now(),
    );
    await apiConfigDao.insert(vocabConfig, 'secret-vocab-key');

    final vocabModel = ModelInfo(
      id: 'vocab-dedicated-llm',
      provider: 'vocab_dedicated',
      modelName: 'Vocab Dedicated LLM',
      supportsVision: false,
      supportsTools: true,
    );

    final container = ProviderContainer(
      overrides: [
        apiConfigDaoProvider.overrideWithValue(apiConfigDao),
        chatServiceProvider.overrideWithValue(recordingChat),
      ],
    );

    // Explicitly configure vocabularyConfigProvider to use vocabConfig and vocabModel
    final vocabNotifier = container.read(vocabularyConfigProvider.notifier);
    await vocabNotifier.initialization;
    await vocabNotifier.setConfig(vocabConfig);
    await vocabNotifier.setModel(vocabModel);

    final testRef = container.read(testRefProvider);

    final service = VocabularyService(
      vocabularyDao: vocabDao,
      weblioService: fakeWeblio,
      chatService: recordingChat,
      apiConfigDao: apiConfigDao,
      ref: testRef,
    );

    expect(service.hasLlmConfigured, isTrue);

    recordingChat.nextResponse = '''
```json
{
  "definitionSc": "专属词汇模型生成的中文翻译",
  "exampleSc1": "专属例句翻译",
  "exampleSc2": ""
}
```''';

    final result = await service.lookupWord('青空');

    // Verify ChatService was invoked with the dedicated vocabulary model credentials!
    expect(recordingChat.lastBaseUrl, 'https://vocab-api.com/v1');
    expect(recordingChat.lastApiKey, 'secret-vocab-key');
    expect(recordingChat.lastModel, 'vocab-dedicated-llm');

    // Verify entry has the Chinese definition
    expect(result.vocabDefSc, '专属词汇模型生成的中文翻译');
    expect(result.sentDefSc1, '专属例句翻译');

    container.dispose();
  });

  test('lookupWord automatically self-heals when cached entry has empty vocabDefSc', () async {
    // 1. Insert an entry in SQLite that has no Chinese definition (e.g. searched when unconfigured)
    final incomplete = VocabularyEntry(
      vocabKanji: '夜空',
      vocabFurigana: 'よぞら',
      vocabDefJa: '夜の空。',
      vocabDefSc: '', // Empty!
      vocabPoS: '名',
      sourceDict: '大辞泉',
      sourceUrl: '',
      createdAt: DateTime.now(),
    );
    await vocabDao.insert(incomplete);

    final defaultCfg = ApiConfig(
      id: 'opencode_free',
      name: 'OpenCode Free',
      baseUrl: 'https://opencode.ai/zen/v1',
      apiKeyRef: 'opencode_free_api_key_ref',
      isDefault: true,
      createdAt: DateTime.now(),
    );
    await apiConfigDao.insert(defaultCfg, 'open-key');

    final container = ProviderContainer(
      overrides: [
        apiConfigDaoProvider.overrideWithValue(apiConfigDao),
        chatServiceProvider.overrideWithValue(recordingChat),
      ],
    );

    final testRef = container.read(testRefProvider);
    final service = VocabularyService(
      vocabularyDao: vocabDao,
      weblioService: fakeWeblio,
      chatService: recordingChat,
      apiConfigDao: apiConfigDao,
      ref: testRef,
    );

    recordingChat.nextResponse = '''
```json
{
  "definitionSc": "夜空，夜晚的天空。",
  "exampleSc1": "",
  "exampleSc2": ""
}
```''';

    // Searching '夜空' hits cache, detects empty vocabDefSc, and self-heals via LLM
    final healed = await service.lookupWord('夜空');

    expect(healed.vocabKanji, '夜空');
    expect(healed.vocabDefSc, '夜空，夜晚的天空。');

    // Verify persisted in DB
    final inDb = await vocabDao.findByKanji('夜空');
    expect(inDb?.vocabDefSc, '夜空，夜晚的天空。');

    container.dispose();
  });

  test('retranslateEntry manually translates and updates entry in SQLite', () async {
    final entry = VocabularyEntry(
      vocabKanji: '星空',
      vocabFurigana: 'ほしぞら',
      vocabDefJa: '星の出ている夜空。',
      vocabDefSc: '',
      vocabPoS: '名',
      sourceDict: '大辞泉',
      sourceUrl: '',
      createdAt: DateTime.now(),
    );
    final id = await vocabDao.insert(entry);
    final savedEntry = entry.copyWith(id: id);

    final defaultCfg = ApiConfig(
      id: 'opencode_free',
      name: 'OpenCode Free',
      baseUrl: 'https://opencode.ai/zen/v1',
      apiKeyRef: 'opencode_free_api_key_ref',
      isDefault: true,
      createdAt: DateTime.now(),
    );
    await apiConfigDao.insert(defaultCfg, 'open-key');

    final container = ProviderContainer(
      overrides: [
        apiConfigDaoProvider.overrideWithValue(apiConfigDao),
        chatServiceProvider.overrideWithValue(recordingChat),
      ],
    );

    final testRef = container.read(testRefProvider);
    final service = VocabularyService(
      vocabularyDao: vocabDao,
      weblioService: fakeWeblio,
      chatService: recordingChat,
      apiConfigDao: apiConfigDao,
      ref: testRef,
    );

    recordingChat.nextResponse = '''
```json
{
  "definitionSc": "星空，满天星斗的夜空。",
  "exampleSc1": "",
  "exampleSc2": ""
}
```''';

    final retranslated = await service.retranslateEntry(savedEntry);
    expect(retranslated.vocabDefSc, '星空，满天星斗的夜空。');

    final inDb = await vocabDao.getById(id);
    expect(inDb?.vocabDefSc, '星空，满天星斗的夜空。');

    container.dispose();
  });
}
