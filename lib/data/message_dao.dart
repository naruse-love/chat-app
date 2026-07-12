import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/chat_message.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

class MessageDao {
  final DatabaseHelper _dbHelper;
  final Future<Directory> Function()? _supportDirResolver;

  MessageDao(this._dbHelper, {this._supportDirResolver});

  Future<String> _getSupportDirPath() async {
    final resolver = _supportDirResolver;
    if (resolver != null) {
      final dir = await resolver();
      return dir.path;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    } catch (_) {
      // Fallback in unit tests where bindings/plugins are not initialized
      return '/dummy_support_dir';
    }
  }

  Future<String?> _toAbsolutePath(String? storedPath) async {
    if (storedPath == null || storedPath.isEmpty || storedPath.startsWith('data:')) {
      return storedPath;
    }
    if (p.isAbsolute(storedPath)) {
      return storedPath;
    }
    final supportPath = await _getSupportDirPath();
    if (storedPath.startsWith(supportPath)) {
      return p.normalize(storedPath);
    }
    return p.normalize(p.join(supportPath, storedPath));
  }

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

    // Translate absolute path to relative path relative to support directory
    if (message.imagePath != null && !message.imagePath!.startsWith('data:')) {
      final supportPath = await _getSupportDirPath();
      final imagePathStr = message.imagePath!;
      if (imagePathStr.startsWith(supportPath)) {
        String relativePath = imagePathStr.substring(supportPath.length);
        if (relativePath.startsWith('/') || relativePath.startsWith('\\')) {
          relativePath = relativePath.substring(1);
        }
        // Store with forward slashes for cross-platform DB consistency
        relativePath = relativePath.replaceAll('\\', '/');
        map['imagePath'] = relativePath;
      }
    }

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
    if (map['imagePath'] != null) {
      map['imagePath'] = await _toAbsolutePath(map['imagePath'] as String);
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

    final List<ChatMessage> messages = [];
    for (final m in maps) {
      final map = Map<String, dynamic>.from(m);
      if (map['toolCalls'] != null && map['toolCalls'] is String) {
        map['toolCalls'] = jsonDecode(map['toolCalls'] as String);
      }
      if (map['imagePath'] != null) {
        map['imagePath'] = await _toAbsolutePath(map['imagePath'] as String);
      }
      messages.add(ChatMessage.fromJson(map));
    }
    return messages;
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
