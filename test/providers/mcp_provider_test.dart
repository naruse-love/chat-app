import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/data/database_helper.dart';
import 'package:chat/data/mcp_server_dao.dart';
import 'package:chat/models/mcp/mcp_server_config.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/providers/api_config_provider.dart';
import 'package:chat/providers/mcp_provider.dart';
import 'package:chat/services/mcp/transports/mcp_transport.dart';
import 'package:chat/services/secure_storage_service.dart';
import 'package:chat/services/tool_registry.dart';
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

class FakeMcpTransport implements McpTransport {
  final McpTransportType type;
  final bool shouldFailConnect;
  final bool shouldFailInitialize;

  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  final StreamController<McpConnectionStatus> _statusController =
      StreamController<McpConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<Map<String, dynamic>> sentMessages = [];

  FakeMcpTransport({
    this.type = McpTransportType.stdio,
    this.shouldFailConnect = false,
    this.shouldFailInitialize = false,
  });

  @override
  McpTransportType get transportType => type;

  @override
  McpConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == McpConnectionStatus.connected;

  @override
  Stream<McpConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  Future<void> connect() async {
    if (shouldFailConnect) {
      _status = McpConnectionStatus.error;
      _statusController.add(_status);
      throw StateError('Simulated transport connection failure');
    }
    _status = McpConnectionStatus.connected;
    _statusController.add(_status);
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    sentMessages.add(message);
    final id = message['id'];
    final method = message['method'];

    if (method == 'initialize') {
      if (shouldFailInitialize) {
        _messageController.add({
          'jsonrpc': '2.0',
          'id': id,
          'error': {
            'code': -32603,
            'message': 'Initialization handshake failed',
          },
        });
        return;
      }
      _messageController.add({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': '2024-11-05',
          'capabilities': {
            'tools': {'listChanged': true},
            'resources': {'listChanged': true},
            'prompts': {'listChanged': true},
          },
          'serverInfo': {
            'name': 'mock-server',
            'version': '1.0.0',
          },
        },
      });
    } else if (method == 'tools/list') {
      _messageController.add({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'tools': [
            {
              'name': 'add',
              'description': 'Adds two numbers',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'a': {'type': 'number', 'description': 'first'},
                  'b': {'type': 'number', 'description': 'second'},
                },
                'required': ['a', 'b'],
              },
            },
            {
              'name': 'ping',
              'description': 'Health ping',
              'inputSchema': {'type': 'object', 'properties': {}},
            }
          ],
        },
      });
    } else if (method == 'resources/list') {
      _messageController.add({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'resources': [
            {
              'uri': 'file:///app/config.json',
              'name': 'App Config',
              'mimeType': 'application/json',
            }
          ],
        },
      });
    } else if (method == 'prompts/list') {
      _messageController.add({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'prompts': [
            {
              'name': 'code_review',
              'description': 'Perform code review',
              'arguments': [
                {'name': 'code', 'required': true},
              ],
            }
          ],
        },
      });
    } else if (method == 'tools/call') {
      final params = message['params'] as Map<String, dynamic>? ?? {};
      final toolName = params['name'];
      final args = params['arguments'] as Map<String, dynamic>? ?? {};

      if (toolName == 'add') {
        final a = (args['a'] as num?) ?? 0;
        final b = (args['b'] as num?) ?? 0;
        _messageController.add({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {'type': 'text', 'text': 'Sum: ${a + b}'},
            ],
            'isError': false,
          },
        });
      } else {
        _messageController.add({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {'type': 'text', 'text': 'PONG'},
            ],
            'isError': false,
          },
        });
      }
    }
  }

  void simulateDisconnect() {
    _status = McpConnectionStatus.disconnected;
    _statusController.add(_status);
  }

  @override
  Future<void> close() async {
    _status = McpConnectionStatus.disconnected;
    _statusController.add(_status);
    await _statusController.close();
    await _messageController.close();
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
  late ToolRegistry toolRegistry;
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mcp_provider_test_');
    final dbPath = p.join(tempDir.path, 'test_mcp_provider.db');

    db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await DatabaseHelper.instance.testOnCreate(db, version);
      },
    );

    dbHelper = DatabaseHelper.instance;
    dbHelper.setMockDatabase(db);

    mockSecureStorage = MockFlutterSecureStorage();
    secureStorageService = SecureStorageService(storage: mockSecureStorage);
    dao = McpServerDao(dbHelper: dbHelper, secureStorage: secureStorageService);
    toolRegistry = ToolRegistry();
  });

  tearDown(() async {
    await db.close();
    dbHelper.setMockDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('McpNotifier Lifecycle & ToolRegistry Integration Tests', () {
    test('loadServers loads servers from DAO and auto-connects', () async {
      final now = DateTime.now();
      final config1 = McpServerConfig(
        id: 'server_1',
        name: 'Auto Connected Server',
        transportType: McpTransportType.stdio,
        command: 'python',
        isEnabled: true,
        autoConnect: true,
        createdAt: now,
        updatedAt: now,
      );

      final config2 = McpServerConfig(
        id: 'server_2',
        name: 'Manual Server',
        transportType: McpTransportType.sse,
        url: 'http://localhost:8000/sse',
        isEnabled: true,
        autoConnect: false,
        createdAt: now,
        updatedAt: now,
      );

      await dao.insertServer(config1);
      await dao.insertServer(config2);

      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(),
        autoLoad: false,
      );

      expect(notifier.state.servers, isEmpty);

      await notifier.loadServers();
      // Allow microtask ticks for auto-connect
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.servers.length, 2);

      final s1 = notifier.state.getServerState('server_1');
      final s2 = notifier.state.getServerState('server_2');

      expect(s1?.status, McpConnectionStatus.connected);
      expect(s1?.tools.length, 2);
      expect(s1?.resources.length, 1);
      expect(s1?.prompts.length, 1);

      expect(s2?.status, McpConnectionStatus.disconnected);
      expect(s2?.tools, isEmpty);

      // Verify ToolRegistry has dynamic tools for server_1
      expect(toolRegistry.hasTool('mcp_server_1_add'), isTrue);
      expect(toolRegistry.hasTool('mcp_server_1_ping'), isTrue);

      notifier.dispose();
    });

    test('concurrent multi-server management (SSE + WS + Stdio in parallel)', () async {
      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(type: config.transportType),
        autoLoad: false,
      );

      final now = DateTime.now();
      final sseConfig = McpServerConfig(
        id: 'sse_srv',
        name: 'SSE Server',
        transportType: McpTransportType.sse,
        url: 'https://sse.example.com/events',
        isEnabled: true,
        autoConnect: true,
        createdAt: now,
        updatedAt: now,
      );

      final wsConfig = McpServerConfig(
        id: 'ws_srv',
        name: 'WS Server',
        transportType: McpTransportType.websocket,
        url: 'wss://ws.example.com/socket',
        isEnabled: true,
        autoConnect: true,
        createdAt: now,
        updatedAt: now,
      );

      final stdioConfig = McpServerConfig(
        id: 'stdio_srv',
        name: 'Stdio Server',
        transportType: McpTransportType.stdio,
        command: 'python',
        isEnabled: true,
        autoConnect: true,
        createdAt: now,
        updatedAt: now,
      );

      // Add all 3 servers in parallel
      await Future.wait([
        notifier.addServer(sseConfig),
        notifier.addServer(wsConfig),
        notifier.addServer(stdioConfig),
      ]);

      expect(notifier.state.servers.length, 3);
      expect(notifier.state.isServerConnected('sse_srv'), isTrue);
      expect(notifier.state.isServerConnected('ws_srv'), isTrue);
      expect(notifier.state.isServerConnected('stdio_srv'), isTrue);

      // Verify ToolRegistry registered tools for all 3 servers
      expect(toolRegistry.hasTool('mcp_sse_srv_add'), isTrue);
      expect(toolRegistry.hasTool('mcp_ws_srv_add'), isTrue);
      expect(toolRegistry.hasTool('mcp_stdio_srv_add'), isTrue);

      // Disconnect one server while others remain connected
      await notifier.disconnectServer('ws_srv');
      expect(notifier.state.isServerConnected('ws_srv'), isFalse);
      expect(toolRegistry.hasTool('mcp_ws_srv_add'), isFalse);
      expect(notifier.state.isServerConnected('sse_srv'), isTrue);
      expect(toolRegistry.hasTool('mcp_sse_srv_add'), isTrue);

      notifier.dispose();
    });

    test('addServer inserts config, autoConnects, and registers tools', () async {
      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(),
        autoLoad: false,
      );

      final config = McpServerConfig(
        id: 'dynamic_srv',
        name: 'Dynamic Math Service',
        transportType: McpTransportType.stdio,
        command: 'python',
        isEnabled: true,
        autoConnect: true,
        defaultSecurityLevel: ToolSecurityLevel.safe,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await notifier.addServer(config);

      expect(notifier.state.servers.length, 1);
      final srvState = notifier.state.getServerState('dynamic_srv');
      expect(srvState?.status, McpConnectionStatus.connected);
      expect(srvState?.toolCount, 2);

      // Verify dynamic tool execution through ToolRegistry
      expect(toolRegistry.hasTool('mcp_dynamic_srv_add'), isTrue);
      final execResult = await toolRegistry.execute('mcp_dynamic_srv_add', {'a': 15, 'b': 27});
      expect(execResult.success, isTrue);
      expect(execResult.content, contains('Sum: 42'));

      notifier.dispose();
    });

    test('updateServer reconnects and updates ToolRegistry', () async {
      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(),
        autoLoad: false,
      );

      final initialConfig = McpServerConfig(
        id: 'upd_srv',
        name: 'Old Server',
        transportType: McpTransportType.stdio,
        command: 'cmd',
        isEnabled: true,
        autoConnect: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await notifier.addServer(initialConfig);
      expect(notifier.state.getServerState('upd_srv')?.isConnected, isTrue);
      expect(toolRegistry.hasTool('mcp_upd_srv_add'), isTrue);

      final updatedConfig = initialConfig.copyWith(
        name: 'New Upgraded Server',
        defaultSecurityLevel: ToolSecurityLevel.sensitiveConfirm,
      );

      await notifier.updateServer(updatedConfig);

      final srvState = notifier.state.getServerState('upd_srv');
      expect(srvState?.config.name, 'New Upgraded Server');
      expect(srvState?.isConnected, isTrue);

      final tool = toolRegistry.getTool('mcp_upd_srv_add');
      expect(tool, isNotNull);
      expect(tool!.securityLevel, ToolSecurityLevel.sensitiveConfirm);

      notifier.dispose();
    });

    test('deleteServer disconnects, unregisters tools, and removes from DAO', () async {
      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(),
        autoLoad: false,
      );

      final config = McpServerConfig(
        id: 'del_srv',
        name: 'Delete Me',
        transportType: McpTransportType.stdio,
        command: 'sh',
        isEnabled: true,
        autoConnect: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await notifier.addServer(config);
      expect(toolRegistry.hasTool('mcp_del_srv_add'), isTrue);

      await notifier.deleteServer('del_srv');

      expect(notifier.state.servers, isEmpty);
      expect(toolRegistry.hasTool('mcp_del_srv_add'), isFalse);
      expect(await dao.getServerById('del_srv'), isNull);

      notifier.dispose();
    });

    test('toggleServerEnabled disables server, disconnects and removes tools', () async {
      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(),
        autoLoad: false,
      );

      final config = McpServerConfig(
        id: 'toggle_srv',
        name: 'Toggle Server',
        transportType: McpTransportType.stdio,
        command: 'node',
        isEnabled: true,
        autoConnect: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await notifier.addServer(config);
      expect(notifier.state.isServerConnected('toggle_srv'), isTrue);
      expect(toolRegistry.hasTool('mcp_toggle_srv_add'), isTrue);

      // Disable
      await notifier.toggleServerEnabled('toggle_srv', false);
      expect(notifier.state.isServerConnected('toggle_srv'), isFalse);
      expect(notifier.state.getServerState('toggle_srv')?.config.isEnabled, isFalse);
      expect(toolRegistry.hasTool('mcp_toggle_srv_add'), isFalse);

      // Enable again
      await notifier.toggleServerEnabled('toggle_srv', true);
      expect(notifier.state.isServerConnected('toggle_srv'), isTrue);
      expect(notifier.state.getServerState('toggle_srv')?.config.isEnabled, isTrue);
      expect(toolRegistry.hasTool('mcp_toggle_srv_add'), isTrue);

      notifier.dispose();
    });

    test('Transport disconnect stream event automatically updates state and cleans ToolRegistry', () async {
      late FakeMcpTransport activeTransport;

      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) {
          activeTransport = FakeMcpTransport();
          return activeTransport;
        },
        autoLoad: false,
      );

      final config = McpServerConfig(
        id: 'stream_drop_srv',
        name: 'Unstable Network Server',
        transportType: McpTransportType.sse,
        url: 'http://unstable/sse',
        isEnabled: true,
        autoConnect: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await notifier.addServer(config);
      expect(notifier.state.isServerConnected('stream_drop_srv'), isTrue);
      expect(toolRegistry.hasTool('mcp_stream_drop_srv_add'), isTrue);

      // Simulate network socket drop
      activeTransport.simulateDisconnect();
      await Future.delayed(const Duration(milliseconds: 30));

      expect(notifier.state.isServerConnected('stream_drop_srv'), isFalse);
      expect(notifier.state.getServerState('stream_drop_srv')?.status, McpConnectionStatus.disconnected);
      expect(toolRegistry.hasTool('mcp_stream_drop_srv_add'), isFalse);

      notifier.dispose();
    });

    test('Connection failure updates status to error and cleans up', () async {
      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(shouldFailConnect: true),
        autoLoad: false,
      );

      final config = McpServerConfig(
        id: 'failing_srv',
        name: 'Broken Server',
        transportType: McpTransportType.stdio,
        command: 'invalid_cmd',
        isEnabled: true,
        autoConnect: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await notifier.addServer(config);
      await notifier.connectServer('failing_srv');

      final srvState = notifier.state.getServerState('failing_srv');
      expect(srvState?.status, McpConnectionStatus.error);
      expect(srvState?.hasError, isTrue);
      expect(srvState?.errorMessage, contains('Simulated transport connection failure'));
      expect(toolRegistry.hasTool('mcp_failing_srv_add'), isFalse);

      notifier.dispose();
    });

    test('testConnection runs temporary check without mutating state', () async {
      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(),
        autoLoad: false,
      );

      final config = McpServerConfig(
        id: 'test_probe',
        name: 'Probe Server',
        transportType: McpTransportType.sse,
        url: 'http://probe/sse',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final probeState = await notifier.testConnection(config);
      expect(probeState.status, McpConnectionStatus.connected);
      expect(probeState.toolCount, 2);
      expect(probeState.resourceCount, 1);
      expect(probeState.promptCount, 1);

      // Verify persistent state was not altered
      expect(notifier.state.servers, isEmpty);
      expect(toolRegistry.getAllTools(), isEmpty);

      notifier.dispose();
    });

    test('StateNotifier mounted check avoids post-dispose exceptions', () async {
      final notifier = McpNotifier(
        dao: dao,
        secureStorage: secureStorageService,
        toolRegistry: toolRegistry,
        transportFactory: (config) => FakeMcpTransport(),
        autoLoad: false,
      );

      final config = McpServerConfig(
        id: 'mount_test_srv',
        name: 'Mount Test',
        transportType: McpTransportType.stdio,
        command: 'echo',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await dao.insertServer(config);

      final loadFuture = notifier.loadServers();
      notifier.dispose(); // Dispose immediately while async operation is pending

      await expectLater(loadFuture, completes);
    });

    test('Riverpod ProviderContainer integration test', () async {
      final container = ProviderContainer(
        overrides: [
          dbHelperProvider.overrideWithValue(dbHelper),
          secureStorageServiceProvider.overrideWithValue(secureStorageService),
          toolRegistryProvider.overrideWithValue(toolRegistry),
        ],
      );

      final daoFromContainer = container.read(mcpServerDaoProvider);
      expect(daoFromContainer, isNotNull);

      final mcpState = container.read(mcpProvider);
      expect(mcpState.servers, isEmpty);

      container.dispose();
    });
  });
}
