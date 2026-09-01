/// MCP 内容块数据模型 (Content Block)
/// 支持文本 (text)、图片 (image) 以及嵌入式资源 (resource)
class McpContentBlock {
  /// 内容块类型: 'text', 'image', 'resource'
  final String type;

  /// 文本内容（适用于 text 类型）
  final String? text;

  /// Base64 编码的二进制数据（适用于 image 类型）
  final String? data;

  /// MIME 媒体类型（如 'image/png', 'application/json'）
  final String? mimeType;

  /// 资源 URI 标识符（适用于 resource 类型）
  final String? uri;

  /// 嵌入的资源原始数据或结构
  final dynamic resource;

  /// 附加注解信息（如 audience, priority）
  final Map<String, dynamic>? annotations;

  const McpContentBlock({
    required this.type,
    this.text,
    this.data,
    this.mimeType,
    this.uri,
    this.resource,
    this.annotations,
  });

  /// 快捷构造文本内容块
  factory McpContentBlock.text(String text, {Map<String, dynamic>? annotations}) {
    return McpContentBlock(
      type: 'text',
      text: text,
      annotations: annotations,
    );
  }

  /// 快捷构造图片内容块
  factory McpContentBlock.image({
    required String data,
    required String mimeType,
    Map<String, dynamic>? annotations,
  }) {
    return McpContentBlock(
      type: 'image',
      data: data,
      mimeType: mimeType,
      annotations: annotations,
    );
  }

  /// 快捷构造资源内容块
  factory McpContentBlock.resource({
    required String uri,
    String? mimeType,
    String? text,
    dynamic resource,
    Map<String, dynamic>? annotations,
  }) {
    return McpContentBlock(
      type: 'resource',
      uri: uri,
      mimeType: mimeType,
      text: text,
      resource: resource,
      annotations: annotations,
    );
  }

  factory McpContentBlock.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'text';
    return McpContentBlock(
      type: type,
      text: json['text'] as String?,
      data: json['data'] as String?,
      mimeType: json['mimeType'] as String?,
      uri: json['uri'] as String?,
      resource: json['resource'],
      annotations: json['annotations'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': type,
    };
    if (text != null) map['text'] = text;
    if (data != null) map['data'] = data;
    if (mimeType != null) map['mimeType'] = mimeType;
    if (uri != null) map['uri'] = uri;
    if (resource != null) map['resource'] = resource;
    if (annotations != null) map['annotations'] = annotations;
    return map;
  }

  /// 转换为可读文本摘要
  String toDisplayText() {
    switch (type) {
      case 'text':
        return text ?? '';
      case 'image':
        final mime = mimeType ?? 'image/*';
        return '[图片内容: $mime]';
      case 'resource':
        if (text != null && text!.isNotEmpty) {
          return text!;
        }
        return '[资源内容: ${uri ?? 'unknown'}]';
      default:
        return text ?? '[$type 内容]';
    }
  }

  @override
  String toString() => 'McpContentBlock(type: $type, text: $text, mimeType: $mimeType, uri: $uri)';
}

/// MCP 工具调用返回结果模型 (CallToolResult)
class McpToolCallResult {
  /// 内容块列表
  final List<McpContentBlock> content;

  /// 服务端是否标记为错误返回
  final bool isError;

  /// 附加元数据
  final Map<String, dynamic>? meta;

  const McpToolCallResult({
    required this.content,
    this.isError = false,
    this.meta,
  });

  /// 快捷构造纯文本成功结果
  factory McpToolCallResult.text(String text) {
    return McpToolCallResult(
      content: [McpContentBlock.text(text)],
      isError: false,
    );
  }

  /// 快捷构造错误结果
  factory McpToolCallResult.error(String errorMessage) {
    return McpToolCallResult(
      content: [McpContentBlock.text(errorMessage)],
      isError: true,
    );
  }

  factory McpToolCallResult.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    final contentList = <McpContentBlock>[];

    if (rawContent is List) {
      for (final item in rawContent) {
        if (item is Map<String, dynamic>) {
          contentList.add(McpContentBlock.fromJson(item));
        } else if (item is String) {
          contentList.add(McpContentBlock.text(item));
        }
      }
    } else if (rawContent is String) {
      contentList.add(McpContentBlock.text(rawContent));
    }

