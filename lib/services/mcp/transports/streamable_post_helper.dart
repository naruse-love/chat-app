import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

/// Streamable HTTP POST 会话过期异常
/// 服务端返回 404 且请求携带了 Mcp-Session-Id 时抛出，表示会话已失效需要重新握手
class McpSessionExpiredException implements Exception {
  final String? sessionId;

  const McpSessionExpiredException({this.sessionId});

  @override
  String toString() =>
      'MCP 会话已过期 (Session ID: ${sessionId ?? "unknown"})，需要重新初始化握手';
}

/// Streamable HTTP POST 响应处理结果
class StreamablePostResult {
  /// 从响应头提取的 Session ID（如果服务端返回）
  final String? sessionId;

  /// 是否为 SSE 流式响应（流仍在后台解析中）
  final bool isStream;

  const StreamablePostResult({this.sessionId, required this.isStream});
}

/// Streamable HTTP POST 公共辅助器
/// 封装 MCP Streamable HTTP 规范的 POST 请求处理：
/// - 收到响应头即返回（不等完整响应体），彻底规避服务端保持 SSE 流开启导致的挂起
/// - 按 Content-Type 分流：SSE 流式增量解析 / JSON 完整解析
/// - 自动提取并维护 Mcp-Session-Id
/// - 404 会话过期检测
class StreamablePostHelper {
  final Dio _dio;
  final void Function(Map<String, dynamic> message) _onMessage;
  final void Function(Object error) _onError;

  /// 活跃的 SSE 流订阅（每个 POST 响应流一个）
  final Set<StreamSubscription<String>> _streamSubscriptions = {};

  StreamablePostHelper({
    required Dio dio,
    required void Function(Map<String, dynamic> message) onMessage,
    required void Function(Object error) onError,
  })  : _dio = dio, // ignore: prefer_initializing_formals
        _onMessage = onMessage, // ignore: prefer_initializing_formals
        _onError = onError; // ignore: prefer_initializing_formals

  /// 当前活跃的流订阅数量（测试与诊断用）
  int get activeStreamCount => _streamSubscriptions.length;

  /// 发送 Streamable HTTP POST 请求并处理响应
  ///
  /// [uri] 目标端点
  /// [message] 已清洗的 JSON-RPC 消息
  /// [headers] 额外自定义请求头（认证等）
  /// [sessionId] 当前会话 ID（如果有）
  /// [cancelToken] 取消令牌
  ///
  /// 返回 [StreamablePostResult]；若响应为 SSE 流，流在后台增量解析，
  /// 每收到完整 data: 事件立即通过 onMessage 回调分发。
  ///
  /// 会话过期时抛出 [McpSessionExpiredException]。
  Future<StreamablePostResult> post({
    required Uri uri,
    required Map<String, dynamic> message,
    Map<String, String>? headers,
    String? sessionId,
    CancelToken? cancelToken,
  }) async {
    final postHeaders = <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': '2024-11-05',
      if (sessionId != null) 'Mcp-Session-Id': sessionId,
      if (headers != null) ...headers,
    };

    final response = await _dio.post<ResponseBody>(
      uri.toString(),
      data: message,
      options: Options(
        headers: postHeaders,
        contentType: 'application/json',
        responseType: ResponseType.stream,
        validateStatus: (status) => status != null && status < 500,
      ),
      cancelToken: cancelToken,
    );

    // 提取服务端可能返回的 Session ID
    final sessionHeader = response.headers.value('mcp-session-id') ??
        response.headers.value('Mcp-Session-Id');
    final newSessionId =
        (sessionHeader != null && sessionHeader.isNotEmpty) ? sessionHeader : null;

    // 404 会话过期检测：请求携带了 session 但服务端返回 404，说明会话已失效
    if (response.statusCode == 404 && sessionId != null) {
      await _drainAndCancelStream(response.data);
      throw McpSessionExpiredException(sessionId: sessionId);
    }

    final contentType =
        (response.headers.value('content-type') ?? '').toLowerCase();
    final body = response.data;

    if (body == null) {
      return StreamablePostResult(sessionId: newSessionId, isStream: false);
    }

    // SSE 流式响应：后台增量解析，收到响应头即返回
    if (contentType.contains('text/event-stream')) {
      _consumeSseStream(body);
      return StreamablePostResult(sessionId: newSessionId, isStream: true);
    }

