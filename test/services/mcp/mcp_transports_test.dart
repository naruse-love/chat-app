import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/services/mcp/transports/sse_mcp_transport.dart';
import 'package:chat/services/mcp/transports/stdio_mcp_transport.dart';
import 'package:chat/services/mcp/transports/websocket_mcp_transport.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Mock WebSocket for testing WebSocketMcpTransport
class _MockWebSocket extends Stream<dynamic> {
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  final List<String> sentMessages = [];
  bool isClosed = false;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  void add(dynamic data) {
    sentMessages.add(data.toString());
  }

  void emitFromServer(dynamic data) {
    _controller.add(data);
  }

  void emitError(dynamic error) {
    _controller.addError(error);
  }

  void emitDone() {
    _controller.close();
  }

  Future<void> close([int? code, String? reason]) async {
    isClosed = true;
    await _controller.close();
  }
}

// Mock Process for StdioMcpTransport
class _MockProcess implements Process {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCodeCompleter = Completer<int>();
  final _MockIOSink _mockStdin = _MockIOSink();
  bool isKilled = false;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  IOSink get stdin => _mockStdin;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  int get pid => 9999;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    isKilled = true;
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    return true;
  }

  void emitStdout(String text) {
    _stdoutController.add(utf8.encode(text));
  }

  void emitStderr(String text) {
    _stderrController.add(utf8.encode(text));
  }

  void completeExit(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
  }

  void closeStreams() {
    _stdoutController.close();
    _stderrController.close();
  }
}

class _MockIOSink implements IOSink {
  final List<String> writtenLines = [];
  bool isFlushed = false;

  @override
  Encoding encoding = utf8;

  @override
  void writeln([Object? obj = '']) {
    writtenLines.add(obj.toString());
  }