    final isError = json['isError'] == true;
    final meta = json['_meta'] as Map<String, dynamic>? ?? json['meta'] as Map<String, dynamic>?;

    return McpToolCallResult(
      content: contentList,
      isError: isError,
      meta: meta,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content.map((c) => c.toJson()).toList(),
      'isError': isError,
      if (meta != null) '_meta': meta,
    };
  }

  /// 聚合所有内容块转换为统一可读字符串
  String toDisplayText() {
    if (content.isEmpty) {
      return isError ? '执行出错（无详细信息）' : '';
    }
    return content.map((c) => c.toDisplayText()).join('\n');
  }

  @override
  String toString() => 'McpToolCallResult(isError: $isError, blocks: ${content.length})';
}

/// MCP 工具元数据模型 (Tool Descriptor)
class McpToolInfo {
  /// 工具名称
  final String name;

  /// 工具描述
  final String? description;

  /// JSON Schema 输入参数模式
  final Map<String, dynamic> inputSchema;

  const McpToolInfo({
    required this.name,
    this.description,
    this.inputSchema = const {'type': 'object', 'properties': {}},
  });

  factory McpToolInfo.fromJson(Map<String, dynamic> json) {
    return McpToolInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] is Map<String, dynamic>
          ? json['inputSchema'] as Map<String, dynamic>
          : const {'type': 'object', 'properties': {}},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'inputSchema': inputSchema,
    };
  }

  @override
  String toString() => 'McpToolInfo(name: $name, description: $description)';
}

/// MCP 资源元数据模型 (Resource Descriptor)
class McpResourceInfo {
  /// 资源 URI
  final String uri;

  /// 资源名称
  final String name;

  /// 资源描述
  final String? description;

  /// 媒体类型
  final String? mimeType;

  /// 文件/资源大小（字节数）
  final int? size;

  const McpResourceInfo({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
    this.size,
  });

