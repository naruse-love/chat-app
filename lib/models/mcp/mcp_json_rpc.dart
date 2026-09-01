/// JSON-RPC 2.0 错误模型
class JsonRpcError {
  /// 语法解析错误（Invalid JSON was received by the server）
  static const int parseError = -32700;

  /// 无效请求（The JSON sent is not a valid Request object）
  static const int invalidRequest = -32600;

  /// 方法不存在（The method does not exist / is not available）
  static const int methodNotFound = -32601;

  /// 无效参数（Invalid method parameter(s)）
  static const int invalidParams = -32602;

  /// 内部错误（Internal JSON-RPC error）
  static const int internalError = -32603;

  /// 错误码
  final int code;

  /// 错误简述
  final String message;

  /// 附加结构化错误数据
  final dynamic data;

  const JsonRpcError({
    required this.code,
    required this.message,
    this.data,
  });

  factory JsonRpcError.fromCode(int code, [String? message, dynamic data]) {
    String defaultMessage;
    switch (code) {
      case parseError:
        defaultMessage = 'Parse error';
        break;
      case invalidRequest:
        defaultMessage = 'Invalid Request';
        break;
      case methodNotFound:
        defaultMessage = 'Method not found';
        break;
      case invalidParams:
        defaultMessage = 'Invalid params';
        break;
      case internalError:
        defaultMessage = 'Internal error';
        break;
      default:
        defaultMessage = 'JSON-RPC error ($code)';
    }
    return JsonRpcError(
      code: code,
      message: message ?? defaultMessage,
      data: data,
    );
  }

  factory JsonRpcError.fromJson(Map<String, dynamic> json) {
    return JsonRpcError(
      code: json['code'] as int? ?? internalError,
      message: json['message']?.toString() ?? 'Unknown error',
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'code': code,
      'message': message,
    };
    if (data != null) {
      map['data'] = data;
    }
    return map;
  }

  @override
  String toString() => 'JsonRpcError(code: $code, message: $message, data: $data)';
}

/// JSON-RPC 2.0 异常
class JsonRpcException implements Exception {
  final JsonRpcError error;

  const JsonRpcException(this.error);

  int get code => error.code;
  String get message => error.message;
  dynamic get data => error.data;

  @override
  String toString() => 'JsonRpcException: ${error.message} (code: ${error.code})';
}

/// JSON-RPC 2.0 请求
class JsonRpcRequest {
  final String jsonrpc;
  final dynamic id; // int or String
  final String method;
  final dynamic params; // Map<String, dynamic> or List<dynamic>

  const JsonRpcRequest({
    this.jsonrpc = '2.0',
    required this.id,
    required this.method,
    this.params,
  });

  factory JsonRpcRequest.fromJson(Map<String, dynamic> json) {
    return JsonRpcRequest(
      jsonrpc: json['jsonrpc']?.toString() ?? '2.0',
      id: json['id'],
      method: json['method']?.toString() ?? '',
      params: json['params'],
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'id': id,
      'method': method,
    };
    if (params != null) {
      map['params'] = params;
    }
    return map;
  }

  @override
  String toString() => 'JsonRpcRequest(id: $id, method: $method, params: $params)';
}

/// JSON-RPC 2.0 响应
class JsonRpcResponse {
  final String jsonrpc;
  final dynamic id; // int or String or null
  final dynamic result;
  final JsonRpcError? error;

  const JsonRpcResponse({
    this.jsonrpc = '2.0',
    this.id,
    this.result,
    this.error,
  });

  factory JsonRpcResponse.success({
    required dynamic id,
    dynamic result,
  }) =>
      JsonRpcResponse(
        id: id,
        result: result,
      );

  factory JsonRpcResponse.failure({
    required dynamic id,
    required JsonRpcError error,
  }) =>
      JsonRpcResponse(
        id: id,
        error: error,
      );

  bool get isSuccess => error == null;
  bool get isError => error != null;

  factory JsonRpcResponse.fromJson(Map<String, dynamic> json) {
    return JsonRpcResponse(
      jsonrpc: json['jsonrpc']?.toString() ?? '2.0',
      id: json['id'],
      result: json['result'],
      error: json['error'] is Map<String, dynamic>
          ? JsonRpcError.fromJson(json['error'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'id': id,
    };
    if (error != null) {
      map['error'] = error!.toJson();
    } else {
      map['result'] = result;
    }
    return map;
  }

  @override
  String toString() => 'JsonRpcResponse(id: $id, result: $result, error: $error)';
}

/// JSON-RPC 2.0 通知
class JsonRpcNotification {
  final String jsonrpc;
  final String method;
  final dynamic params;

  const JsonRpcNotification({
    this.jsonrpc = '2.0',
    required this.method,
    this.params,
  });

  factory JsonRpcNotification.fromJson(Map<String, dynamic> json) {
    return JsonRpcNotification(
      jsonrpc: json['jsonrpc']?.toString() ?? '2.0',
      method: json['method']?.toString() ?? '',
      params: json['params'],
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'jsonrpc': jsonrpc,
      'method': method,
    };
    if (params != null) {
      map['params'] = params;
    }
    return map;
  }

  @override
  String toString() => 'JsonRpcNotification(method: $method, params: $params)';
}
