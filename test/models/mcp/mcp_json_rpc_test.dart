import 'package:chat/models/mcp/mcp_json_rpc.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('McpTransportType & McpConnectionStatus Enums', () {
    test('McpTransportType properties and parsing', () {
      expect(McpTransportType.stdio.nameString, 'stdio');
      expect(McpTransportType.sse.nameString, 'sse');
      expect(McpTransportType.websocket.nameString, 'websocket');

      expect(McpTransportType.stdio.displayName, contains('Stdio'));
      expect(McpTransportType.sse.displayName, contains('SSE'));
      expect(McpTransportType.websocket.displayName, contains('WebSocket'));

      expect(McpTransportTypeExtension.fromString('stdio'), McpTransportType.stdio);
      expect(McpTransportTypeExtension.fromString('sse'), McpTransportType.sse);
      expect(McpTransportTypeExtension.fromString('websocket'), McpTransportType.websocket);
      expect(McpTransportTypeExtension.fromString('ws'), McpTransportType.websocket);
      expect(McpTransportTypeExtension.fromString('other'), McpTransportType.stdio);
    });

    test('McpConnectionStatus display names', () {
      expect(McpConnectionStatus.disconnected.displayName, '未连接');
      expect(McpConnectionStatus.connecting.displayName, '连接中...');
      expect(McpConnectionStatus.connected.displayName, '已连接');
      expect(McpConnectionStatus.error.displayName, '连接异常');
    });
  });

  group('JsonRpcError Model Tests', () {
    test('standard error constants have correct JSON-RPC 2.0 codes', () {
      expect(JsonRpcError.parseError, -32700);
      expect(JsonRpcError.invalidRequest, -32600);
      expect(JsonRpcError.methodNotFound, -32601);
      expect(JsonRpcError.invalidParams, -32602);
      expect(JsonRpcError.internalError, -32603);
    });

    test('fromCode factory constructs default messages correctly', () {
      final parseErr = JsonRpcError.fromCode(JsonRpcError.parseError);
      expect(parseErr.code, -32700);
      expect(parseErr.message, 'Parse error');

      final notFoundErr = JsonRpcError.fromCode(JsonRpcError.methodNotFound, 'Custom not found');
      expect(notFoundErr.code, -32601);
      expect(notFoundErr.message, 'Custom not found');

      final invalidParamsErr = JsonRpcError.fromCode(JsonRpcError.invalidParams);
      expect(invalidParamsErr.code, -32602);
      expect(invalidParamsErr.message, 'Invalid params');
    });

    test('toJson and fromJson round-trip with data', () {
      const error = JsonRpcError(
        code: -32602,
        message: 'Invalid parameters provided',
        data: {'param': 'foo', 'expected': 'string'},
      );

      final json = error.toJson();
      expect(json['code'], -32602);
      expect(json['message'], 'Invalid parameters provided');
      expect(json['data']['param'], 'foo');

      final reconstructed = JsonRpcError.fromJson(json);
      expect(reconstructed.code, -32602);
      expect(reconstructed.message, 'Invalid parameters provided');
      expect(reconstructed.data['expected'], 'string');
      expect(reconstructed.toString(), contains('-32602'));
    });

    test('JsonRpcException encapsulates error', () {
      const error = JsonRpcError(
        code: JsonRpcError.internalError,
        message: 'Database failure',
        data: {'detail': 'timeout'},
      );
      const exception = JsonRpcException(error);

      expect(exception.code, -32603);
      expect(exception.message, 'Database failure');
      expect(exception.data, {'detail': 'timeout'});
      expect(exception.toString(), contains('Database failure'));
    });
  });

  group('JsonRpcRequest Model Tests', () {
    test('toJson and fromJson round-trip', () {
      const request = JsonRpcRequest(
        id: 42,
        method: 'tools/call',
        params: {'name': 'calculator', 'arguments': {'x': 10, 'y': 20}},
      );

      final json = request.toJson();
      expect(json['jsonrpc'], '2.0');
      expect(json['id'], 42);
      expect(json['method'], 'tools/call');
      expect(json['params']['name'], 'calculator');

      final reconstructed = JsonRpcRequest.fromJson(json);
      expect(reconstructed.jsonrpc, '2.0');
      expect(reconstructed.id, 42);
      expect(reconstructed.method, 'tools/call');
      expect(reconstructed.params['name'], 'calculator');
      expect(reconstructed.toString(), contains('tools/call'));
    });

    test('handles String ID and null params', () {
      const request = JsonRpcRequest(
        id: 'uuid-12345',
        method: 'ping',
      );

      final json = request.toJson();
      expect(json['id'], 'uuid-12345');
      expect(json.containsKey('params'), isFalse);

      final reconstructed = JsonRpcRequest.fromJson(json);
      expect(reconstructed.id, 'uuid-12345');
      expect(reconstructed.params, isNull);
    });
  });

  group('JsonRpcResponse Model Tests', () {
    test('success response toJson and fromJson', () {
      final response = JsonRpcResponse.success(
        id: 1,
        result: {'tools': ['tool1', 'tool2']},
      );

      expect(response.isSuccess, isTrue);
      expect(response.isError, isFalse);

      final json = response.toJson();
      expect(json['jsonrpc'], '2.0');
      expect(json['id'], 1);
      expect(json['result']['tools'], ['tool1', 'tool2']);
      expect(json.containsKey('error'), isFalse);

      final reconstructed = JsonRpcResponse.fromJson(json);
      expect(reconstructed.isSuccess, isTrue);
      expect(reconstructed.result['tools'], ['tool1', 'tool2']);
    });

    test('failure response toJson and fromJson', () {
      final response = JsonRpcResponse.failure(
        id: 2,
        error: const JsonRpcError(
          code: JsonRpcError.methodNotFound,
          message: 'Unknown method: foo',
        ),
      );

      expect(response.isSuccess, isFalse);
      expect(response.isError, isTrue);

      final json = response.toJson();
      expect(json['id'], 2);
      expect(json['error']['code'], -32601);
      expect(json['error']['message'], 'Unknown method: foo');

      final reconstructed = JsonRpcResponse.fromJson(json);
      expect(reconstructed.isError, isTrue);
      expect(reconstructed.error?.code, -32601);
      expect(reconstructed.error?.message, 'Unknown method: foo');
    });
  });

  group('JsonRpcNotification Model Tests', () {
    test('toJson and fromJson round-trip', () {
      const notification = JsonRpcNotification(
        method: 'notifications/initialized',
        params: {'clientInfo': {'name': 'flutter-chat', 'version': '1.0.0'}},
      );

      final json = notification.toJson();
      expect(json['jsonrpc'], '2.0');
      expect(json['method'], 'notifications/initialized');
      expect(json.containsKey('id'), isFalse);
      expect(json['params']['clientInfo']['name'], 'flutter-chat');

      final reconstructed = JsonRpcNotification.fromJson(json);
      expect(reconstructed.method, 'notifications/initialized');
      expect(reconstructed.params['clientInfo']['version'], '1.0.0');
      expect(reconstructed.toString(), contains('notifications/initialized'));
    });
  });
}
