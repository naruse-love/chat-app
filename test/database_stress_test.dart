// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/conversation_dao.dart';
import 'package:chat/data/message_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  // Initialize FFI for local SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late ConversationDao conversationDao;
  late MessageDao messageDao;
  late String dbPath;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_stress_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    // Reset DatabaseHelper to force clean initialization
    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(null);

    conversationDao = ConversationDao(dbHelper);
    messageDao = MessageDao(dbHelper);
    dbPath = p.join(tempDir.path, 'app_database.db');
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

  group('Database and Storage Stress Tests', () {
    test('Empirical performance and robustness under heavy workloads', () async {
      print('=== DATABASE STRESS TEST START ===');

      // Ensure database is initialized
      final db = await dbHelper.database;
      expect(File(dbPath).existsSync(), isTrue);

      final initialSize = File(dbPath).lengthSync();
      print('Initial Database Size: ${initialSize / 1024} KB');

      // Insert default API config for foreign key constraint reference
      await db.insert('api_configs', {
        'id': 'api_config_default',
        'name': 'Default Config',
        'baseUrl': 'https://api.openai.com/v1',
        'apiKeyRef': 'default_api_key_ref',
        'isDefault': 1,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // 1. Insert 1,000 Conversations
      print('Inserting 1,000 conversations...');
      final stopwatchConvWrite = Stopwatch()..start();
      
      await db.transaction((txn) async {
        for (int i = 0; i < 1000; i++) {
          final convMap = {
            'id': 'conv_$i',
            'title': 'Conversation #$i',
            'apiConfigId': 'api_config_default',
            'modelId': 'openai/gpt-4o',
            'systemPrompt': 'System prompt for conversation $i',
            'isPinned': i % 10 == 0 ? 1 : 0,
            'isArchived': 0,
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          };
          await txn.insert('conversations', convMap);
        }
      });
      stopwatchConvWrite.stop();
      print('Time taken to write 1,000 conversations: ${stopwatchConvWrite.elapsedMilliseconds} ms');
      print('Average write time per conversation: ${(stopwatchConvWrite.elapsedMilliseconds / 1000).toStringAsFixed(3)} ms');

      // Verify conversation count
      final convs = await conversationDao.getAll();
      expect(convs.length, 1000);

      // 2. Insert 10,000 Messages (10 messages per conversation)
      print('Inserting 10,000 messages (10 per conversation)...');
      final stopwatchMsgWrite = Stopwatch()..start();
      
      await db.transaction((txn) async {
        for (int i = 0; i < 1000; i++) {
          for (int j = 0; j < 10; j++) {
            final msgMap = {
              'id': 'msg_${i}_$j',
              'conversationId': 'conv_$i',
              'role': j % 2 == 0 ? 'user' : 'assistant',
              'content': 'Message content $j for conversation $i. This is a stress test message that contains some content to mimic standard conversation lengths.',
              'reasoningContent': j % 2 == 1 ? 'Reasoning step: analyzing user input for conversation $i message $j. Developing answer.' : null,
              'imagePath': null,
              'toolCalls': null,
              'toolCallId': null,
              'timestamp': DateTime.now().add(Duration(seconds: j)).toIso8601String(),
            };
            await txn.insert('messages', msgMap);
          }
        }
      });
      stopwatchMsgWrite.stop();
      print('Time taken to write 10,000 messages: ${stopwatchMsgWrite.elapsedMilliseconds} ms');
      print('Average write time per message: ${(stopwatchMsgWrite.elapsedMilliseconds / 10000).toStringAsFixed(3)} ms');

      // 3. Verify Database Size after inserts
      final populatedSize = File(dbPath).lengthSync();
      print('Database Size after inserts: ${(populatedSize / (1024 * 1024)).toStringAsFixed(2)} MB (${populatedSize / 1024} KB)');

      // 4. Verify Read Times: Load all conversations
      print('Reading all 1,000 conversations...');
      final stopwatchConvRead = Stopwatch()..start();
      final allConvs = await conversationDao.getAll();
      stopwatchConvRead.stop();
      expect(allConvs.length, 1000);
      print('Time taken to read all 1,000 conversations (sorted): ${stopwatchConvRead.elapsedMilliseconds} ms');

      // 5. Verify Read Times: Load messages for 100 random conversations
      print('Reading messages for 100 random conversations...');
      final random = Random();
      final stopwatchMsgRead = Stopwatch()..start();
      
      for (int k = 0; k < 100; k++) {
        final convIdx = random.nextInt(1000);
        final messages = await messageDao.getMessagesForConversation('conv_$convIdx');
        expect(messages.length, 10);
      }
      stopwatchMsgRead.stop();
      print('Time taken to read messages for 100 random conversations: ${stopwatchMsgRead.elapsedMilliseconds} ms');
      print('Average read time per conversation history (10 messages): ${(stopwatchMsgRead.elapsedMilliseconds / 100).toStringAsFixed(2)} ms');

      // 6. Verify Read Times: Query performance (Searching messages by text)
      print('Searching messages containing keyword...');
      final stopwatchQuery = Stopwatch()..start();
      final List<Map<String, dynamic>> searchResults = await db.query(
        'messages',
        where: 'content LIKE ?',
        whereArgs: ['%content 5%'],
      );
      stopwatchQuery.stop();
      print('Search completed in ${stopwatchQuery.elapsedMilliseconds} ms. Found ${searchResults.length} matches.');

      // 7. Robustness: Concurrent Reads
      print('Testing concurrent reads robustness...');
      final stopwatchConcurrentRead = Stopwatch()..start();
      final readFutures = List.generate(50, (index) {
        final convId = 'conv_${random.nextInt(1000)}';
        return messageDao.getMessagesForConversation(convId);
      });
      final concurrentResults = await Future.wait(readFutures);
      stopwatchConcurrentRead.stop();
      expect(concurrentResults.length, 50);
      print('Completed 50 concurrent reads in ${stopwatchConcurrentRead.elapsedMilliseconds} ms');

      // 8. Robustness: Cascade Delete Performance
      print('Deleting conversations and verifying cascade delete...');
      final stopwatchDelete = Stopwatch()..start();
      // Delete 50 conversations (which should cascade delete 500 messages)
      await db.transaction((txn) async {
        for (int i = 0; i < 50; i++) {
          final convId = 'conv_$i';
          await txn.delete('conversations', where: 'id = ?', whereArgs: [convId]);
        }
      });
      stopwatchDelete.stop();
      print('Time taken to delete 50 conversations (cascade deleting 500 messages): ${stopwatchDelete.elapsedMilliseconds} ms');

      // Verify cascade delete worked
      final remainingConvs = await conversationDao.getAll();
      expect(remainingConvs.length, 950);

      final List<Map<String, dynamic>> remainingMsgs = await db.query('messages');
      expect(remainingMsgs.length, 9500);

      // Verify Database Size after deletes
      final postDeleteSize = File(dbPath).lengthSync();
      print('Database Size after deletes: ${(postDeleteSize / 1024).toStringAsFixed(2)} KB');

      print('=== DATABASE STRESS TEST END ===');
    });
  });
}
