// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/api_config_dao.dart';
import 'package:chat/data/conversation_dao.dart';
import 'package:chat/data/message_dao.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/conversation.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #write) {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      return Future(() async {
        await Future.delayed(const Duration(milliseconds: 1));
        if (value != null) {
          _data[key] = value;
        } else {
          _data.remove(key);
        }
      });
    }
    if (name == #read) {
      final key = invocation.namedArguments[#key] as String;
      return Future(() async {
        await Future.delayed(const Duration(milliseconds: 1));
        return _data[key];
      });
    }
    if (name == #delete) {
      final key = invocation.namedArguments[#key] as String;
      return Future(() async {
        await Future.delayed(const Duration(milliseconds: 1));
        _data.remove(key);
      });
    }
    if (name == #deleteAll) {
      return Future(() async {
        await Future.delayed(const Duration(milliseconds: 1));
        _data.clear();
      });
    }
    if (name == #containsKey) {
      final key = invocation.namedArguments[#key] as String;
      return Future(() async {
        await Future.delayed(const Duration(milliseconds: 1));
        return _data.containsKey(key);
      });
    }
    return super.noSuchMethod(invocation);
  }

  Map<String, String> getAllData() => Map.unmodifiable(_data);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late FakeSecureStorage fakeSecureStorage;
  late SecureStorageService secureStorageService;
  late ApiConfigDao apiConfigDao;
  late ConversationDao conversationDao;
  late MessageDao messageDao;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_concurrency_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(null);
    db = await dbHelper.database;

    fakeSecureStorage = FakeSecureStorage();
    secureStorageService = SecureStorageService(storage: fakeSecureStorage);
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

  group('Database Concurrency and Transaction Safety Tests', () {
    test('Concurrent default API config updates maintain strict single-default integrity', () async {
      print('=== CONCURRENT DEFAULT API CONFIG UPDATES TEST ===');
      
      // 1. Insert 5 API configurations
      final now = DateTime.now();
      for (int i = 1; i <= 5; i++) {
        final config = ApiConfig(
          id: 'config_$i',
          name: 'API Config $i',
          baseUrl: 'https://api.example.com/$i',
          apiKeyRef: 'key_ref_$i',
          isDefault: false,
          createdAt: now,
        );
        await apiConfigDao.insert(config, 'key_value_$i');
      }

      // Verify initially none or exactly one (if auto-set, though we set isDefault: false) is default
      var allConfigs = await apiConfigDao.getAll();
      expect(allConfigs.length, 5);
      expect(allConfigs.where((c) => c.isDefault).length, 0);

      // 2. Spawn 100 concurrent tasks attempting to set different configs as default
      // We also do concurrent read tasks to verify dirty reads or inconsistent states don't crash the system.
      final random = Random();
      final List<Future<void>> futures = [];

      for (int i = 0; i < 100; i++) {
        // Randomly choose a config to set as default
        final targetConfigIndex = random.nextInt(5) + 1;
        futures.add(Future(() async {
          final config = await apiConfigDao.getById('config_$targetConfigIndex');
          if (config != null) {
            // Update to default
            await apiConfigDao.update(config.copyWith(isDefault: true));
          }
        }));

        // Insert some random reads too
        futures.add(Future(() async {
          final currentDefault = await apiConfigDao.getDefault();
          if (currentDefault != null) {
            final key = await apiConfigDao.getApiKey(currentDefault.apiKeyRef);
            expect(key, isNotNull);
          }
        }));
      }

      await Future.wait(futures);

      // 3. Verify database integrity post concurrency
      allConfigs = await apiConfigDao.getAll();
      final defaultConfigs = allConfigs.where((c) => c.isDefault).toList();
      print('Total default configs after concurrent storm: ${defaultConfigs.length}');
      for (final def in defaultConfigs) {
        print('  Default config: ${def.id}');
      }

      // Assert that AT MOST one configuration can be set as default.
      // Under high load, one config will win.
      expect(defaultConfigs.length, lessThanOrEqualTo(1));

      // Check secure storage alignment:
      // Verify that all keys in secure storage exist in the database and match.
      final secureData = fakeSecureStorage.getAllData();
      print('Secure storage size: ${secureData.length}');
      for (final entry in secureData.entries) {
        final keyRef = entry.key;
        final keyValue = entry.value;
        // Verify keyRef is in database
        final matches = allConfigs.where((c) => c.apiKeyRef == keyRef).toList();
        expect(matches.length, 1, reason: 'Key reference $keyRef in secure storage has no matching DB record.');
        expect(keyValue, 'key_value_${matches.first.id.split('_')[1]}');
      }

      print('=== CONCURRENT DEFAULT API CONFIG UPDATES TEST END ===');
    });

    test('Concurrent message insertions and conversation updates under load', () async {
      print('=== CONCURRENT MESSAGE INSERTIONS TEST ===');

      // 1. Insert default config and a conversation
      final now = DateTime.now();
      final config = ApiConfig(
        id: 'default_config',
        name: 'Default',
        baseUrl: 'https://api.example.com',
        apiKeyRef: 'default_ref',
        isDefault: true,
        createdAt: now,
      );
      await apiConfigDao.insert(config, 'secret');

      final conversation = Conversation(
        id: 'conv_concurrency',
        title: 'Concurrent Chat',
        apiConfigId: 'default_config',
        modelId: 'gpt-4o',
        isPinned: false,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );
      await conversationDao.insert(conversation);

      // 2. Spawn 150 concurrent message insertions and conversation updates
      final List<Future<void>> futures = [];
      for (int i = 0; i < 150; i++) {
        futures.add(Future(() async {
          final message = ChatMessage(
            id: 'msg_conc_$i',
            conversationId: 'conv_concurrency',
            role: i % 2 == 0 ? 'user' : 'assistant',
            content: 'Concurrent message #$i content.',
            timestamp: DateTime.now().add(Duration(milliseconds: i)),
          );
          await messageDao.insert(message);
        }));

        futures.add(Future(() async {
          final conv = await conversationDao.getById('conv_concurrency');
          if (conv != null) {
            await conversationDao.update(
              conv.copyWith(
                title: 'Updated Title $i',
                updatedAt: DateTime.now(),
              ),
            );
          }
        }));
      }

      await Future.wait(futures);

      // 3. Verify all messages are inserted and order is preserved
      final messages = await messageDao.getMessagesForConversation('conv_concurrency');
      print('Inserted messages count under concurrency: ${messages.length}');
      expect(messages.length, 150);

      // Verify that timestamps are strictly ascending or equal (ordered correctly)
      for (int i = 0; i < messages.length - 1; i++) {
        expect(
          messages[i].timestamp.isBefore(messages[i + 1].timestamp) ||
          messages[i].timestamp.isAtSameMomentAs(messages[i + 1].timestamp),
          isTrue,
        );
      }

      print('=== CONCURRENT MESSAGE INSERTIONS TEST END ===');
    });
  });
}
