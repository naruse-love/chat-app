import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../models/mcp/mcp_transport_type.dart';
import 'mcp_transport.dart';

typedef WebSocketConnector = Future<dynamic> Function(
  String url, {
  Map<String, dynamic>? headers,
});

/// 基于全双工 WebSocket 的 MCP 传输通道实现
class WebSocketMcpTransport implements McpTransport {
  final Uri uri;
  final Map<String, dynamic>? headers;
  final WebSocketConnector? customConnector;

  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  final StreamController<McpConnectionStatus> _statusController =
      StreamController<McpConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  dynamic _webSocket;
  StreamSubscription? _subscription;
  bool _isClosed = false;

  WebSocketMcpTransport({
    required this.uri,
    this.headers,
    this.customConnector,
  });

  @override
  McpTransportType get transportType => McpTransportType.websocket;

  @override
  McpConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == McpConnectionStatus.connected;

  @override
  Stream<McpConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  void _setStatus(McpConnectionStatus newStatus) {
    if (_status != newStatus && !_isClosed) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  @override
  Future<void> connect() async {
    if (_isClosed) {
      throw StateError('Cannot connect a closed WebSocketMcpTransport');
    }
    if (_status == McpConnectionStatus.connected ||
        _status == McpConnectionStatus.connecting) {
      return;
    }

    _setStatus(McpConnectionStatus.connecting);

    try {
      final connector = customConnector;
      if (connector != null) {
        _webSocket = await connector(
          uri.toString(),
          headers: headers,
        );
      } else {
        _webSocket = await WebSocket.connect(
          uri.toString(),
          headers: headers,
        );
      }

      _setStatus(McpConnectionStatus.connected);

      _subscription = (_webSocket as Stream).listen(
        (data) {
          try {
            String text;
            if (data is String) {
              text = data;
            } else if (data is List<int>) {
              text = utf8.decode(data);
            } else {
              text = data.toString();
            }

            final decoded = jsonDecode(text);
            if (decoded is Map<String, dynamic>) {
              _messageController.add(decoded);
            }
          } catch (_) {
            // 忽略非 JSON 帧
          }
        },
        onError: (error) {
          _setStatus(McpConnectionStatus.error);
        },
        onDone: () {
          if (!_isClosed) {
            _setStatus(McpConnectionStatus.disconnected);
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      _setStatus(McpConnectionStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_isClosed) {
      throw StateError('WebSocketMcpTransport is closed');
    }
    if (_status != McpConnectionStatus.connected || _webSocket == null) {
      throw StateError('WebSocketMcpTransport is not connected');
    }

    final jsonString = jsonEncode(message);
    _webSocket.add(jsonString);
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _setStatus(McpConnectionStatus.disconnected);
    _isClosed = true;

    await _subscription?.cancel();
    _subscription = null;

    try {
      await _webSocket?.close();
    } catch (_) {}
    _webSocket = null;

    await _statusController.close();
    await _messageController.close();
  }
}