  factory McpResourceInfo.fromJson(Map<String, dynamic> json) {
    return McpResourceInfo(
      uri: json['uri'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      mimeType: json['mimeType'] as String?,
      size: json['size'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uri': uri,
      'name': name,
      if (description != null) 'description': description,
      if (mimeType != null) 'mimeType': mimeType,
      if (size != null) 'size': size,
    };
  }

  @override
  String toString() => 'McpResourceInfo(uri: $uri, name: $name)';
}

/// MCP 资源读取内容模型 (Resource Content)
class McpResourceContent {
  /// 资源 URI
  final String uri;

  /// 媒体类型
  final String? mimeType;

  /// 文本内容
  final String? text;

  /// Base64 编码的二进制内容
  final String? blob;

  const McpResourceContent({
    required this.uri,
    this.mimeType,
    this.text,
    this.blob,
  });

  factory McpResourceContent.fromJson(Map<String, dynamic> json) {
    return McpResourceContent(
      uri: json['uri'] as String? ?? '',
      mimeType: json['mimeType'] as String?,
      text: json['text'] as String?,
      blob: json['blob'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uri': uri,
      if (mimeType != null) 'mimeType': mimeType,
      if (text != null) 'text': text,
      if (blob != null) 'blob': blob,
    };
  }

  @override
  String toString() => 'McpResourceContent(uri: $uri, mimeType: $mimeType)';
}

/// MCP Prompt 参数模型 (Prompt Argument)
class McpPromptArgument {
  /// 参数名称
  final String name;

  /// 参数说明
  final String? description;

  /// 是否必填
  final bool required;

  const McpPromptArgument({
    required this.name,
    this.description,
    this.required = false,
  });

  factory McpPromptArgument.fromJson(Map<String, dynamic> json) {
    return McpPromptArgument(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      required: json['required'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'required': required,
    };
  }

  @override
  String toString() => 'McpPromptArgument(name: $name, required: $required)';
}

/// MCP Prompt 模板信息模型 (Prompt Info)
class McpPromptInfo {
  /// Prompt 标识名称
  final String name;

  /// Prompt 功能描述
  final String? description;

  /// 参数定义列表
  final List<McpPromptArgument> arguments;

  const McpPromptInfo({
    required this.name,
    this.description,
    this.arguments = const [],
  });

  factory McpPromptInfo.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['arguments'];
    final argsList = <McpPromptArgument>[];
    if (rawArgs is List) {
      for (final item in rawArgs) {
        if (item is Map<String, dynamic>) {
          argsList.add(McpPromptArgument.fromJson(item));
        }
      }
    }

    return McpPromptInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      arguments: argsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'arguments': arguments.map((a) => a.toJson()).toList(),
    };
  }

  @override
  String toString() => 'McpPromptInfo(name: $name, arguments: ${arguments.length})';
}

/// MCP Server 功能特性声明 (Server Capabilities)
class McpServerCapabilities {
  /// 工具特性支持
  final Map<String, dynamic>? tools;

  /// 资源特性支持
  final Map<String, dynamic>? resources;

  /// Prompt 模板特性支持
  final Map<String, dynamic>? prompts;

  /// 日志特性支持
  final Map<String, dynamic>? logging;

  /// 实验性特性
  final Map<String, dynamic>? experimental;

  const McpServerCapabilities({
    this.tools,
    this.resources,
    this.prompts,
    this.logging,
    this.experimental,
  });

  bool get supportsTools => tools != null;
  bool get supportsResources => resources != null;
  bool get supportsPrompts => prompts != null;
  bool get supportsLogging => logging != null;

  factory McpServerCapabilities.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? toMap(dynamic val) {
      if (val is Map) return Map<String, dynamic>.from(val);
      return null;
    }

    return McpServerCapabilities(
      tools: toMap(json['tools']),
      resources: toMap(json['resources']),
      prompts: toMap(json['prompts']),
      logging: toMap(json['logging']),
      experimental: toMap(json['experimental']),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (tools != null) map['tools'] = tools;
    if (resources != null) map['resources'] = resources;
    if (prompts != null) map['prompts'] = prompts;
    if (logging != null) map['logging'] = logging;
    if (experimental != null) map['experimental'] = experimental;
    return map;
  }

  @override
  String toString() =>
      'McpServerCapabilities(tools: $supportsTools, resources: $supportsResources, prompts: $supportsPrompts)';
}

/// MCP 服务端信息模型 (Server Info)
class McpServerInfo {
  final String name;
  final String version;

  const McpServerInfo({
    required this.name,
    required this.version,
  });

  factory McpServerInfo.fromJson(Map<String, dynamic> json) {
    return McpServerInfo(
      name: json['name'] as String? ?? 'unknown',
      version: json['version'] as String? ?? '1.0.0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'version': version,
    };
  }

  @override
  String toString() => 'McpServerInfo(name: $name, version: $version)';
}

/// MCP 握手初始化协商返回模型 (Initialize Result)
class McpInitializeResult {
  /// 协商确定的协议版本（如 '2024-11-05'）
  final String protocolVersion;

  /// 服务端能力声明
  final McpServerCapabilities capabilities;

  /// 服务端基本信息
  final McpServerInfo serverInfo;

  /// 服务端系统指令或说明
  final String? instructions;

  const McpInitializeResult({
    required this.protocolVersion,
    required this.capabilities,
    required this.serverInfo,
    this.instructions,
  });

  factory McpInitializeResult.fromJson(Map<String, dynamic> json) {
    return McpInitializeResult(
      protocolVersion: json['protocolVersion'] as String? ?? '2024-11-05',
      capabilities: json['capabilities'] is Map<String, dynamic>
          ? McpServerCapabilities.fromJson(json['capabilities'] as Map<String, dynamic>)
          : const McpServerCapabilities(),
      serverInfo: json['serverInfo'] is Map<String, dynamic>
          ? McpServerInfo.fromJson(json['serverInfo'] as Map<String, dynamic>)
          : const McpServerInfo(name: 'unknown', version: '1.0.0'),
      instructions: json['instructions'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'protocolVersion': protocolVersion,
      'capabilities': capabilities.toJson(),
      'serverInfo': serverInfo.toJson(),
      if (instructions != null) 'instructions': instructions,
    };
  }

  @override
  String toString() =>
      'McpInitializeResult(protocolVersion: $protocolVersion, server: ${serverInfo.name})';
}
