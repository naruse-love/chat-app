import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'package:chat/data/database_helper.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/image_service.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/model_info.dart';

import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/conversation_provider.dart';
import 'package:chat/providers/chat_provider.dart';
import 'package:chat/providers/model_provider.dart';

class MockChatService extends ChatService {
  dynamic chatCompletionsStreamHandler;

  @override
  Stream<Map<String, dynamic>> chatCompletionsStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    String? reasoningEffort,
    CancelToken? cancelToken,
  }) {
    if (chatCompletionsStreamHandler != null) {
      dynamic res;
      try {
        res = (chatCompletionsStreamHandler as Function)(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          tools: tools,
          reasoningEffort: reasoningEffort,
          cancelToken: cancelToken,
        );
      } catch (_) {
        res = (chatCompletionsStreamHandler as Function)(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          tools: tools,
          cancelToken: cancelToken,
        );
      }
      if (res is Stream<Map<String, dynamic>>) {
        return res;
      } else if (res is Stream) {
        return res.cast<Map<String, dynamic>>();
      }
    }
    return const Stream.empty();
  }
}

class MockSearchService extends SearchService {}

class MockImageService extends ImageService {
  Future<String> Function(String sourcePath, String messageId)? compressHandler;

  @override
  Future<String> compressAndSaveImage({
    required String sourcePath,
    required String messageId,
  }) async {
    if (compressHandler != null) {
      return compressHandler!(sourcePath, messageId);
    }
    return 'mock/permanent/path/$messageId.jpg';
  }
}

class MockFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #write) {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value != null) {
        _data[key] = value;
      } else {
        _data.remove(key);
      }
      return Future<void>.value();
    }
    if (invocation.memberName == #read) {
      final key = invocation.namedArguments[#key] as String;
      return Future<String?>.value(_data[key]);
    }
    if (invocation.memberName == #containsKey) {
      final key = invocation.namedArguments[#key] as String;
      return Future<bool>.value(_data.containsKey(key));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late MockFlutterSecureStorage mockSecureStorage;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('adversarial_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(null);
    mockSecureStorage = MockFlutterSecureStorage();
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

  group('Milestone 8: Adversarial Error Handling & Hardening Tests', () {
    test('1. Database Corruption Recovery Logic', () async {
      // Create a corrupted file at the target database path
      final dbPath = p.join(tempDir.path, 'app_database.db');
      final corruptFile = File(dbPath);
      await corruptFile.create(recursive: true);
      await corruptFile.writeAsString('THIS IS CORRUPTED AND INVALID SQLITE FILE BYTES');

      // DatabaseHelper._initDatabase should catch the open failure, delete the corrupted file, and recreate it successfully
      final db = await dbHelper.database;
      expect(db.isOpen, isTrue);

      // Verify that tables exist (meaning it recreated the tables successfully)
      final tables = await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']);
      final tableNames = tables.map((t) => t['name'] as String).toList();
      expect(tableNames, contains('api_configs'));
      expect(tableNames, contains('conversations'));
      expect(tableNames, contains('messages'));
    });

    test('2. Model Mismatched Capabilities Vision Check', () async {
      final mockChatService = MockChatService();
      final mockSearchService = MockSearchService();
      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);
      final mockImageService = MockImageService();

      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          chatServiceProvider.overrideWithValue(mockChatService),
          searchServiceProvider.overrideWithValue(mockSearchService),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
          imageServiceProvider.overrideWithValue(mockImageService),
        ],
      );
      addTearDown(container.dispose);

      // Initialize providers
      container.read(apiConfigProvider);
      container.read(conversationProvider);
      container.read(modelProvider);
      await Future.delayed(const Duration(milliseconds: 50));

      // Setup default configuration
      await container.read(apiConfigProvider.notifier).createConfig(
        ApiConfig(
          id: 'config_1',
          name: 'Endpoint 1',
          baseUrl: 'http://localhost:20128/v1',
          apiKeyRef: 'key_ref_1',
          isDefault: true,
          createdAt: DateTime.now(),
        ),
        'sk-key',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Setup a selected model that does NOT support vision
      final modelStateNotifier = container.read(modelProvider.notifier);
      final nonVisionModel = ModelInfo(
        id: 'openai/gpt-3.5-turbo',
        provider: 'openai',
        modelName: 'gpt-3.5-turbo',
        supportsVision: false,
        supportsTools: true,
      );
      modelStateNotifier.selectModel(nonVisionModel);

      // Create conversation
      final conversation = await container.read(conversationProvider.notifier).createConversation(
        title: 'Adversarial Test Chat',
        apiConfigId: 'config_1',
        modelId: 'openai/gpt-3.5-turbo',
      );

      // Load messages
      final chatNotifier = container.read(chatProvider.notifier);
      await chatNotifier.loadMessages(conversation.id);

      // Track whether the chat service stream was invoked
      var streamInvoked = false;
      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        streamInvoked = true;
        return const Stream.empty();
      };

      // Send a message with an image. Local precheck is intentionally absent:
      // the request proceeds and the API itself is responsible for any vision
      // capability error.
      await chatNotifier.sendMessage('Identify this object', imagePath: 'temp/photo.jpg');

      // The local precheck must NOT have blocked the request: the user
      // message should be in state and the chat service should have been
      // invoked (i.e. the send pipeline ran).
      final chatState = container.read(chatProvider);
      expect(chatState.error, isNot(equals('所选模型不支持图片输入。')));
      expect(chatState.messages, isNotEmpty);
      expect(chatState.messages.first.role, equals('user'));
      expect(streamInvoked, isTrue);
    });

    test('3. Network Connection Failure Error Formatting', () async {
      final mockChatService = MockChatService();
      final mockSearchService = MockSearchService();
      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);

      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          chatServiceProvider.overrideWithValue(mockChatService),
          searchServiceProvider.overrideWithValue(mockSearchService),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );
      addTearDown(container.dispose);

      container.read(apiConfigProvider);
      container.read(conversationProvider);
      container.read(modelProvider);
      await Future.delayed(const Duration(milliseconds: 50));

      await container.read(apiConfigProvider.notifier).createConfig(
        ApiConfig(
          id: 'config_1',
          name: 'Endpoint 1',
          baseUrl: 'http://localhost:20128/v1',
          apiKeyRef: 'key_ref_1',
          isDefault: true,
          createdAt: DateTime.now(),
        ),
        'sk-key',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final modelStateNotifier = container.read(modelProvider.notifier);
      final visionModel = ModelInfo(
        id: 'openai/gpt-4o',
        provider: 'openai',
        modelName: 'gpt-4o',
        supportsVision: true,
        supportsTools: true,
      );
      modelStateNotifier.selectModel(visionModel);

      final conversation = await container.read(conversationProvider.notifier).createConversation(
        title: 'Adversarial Test Chat',
        apiConfigId: 'config_1',
        modelId: 'openai/gpt-4o',
      );

      final chatNotifier = container.read(chatProvider.notifier);
      await chatNotifier.loadMessages(conversation.id);

      // Mock ChatService throwing connection timeout exception
      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.error(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionTimeout,
            error: 'Connection timeout',
          ),
        );
      };

      await chatNotifier.sendMessage('Test message');

      final chatState = container.read(chatProvider);
      expect(
        chatState.error,
        equals('连接失败。请检查您的网络连接或端点 URL。'),
      );
    });

    test('4. Network HTTP API Error (401 Unauthorized) Formatting', () async {
      final mockChatService = MockChatService();
      final mockSearchService = MockSearchService();
      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);

      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          chatServiceProvider.overrideWithValue(mockChatService),
          searchServiceProvider.overrideWithValue(mockSearchService),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );
      addTearDown(container.dispose);

      container.read(apiConfigProvider);
      container.read(conversationProvider);
      container.read(modelProvider);
      await Future.delayed(const Duration(milliseconds: 50));

      await container.read(apiConfigProvider.notifier).createConfig(
        ApiConfig(
          id: 'config_1',
          name: 'Endpoint 1',
          baseUrl: 'http://localhost:20128/v1',
          apiKeyRef: 'key_ref_1',
          isDefault: true,
          createdAt: DateTime.now(),
        ),
        'sk-key',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final modelStateNotifier = container.read(modelProvider.notifier);
      final visionModel = ModelInfo(
        id: 'openai/gpt-4o',
        provider: 'openai',
        modelName: 'gpt-4o',
        supportsVision: true,
        supportsTools: true,
      );
      modelStateNotifier.selectModel(visionModel);

      final conversation = await container.read(conversationProvider.notifier).createConversation(
        title: 'Adversarial Test Chat',
        apiConfigId: 'config_1',
        modelId: 'openai/gpt-4o',
      );

      final chatNotifier = container.read(chatProvider.notifier);
      await chatNotifier.loadMessages(conversation.id);

      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.error(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 401,
              statusMessage: 'Unauthorized',
            ),
          ),
        );
      };

      await chatNotifier.sendMessage('Test message');

      final chatState = container.read(chatProvider);
      expect(
        chatState.error,
        equals('API 身份验证失败。请检查您的 API 密钥。'),
      );
    });

    test('5. Image Compression Failure / ImageServiceException handling', () async {
      final mockChatService = MockChatService();
      final mockSearchService = MockSearchService();
      final mockImageService = MockImageService();
      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);

      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          chatServiceProvider.overrideWithValue(mockChatService),
          searchServiceProvider.overrideWithValue(mockSearchService),
          imageServiceProvider.overrideWithValue(mockImageService),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );
      addTearDown(container.dispose);

      container.read(apiConfigProvider);
      container.read(conversationProvider);
      container.read(modelProvider);
      await Future.delayed(const Duration(milliseconds: 50));

      await container.read(apiConfigProvider.notifier).createConfig(
        ApiConfig(
          id: 'config_1',
          name: 'Endpoint 1',
          baseUrl: 'http://localhost:20128/v1',
          apiKeyRef: 'key_ref_1',
          isDefault: true,
          createdAt: DateTime.now(),
        ),
        'sk-key',
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final modelStateNotifier = container.read(modelProvider.notifier);
      final visionModel = ModelInfo(
        id: 'openai/gpt-4o',
        provider: 'openai',
        modelName: 'gpt-4o',
        supportsVision: true,
        supportsTools: true,
      );
      modelStateNotifier.selectModel(visionModel);

      final conversation = await container.read(conversationProvider.notifier).createConversation(
        title: 'Adversarial Test Chat',
        apiConfigId: 'config_1',
        modelId: 'openai/gpt-4o',
      );

      final chatNotifier = container.read(chatProvider.notifier);
      await chatNotifier.loadMessages(conversation.id);

      // Mock ImageService throwing a File Not Found exception
      mockImageService.compressHandler = (srcPath, msgId) => throw const ImageFileNotFoundException('File not found');

      await chatNotifier.sendMessage('Test image', imagePath: 'missing_image.png');

      final chatState = container.read(chatProvider);
      expect(
        chatState.error,
        contains('图片处理失败: File not found'),
      );
      expect(chatState.messages, isEmpty);
    });
  });
}
