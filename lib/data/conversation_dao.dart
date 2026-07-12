import '../models/conversation.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class ConversationDao {
  final DatabaseHelper _dbHelper;

  ConversationDao(this._dbHelper);

  Future<void> insert(Conversation conversation) async {
    final db = await _dbHelper.database;
    final map = conversation.toJson();
    map['isPinned'] = conversation.isPinned ? 1 : 0;
    map['isArchived'] = conversation.isArchived ? 1 : 0;
    map['createdAt'] = conversation.createdAt.toIso8601String();
    map['updatedAt'] = conversation.updatedAt.toIso8601String();

    await db.insert(
      'conversations',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Conversation?> getById(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;

    final map = Map<String, dynamic>.from(maps.first);
    map['isPinned'] = map['isPinned'] == 1;
    map['isArchived'] = map['isArchived'] == 1;
    return Conversation.fromJson(map);
  }

  Future<List<Conversation>> getAll() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'conversations',
      orderBy: 'isPinned DESC, updatedAt DESC',
    );

    return maps.map((m) {
      final map = Map<String, dynamic>.from(m);
      map['isPinned'] = map['isPinned'] == 1;
      map['isArchived'] = map['isArchived'] == 1;
      return Conversation.fromJson(map);
    }).toList();
  }

  Future<void> update(Conversation conversation) async {
    final db = await _dbHelper.database;
    final map = conversation.toJson();
    map['isPinned'] = conversation.isPinned ? 1 : 0;
    map['isArchived'] = conversation.isArchived ? 1 : 0;
    map['createdAt'] = conversation.createdAt.toIso8601String();
    map['updatedAt'] = conversation.updatedAt.toIso8601String();

    await db.update(
      'conversations',
      map,
      where: 'id = ?',
      whereArgs: [conversation.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
