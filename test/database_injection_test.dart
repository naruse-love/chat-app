import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/conversation_dao.dart';
import 'package:chat/data/message_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/models/conversation.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/api_config.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// InjectionMockDatabase acts as a secure test oracle to verify that the DAOs
// utilize parameterized queries and do not interpolate user input into SQL structures.
class InjectionMockDatabase implements Database, Transaction {
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

  // Malicious SQL injection payloads we want to ensure do NOT end up inside query structures.
  static const List<String> maliciousPayloads = [
    "'; DROP TABLE conversations; --",
    "'; DROP TABLE messages; --",
    "'; DROP TABLE api_configs; --",
    "'; DELETE FROM conversations; --",
    "'; DELETE FROM messages; --",
    "' OR '1'='1",
    "' OR 1=1 --",
    "admin' --",
    "'; UPDATE api_configs SET name='injected' WHERE 'a'='a",
    "'; UPDATE messages SET content='hacked'; --",
    "UNION SELECT null, null, null",
  ];

  @override
  String get path => 'mock_injection.db';

  @override
  bool get isOpen => true;

  // Helper method to verify the query structure is safe
  void _assertSafeQuery(String? where, List<Object?>? whereArgs) {
    if (where == null) return;

    // Check that none of the malicious payloads are interpolated directly into the SQL 'where' clause
    for (final payload in maliciousPayloads) {
      if (where.contains(payload)) {
        fail('VULNERABILITY DETECTED: Malicious payload was interpolated directly into SQL query: "$where"');
      }
    }

    // Verify placeholder matches whereArgs length
    final placeholderCount = '?'.allMatches(where).length;
    final argsLength = whereArgs?.length ?? 0;
    if (placeholderCount != argsLength) {
      fail('VULNERABILITY OR BUG DETECTED: Placeholder count ($placeholderCount) does not match arguments length ($argsLength) in query: "$where"');
    }
  }

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
    // Check that values are not interpolated. In db.insert, the query is parameterized,
    // and values are passed separately. We store them safely as data.
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
    _assertSafeQuery(where, whereArgs);

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
    _assertSafeQuery(where, whereArgs);

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
    _assertSafeQuery(where, whereArgs);

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
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late DatabaseHelper dbHelper;
  late InjectionMockDatabase mockDb;
  late MockFlutterSecureStorage mockSecureStorage;
  late SecureStorageService secureStorageService;

  setUp(() {
    dbHelper = DatabaseHelper.instance;
    mockDb = InjectionMockDatabase();
    dbHelper.setMockDatabase(mockDb);

    mockSecureStorage = MockFlutterSecureStorage();
    secureStorageService = SecureStorageService(storage: mockSecureStorage);
  });

