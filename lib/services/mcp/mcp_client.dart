import 'dart:async';
import '../../models/mcp/mcp_json_rpc.dart';
import '../../models/mcp/mcp_tool_info.dart';
import '../../models/mcp/mcp_transport_type.dart';
import 'json_rpc_engine.dart';
import 'transports/mcp_transport.dart';

/// Model Context Protocol (MCP) 客户端核心协议驱动
/// 遵循 MCP 2024-11-05 标准协议规范
/// 提供连接握手、心跳保活、工具/资源/Prompt 检索与调用、事件通知等完整契约
class McpClient {
  final McpTransport _transport;
  final JsonRpcEngine _engine;
  final Map<String, dynamic> _clientInfo;
  final Duration defaultTimeout;

  McpInitializeResult? _initResult;
  bool _isInitialized = false;
  bool _isDisposed = false;

  McpClient({
    required McpTransport transport,
    JsonRpcEngine? engine,
    Map<String, dynamic>? clientInfo,
    this.defaultTimeout = const Duration(seconds: 15),
  })  : _transport = transport,
        _engine = engine ?? JsonRpcEngine(transport: transport),
        _clientInfo = clientInfo ??
            const {
              'name': 'chat-app',
              'version': '1.11.0',
            };

  /// 底层传输通道
  McpTransport get transport => _transport;

  /// 底层 JSON-RPC 协议引擎
  JsonRpcEngine get engine => _engine;

  /// 当前底层传输连接状态
  McpConnectionStatus get status => _transport.status;

  /// 底层传输状态变更流
  Stream<McpConnectionStatus> get statusStream => _transport.statusStream;

  /// 服务端推送的通知流
  Stream<JsonRpcNotification> get notificationStream => _engine.notificationStream;

  /// 服务端发起的反向请求流
  Stream<JsonRpcRequest> get requestStream => _engine.requestStream;

  /// 握手成功后记录的服务端初始化能力与元数据
  McpInitializeResult? get initResult => _initResult;

  /// 是否已建立底层连接
  bool get isConnected => _transport.isConnected;

  /// 是否已完成协议握手初始化
  bool get isInitialized => _isInitialized && _transport.isConnected;

  /// 是否已被销毁
  bool get isDisposed => _isDisposed;

  /// 1. 协议握手协商 (initialize & notifications/initialized)
  /// 自动确保底层连接已建立，发起 initialize 请求并协商协议版本及 Capabilities，
  /// 随后依据 MCP 规范发送 notifications/initialized 确认通知。
  Future<McpInitializeResult> initialize({Duration? timeout}) async {
    if (_isDisposed) {
      throw StateError('McpClient has been disposed');
    }

    // 确保传输通道已连接
    if (!_transport.isConnected) {
      await _transport.connect();
    }

    final effectiveTimeout = timeout ?? defaultTimeout;

    // 发起 initialize 协议握手
    final initParams = {
      'protocolVersion': '2024-11-05',
      'capabilities': {
        'tools': {'listChanged': true},
        'resources': {'subscribe': false, 'listChanged': true},
        'prompts': {'listChanged': true},
      },
      'clientInfo': _clientInfo,
    };

    final rawResponse = await _engine.sendRequest(
      'initialize',
      initParams,
      effectiveTimeout,
    );

    final initResultMap = rawResponse is Map<String, dynamic>
        ? rawResponse
        : <String, dynamic>{};

    _initResult = McpInitializeResult.fromJson(initResultMap);

    // 发送 notifications/initialized 单向通知
    await _engine.sendNotification('notifications/initialized', {});

    _isInitialized = true;
    return _initResult!;
  }

