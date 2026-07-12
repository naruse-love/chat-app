import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/conversation_dao.dart';
import 'package:chat/data/message_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/models/conversation.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool_call.dart';
import 'package:chat/models/api_config.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Mock implementation of Database using noSuchMethod to delegate unimplemented members
class MockDatabase implements Database, Transaction {
  final List<String> executedQueries = [];

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    return await action(this as Transaction);
  }
  final List<Map<String, dynamic>> insertedRecords = [];
  final List<Map<String, dynamic>> updatedRecords = [];
  final List<Map<String, dynamic>> deletedRecords = [];

  final Map<String, List<Map<String, dynamic>>> tables = {
    'api_configs': [],
    'conversations': [],
    'messages': [],
    'system_prompts': [],
  };

  @override
  String get path => 'mock.db';

  @override
  bool get isOpen => true;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    executedQueries.add(sql);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final record = Map<String, dynamic>.from(values);
    tables[table]?.add(record);
    insertedRecords.add({'table': table, 'values': record});
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    var results = tables[table] ?? [];

    if (where != null && whereArgs != null) {
      if (where.contains('id = ?')) {
        final id = whereArgs.first;
        results = results.where((r) => r['id'] == id).toList();
      } else if (where.contains('conversationId = ?')) {
        final convId = whereArgs.first;
        results = results.where((r) => r['conversationId'] == convId).toList();
      } else if (where.contains('isDefault = ?')) {
        final isDefaultVal = whereArgs.first;
        results = results.where((r) => r['isDefault'] == isDefaultVal).toList();
      }
    }

    if (table == 'conversations' && orderBy == 'isPinned DESC, updatedAt DESC') {
      final sorted = List<Map<String, dynamic>>.from(results);
      sorted.sort((a, b) {
        final pinA = a['isPinned'] as int? ?? 0;
        final pinB = b['isPinned'] as int? ?? 0;
        if (pinA != pinB) {
          return pinB.compareTo(pinA);
        }
        final updateA = a['updatedAt'] as String? ?? '';
        final updateB = b['updatedAt'] as String? ?? '';
        return updateB.compareTo(updateA);
      });
      results = sorted;
    }

    if (table == 'messages' && orderBy == 'timestamp ASC') {
      final sorted = List<Map<String, dynamic>>.from(results);
      sorted.sort((a, b) {
        final timeA = a['timestamp'] as String? ?? '';
        final timeB = b['timestamp'] as String? ?? '';
        return timeA.compareTo(timeB);
      });
      results = sorted;
    }

    return results;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final list = tables[table] ?? [];
    int count = 0;

    for (int i = 0; i < list.length; i++) {
      bool matches = true;
      if (where != null) {
        if (where.contains('id = ?') && whereArgs != null && whereArgs.isNotEmpty) {
          matches = list[i]['id'] == whereArgs.first;
        } else if (where.contains('id != ?') && whereArgs != null && whereArgs.isNotEmpty) {
          matches = list[i]['id'] != whereArgs.first;
        } else {
          matches = false;
        }
      }
      if (matches) {
        list[i] = {...list[i], ...values};
        updatedRecords.add({'table': table, 'values': values, 'id': list[i]['id']});
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final list = tables[table] ?? [];
    int count = 0;

    if (where != null && whereArgs != null) {
      if (where.contains('id = ?')) {
        final id = whereArgs.first;
        final beforeLength = list.length;
        list.removeWhere((r) => r['id'] == id);
        count = beforeLength - list.length;
        deletedRecords.add({'table': table, 'where': where, 'whereArgs': whereArgs});
      } else if (where.contains('conversationId = ?')) {
        final convId = whereArgs.first;
        final beforeLength = list.length;
        list.removeWhere((r) => r['conversationId'] == convId);
        count = beforeLength - list.length;
        deletedRecords.add({'table': table, 'where': where, 'whereArgs': whereArgs});
      }
    } else {
      count = list.length;
      list.clear();
      deletedRecords.add({'table': table, 'where': null, 'whereArgs': null});
    }
    return count;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  late DatabaseHelper dbHelper;
  late MockDatabase mockDb;
  late MockFlutterSecureStorage mockSecureStorage;
  late SecureStorageService secureStorageService;

  setUp(() {
    dbHelper = DatabaseHelper.instance;
    mockDb = MockDatabase();
    dbHelper.setMockDatabase(mockDb);

    mockSecureStorage = MockFlutterSecureStorage();
    secureStorageService = SecureStorageService(storage: mockSecureStorage);
  });

  group('DatabaseHelper Schema & Migrations', () {
    test('onCreate should create tables with correct schemas', () async {
      await dbHelper.testOnCreate(mockDb, 2);

      // Verify executed queries contain table definitions
      final queries = mockDb.executedQueries.join('\n').toLowerCase();
      expect(queries, contains('create table api_configs'));
      expect(queries, contains('create table conversations'));
      expect(queries, contains('create table messages'));
      expect(queries, contains('create table system_prompts'));
    });

    test('onUpgrade should migrate conversations schema from version 1 to 2', () async {
      await dbHelper.testOnUpgrade(mockDb, 1, 2);

      final queries = mockDb.executedQueries.join('\n').toLowerCase();
      expect(queries, contains('alter table conversations add column ispinned'));
      expect(queries, contains('alter table conversations add column isarchived'));
    });
  });

  group('ConversationDao CRUD Operations', () {
    late ConversationDao conversationDao;

    setUp(() {
      conversationDao = ConversationDao(dbHelper);
    });

    test('should insert and retrieve a conversation by ID', () async {
      final now = DateTime.now();
      final conversation = Conversation(
        id: 'conv-1',
        title: 'Test Conversation',
        apiConfigId: 'api-1',
        modelId: 'gpt-4o',
        systemPrompt: 'You are a helpful assistant.',
        isPinned: true,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );

      await conversationDao.insert(conversation);

      final retrieved = await conversationDao.getById('conv-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, conversation.id);
      expect(retrieved.title, conversation.title);
      expect(retrieved.apiConfigId, conversation.apiConfigId);
      expect(retrieved.modelId, conversation.modelId);
      expect(retrieved.systemPrompt, conversation.systemPrompt);
      expect(retrieved.isPinned, isTrue);
      expect(retrieved.isArchived, isFalse);
      expect(retrieved.createdAt.toIso8601String(), conversation.createdAt.toIso8601String());
      expect(retrieved.updatedAt.toIso8601String(), conversation.updatedAt.toIso8601String());
    });

    test('should update an existing conversation', () async {
      final now = DateTime.now();
      final conversation = Conversation(
        id: 'conv-2',
        title: 'Old Title',
        apiConfigId: 'api-1',
        modelId: 'gpt-4o',
        isPinned: false,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );

      await conversationDao.insert(conversation);

      final updated = conversation.copyWith(
        title: 'New Title',
        isPinned: true,
        updatedAt: now.add(const Duration(minutes: 5)),
      );

      await conversationDao.update(updated);

      final retrieved = await conversationDao.getById('conv-2');
      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'New Title');
      expect(retrieved.isPinned, isTrue);
      expect(retrieved.updatedAt.toIso8601String(), updated.updatedAt.toIso8601String());
    });

    test('should delete a conversation', () async {
      final now = DateTime.now();
      final conversation = Conversation(
        id: 'conv-3',
        title: 'To Delete',
        apiConfigId: 'api-1',
        modelId: 'gpt-4o',
        isPinned: false,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );

      await conversationDao.insert(conversation);
      expect(await conversationDao.getById('conv-3'), isNotNull);

      await conversationDao.delete('conv-3');
      expect(await conversationDao.getById('conv-3'), isNull);
    });

    test('should return all conversations ordered by isPinned and updatedAt desc', () async {
      final baseTime = DateTime.parse('2026-07-11T12:00:00Z');

      // Conv 1: Pinned, updated at 12:00
      final c1 = Conversation(
        id: 'conv-p1',
        title: 'Pinned 1',
        apiConfigId: 'api-1',
        modelId: 'gpt-4o',
        isPinned: true,
        isArchived: false,
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      // Conv 2: Unpinned, updated at 13:00
      final c2 = Conversation(
        id: 'conv-u1',
        title: 'Unpinned 1',
        apiConfigId: 'api-1',
        modelId: 'gpt-4o',
        isPinned: false,
        isArchived: false,
        createdAt: baseTime,
        updatedAt: baseTime.add(const Duration(hours: 1)),
      );

      // Conv 3: Pinned, updated at 14:00 (should be first)
      final c3 = Conversation(
        id: 'conv-p2',
        title: 'Pinned 2',
        apiConfigId: 'api-1',
        modelId: 'gpt-4o',
        isPinned: true,
        isArchived: false,
        createdAt: baseTime,
        updatedAt: baseTime.add(const Duration(hours: 2)),
      );

      await conversationDao.insert(c1);
      await conversationDao.insert(c2);
      await conversationDao.insert(c3);

      final list = await conversationDao.getAll();
      expect(list.length, 3);
      expect(list[0].id, 'conv-p2'); // Pinned, newest update
      expect(list[1].id, 'conv-p1'); // Pinned, older update
      expect(list[2].id, 'conv-u1'); // Unpinned
    });
  });

  group('MessageDao CRUD Operations', () {
    late MessageDao messageDao;

    setUp(() {
      messageDao = MessageDao(dbHelper);
    });

    test('should insert and retrieve a message, serializing toolCalls', () async {
      final now = DateTime.now();
      final toolCall = ToolCall(
        id: 'tc-1',
        type: 'function',
        functionName: 'get_weather',
        arguments: '{"location": "Tokyo"}',
      );

      final message = ChatMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        role: 'assistant',
        content: 'Checking weather...',
        reasoningContent: 'User wants weather details.',
        imagePath: '/path/to/image.jpg',
        toolCalls: [toolCall],
        toolCallId: 'tc-1',
        timestamp: now,
      );

      await messageDao.insert(message);

      // Verify that toolCalls are stored as JSON string in the database
      final rawRecords = mockDb.tables['messages']!;
      expect(rawRecords.length, 1);
      final rawRecord = rawRecords.first;
      expect(rawRecord['toolCalls'], isA<String>());
      final decodedToolCalls = jsonDecode(rawRecord['toolCalls'] as String) as List;
      expect(decodedToolCalls.first['functionName'], 'get_weather');

      final retrieved = await messageDao.getById('msg-1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, message.id);
      expect(retrieved.content, message.content);
      expect(retrieved.reasoningContent, message.reasoningContent);
      expect(retrieved.imagePath, message.imagePath);
      expect(retrieved.toolCallId, message.toolCallId);
      expect(retrieved.timestamp.toIso8601String(), message.timestamp.toIso8601String());
      expect(retrieved.toolCalls, isNotNull);
      expect(retrieved.toolCalls!.length, 1);
      expect(retrieved.toolCalls!.first.functionName, 'get_weather');
      expect(retrieved.toolCalls!.first.arguments, '{"location": "Tokyo"}');
    });

    test('should get all messages for a conversation ordered by timestamp asc', () async {
      final baseTime = DateTime.parse('2026-07-11T12:00:00Z');
      final m1 = ChatMessage(
        id: 'msg-c1-t2',
        conversationId: 'conv-c1',
        role: 'user',
        content: 'Second message',
        timestamp: baseTime.add(const Duration(seconds: 10)),
      );
      final m2 = ChatMessage(
        id: 'msg-c1-t1',
        conversationId: 'conv-c1',
        role: 'user',
        content: 'First message',
        timestamp: baseTime,
      );
      final m3 = ChatMessage(
        id: 'msg-c2-t1',
        conversationId: 'conv-c2',
        role: 'user',
        content: 'Other conversation message',
        timestamp: baseTime,
      );

      await messageDao.insert(m1);
      await messageDao.insert(m2);
      await messageDao.insert(m3);

      final list = await messageDao.getMessagesForConversation('conv-c1');
      expect(list.length, 2);
      expect(list[0].id, 'msg-c1-t1'); // First message in time
      expect(list[1].id, 'msg-c1-t2'); // Second message in time
    });

    test('should clear all messages for a conversation', () async {
      final now = DateTime.now();
      final m1 = ChatMessage(id: 'm1', conversationId: 'c1', role: 'user', content: 'A', timestamp: now);
      final m2 = ChatMessage(id: 'm2', conversationId: 'c1', role: 'user', content: 'B', timestamp: now);
      final m3 = ChatMessage(id: 'm3', conversationId: 'c2', role: 'user', content: 'C', timestamp: now);

      await messageDao.insert(m1);
      await messageDao.insert(m2);
      await messageDao.insert(m3);

      expect((await messageDao.getMessagesForConversation('c1')).length, 2);
      expect((await messageDao.getMessagesForConversation('c2')).length, 1);

      await messageDao.clearConversation('c1');
      expect((await messageDao.getMessagesForConversation('c1')).length, 0);
      expect((await messageDao.getMessagesForConversation('c2')).length, 1);
    });
  });

  group('ApiConfigDao & Security Operations', () {
    late ApiConfigDao apiConfigDao;

    setUp(() {
      apiConfigDao = ApiConfigDao(dbHelper, secureStorageService);
    });

    test('should store API config in SQLite and plaintext API key in secure storage', () async {
      final now = DateTime.now();
      final config = ApiConfig(
        id: 'api-sec-1',
        name: 'Secure OpenAi',
        baseUrl: 'https://api.openai.com/v1',
        apiKeyRef: 'secure-key-openai-ref',
        isDefault: true,
        createdAt: now,
      );

      const plaintextApiKey = 'sk-proj-1234567890abcdefghijklmnopqrstuvwxyz';

      // Insert using DAO
      await apiConfigDao.insert(config, plaintextApiKey);

      // 1. Verify SQLite record DOES NOT contain the plaintext API key
      final rawRecords = mockDb.tables['api_configs']!;
      expect(rawRecords.length, 1);
      final rawRecord = rawRecords.first;
      expect(rawRecord.values.join(' '), isNot(contains(plaintextApiKey)));
      expect(rawRecord['apiKeyRef'], 'secure-key-openai-ref');

      // 2. Verify that the secure storage DOES contain the plaintext API key under the keyRef
      final secureVal = await mockSecureStorage.read(key: 'secure-key-openai-ref');
      expect(secureVal, plaintextApiKey);

      // 3. Retrieve through DAO and verify getApiKey yields plaintext key
      final retrievedConfig = await apiConfigDao.getById('api-sec-1');
      expect(retrievedConfig, isNotNull);
      expect(retrievedConfig!.apiKeyRef, 'secure-key-openai-ref');

      final loadedApiKey = await apiConfigDao.getApiKey(retrievedConfig.apiKeyRef);
      expect(loadedApiKey, plaintextApiKey);
    });

    test('should clean up secure storage when api config is deleted', () async {
      final now = DateTime.now();
      final config = ApiConfig(
        id: 'api-sec-2',
        name: 'Temporary API',
        baseUrl: 'https://api.temp.org',
        apiKeyRef: 'temp-key-ref',
        isDefault: false,
        createdAt: now,
      );

      const plaintextApiKey = 'temp-key-value-123';

      await apiConfigDao.insert(config, plaintextApiKey);
      expect(await mockSecureStorage.read(key: 'temp-key-ref'), plaintextApiKey);
      expect(await apiConfigDao.getById('api-sec-2'), isNotNull);

      await apiConfigDao.delete('api-sec-2');

      // Verify metadata is deleted from SQLite
      expect(await apiConfigDao.getById('api-sec-2'), isNull);

      // Verify API key is deleted from secure storage
      expect(await mockSecureStorage.read(key: 'temp-key-ref'), isNull);
    });

    test('should maintain default config integrity by setting other configs isDefault to 0', () async {
      final now = DateTime.now();
      final config1 = ApiConfig(
        id: 'api-1',
        name: 'Config 1',
        baseUrl: 'https://api1.com',
        apiKeyRef: 'ref-1',
        isDefault: true,
        createdAt: now,
      );
      final config2 = ApiConfig(
        id: 'api-2',
        name: 'Config 2',
        baseUrl: 'https://api2.com',
        apiKeyRef: 'ref-2',
        isDefault: false,
        createdAt: now,
      );

      // Insert config1 as default
      await apiConfigDao.insert(config1, 'key-1');
      expect((await apiConfigDao.getById('api-1'))!.isDefault, isTrue);

      // Insert config2 as NOT default, should not change config1
      await apiConfigDao.insert(config2, 'key-2');
      expect((await apiConfigDao.getById('api-1'))!.isDefault, isTrue);
      expect((await apiConfigDao.getById('api-2'))!.isDefault, isFalse);

      // Create config3 as default, insert it
      final config3 = ApiConfig(
        id: 'api-3',
        name: 'Config 3',
        baseUrl: 'https://api3.com',
        apiKeyRef: 'ref-3',
        isDefault: true,
        createdAt: now,
      );
      await apiConfigDao.insert(config3, 'key-3');

      // Now config3 should be default, config1 and config2 should NOT be default
      expect((await apiConfigDao.getById('api-3'))!.isDefault, isTrue);
      expect((await apiConfigDao.getById('api-1'))!.isDefault, isFalse);
      expect((await apiConfigDao.getById('api-2'))!.isDefault, isFalse);

      // Update config2 to be default
      final updatedConfig2 = config2.copyWith(isDefault: true);
      await apiConfigDao.update(updatedConfig2);

      // Now config2 should be default, config1 and config3 should NOT be default
      expect((await apiConfigDao.getById('api-2'))!.isDefault, isTrue);
      expect((await apiConfigDao.getById('api-1'))!.isDefault, isFalse);
      expect((await apiConfigDao.getById('api-3'))!.isDefault, isFalse);
    });

    test('should prevent secure storage leaks by deleting old key ref when apiKeyRef changes and new apiKey is provided', () async {
      final now = DateTime.now();
      final config = ApiConfig(
        id: 'api-leak-1',
        name: 'Leak test 1',
        baseUrl: 'https://api.com',
        apiKeyRef: 'old-ref',
        isDefault: false,
        createdAt: now,
      );

      await apiConfigDao.insert(config, 'old-key');
      expect(await mockSecureStorage.read(key: 'old-ref'), 'old-key');

      // Update with new apiKeyRef and new apiKey
      final updatedConfig = config.copyWith(apiKeyRef: 'new-ref');
      await apiConfigDao.update(updatedConfig, apiKey: 'new-key');

      // Verify new key is stored under new reference
      expect(await mockSecureStorage.read(key: 'new-ref'), 'new-key');
      // Verify old key reference is deleted (prevent leak)
      expect(await mockSecureStorage.read(key: 'old-ref'), isNull);
    });

    test('should migrate secure storage key when apiKeyRef changes and no new apiKey is provided', () async {
      final now = DateTime.now();
      final config = ApiConfig(
        id: 'api-migration-1',
        name: 'Migration test 1',
        baseUrl: 'https://api.com',
        apiKeyRef: 'old-ref',
        isDefault: false,
        createdAt: now,
      );

      await apiConfigDao.insert(config, 'secret-value');
      expect(await mockSecureStorage.read(key: 'old-ref'), 'secret-value');

      // Update with new apiKeyRef, but without providing new apiKey (apiKey = null)
      final updatedConfig = config.copyWith(apiKeyRef: 'new-ref');
      await apiConfigDao.update(updatedConfig);

      // Verify key is migrated to the new reference
      expect(await mockSecureStorage.read(key: 'new-ref'), 'secret-value');
      // Verify old reference is deleted
      expect(await mockSecureStorage.read(key: 'old-ref'), isNull);
    });
  });
}
