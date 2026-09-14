import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/vocabulary_dao.dart';
import 'package:chat/models/vocabulary_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseHelper dbHelper;
  late VocabularyDao dao;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('vocab_dao_test_');
    final dbPath = p.join(tempDir.path, 'test_vocab.db');

    db = await openDatabase(
      dbPath,
      version: 7,
      onCreate: (db, version) async {
        await DatabaseHelper.instance.testOnCreate(db, version);
      },
      onUpgrade: (db, oldV, newV) async {
        await DatabaseHelper.instance.testOnUpgrade(db, oldV, newV);
      },
    );

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(db);
    dao = VocabularyDao(dbHelper: dbHelper);
  });

  tearDown(() async {
    await db.close();
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('VocabularyDao CRUD & Deduplication Tests', () {
    test('insert and getById returns correct entry with autoincrement ID', () async {
      final now = DateTime.now();
      final entry = VocabularyEntry(
        vocabKanji: '食べる',
        vocabFurigana: 'たべる',
        vocabDefJa: '食物をかんで、のみこむ。',
        vocabDefSc: '吃，咀嚼并吞咽食物。',
        vocabPoS: '動バ下一',
        sentKanji1: '生で食べる',
        sentFurigana1: '生[なま]で食べる',
        sentDefSc1: '生吃',
        sentKanji2: 'ひと口食べてみる',
        sentFurigana2: 'ひと口食べてみる',
        sentDefSc2: '尝一口看看',
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/食べる',
        createdAt: now,
      );

      final insertedId = await dao.insert(entry);
      expect(insertedId, isPositive);

      final retrieved = await dao.getById(insertedId);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, insertedId);
      expect(retrieved.vocabKanji, '食べる');
      expect(retrieved.vocabFurigana, 'たべる');
      expect(retrieved.vocabDefJa, '食物をかんで、のみこむ。');
      expect(retrieved.vocabDefSc, '吃，咀嚼并吞咽食物。');
      expect(retrieved.vocabPoS, '動バ下一');
      expect(retrieved.sentKanji1, '生で食べる');
      expect(retrieved.sentFurigana1, '生[なま]で食べる');
      expect(retrieved.sentDefSc1, '生吃');
      expect(retrieved.sentKanji2, 'ひと口食べてみる');
      expect(retrieved.sentDefSc2, '尝一口看看');
      expect(retrieved.sourceDict, 'デジタル大辞泉');
    });

    test('insert with existing vocabKanji updates the record instead of duplicating', () async {
      final id1 = await dao.insert(VocabularyEntry(
        vocabKanji: '食べる',
        vocabFurigana: 'たべる',
        vocabDefJa: '释义1',
        createdAt: DateTime.now(),
      ));
      expect(await dao.count(), 1);

      // Insert same word with updated definition, without id
      final id2 = await dao.insert(VocabularyEntry(
        vocabKanji: '食べる',
        vocabFurigana: 'たべる',
        vocabDefJa: '释义2 - 已更新',
        createdAt: DateTime.now(),
      ));

      expect(id2, id1); // Reused the same ID
      expect(await dao.count(), 1); // Total row count remains 1

      final updated = await dao.getById(id1);
      expect(updated!.vocabDefJa, '释义2 - 已更新');
    });

    test('findByKanji successfully finds cached word and trims whitespace', () async {
      final now = DateTime.now();
      final entry = VocabularyEntry(
        vocabKanji: '走る',
        vocabFurigana: 'はしる',
        vocabDefJa: '足を速く動かして前進する。',
        vocabDefSc: '跑，奔跑。',
        createdAt: now,
      );

      await dao.insert(entry);

      // Exact match
      final match = await dao.findByKanji('走る');
      expect(match, isNotNull);
      expect(match!.vocabKanji, '走る');

      // Whitespace padded query
      final paddedMatch = await dao.findByKanji('  走る \n');
      expect(paddedMatch, isNotNull);
      expect(paddedMatch!.vocabKanji, '走る');

      // Non-existent word
      final none = await dao.findByKanji('飛ぶ');
      expect(none, isNull);

      // Empty string query
      final empty = await dao.findByKanji('   ');
      expect(empty, isNull);
    });

    test('getAll supports empty filter and multi-field keyword search', () async {
      final t1 = DateTime.now().subtract(const Duration(minutes: 10));
      final t2 = DateTime.now().subtract(const Duration(minutes: 5));
      final t3 = DateTime.now();

      await dao.insert(VocabularyEntry(
        vocabKanji: '美しい',
        vocabFurigana: 'うつくしい',
        vocabDefJa: '形や色がきれいである。',
        vocabDefSc: '美丽，漂亮。',
        createdAt: t1,
      ));

      await dao.insert(VocabularyEntry(
        vocabKanji: '猫',
        vocabFurigana: 'ねこ',
        vocabDefJa: '食肉目の哺乳類。',
        vocabDefSc: '猫，猫咪。',
        createdAt: t2,
      ));

      await dao.insert(VocabularyEntry(
        vocabKanji: '犬',
        vocabFurigana: 'いぬ',
        vocabDefJa: '食肉目の哺乳類。',
        vocabDefSc: '狗，小狗。',
        createdAt: t3,
      ));

      // 1. All without filter (sorted by createdAt DESC)
      final all = await dao.getAll();
      expect(all.length, 3);
      expect(all[0].vocabKanji, '犬');
      expect(all[1].vocabKanji, '猫');
      expect(all[2].vocabKanji, '美しい');

      // 2. Search by kanji
      final kanjiResults = await dao.getAll(searchQuery: '猫');
      expect(kanjiResults.length, 1);
      expect(kanjiResults.first.vocabKanji, '猫');

      // 3. Search by furigana
      final furiganaResults = await dao.getAll(searchQuery: 'うつく');
      expect(furiganaResults.length, 1);
      expect(furiganaResults.first.vocabKanji, '美しい');

      // 4. Search by Chinese definition
      final defScResults = await dao.getAll(searchQuery: '漂亮');
      expect(defScResults.length, 1);
      expect(defScResults.first.vocabKanji, '美しい');

      // 5. Search by Japanese definition
      final defJaResults = await dao.getAll(searchQuery: '哺乳類');
      expect(defJaResults.length, 2);
    });

    test('delete, deleteAll, and count', () async {
      expect(await dao.count(), 0);

      final id1 = await dao.insert(VocabularyEntry(
        vocabKanji: '単語1',
        createdAt: DateTime.now(),
      ));
      final id2 = await dao.insert(VocabularyEntry(
        vocabKanji: '単語2',
        createdAt: DateTime.now(),
      ));

      expect(await dao.count(), 2);

      await dao.delete(id1);
      expect(await dao.count(), 1);
      expect(await dao.getById(id1), isNull);
      expect(await dao.getById(id2), isNotNull);

      await dao.deleteAll();
      expect(await dao.count(), 0);
    });

    test('testOnUpgrade from version 4 to 5 creates vocabulary table and indexes', () async {
      final upgradeTempDir = Directory.systemTemp.createTempSync('upgrade_test_');
      final upgradeDbPath = p.join(upgradeTempDir.path, 'upgrade.db');

      // 1. Open as v4
      final oldDb = await openDatabase(
        upgradeDbPath,
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE api_configs (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              baseUrl TEXT NOT NULL,
              apiKeyRef TEXT NOT NULL,
              isDefault INTEGER NOT NULL,
              createdAt TEXT NOT NULL
            );
          ''');
          await db.execute('''
            CREATE TABLE conversations (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              apiConfigId TEXT NOT NULL,
              modelId TEXT NOT NULL,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            );
          ''');
        },
      );
      await oldDb.close();

      // 2. Open as v5 triggering onUpgrade
      final upgradedDb = await openDatabase(
        upgradeDbPath,
        version: 5,
        onUpgrade: (db, oldV, newV) async {
          await DatabaseHelper.instance.testOnUpgrade(db, oldV, newV);
        },
      );

      // Verify vocabulary table exists
      final tables = await upgradedDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='vocabulary'",
      );
      expect(tables.length, 1);

      // Verify indexes exist
      final indexes = await upgradedDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='vocabulary'",
      );
      final indexNames = indexes.map((i) => i['name'] as String).toList();
      expect(indexNames, contains('idx_vocabulary_kanji'));
      expect(indexNames, contains('idx_vocabulary_created_at'));

      await upgradedDb.close();
      if (upgradeTempDir.existsSync()) {
        upgradeTempDir.deleteSync(recursive: true);
      }
    });

    test('getUnexported, markAsExported, markAllAsExported, unexportedCount, and resetExportStatus', () async {
      final now = DateTime.now();
      final id1 = await dao.insert(VocabularyEntry(vocabKanji: '青空', createdAt: now));
      final id2 = await dao.insert(VocabularyEntry(vocabKanji: '星空', createdAt: now));
      final id3 = await dao.insert(VocabularyEntry(vocabKanji: '夜空', createdAt: now));

      // 初始全部为未导出
      expect(await dao.unexportedCount(), 3);
      var unexported = await dao.getUnexported();
      expect(unexported.length, 3);
      expect(unexported.map((e) => e.vocabKanji), containsAll(['青空', '星空', '夜空']));

      // 标记单个已导出
      final markRes = await dao.markAsExported(id1);
      expect(markRes, 1);
      expect(await dao.unexportedCount(), 2);
      unexported = await dao.getUnexported();
      expect(unexported.length, 2);
      expect(unexported.any((e) => e.id == id1), isFalse);

      // 批量标记已导出
      final batchRes = await dao.markAllAsExported([id2, id3]);
      expect(batchRes, 2);
      expect(await dao.unexportedCount(), 0);
      expect((await dao.getUnexported()).isEmpty, isTrue);

      // 验证已导出的记录单独查询时 exportedToAnki == true
      final entry1 = await dao.getById(id1);
      expect(entry1?.exportedToAnki, isTrue);

      // 重置导出状态
      final resetCount = await dao.resetExportStatus();
      expect(resetCount, 3);
      expect(await dao.unexportedCount(), 3);
      unexported = await dao.getUnexported();
      expect(unexported.length, 3);
      for (final e in unexported) {
        expect(e.exportedToAnki, isFalse);
      }
    });

    test('database migration v5 to v6 adds exportedToAnki column with default 0', () async {
      final migrationTempDir = Directory.systemTemp.createTempSync('migration_v5_v6_');
      final migrationDbPath = p.join(migrationTempDir.path, 'migration_v5_v6.db');

      // 1. 创建 v5 数据库（不含 exportedToAnki 列）
      final v5Db = await openDatabase(
        migrationDbPath,
        version: 5,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE vocabulary (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              vocabKanji TEXT NOT NULL,
              vocabFurigana TEXT NOT NULL DEFAULT '',
              vocabDefJa TEXT NOT NULL DEFAULT '',
              vocabDefSc TEXT NOT NULL DEFAULT '',
              vocabPoS TEXT NOT NULL DEFAULT '',
              sentKanji1 TEXT,
              sentFurigana1 TEXT,
              sentDefSc1 TEXT,
              sentKanji2 TEXT,
              sentFurigana2 TEXT,
              sentDefSc2 TEXT,
              sourceDict TEXT NOT NULL DEFAULT '',
              sourceUrl TEXT NOT NULL DEFAULT '',
              createdAt TEXT NOT NULL
            );
          ''');
        },
      );

      // 插入一条旧数据
      await v5Db.insert('vocabulary', {
        'vocabKanji': '桜',
        'createdAt': DateTime.now().toIso8601String(),
      });
      await v5Db.close();

      // 2. 升级到 v6
      final v6Db = await openDatabase(
        migrationDbPath,
        version: 6,
        onUpgrade: (db, oldV, newV) async {
          await DatabaseHelper.instance.testOnUpgrade(db, oldV, newV);
        },
      );

      // 验证旧记录默认 exportedToAnki 为 0
      final rows = await v6Db.query('vocabulary', where: 'vocabKanji = ?', whereArgs: ['桜']);
      expect(rows.length, 1);
      expect(rows.first['exportedToAnki'], 0);

      // 验证可以在升级后的表中更新 exportedToAnki
      await v6Db.update('vocabulary', {'exportedToAnki': 1}, where: 'vocabKanji = ?', whereArgs: ['桜']);
      final updatedRows = await v6Db.query('vocabulary', where: 'vocabKanji = ?', whereArgs: ['桜']);
      expect(updatedRows.first['exportedToAnki'], 1);

      await v6Db.close();
      if (migrationTempDir.existsSync()) {
        migrationTempDir.deleteSync(recursive: true);
      }
    });

    test('database migration v6 to v7 adds vocabPitch column with default empty string', () async {
      final migrationTempDir = Directory.systemTemp.createTempSync('migration_v6_v7_');
      final migrationDbPath = p.join(migrationTempDir.path, 'migration_v6_v7.db');

      // 1. 创建 v6 数据库（不含 vocabPitch 列）
      final v6Db = await openDatabase(
        migrationDbPath,
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE vocabulary (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              vocabKanji TEXT NOT NULL,
              vocabFurigana TEXT NOT NULL DEFAULT '',
              vocabDefJa TEXT NOT NULL DEFAULT '',
              vocabDefSc TEXT NOT NULL DEFAULT '',
              vocabPoS TEXT NOT NULL DEFAULT '',
              sentKanji1 TEXT,
              sentFurigana1 TEXT,
              sentDefSc1 TEXT,
              sentKanji2 TEXT,
              sentFurigana2 TEXT,
              sentDefSc2 TEXT,
              sourceDict TEXT NOT NULL DEFAULT '',
              sourceUrl TEXT NOT NULL DEFAULT '',
              createdAt TEXT NOT NULL,
              exportedToAnki INTEGER NOT NULL DEFAULT 0
            );
          ''');
        },
      );

      // 插入一条旧数据
      await v6Db.insert('vocabulary', {
        'vocabKanji': 'いとも',
        'createdAt': DateTime.now().toIso8601String(),
      });
      await v6Db.close();

      // 2. 升级到 v7
      final v7Db = await openDatabase(
        migrationDbPath,
        version: 7,
        onUpgrade: (db, oldV, newV) async {
          await DatabaseHelper.instance.testOnUpgrade(db, oldV, newV);
        },
      );

      // 验证旧记录默认 vocabPitch 为 ''
      final rows = await v7Db.query('vocabulary', where: 'vocabKanji = ?', whereArgs: ['いとも']);
      expect(rows.length, 1);
      expect(rows.first['vocabPitch'], '');

      // 验证可以在升级后的表中更新 vocabPitch
      await v7Db.update('vocabulary', {'vocabPitch': '①'}, where: 'vocabKanji = ?', whereArgs: ['いとも']);
      final updatedRows = await v7Db.query('vocabulary', where: 'vocabKanji = ?', whereArgs: ['いとも']);
      expect(updatedRows.first['vocabPitch'], '①');

      await v7Db.close();
      if (migrationTempDir.existsSync()) {
        migrationTempDir.deleteSync(recursive: true);
      }
    });
  });
}
