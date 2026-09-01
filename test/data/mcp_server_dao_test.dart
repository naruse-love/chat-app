import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/mcp_server_dao.dart';
import 'package:chat/models/mcp/mcp_server_config.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

class MockFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #write) {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value != null) {
        data[key] = value;
      } else {
        data.remove(key);
      }
      return Future<void>.value();
    }
    if (invocation.memberName == #read) {
      final key = invocation.namedArguments[#key] as String;
      return Future<String?>.value(data[key]);
    }
    if (invocation.memberName == #delete) {
      final key = invocation.namedArguments[#key] as String;
      data.remove(key);
      return Future<void>.value();
    }
    if (invocation.memberName == #deleteAll) {
      data.clear();
      return Future<void>.value();
    }
    if (invocation.memberName == #containsKey) {
      final key = invocation.namedArguments[#key] as String;
      return Future<bool>.value(data.containsKey(key));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseHelper dbHelper;
  late MockFlutterSecureStorage mockSecureStorage;
  late SecureStorageService secureStorageService;
  late McpServerDao dao;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mcp_dao_test_');
    final dbPath = p.join(tempDir.path, 'test_mcp.db');

    db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await DatabaseHelper.instance.testOnCreate(db, version);
      },
      onUpgrade: (db, oldV, newV) async {
        await DatabaseHelper.instance.testOnUpgrade(db, oldV, newV);
      },
    );

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(db);

    mockSecureStorage = MockFlutterSecureStorage();
    secureStorageService = SecureStorageService(storage: mockSecureStorage);
    dao = McpServerDao(dbHelper: dbHelper, secureStorage: secureStorageService);
  });

  tearDown(() async {
    await db.close();
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('McpServerDao CRUD & SecureStorage Deep Tests', () {
    test('Insert and get MCP server without headers', () async {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'stdio_server_1',
        name: 'Local Node MCP',
        transportType: McpTransportType.stdio,
        command: 'node',
        arguments: ['server.js'],
        environment: {'NODE_ENV': 'production'},
        workingDirectory: '/var/app',
        isEnabled: true,
        autoConnect: true,
        defaultSecurityLevel: ToolSecurityLevel.readOnly,
        createdAt: now,
        updatedAt: now,
      );

      await dao.insertServer(config);

      final retrieved = await dao.getServerById('stdio_server_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'stdio_server_1');
      expect(retrieved.name, 'Local Node MCP');
      expect(retrieved.transportType, McpTransportType.stdio);
      expect(retrieved.command, 'node');
      expect(retrieved.arguments, ['server.js']);
      expect(retrieved.environment, {'NODE_ENV': 'production'});
      expect(retrieved.workingDirectory, '/var/app');
      expect(retrieved.isEnabled, isTrue);
      expect(retrieved.autoConnect, isTrue);
      expect(retrieved.defaultSecurityLevel, ToolSecurityLevel.readOnly);
      expect(retrieved.headers, isNull);
      expect(retrieved.headersRef, isNull);
    });

    test('Insert MCP server with headers persists headers in SecureStorage and references key', () async {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'sse_server_1',
        name: 'Remote Auth SSE',
        transportType: McpTransportType.sse,
        url: 'https://mcp.company.com/sse',
        isEnabled: true,
        autoConnect: false,
        defaultSecurityLevel: ToolSecurityLevel.sensitiveConfirm,
        createdAt: now,
        updatedAt: now,
      );

      final headers = {
        'Authorization': 'Bearer secret_jwt_token',
        'X-Tenant-ID': 'tenant_abc',
      };

      await dao.insertServer(config, headers: headers);

      // Verify SecureStorage has the headers JSON
      expect(mockSecureStorage.data.containsKey('mcp_headers_sse_server_1'), isTrue);
      expect(mockSecureStorage.data['mcp_headers_sse_server_1'], contains('secret_jwt_token'));

      // Retrieve via DAO
      final retrieved = await dao.getServerById('sse_server_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.headersRef, 'mcp_headers_sse_server_1');
      expect(retrieved.headers, isNotNull);
      expect(retrieved.headers!['Authorization'], 'Bearer secret_jwt_token');
      expect(retrieved.headers!['X-Tenant-ID'], 'tenant_abc');
    });

    test('Update server metadata and rotate headers in SecureStorage', () async {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'ws_server_1',
        name: 'Initial WebSocket',
        transportType: McpTransportType.websocket,
        url: 'ws://127.0.0.1:8080/ws',
        createdAt: now,
        updatedAt: now,
      );

      await dao.insertServer(config, headers: {'X-Api-Key': 'initial_key'});

      final updatedConfig = config.copyWith(
        name: 'Updated WebSocket Server',
        url: 'wss://127.0.0.1:8443/ws',
        isEnabled: false,
      );

      await dao.updateServer(updatedConfig, headers: {'X-Api-Key': 'rotated_key'});

      final retrieved = await dao.getServerById('ws_server_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Updated WebSocket Server');
      expect(retrieved.url, 'wss://127.0.0.1:8443/ws');
      expect(retrieved.isEnabled, isFalse);
      expect(retrieved.headers!['X-Api-Key'], 'rotated_key');
      expect(mockSecureStorage.data['mcp_headers_ws_server_1'], contains('rotated_key'));
    });

    test('getAllServers retrieves all configured servers in chronological order with headers', () async {
      final now = DateTime.now();
      final s1 = McpServerConfig(
        id: 's1',
        name: 'Server 1',
        transportType: McpTransportType.stdio,
        command: 'p1',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now,
      );
      final s2 = McpServerConfig(
        id: 's2',
        name: 'Server 2',
        transportType: McpTransportType.sse,
        url: 'http://s2/sse',
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now,
      );

      await dao.insertServer(s1);
      await dao.insertServer(s2, headers: {'Auth': 's2_secret'});

      final all = await dao.getAllServers();
      expect(all.length, 2);
      expect(all[0].id, 's1');
      expect(all[0].headers, isNull);
      expect(all[1].id, 's2');
      expect(all[1].headers?['Auth'], 's2_secret');
    });

    test('Delete server removes SQLite record and physically clears SecureStorage headers', () async {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'del_server',
        name: 'To Delete',
        transportType: McpTransportType.sse,
        url: 'http://del/sse',
        createdAt: now,
        updatedAt: now,
      );

      await dao.insertServer(config, headers: {'Token': 'secret_to_delete'});
      expect(mockSecureStorage.data.containsKey('mcp_headers_del_server'), isTrue);

      await dao.deleteServer('del_server');

      final retrieved = await dao.getServerById('del_server');
      expect(retrieved, isNull);
      expect(mockSecureStorage.data.containsKey('mcp_headers_del_server'), isFalse);
    });

    test('Non-existent server getById returns null and delete completes safely', () async {
      final nonExistent = await dao.getServerById('non_existent_id');
      expect(nonExistent, isNull);

      await dao.deleteServer('non_existent_id');
    });

    test('Database schema upgrade from v3 to v4 creates mcp_servers table', () async {
      final upgradeDbPath = p.join(tempDir.path, 'upgrade_v3_to_v4.db');

      // 1. Create DB at v3
      final v3Db = await openDatabase(
        upgradeDbPath,
        version: 3,
        onCreate: (db, version) async {
          await DatabaseHelper.instance.testOnCreate(db, 3);
        },
      );
      await v3Db.close();

      // 2. Open DB at v4 to trigger onUpgrade
      final v4Db = await openDatabase(
        upgradeDbPath,
        version: 4,
        onUpgrade: (db, oldV, newV) async {
          await DatabaseHelper.instance.testOnUpgrade(db, oldV, newV);
        },
      );

      // 3. Verify mcp_servers table exists and can be written
      final now = DateTime.now().toIso8601String();
      await v4Db.insert('mcp_servers', {
        'id': 'upgraded_server',
        'name': 'Upgraded Server',
        'transportType': 'stdio',
        'command': 'python',
        'isEnabled': 1,
        'autoConnect': 1,
        'defaultSecurityLevel': 1,
        'createdAt': now,
        'updatedAt': now,
      });

      final rows = await v4Db.query('mcp_servers', where: 'id = ?', whereArgs: ['upgraded_server']);
      expect(rows.length, 1);
      expect(rows.first['name'], 'Upgraded Server');

      await v4Db.close();
    });
  });
}
