import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/secure_storage_service.dart';
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

class FakeChatService extends ChatService {
  FakeChatService() : super(dio: Dio());

  @override
  Future<List<ModelInfo>> getModels({
    required String baseUrl,
    required String apiKey,
    CancelToken? cancelToken,
  }) async {
    return [
      ModelInfo(
        id: 'mock-model-1',
        provider: 'mock',
        modelName: 'Mock Model 1',
        supportsVision: false,
        supportsTools: true,
      ),
      ModelInfo(
        id: 'mock-model-2',
        provider: 'mock',
        modelName: 'Mock Model 2',
        supportsVision: true,
        supportsTools: true,
      ),
    ];
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Database db;
  late DatabaseHelper dbHelper;
  late ApiConfigDao apiConfigDao;
  late FakeChatService fakeChat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('vocab_cfg_test_');
    final dbPath = p.join(tempDir.path, 'test_vocab_cfg.db');
    db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE api_configs (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              baseUrl TEXT NOT NULL,
              apiKeyRef TEXT NOT NULL,
              isDefault INTEGER NOT NULL DEFAULT 0,
              createdAt INTEGER NOT NULL
            )
          ''');
        },
      ),
    );

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(db);

    final mockStorage = MockFlutterSecureStorage();
    final secService = SecureStorageService(storage: mockStorage);
    apiConfigDao = ApiConfigDao(dbHelper, secService);
    fakeChat = FakeChatService();
  });

  tearDown(() async {
    await db.close();
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('VocabularyConfigNotifier loads default config & model when no preferences saved', () async {
    final notifier = VocabularyConfigNotifier(apiConfigDao, fakeChat);
    await notifier.initialization;

    expect(notifier.state.config, isNotNull);
    expect(notifier.state.config!.id, 'opencode_free');
    expect(notifier.state.model, isNotNull);
    expect(notifier.state.model!.id, 'deepseek-v4-flash-free');
    expect(notifier.state.isCustomSelected, isFalse);
  });

  test('VocabularyConfigNotifier persists and reloads custom provider and model selection', () async {
    final customConfig = ApiConfig(
      id: 'custom_provider_1',
      name: 'Custom Provider',
      baseUrl: 'https://api.custom.com/v1',
      apiKeyRef: 'sec_key_custom',
      isDefault: false,
      createdAt: DateTime.now(),
    );
    await apiConfigDao.insert(customConfig, 'test-key');

    final notifier = VocabularyConfigNotifier(apiConfigDao, fakeChat);
    await notifier.initialization;

    // Switch to custom provider
    await notifier.setConfig(customConfig);
    expect(notifier.state.config?.id, 'custom_provider_1');
    expect(notifier.state.isCustomSelected, isTrue);

    // Switch to custom model
    final customModel = ModelInfo(
      id: 'custom-vocab-gpt',
      provider: 'custom',
      modelName: 'Custom Vocab GPT',
      supportsVision: false,
      supportsTools: true,
    );
    await notifier.setModel(customModel);
    expect(notifier.state.model?.id, 'custom-vocab-gpt');

    // Verify written to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(VocabularyConfigNotifier.keyVocabApiConfigId), 'custom_provider_1');
    expect(prefs.getString(VocabularyConfigNotifier.keyVocabModelId), 'custom-vocab-gpt');

    // Create a new notifier instance and verify it restores the persisted custom settings
    final restoredNotifier = VocabularyConfigNotifier(apiConfigDao, fakeChat);
    await restoredNotifier.initialization;

    expect(restoredNotifier.state.config?.id, 'custom_provider_1');
    expect(restoredNotifier.state.model?.id, 'custom-vocab-gpt');
    expect(restoredNotifier.state.isCustomSelected, isTrue);
  });

  test('VocabularyConfigNotifier addCustomModel adds and persists model', () async {
    final notifier = VocabularyConfigNotifier(apiConfigDao, fakeChat);
    await notifier.initialization;

    await notifier.addCustomModel('anthropic/claude-3-5-haiku');

    expect(notifier.state.model?.id, 'anthropic/claude-3-5-haiku');
    expect(notifier.state.model?.provider, 'anthropic');
    expect(notifier.state.model?.modelName, 'claude-3-5-haiku');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(VocabularyConfigNotifier.keyVocabModelId), 'anthropic/claude-3-5-haiku');
  });

  test('VocabularyConfigNotifier resetToDefault clears saved preferences and reloads default', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(VocabularyConfigNotifier.keyVocabApiConfigId, 'some_old_id');
    await prefs.setString(VocabularyConfigNotifier.keyVocabModelId, 'some_old_model');

    final notifier = VocabularyConfigNotifier(apiConfigDao, fakeChat);
    await notifier.initialization;

    await notifier.resetToDefault();

    expect(notifier.state.config?.id, 'opencode_free');
    expect(prefs.getString(VocabularyConfigNotifier.keyVocabApiConfigId), isNull);
    expect(prefs.getString(VocabularyConfigNotifier.keyVocabModelId), isNull);
  });

  test('VocabularyConfigNotifier resolves provider-appropriate fallback models for OpenAI and DeepSeek', () async {
    final openAiConfig = ApiConfig(
      id: 'cfg_openai',
      name: 'OpenAI Provider',
      baseUrl: 'https://api.openai.com/v1',
      apiKeyRef: 'key_openai',
      isDefault: false,
      createdAt: DateTime.now(),
    );
    await apiConfigDao.insert(openAiConfig, 'sk-test');

    final deepSeekConfig = ApiConfig(
      id: 'cfg_deepseek',
      name: 'DeepSeek Official',
      baseUrl: 'https://api.deepseek.com/v1',
      apiKeyRef: 'key_deepseek',
      isDefault: false,
      createdAt: DateTime.now(),
    );
    await apiConfigDao.insert(deepSeekConfig, 'sk-deepseek');

    final notifier = VocabularyConfigNotifier(apiConfigDao, fakeChat);
    await notifier.initialization;

    // Switch to OpenAI
    await notifier.setConfig(openAiConfig);
    expect(notifier.state.config?.id, 'cfg_openai');
    // Model must be gpt-4o-mini or gpt-4o, NEVER opencode free!
    expect(notifier.state.model?.id, anyOf('gpt-4o-mini', 'gpt-4o'));
    expect(notifier.state.model?.id.contains('free'), isFalse);

    // Switch to DeepSeek
    await notifier.setConfig(deepSeekConfig);
    expect(notifier.state.config?.id, 'cfg_deepseek');
    expect(notifier.state.model?.id, anyOf('deepseek-chat', 'deepseek-reasoner'));
    expect(notifier.state.model?.id.contains('opencode'), isFalse);
  });

  test('VocabularyConfigNotifier adopts last selected model previously used in chat for that config', () async {
    final customConfig = ApiConfig(
      id: 'cfg_recalled',
      name: 'Recall Provider',
      baseUrl: 'https://api.recall.com/v1',
      apiKeyRef: 'key_recall',
      isDefault: false,
      createdAt: DateTime.now(),
    );
    await apiConfigDao.insert(customConfig, 'sk-recall');

    // Simulate chat module having saved a selected model for this config
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_selected_model_cfg_recalled', 'custom-recalled-model');

    final notifier = VocabularyConfigNotifier(apiConfigDao, fakeChat);
    await notifier.initialization;

    await notifier.setConfig(customConfig);
    expect(notifier.state.model?.id, 'custom-recalled-model');
  });
}
