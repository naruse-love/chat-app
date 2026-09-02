import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/mcp/mcp_transport_type.dart';
import 'mcp_transport.dart';

/// 基于 Streamable HTTP / MCP over HTTP 的传输通道实现
/// 符合 Model Context Protocol 官方 HTTP 规范 (支持 POST /mcp、JSON-RPC 及可选 SSE 流式响应与 Session 保持)
class HttpMcpTransport implements McpTransport {
  final Uri uri;
  final Map<String, String>? headers;
  final Dio _dio;

  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  final StreamController<McpConnectionStatus> _statusController =
      StreamController<McpConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  CancelToken? _cancelToken;
  String? _sessionId;
  bool _isClosed = false;

  HttpMcpTransport({
    required this.uri,
    this.headers,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  @override
  McpTransportType get transportType => McpTransportType.http;

  @override
  McpConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == McpConnectionStatus.connected;

  @override
  Stream<McpConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// 获取当前协商维护的 Session ID (如果有)
  String? get sessionId => _sessionId;

  void _setStatus(McpConnectionStatus newStatus) {
    if (_status != newStatus && !_isClosed) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  @override
  Future<void> connect() async {
    if (_isClosed) {
      throw StateError('Cannot connect a closed HttpMcpTransport');
    }
    if (_status == McpConnectionStatus.connected) {
      return;
    }

    _setStatus(McpConnectionStatus.connecting);
    _cancelToken = CancelToken();

    try {
      // Streamable HTTP 端点为标准 HTTP POST 接口，标记为 connected 准备发送消息
      _setStatus(McpConnectionStatus.connected);
    } catch (e) {
      _setStatus(McpConnectionStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_isClosed) {
      throw StateError('HttpMcpTransport is closed');
    }
    if (_status != McpConnectionStatus.connected) {
      throw StateError('HttpMcpTransport is not connected');
    }

    final postHeaders = <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': '2024-11-05',
      if (_sessionId != null) 'Mcp-Session-Id': _sessionId!,
      if (headers != null) ...headers!,
    };

    try {
      final response = await _dio.post(
        uri.toString(),
        data: message,
        options: Options(
          headers: postHeaders,
          responseType: ResponseType.plain, // 允许灵活处理纯文本/JSON/SSE
          validateStatus: (status) => status != null && status < 500, // 接收 4xx 里的 JSON-RPC 错误
        ),
        cancelToken: _cancelToken,
      );

      // 提取服务端可能返回的 Session ID
      final sessionHeader = response.headers.value('mcp-session-id') ??
          response.headers.value('Mcp-Session-Id');
      if (sessionHeader != null && sessionHeader.isNotEmpty) {
        _sessionId = sessionHeader;
      }

      final data = response.data;
      if (data == null || data.toString().trim().isEmpty) {
        return;
      }

      final bodyStr = data.toString().trim();

      // 1. 尝试直接作为 JSON-RPC 响应解析
      if (bodyStr.startsWith('{') || bodyStr.startsWith('[')) {
        try {
          final decoded = jsonDecode(bodyStr);
          if (decoded is Map<String, dynamic>) {
            _messageController.add(decoded);
            return;
          } else if (decoded is List) {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                _messageController.add(item);
              }
            }
            return;
          }
        } catch (_) {}
      }

      // 2. 如果返回的是 SSE 格式 (event: ... / data: ...)
      if (bodyStr.contains('data:')) {
        for (final line in bodyStr.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('data:')) {
            final jsonStr = trimmed.substring(5).trim();
            if (jsonStr.isNotEmpty && (jsonStr.startsWith('{') || jsonStr.startsWith('['))) {
              try {
                final decoded = jsonDecode(jsonStr);
                if (decoded is Map<String, dynamic>) {
                  _messageController.add(decoded);
                } else if (decoded is List) {
                  for (final item in decoded) {
                    if (item is Map<String, dynamic>) {
                      _messageController.add(item);
                    }
                  }
                }
              } catch (_) {}
            }
          }
        }
      }
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        _setStatus(McpConnectionStatus.error);
      }
      rethrow;
    } catch (e) {
      _setStatus(McpConnectionStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _setStatus(McpConnectionStatus.disconnected);
    _isClosed = true;

    _cancelToken?.cancel('Transport closed');
    await _statusController.close();
    await _messageController.close();
  }
}
