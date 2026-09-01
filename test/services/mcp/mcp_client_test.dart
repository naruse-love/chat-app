import 'dart:async';
import 'package:chat/models/mcp/mcp_json_rpc.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/services/mcp/mcp_client.dart';
import 'package:chat/services/mcp/transports/mcp_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockMcpTransport implements McpTransport {
  McpConnectionStatus _status = McpConnectionStatus.connected;
  final StreamController<McpConnectionStatus> _statusController =
      StreamController<McpConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<Map<String, dynamic>> sentMessages = [];
  bool connectCalled = false;

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
    connectCalled = true;
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

  void setStatus(McpConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
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
  group('McpClient Deep & Adversarial Tests', () {
    late _MockMcpTransport transport;
    late McpClient client;

    setUp(() {
      transport = _MockMcpTransport();
      client = McpClient(
        transport: transport,
        defaultTimeout: const Duration(seconds: 5),
      );
    });

    tearDown(() async {
      await client.close();
    });

    test('initialize performs handshake and sends notifications/initialized', () async {
      final initFuture = client.initialize();

      // Verify initialize request was sent
      expect(transport.sentMessages.length, 1);
      final initMsg = transport.sentMessages.first;
      expect(initMsg['method'], 'initialize');
      expect(initMsg['params']['protocolVersion'], '2024-11-05');
      expect(initMsg['params']['capabilities'], isNotNull);
      expect(initMsg['params']['clientInfo']['name'], 'chat-app');

      final reqId = initMsg['id'];

      // Simulate server initialize response
      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': reqId,
        'result': {
          'protocolVersion': '2024-11-05',
          'capabilities': {
            'tools': {'listChanged': true},
            'resources': {'subscribe': true},
            'prompts': {'listChanged': false},
          },
          'serverInfo': {
            'name': 'test-mcp-server',
            'version': '1.2.0',
          },
          'instructions': 'Test server instructions',
        },
      });

      final result = await initFuture;

      expect(result.protocolVersion, '2024-11-05');
      expect(result.serverInfo.name, 'test-mcp-server');
      expect(result.serverInfo.version, '1.2.0');
      expect(result.capabilities.supportsTools, isTrue);
      expect(result.capabilities.supportsResources, isTrue);
      expect(result.instructions, 'Test server instructions');

      // Verify initialized notification was sent
      expect(transport.sentMessages.length, 2);
      final notifyMsg = transport.sentMessages[1];
      expect(notifyMsg['method'], 'notifications/initialized');
      expect(notifyMsg.containsKey('id'), isFalse);

      expect(client.isInitialized, isTrue);
      expect(client.initResult, isNotNull);
    });

    test('initialize auto-connects transport if not connected', () async {
      transport.setStatus(McpConnectionStatus.disconnected);
      expect(transport.connectCalled, isFalse);

      final initFuture = client.initialize();
      await Future.delayed(const Duration(milliseconds: 10));
      expect(transport.connectCalled, isTrue);

      final initMsg = transport.sentMessages.first;
      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': initMsg['id'],
        'result': {
          'protocolVersion': '2024-11-05',
          'capabilities': {},
          'serverInfo': {'name': 'auto-connected-server'},
        },
      });

      final result = await initFuture;
      expect(result.serverInfo.name, 'auto-connected-server');
      expect(client.isInitialized, isTrue);
    });

    test('ping sends ping request and returns true on success', () async {
      final pingFuture = client.ping();

      expect(transport.sentMessages.length, 1);
      final sent = transport.sentMessages.first;
      expect(sent['method'], 'ping');

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {},
      });

      final success = await pingFuture;
      expect(success, isTrue);
    });

    test('ping returns false when transport is disconnected or fails', () async {
      transport.setStatus(McpConnectionStatus.disconnected);
      final success = await client.ping();
      expect(success, isFalse);
    });

    test('listTools retrieves and deserializes tool info list', () async {
      final listFuture = client.listTools(cursor: 'cur_page_2');

      expect(transport.sentMessages.length, 1);
      final sent = transport.sentMessages.first;
      expect(sent['method'], 'tools/list');
      expect(sent['params']['cursor'], 'cur_page_2');

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {
          'tools': [
            {
              'name': 'calculator',
              'description': 'Performs math calculations',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'expr': {'type': 'string', 'description': 'Math expression'}
                },
                'required': ['expr']
              }
            },
            {
              'name': 'fetch_page',
              'description': 'Fetches URL content',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'url': {'type': 'string', 'description': 'Target URL'}
                },
                'required': ['url']
              }
            }
          ]
        },
      });

      final tools = await listFuture;
      expect(tools.length, 2);
      expect(tools[0].name, 'calculator');
      expect(tools[0].description, 'Performs math calculations');
      expect(tools[0].inputSchema['type'], 'object');
      expect(tools[1].name, 'fetch_page');
    });

    test('listTools handles empty tools response gracefully', () async {
      final listFuture = client.listTools();
      final sent = transport.sentMessages.first;

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {'tools': []},
      });

      final tools = await listFuture;
      expect(tools, isEmpty);
    });

    test('callTool sends tools/call and parses multimodal content blocks', () async {
      final callFuture = client.callTool('calculator', {'expr': '12 * 12'});

      expect(transport.sentMessages.length, 1);
      final sent = transport.sentMessages.first;
      expect(sent['method'], 'tools/call');
      expect(sent['params']['name'], 'calculator');
      expect(sent['params']['arguments'], {'expr': '12 * 12'});

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {
          'content': [
            {'type': 'text', 'text': '144'},
            {
              'type': 'image',
              'data': 'iVBORw0KGgoAAAANSUhEUg==',
              'mimeType': 'image/png'
            },
            {
              'type': 'resource',
              'uri': 'file:///result.txt',
              'text': 'Result file content'
            }
          ],
          'isError': false,
        },
      });

      final result = await callFuture;
      expect(result.isError, isFalse);
      expect(result.content.length, 3);
      expect(result.content[0].type, 'text');
      expect(result.content[0].text, '144');
      expect(result.content[1].type, 'image');
      expect(result.content[2].type, 'resource');
      expect(result.toDisplayText(), contains('144'));
      expect(result.toDisplayText(), contains('image/png'));
      expect(result.toDisplayText(), contains('Result file content'));
    });

    test('callTool returns error result when server responds with isError: true', () async {
      final callFuture = client.callTool('failing_tool', {});

      final sent = transport.sentMessages.first;
      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'result': {
          'content': [
            {'type': 'text', 'text': 'Database connection timeout'}
          ],
          'isError': true,
        },
      });

      final result = await callFuture;
      expect(result.isError, isTrue);
      expect(result.toDisplayText(), 'Database connection timeout');
    });

    test('callTool gracefully converts JSON-RPC exception into error result', () async {
      final callFuture = client.callTool('unknown_tool', {});

      final sent = transport.sentMessages.first;
      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': sent['id'],
        'error': {
          'code': JsonRpcError.methodNotFound,
          'message': 'Tool unknown_tool not found',
        },
      });

      final result = await callFuture;
      expect(result.isError, isTrue);
      expect(result.toDisplayText(), contains('MCP JSON-RPC 调用失败 (-32601)'));
    });

    test('callTool handles timeout into friendly error result', () async {
      final callFuture = client.callTool(
        'very_slow_tool',
        {},
        timeout: const Duration(milliseconds: 30),
      );

      final result = await callFuture;
      expect(result.isError, isTrue);
      expect(result.toDisplayText(), contains('MCP 工具调用超时'));
    });

    test('listResources and readResource retrieve resource descriptors and contents', () async {
      // 1. listResources
      final listFuture = client.listResources();
      final listSent = transport.sentMessages.last;
      expect(listSent['method'], 'resources/list');

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': listSent['id'],
        'result': {
          'resources': [
            {
              'uri': 'file:///logs/app.log',
              'name': 'App Log',
              'description': 'Application execution log',
              'mimeType': 'text/plain',
              'size': 1024,
            }
          ]
        },
      });

      final resources = await listFuture;
      expect(resources.length, 1);
      expect(resources.first.uri, 'file:///logs/app.log');
      expect(resources.first.name, 'App Log');
      expect(resources.first.size, 1024);

      // 2. readResource
      final readFuture = client.readResource('file:///logs/app.log');
      final readSent = transport.sentMessages.last;
      expect(readSent['method'], 'resources/read');
      expect(readSent['params']['uri'], 'file:///logs/app.log');

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': readSent['id'],
        'result': {
          'contents': [
            {
              'uri': 'file:///logs/app.log',
              'mimeType': 'text/plain',
              'text': '[INFO] Server started successfully',
            }
          ]
        },
      });

      final contents = await readFuture;
      expect(contents.length, 1);
      expect(contents.first.text, '[INFO] Server started successfully');
    });

    test('listPrompts and getPrompt retrieve prompts and template messages', () async {
      // 1. listPrompts
      final listFuture = client.listPrompts();
      final listSent = transport.sentMessages.last;
      expect(listSent['method'], 'prompts/list');

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': listSent['id'],
        'result': {
          'prompts': [
            {
              'name': 'code_review',
              'description': 'Perform a code review',
              'arguments': [
                {'name': 'code', 'description': 'Source code', 'required': true}
              ]
            }
          ]
        },
      });

      final prompts = await listFuture;
      expect(prompts.length, 1);
      expect(prompts.first.name, 'code_review');
      expect(prompts.first.arguments.length, 1);
      expect(prompts.first.arguments.first.required, isTrue);

      // 2. getPrompt
      final getFuture = client.getPrompt('code_review', {'code': 'print("hello")'});
      final getSent = transport.sentMessages.last;
      expect(getSent['method'], 'prompts/get');
      expect(getSent['params']['name'], 'code_review');
      expect(getSent['params']['arguments']['code'], 'print("hello")');

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': getSent['id'],
        'result': {
          'description': 'Review code prompt',
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': 'Please review: print("hello")'}
            }
          ]
        },
      });

      final promptData = await getFuture;
      expect(promptData['description'], 'Review code prompt');
      expect(promptData['messages'], isList);
    });

    test('close marks client disposed and rejects subsequent calls', () async {
      await client.close();
      expect(client.isDisposed, isTrue);
      expect(client.isInitialized, isFalse);

      expect(() => client.initialize(), throwsStateError);
      expect(() => client.ping(), throwsStateError);
      expect(() => client.listTools(), throwsStateError);
      expect(() => client.callTool('a', {}), throwsStateError);
      expect(() => client.listResources(), throwsStateError);
      expect(() => client.readResource('uri'), throwsStateError);
      expect(() => client.listPrompts(), throwsStateError);
      expect(() => client.getPrompt('p'), throwsStateError);
    });
  });
}
