import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'package:chat/data/database_helper.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/model_provider.dart';
import 'e2e_integration_test.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late MockFlutterSecureStorage mockSecureStorage;
  late MockChatService mockChatService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('opencode_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(null);
    mockSecureStorage = MockFlutterSecureStorage();
    mockChatService = MockChatService();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    try {
      final db = await dbHelper.database;
      await db.close();
    } catch (_) {}
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('OpenCode Free Requirement Tests', () {
    test('ApiConfigNotifier pre-populates OpenCode Free default config on empty database', () async {
      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);

      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );
      addTearDown(container.dispose);

      container.read(apiConfigProvider);
      await Future.delayed(const Duration(milliseconds: 100));

      final state = container.read(apiConfigProvider);
      expect(state.configs, hasLength(1));
      final config = state.configs.first;
      expect(config.name, equals('OpenCode Free'));
      expect(config.baseUrl, equals('https://opencode.ai/zen/v1'));
      expect(config.isDefault, isTrue);
      expect(state.activeConfig?.id, equals('opencode_free'));

      final storedKey = await mockSecureStorage.read(key: 'opencode_free_api_key_ref');
      expect(storedKey, equals(''));
    });

    test('ModelInfo.fromApiResponse defaults unknown provider to opencode', () {
      final json = {'id': 'deepseek-v4-flash-free', 'owned_by': 'opencode'};
      final modelInfo = ModelInfo.fromApiResponse(json);
      expect(modelInfo.provider, equals('opencode'));
      expect(modelInfo.id, equals('deepseek-v4-flash-free'));
      expect(modelInfo.supportsTools, isTrue);
    });

    test('ModelNotifier falls back to defaultOpenCodeFallbackModels on network failure', () async {
      mockChatService.listModelsHandler = (baseUrl, apiKey) async {
        throw DioException(
          requestOptions: RequestOptions(path: baseUrl),
          type: DioExceptionType.connectionError,
          error: 'Network unreachable',
        );
      };

      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);
      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          chatServiceProvider.overrideWithValue(mockChatService),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );
      addTearDown(container.dispose);

      container.read(apiConfigProvider);
      await Future.delayed(const Duration(milliseconds: 100));

      final modelNotifier = container.read(modelProvider.notifier);
      await modelNotifier.fetchModels();

      final modelState = container.read(modelProvider);
      expect(modelState.models, hasLength(5));
      expect(modelState.models.map((m) => m.id), containsAll([
        'deepseek-v4-flash-free',
        'mimo-v2.5-free',
        'hy3-free',
        'nemotron-3-ultra-free',
        'north-mini-code-free',
      ]));
      expect(modelState.selectedModel, isNotNull);
      expect(modelState.selectedModel!.id, equals('deepseek-v4-flash-free'));
    });

    test('ModelNotifier filters models and defaults to deepseek-v4-flash-free when config is opencode_free', () async {
      mockChatService.listModelsHandler = (baseUrl, apiKey) async {
        return [
          ModelInfo(id: 'deepseek-v4-flash-free', provider: 'opencode', modelName: 'deepseek-v4-flash-free', supportsVision: false, supportsTools: true),
          ModelInfo(id: 'gpt-4o', provider: 'openai', modelName: 'gpt-4o', supportsVision: true, supportsTools: true),
          ModelInfo(id: 'mimo-v2.5-free', provider: 'opencode', modelName: 'mimo-v2.5-free', supportsVision: false, supportsTools: true),
        ];
      };

      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);
      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          chatServiceProvider.overrideWithValue(mockChatService),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );
      addTearDown(container.dispose);

      container.read(apiConfigProvider);
      await Future.delayed(const Duration(milliseconds: 100));

      final modelNotifier = container.read(modelProvider.notifier);
      await modelNotifier.fetchModels();

      final modelState = container.read(modelProvider);
      // gpt-4o should be filtered out because it is not free (doesn't contain 'free')
      expect(modelState.models, hasLength(2));
      expect(modelState.models.map((m) => m.id), containsAll([
        'deepseek-v4-flash-free',
        'mimo-v2.5-free',
      ]));
      expect(modelState.selectedModel, isNotNull);
      expect(modelState.selectedModel!.id, equals('deepseek-v4-flash-free'));
    });
  });
}
