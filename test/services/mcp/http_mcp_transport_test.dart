import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/services/mcp/transports/http_mcp_transport.dart';
import 'package:chat/services/mcp/transports/sse_mcp_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// 自定义 Mock Adapter 用于精准拦截 Dio 请求
class _MockDioAdapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(RequestOptions options) onPost;
  final ResponseBody Function(RequestOptions options)? onGet;

  _MockDioAdapter({required this.onPost, this.onGet});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST') {
      final result = onPost(options);
      final statusCode = result['statusCode'] as int? ?? 200;
      final body = result['body'] as String? ?? '';
      final headers = (result['headers'] as Map<String, List<String>>?) ?? {
        'content-type': ['application/json'],
      };

      return ResponseBody.fromString(
        body,
        statusCode,
        headers: headers,
      );
    } else if (options.method == 'GET' && onGet != null) {
      return onGet!(options);
    }

    return ResponseBody.fromString('Not Found', 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('HttpMcpTransport Tests', () {
    test('Connect and send JSON-RPC message with JSON response', () async {
      final uri = Uri.parse('http://10.0.0.103:8338/mcp');
      final dio = Dio();

      dio.httpClientAdapter = _MockDioAdapter(
        onPost: (options) {
          expect(options.path, 'http://10.0.0.103:8338/mcp');
          expect(options.headers['Content-Type'], 'application/json');
          expect(options.headers['MCP-Protocol-Version'], '2024-11-05');

          final data = options.data as Map<String, dynamic>;
          if (data['method'] == 'initialize') {
            return {
              'statusCode': 200,
              'headers': {
                'content-type': ['application/json'],
                'mcp-session-id': ['sess-test-12345'],
              },
              'body': jsonEncode({
                'jsonrpc': '2.0',
                'id': data['id'],
                'result': {
                  'protocolVersion': '2024-11-05',
                  'capabilities': {'tools': {}},
                  'serverInfo': {'name': 'websearch-mcp', 'version': '1.0.0'}
                }
              }),
            };
          }
          return {'statusCode': 200, 'body': ''};
        },
      );

      final transport = HttpMcpTransport(uri: uri, dio: dio);
      expect(transport.transportType, McpTransportType.http);
      expect(transport.status, McpConnectionStatus.disconnected);

      await transport.connect();
      expect(transport.isConnected, isTrue);
      expect(transport.status, McpConnectionStatus.connected);

      final messageFuture = transport.messageStream.first;
      await transport.send({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {},
      });

      final received = await messageFuture;
      expect(received['id'], 1);
      expect(received['result']['serverInfo']['name'], 'websearch-mcp');
      expect(transport.sessionId, 'sess-test-12345');

      await transport.close();
      expect(transport.isConnected, isFalse);
    });

    test('Handles streamed SSE response from Streamable HTTP POST', () async {
      final uri = Uri.parse('http://10.0.0.103:8338/mcp');
      final dio = Dio();

      dio.httpClientAdapter = _MockDioAdapter(
        onPost: (options) {
          return {
            'statusCode': 200,
            'headers': {
              'content-type': ['text/event-stream'],
            },
            'body': 'event: message\ndata: {"jsonrpc":"2.0","id":2,"result":{"tools":[]}}\n\n',
          };
        },
      );

      final transport = HttpMcpTransport(uri: uri, dio: dio);
      await transport.connect();

      final messageFuture = transport.messageStream.first;
      await transport.send({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      });

      final received = await messageFuture;
      expect(received['id'], 2);
      expect(received['result']['tools'], isEmpty);

      await transport.close();
    });

    test('SseMcpTransport smart fallback when GET returns 400', () async {
      final uri = Uri.parse('http://10.0.0.103:8338/mcp');
      final dio = Dio();

      dio.httpClientAdapter = _MockDioAdapter(
        onGet: (options) {
          return ResponseBody.fromString(
            'Bad Request: Expected POST',
            400,
            headers: {'content-type': ['text/plain']},
          );
        },
        onPost: (options) {
          return {
            'statusCode': 200,
            'body': jsonEncode({
              'jsonrpc': '2.0',
              'id': 99,
              'result': {'status': 'ok'}
            }),
          };
        },
      );

      final sseTransport = SseMcpTransport(uri: uri, dio: dio);
      await sseTransport.connect();
      expect(sseTransport.isConnected, isTrue);

      final messageFuture = sseTransport.messageStream.first;
      await sseTransport.send({
        'jsonrpc': '2.0',
        'id': 99,
        'method': 'ping',
      });

      final received = await messageFuture;
      expect(received['id'], 99);
      expect(received['result']['status'], 'ok');

      await sseTransport.close();
    });
  });
}
