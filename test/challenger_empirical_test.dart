// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/conversation_dao.dart';
import 'package:chat/data/message_dao.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/models/conversation.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/api_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

class FailableDatabase implements Database {
  final Database inner;
  bool shouldFail = false;

  FailableDatabase(this.inner);

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    if (shouldFail) {
      throw Exception('Simulated transaction failure');
    }
    return await inner.transaction((txn) async {
      if (shouldFail) {
        throw Exception('Simulated transaction failure');
      }
      return await action(FailableTransaction(txn, () => shouldFail));
    }, exclusive: exclusive);
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
  }) {
    return inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    if (shouldFail) {
      throw Exception('Simulated delete failure');
    }
    return inner.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {
    if (shouldFail) {
      throw Exception('Simulated insert failure');
    }
    return inner.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  }

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) {
    if (shouldFail) {
      throw Exception('Simulated update failure');
    }
    return inner.update(table, values, where: where, whereArgs: whereArgs, conflictAlgorithm: conflictAlgorithm);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('noSuchMethod in FailableDatabase for ${invocation.memberName}');
  }
}

class FailableTransaction implements Transaction {
  final Transaction inner;
  final bool Function() shouldFailFn;

  FailableTransaction(this.inner, this.shouldFailFn);

  @override
  Future<int> update(String table, Map<String, Object?> values, {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    if (shouldFailFn()) {
      throw Exception('Simulated update failure inside transaction');
    }
    return await inner.update(table, values, where: where, whereArgs: whereArgs, conflictAlgorithm: conflictAlgorithm);
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    if (shouldFailFn()) {
      throw Exception('Simulated insert failure inside transaction');
    }
    return await inner.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
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
  }) {
    if (shouldFailFn()) {
      throw Exception('Simulated query failure inside transaction');
    }
    return inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    if (shouldFailFn()) {
      throw Exception('Simulated delete failure inside transaction');
    }
    return inner.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    if (shouldFailFn()) {
      throw Exception('Simulated execute failure inside transaction');
    }
    return inner.execute(sql, arguments);
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) {
    throw UnimplementedError('Nested transaction not implemented in FailableTransaction');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('noSuchMethod in FailableTransaction for ${invocation.memberName}');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late Database db;
  late MockFlutterSecureStorage mockSecureStorage;
  late SecureStorageService secureStorageService;
  late ApiConfigDao apiConfigDao;
  late ConversationDao conversationDao;
  late MessageDao messageDao;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_challenger_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(null);

    db = await dbHelper.database;

    mockSecureStorage = MockFlutterSecureStorage();
    secureStorageService = SecureStorageService(storage: mockSecureStorage);
    apiConfigDao = ApiConfigDao(dbHelper, secureStorageService);
    conversationDao = ConversationDao(dbHelper);
    messageDao = MessageDao(dbHelper);
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Challenger Empirical Verification Tests', () {
    test('1. Index Coverage & Query Plan Verification', () async {
      // Check indices exist in sqlite_master
      final List<Map<String, dynamic>> indices = await db.rawQuery(
        "SELECT name, tbl_name, sql FROM sqlite_master WHERE type='index'"
      );

      final indexNames = indices.map((idx) => idx['name'] as String).toList();
      print('Discovered Indexes: $indexNames');

      expect(indexNames, contains('idx_messages_conversation_id'));
      expect(indexNames, contains('idx_conversations_pinned_updated'));
      expect(indexNames, contains('idx_conversations_api_config_id'));
      expect(indexNames, contains('idx_messages_conversation_timestamp'));

      // Explain query plan for Message query by conversationId
      final List<Map<String, dynamic>> planMsg = await db.rawQuery(
        "EXPLAIN QUERY PLAN SELECT * FROM messages WHERE conversationId = 'some-id' ORDER BY timestamp ASC"
      );
      print('Message Query Plan: $planMsg');
      final planMsgStr = planMsg.map((row) => row['detail'] as String).join('\n');
      expect(planMsgStr, contains('idx_messages_conversation_timestamp'));

      // Explain query plan for Conversation query ordered by pinned & updated desc
      final List<Map<String, dynamic>> planConv = await db.rawQuery(
        "EXPLAIN QUERY PLAN SELECT * FROM conversations ORDER BY isPinned DESC, updatedAt DESC"
      );
      print('Conversation Query Plan: $planConv');
      final planConvStr = planConv.map((row) => row['detail'] as String).join('\n');
      expect(planConvStr, contains('idx_conversations_pinned_updated'));
    });

    test('2. Foreign Key Cascade Delete Verification', () async {
      // 1. Insert ApiConfig
      final config = ApiConfig(
        id: 'test-config-fk',
        name: 'Config for FK',
        baseUrl: 'https://test.com',
        apiKeyRef: 'key-ref-fk',
        isDefault: false,
        createdAt: DateTime.now(),
      );
      await apiConfigDao.insert(config, 'my-secret-api-key');

      // 2. Insert Conversation referencing the ApiConfig
      final conversation = Conversation(
        id: 'test-conv-fk',
        title: 'Conversation for FK',
        apiConfigId: config.id,
        modelId: 'gpt-4',
        isPinned: false,
        isArchived: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await conversationDao.insert(conversation);

      // 3. Insert ChatMessage referencing the Conversation
      final message = ChatMessage(
        id: 'test-msg-fk',
        conversationId: conversation.id,
        role: 'user',
        content: 'Hello FK',
        timestamp: DateTime.now(),
      );
      await messageDao.insert(message);

      // Verify they all exist in SQLite
      expect((await apiConfigDao.getById(config.id)), isNotNull);
      expect((await conversationDao.getById(conversation.id)), isNotNull);
      expect((await messageDao.getById(message.id)), isNotNull);

      // Verify secret is in secure storage
      expect(await mockSecureStorage.read(key: config.apiKeyRef), 'my-secret-api-key');

      // Delete ApiConfig using ApiConfigDao.delete
      await apiConfigDao.delete(config.id);

      // Verify ApiConfig metadata was deleted
      expect((await apiConfigDao.getById(config.id)), isNull);
      // Verify ApiKey is deleted from secure storage
      expect(await mockSecureStorage.read(key: config.apiKeyRef), isNull);

      // Verify Conversation was CASCADE deleted
      expect((await conversationDao.getById(conversation.id)), isNull);
      // Verify ChatMessage was CASCADE deleted
      expect((await messageDao.getById(message.id)), isNull);
    });

    test('3. Default ApiConfig Flag Integrity Under Concurrency', () async {
      final random = Random();

      // Create 20 different ApiConfigs, setting isDefault = true concurrently
      final futures = List.generate(20, (index) async {
        final config = ApiConfig(
          id: 'concurrent-config-$index',
          name: 'Config $index',
          baseUrl: 'https://api.com/$index',
          apiKeyRef: 'key-ref-$index',
          isDefault: true,
          createdAt: DateTime.now(),
        );
        // Sleep a random small millisecond duration to interleave transactions
        await Future.delayed(Duration(microseconds: random.nextInt(500)));
        await apiConfigDao.insert(config, 'key-$index');
      });

      await Future.wait(futures);

      // Verify that after concurrent inserts, there is exactly ONE default config
      final allConfigs = await apiConfigDao.getAll();
      final defaultConfigs = allConfigs.where((c) => c.isDefault).toList();
      print('Default Configs count after inserts: ${defaultConfigs.length}');
      expect(defaultConfigs.length, 1);

      // Concurrently update different configs to default
      final updateFutures = List.generate(10, (index) async {
        final config = allConfigs[index].copyWith(isDefault: true);
        await Future.delayed(Duration(microseconds: random.nextInt(500)));
        await apiConfigDao.update(config);
      });

      await Future.wait(updateFutures);

      // Verify again that only ONE default config exists
      final postUpdateConfigs = await apiConfigDao.getAll();
      final postUpdateDefaults = postUpdateConfigs.where((c) => c.isDefault).toList();
      print('Default Configs count after updates: ${postUpdateDefaults.length}');
      expect(postUpdateDefaults.length, 1);
    });

    test('4a. API Key Secure Storage Leak Prevention (Orphan Key Leak)', () async {
      // Construct a config that does not exist in SQLite
      final nonExistentConfig = ApiConfig(
        id: 'non-existent-config-id',
        name: 'Ghost Config',
        baseUrl: 'https://ghost.com',
        apiKeyRef: 'ghost-key-ref',
        isDefault: false,
        createdAt: DateTime.now(),
      );

      // Verify config does not exist in SQLite
      expect(await apiConfigDao.getById(nonExistentConfig.id), isNull);

      // Call update. This must throw ArgumentError because the config is not found in SQLite.
      expect(
        () => apiConfigDao.update(nonExistentConfig, apiKey: 'ghost-secret-key'),
        throwsArgumentError,
      );

      // Verify that the apiKey is NOT stored in secure storage!
      final storedKey = await mockSecureStorage.read(key: 'ghost-key-ref');
      expect(storedKey, isNull);
    });

    test('4b. API Key Migration Atomicity Failure on DB Exception', () async {
      // 1. Setup a valid config and insert it
      final initialConfig = ApiConfig(
        id: 'migration-fail-id',
        name: 'Initial Config',
        baseUrl: 'https://initial.com',
        apiKeyRef: 'old-key-ref',
        isDefault: false,
        createdAt: DateTime.now(),
      );
      await apiConfigDao.insert(initialConfig, 'original-secret');

      // Verify initial setup
      expect(await mockSecureStorage.read(key: 'old-key-ref'), 'original-secret');
      expect(await apiConfigDao.getById('migration-fail-id'), isNotNull);

      // 2. Wrap db with FailableDatabase to mock transaction/db failure
      final failableDb = FailableDatabase(db);
      dbHelper.setMockDatabase(failableDb);

      // Set helper to fail on SQL operations (e.g. database throws exception)
      failableDb.shouldFail = true;

      // 3. Attempt update to change apiKeyRef (key migration)
      final migratedConfig = initialConfig.copyWith(apiKeyRef: 'new-key-ref');
      
      try {
        await apiConfigDao.update(migratedConfig);
        fail('Should have thrown database exception');
      } catch (e) {
        expect(e.toString(), contains('Simulated transaction failure'));
      }

      // Restore SQL helper
      failableDb.shouldFail = false;
      dbHelper.setMockDatabase(db);

      // 4. Verify DB vs Secure Storage mismatch!
      // SQLite transaction rolled back, so SQLite still has 'old-key-ref' for this config.
      final dbConfig = await apiConfigDao.getById('migration-fail-id');
      expect(dbConfig, isNotNull);
      expect(dbConfig!.apiKeyRef, 'old-key-ref'); // SQLite still references the old key ref!

      // Atomic rollback verification: old-key-ref must still have original-secret
      expect(await mockSecureStorage.read(key: 'old-key-ref'), 'original-secret');
      // And new-key-ref must be cleaned up (deleted)
      expect(await mockSecureStorage.read(key: 'new-key-ref'), isNull);
    });

    test('4c. API Key Insertion Failure Leak Verification', () async {
      final config = ApiConfig(
        id: 'insert-fail-id',
        name: 'Fail Insert Config',
        baseUrl: 'https://fail-insert.com',
        apiKeyRef: 'fail-insert-key-ref',
        isDefault: false,
        createdAt: DateTime.now(),
      );

      // Wrap db with FailableDatabase to mock transaction/db failure
      final failableDb = FailableDatabase(db);
      dbHelper.setMockDatabase(failableDb);
      failableDb.shouldFail = true;

      try {
        await apiConfigDao.insert(config, 'secret-to-leak');
        fail('Should have thrown database exception');
      } catch (e) {
        expect(e.toString(), contains('Simulated transaction failure'));
      }

      // Restore SQL helper
      failableDb.shouldFail = false;
      dbHelper.setMockDatabase(db);

      // Verify DB does not contain the config
      expect(await apiConfigDao.getById('insert-fail-id'), isNull);

      // Verify that the apiKey is rolled back (deleted) in secure storage on insert failure
      final storedKey = await mockSecureStorage.read(key: 'fail-insert-key-ref');
      expect(storedKey, isNull);
    });

    test('4d. API Key Overwrite Rollback on DB Exception', () async {
      // 1. Setup a valid config and insert it
      final config = ApiConfig(
        id: 'overwrite-fail-id',
        name: 'Overwrite Config',
        baseUrl: 'https://overwrite.com',
        apiKeyRef: 'overwrite-key-ref',
        isDefault: false,
        createdAt: DateTime.now(),
      );
      await apiConfigDao.insert(config, 'original-secret');

      // Verify setup
      expect(await mockSecureStorage.read(key: 'overwrite-key-ref'), 'original-secret');
      expect(await apiConfigDao.getById('overwrite-fail-id'), isNotNull);

      // 2. Wrap db with FailableDatabase to mock transaction/db failure
      final failableDb = FailableDatabase(db);
      dbHelper.setMockDatabase(failableDb);
      failableDb.shouldFail = true;

      // 3. Try to update the configuration with a new apiKey (but keeping the same apiKeyRef)
      try {
        await apiConfigDao.update(config, apiKey: 'new-leaked-secret');
        fail('Should have thrown database exception');
      } catch (e) {
        expect(e.toString(), contains('Simulated transaction failure'));
      }

      // 4. Restore SQL helper
      failableDb.shouldFail = false;
      dbHelper.setMockDatabase(db);

      // 5. Verify that secure storage has rolled back to the old key under apiKeyRef
      final storedKey = await mockSecureStorage.read(key: 'overwrite-key-ref');
      expect(storedKey, 'original-secret');
    });

    test('4e. API Key Plaintext Storage Exclusion in Database File', () async {
      const String databaseSecret = 'MY-SECRET-API-KEY-THAT-MUST-NEVER-BE-IN-SQLITE';
      final config = ApiConfig(
        id: 'plaintext-exclude-id',
        name: 'Plaintext Exclude Config',
        baseUrl: 'https://plaintext-exclude.com',
        apiKeyRef: 'plaintext-exclude-key-ref',
        isDefault: false,
        createdAt: DateTime.now(),
      );

      // Insert using the API config DAO
      await apiConfigDao.insert(config, databaseSecret);

      // Find the physical database file
      final dbPath = '${tempDir.path}/app_database.db';
      final dbFile = File(dbPath);
      expect(dbFile.existsSync(), isTrue);

      // Read database file contents as a string or raw bytes
      final dbBytes = dbFile.readAsBytesSync();
      final dbContent = String.fromCharCodes(dbBytes);

      // Verify that the secret is NOT present in the database file
      expect(dbContent.contains(databaseSecret), isFalse);

      // Double-check the metadata is present (verifying the file was indeed written to)
      expect(dbContent.contains('plaintext-exclude-key-ref'), isTrue);
    });
  });
}