  @override
  Future<void> flush() async {
    isFlushed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WebSocketMcpTransport Deep & Adversarial Tests', () {
    late _MockWebSocket mockSocket;
    late WebSocketMcpTransport transport;

    setUp(() {
      mockSocket = _MockWebSocket();
      transport = WebSocketMcpTransport(
        uri: Uri.parse('ws://127.0.0.1:8080/mcp'),
        headers: {'Authorization': 'Bearer test-token'},
        customConnector: (url, {headers}) async {
          return mockSocket;
        },
      );
    });

    tearDown(() async {
      await transport.close();
    });

    test('lifecycle: connect -> send -> receive -> close', () async {
      expect(transport.transportType, McpTransportType.websocket);
      expect(transport.status, McpConnectionStatus.disconnected);
      expect(transport.isConnected, isFalse);

      final statusHistory = <McpConnectionStatus>[];
      final statusSub = transport.statusStream.listen(statusHistory.add);

      await transport.connect();
      await Future.delayed(const Duration(milliseconds: 10));

      expect(transport.status, McpConnectionStatus.connected);
      expect(transport.isConnected, isTrue);
      expect(statusHistory, contains(McpConnectionStatus.connecting));
      expect(statusHistory, contains(McpConnectionStatus.connected));

      // Test sending message
      await transport.send({'jsonrpc': '2.0', 'method': 'ping', 'id': 1});
      expect(mockSocket.sentMessages.length, 1);
      expect(mockSocket.sentMessages.first, contains('"method":"ping"'));

      // Test receiving message
      final receivedMessages = <Map<String, dynamic>>[];
      final msgSub = transport.messageStream.listen(receivedMessages.add);

      mockSocket.emitFromServer('{"jsonrpc":"2.0","id":1,"result":"pong"}');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(receivedMessages.length, 1);
      expect(receivedMessages.first['result'], 'pong');

      // Test binary frames (Uint8List & List<int>)
      mockSocket.emitFromServer(
        utf8.encode('{"jsonrpc":"2.0","method":"notify","params":{"x":1}}'),
      );
      await Future.delayed(const Duration(milliseconds: 20));
      expect(receivedMessages.length, 2);
      expect(receivedMessages.last['method'], 'notify');

      mockSocket.emitFromServer(
        Uint8List.fromList(utf8.encode('{"jsonrpc":"2.0","id":2,"result":"binary_ok"}')),
      );
      await Future.delayed(const Duration(milliseconds: 20));
      expect(receivedMessages.length, 3);
      expect(receivedMessages.last['result'], 'binary_ok');

      await msgSub.cancel();
      await statusSub.cancel();
    });

    test('safely ignores non-JSON text and binary frames', () async {
      await transport.connect();

      final receivedMessages = <Map<String, dynamic>>[];
      final msgSub = transport.messageStream.listen(receivedMessages.add);

      // Non-JSON plain text
      mockSocket.emitFromServer('PING');
      mockSocket.emitFromServer('Hello Server');

      // Non-JSON binary
      mockSocket.emitFromServer(Uint8List.fromList([0x00, 0x01, 0x02, 0xFF]));

      // Valid JSON
      mockSocket.emitFromServer('{"jsonrpc":"2.0","id":99,"result":"valid"}');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(receivedMessages.length, 1);
      expect(receivedMessages.first['id'], 99);

      await msgSub.cancel();
    });

    test('handles socket onError and onDone transitions to error and disconnected', () async {
      await transport.connect();
      expect(transport.isConnected, isTrue);

      // Socket error
      mockSocket.emitError(Exception('Socket drop'));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(transport.status, McpConnectionStatus.error);
      expect(transport.isConnected, isFalse);

      // Create new socket for reconnection test
      final newMockSocket = _MockWebSocket();
      final reconnTransport = WebSocketMcpTransport(
        uri: Uri.parse('ws://127.0.0.1:8080/mcp'),
        customConnector: (url, {headers}) async => newMockSocket,
      );

      await reconnTransport.connect();
      expect(reconnTransport.status, McpConnectionStatus.connected);

      // Socket onDone
      newMockSocket.emitDone();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(reconnTransport.status, McpConnectionStatus.disconnected);

      await reconnTransport.close();
    });

    test('closed state guards and reconnect protection', () async {
      // Connect when already connecting or connected is no-op
      await transport.connect();
      await transport.connect(); // No error, no-op
      expect(transport.isConnected, isTrue);

      await transport.close();
      expect(transport.status, McpConnectionStatus.disconnected);

      // Connect or send on closed transport throws StateError
      expect(() => transport.connect(), throwsStateError);
      expect(() => transport.send({'foo': 'bar'}), throwsStateError);
    });

    test('send when not connected throws StateError', () {
      expect(() => transport.send({'method': 'test'}), throwsStateError);
    });
  });

  group('SseMcpTransport Deep & Adversarial Tests', () {
    late Dio dio;
    late StreamController<Uint8List> sseStreamController;
    late SseMcpTransport transport;
    final List<Map<String, dynamic>> postedRequests = [];
    int statusCodeToReturn = 200;
    bool shouldThrowDioError = false;

    setUp(() {
      dio = Dio();
      sseStreamController = StreamController<Uint8List>.broadcast();
      postedRequests.clear();
      statusCodeToReturn = 200;
      shouldThrowDioError = false;

      // Intercept GET (SSE stream) and POST (outgoing messages)
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (shouldThrowDioError) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: statusCodeToReturn,
                    statusMessage: 'HTTP Error $statusCodeToReturn',
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }

            if (options.method == 'GET') {
              final responseBody = ResponseBody(
                sseStreamController.stream,
                statusCodeToReturn,
                headers: {
                  Headers.contentTypeHeader: ['text/event-stream'],
                },
              );
              return handler.resolve(
                Response(
                  requestOptions: options,
                  data: responseBody,
                  statusCode: statusCodeToReturn,
                ),
              );
            } else if (options.method == 'POST') {
              postedRequests.add(options.data as Map<String, dynamic>);
              return handler.resolve(
                Response(
                  requestOptions: options,
                  data: {'ok': true},
                  statusCode: 202,
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      transport = SseMcpTransport(
        uri: Uri.parse('http://127.0.0.1:8000/sse'),
        headers: {'X-Custom-Auth': 'Bearer test-token'},
        dio: dio,
      );
    });

    tearDown(() async {
      await transport.close();
      await sseStreamController.close();
    });

    test('SSE endpoint discovery, message dispatch, and HTTP POST sending', () async {
      expect(transport.transportType, McpTransportType.sse);
      final messages = <Map<String, dynamic>>[];
      final msgSub = transport.messageStream.listen(messages.add);

      await transport.connect();

      // Emit SSE endpoint event
      sseStreamController.add(
        Uint8List.fromList(
          utf8.encode('event: endpoint\ndata: /messages?session_id=s123\n\n'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 30));

      expect(transport.isConnected, isTrue);
      expect(transport.postUri.toString(), 'http://127.0.0.1:8000/messages?session_id=s123');

      // Send outgoing POST message
      await transport.send({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'});
      expect(postedRequests.length, 1);
      expect(postedRequests.first['method'], 'tools/list');

      // Server emits message event
      sseStreamController.add(
        Uint8List.fromList(
          utf8.encode('event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"tools":[]}}\n\n'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 30));

      expect(messages.length, 1);
      expect(messages.first['id'], 1);

      await msgSub.cancel();
    });

    test('handles cross-chunk fragmented SSE data and comment line filtering', () async {
      final messages = <Map<String, dynamic>>[];
      final msgSub = transport.messageStream.listen(messages.add);

      await transport.connect();

      // Emit comment lines (keepalive/ping)
      sseStreamController.add(
        Uint8List.fromList(utf8.encode(': ping\n: keepalive heartbeat\n\n')),
      );

      // Emit fragmented message across 2 chunks
      const chunk1 = 'event: message\ndata: {"jsonrpc":"2.0","id":42,';
      const chunk2 = '"result":{"answer":"fragmented_ok"}}\n\n';

      sseStreamController.add(Uint8List.fromList(utf8.encode(chunk1)));
      await Future.delayed(const Duration(milliseconds: 20));
      sseStreamController.add(Uint8List.fromList(utf8.encode(chunk2)));
      await Future.delayed(const Duration(milliseconds: 30));

      expect(messages.length, 1);
      expect(messages.first['id'], 42);
      expect(messages.first['result']['answer'], 'fragmented_ok');

      await msgSub.cancel();
    });

    test('falls back to base URI if endpoint event is not received within 500ms', () async {
      await transport.connect();
      expect(transport.status, McpConnectionStatus.connecting);

      // Wait for fallback timer (500ms)
      await Future.delayed(const Duration(milliseconds: 550));

      expect(transport.isConnected, isTrue);
      expect(transport.postUri.toString(), 'http://127.0.0.1:8000/sse');
    });

    test('handles HTTP status errors (401, 403, 404, 500) and sets status to error', () async {
      shouldThrowDioError = true;
      statusCodeToReturn = 401;

      expect(() => transport.connect(), throwsA(isA<DioException>()));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(transport.status, McpConnectionStatus.error);
      expect(transport.isConnected, isFalse);
    });

    test('close cancels stream and prevents subsequent operations', () async {
      await transport.connect();
      await transport.close();

      expect(transport.status, McpConnectionStatus.disconnected);
      expect(() => transport.connect(), throwsStateError);
      expect(() => transport.send({'foo': 'bar'}), throwsStateError);
    });

    test('send when disconnected throws StateError', () {
      expect(() => transport.send({'id': 1}), throwsStateError);
    });
  });

  group('StdioMcpTransport Deep & Adversarial Tests', () {
    late _MockProcess mockProcess;
    late StdioMcpTransport transport;

    setUp(() {
      mockProcess = _MockProcess();
      transport = StdioMcpTransport(
        command: 'mcp-server',
        arguments: ['--stdio'],
        environment: {'DEBUG': '1'},
        workingDirectory: '/tmp',
        processStarter: (exec, args, {environment, includeParentEnvironment = true, mode = ProcessStartMode.normal, runInShell = false, workingDirectory}) async {
          return mockProcess;
        },
      );
    });

    tearDown(() async {
      await transport.close();
    });

    test('Stdio connects, streams stdout JSON lines, and writes to stdin', () async {
      expect(transport.transportType, McpTransportType.stdio);
      expect(transport.status, McpConnectionStatus.disconnected);

      await transport.connect();
      expect(transport.isConnected, isTrue);

      final messages = <Map<String, dynamic>>[];
      final msgSub = transport.messageStream.listen(messages.add);

      // Emit stdout line from child process
      mockProcess.emitStdout('{"jsonrpc":"2.0","id":1,"result":"success"}\n');
      await Future.delayed(const Duration(milliseconds: 30));

      expect(messages.length, 1);
      expect(messages.first['result'], 'success');

      // Send message to process stdin
      await transport.send({'jsonrpc': '2.0', 'method': 'initialize', 'id': 2});
      expect(mockProcess._mockStdin.writtenLines.length, 1);
      expect(mockProcess._mockStdin.writtenLines.first, contains('"method":"initialize"'));
      expect(mockProcess._mockStdin.isFlushed, isTrue);

      await msgSub.cancel();
    });

    test('filters out non-JSON stdout debug log lines safely', () async {
      await transport.connect();

      final messages = <Map<String, dynamic>>[];
      final msgSub = transport.messageStream.listen(messages.add);

      // Child process prints debug and info logs to stdout
      mockProcess.emitStdout('[INFO] MCP Server v1.0.0 starting...\n');
      mockProcess.emitStdout('DEBUG: Loading plugins...\n');
      mockProcess.emitStdout('{"jsonrpc":"2.0","method":"ready"}\n');
      mockProcess.emitStdout('--- separator ---\n');

      // Child process stderr output
      mockProcess.emitStderr('stderr: worker warning\n');

      await Future.delayed(const Duration(milliseconds: 30));

      expect(messages.length, 1);
      expect(messages.first['method'], 'ready');

      await msgSub.cancel();
    });

    test('captures non-zero process exit code and sets status to error', () async {
      await transport.connect();
      expect(transport.isConnected, isTrue);

      // Process crashes with exit code 1
      mockProcess.completeExit(1);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(transport.status, McpConnectionStatus.error);
      expect(transport.isConnected, isFalse);
    });

    test('captures zero process exit code and sets status to disconnected', () async {
      await transport.connect();
      expect(transport.isConnected, isTrue);

      // Process exits normally with exit code 0
      mockProcess.completeExit(0);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(transport.status, McpConnectionStatus.disconnected);
    });

    test('close kills child process and disables subsequent calls', () async {
      await transport.connect();
      await transport.close();

      expect(mockProcess.isKilled, isTrue);
      expect(transport.status, McpConnectionStatus.disconnected);
      expect(() => transport.connect(), throwsStateError);
      expect(() => transport.send({'foo': 'bar'}), throwsStateError);
    });

    test('send when disconnected throws StateError', () {
      expect(() => transport.send({'a': 1}), throwsStateError);
    });
  });
}
