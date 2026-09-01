import 'dart:async';
import '../../models/mcp/mcp_json_rpc.dart';
import '../../models/mcp/mcp_transport_type.dart';
import 'transports/mcp_transport.dart';

class _PendingRequest {
  final dynamic id;
  final String method;
  final Completer<dynamic> completer;
  final Timer timer;

  _PendingRequest({
    required this.id,
    required this.method,
    required this.completer,
    required this.timer,
  });
}

/// JSON-RPC 2.0 异步协议引擎
/// 负责请求/响应匹配关联、ID 分配、超时管理、通知派发以及异常转换
class JsonRpcEngine {
  final McpTransport transport;

  int _nextId = 1;
  final Map<dynamic, _PendingRequest> _pendingRequests = {};

  final StreamController<JsonRpcNotification> _notificationController =
      StreamController<JsonRpcNotification>.broadcast();
  final StreamController<JsonRpcRequest> _requestController =
      StreamController<JsonRpcRequest>.broadcast();

  StreamSubscription? _messageSubscription;
  StreamSubscription? _statusSubscription;
  bool _isClosed = false;

  JsonRpcEngine({required this.transport}) {
    _init();
  }

  void _init() {
    _messageSubscription = transport.messageStream.listen(
      _handleIncomingMessage,
      onError: (error) {
        _failAllPending('Transport message error: $error');
      },
    );

    _statusSubscription = transport.statusStream.listen((status) {
      if (status == McpConnectionStatus.disconnected ||
          status == McpConnectionStatus.error) {
        _failAllPending('Transport ${status.name}');
      }
    });
  }

  /// 收到来自底层传输的原始 JSON-RPC 字典消息
  void _handleIncomingMessage(Map<String, dynamic> raw) {
    // 1. 判断是否为 Response (包含 id 且有 result 或 error，且不含 method)
    final hasId = raw.containsKey('id') && raw['id'] != null;
    final hasMethod = raw.containsKey('method') && raw['method'] != null;
    final hasResultOrError = raw.containsKey('result') || raw.containsKey('error');

    if (hasId && (hasResultOrError || !hasMethod)) {
      final response = JsonRpcResponse.fromJson(raw);
      final pending = _pendingRequests.remove(response.id);
      if (pending != null) {
        pending.timer.cancel();
        if (response.isError) {
          pending.completer.completeError(
            JsonRpcException(
              response.error ??
                  const JsonRpcError(
                    code: JsonRpcError.internalError,
                    message: 'Internal error',
                  ),
            ),
          );
        } else {
          pending.completer.complete(response.result);
        }
      }
      return;
    }

    // 2. 判断是否为服务端发起的 Request (包含 id 与 method)
    if (hasId && hasMethod) {
      final request = JsonRpcRequest.fromJson(raw);
      if (!_requestController.isClosed) {
        _requestController.add(request);
      }
      return;
    }

    // 3. 判断是否为服务端发起的 Notification (不含 id 或 id 为 null，且包含 method)
    if (hasMethod) {
      final notification = JsonRpcNotification.fromJson(raw);
      if (!_notificationController.isClosed) {
        _notificationController.add(notification);
      }
      return;
    }
  }

  /// 发送 JSON-RPC 2.0 请求并等待响应结果
  Future<dynamic> sendRequest(
    String method, [
    dynamic params,
    Duration timeout = const Duration(seconds: 10),
  ]) async {
    if (_isClosed) {
      throw StateError('JsonRpcEngine is closed');
    }
    if (!transport.isConnected) {
      throw StateError('Transport is not connected');
    }

    final id = _nextId++;
    final completer = Completer<dynamic>();

    final timer = Timer(timeout, () {
      final pending = _pendingRequests.remove(id);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.completeError(
          TimeoutException(
            'JSON-RPC request $id ($method) timed out after ${timeout.inSeconds}s',
            timeout,
          ),
        );
      }
    });

    final pending = _PendingRequest(
      id: id,
      method: method,
      completer: completer,
      timer: timer,
    );
    _pendingRequests[id] = pending;

    final request = JsonRpcRequest(
      id: id,
      method: method,
      params: params,
    );

    try {
      await transport.send(request.toJson());
    } catch (e) {
      _pendingRequests.remove(id);
      timer.cancel();
      rethrow;
    }

    return completer.future;
  }

  /// 发送 JSON-RPC 2.0 单向通知（无需等待响应）
  Future<void> sendNotification(String method, [dynamic params]) async {
    if (_isClosed) {
      throw StateError('JsonRpcEngine is closed');
    }
    if (!transport.isConnected) {
      throw StateError('Transport is not connected');
    }

    final notification = JsonRpcNotification(
      method: method,
      params: params,
    );

    await transport.send(notification.toJson());
  }

  /// 响应服务端发起的请求结果
  Future<void> sendResponse(dynamic id, dynamic result) async {
    if (_isClosed) {
      throw StateError('JsonRpcEngine is closed');
    }
    if (!transport.isConnected) {
      throw StateError('Transport is not connected');
    }

    final response = JsonRpcResponse.success(id: id, result: result);
    await transport.send(response.toJson());
  }

  /// 响应服务端发起的请求错误
  Future<void> sendError(dynamic id, JsonRpcError error) async {
    if (_isClosed) {
      throw StateError('JsonRpcEngine is closed');
    }
    if (!transport.isConnected) {
      throw StateError('Transport is not connected');
    }

    final response = JsonRpcResponse.failure(id: id, error: error);
    await transport.send(response.toJson());
  }

  /// 服务端通知事件流
  Stream<JsonRpcNotification> get notificationStream =>
      _notificationController.stream;

  /// 服务端反向请求事件流
  Stream<JsonRpcRequest> get requestStream => _requestController.stream;

  /// 正在等待响应的请求总数
  int get pendingRequestCount => _pendingRequests.length;

  /// 终止并失败所有挂起请求
  void _failAllPending(String reason) {
    final entries = _pendingRequests.values.toList();
    _pendingRequests.clear();
    for (final pending in entries) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          JsonRpcException(
            JsonRpcError(
              code: JsonRpcError.internalError,
              message: 'Request ${pending.id} (${pending.method}) failed: $reason',
            ),
          ),
        );
      }
    }
  }

  /// 关闭引擎并释放资源
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    _failAllPending('Engine closed');

    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _statusSubscription?.cancel();
    _statusSubscription = null;

    await _notificationController.close();
    await _requestController.close();
  }
}
