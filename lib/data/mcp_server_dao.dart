import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/mcp/mcp_server_config.dart';
import '../services/secure_storage_service.dart';
import 'database_helper.dart';

/// MCP Server 数据库访问对象 (DAO)
/// 负责 MCP Server 配置在 SQLite (`mcp_servers` 表) 与 FlutterSecureStorage 中的持久化管理
class McpServerDao {
  final DatabaseHelper _dbHelper;
  final SecureStorageService _secureStorage;

  McpServerDao({
    DatabaseHelper? dbHelper,
    SecureStorageService? secureStorage,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _secureStorage = secureStorage ?? SecureStorageService();

  /// 插入新 MCP Server 配置，并将敏感 headers（若存在）持久化至安全存储
  Future<void> insertServer(McpServerConfig server, {Map<String, String>? headers}) async {
    final effectiveHeaders = headers ?? server.headers;
    String? headersRef = server.headersRef;

    if (effectiveHeaders != null && effectiveHeaders.isNotEmpty) {
      headersRef ??= 'mcp_headers_${server.id}';
      await _secureStorage.write(headersRef, jsonEncode(effectiveHeaders));
    }

    final effectiveServer = server.copyWith(
      headersRef: headersRef,
      headers: effectiveHeaders,
    );

    final db = await _dbHelper.database;
    await db.insert(
      'mcp_servers',
      effectiveServer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 更新已存在的 MCP Server 配置，同步更新安全存储中的请求头
  Future<void> updateServer(McpServerConfig server, {Map<String, String>? headers}) async {
    final effectiveHeaders = headers ?? server.headers;
    String? headersRef = server.headersRef;

    if (effectiveHeaders != null) {
      headersRef ??= 'mcp_headers_${server.id}';
      if (effectiveHeaders.isNotEmpty) {
        await _secureStorage.write(headersRef, jsonEncode(effectiveHeaders));
      } else {
        await _secureStorage.delete(headersRef);
      }
    }

    final effectiveServer = server.copyWith(
      headersRef: headersRef,
      headers: effectiveHeaders,
      updatedAt: DateTime.now(),
    );

    final db = await _dbHelper.database;
    final count = await db.update(
      'mcp_servers',
      effectiveServer.toMap(),
      where: 'id = ?',
      whereArgs: [server.id],
    );

    if (count == 0) {
      // 若不存在则自动插入
      await db.insert(
        'mcp_servers',
        effectiveServer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 删除指定 ID 的 MCP Server 配置并清理其关联的安全存储敏感请求头
  Future<void> deleteServer(String id) async {
    final server = await getServerById(id, loadHeaders: false);
    if (server?.headersRef != null) {
      await _secureStorage.delete(server!.headersRef!);
    }
    // 防御性清理默认 key
    await _secureStorage.delete('mcp_headers_$id');

    final db = await _dbHelper.database;
    await db.delete(
      'mcp_servers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取所有已保存的 MCP Server 配置列表
  Future<List<McpServerConfig>> getAllServers({bool loadHeaders = true}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'mcp_servers',
      orderBy: 'createdAt ASC',
    );

    final result = <McpServerConfig>[];
    for (final map in maps) {
      var config = McpServerConfig.fromMap(map);
      if (loadHeaders && config.headersRef != null && config.headersRef!.isNotEmpty) {
        final headers = await getHeaders(config.headersRef!);
        if (headers != null) {
          config = config.copyWith(headers: headers);
        }
      }
      result.add(config);
    }

    return result;
  }

  /// 根据 ID 查询单个 MCP Server 配置
  Future<McpServerConfig?> getServerById(String id, {bool loadHeaders = true}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'mcp_servers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;

    var config = McpServerConfig.fromMap(maps.first);
    if (loadHeaders && config.headersRef != null && config.headersRef!.isNotEmpty) {
      final headers = await getHeaders(config.headersRef!);
      if (headers != null) {
        config = config.copyWith(headers: headers);
      }
    }
    return config;
  }

  /// 从安全存储读取请求头 Map
  Future<Map<String, String>?> getHeaders(String headersRef) async {
    try {
      final raw = await _secureStorage.read(headersRef);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return null;
  }

  /// 保存请求头至安全存储
  Future<void> saveHeaders(String headersRef, Map<String, String> headers) async {
    await _secureStorage.write(headersRef, jsonEncode(headers));
  }

  /// 从安全存储删除指定请求头
  Future<void> deleteHeaders(String headersRef) async {
    await _secureStorage.delete(headersRef);
  }
}