  group('Database SQL Injection Resiliency Tests', () {
    group('Conversation Title Injection', () {
      late ConversationDao conversationDao;

      setUp(() {
        conversationDao = ConversationDao(dbHelper);
      });

      test('should safely handle malicious SQL injection payloads in Conversation Title', () async {
        final now = DateTime.now();

        // Test insertion of conversations with each SQL injection payload
        for (int i = 0; i < InjectionMockDatabase.maliciousPayloads.length; i++) {
          final payload = InjectionMockDatabase.maliciousPayloads[i];
          final convId = 'conv-injection-$i';

          final conversation = Conversation(
            id: convId,
            title: payload,
            apiConfigId: 'api-config-id',
            modelId: 'gpt-4o',
            systemPrompt: 'Default Prompt',
            isPinned: false,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
          );

          // 1. Insert conversation.
          // This must not fail or execute the payload as SQL (e.g. dropping tables or deleting other records).
          await conversationDao.insert(conversation);

          // 2. Retrieve conversation and verify that it matches exactly.
          final retrieved = await conversationDao.getById(convId);
          expect(retrieved, isNotNull);
          expect(retrieved!.title, payload);
          expect(retrieved.id, convId);
        }

        // Verify that the table was NOT cleared or dropped by malicious payloads.
        // There should be exactly as many records as we inserted.
        final allConversations = await conversationDao.getAll();
        expect(allConversations.length, InjectionMockDatabase.maliciousPayloads.length);

        // 3. Test updating a title to a malicious SQL injection payload
        const updatePayload = "'; DROP TABLE conversations; --";
        final targetConv = allConversations.first;
        final updatedConv = targetConv.copyWith(title: updatePayload);

        await conversationDao.update(updatedConv);

        final retrievedUpdated = await conversationDao.getById(targetConv.id);
        expect(retrievedUpdated, isNotNull);
        expect(retrievedUpdated!.title, updatePayload);

        // Verify all other conversations are still present and unaffected
        final allConversationsPostUpdate = await conversationDao.getAll();
        expect(allConversationsPostUpdate.length, InjectionMockDatabase.maliciousPayloads.length);
      });
    });

    group('Message Content Injection', () {
      late MessageDao messageDao;

      setUp(() {
        messageDao = MessageDao(dbHelper);
      });

      test('should safely handle malicious SQL injection payloads in Message Content', () async {
        final now = DateTime.now();
        const conversationId = 'conv-for-messages';

        // Test insertion of messages with each SQL injection payload
        for (int i = 0; i < InjectionMockDatabase.maliciousPayloads.length; i++) {
          final payload = InjectionMockDatabase.maliciousPayloads[i];
          final msgId = 'msg-injection-$i';

          final message = ChatMessage(
            id: msgId,
            conversationId: conversationId,
            role: 'user',
            content: payload,
            timestamp: now.add(Duration(seconds: i)),
          );

          // 1. Insert message
          await messageDao.insert(message);

          // 2. Retrieve message and verify
          final retrieved = await messageDao.getById(msgId);
          expect(retrieved, isNotNull);
          expect(retrieved!.content, payload);
          expect(retrieved.id, msgId);
        }

        // 3. Retrieve all messages for the conversation
        final allMessages = await messageDao.getMessagesForConversation(conversationId);
        expect(allMessages.length, InjectionMockDatabase.maliciousPayloads.length);

        // Verify content order and values match exactly
        for (int i = 0; i < allMessages.length; i++) {
          expect(allMessages[i].content, InjectionMockDatabase.maliciousPayloads[i]);
        }
      });
    });

    group('API Config Injection', () {
      late ApiConfigDao apiConfigDao;

      setUp(() {
        apiConfigDao = ApiConfigDao(dbHelper, secureStorageService);
      });

      test('should safely handle malicious SQL injection payloads in API Config fields', () async {
        final now = DateTime.now();

        for (int i = 0; i < InjectionMockDatabase.maliciousPayloads.length; i++) {
          final payload = InjectionMockDatabase.maliciousPayloads[i];
          final configId = 'api-injection-$i';

          final config = ApiConfig(
            id: configId,
            name: payload,
            baseUrl: 'https://api.example.com/v1/$payload',
            apiKeyRef: 'api-key-ref-$i-$payload',
            isDefault: i == 0,
            createdAt: now,
          );

          final plaintextKey = 'secret-key-$i-$payload';

          // 1. Insert API config (saves to SQLite and SecureStorage)
          await apiConfigDao.insert(config, plaintextKey);

          // 2. Retrieve from DAO and verify
          final retrieved = await apiConfigDao.getById(configId);
          expect(retrieved, isNotNull);
          expect(retrieved!.name, payload);
          expect(retrieved.baseUrl, 'https://api.example.com/v1/$payload');
          expect(retrieved.apiKeyRef, 'api-key-ref-$i-$payload');

          // Verify the plaintext API key is correctly matched in secure storage under its ref
          final loadedKey = await apiConfigDao.getApiKey(retrieved.apiKeyRef);
          expect(loadedKey, plaintextKey);
        }

        // Verify the database contains all inserted configs (the table was not dropped/compromised)
        final allConfigs = await apiConfigDao.getAll();
        expect(allConfigs.length, InjectionMockDatabase.maliciousPayloads.length);
      });
    });

    group('ID Injection (SQL Parameterization Check)', () {
      late ConversationDao conversationDao;

      setUp(() {
        conversationDao = ConversationDao(dbHelper);
      });

      test('should fail to fetch or delete other data when IDs are crafted as SQL injection payloads', () async {
        final now = DateTime.now();

        // 1. Insert a legitimate conversation
        final legitimateConv = Conversation(
          id: 'legit-conv-id',
          title: 'Legitimate Chat',
          apiConfigId: 'api-1',
          modelId: 'gpt-4o',
          isPinned: false,
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        );
        await conversationDao.insert(legitimateConv);

        // Verify it exists
        expect(await conversationDao.getById('legit-conv-id'), isNotNull);

        // 2. Try to getById using a malicious SQL injection ID
        // If query was not parameterized, this might bypass the ID constraint or crash.
        // With parameterized query, it looks for the exact string, finds nothing, and returns null.
        const maliciousId = "legit-conv-id' OR '1'='1";
        final retrieved = await conversationDao.getById(maliciousId);
        expect(retrieved, isNull);

        // Try another malicious ID designed to drop tables or delete records
        const maliciousIdDelete = "legit-conv-id'; DELETE FROM conversations; --";
        final retrievedDelete = await conversationDao.getById(maliciousIdDelete);
        expect(retrievedDelete, isNull);

        // Verify the legitimate conversation is STILL in the database (not deleted or modified)
        expect(await conversationDao.getById('legit-conv-id'), isNotNull);

        // 3. Try to delete using a malicious ID payload
        // If not parameterized, this might delete the entire table.
        // With parameterization, it will try to delete a conversation with ID: "legit-conv-id' OR '1'='1", which affects 0 rows.
        await conversationDao.delete(maliciousId);

        // Verify legitimate conversation is still intact
        expect(await conversationDao.getById('legit-conv-id'), isNotNull);

        // Clean up legitimately
        await conversationDao.delete('legit-conv-id');
        expect(await conversationDao.getById('legit-conv-id'), isNull);
      });
    });
  });
}
