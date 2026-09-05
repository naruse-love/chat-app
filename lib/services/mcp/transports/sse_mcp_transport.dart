import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/mcp/mcp_transport_type.dart';
import 'mcp_transport.dart';

/// 基于 HTTP Server-Sent Events (SSE) + POST 的 MCP 传输通道实现
class SseMcpTransport implements McpTransport {
  final Uri uri;
  final Map<String, String>? headers;
  final Dio _dio;

  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  final StreamController<McpConnectionStatus> _statusController =
      StreamController<McpConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  CancelToken? _cancelToken;
  StreamSubscription? _streamSubscription;
  Uri? _postUri;
  bool _isHttpFallback = false;
  bool _isClosed = false;

  SseMcpTransport({
    required this.uri,
    this.headers,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  @override
  McpTransportType get transportType => McpTransportType.sse;

  @override
  McpConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == McpConnectionStatus.connected;

  @override
  Stream<McpConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// POST 请求的目标 URI（通过 SSE endpoint 事件动态获得，或默认使用基准 URI）
  Uri? get postUri => _postUri;

  void _setStatus(McpConnectionStatus newStatus) {
    if (_status != newStatus && !_isClosed) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  @override
  Future<void> connect() async {
    if (_isClosed) {
      throw StateError('Cannot connect a closed SseMcpTransport');
    }
    if (_status == McpConnectionStatus.connected ||
        _status == McpConnectionStatus.connecting) {
      return;
    }

    _setStatus(McpConnectionStatus.connecting);
    _cancelToken = CancelToken();

    try {
      final requestHeaders = <String, dynamic>{
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        if (headers != null) ...headers!,
      };

      final response = await _dio.get<ResponseBody>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.stream,
          headers: requestHeaders,
        ),
        cancelToken: _cancelToken,
      );

      final responseBody = response.data;
      if (responseBody == null) {
        throw DioException(
          requestOptions: RequestOptions(path: uri.toString()),
          error: 'Empty response body from SSE server',
        );
      }

      String? currentEvent;
      final List<String> currentDataLines = [];

      void flushEvent() {
        if (currentEvent == 'endpoint' ||
            (currentEvent == null &&
                currentDataLines.isNotEmpty &&
                _postUri == null &&
                currentDataLines.first.startsWith('/'))) {
          final data = currentDataLines.join('\n').trim();
          if (data.isNotEmpty) {
            _postUri = uri.resolve(data);
            _setStatus(McpConnectionStatus.connected);
          }
        } else if (currentEvent == 'message' || currentEvent == null) {
          final data = currentDataLines.join('\n').trim();
          if (data.isNotEmpty) {
            try {
              final decoded = jsonDecode(data);
              if (decoded is Map<String, dynamic>) {
                _messageController.add(decoded);
              }
            } catch (_) {
              // 忽略非合法 JSON 格式的心跳或系统行
            }
          }
        }
        currentEvent = null;
        currentDataLines.clear();
      }

      final lineStream = responseBody.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _streamSubscription = lineStream.listen(
        (line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            flushEvent();
          } else if (trimmed.startsWith(':')) {
            // SSE 注释或 Ping 保活，忽略
          } else if (trimmed.startsWith('event:')) {
            currentEvent = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('data:')) {
            currentDataLines.add(trimmed.substring(5).trimLeft());
          }
        },
        onError: (error) {
          _setStatus(McpConnectionStatus.error);
        },
        onDone: () {
          flushEvent();
          if (!_isClosed) {
            _setStatus(McpConnectionStatus.disconnected);
          }
        },
        cancelOnError: true,
      );

      // 如果未收到 endpoint 事件，默认降级为基准 URI 进行 POST
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_postUri == null &&
            _status == McpConnectionStatus.connecting &&
            !_isClosed) {
          _postUri = uri;
          _setStatus(McpConnectionStatus.connected);
        }
      });
    } on DioException catch (dioErr) {
      // 智能自愈：若 GET 请求返回 400/404/405，说明目标端点为 Streamable HTTP POST /mcp 服务端
      final statusCode = dioErr.response?.statusCode;
      if (statusCode == 400 || statusCode == 404 || statusCode == 405) {
        _isHttpFallback = true;
        _postUri = uri;
        _setStatus(McpConnectionStatus.connected);
        return;
      }
      _setStatus(McpConnectionStatus.error);
      rethrow;
    } catch (e) {
      _setStatus(McpConnectionStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_isClosed) {
      throw StateError('SseMcpTransport is closed');
    }
    if (_status != McpConnectionStatus.connected || _postUri == null) {
      throw StateError('SseMcpTransport is not connected');
    }

    final postHeaders = <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': '2024-11-05',
      if (headers != null) ...headers!,
    };

    final safeMessage = _deepSanitizeForJson(message) as Map<String, dynamic>;

    final response = await _dio.post(
      _postUri.toString(),
      data: safeMessage,
      options: Options(
        headers: postHeaders,
        contentType: 'application/json',
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    // 如果处于 Streamable HTTP 降级模式，直接从 POST 响应体中解析消息
    if (_isHttpFallback) {
      final data = response.data;
      if (data != null) {
        final bodyStr = data.toString().trim();
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
      }
    }
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _setStatus(McpConnectionStatus.disconnected);
    _isClosed = true;

    _cancelToken?.cancel('Transport closed');
    await _streamSubscription?.cancel();
    _streamSubscription = null;

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
