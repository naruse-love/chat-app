import 'dart:async';
import '../../models/mcp/mcp_tool_info.dart';
import '../../models/tool/tool.dart';
import 'mcp_client.dart';

/// MCP 动态工具桥接适配器
/// 将远程 MCP Server 暴露的工具元数据动态包装为标准的 [Tool] 实例，
/// 支持自动命名空间隔离、参数 JSON Schema 自动解析转换、调用分发与执行结果标准化。
class McpDynamicTool extends Tool {
  /// 所属 MCP 客户端
  final McpClient client;

  /// 所属 MCP Server 唯一标识 ID
  final String serverId;

  /// 所属 MCP Server 显示名称
  final String serverName;

  /// MCP 原始工具元数据
  final McpToolInfo toolInfo;

  /// 安全等级分类（默认为 readOnly）
  @override
  final ToolSecurityLevel securityLevel;

  late final String _name;
  late final List<ToolParameter> _parameters;

  McpDynamicTool({
    required this.client,
    required this.serverId,
    required this.serverName,
    required this.toolInfo,
    this.securityLevel = ToolSecurityLevel.readOnly,
  }) {
    _name = _buildNamespacedName(serverId, toolInfo.name);
    _parameters = _parseInputSchema(toolInfo.inputSchema);
  }

  /// 原始远程 MCP 工具名称
  String get originalToolName => toolInfo.name;

  /// 符合 OpenAI 规范的唯一工具标识名 (mcp_{serverId}_{toolName})
  @override
  String get name => _name;

  /// UI 人性化展示名称 (例如: [MCP: Fetcher] fetch_html)
  @override
  String get displayName => '[MCP: $serverName] ${toolInfo.name}';

  /// LLM 提示词工具功能描述
  @override
  String get description {
    final desc = toolInfo.description?.trim();
    if (desc != null && desc.isNotEmpty) {
      return '$desc (MCP服务: $serverName)';
    }
    return '${toolInfo.name} (MCP服务: $serverName)';
  }

  /// 转换后的结构化参数列表
  @override
  List<ToolParameter> get parameters => _parameters;

  /// 构建符合 OpenAI Function Calling 规范的命名空间工具标识名
  /// 仅允许字母、数字、下划线和短横线，长度最多 64 字符
  static String _buildNamespacedName(String serverId, String toolName) {
    final cleanServer = _sanitizeIdentifier(serverId);
    final cleanTool = _sanitizeIdentifier(toolName);
    final rawName = 'mcp_${cleanServer}_$cleanTool';

    if (rawName.length <= 64) {
      return rawName;
    }
    // 超过 64 字符时截断，保留有效前缀与哈希特征
    return rawName.substring(0, 64);
  }

  /// 清洗字符串为合规的标识符
  static String _sanitizeIdentifier(String input) {
    final sanitized = input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    // 去除连续的多余下划线并去除首尾下划线
    final trimmed = sanitized.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isNotEmpty ? trimmed : 'tool';
  }

  /// 解析 JSON Schema inputSchema 为 ToolParameter 列表
  static List<ToolParameter> _parseInputSchema(Map<String, dynamic> schema) {
    final list = <ToolParameter>[];
    final properties = schema['properties'];
    if (properties is! Map<String, dynamic>) {
      return list;
    }

    final requiredSet = <String>{};
    final rawRequired = schema['required'];
    if (rawRequired is List) {
      for (final r in rawRequired) {
        if (r != null) {
          requiredSet.add(r.toString());
        }
      }
    }

    for (final entry in properties.entries) {
      final paramName = entry.key;
      final propDef = entry.value;

      if (propDef is Map<String, dynamic>) {
        final rawType = propDef['type'];
        String typeString = 'string';
        if (rawType is String) {
          typeString = rawType;
        } else if (rawType is List && rawType.isNotEmpty) {
          typeString = rawType.first.toString();
        }

        final desc = propDef['description']?.toString() ?? paramName;
        final isRequired = requiredSet.contains(paramName);

        List<String>? enumList;
        if (propDef['enum'] is List) {
          enumList = (propDef['enum'] as List)
              .map((e) => e.toString())
              .toList();
        }

        String? arrayItemType;
        if (typeString == 'array' && propDef['items'] is Map<String, dynamic>) {
          arrayItemType = (propDef['items'] as Map<String, dynamic>)['type']?.toString();
        }

        list.add(
          ToolParameter(
            name: paramName,
            description: desc,
            type: typeString,
            required: isRequired,
            enumValues: enumList,
            defaultValue: propDef['default'],
            arrayItemType: arrayItemType,
          ),
        );
      } else {
        // 宽松回退为通用 string 参数
        list.add(
          ToolParameter(
            name: paramName,
            description: paramName,
            type: 'string',
            required: requiredSet.contains(paramName),
          ),
        );
      }
    }

    return list;
  }

  /// 导出 OpenAI Function Calling JSON Schema
  @override
  Map<String, dynamic> toOpenAiSchema() {
    final schemaMap = Map<String, dynamic>.from(toolInfo.inputSchema);
    schemaMap.putIfAbsent('type', () => 'object');
    schemaMap.putIfAbsent('properties', () => <String, dynamic>{});

    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': schemaMap,
      },
    };
  }

  /// 校验传入实参
  @override
  String? validateArguments(Map<String, dynamic> arguments) {
    // 过滤内部以 __ 开头的上下文变量
    final filteredArgs = Map<String, dynamic>.fromEntries(
      arguments.entries.where((e) => !e.key.startsWith('__')),
    );

    for (final param in parameters) {
      final val = filteredArgs[param.name];
      final error = param.validate(val);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  /// 执行 MCP 远程工具调用并转换为标准 ToolExecutionResult
  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    // 剔除内部注入的上下文参数（以 __ 开头）
    final cleanArgs = <String, dynamic>{};
    for (final entry in arguments.entries) {
      if (!entry.key.startsWith('__')) {
        cleanArgs[entry.key] = entry.value;
      }
    }

    try {
      final mcpResult = await client.callTool(originalToolName, cleanArgs);
      stopwatch.stop();

      final displayText = mcpResult.toDisplayText();

      if (mcpResult.isError) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: displayText.isNotEmpty ? displayText : 'MCP 工具执行返回错误',
          content: displayText.isNotEmpty ? displayText : 'MCP 工具执行失败',
          rawData: mcpResult.toJson(),
          executionDuration: stopwatch.elapsed,
          metadata: {
            'serverId': serverId,
            'serverName': serverName,
            'originalToolName': originalToolName,
            'mcpResult': mcpResult.toJson(),
          },
        );
      }

      return ToolExecutionResult.success(
        toolName: name,
        content: displayText,
        rawData: mcpResult.toJson(),
        executionDuration: stopwatch.elapsed,
        metadata: {
          'serverId': serverId,
          'serverName': serverName,
          'originalToolName': originalToolName,
        },
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: 'MCP 工具调用发生异常: $e',
        content: 'MCP 工具 [$name] 执行失败: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {
          'serverId': serverId,
          'serverName': serverName,
          'originalToolName': originalToolName,
          'exception': e.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }

  @override
  String toString() => 'McpDynamicTool(name: $name, server: $serverName, original: $originalToolName)';
}