  /// 2. 心跳探活 (ping)
  /// 向服务端发送 ping 请求检测保活状态
  Future<bool> ping({Duration? timeout}) async {
    if (_isDisposed) {
      throw StateError('McpClient has been disposed');
    }
    if (!_transport.isConnected) {
      return false;
    }

    try {
      await _engine.sendRequest(
        'ping',
        null,
        timeout ?? const Duration(seconds: 5),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 3. 工具列表发现 (tools/list)
  /// 获取服务端支持的全部工具元数据列表
  Future<List<McpToolInfo>> listTools({String? cursor, Duration? timeout}) async {
    if (_isDisposed) {
      throw StateError('McpClient has been disposed');
    }

    final params = cursor != null ? {'cursor': cursor} : null;
    final rawResponse = await _engine.sendRequest(
      'tools/list',
      params,
      timeout ?? defaultTimeout,
    );

    final toolsList = <McpToolInfo>[];
    if (rawResponse is Map<String, dynamic>) {
      final rawTools = rawResponse['tools'];
      if (rawTools is List) {
        for (final item in rawTools) {
          if (item is Map<String, dynamic>) {
            toolsList.add(McpToolInfo.fromJson(item));
          }
        }
      }
    }

    return toolsList;
  }

  /// 4. 工具调用执行 (tools/call)
  /// 调用指定名称的 MCP 远程工具并返回标准化结果
  Future<McpToolCallResult> callTool(
    String name,
    Map<String, dynamic> arguments, {
    Duration? timeout,
  }) async {
    if (_isDisposed) {
      throw StateError('McpClient has been disposed');
    }

    try {
      final rawResponse = await _engine.sendRequest(
        'tools/call',
        {
          'name': name,
          'arguments': arguments,
        },
        timeout ?? defaultTimeout,
      );

      if (rawResponse is Map<String, dynamic>) {
        return McpToolCallResult.fromJson(rawResponse);
      } else if (rawResponse is String) {
        return McpToolCallResult.text(rawResponse);
      } else {
        return McpToolCallResult.text(rawResponse?.toString() ?? '');
      }
    } on JsonRpcException catch (e) {
      return McpToolCallResult.error('MCP JSON-RPC 调用失败 (${e.code}): ${e.message}');
    } on TimeoutException catch (e) {
      return McpToolCallResult.error('MCP 工具调用超时 (${e.duration?.inSeconds ?? 0}s)');
    } catch (e) {
      return McpToolCallResult.error('MCP 工具调用异常: $e');
    }
  }

  /// 5. 资源列表发现 (resources/list)
  Future<List<McpResourceInfo>> listResources({
    String? cursor,
    Duration? timeout,
  }) async {
    if (_isDisposed) {
      throw StateError('McpClient has been disposed');
    }

    final params = cursor != null ? {'cursor': cursor} : null;
    final rawResponse = await _engine.sendRequest(
      'resources/list',
      params,
      timeout ?? defaultTimeout,
    );

    final resourcesList = <McpResourceInfo>[];
    if (rawResponse is Map<String, dynamic>) {
      final rawResources = rawResponse['resources'];
      if (rawResources is List) {
        for (final item in rawResources) {
          if (item is Map<String, dynamic>) {
            resourcesList.add(McpResourceInfo.fromJson(item));
          }
        }
      }
    }

    return resourcesList;
  }

  /// 6. 读取资源内容 (resources/read)
  Future<List<McpResourceContent>> readResource(
    String uri, {
    Duration? timeout,
  }) async {
    if (_isDisposed) {
      throw StateError('McpClient has been disposed');
    }

    final rawResponse = await _engine.sendRequest(
      'resources/read',
      {'uri': uri},
      timeout ?? defaultTimeout,
    );

    final contentsList = <McpResourceContent>[];
    if (rawResponse is Map<String, dynamic>) {
      final rawContents = rawResponse['contents'];
      if (rawContents is List) {
        for (final item in rawContents) {
          if (item is Map<String, dynamic>) {
            contentsList.add(McpResourceContent.fromJson(item));
          }
        }
      }
    }

    return contentsList;
  }

  /// 7. Prompt 模板列表发现 (prompts/list)
  Future<List<McpPromptInfo>> listPrompts({
    String? cursor,
    Duration? timeout,
  }) async {
    if (_isDisposed) {
      throw StateError('McpClient has been disposed');
    }

    final params = cursor != null ? {'cursor': cursor} : null;
    final rawResponse = await _engine.sendRequest(
      'prompts/list',
      params,
      timeout ?? defaultTimeout,
    );

    final promptsList = <McpPromptInfo>[];
    if (rawResponse is Map<String, dynamic>) {
      final rawPrompts = rawResponse['prompts'];
      if (rawPrompts is List) {
        for (final item in rawPrompts) {
          if (item is Map<String, dynamic>) {
            promptsList.add(McpPromptInfo.fromJson(item));
          }
        }
      }
    }

    return promptsList;
  }

  /// 8. 获取 Prompt 具体内容 (prompts/get)
  Future<Map<String, dynamic>> getPrompt(
    String name, [
    Map<String, dynamic>? arguments,
    Duration? timeout,
  ]) async {
    if (_isDisposed) {
      throw StateError('McpClient has been disposed');
    }

    final params = <String, dynamic>{
      'name': name,
      if (arguments != null) 'arguments': arguments,
    };

    final rawResponse = await _engine.sendRequest(
      'prompts/get',
      params,
      timeout ?? defaultTimeout,
    );

    if (rawResponse is Map<String, dynamic>) {
      return rawResponse;
    }
    return {'result': rawResponse};
  }

  /// 释放所有资源并关闭传输通道
  Future<void> close() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isInitialized = false;

    await _engine.close();
    await _transport.close();
  }

  /// 兼容释放接口
  Future<void> dispose() => close();
}
