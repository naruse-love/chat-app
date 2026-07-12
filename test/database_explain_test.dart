// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_explain_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(null);

    db = await dbHelper.database;
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

  group('Database Query Plan Verification', () {
    test('Verify indices are used in EXPLAIN QUERY PLAN', () async {
      print('=== EXPLAIN QUERY PLAN VERIFICATION ===');

      // 1. Check index usage for getMessagesForConversation query
      // Query: SELECT * FROM messages WHERE conversationId = ? ORDER BY timestamp ASC
      final msgQueryPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM messages WHERE conversationId = ? ORDER BY timestamp ASC',
        ['some_conv_id'],
      );
      print('Messages query plan:');
      for (final row in msgQueryPlan) {
        print('  $row');
      }
      
      // We expect the query plan to use index 'idx_messages_conversation_timestamp'
      final msgPlanStr = msgQueryPlan.toString().toLowerCase();
      expect(
        msgPlanStr.contains('idx_messages_conversation_timestamp') ||
        msgPlanStr.contains('idx_messages_conversation_id'),
        isTrue,
        reason: 'Messages query should use conversation_timestamp or conversationId index.',
      );

      // 2. Check index usage for getAll conversations query
      // Query: SELECT * FROM conversations ORDER BY isPinned DESC, updatedAt DESC
      final convQueryPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM conversations ORDER BY isPinned DESC, updatedAt DESC',
      );
      print('Conversations query plan:');
      for (final row in convQueryPlan) {
        print('  $row');
      }

      final convPlanStr = convQueryPlan.toString().toLowerCase();
      expect(
        convPlanStr.contains('idx_conversations_pinned_updated'),
        isTrue,
        reason: 'Conversations query should use idx_conversations_pinned_updated index.',
      );

      // 3. Check index usage for conversations by apiConfigId query
      // Query: SELECT * FROM conversations WHERE apiConfigId = ?
      final apiConfigQueryPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM conversations WHERE apiConfigId = ?',
        ['some_api_id'],
      );
      print('Conversations by apiConfigId query plan:');
      for (final row in apiConfigQueryPlan) {
        print('  $row');
      }

      final apiConfigPlanStr = apiConfigQueryPlan.toString().toLowerCase();
      expect(
        apiConfigPlanStr.contains('idx_conversations_api_config_id'),
        isTrue,
        reason: 'Conversations by apiConfigId query should use idx_conversations_api_config_id index.',
      );

      print('=== EXPLAIN QUERY PLAN VERIFICATION END ===');
    });
  });
}
