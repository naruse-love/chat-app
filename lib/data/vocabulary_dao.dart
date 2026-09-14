import 'package:sqflite/sqflite.dart';
import '../models/vocabulary_entry.dart';
import 'database_helper.dart';

/// 单词本数据库访问对象 (DAO)
/// 管理 SQLite 中 `vocabulary` 表的增删改查
class VocabularyDao {
  final DatabaseHelper _dbHelper;

  VocabularyDao({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// 插入或替换新单词，返回生成的自增 ID（当单词已存在时更新并返回已有 ID，防止冗余重复行）
  Future<int> insert(VocabularyEntry entry) async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return -1;

    int? effectiveId = entry.id;
    bool effectiveExported = entry.exportedToAnki;
    if (effectiveId == null) {
      final existing = await findByKanji(entry.vocabKanji);
      if (existing != null) {
        effectiveId = existing.id;
        if (!effectiveExported && existing.exportedToAnki) {
          effectiveExported = true;
        }
      }
    }

    final entryToSave = entry.copyWith(
      id: effectiveId,
      exportedToAnki: effectiveExported,
    );
    final map = entryToSave.toMap();

    final resultId = await db.insert(
      'vocabulary',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return effectiveId ?? resultId;
  }

  /// 按汉字/单词精准查找（去重与缓存命中用）
  Future<VocabularyEntry?> findByKanji(String kanji) async {
    final clean = kanji.trim();
    if (clean.isEmpty) return null;

    final db = await _dbHelper.database;
    if (!db.isOpen) return null;
    final List<Map<String, dynamic>> maps = await db.query(
      'vocabulary',
      where: 'vocabKanji = ?',
      whereArgs: [clean],
      orderBy: 'createdAt DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return VocabularyEntry.fromMap(maps.first);
  }

  /// 按主键 ID 查询
  Future<VocabularyEntry?> getById(int id) async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return null;
    final List<Map<String, dynamic>> maps = await db.query(
      'vocabulary',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return VocabularyEntry.fromMap(maps.first);
  }

  /// 获取单词列表，支持关键字搜索（支持汉字、假名、中文释义、日文释义）
  Future<List<VocabularyEntry>> getAll({String? searchQuery}) async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return [];
    final cleanQuery = searchQuery?.trim();

    final List<Map<String, dynamic>> maps;
    if (cleanQuery != null && cleanQuery.isNotEmpty) {
      final likePattern = '%$cleanQuery%';
      maps = await db.query(
        'vocabulary',
        where:
            'vocabKanji LIKE ? OR vocabFurigana LIKE ? OR vocabDefSc LIKE ? OR vocabDefJa LIKE ?',
        whereArgs: [likePattern, likePattern, likePattern, likePattern],
        orderBy: 'createdAt DESC',
      );
    } else {
      maps = await db.query(
        'vocabulary',
        orderBy: 'createdAt DESC',
      );
    }

    return maps.map((m) => VocabularyEntry.fromMap(m)).toList();
  }

  /// 更新指定单词内容
  Future<int> update(VocabularyEntry entry) async {
    final db = await _dbHelper.database;
    if (!db.isOpen || entry.id == null) return -1;
    return await db.update(
      'vocabulary',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  /// 删除指定 ID 的单词
  Future<int> delete(int id) async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return 0;
    return await db.delete(
      'vocabulary',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 清空所有单词
  Future<int> deleteAll() async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return 0;
    return await db.delete('vocabulary');
  }

  /// 获取单词总数
  Future<int> count() async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return 0;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM vocabulary');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 获取所有未导出到 Anki 的单词列表（按创建时间倒序）
  Future<List<VocabularyEntry>> getUnexported() async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return [];
    final List<Map<String, dynamic>> maps = await db.query(
      'vocabulary',
      where: 'exportedToAnki = 0',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => VocabularyEntry.fromMap(m)).toList();
  }

  /// 标记指定 ID 的单词为已导出
  Future<int> markAsExported(int id) async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return 0;
    return await db.update(
      'vocabulary',
      {'exportedToAnki': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批量标记单词为已导出
  Future<int> markAllAsExported(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await _dbHelper.database;
    if (!db.isOpen) return 0;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(
        'vocabulary',
        {'exportedToAnki': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    final results = await batch.commit(noResult: false);
    return results.length;
  }

  /// 重置所有单词的导出状态为未导出
  Future<int> resetExportStatus() async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return 0;
    return await db.update(
      'vocabulary',
      {'exportedToAnki': 0},
    );
  }

  /// 获取未导出的单词数量
  Future<int> unexportedCount() async {
    final db = await _dbHelper.database;
    if (!db.isOpen) return 0;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM vocabulary WHERE exportedToAnki = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