    // JSON 或其他类型：读取完整响应体后解析
    final rawBody = await _readFullBody(body);
    if (rawBody.isNotEmpty) {
      _dispatchMessagePayload(rawBody);
    }
    return StreamablePostResult(sessionId: newSessionId, isStream: false);
  }

  /// 后台增量消费 SSE 流：每收到完整 data: 事件块立即解析分发
  void _consumeSseStream(ResponseBody body) {
    final dataLines = <String>[];

    void flushBlock() {
      if (dataLines.isEmpty) return;
      final joined = dataLines.join('\n').trim();
      if (joined.isNotEmpty) {
        _tryDecodeAndDispatch(joined);
      }
      dataLines.clear();
    }

    late final StreamSubscription<String> subscription;
    subscription = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) {
              // 空行 = SSE 事件块结束
              flushBlock();
            } else if (trimmed.startsWith(':')) {
              // SSE 注释或 keepalive ping，忽略
            } else if (trimmed.startsWith('data:')) {
              dataLines.add(trimmed.substring(5).trimLeft());
            }
            // 其他行（event:/id:/retry:）对消息分发无意义，忽略
          },
          onError: (Object error) {
            _streamSubscriptions.remove(subscription);
            // 流中断：尽力刷新已缓冲的行，避免丢失最后一条消息
            flushBlock();
            _onError(error);
          },
          onDone: () {
            _streamSubscriptions.remove(subscription);
            // 流正常关闭：刷新可能残留的最后一个事件块（无尾随空行的容错）
            flushBlock();
          },
          cancelOnError: true,
        );
    _streamSubscriptions.add(subscription);
  }

  /// 读取完整响应体为字符串
  Future<String> _readFullBody(ResponseBody body) async {
    final chunks = <List<int>>[];
    await for (final chunk in body.stream) {
      chunks.add(chunk);
    }
    if (chunks.isEmpty) return '';
    final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final merged = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      merged.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return utf8.decode(merged, allowMalformed: true);
  }

  /// 排空并取消流（404 等错误响应场景，避免连接泄漏）
  Future<void> _drainAndCancelStream(ResponseBody? body) async {
    if (body == null) return;
    try {
      await body.stream.drain<void>();
    } catch (_) {
      // 忽略排空失败
    }
  }

  /// 尝试解码 JSON 并分发 JSON-RPC 消息
  void _tryDecodeAndDispatch(String raw) {
    if (!raw.startsWith('{') && !raw.startsWith('[')) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        if (_isJsonRpcMessage(decoded)) {
          _onMessage(decoded);
        }
      } else if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic> && _isJsonRpcMessage(item)) {
            _onMessage(item);
          }
        }
      }
    } catch (_) {
      // 忽略非合法 JSON
    }
  }

  /// 通用 JSON-RPC 及标准 SSE 消息分发解析器
  /// (支持直接 JSON 对象/数组，以及以空行分隔的标准 SSE 事件块)
  void _dispatchMessagePayload(String rawBody) {
    final body = rawBody.trim();
    if (body.isEmpty) return;

    // 1. 直接作为 JSON-RPC 对象或数组解析
    if (body.startsWith('{') || body.startsWith('[')) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          if (_isJsonRpcMessage(decoded)) {
            _onMessage(decoded);
          }
          return;
        } else if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic> && _isJsonRpcMessage(item)) {
              _onMessage(item);
            }
          }
          return;
        }
      } catch (_) {}
    }

    // 2. 标准 SSE 格式块解析 (事件块以双换行分隔，支持多行 data:)
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
                _onMessage(decoded);
              }
              decodedSuccess = true;
            } else if (decoded is List) {
              for (final item in decoded) {
                if (item is Map<String, dynamic> && _isJsonRpcMessage(item)) {
                  _onMessage(item);
                }
              }
              decodedSuccess = true;
            }
          } catch (_) {}
        }

        // 容错：若合并多行解析失败，可能是非标服务端按单换行分隔了多个独立 JSON 消息
        if (!decodedSuccess && dataLines.length > 1) {
          for (final singleLine in dataLines) {
            _tryDecodeAndDispatch(singleLine.trim());
          }
        }
      }
    }
  }

  /// 验证是否为合法的 JSON-RPC 2.0 消息
  /// (过滤仅表示 HTTP 状态确认的 {'ok': true} 等非 RPC 响应)
  static bool _isJsonRpcMessage(Map<String, dynamic> map) {
    return map.containsKey('jsonrpc') ||
        (map.containsKey('id') &&
            (map.containsKey('result') ||
                map.containsKey('error') ||
                map.containsKey('method')));
  }

  /// 关闭并清理所有资源（取消全部活跃流订阅）
  Future<void> close() async {
    for (final subscription in _streamSubscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    _streamSubscriptions.clear();
  }
}
