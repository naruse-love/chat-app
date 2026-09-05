import 'dart:async';
import 'dart:convert';
import 'package:chat/models/mcp/mcp_tool_info.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/services/mcp/mcp_client.dart';
import 'package:chat/services/mcp/mcp_dynamic_tool.dart';
import 'package:chat/services/mcp/transports/mcp_transport.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockMcpTransport implements McpTransport {
  McpConnectionStatus _status = McpConnectionStatus.connected;
  final StreamController<McpConnectionStatus> _statusController =
      StreamController<McpConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<Map<String, dynamic>> sentMessages = [];

  @override
  McpTransportType get transportType => McpTransportType.stdio;

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
    _status = McpConnectionStatus.connected;
    _statusController.add(_status);
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    sentMessages.add(message);
  }

  void receiveFromServer(Map<String, dynamic> message) {
    _messageController.add(message);
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
  group('McpDynamicTool Deep & Adversarial Tests', () {
    late _MockMcpTransport transport;
    late McpClient client;

    setUp(() {
      transport = _MockMcpTransport();
      client = McpClient(transport: transport);
    });

    tearDown(() async {
      await client.close();
    });

    test('generates sanitized OpenAI-compatible namespaced name', () {
      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 'srv-local@123',
        serverName: 'Local Server',
        toolInfo: const McpToolInfo(
          name: 'query:database_record',
          description: 'Query database records',
        ),
      );

      expect(dynamicTool.name, 'mcp_srv_local_123_query_database_record');
      expect(dynamicTool.originalToolName, 'query:database_record');
      expect(dynamicTool.displayName, '[MCP: Local Server] query:database_record');
      expect(dynamicTool.description, 'Query database records (MCP服务: Local Server)');
      expect(dynamicTool.securityLevel, ToolSecurityLevel.readOnly);
    });

    test('truncates name exceeding 64 characters safely for OpenAI compatibility', () {
      final longServerId = 'server_${'a' * 40}';
      final longToolName = 'tool_${'b' * 40}';

      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: longServerId,
        serverName: 'Long Server',
        toolInfo: McpToolInfo(name: longToolName),
      );

      expect(dynamicTool.name.length, lessThanOrEqualTo(64));
      expect(dynamicTool.name.startsWith('mcp_'), isTrue);
    });

    test('correctly parses JSON Schema properties into ToolParameters with fallbacks', () {
      const toolInfo = McpToolInfo(
        name: 'complex_search',
        description: 'Multi-criteria search',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Search keyword',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max results',
              'default': 10,
            },
            'score': {
              'type': 'number',
              'description': 'Min threshold score',
            },
            'include_drafts': {
              'type': 'boolean',
              'description': 'Include draft records',
            },
            'tags': {
              'type': 'array',
              'description': 'Filter tags',
              'items': {'type': 'string'}
            },
            'status': {
              'type': 'string',
              'description': 'Item status',
              'enum': ['active', 'archived', 'pending']
            },
            'raw_fallback': 'non_map_property_definition',
          },
          'required': ['query', 'status']
        },
      );

      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 's1',
        serverName: 'S1',
        toolInfo: toolInfo,
      );

      expect(dynamicTool.parameters.length, 7);

      final queryParam = dynamicTool.parameters.firstWhere((p) => p.name == 'query');
      expect(queryParam.type, 'string');
      expect(queryParam.required, isTrue);

      final limitParam = dynamicTool.parameters.firstWhere((p) => p.name == 'limit');
      expect(limitParam.type, 'integer');
      expect(limitParam.required, isFalse);
      expect(limitParam.defaultValue, 10);

      final tagsParam = dynamicTool.parameters.firstWhere((p) => p.name == 'tags');
      expect(tagsParam.type, 'array');
      expect(tagsParam.arrayItemType, 'string');

      final statusParam = dynamicTool.parameters.firstWhere((p) => p.name == 'status');
      expect(statusParam.enumValues, ['active', 'archived', 'pending']);
      expect(statusParam.required, isTrue);

      final fallbackParam = dynamicTool.parameters.firstWhere((p) => p.name == 'raw_fallback');
      expect(fallbackParam.type, 'string');
    });

    test('toOpenAiSchema exports valid function schema structure with fallbacks', () {
      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 'srv1',
        serverName: 'Server1',
        toolInfo: const McpToolInfo(
          name: 'get_weather',
          description: 'Get weather forecast',
          inputSchema: {
            'type': 'object',
            'properties': {
              'city': {'type': 'string', 'description': 'City name'}
            },
            'required': ['city']
          },
        ),
      );

      final schema = dynamicTool.toOpenAiSchema();
      expect(schema['type'], 'function');
      expect(schema['function']['name'], 'mcp_srv1_get_weather');
      expect(schema['function']['description'], contains('Get weather forecast'));
      expect(schema['function']['parameters']['properties']['city']['type'], 'string');
      expect(schema['function']['parameters']['required'], ['city']);
    });

    test('validateArguments validates missing required fields, types, and enum values', () {
      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 'srv1',
        serverName: 'Server1',
        toolInfo: const McpToolInfo(
          name: 'set_mode',
          inputSchema: {
            'type': 'object',
            'properties': {
              'mode': {
                'type': 'string',
                'description': 'Operation mode',
                'enum': ['fast', 'accurate']
              }
            },
            'required': ['mode']
          },
        ),
      );

      // Missing required parameter
      expect(dynamicTool.validateArguments({}), contains("缺少必需参数 'mode'"));

      // Invalid enum value
      expect(
        dynamicTool.validateArguments({'mode': 'unknown'}),
        contains("不在允许的枚举范围"),
      );

      // Valid parameter
      expect(dynamicTool.validateArguments({'mode': 'fast'}), isNull);

      // Ignores context args prefixed with __
      expect(
        dynamicTool.validateArguments({'mode': 'accurate', '__context': 123}),
        isNull,
      );
    });

    test('execute dispatches tool call and converts success result with context parameter filtering', () async {
      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 's1',
        serverName: 'Test Server',
        toolInfo: const McpToolInfo(
          name: 'fetch_data',
          description: 'Fetch data by id',
          inputSchema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': 'Item ID'}
            },
            'required': ['id']
          },
        ),
      );

      final execFuture = dynamicTool.execute({'id': 'item-99', '__systemContext': 'hidden'});

      // Check message sent to MCP transport
      expect(transport.sentMessages.length, 1);
      final sent = transport.sentMessages.first;
      expect(sent['method'], 'tools/call');
      expect(sent['params']['name'], 'fetch_data'); // Original tool name
      expect(sent['params']['arguments']['id'], 'item-99');
      expect(sent['params']['arguments'].containsKey('__systemContext'), isFalse); // Stripped

      // Server responds with content
      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {
          'content': [
            {'type': 'text', 'text': '{"id": "item-99", "status": "active"}'}
          ],
          'isError': false,
        },
      });

      final result = await execFuture;
      expect(result.success, isTrue);
      expect(result.toolName, 'mcp_s1_fetch_data');
      expect(result.content, contains('"item-99"'));
      expect(result.metadata?['serverId'], 's1');
      expect(result.metadata?['originalToolName'], 'fetch_data');
    });

    test('execute converts error MCP tool result to ToolExecutionResult.failure', () async {
      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 's1',
        serverName: 'Test Server',
        toolInfo: const McpToolInfo(
          name: 'delete_resource',
          description: 'Delete resource',
        ),
      );

      final execFuture = dynamicTool.execute({'target': '/protected/dir'});

      final sent = transport.sentMessages.first;
      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {
          'content': [
            {'type': 'text', 'text': 'Permission denied: Cannot delete protected resource'}
          ],
          'isError': true,
        },
      });

      final result = await execFuture;
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Permission denied'));
      expect(result.content, contains('Permission denied'));
    });

    test('execute catches exceptions gracefully into ToolExecutionResult.failure', () async {
      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 's1',
        serverName: 'Test Server',
        toolInfo: const McpToolInfo(name: 'broken_tool'),
      );

      await client.close(); // Close client to force callTool to throw

      final result = await dynamicTool.execute({});
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('MCP 工具'));
    });

    test('integrates seamlessly with ToolRegistry and dynamically handles lifecycle', () async {
      final registry = ToolRegistry();

      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 'srv1',
        serverName: 'Remote Srv',
        toolInfo: const McpToolInfo(
          name: 'ping_remote',
          description: 'Ping remote host',
          inputSchema: {
            'type': 'object',
            'properties': {
              'host': {'type': 'string', 'description': 'Target host'}
            },
            'required': ['host']
          },
        ),
      );

      // Register dynamic tool
      registry.register(dynamicTool);
      expect(registry.hasTool(dynamicTool.name), isTrue);
      expect(registry.getTool(dynamicTool.name), dynamicTool);

      // Verify schema export
      final schemas = registry.exportOpenAiSchemas();
      expect(schemas.length, 1);
      expect(schemas.first['function']['name'], dynamicTool.name);

      // Dispatch execution via ToolRegistry
      final execFuture = registry.execute(
        dynamicTool.name,
        {'host': 'example.com'},
        context: {'sessionId': 'sess_123'},
      );

      expect(transport.sentMessages.length, 1);
      final sent = transport.sentMessages.first;
      expect(sent['params']['name'], 'ping_remote');
      expect(sent['params']['arguments']['host'], 'example.com');

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {
          'content': [
            {'type': 'text', 'text': 'Ping example.com: 24ms'}
          ],
          'isError': false,
        },
      });

      final execResult = await execFuture;
      expect(execResult.success, isTrue);
      expect(execResult.content, 'Ping example.com: 24ms');

      // Unregister dynamic tool on disconnection
      final removed = registry.unregister(dynamicTool.name);
      expect(removed, isTrue);
      expect(registry.hasTool(dynamicTool.name), isFalse);
    });

    test('filters CancelToken and context framework parameters from MCP arguments safely', () async {
      final registry = ToolRegistry();
      final dynamicTool = McpDynamicTool(
        client: client,
        serverId: 'srv-remote',
        serverName: 'Remote Server',
        toolInfo: const McpToolInfo(
          name: 'query_db',
          description: 'Query database',
          inputSchema: {
            'type': 'object',
            'properties': {
              'sql': {'type': 'string'},
            },
            'required': ['sql'],
          },
        ),
      );
      registry.register(dynamicTool);

      final cancelToken = CancelToken();
      final execFuture = registry.execute(
        dynamicTool.name,
        {'sql': 'SELECT * FROM users;'},
        context: {
          'cancelToken': cancelToken,
          '__cancelToken': cancelToken,
          'searxngUrl': 'http://localhost:8888',
          'searchBackend': 'searxng',
          'sessionId': 'session-xyz',
        },
      );

      expect(transport.sentMessages.length, 1);
      final sent = transport.sentMessages.first;
      expect(sent['params']['name'], 'query_db');
      final sentArgs = sent['params']['arguments'] as Map<String, dynamic>;
      expect(sentArgs['sql'], 'SELECT * FROM users;');
      // CancelToken and internal context keys must not be present in arguments
      expect(sentArgs.containsKey('cancelToken'), isFalse);
      expect(sentArgs.containsKey('__cancelToken'), isFalse);
      expect(sentArgs.containsKey('searxngUrl'), isFalse);
      expect(sentArgs.containsKey('searchBackend'), isFalse);

      // Verify that json.encode succeeds without throwing "Converting object to an encodable object failed"
      final encoded = json.encode(sent);
      expect(encoded, isNotEmpty);
      expect(encoded, isNot(contains('CancelToken')));

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {
          'content': [
            {'type': 'text', 'text': 'Found 3 records'}
          ],
        },
      });

      final res = await execFuture;
      expect(res.success, isTrue);
      expect(res.content, 'Found 3 records');
    });
  });
}
