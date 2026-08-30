import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:chat/data/database_helper.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/model_info.dart';

import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/conversation_provider.dart';
import 'package:chat/providers/chat_provider.dart';
import 'package:chat/providers/model_provider.dart';
import 'package:chat/providers/settings_provider.dart';
import 'package:chat/providers/theme_provider.dart';

class MockChatService extends ChatService {
  dynamic chatCompletionsStreamHandler;

  Future<List<ModelInfo>> Function(String baseUrl, String apiKey)? listModelsHandler;

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

  @override
  Future<List<ModelInfo>> getModels({
    required String baseUrl,
    required String apiKey,
    CancelToken? cancelToken,
  }) async {
    if (listModelsHandler != null) {
      return listModelsHandler!(baseUrl, apiKey);
    }
    return [];
  }
}

class MockSearchService extends SearchService {
  Future<List<SearchResult>> Function(String query)? searchHandler;

  @override
  Future<List<SearchResult>> search({
    required String query,
    String? searxngUrl,
    String searchBackend = 'searxng',
    String? googleApiKey,
    String? googleBaseUrl,
    String? googleSearchModel,
    String? bingCookie,
  }) async {
    if (searchHandler != null) {
      return searchHandler!(query);
    }
    return [];
  }
}

// Mock implementation of FlutterSecureStorage using noSuchMethod
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
    if (invocation.memberName == #delete) {
      final key = invocation.namedArguments[#key] as String;
      _data.remove(key);
      return Future<void>.value();
    }
    if (invocation.memberName == #deleteAll) {
      _data.clear();
      return Future<void>.value();
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
    tempDir = Directory.systemTemp.createTempSync('e2e_integration_test_');
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

  group('End-to-End & Provider Integration Flow Tests', () {
    test('Verify complete app state, conversation management, message streaming and DB persistence', () async {
      final mockChatService = MockChatService();
      final mockSearchService = MockSearchService();
      final mockSecureStorageService = SecureStorageService(storage: mockSecureStorage);

      // Configure mock behavior for chat model list
      mockChatService.listModelsHandler = (baseUrl, apiKey) async {
        return [
          ModelInfo(
            id: 'openai/gpt-4o',
            provider: 'openai',
            modelName: 'gpt-4o',
            supportsVision: true,
            supportsTools: true,
          ),
          ModelInfo(
            id: 'deepseek/deepseek-chat',
            provider: 'deepseek',
            modelName: 'deepseek-chat',
            supportsVision: false,
            supportsTools: true,
          ),
        ];
      };

      // Create ProviderContainer with overridden services
      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          chatServiceProvider.overrideWithValue(mockChatService),
          searchServiceProvider.overrideWithValue(mockSearchService),
          secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
        ],
      );

      addTearDown(container.dispose);

      // Trigger lazy loading of providers
      container.read(themeProvider);
      container.read(settingsProvider);
      container.read(apiConfigProvider);
      container.read(conversationProvider);

      // Yield control to let async constructors finish initialization (e.g. loadConfigs, _loadSettings, etc.)
      await Future.delayed(const Duration(milliseconds: 100));
      while (container.read(apiConfigProvider).isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // Verify initial theme state
      final themeMode = container.read(themeProvider);
      expect(themeMode, equals(ThemeMode.system)); // Default state from notifier

      // Switch theme mode
      await container.read(themeProvider.notifier).setThemeMode(ThemeMode.light);
      expect(container.read(themeProvider), equals(ThemeMode.light));

      // Configure setting SearXNG URL
      final settingsNotifier = container.read(settingsProvider.notifier);
      await settingsNotifier.updateSearxngUrl('https://searxng.local/search');
      expect(container.read(settingsProvider).searxngUrl, equals('https://searxng.local/search'));

      // 1. Add API config and verify it is updated in SQLite & state
      final apiNotifier = container.read(apiConfigProvider.notifier);
      await apiNotifier.createConfig(
        ApiConfig(
          id: 'config_1',
          name: 'My 9Router Endpoint',
          baseUrl: 'http://localhost:20128/v1',
          apiKeyRef: 'key_ref_1',
          isDefault: true,
          createdAt: DateTime.now(),
        ),
        'sk-9router-test-key-123456789',
      );

      final apiState = container.read(apiConfigProvider);
      expect(apiState.configs.length, equals(2));
      expect(apiState.activeConfig, isNotNull);
      expect(apiState.activeConfig!.name, equals('My 9Router Endpoint'));
      expect(apiState.activeConfig!.isDefault, equals(true));

      // 2. Fetch and list models
      final modelNotifier = container.read(modelProvider.notifier);
      await modelNotifier.fetchModels();
      final modelState = container.read(modelProvider);
      expect(modelState.models.length, equals(2));
      expect(modelState.selectedModel, isNotNull);
      expect(modelState.selectedModel!.id, equals('openai/gpt-4o')); // Default first one

      // Switch model
      modelNotifier.selectModel(modelState.models[1]);
      expect(container.read(modelProvider).selectedModel!.id, equals('deepseek/deepseek-chat'));

      // 3. Create a conversation
      final convNotifier = container.read(conversationProvider.notifier);
      final activeConfigId = apiState.activeConfig!.id;
      final activeModelId = container.read(modelProvider).selectedModel!.id;

      final conversation = await convNotifier.createConversation(
        title: 'New Integration Test Chat',
        apiConfigId: activeConfigId,
        modelId: activeModelId,
        systemPrompt: 'You are a test assistant.',
      );

      expect(conversation, isNotNull);
      expect(conversation.title, equals('New Integration Test Chat'));
      expect(container.read(conversationProvider).activeConversation?.id, equals(conversation.id));

      // 4. Load messages (should be empty initially)
      final chatNotifier = container.read(chatProvider.notifier);
      await chatNotifier.loadMessages(conversation.id);
      expect(container.read(chatProvider).messages, isEmpty);

      // 5. Send message and stream reply (standard flow)
      mockChatService.chatCompletionsStreamHandler = ({
        required String baseUrl,
        required String apiKey,
        required String model,
        required List<ChatMessage> messages,
        List<Map<String, dynamic>>? tools,
        CancelToken? cancelToken,
      }) {
        return Stream.fromIterable([
          {
            'choices': [
              {
                'delta': {
                  'reasoning_content': 'Thinking steps...',
                  'content': 'Hello',
                }
              }
            ]
          },
          {
            'choices': [
              {
                'delta': {
                  'content': ' user! How can I help today?',
                }
              }
            ]
          }
        ]);
      };

      final sendFuture = chatNotifier.sendMessage('Hello Assistant');
      
      // Wait momentarily for the stream to resolve
      await sendFuture;

      final updatedChatState = container.read(chatProvider);
      expect(updatedChatState.error, isNull);
      expect(updatedChatState.messages.length, equals(2)); // User message + Assistant response
      expect(updatedChatState.messages[0].role, equals('user'));
      expect(updatedChatState.messages[0].content, equals('Hello Assistant'));
      
      expect(updatedChatState.messages[1].role, equals('assistant'));
      expect(updatedChatState.messages[1].content, equals('Hello user! How can I help today?'));
      expect(updatedChatState.messages[1].reasoningContent, equals('Thinking steps...'));

      // Verify that messages are written to database
      final dbMessages = await container.read(messageDaoProvider).getMessagesForConversation(conversation.id);
      expect(dbMessages.length, equals(2));
      expect(dbMessages[0].content, equals('Hello Assistant'));
      expect(dbMessages[1].content, equals('Hello user! How can I help today?'));

      // 6. Pin/Archive conversation tests
      final initialConvs = container.read(conversationProvider).conversations;
      expect(initialConvs.length, equals(1));
      expect(initialConvs[0].isPinned, isFalse);

      // Toggle pin
      await convNotifier.togglePin(conversation.id);
      expect(container.read(conversationProvider).conversations[0].isPinned, isTrue);

      // Toggle archive
      await convNotifier.toggleArchive(conversation.id);
      expect(container.read(conversationProvider).conversations[0].isArchived, isTrue);

      // 7. Delete conversation cascade deletes messages
      await convNotifier.deleteConversation(conversation.id);
      expect(container.read(conversationProvider).conversations, isEmpty);
      expect(container.read(conversationProvider).activeConversation, isNull);

      final dbMessagesAfterDelete = await container.read(messageDaoProvider).getMessagesForConversation(conversation.id);
      expect(dbMessagesAfterDelete, isEmpty);
    });
  });
}
