import 'dart:async';
import 'package:chat/models/mcp/mcp_json_rpc.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/services/mcp/json_rpc_engine.dart';
import 'package:chat/services/mcp/transports/mcp_transport.dart';
import 'package:flutter_test/flutter_test.dart';

// In-Memory Mock Transport for testing JsonRpcEngine
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
  group('JsonRpcEngine Deep & Adversarial Tests', () {
    late _MockMcpTransport transport;
    late JsonRpcEngine engine;

    setUp(() {
      transport = _MockMcpTransport();
      engine = JsonRpcEngine(transport: transport);
    });

    tearDown(() async {
      await engine.close();
      await transport.close();
    });

    test('sendRequest successfully returns result when response is received', () async {
      final requestFuture = engine.sendRequest('tools/list', {'cursor': 'c1'});

      expect(transport.sentMessages.length, 1);
      final sent = transport.sentMessages.first;
      expect(sent['jsonrpc'], '2.0');
      expect(sent['id'], 1);
      expect(sent['method'], 'tools/list');
      expect(sent['params'], {'cursor': 'c1'});

      // Simulate server response
      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'tools': [
            {'name': 'query_db', 'description': 'Query database'}
          ]
        },
      });

      final result = await requestFuture;
      expect(result['tools'], isList);
      expect(result['tools'].first['name'], 'query_db');
      expect(engine.pendingRequestCount, 0);
    });

    test('handles concurrent requests with out-of-order responses correctly', () async {
      final f1 = engine.sendRequest('method_1');
      final f2 = engine.sendRequest('method_2');
      final f3 = engine.sendRequest('method_3');
      final f4 = engine.sendRequest('method_4');

      expect(transport.sentMessages.length, 4);
      expect(engine.pendingRequestCount, 4);

      // Server responds out of order: 3 -> 1 -> 4 -> 2
      transport.receiveFromServer({'jsonrpc': '2.0', 'id': 3, 'result': 'res_3'});
      transport.receiveFromServer({'jsonrpc': '2.0', 'id': 1, 'result': 'res_1'});
      transport.receiveFromServer({'jsonrpc': '2.0', 'id': 4, 'result': 'res_4'});
      transport.receiveFromServer({'jsonrpc': '2.0', 'id': 2, 'result': 'res_2'});

      final results = await Future.wait([f1, f2, f3, f4]);
      expect(results[0], 'res_1');
      expect(results[1], 'res_2');
      expect(results[2], 'res_3');
      expect(results[3], 'res_4');
      expect(engine.pendingRequestCount, 0);
    });

    test('times out and safely ignores late response without throwing unhandled exceptions', () async {
      final requestFuture = engine.sendRequest(
        'slow_method',
        null,
        const Duration(milliseconds: 40),
      );

      await expectLater(
        requestFuture,
        throwsA(isA<TimeoutException>()),
      );

      expect(engine.pendingRequestCount, 0);

      // Server response arrives late after timeout
      expect(
        () => transport.receiveFromServer({'jsonrpc': '2.0', 'id': 1, 'result': 'late_data'}),
        returnsNormally,
      );
    });

    test('maps all standard JSON-RPC 2.0 error codes to JsonRpcException correctly', () async {
      final errorCodes = [
        JsonRpcError.parseError, // -32700
        JsonRpcError.invalidRequest, // -32600
        JsonRpcError.methodNotFound, // -32601
        JsonRpcError.invalidParams, // -32602
        JsonRpcError.internalError, // -32603
        -32000, // Custom server error
      ];

      for (final code in errorCodes) {
        final reqFuture = engine.sendRequest('test_code_$code');
        final reqId = transport.sentMessages.last['id'];

        transport.receiveFromServer({
          'jsonrpc': '2.0',
          'id': reqId,
          'error': {
            'code': code,
            'message': 'Error description for code $code',
            'data': {'debugInfo': 'test_data_$code'},
          },
        });

        await expectLater(
          reqFuture,
          throwsA(
            isA<JsonRpcException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.message, 'message', contains('Error description for code $code'))
                .having((e) => e.data?['debugInfo'], 'debugInfo', 'test_data_$code'),
          ),
        );
      }
    });

    test('sendNotification sends JSON-RPC notification with no pending completers', () async {
      await engine.sendNotification('notifications/initialized', {'status': 'ready'});

      expect(transport.sentMessages.length, 1);
      final sent = transport.sentMessages.first;
      expect(sent['jsonrpc'], '2.0');
      expect(sent['method'], 'notifications/initialized');
      expect(sent['params'], {'status': 'ready'});
      expect(sent.containsKey('id'), isFalse);
      expect(engine.pendingRequestCount, 0);
    });

    test('receives server notifications on notificationStream', () async {
      final notifications = <JsonRpcNotification>[];
      final sub = engine.notificationStream.listen(notifications.add);

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'method': 'notifications/tools/list_changed',
      });

      await Future.delayed(const Duration(milliseconds: 20));

      expect(notifications.length, 1);
      expect(notifications.first.method, 'notifications/tools/list_changed');
      expect(notifications.first.params, isNull);

      await sub.cancel();
    });

    test('receives server requests on requestStream and sends success/error responses', () async {
      final serverRequests = <JsonRpcRequest>[];
      final sub = engine.requestStream.listen(serverRequests.add);

      transport.receiveFromServer({
        'jsonrpc': '2.0',
        'id': 'srv-req-1',
        'method': 'roots/list',
      });

      await Future.delayed(const Duration(milliseconds: 20));

      expect(serverRequests.length, 1);
      expect(serverRequests.first.id, 'srv-req-1');
      expect(serverRequests.first.method, 'roots/list');

      // 1. Client responds to server request with success
      await engine.sendResponse('srv-req-1', {'roots': ['/workspace']});
      expect(transport.sentMessages.length, 1);
      expect(transport.sentMessages.first['id'], 'srv-req-1');
      expect(transport.sentMessages.first['result']['roots'], ['/workspace']);

      // 2. Client responds to server request with error
      await engine.sendError(
        'srv-req-2',
        const JsonRpcError(code: JsonRpcError.invalidParams, message: 'Invalid root path'),
      );
      expect(transport.sentMessages.length, 2);
      expect(transport.sentMessages.last['id'], 'srv-req-2');
      expect(transport.sentMessages.last['error']['code'], -32602);

      await sub.cancel();
    });

    test('transport disconnection fails all pending requests immediately', () async {
      final req1 = engine.sendRequest('m1');
      final req2 = engine.sendRequest('m2');

      expect(engine.pendingRequestCount, 2);

      final exp1 = expectLater(
        req1,
        throwsA(
          isA<JsonRpcException>()
              .having((e) => e.code, 'code', JsonRpcError.internalError)
              .having((e) => e.message, 'message', contains('disconnected')),
        ),
      );

      final exp2 = expectLater(
        req2,
        throwsA(isA<JsonRpcException>()),
      );

      // Disconnect transport
      transport.setStatus(McpConnectionStatus.disconnected);

      await Future.wait([exp1, exp2]);
      expect(engine.pendingRequestCount, 0);
    });

    test('closing engine fails all pending requests and prevents new operations', () async {
      final req = engine.sendRequest('long_operation');

      final exp = expectLater(
        req,
        throwsA(isA<JsonRpcException>()),
      );

      await engine.close();
      await exp;

      expect(() => engine.sendRequest('new_op'), throwsStateError);
      expect(() => engine.sendNotification('new_notify'), throwsStateError);
      expect(() => engine.sendResponse(1, 'res'), throwsStateError);
      expect(() => engine.sendError(1, const JsonRpcError(code: -1, message: 'e')), throwsStateError);
    });

    test('guards: sending when transport is disconnected throws StateError', () {
      transport.setStatus(McpConnectionStatus.disconnected);

      expect(() => engine.sendRequest('req'), throwsStateError);
      expect(() => engine.sendNotification('notif'), throwsStateError);
      expect(() => engine.sendResponse(1, {}), throwsStateError);
      expect(() => engine.sendError(1, const JsonRpcError(code: -1, message: 'err')), throwsStateError);
    });
  });
}
