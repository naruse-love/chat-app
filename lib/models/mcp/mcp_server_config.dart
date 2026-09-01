import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../tool/tool_security_level.dart';
import 'mcp_transport_type.dart';

/// MCP 服务器配置模型
/// 用于持久化存储和管理单个 MCP Server 的通信与安全参数
class McpServerConfig {
  /// 服务器唯一标识 ID
  final String id;

  /// 服务器用户可读显示名称
  final String name;

  /// 传输通道类型 (stdio / sse / websocket)
  final McpTransportType transportType;

  /// 可执行文件命令路径 (适用于 stdio 传输)
  final String? command;

  /// 启动命令行参数列表 (适用于 stdio 传输)
  final List<String>? arguments;

  /// 进程环境变量字典 (适用于 stdio 传输)
  final Map<String, String>? environment;

  /// 子进程工作目录 (适用于 stdio 传输)
  final String? workingDirectory;

  /// 远程服务连接 URL (适用于 sse / websocket 传输)
  final String? url;

  /// 自定义 HTTP / WebSocket 请求头字典 (内存中缓存或显式传递)
  final Map<String, String>? headers;

  /// 安全存储中敏感请求头的引用标识键 (如 mcp_headers_${id})
  final String? headersRef;

  /// 是否启用该 Server
  final bool isEnabled;

  /// 启动或加载时是否自动建立连接
  final bool autoConnect;

  /// 注入 ToolRegistry 时赋予该 Server 工具的默认安全等级
  final ToolSecurityLevel defaultSecurityLevel;

  /// 配置创建时间
  final DateTime createdAt;

  /// 配置最后更新时间
  final DateTime updatedAt;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.transportType,
    this.command,
    this.arguments,
    this.environment,
    this.workingDirectory,
    this.url,
    this.headers,
    this.headersRef,
    this.isEnabled = true,
    this.autoConnect = true,
    this.defaultSecurityLevel = ToolSecurityLevel.readOnly,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 创建配置副本并允许修改部分字段
  McpServerConfig copyWith({
    String? id,
    String? name,
    McpTransportType? transportType,
    String? command,
    List<String>? arguments,
    Map<String, String>? environment,
    String? workingDirectory,
    String? url,
    Map<String, String>? headers,
    String? headersRef,
    bool? isEnabled,
    bool? autoConnect,
    ToolSecurityLevel? defaultSecurityLevel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      transportType: transportType ?? this.transportType,
      command: command ?? this.command,
      arguments: arguments ?? this.arguments,
      environment: environment ?? this.environment,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      headersRef: headersRef ?? this.headersRef,
      isEnabled: isEnabled ?? this.isEnabled,
      autoConnect: autoConnect ?? this.autoConnect,
      defaultSecurityLevel: defaultSecurityLevel ?? this.defaultSecurityLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 转换为 SQLite 存储专用的 Map 字典 (JSON 序列化复杂类型)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'transportType': transportType.nameString,
      'command': command,
      'arguments': arguments != null ? jsonEncode(arguments) : null,
      'environment': environment != null ? jsonEncode(environment) : null,
      'workingDirectory': workingDirectory,
      'url': url,
      'headersRef': headersRef,
      'isEnabled': isEnabled ? 1 : 0,
      'autoConnect': autoConnect ? 1 : 0,
      'defaultSecurityLevel': defaultSecurityLevel.level,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从 SQLite Map 字典解析还原对象
  factory McpServerConfig.fromMap(Map<String, dynamic> map, {Map<String, String>? headers}) {
    List<String>? argumentsList;
    final rawArguments = map['arguments'];
    if (rawArguments is String && rawArguments.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArguments);
        if (decoded is List) {
          argumentsList = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    } else if (rawArguments is List) {
      argumentsList = rawArguments.map((e) => e.toString()).toList();
    }

    Map<String, String>? envMap;
    final rawEnvironment = map['environment'];
    if (rawEnvironment is String && rawEnvironment.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEnvironment);
        if (decoded is Map) {
          envMap = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    } else if (rawEnvironment is Map) {
      envMap = rawEnvironment.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    ToolSecurityLevel securityLevel = ToolSecurityLevel.readOnly;
    final rawSec = map['defaultSecurityLevel'];
    if (rawSec is int) {
      securityLevel = ToolSecurityLevel.fromLevel(rawSec);
    } else if (rawSec is String) {
      securityLevel = ToolSecurityLevel.fromJson(rawSec);
    }

    final rawTransport = map['transportType']?.toString() ?? 'stdio';
    final transportType = McpTransportTypeExtension.fromString(rawTransport);

    final rawCreatedAt = map['createdAt']?.toString();
    final createdAt = rawCreatedAt != null
        ? (DateTime.tryParse(rawCreatedAt) ?? DateTime.now())
        : DateTime.now();

    final rawUpdatedAt = map['updatedAt']?.toString();
    final updatedAt = rawUpdatedAt != null
        ? (DateTime.tryParse(rawUpdatedAt) ?? DateTime.now())
        : DateTime.now();

    return McpServerConfig(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      transportType: transportType,
      command: map['command'] as String?,
      arguments: argumentsList,
      environment: envMap,
      workingDirectory: map['workingDirectory'] as String?,
      url: map['url'] as String?,
      headers: headers,
      headersRef: map['headersRef'] as String?,
      isEnabled: map['isEnabled'] == 1 || map['isEnabled'] == true,
      autoConnect: map['autoConnect'] == 1 || map['autoConnect'] == true,
      defaultSecurityLevel: securityLevel,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 转换为通用 JSON 字典
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'transportType': transportType.nameString,
      'command': command,
      'arguments': arguments,
      'environment': environment,
      'workingDirectory': workingDirectory,
      'url': url,
      'headers': headers,
      'headersRef': headersRef,
      'isEnabled': isEnabled,
      'autoConnect': autoConnect,
      'defaultSecurityLevel': defaultSecurityLevel.level,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 从通用 JSON 字典解析
  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig.fromMap(json, headers: json['headers'] is Map
        ? (json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
        : null);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpServerConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          transportType == other.transportType &&
          command == other.command &&
          listEquals(arguments, other.arguments) &&
          mapEquals(environment, other.environment) &&
          workingDirectory == other.workingDirectory &&
          url == other.url &&
          mapEquals(headers, other.headers) &&
          headersRef == other.headersRef &&
          isEnabled == other.isEnabled &&
          autoConnect == other.autoConnect &&
          defaultSecurityLevel == other.defaultSecurityLevel &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      transportType.hashCode ^
      command.hashCode ^
      (arguments?.length ?? 0).hashCode ^
      (environment?.length ?? 0).hashCode ^
      workingDirectory.hashCode ^
      url.hashCode ^
      (headers?.length ?? 0).hashCode ^
      headersRef.hashCode ^
      isEnabled.hashCode ^
      autoConnect.hashCode ^
      defaultSecurityLevel.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() =>
      'McpServerConfig(id: $id, name: $name, transport: ${transportType.nameString}, enabled: $isEnabled)';
}
