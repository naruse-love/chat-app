import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/mcp/mcp_transport_type.dart';
import 'mcp_transport.dart';
import 'streamable_post_helper.dart';

/// 基于 HTTP Server-Sent Events (SSE) + POST 的 MCP 传输通道实现
class SseMcpTransport implements McpTransport {
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
  StreamSubscription? _streamSubscription;
  Uri? _postUri;
  String? _sessionId;
  bool _isHttpFallback = false;
  bool _isClosed = false;

  SseMcpTransport({
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
        // HTTP 降级模式的响应流中断：置错误态使挂起请求快速失败
        _setStatus(McpConnectionStatus.error);
      },
    );
  }

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

  /// 获取当前维护的 Session ID (如果有)
  String? get sessionId => _sessionId;

  /// POST 请求的目标 URI（通过 SSE endpoint 事件动态获得，或默认使用基准 URI）
  Uri? get postUri => _postUri;

  /// 是否处于 Streamable HTTP POST 降级模式
  bool get isHttpFallback => _isHttpFallback;

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

    // 智能自愈：如果 URI 路径为 /mcp 端点（Streamable HTTP 规范），
    // 避免未携带 Mcp-Session-Id 发送可能挂起 10+ 秒的 GET 请求，直接降级为 HTTP POST 模式
    if (uri.path.endsWith('/mcp') || uri.path.endsWith('/mcp/') || _isHttpFallback) {
      _isHttpFallback = true;
      _postUri = uri;
      _setStatus(McpConnectionStatus.connected);
      return;
    }

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
      // 智能自愈：若 GET 请求返回 400/405（常见于 Streamable HTTP POST 端点），进入 HTTP 降级模式
      final statusCode = dioErr.response?.statusCode;
      if (statusCode == 400 || statusCode == 405) {
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

    final safeMessage = _deepSanitizeForJson(message) as Map<String, dynamic>;

    try {
      final result = await _postHelper.post(
        uri: _postUri!,
        message: safeMessage,
        headers: headers,
        sessionId: _sessionId,
        cancelToken: _cancelToken,
      );

      // 捕获并维护服务端可能返回的 Session ID
      if (result.sessionId != null) {
        _sessionId = result.sessionId;
      }
    } on McpSessionExpiredException {
      // 会话过期：清除失效 Session ID 并置错误态，由上层重新握手自愈
      _sessionId = null;
      _setStatus(McpConnectionStatus.error);
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
    await _streamSubscription?.cancel();
    _streamSubscription = null;
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
