import 'dart:convert';
import '../models/chat_message.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class MessageDao {
  final DatabaseHelper _dbHelper;

  MessageDao(this._dbHelper);

  Future<void> insert(ChatMessage message) async {
    final db = await _dbHelper.database;
    final map = message.toJson();

    // Serialize toolCalls to JSON string if present
    if (message.toolCalls != null) {
      map['toolCalls'] = jsonEncode(message.toolCalls!.map((e) => e.toJson()).toList());
    } else {
      map['toolCalls'] = null;
    }

    // Convert DateTime to ISO8601 string
    map['timestamp'] = message.timestamp.toIso8601String();

    await db.insert(
      'messages',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ChatMessage?> getById(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;

    final map = Map<String, dynamic>.from(maps.first);
    if (map['toolCalls'] != null && map['toolCalls'] is String) {
      map['toolCalls'] = jsonDecode(map['toolCalls'] as String);
    }
    return ChatMessage.fromJson(map);
  }

  Future<List<ChatMessage>> getMessagesForConversation(String conversationId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((m) {
      final map = Map<String, dynamic>.from(m);
      if (map['toolCalls'] != null && map['toolCalls'] is String) {
        map['toolCalls'] = jsonDecode(map['toolCalls'] as String);
      }
      return ChatMessage.fromJson(map);
    }).toList();
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearConversation(String conversationId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
    );
  }
}
