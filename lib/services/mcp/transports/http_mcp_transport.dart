import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/mcp/mcp_transport_type.dart';
import 'mcp_transport.dart';
import 'streamable_post_helper.dart';

/// 基于 Streamable HTTP / MCP over HTTP 的传输通道实现
/// 符合 Model Context Protocol 官方 HTTP 规范 (支持 POST /mcp、JSON-RPC 及可选 SSE 流式响应与 Session 保持)
class HttpMcpTransport implements McpTransport {
  final Uri uri;
  final Map<String, String>? headers;
  final Dio _dio;
  late final StreamablePostHelper _postHelper;

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
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
                sendTimeout: const Duration(seconds: 30),
              ),
            ) {
    _postHelper = StreamablePostHelper(
      dio: _dio,
      onMessage: (msg) {
        if (!_messageController.isClosed) {
          _messageController.add(msg);
        }
      },
      onError: (error) {
        // SSE 响应流中断：置错误态使挂起请求快速失败，下次调用时自动重连
        _setStatus(McpConnectionStatus.error);
      },
    );
  }

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

    final safeMessage = _deepSanitizeForJson(message) as Map<String, dynamic>;

    try {
      final result = await _postHelper.post(
        uri: uri,
        message: safeMessage,
        headers: headers,
        sessionId: _sessionId,
        cancelToken: _cancelToken,
      );

      // 维护服务端协商的 Session ID
      if (result.sessionId != null) {
        _sessionId = result.sessionId;
      }
    } on McpSessionExpiredException {
      // 会话过期：清除失效 Session ID 并置错误态，由上层重新握手自愈
      _sessionId = null;
      _setStatus(McpConnectionStatus.error);
      rethrow;
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
    await _postHelper.close();
    await _statusController.close();
    await _messageController.close();
  }

  static dynamic _deepSanitizeForJson(dynamic val) {
    if (val == null || val is num || val is String || val is bool) {
      return val;
    }
    if (val.runtimeType.toString().contains('CancelToken')) {
      return null;
    }
    if (val is List) {
      return val
          .map(_deepSanitizeForJson)
          .where((e) => e != null)
          .toList();
    }
    if (val is Map) {
      final result = <String, dynamic>{};
      for (final entry in val.entries) {
        final k = entry.key.toString();
        if (k.startsWith('__') ||
            k == 'cancelToken' ||
            entry.value.runtimeType.toString().contains('CancelToken')) {
          continue;
        }
        final cleaned = _deepSanitizeForJson(entry.value);
        if (cleaned != null) {
          result[k] = cleaned;
        }
      }
      return result;
    }
    try {
      final enc = jsonEncode(val);
      return jsonDecode(enc);
    } catch (_) {
      return val.toString();
    }
  }
}
