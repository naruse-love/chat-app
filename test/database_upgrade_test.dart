// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_upgrade_test_');
    dbPath = p.join(tempDir.path, 'app_database.db');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Database Upgrade Path Tests', () {
    test('Empirical migration verification from V1 to V2', () async {
      print('=== MIGRATION TEST V1 -> V2 START ===');

      // 1. Initialize database at Version 1 with original schema
      final dbV1 = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          // api_configs table
          await db.execute('''
            CREATE TABLE api_configs (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              baseUrl TEXT NOT NULL,
              apiKeyRef TEXT NOT NULL,
              isDefault INTEGER NOT NULL,
              createdAt TEXT NOT NULL
            )
          ''');

          // conversations table (V1 - without isPinned and isArchived)
          await db.execute('''
            CREATE TABLE conversations (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              apiConfigId TEXT NOT NULL,
              modelId TEXT NOT NULL,
              systemPrompt TEXT,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL,
              FOREIGN KEY (apiConfigId) REFERENCES api_configs (id) ON DELETE CASCADE
            )
          ''');

          // messages table
          await db.execute('''
            CREATE TABLE messages (
              id TEXT PRIMARY KEY,
              conversationId TEXT NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              reasoningContent TEXT,
              imagePath TEXT,
              toolCalls TEXT,
              toolCallId TEXT,
              timestamp TEXT NOT NULL,
              FOREIGN KEY (conversationId) REFERENCES conversations (id) ON DELETE CASCADE
            )
          ''');

          // original index
          await db.execute('''
            CREATE INDEX idx_messages_conversation_id ON messages (conversationId);
          ''');
        },
      );

      // 2. Insert test data under Version 1 schema
      await dbV1.insert('api_configs', {
        'id': 'api_1',
        'name': 'API Config 1',
        'baseUrl': 'https://api.example.com',
        'apiKeyRef': 'key_ref_1',
        'isDefault': 1,
        'createdAt': '2026-07-11T12:00:00Z',
      });

      await dbV1.insert('conversations', {
        'id': 'conv_1',
        'title': 'Test Conversation V1',
        'apiConfigId': 'api_1',
        'modelId': 'gpt-4o',
        'systemPrompt': 'Be helpful.',
        'createdAt': '2026-07-11T12:05:00Z',
        'updatedAt': '2026-07-11T12:05:00Z',
      });

      await dbV1.insert('messages', {
        'id': 'msg_1',
        'conversationId': 'conv_1',
        'role': 'user',
        'content': 'Hello from V1!',
        'timestamp': '2026-07-11T12:06:00Z',
      });

      // Verify the V1 data exists and columns are not there yet
      final v1ConvCheck = await dbV1.query('conversations');
      expect(v1ConvCheck.first.containsKey('isPinned'), isFalse);
      expect(v1ConvCheck.first.containsKey('isArchived'), isFalse);

      await dbV1.close();
      print('Version 1 database closed. Test data stored.');

      // 3. Open the database using DatabaseHelper to trigger the Version 2 upgrade
      final dbHelper = DatabaseHelper.instance;
      dbHelper.setMockDatabase(null);

      // We override the databases path for DatabaseHelper so it points to our temp folder
      // In sqflite, we can accomplish this by setting the mock database or replacing it,
      // or opening it manually using openDatabase with onUpgrade from DatabaseHelper.
      // Let's open it manually using the exact same callbacks as DatabaseHelper:
      print('Upgrading database to Version 2...');
      final dbV2 = await openDatabase(
        dbPath,
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await dbHelper.testOnUpgrade(db, oldVersion, newVersion);
        },
      );

      // 4. Verify structural integrity of V2
      // A. Columns 'isPinned' and 'isArchived' must now exist on 'conversations' table
      final tableInfo = await dbV2.rawQuery('PRAGMA table_info(conversations)');
      print('Conversations Table Info:');
      bool hasPinned = false;
      bool hasArchived = false;
      for (final col in tableInfo) {
        print('  Column: ${col['name']} (${col['type']})');
        if (col['name'] == 'isPinned') hasPinned = true;
        if (col['name'] == 'isArchived') hasArchived = true;
      }
      expect(hasPinned, isTrue, reason: 'isPinned column should be added.');
      expect(hasArchived, isTrue, reason: 'isArchived column should be added.');

      // B. Check that existing V1 data was preserved, and default values are applied
      final migratedConvs = await dbV2.query('conversations');
      expect(migratedConvs.length, 1);
      final migratedConv = migratedConvs.first;
      expect(migratedConv['id'], 'conv_1');
      expect(migratedConv['title'], 'Test Conversation V1');
      expect(migratedConv['isPinned'], 0, reason: 'Default isPinned should be 0 (false).');
      expect(migratedConv['isArchived'], 0, reason: 'Default isArchived should be 0 (false).');

      final migratedMsgs = await dbV2.query('messages');
      expect(migratedMsgs.length, 1);
      expect(migratedMsgs.first['content'], 'Hello from V1!');

      // C. Check that the new indexes have been successfully created
      final indexList = await dbV2.rawQuery('PRAGMA index_list(conversations)');
      print('Conversations index list:');
      bool hasPinnedUpdatedIndex = false;
      bool hasApiConfigIndex = false;
      for (final idx in indexList) {
        print('  Index: ${idx['name']}');
        if (idx['name'] == 'idx_conversations_pinned_updated') hasPinnedUpdatedIndex = true;
        if (idx['name'] == 'idx_conversations_api_config_id') hasApiConfigIndex = true;
      }
      expect(hasPinnedUpdatedIndex, isTrue, reason: 'idx_conversations_pinned_updated should exist.');
      expect(hasApiConfigIndex, isTrue, reason: 'idx_conversations_api_config_id should exist.');

      final msgIndexList = await dbV2.rawQuery('PRAGMA index_list(messages)');
      print('Messages index list:');
      bool hasMsgTimestampIndex = false;
      for (final idx in msgIndexList) {
        print('  Index: ${idx['name']}');
        if (idx['name'] == 'idx_messages_conversation_timestamp') hasMsgTimestampIndex = true;
      }
      expect(hasMsgTimestampIndex, isTrue, reason: 'idx_messages_conversation_timestamp should exist.');

      // D. Verify that we can write to the migrated tables with V2 fields
      await dbV2.insert('conversations', {
        'id': 'conv_v2',
        'title': 'New V2 Conversation',
        'apiConfigId': 'api_1',
        'modelId': 'gpt-4o',
        'isPinned': 1,
        'isArchived': 0,
        'createdAt': '2026-07-11T12:10:00Z',
        'updatedAt': '2026-07-11T12:10:00Z',
      });

      final queryV2 = await dbV2.query('conversations', where: 'id = ?', whereArgs: ['conv_v2']);
      expect(queryV2.length, 1);
      expect(queryV2.first['isPinned'], 1);

      await dbV2.close();
      print('=== MIGRATION TEST V1 -> V2 END ===');
    });
  });
}
