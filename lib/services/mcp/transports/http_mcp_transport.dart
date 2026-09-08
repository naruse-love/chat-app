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
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
                sendTimeout: const Duration(seconds: 30),
              ),
            );

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

    final safeMessage = _deepSanitizeForJson(message) as Map<String, dynamic>;

    try {
      final response = await _dio.post(
        uri.toString(),
        data: safeMessage,
        options: Options(
          headers: postHeaders,
          contentType: 'application/json',
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
      if (data != null) {
        if (data is Map<String, dynamic>) {
          if (_isJsonRpcMessage(data)) {
            _messageController.add(data);
          }
        } else if (data is List) {
          for (final item in data) {
            if (item is Map<String, dynamic> && _isJsonRpcMessage(item)) {
              _messageController.add(item);
            }
          }
        } else {
          _dispatchMessagePayload(data.toString(), _messageController);
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

  /// 验证是否为合法的 JSON-RPC 2.0 消息（过滤仅表示 HTTP 状态确认的 {'ok': true} 等非 RPC 响应）
  static bool _isJsonRpcMessage(Map<String, dynamic> map) {
    return map.containsKey('jsonrpc') ||
        (map.containsKey('id') && (map.containsKey('result') || map.containsKey('error') || map.containsKey('method')));
  }

  /// 通用 JSON-RPC 及标准 SSE 消息分发解析器 (支持直接 JSON 对象/数组，以及以空行分隔的标准 SSE 事件块)
  static void _dispatchMessagePayload(
    String rawBody,
    StreamController<Map<String, dynamic>> controller,
  ) {
    final body = rawBody.trim();
    if (body.isEmpty) return;

    // 1. 直接作为 JSON-RPC 对象或数组解析
    if (body.startsWith('{') || body.startsWith('[')) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          if (_isJsonRpcMessage(decoded)) {
            controller.add(decoded);
          }
          return;
        } else if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic> && _isJsonRpcMessage(item)) {
              controller.add(item);
            }
          }
          return;
        }
      } catch (_) {}
    }

    // 2. 标准 SSE 格式块解析 (事件块以双换行 \n\n 或 \r\n\r\n 分隔，支持多行 data:)
    final blocks = body.split(RegExp(r'\r?\n\r?\n'));
    for (final block in blocks) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) continue;

      final dataLines = <String>[];
      for (final line in trimmedBlock.split(RegExp(r'\r?\n'))) {
        final trimmedLine = line.trim();
        if (trimmedLine.startsWith('data:')) {
          dataLines.add(trimmedLine.substring(5).trimLeft());
        }
      }

      if (dataLines.isNotEmpty) {
        final joined = dataLines.join('\n').trim();
        bool decodedSuccess = false;
        if (joined.isNotEmpty && (joined.startsWith('{') || joined.startsWith('['))) {
          try {
            final decoded = jsonDecode(joined);
            if (decoded is Map<String, dynamic>) {
              if (_isJsonRpcMessage(decoded)) {
                controller.add(decoded);
              }
              decodedSuccess = true;
            } else if (decoded is List) {
              for (final item in decoded) {
                if (item is Map<String, dynamic> && _isJsonRpcMessage(item)) {
                  controller.add(item);
                }
              }
              decodedSuccess = true;
            }
          } catch (_) {}
        }

        // 容错：若合并多行解析失败，可能是非标服务端按单换行分隔了多个独立 JSON 消息
        if (!decodedSuccess && dataLines.length > 1) {
          for (final singleLine in dataLines) {
            final lineTrimmed = singleLine.trim();
            if (lineTrimmed.startsWith('{') || lineTrimmed.startsWith('[')) {
              try {
                final decoded = jsonDecode(lineTrimmed);
                if (decoded is Map<String, dynamic> && _isJsonRpcMessage(decoded)) {
                  controller.add(decoded);
                } else if (decoded is List) {
                  for (final item in decoded) {
                    if (item is Map<String, dynamic> && _isJsonRpcMessage(item)) {
                      controller.add(item);
                    }
                  }
                }
              } catch (_) {}
            }
          }
        }
      }
    }
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
