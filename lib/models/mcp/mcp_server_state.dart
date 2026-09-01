import 'package:flutter/foundation.dart';
import 'mcp_server_config.dart';
import 'mcp_tool_info.dart';
import 'mcp_transport_type.dart';

/// MCP Server 运行时状态模型
/// 封装单个 MCP Server 的运行时连接状态、元数据与已发现工具/资源/Prompt 集合
class McpServerState {
  /// 所属 MCP Server 的持久化配置
  final McpServerConfig config;

  /// 当前运行时连接状态
  final McpConnectionStatus status;

  /// 该 Server 已发现并注册的工具元数据列表
  final List<McpToolInfo> tools;

  /// 该 Server 已发现的资源元数据列表
  final List<McpResourceInfo> resources;

  /// 该 Server 已发现的 Prompt 模板列表
  final List<McpPromptInfo> prompts;

  /// 握手成功后返回的服务端基础信息
  final McpServerInfo? serverInfo;

  /// 握手成功后返回的服务端能力声明
  final McpServerCapabilities? capabilities;

  /// 连接出错或调用失败时的错误信息
  final String? errorMessage;

  /// 最后一次成功建立连接的时间
  final DateTime? lastConnectedAt;

  const McpServerState({
    required this.config,
    this.status = McpConnectionStatus.disconnected,
    this.tools = const [],
    this.resources = const [],
    this.prompts = const [],
    this.serverInfo,
    this.capabilities,
    this.errorMessage,
    this.lastConnectedAt,
  });

  /// 是否处于已连接可用状态
  bool get isConnected => status == McpConnectionStatus.connected;

  /// 是否正在建立连接
  bool get isConnecting => status == McpConnectionStatus.connecting;

  /// 是否处于已断开状态
  bool get isDisconnected => status == McpConnectionStatus.disconnected;

  /// 是否处于异常错误状态
  bool get hasError => status == McpConnectionStatus.error || (errorMessage != null && errorMessage!.isNotEmpty);

  /// 已发现工具数量
  int get toolCount => tools.length;

  /// 已发现资源数量
  int get resourceCount => resources.length;

  /// 已发现 Prompt 数量
  int get promptCount => prompts.length;

  /// 创建状态副本并允许修改部分属性
  McpServerState copyWith({
    McpServerConfig? config,
    McpConnectionStatus? status,
    List<McpToolInfo>? tools,
    List<McpResourceInfo>? resources,
    List<McpPromptInfo>? prompts,
    McpServerInfo? serverInfo,
    McpServerCapabilities? capabilities,
    String? errorMessage,
    DateTime? lastConnectedAt,
    bool clearError = false,
  }) {
    return McpServerState(
      config: config ?? this.config,
      status: status ?? this.status,
      tools: tools ?? this.tools,
      resources: resources ?? this.resources,
      prompts: prompts ?? this.prompts,
      serverInfo: serverInfo ?? this.serverInfo,
      capabilities: capabilities ?? this.capabilities,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpServerState &&
          runtimeType == other.runtimeType &&
          config == other.config &&
          status == other.status &&
          listEquals(tools, other.tools) &&
          listEquals(resources, other.resources) &&
          listEquals(prompts, other.prompts) &&
          serverInfo == other.serverInfo &&
          capabilities == other.capabilities &&
          errorMessage == other.errorMessage &&
          lastConnectedAt == other.lastConnectedAt;

  @override
  int get hashCode =>
      config.hashCode ^
      status.hashCode ^
      tools.length.hashCode ^
      resources.length.hashCode ^
      prompts.length.hashCode ^
      serverInfo.hashCode ^
      capabilities.hashCode ^
      errorMessage.hashCode ^
      lastConnectedAt.hashCode;

  @override
  String toString() =>
      'McpServerState(id: ${config.id}, status: ${status.name}, tools: ${tools.length}, error: $errorMessage)';
}
