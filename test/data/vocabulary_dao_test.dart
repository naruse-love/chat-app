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
      version: 5,
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
  });
}
