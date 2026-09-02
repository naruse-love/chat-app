import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mcp_server_dao.dart';
import '../models/mcp/mcp_server_config.dart';
import '../models/mcp/mcp_server_state.dart';
import '../models/mcp/mcp_tool_info.dart';
import '../models/mcp/mcp_transport_type.dart';
import '../services/mcp/mcp_client.dart';
import '../services/mcp/mcp_dynamic_tool.dart';
import '../services/mcp/transports/http_mcp_transport.dart';
import '../services/mcp/transports/mcp_transport.dart';
import '../services/mcp/transports/sse_mcp_transport.dart';
import '../services/mcp/transports/stdio_mcp_transport.dart';
import '../services/mcp/transports/websocket_mcp_transport.dart';
import '../services/secure_storage_service.dart';
import '../services/tool_registry.dart';
import 'api_config_provider.dart';

typedef McpTransportFactory = McpTransport Function(McpServerConfig config);
typedef McpClientFactory = McpClient Function(McpTransport transport);

/// 全局 MCP DAO Provider
final mcpServerDaoProvider = Provider<McpServerDao>((ref) {
  final dbHelper = ref.watch(dbHelperProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return McpServerDao(dbHelper: dbHelper, secureStorage: secureStorage);
});

/// 全局 MCP 状态管理 Provider
final mcpProvider = StateNotifierProvider<McpNotifier, McpState>((ref) {
  final dao = ref.watch(mcpServerDaoProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  final toolRegistry = ref.watch(toolRegistryProvider);
  return McpNotifier(
    dao: dao,
    secureStorage: secureStorage,
    toolRegistry: toolRegistry,
  );
});

/// MCP 全局响应式状态
class McpState {
  final List<McpServerState> servers;
  final bool isLoading;
  final String? error;

  const McpState({
    this.servers = const [],
    this.isLoading = false,
    this.error,
  });

  McpState copyWith({
    List<McpServerState>? servers,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return McpState(
      servers: servers ?? this.servers,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  /// 获取指定 ID 的 Server 运行时状态
  McpServerState? getServerState(String serverId) {
    try {
      return servers.firstWhere((s) => s.config.id == serverId);
    } catch (_) {
      return null;
    }
  }

  /// 获取指定 ID 的 Server 配置
  McpServerConfig? getServerConfig(String serverId) {
    return getServerState(serverId)?.config;
  }

  /// 检查指定 Server 是否处于连接可用状态
  bool isServerConnected(String serverId) {
    return getServerState(serverId)?.isConnected ?? false;
  }

  /// 获取所有当前已连接的 Server 状态列表
  List<McpServerState> get connectedServers =>
      servers.where((s) => s.status == McpConnectionStatus.connected).toList();

  /// 获取所有启用的 Server 状态列表
  List<McpServerState> get enabledServers =>
      servers.where((s) => s.config.isEnabled).toList();

  /// 统计所有已连接 Server 注册的动态工具总数
  int get totalDynamicTools =>
      servers.fold(0, (sum, s) => sum + s.tools.length);
}

/// MCP 状态驱动管理控制器
/// 负责管理多 MCP Server 的持久化配置、连接生命周期、动态工具注入与注销
class McpNotifier extends StateNotifier<McpState> {
  final McpServerDao dao;
  final SecureStorageService secureStorage;
  final ToolRegistry toolRegistry;
  final McpTransportFactory? _customTransportFactory;
  final McpClientFactory? _customClientFactory;

  final Map<String, McpClient> _clients = {};
  final Map<String, List<String>> _registeredToolNames = {};
  final Map<String, StreamSubscription<McpConnectionStatus>> _statusSubscriptions = {};

  McpNotifier({
    required this.dao,
    SecureStorageService? secureStorage,
    ToolRegistry? toolRegistry,
    McpTransportFactory? transportFactory,
    McpClientFactory? clientFactory,
    bool autoLoad = true,
  })  : secureStorage = secureStorage ?? SecureStorageService(),
        toolRegistry = toolRegistry ?? ToolRegistry.defaultRegistry(),
        _customTransportFactory = transportFactory,
        _customClientFactory = clientFactory,
        super(const McpState()) {
    if (autoLoad) {
      loadServers();
    }
  }

  Map<String, McpClient> get activeClients => Map.unmodifiable(_clients);
  Map<String, List<String>> get registeredToolNames => Map.unmodifiable(_registeredToolNames);

  McpClient? getClient(String serverId) => _clients[serverId];

  /// 1. 加载所有 Server 配置并初始化状态
  Future<void> loadServers() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final configs = await dao.getAllServers();
      if (!mounted) return;

      final initialStates = configs.map((cfg) {
        return McpServerState(
          config: cfg,
          status: McpConnectionStatus.disconnected,
        );
      }).toList();

      state = state.copyWith(servers: initialStates, isLoading: false);

      // 对开启 autoConnect 且启用的 Server 自动触发异步连接
      for (final cfg in configs) {
        if (cfg.isEnabled && cfg.autoConnect) {
          unawaited(connectServer(cfg.id));
        }
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 2. 添加新 MCP Server 配置并按需自动连接
  Future<void> addServer(McpServerConfig config, {Map<String, String>? headers}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await dao.insertServer(config, headers: headers);
      if (!mounted) return;

      final savedConfig = await dao.getServerById(config.id);
      if (!mounted) return;

      final effectiveConfig = savedConfig ?? config;
      final serverState = McpServerState(
        config: effectiveConfig,
        status: McpConnectionStatus.disconnected,
      );

      final updatedServers = [
        ...state.servers.where((s) => s.config.id != effectiveConfig.id),
        serverState,
      ];
      state = state.copyWith(servers: updatedServers, isLoading: false);

      if (effectiveConfig.isEnabled && effectiveConfig.autoConnect) {
        await connectServer(effectiveConfig.id);
        if (!mounted) return;
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 3. 更新 MCP Server 配置并在需要时重新建立连接
  Future<void> updateServer(McpServerConfig config, {Map<String, String>? headers}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final existingState = state.getServerState(config.id);
      final wasConnected = existingState?.status == McpConnectionStatus.connected;

      if (wasConnected || _clients.containsKey(config.id)) {
        await disconnectServer(config.id);
        if (!mounted) return;
      }

      await dao.updateServer(config, headers: headers);
      if (!mounted) return;

      final updatedConfig = await dao.getServerById(config.id) ?? config;
      if (!mounted) return;

      final updatedServers = state.servers.map((s) {
        if (s.config.id == config.id) {
          return s.copyWith(config: updatedConfig);
        }
        return s;
      }).toList();

      state = state.copyWith(servers: updatedServers, isLoading: false);

      if (updatedConfig.isEnabled && (wasConnected || updatedConfig.autoConnect)) {
        await connectServer(updatedConfig.id);
        if (!mounted) return;
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 4. 删除指定 MCP Server 配置并注销其注入的动态工具
  Future<void> deleteServer(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await disconnectServer(id);
      if (!mounted) return;

      await dao.deleteServer(id);
      if (!mounted) return;

      final updatedServers = state.servers.where((s) => s.config.id != id).toList();
      state = state.copyWith(servers: updatedServers, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 5. 切换 MCP Server 启用状态
  Future<void> toggleServerEnabled(String id, bool isEnabled) async {
    final serverState = state.getServerState(id);
    if (serverState == null) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final updatedConfig = serverState.config.copyWith(
        isEnabled: isEnabled,
        updatedAt: DateTime.now(),
      );
      await dao.updateServer(updatedConfig);
      if (!mounted) return;

      final updatedServers = state.servers.map((s) {
        if (s.config.id == id) {
          return s.copyWith(config: updatedConfig);
        }
        return s;
      }).toList();
      state = state.copyWith(servers: updatedServers, isLoading: false);

      if (!isEnabled) {
        await disconnectServer(id);
        if (!mounted) return;
      } else if (updatedConfig.autoConnect) {
        await connectServer(id);
        if (!mounted) return;
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 6. 连接指定 MCP Server，完成协议握手并将发现的工具注入 ToolRegistry
  Future<void> connectServer(String id) async {
    final serverState = state.getServerState(id);
    if (serverState == null) return;

    if (serverState.status == McpConnectionStatus.connecting) return;

    if (_clients.containsKey(id)) {
      await _cleanupClient(id);
      if (!mounted) return;
    }

    _updateServerState(id, (s) => s.copyWith(status: McpConnectionStatus.connecting, clearError: true));

    try {
      final transport = _createTransport(serverState.config);
      final client = _createClient(transport);
      _clients[id] = client;

      // 监听传输层断连事件
      _statusSubscriptions[id]?.cancel();
      _statusSubscriptions[id] = client.statusStream.listen((newStatus) {
        if (!mounted) return;
        if (newStatus == McpConnectionStatus.disconnected &&
            state.getServerState(id)?.status == McpConnectionStatus.connected) {
          _unregisterToolsForServer(id);
          _updateServerState(id, (s) => s.copyWith(
            status: McpConnectionStatus.disconnected,
            tools: const [],
            resources: const [],
            prompts: const [],
          ));
        }
      });

      // 1. 协议握手协商
      final initResult = await client.initialize();
      if (!mounted) return;

      // 2. 工具列表发现
      List<McpToolInfo> tools = [];
      try {
        tools = await client.listTools();
        if (!mounted) return;
      } catch (_) {}

      // 3. 资源列表发现 (若服务端支持)
      List<McpResourceInfo> resources = [];
      if (initResult.capabilities.supportsResources) {
        try {
          resources = await client.listResources();
          if (!mounted) return;
        } catch (_) {}
      }

      // 4. Prompt 列表发现 (若服务端支持)
      List<McpPromptInfo> prompts = [];
      if (initResult.capabilities.supportsPrompts) {
        try {
          prompts = await client.listPrompts();
          if (!mounted) return;
        } catch (_) {}
      }

      // 5. 将动态工具注册至 ToolRegistry
      _unregisterToolsForServer(id);
      final registeredNames = <String>[];
      for (final tool in tools) {
        final dynamicTool = McpDynamicTool(
          client: client,
          serverId: id,
          serverName: serverState.config.name,
          toolInfo: tool,
          securityLevel: serverState.config.defaultSecurityLevel,
        );
        toolRegistry.register(dynamicTool, enabled: true);
        registeredNames.add(dynamicTool.name);
      }
      _registeredToolNames[id] = registeredNames;

      _updateServerState(id, (s) => s.copyWith(
        status: McpConnectionStatus.connected,
        tools: tools,
        resources: resources,
        prompts: prompts,
        serverInfo: initResult.serverInfo,
        capabilities: initResult.capabilities,
        lastConnectedAt: DateTime.now(),
        clearError: true,
      ));
    } catch (e) {
      if (!mounted) return;
      _unregisterToolsForServer(id);
      await _cleanupClient(id);
      if (!mounted) return;

      _updateServerState(id, (s) => s.copyWith(
        status: McpConnectionStatus.error,
        errorMessage: '连接失败: $e',
      ));
    }
  }

  /// 7. 断开指定 MCP Server 连接并注销已注册的动态工具
  Future<void> disconnectServer(String id) async {
    _unregisterToolsForServer(id);
    await _cleanupClient(id);
    if (!mounted) return;

    _updateServerState(id, (s) => s.copyWith(
      status: McpConnectionStatus.disconnected,
      tools: const [],
      resources: const [],
      prompts: const [],
      clearError: true,
    ));
  }

  /// 8. 测试指定配置的连接可行性并返回探测状态 (不影响持久化状态与 ToolRegistry)
  Future<McpServerState> testConnection(McpServerConfig config, {Map<String, String>? headers}) async {
    final effectiveConfig = headers != null ? config.copyWith(headers: headers) : config;
    McpClient? tempClient;
    try {
      final transport = _createTransport(effectiveConfig);
      tempClient = _createClient(transport);

      final initResult = await tempClient.initialize(timeout: const Duration(seconds: 10));

      List<McpToolInfo> tools = [];
      try {
        tools = await tempClient.listTools(timeout: const Duration(seconds: 10));
      } catch (_) {}

      List<McpResourceInfo> resources = [];
      if (initResult.capabilities.supportsResources) {
        try {
          resources = await tempClient.listResources(timeout: const Duration(seconds: 10));
        } catch (_) {}
      }

      List<McpPromptInfo> prompts = [];
      if (initResult.capabilities.supportsPrompts) {
        try {
          prompts = await tempClient.listPrompts(timeout: const Duration(seconds: 10));
        } catch (_) {}
      }

      return McpServerState(
        config: effectiveConfig,
        status: McpConnectionStatus.connected,
        tools: tools,
        resources: resources,
        prompts: prompts,
        serverInfo: initResult.serverInfo,
        capabilities: initResult.capabilities,
        lastConnectedAt: DateTime.now(),
      );
    } catch (e) {
      return McpServerState(
        config: effectiveConfig,
        status: McpConnectionStatus.error,
        errorMessage: '测试连接失败: $e',
      );
    } finally {
      if (tempClient != null) {
        await tempClient.close();
      }
    }
  }

  void _updateServerState(String id, McpServerState Function(McpServerState current) updater) {
    final updatedServers = state.servers.map((s) {
      if (s.config.id == id) {
        return updater(s);
      }
      return s;
    }).toList();
    state = state.copyWith(servers: updatedServers);
  }

  void _unregisterToolsForServer(String serverId) {
    final names = _registeredToolNames.remove(serverId);
    if (names != null) {
      for (final name in names) {
        toolRegistry.unregister(name);
      }
    }
  }

  Future<void> _cleanupClient(String serverId) async {
    _statusSubscriptions.remove(serverId)?.cancel();
    final client = _clients.remove(serverId);
    if (client != null) {
      await client.close();
    }
  }

  McpTransport _createTransport(McpServerConfig config) {
    final customFactory = _customTransportFactory;
    if (customFactory != null) {
      return customFactory(config);
    }

    switch (config.transportType) {
      case McpTransportType.stdio:
        final cmd = config.command?.trim() ?? '';
        if (cmd.isEmpty) {
          throw ArgumentError('Stdio 传输类型必须指定可执行命令路径 (command)');
        }
        return StdioMcpTransport(
          command: cmd,
          arguments: config.arguments ?? const [],
          environment: config.environment,
          workingDirectory: config.workingDirectory,
        );
      case McpTransportType.sse:
        final urlStr = config.url?.trim() ?? '';
        if (urlStr.isEmpty) {
          throw ArgumentError('SSE 传输类型必须指定服务 URL (url)');
        }
        final parsedUri = Uri.tryParse(urlStr);
        if (parsedUri == null || !parsedUri.hasScheme) {
          throw ArgumentError('无效的 SSE URL 格式: $urlStr');
        }
        return SseMcpTransport(
          uri: parsedUri,
          headers: config.headers,
        );
      case McpTransportType.websocket:
        final urlStr = config.url?.trim() ?? '';
        if (urlStr.isEmpty) {
          throw ArgumentError('WebSocket 传输类型必须指定服务 URL (url)');
        }
        final parsedUri = Uri.tryParse(urlStr);
        if (parsedUri == null || !parsedUri.hasScheme) {
          throw ArgumentError('无效的 WebSocket URL 格式: $urlStr');
        }
        return WebSocketMcpTransport(
          uri: parsedUri,
          headers: config.headers,
        );
      case McpTransportType.http:
        final urlStr = config.url?.trim() ?? '';
        if (urlStr.isEmpty) {
          throw ArgumentError('HTTP 传输类型必须指定服务 URL (url)');
        }
        final parsedUri = Uri.tryParse(urlStr);
        if (parsedUri == null || !parsedUri.hasScheme) {
          throw ArgumentError('无效的 HTTP URL 格式: $urlStr');
        }
        return HttpMcpTransport(
          uri: parsedUri,
          headers: config.headers,
        );
    }
  }

  McpClient _createClient(McpTransport transport) {
    final customFactory = _customClientFactory;
    if (customFactory != null) {
      return customFactory(transport);
    }
    return McpClient(transport: transport);
  }

  @override
  void dispose() {
    for (final sub in _statusSubscriptions.values) {
      sub.cancel();
    }
    _statusSubscriptions.clear();

    for (final client in _clients.values) {
      unawaited(client.close());
    }
    _clients.clear();

    for (final names in _registeredToolNames.values) {
      for (final name in names) {
        toolRegistry.unregister(name);
      }
    }
    _registeredToolNames.clear();

    super.dispose();
  }
}
