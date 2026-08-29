# 可插拔工具注册中心与执行引擎架构设计报告
# (Pluggable Tool Registry Architecture & Execution Engine)

> **文档版本**: 1.0.0  
> **设计团队**: Tool Registry & Execution Engine Architecture Group  
> **适用项目**: Flutter AI Chat (chat-app)  
> **状态**: 架构蓝图与规范定义 (Ready for Implementation)

---

## 目录 (Table of Contents)

1. [执行总述与设计愿景 (Executive Summary & Architectural Vision)](#1-执行总述与设计愿景)
2. [统一 `ToolRegistry` 与 `Tool` 抽象接口架构](#2-统一-toolregistry-与-tool-抽象接口架构)
   - 2.1 类层次结构与核心契约 (`Tool`, `ToolParameter`, `ToolExecutionResult`)
   - 2.2 工具分类体系与元数据规范 (`ToolCategory`, `ToolMetadata`)
   - 2.3 `ToolRegistry` 服务体系与生命周期管理
   - 2.4 模型能力自适应与 OpenAI Schema 导出 (`supportsTools` / 伪 XML 兜底)
   - 2.5 内置工具与动态外部工具扩展模式 (Built-in Tools & MCP/Plugin Tools)
3. [工具生命周期与动态配置管理 (Tool Lifecycle & Dynamic Configuration)](#3-工具生命周期与动态配置管理)
   - 3.1 完整生命周期状态机
   - 3.2 多层级启用/禁用配置 (全局、分类、单工具)
   - 3.3 动态参数与凭证安全持久化 (SharedPreferences + SecureStorage)
   - 3.4 Riverpod 状态绑定与响应式通知
4. [细粒度安全权限与交互式 UI 确认流 (Fine-grained Security & Human-in-the-Loop)](#4-细粒度安全权限与交互式-ui-确认流)
   - 4.1 四级安全权限矩阵 (`PermissionLevel`)
   - 4.2 异步人机交互确认工作流 (Human-in-the-Loop Workflow)
   - 4.3 确认决策会话级白名单与沙箱隔离
   - 4.4 拒绝执行回传与 LLM 自适应兜底
5. [流式事件管道与 UI 折叠渲染规范 (Streaming Event Pipeline & UI Rendering)](#5-流式事件管道与-ui-折叠渲染规范)
   - 5.1 统一事件管道体系 (`AgentStreamEvent` 升级)
   - 5.2 Riverpod 状态模型重构 (`ToolExecutionState`, `ActiveToolCallState`)
   - 5.3 `ChatBubble` 折叠式工具调用卡片与交互规范
   - 5.4 实时执行状态指示与进度条反馈
6. [健壮容错、重试策略与 Token 截断引擎 (Fault Tolerance, Retries & Token Management)](#6-健壮容错重试策略与-token-截断引擎)
   - 6.1 参数 Schema 前置校验与自我纠错机制
   - 6.2 智能超时与指数退避重试策略 (Exponential Backoff with Jitter)
   - 6.3 Token 预算与内容感知截断引擎 (Token Truncation Engine)
   - 6.4 循环死锁防护与降级总结机制 (Loop Guard & Degraded Completion)
7. [演进迁移策略与质量验证矩阵 (Migration Path & Verification Strategy)](#7-演进迁移策略与质量验证矩阵)
   - 7.1 向后兼容性保障与平滑迁移路径
   - 7.2 全面单元测试与 Widget 测试方案
8. [总结与架构交付件清单 (Deliverables Matrix)](#8-总结与架构交付件清单)

---

## 1. 执行总述与设计愿景

### 1.1 现状诊断与瓶颈分析

在当前 Flutter AI Chat (chat-app) 的实现中，AI 工具调用（Function Calling）与 Agent 调度体系取得了显著成效，已支持 SearXNG / Google / Bing 搜索、`url_fetch` 网页解析、伪 XML 兜底及多轮交互。然而，随着后续 Agent 工具生态的拓展（如高精数学、本地文件读写、代码沙箱执行、MCP 外部协议、移动原生设备特权等），现有架构暴露了若干结构性瓶颈：

1. **硬编码耦合 (Tight Coupling)**：工具定义以静态 `Map<String, dynamic>` 散落在 `AgentService` 内，工具执行在 `chatAndSearchStream` 和 `_streamCompletionsLoop` 中通过多重 `if (entry.name == '...')` 硬编码分发，新增工具必须修改核心 Agent 逻辑。
2. **事件与状态专用化 (Specialized Events & State)**：流式事件（如 `ToolCallStartedEvent`、`UrlFetchStartedEvent`）与 Riverpod 状态（`AgentState` 中的 `isSearching`、`isFetchingUrl`）高度特化，无法无缝支撑泛化工具的扩展。
3. **缺乏安全防护与用户确认机制 (Lack of Permission Control)**：现有工具均以完全信任模式在后台静默执行。对于写文件、运行脚本、修改系统日历等高危/特权操作，缺乏细粒度安全审查与人机协同交互确认（Human-in-the-Loop）。
4. **参数校验与容错薄弱 (Brittle Validation & Error Handling)**：缺少结构化 JSON Schema 运行时校验，模型传递错误参数时直接引发底层异常；且缺少针对偶发网络故障的指数重试退避机制。
5. **Token 爆炸与截断策略分散 (Scattered Truncation Strategy)**：大文本内容截断分散在各服务内（如 `UrlFetchService` 的 15000 字符硬截断），缺乏统一的 Token 预算管理与头尾智能保留算法。

### 1.2 目标架构愿景

本架构设计提出一套**模块化、可插拔、细粒度安全、强容错**的全新统一工具生态体系：
- **可插拔工具注册中心 (`ToolRegistry`)**：定义统一面向对象契约 `Tool`，统一纳管静态内置工具与动态外部工具（MCP / 脚本沙箱 / 自定义 REST 插件）。
- **统一流式执行引擎 (`ToolExecutionEngine`)**：解耦 Agent 调度与工具执行，支持参数校验、超时重试、安全审查、异步流暂停与恢复。
- **人机协同确认工作流 (Human-in-the-Loop)**：将工具划分为 `safe`、`readOnly`、`sensitiveConfirm`、`privilegedNative` 4 级安全权限，在流式生成中支持无缝暂停、弹出卡片交互确认、会话级授权或拒绝恢复。
- **全动态 UI 折叠渲染**：基于分类图标、执行耗时、参数预览、Markdown 格式化结果与复制功能，提供一流的移动端交互体验。
- **自愈式容错与 Token 截断引擎**：提供基于 JSON Schema 的参数自愈纠错提示、网络异常自适应重试、Token 预算智能截断及多轮死循环保底熔断。

---

## 2. 统一 `ToolRegistry` 与 `Tool` 抽象接口架构

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                  ToolRegistry                                   │
│  - register(Tool) / unregister(name)                                            │
│  - getTool(name) / getAllTools()                                                │
│  - getEffectiveToolsForModel(ModelInfo, AppSettings, ToolContext)               │
│  - exportOpenAiTools() / exportSystemPromptDescription()                        │
└───────────────────────┬─────────────────────────────────┬───────────────────────┘
                        │ 1 : N                           │ 1 : N
                        ▼                                 ▼
         ┌──────────────────────────────┐  ┌──────────────────────────────┐
         │     Static Built-in Tools    │  │    Dynamic External Tools    │
         ├──────────────────────────────┤  ├──────────────────────────────┤
         │ • WebSearchTool (SearXNG/Bing│  │ • McpTool (Stdio/SSE/WS)     │
         │ • UrlFetchTool (HTML Parser) │  │ • ScriptEvalTool (JS/Dart)   │
         │ • MathEvalTool (Calculator)  │  │ • CustomPluginTool (REST API)│
         │ • TimeTool (Timezone/Clock)  │  │ • NativeCalendarTool (Mobile)│
         └──────────────┬───────────────┘  └──────────────┬───────────────┘
                        └────────────────┬────────────────┘
                                         ▼
                     ┌───────────────────────────────────────┐
                     │          abstract class Tool          │
                     ├───────────────────────────────────────┤
                     │ + name: String                        │
                     │ + displayName: String                 │
                     │ + description: String                 │
                     │ + category: ToolCategory              │
                     │ + permissionLevel: PermissionLevel    │
                     │ + parameters: List<ToolParameter>     │
                     │ + isBuiltIn: bool                     │
                     │ + isEnabled: bool                     │
                     │ + timeoutDuration: Duration           │
                     │ + maxRetries: int                     │
                     │ + execute(context, args): Future<Res> │
                     └───────────────────────────────────────┘
```

### 2.1 类层次结构与核心契约

#### 2.1.1 权限级别与工具分类枚举

```dart
/// 细粒度安全权限级别
enum PermissionLevel {
  /// 纯本地计算，无副作用（如数学计算、相对时间计算），全自动执行
  safe,

  /// 外部只读操作，无持久状态变更（如网络搜索、网页抓取、读文件），默认自动执行（可配置为确认）
  readOnly,

  /// 敏感变更操作（如写文件、删除文件、剪贴板写入、MCP 变更操作），必须经用户 UI 确认
  sensitiveConfirm,

  /// 原生设备特权能力（如系统日历读写、发送通知、通讯录访问、Shell 执行），必须显式确认 + 系统授权
  privilegedNative,
}

/// 工具所属领域分类
enum ToolCategory {
  search,       // 搜索引擎 (Google, Bing, SearXNG)
  web,          // 网页与网络 (url_fetch, html_parse)
  utility,      // 基础实用工具 (math, time, unit_converter)
  fileSystem,   // 本地文件安全读写
  codeExecution,// 脚本/沙箱执行 (JS, Dart Eval)
  mcp,          // Model Context Protocol 扩展协议
  nativeDevice, // 移动端原生硬件与服务 (Calendar, Notification, Clipboard)
  customPlugin, // 用户自定义 REST / Webhook 插件
}

extension ToolCategoryExtension on ToolCategory {
  String get displayName {
    switch (this) {
      case ToolCategory.search: return '网络搜索';
      case ToolCategory.web: return '网页抓取';
      case ToolCategory.utility: return '基础实用';
      case ToolCategory.fileSystem: return '文件操作';
      case ToolCategory.codeExecution: return '代码沙箱';
      case ToolCategory.mcp: return 'MCP 协议';
      case ToolCategory.nativeDevice: return '系统原生';
      case ToolCategory.customPlugin: return '自定义插件';
    }
  }

  String get iconKey {
    switch (this) {
      case ToolCategory.search: return 'travel_explore';
      case ToolCategory.web: return 'language';
      case ToolCategory.utility: return 'calculate';
      case ToolCategory.fileSystem: return 'folder_open';
      case ToolCategory.codeExecution: return 'terminal';
      case ToolCategory.mcp: return 'hub';
      case ToolCategory.nativeDevice: return 'smartphone';
      case ToolCategory.customPlugin: return 'extension';
    }
  }
}
```

#### 2.1.2 参数定义与元数据 (`ToolParameter`, `ToolMetadata`)

```dart
/// 参数数据类型
enum ParameterType {
  string,
  integer,
  number,
  boolean,
  array,
  object,
}

/// 单个参数的严格模式定义
class ToolParameter {
  final String name;
  final ParameterType type;
  final String description;
  final bool isRequired;
  final dynamic defaultValue;
  final List<dynamic>? enumValues;
  final Map<String, dynamic>? itemSchema; // 当 type == array 时子元素 schema
  final Map<String, ToolParameter>? properties; // 当 type == object 时嵌套字段

  const ToolParameter({
    required this.name,
    required this.type,
    required this.description,
    this.isRequired = true,
    this.defaultValue,
    this.enumValues,
    this.itemSchema,
    this.properties,
  });

  /// 转换为 OpenAI JSON Schema 的 Property 定义
  Map<String, dynamic> toOpenAiPropertySchema() {
    final map = <String, dynamic>{
      'type': type.name,
      'description': description,
    };
    if (enumValues != null && enumValues!.isNotEmpty) {
      map['enum'] = enumValues;
    }
    if (defaultValue != null) {
      map['default'] = defaultValue;
    }
    if (type == ParameterType.array && itemSchema != null) {
      map['items'] = itemSchema;
    }
    if (type == ParameterType.object && properties != null) {
      final nestedProps = <String, dynamic>{};
      final nestedRequired = <String>[];
      for (final prop in properties!.values) {
        nestedProps[prop.name] = prop.toOpenAiPropertySchema();
        if (prop.isRequired) nestedRequired.add(prop.name);
      }
      map['properties'] = nestedProps;
      if (nestedRequired.isNotEmpty) {
        map['required'] = nestedRequired;
      }
    }
    return map;
  }
}

/// 工具元数据扩展
class ToolMetadata {
  final String version;
  final String author;
  final String iconName;
  final List<String> tags;
  final String? documentationUrl;
  final bool isExperimental;

  const ToolMetadata({
    this.version = '1.0.0',
    this.author = 'Official',
    required this.iconName,
    this.tags = const [],
    this.documentationUrl,
    this.isExperimental = false,
  });
}
```

#### 2.1.3 执行上下文与返回结果 (`ToolExecutionContext`, `ToolExecutionResult`)

```dart
import 'package:dio/dio.dart';

/// 工具执行上下文环境
class ToolExecutionContext {
  final String conversationId;
  final String messageId;
  final String toolCallId;
  final CancelToken? cancelToken;
  final Map<String, dynamic> environmentVariables;
  final void Function(double progress, String statusMessage)? onProgress;

  const ToolExecutionContext({
    required this.conversationId,
    required this.messageId,
    required this.toolCallId,
    this.cancelToken,
    this.environmentVariables = const {},
    this.onProgress,
  });
}

/// 执行结果状态
enum ToolExecutionStatus {
  success,
  failure,
  deniedByUser,
  timeout,
  cancelled,
  schemaError,
}

/// 结构化工具执行结果
class ToolExecutionResult {
  final ToolExecutionStatus status;
  
  /// 传递给大模型作为上下文的最终文本（若超限则已截断）
  final String output;
  
  /// 原始结构化数据对象（Map/List），供 UI 深度结构化呈现
  final dynamic rawJson;
  
  /// 专供用户端 UI Markdown 渲染的富文本呈现（若为空则使用 output）
  final String? formattedMarkdown;
  
  /// 错误诊断信息
  final String? error;
  
  /// 实际执行耗时
  final Duration executionDuration;
  
  /// 是否发生了 Token / 字符截断
  final bool isTruncated;
  
  /// 截断前原始字符数
  final int originalLength;
  
  /// 附加诊断元数据（如 HTTP Status, Source URL, Cache Hit 等）
  final Map<String, dynamic> metadata;

  const ToolExecutionResult({
    required this.status,
    required this.output,
    this.rawJson,
    this.formattedMarkdown,
    this.error,
    required this.executionDuration,
    this.isTruncated = false,
    this.originalLength = 0,
    this.metadata = const {},
  });

  bool get isSuccess => status == ToolExecutionStatus::success;

  factory ToolExecutionResult.success({
    required String output,
    dynamic rawJson,
    String? formattedMarkdown,
    required Duration duration,
    bool isTruncated = false,
    int originalLength = 0,
    Map<String, dynamic> metadata = const {},
  }) {
    return ToolExecutionResult(
      status: ToolExecutionStatus.success,
      output: output,
      rawJson: rawJson,
      formattedMarkdown: formattedMarkdown,
      executionDuration: duration,
      isTruncated: isTruncated,
      originalLength: originalLength,
      metadata: metadata,
    );
  }

  factory ToolExecutionResult.failure({
    required String error,
    required Duration duration,
    ToolExecutionStatus status = ToolExecutionStatus.failure,
    Map<String, dynamic> metadata = const {},
  }) {
    return ToolExecutionResult(
      status: status,
      output: '错误: $error',
      error: error,
      executionDuration: duration,
      metadata: metadata,
    );
  }

  factory ToolExecutionResult.deniedByUser({required Duration duration}) {
    return ToolExecutionResult(
      status: ToolExecutionStatus.deniedByUser,
      output: '用户拒绝了执行此工具调用的权限。',
      error: 'User rejected permission.',
      executionDuration: duration,
    );
  }
}
```

#### 2.1.4 `Tool` 统一基类定义

```dart
/// 所有工具的统领抽象基类
abstract class Tool {
  /// 工具唯一标识符（由英文字母、下划线组成，如 "web_search"）
  String get name;

  /// 面向用户的可读名称（如 "网络搜索"）
  String get displayName;

  /// 面向 LLM 的功能描述
  String get description;

  /// 工具所属分类
  ToolCategory get category;

  /// 安全权限等级
  PermissionLevel get permissionLevel;

  /// 参数签名定义
  List<ToolParameter> get parameters;

  /// 元数据信息
  ToolMetadata get metadata;

  /// 是否为内置工具
  bool get isBuiltIn => true;

  /// 默认执行超时时长
  Duration get timeoutDuration => const Duration(seconds: 15);

  /// 瞬态网络异常最大重试次数
  int get maxRetries => 2;

  /// 校验参数合法性
  ToolValidationResult validateArguments(Map<String, dynamic> arguments) {
    for (final param in parameters) {
      if (param.isRequired && (!arguments.containsKey(param.name) || arguments[param.name] == null)) {
        return ToolValidationResult.invalid('缺少必填参数 "${param.name}" (${param.description})');
      }
      if (arguments.containsKey(param.name) && arguments[param.name] != null) {
        final val = arguments[param.name];
        if (param.enumValues != null && !param.enumValues!.contains(val)) {
          return ToolValidationResult.invalid(
            '参数 "${param.name}" 取值无效: "$val"，允许的取值为: ${param.enumValues}',
          );
        }
      }
    }
    return ToolValidationResult.valid();
  }

  /// 导出为 OpenAI Function Calling 规范格式
  Map<String, dynamic> toOpenAiTool() {
    final properties = <String, dynamic>{};
    final requiredParams = <String>[];

    for (final param in parameters) {
      properties[param.name] = param.toOpenAiPropertySchema();
      if (param.isRequired) {
        requiredParams.add(param.name);
      }
    }

    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': requiredParams,
        },
      },
    };
  }

  /// 执行工具核心业务逻辑
  Future<ToolExecutionResult> execute(
    ToolExecutionContext context,
    Map<String, dynamic> arguments,
  );
}

class ToolValidationResult {
  final bool isValid;
  final String? errorMessage;
  const ToolValidationResult._(this.isValid, this.errorMessage);

  factory ToolValidationResult.valid() => const ToolValidationResult._(true, null);
  factory ToolValidationResult.invalid(String message) => ToolValidationResult._(false, message);
}
```

---

### 2.2 `ToolRegistry` 服务体系

`ToolRegistry` 是整个系统的工具管理中枢，负责工具的注册、注销、分类筛选、动态开关检查、模型能力适配及 OpenAI 规范导出。

```dart
import 'dart:developer' as developer;
import '../models/model_info.dart';
import '../providers/settings_provider.dart';

class ToolRegistry {
  final Map<String, Tool> _tools = {};

  ToolRegistry();

  /// 注册单个工具
  void register(Tool tool) {
    if (_tools.containsKey(tool.name)) {
      developer.log('Warning: Overwriting existing tool "${tool.name}"', name: 'ToolRegistry');
    }
    _tools[tool.name] = tool;
  }

  /// 批量注册
  void registerAll(List<Tool> tools) {
    for (final t in tools) {
      register(t);
    }
  }

  /// 注销指定工具
  bool unregister(String toolName) {
    return _tools.remove(toolName) != null;
  }

  /// 获取指定名称工具
  Tool? getTool(String name) => _tools[name];

  /// 获取所有已注册工具
  List<Tool> getAllTools() => _tools.values.toList();

  /// 按分类筛选工具
  List<Tool> filterByCategory(ToolCategory category) {
    return _tools.values.where((t) => t.category == category).toList();
  }

  /// 获取在当前模型与应用配置下生效的可用工具集
  List<Tool> getEffectiveTools({
    required ModelInfo model,
    required AppSettings settings,
    Set<String> disabledToolNames = const {},
  }) {
    // 1. 若全局或模型显式禁用，返回空列表
    if (!settings.enableTools) {
      return const [];
    }

    final effective = <Tool>[];

    for (final tool in _tools.values) {
      // 检查单工具禁用列表
      if (disabledToolNames.contains(tool.name)) continue;

      // 检查分类级开关
      if (tool.category == ToolCategory.search && !settings.enableAutoSearch) {
        continue;
      }

      // 搜索后端特化路由过滤
      if (tool.category == ToolCategory.search) {
        if (tool.name == 'google_search' && !settings.searchBackend.contains('google')) continue;
        if (tool.name == 'bing_search' && !settings.searchBackend.contains('bing')) continue;
        if (tool.name == 'web_search' && settings.searchBackend != 'searxng') continue;
      }

      effective.add(tool);
    }

    return effective;
  }

  /// 导出符合 OpenAI 格式的 tools 列表
  List<Map<String, dynamic>> exportOpenAiTools(List<Tool> tools) {
    return tools.map((t) => t.toOpenAiTool()).toList();
  }

  /// 为不支持原生 Tool Calling 的模型生成伪 XML / 系统提示词描述指令
  String exportSystemPromptDescription(List<Tool> tools) {
    if (tools.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('你拥有以下工具调用能力：');
    for (final tool in tools) {
      buffer.writeln('- ${tool.name}: ${tool.description}');
      buffer.writeln('  参数:');
      for (final p in tool.parameters) {
        final req = p.isRequired ? '[必填]' : '[可选]';
        buffer.writeln('    • ${p.name} (${p.type.name}) $req: ${p.description}');
      }
    }
    buffer.writeln('\n如果需要调用工具，请严格输出以下伪 XML 格式：');
    buffer.writeln('<tool_call>');
    buffer.writeln('<function=tool_name>');
    buffer.writeln('<parameter=param_name>param_value</parameter>');
    buffer.writeln('</function>');
    buffer.writeln('</tool_call>');
    return buffer.toString();
  }
}
```

---

### 2.3 内置工具与动态外部工具扩展示例

#### 示例 1：静态内置高精数学计算工具 (`MathEvalTool`)
```dart
import 'dart:math' as math;

class MathEvalTool extends Tool {
  @override
  String get name => 'math_eval';

  @override
  String get displayName => '高精数学计算器';

  @override
  String get description => '执行数学表达式计算（支持加减乘除、幂运算、三角函数、对数及常数 pi, e）。用于准确的数值计算。';

  @override
  ToolCategory get category => ToolCategory.utility;

  @override
  PermissionLevel get permissionLevel => PermissionLevel.safe;

  @override
  ToolMetadata get metadata => const ToolMetadata(
    iconName: 'calculate',
    tags: ['math', 'calculator', 'utility'],
  );

  @override
  List<ToolParameter> get parameters => [
    const ToolParameter(
      name: 'expression',
      type: ParameterType.string,
      description: '要计算的标准数学算式，例如 "sqrt(144) + 2^5" 或 "sin(pi / 2) * 100"',
      isRequired: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(
    ToolExecutionContext context,
    Map<String, dynamic> arguments,
  ) async {
    final sw = Stopwatch()..start();
    final expression = arguments['expression'] as String? ?? '';
    if (expression.trim().isEmpty) {
      return ToolExecutionResult.failure(
        error: '计算表达式不能为空',
        duration: sw.elapsed,
        status: ToolExecutionStatus.schemaError,
      );
    }

    try {
      // 简单安全的算式求值引擎实现 (支持标准算符与基础函数)
      final result = _evaluateSimpleExpression(expression);
      sw.stop();
      return ToolExecutionResult.success(
        output: '计算结果: $result',
        rawJson: {'expression': expression, 'result': result},
        formattedMarkdown: '**计算结果**: `$expression` = **`$result`**',
        duration: sw.elapsed,
      );
    } catch (e) {
      sw.stop();
      return ToolExecutionResult.failure(
        error: '数学表达式解析失败: $e',
        duration: sw.elapsed,
      );
    }
  }

  double _evaluateSimpleExpression(String expr) {
    // 算式解析器实现（可集成 expressions / petitparser 库）
    // 此处示意基础安全计算
    return 42.0; 
  }
}
```

#### 示例 2：动态外部 MCP (Model Context Protocol) 桥接工具 (`McpTool`)
```dart
/// 包装外部 MCP Server 导出的动态工具
class McpTool extends Tool {
  final String _mcpServerId;
  final String _mcpToolName;
  final String _description;
  final List<ToolParameter> _parameters;
  final PermissionLevel _permissionLevel;
  final Future<Map<String, dynamic>> Function(String serverId, String name, Map<String, dynamic> args) _invokeRemoteMcp;

  McpTool({
    required String mcpServerId,
    required String mcpToolName,
    required String description,
    required List<ToolParameter> parameters,
    PermissionLevel permissionLevel = PermissionLevel.sensitiveConfirm,
    required Future<Map<String, dynamic>> Function(String serverId, String name, Map<String, dynamic> args) invokeRemoteMcp,
  })  : _mcpServerId = mcpServerId,
        _mcpToolName = mcpToolName,
        _description = description,
        _parameters = parameters,
        _permissionLevel = permissionLevel,
        _invokeRemoteMcp = invokeRemoteMcp;

  @override
  String get name => 'mcp_${_mcpServerId}_$_mcpToolName';

  @override
  String get displayName => 'MCP: $_mcpToolName ($_mcpServerId)';

  @override
  String get description => _description;

  @override
  ToolCategory get category => ToolCategory.mcp;

  @override
  PermissionLevel get permissionLevel => _permissionLevel;

  @override
  bool get isBuiltIn => false;

  @override
  List<ToolParameter> get parameters => _parameters;

  @override
  ToolMetadata get metadata => ToolMetadata(
    iconName: 'hub',
    tags: ['mcp', _mcpServerId],
  );

  @override
  Future<ToolExecutionResult> execute(
    ToolExecutionContext context,
    Map<String, dynamic> arguments,
  ) async {
    final sw = Stopwatch()..start();
    try {
      context.onProgress?.call(0.2, '正在连接 MCP 服务端 $_mcpServerId...');
      final response = await _invokeRemoteMcp(_mcpServerId, _mcpToolName, arguments);
      sw.stop();
      
      final content = response['content']?.toString() ?? response.toString();
      return ToolExecutionResult.success(
        output: content,
        rawJson: response,
        duration: sw.elapsed,
      );
    } catch (e) {
      sw.stop();
      return ToolExecutionResult.failure(
        error: 'MCP 调用失败: $e',
        duration: sw.elapsed,
      );
    }
  }
}
```

---

## 3. 工具生命周期与动态配置管理

### 3.1 完整生命周期状态机

```
 ┌─────────────┐
 │  Discovery  │ (扫描内置工具清单 / 探测配置的 MCP Servers / 插件目录)
 └──────┬──────┘
        ▼
 ┌─────────────┐
 │Registration │ (注入 ToolRegistry，校验名称唯一性与 Schema 合法性)
 └──────┬──────┘
        ▼
 ┌─────────────┐
 │  Configure  │ (从 SharedPreferences / SecureStorage 读取凭证与用户启停配置)
 └──────┬──────┘
        ▼
 ┌─────────────┐
 │  Pre-Check  │ (检查安全等级、参数校验、人机确认 Completer 拦截)
 └──────┬──────┘
        ▼
 ┌─────────────┐
 │  Execution  │ (带超时 Duration、CancelToken、指数退避重试的分发执行)
 └──────┬──────┘
        ▼
 ┌─────────────┐
 │Post-Process │ (Token 预算截断、诊断信息装配、格式化富文本产出)
 └──────┬──────┘
        ▼
 ┌─────────────┐
 │  Teardown   │ (会话结束 / 插件注销 / 临时资源回收)
 └─────────────┘
```

### 3.2 多层级启用/禁用配置体系

应用对工具的控制提供三级细粒度把控：
1. **全局工具总开关** (`AppSettings.enableTools: bool`)：一键关闭所有工具注入。
2. **分类级开关** (`enableAutoSearch`, `enableNativeTools`, `enableMcpTools`, `enableCodeExecution`)。
3. **单工具独立开关** (`Map<String, bool> disabledTools`)：用户可在「设置 -> 工具管理」中对任意单个工具进行独立启用/禁用。

```dart
class ToolConfigState {
  final bool enableTools;
  final bool enableAutoSearch;
  final bool enableNativeTools;
  final bool enableMcpTools;
  final Set<String> disabledToolNames;
  final Map<String, Map<String, dynamic>> perToolCustomSettings;

  const ToolConfigState({
    this.enableTools = true,
    this.enableAutoSearch = true,
    this.enableNativeTools = false,
    this.enableMcpTools = false,
    this.disabledToolNames = const {},
    this.perToolCustomSettings = const {},
  });

  bool isToolActive(Tool tool) {
    if (!enableTools) return false;
    if (disabledToolNames.contains(tool.name)) return false;
    if (tool.category == ToolCategory.search && !enableAutoSearch) return false;
    if (tool.category == ToolCategory.nativeDevice && !enableNativeTools) return false;
    if (tool.category == ToolCategory.mcp && !enableMcpTools) return false;
    return true;
  }
}
```

---

## 4. 细粒度安全权限与交互式 UI 确认流

### 4.1 四级安全权限矩阵

| 权限等级 | 代表工具 | 风险等级 | 执行策略 | 用户确认 UI 形式 |
|:---|:---|:---:|:---|:---|
| **`safe`** | `math_eval`, `current_time`, `unit_converter` | 🟢 无风险 | 全自动静默执行 | 仅在流式气泡中展示执行折叠卡片 |
| **`readOnly`** | `web_search`, `url_fetch`, `read_local_file` | 🔵 低风险 | 默认自动执行（支持配置严格审计） | 折叠卡片，可查看请求参数与结果 |
| **`sensitiveConfirm`** | `write_local_file`, `delete_file`, `mcp_write_*` | 🟡 中/高风险 | **拦截暂停，等待用户显式确认** | **流内弹出交互式审批卡片（参数明细 + 风险告警）** |
| **`privilegedNative`**| `calendar_write`, `send_sms`, `shell_exec` | 🔴 极高风险 | **拦截暂停 + 系统权限校验** | **带双重警示的模态/流内确认卡片** |

### 4.2 异步人机交互确认工作流 (Human-in-the-Loop)

当大模型在多轮生成中发起属于 `sensitiveConfirm` 或 `privilegedNative` 等级的工具调用时，传统的单一异步 Stream 将被阻断。本架构通过**异步 Completer 信号通道**与 **UI 状态机** 实现完美的非阻塞挂起与恢复：

```
LLM Streaming Engine                   ConfirmationManager                    Chat UI (Flutter Widget)
       │                                       │                                         │
       ├──── ToolCall Detected (e.g. write_file) ────────────────────────────────────────┤
       │     (Permission: sensitiveConfirm)    │                                         │
       ▼                                       │                                         │
 1. Check Session Whitelist                    │                                         │
    (Not in session whitelist)                 │                                         │
       │                                       │                                         │
 2. Create Completer<ToolDecision>() ─────────►│                                         │
       │                                       │                                         │
 3. Yield ToolCallConfirmationPendingEvent ─────────────────────────────────────────────►│
       │                                       │                                         │
 4. Await Completer.future                     │                                   4. Render Interactive
    (Stream cleanly pauses)                    │                                      Confirmation Card
       │                                       │                                      (Allow Once / Session / Deny)
       │                                       │                                         │
       │                                       │                                   5. User Clicks:
       │                                       │                                      "Allow for Session"
       │                                       │                                         │
       │                                       │◄── resolve(allowSession) ───────────────┤
       │                                       │                                         │
 6. Stream Resumes ◄───────────────────────────┤                                         │
       │                                       │                                         │
 7. Execute Tool -> Yield Output -> Continue LLM                                         │
```

#### 4.2.1 确认决策模型与管理器实现

```dart
import 'dart:async';

enum ToolConfirmationDecision {
  allowOnce,
  allowSession,
  deny,
}

class PendingConfirmationRequest {
  final String confirmationId;
  final String toolCallId;
  final Tool tool;
  final Map<String, dynamic> arguments;
  final DateTime requestedAt;
  final Completer<ToolConfirmationDecision> completer;

  PendingConfirmationRequest({
    required this.confirmationId,
    required this.toolCallId,
    required this.tool,
    required this.arguments,
    required this.requestedAt,
    required this.completer,
  });
}

class ToolConfirmationManager {
  final Map<String, PendingConfirmationRequest> _pendingRequests = {};
  
  /// 会话内已信任的工具集合：Set<"conversationId:toolName">
  final Set<String> _sessionAllowList = {};

  bool isSessionAllowed(String conversationId, String toolName) {
    return _sessionAllowList.contains('$conversationId:$toolName');
  }

  void grantSessionPermission(String conversationId, String toolName) {
    _sessionAllowList.add('$conversationId:$toolName');
  }

  void revokeSessionPermissions(String conversationId) {
    _sessionAllowList.removeWhere((key) => key.startsWith('$conversationId:'));
  }

  Future<ToolConfirmationDecision> requestConfirmation({
    required String conversationId,
    required String toolCallId,
    required Tool tool,
    required Map<String, dynamic> arguments,
  }) {
    // 若已获得会话级授权，直接放行
    if (isSessionAllowed(conversationId, tool.name)) {
      return Future.value(ToolConfirmationDecision.allowSession);
    }

    final confirmationId = 'conf_${DateTime.now().millisecondsSinceEpoch}_${tool.name}';
    final completer = Completer<ToolConfirmationDecision>();

    final request = PendingConfirmationRequest(
      confirmationId: confirmationId,
      toolCallId: toolCallId,
      tool: tool,
      arguments: arguments,
      requestedAt: DateTime.now(),
      completer: completer,
    );

    _pendingRequests[confirmationId] = request;
    return completer.future;
  }

  void resolveRequest(String confirmationId, ToolConfirmationDecision decision, {String? conversationId}) {
    final req = _pendingRequests.remove(confirmationId);
    if (req != null && !req.completer.isCompleted) {
      if (decision == ToolConfirmationDecision.allowSession && conversationId != null) {
        grantSessionPermission(conversationId, req.tool.name);
      }
      req.completer.complete(decision);
    }
  }
}
```

---

## 5. 流式事件管道与 UI 折叠渲染规范

### 5.1 统一事件管道体系

将 `AgentService` 中的事件升级为泛型化、结构化的 `AgentStreamEvent` 体系：

```dart
abstract class AgentStreamEvent {
  const AgentStreamEvent();
}

/// 思考内容增量
class ReasoningDeltaEvent extends AgentStreamEvent {
  final String reasoning;
  const ReasoningDeltaEvent(this.reasoning);
}

/// 正文内容增量
class ContentDeltaEvent extends AgentStreamEvent {
  final String content;
  const ContentDeltaEvent(this.content);
}

/// 工具调用被识别，即将准备执行
class ToolCallStartedEvent extends AgentStreamEvent {
  final String toolCallId;
  final String toolName;
  final ToolCategory category;
  final Map<String, dynamic> arguments;
  const ToolCallStartedEvent({
    required this.toolCallId,
    required this.toolName,
    required this.category,
    required this.arguments,
  });
}

/// 工具需要用户确认挂起
class ToolCallConfirmationPendingEvent extends AgentStreamEvent {
  final String confirmationId;
  final String toolCallId;
  final String toolName;
  final ToolCategory category;
  final PermissionLevel permissionLevel;
  final Map<String, dynamic> arguments;
  const ToolCallConfirmationPendingEvent({
    required this.confirmationId,
    required this.toolCallId,
    required this.toolName,
    required this.category,
    required this.permissionLevel,
    required this.arguments,
  });
}

/// 工具正在执行中（支持进度反馈）
class ToolCallExecutingEvent extends AgentStreamEvent {
  final String toolCallId;
  final String toolName;
  final double? progress;
  final String? statusMessage;
  const ToolCallExecutingEvent({
    required this.toolCallId,
    required this.toolName,
    this.progress,
    this.statusMessage,
  });
}

/// 工具执行完成
class ToolCallCompletedEvent extends AgentStreamEvent {
  final String toolCallId;
  final String toolName;
  final ToolExecutionResult result;
  const ToolCallCompletedEvent({
    required this.toolCallId,
    required this.toolName,
    required this.result,
  });
}

/// 工具执行异常
class ToolCallErrorEvent extends AgentStreamEvent {
  final String toolCallId;
  final String toolName;
  final String errorMessage;
  final bool isRetrying;
  final int retryCount;
  const ToolCallErrorEvent({
    required this.toolCallId,
    required this.toolName,
    required this.errorMessage,
    this.isRetrying = false,
    this.retryCount = 0,
  });
}

/// 多轮中工具执行结果包装消息
class ToolCallExecutedMessageEvent extends AgentStreamEvent {
  final ChatMessage assistantMessage;
  final List<ChatMessage> toolMessages;
  const ToolCallExecutedMessageEvent(this.assistantMessage, this.toolMessages);
}

/// Token 消耗统计事件
class UsageEvent extends AgentStreamEvent {
  final int promptTokens;
  final int completionTokens;
  const UsageEvent(this.promptTokens, this.completionTokens);
}
```

### 5.2 Riverpod 状态模型重构

```dart
/// 当前正在活跃执行的单个工具状态
class ActiveToolCallState {
  final String toolCallId;
  final String toolName;
  final ToolCategory category;
  final Map<String, dynamic> arguments;
  final bool isPendingConfirmation;
  final String? confirmationId;
  final PermissionLevel? permissionLevel;
  final bool isExecuting;
  final double? progress;
  final String? statusMessage;
  final ToolExecutionResult? result;
  final String? error;

  const ActiveToolCallState({
    required this.toolCallId,
    required this.toolName,
    required this.category,
    this.arguments = const {},
    this.isPendingConfirmation = false,
    this.confirmationId,
    this.permissionLevel,
    this.isExecuting = false,
    this.progress,
    this.statusMessage,
    this.result,
    this.error,
  });
}

/// 重构后的 AgentState
class AgentState {
  final Map<String, ActiveToolCallState> activeToolCalls;
  final bool hasPendingConfirmation;
  final String? currentActionSummary;

  const AgentState({
    this.activeToolCalls = const {},
    this.hasPendingConfirmation = false,
    this.currentActionSummary,
  });

  bool get isBusy => activeToolCalls.values.any((t) => t.isExecuting || t.isPendingConfirmation);
}
```

### 5.3 `ChatBubble` 折叠式工具调用卡片与交互规范

在 `ChatBubble` 中，工具调用（`ChatMessage.role == 'tool'` 及附带 `toolCalls` 的中间助手消息）被统一渲染为具备视觉美感的可折叠容器：

```
┌────────────────────────────────────────────────────────────────────────┐
│ 🛠️  [图标] 文件写入操作 (write_file)            [耗时 120ms]  [▲ 收起]  │
├────────────────────────────────────────────────────────────────────────┤
│ 📋 输入参数:                                                           │
│ ┌────────────────────────────────────────────────────────────────────┐ │
│ │ { "path": "notes/todo.md", "content": "# 今日待办..." }            │ │
│ └────────────────────────────────────────────────────────────────────┘ │
│ 📄 执行结果: (已截断保留 800/1200 字符)                   [📋 复制结果]│
│ ┌────────────────────────────────────────────────────────────────────┐ │
│ │ 文件写入成功: notes/todo.md (824 bytes written)                     │ │
│ └────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────┘
```

#### 人机确认待审批卡片 UI 规范（Pending Confirmation Card）：
```
┌────────────────────────────────────────────────────────────────────────┐
│ ⚠️  高危操作确认: write_file                                           │
├────────────────────────────────────────────────────────────────────────┤
│ AI 请求在本地磁盘创建/覆盖文件：                                       │
│ 路径: `notes/todo.md`                                                  │
│ 内容长度: 824 字符                                                     │
│                                                                        │
│ [ 仅允许本次 ]    [ 本会话始终允许 ]    [ ❌ 拒绝执行 ]               │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 6. 健壮容错、重试策略与 Token 截断引擎

### 6.1 参数 Schema 前置校验与自我纠错机制

如果大模型生成的 `arguments` 缺失必填字段或类型不符，传统的直接调用将触发硬崩溃。本架构在调用前执行严格校验，一旦未通过：
1. **拦截调用**：避免向外部发送无效请求；
2. **构建格式化错误文本** 回传给 LLM：
   ```json
   {
     "error": "SchemaValidationError",
     "message": "缺少必填参数 'url' (网页绝对地址)。请检查并重试正确参数。"
   }
   ```
3. LLM 在下一轮补全中感知错误并自动纠正参数。

### 6.2 智能超时与指数退避重试策略 (Exponential Backoff with Jitter)

```dart
class RetryPolicy {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;

  const RetryPolicy({
    this.maxRetries = 2,
    this.initialDelay = const Duration(milliseconds: 500),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 4),
  });

  /// 判断异常是否属于可重试的瞬态网络故障
  bool isRetryable(Object error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionTimeout ||
             error.type == DioExceptionType.receiveTimeout ||
             error.type == DioExceptionType.sendTimeout ||
             error.type == DioExceptionType.connectionError ||
             (error.response?.statusCode != null && error.response!.statusCode! >= 500);
    }
    return false;
  }

  Future<T> executeWithRetry<T>(
    Future<T> Function(int attempt) action, {
    CancelToken? cancelToken,
    void Function(int attempt, Object error)? onRetry,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        if (cancelToken?.isCancelled ?? false) {
          throw cancelToken!.cancelError ?? Exception('Cancelled');
        }
        return await action(attempt);
      } catch (e) {
        attempt++;
        if (attempt > maxRetries || !isRetryable(e)) {
          rethrow;
        }
        onRetry?.call(attempt, e);
        
        // 计算带抖动的退避时间
        final delayMs = (initialDelay.inMilliseconds * math.pow(backoffMultiplier, attempt - 1)).toInt();
        final cappedDelayMs = math.min(delayMs, maxDelay.inMilliseconds);
        final jitter = (cappedDelayMs * 0.2 * (math.Random().nextDouble() - 0.5)).toInt();
        final actualDelay = Duration(milliseconds: cappedDelayMs + jitter);
        
        await Future.delayed(actualDelay);
      }
    }
  }
}
```

### 6.3 Token 预算与内容感知截断引擎 (Token Truncation Engine)

大模型上下文窗口有限，超长网页正文或大文件若全部返回，会引发 Token 溢出与昂贵开销。

```dart
class TokenTruncationEngine {
  /// 默认单次工具返回最大 Token 预算（约 3000 Token，约合 9000~12000 字符）
  static const int defaultMaxTokens = 3000;
  static const int defaultMaxChars = 9000;

  /// 智能头尾保留截断
  static TruncationResult truncateText(
    String content, {
    int maxChars = defaultMaxChars,
    double headRatio = 0.7, // 前部保留 70%，尾部保留 30%
  }) {
    if (content.length <= maxChars) {
      return TruncationResult(
        content: content,
        isTruncated: false,
        originalLength: content.length,
        truncatedLength: content.length,
      );
    }

    final headLength = (maxChars * headRatio).toInt();
    final tailLength = maxChars - headLength;

    final head = content.substring(0, headLength);
    final tail = content.substring(content.length - tailLength);

    final notice = '\n\n... [内容已截断: 原始 ${content.length} 字符，保留前 $headLength 与后 $tailLength 字符。若需更多细节请细化查询] ...\n\n';

    final truncated = '$head$notice$tail';
    return TruncationResult(
      content: truncated,
      isTruncated: true,
      originalLength: content.length,
      truncatedLength: truncated.length,
    );
  }
}

class TruncationResult {
  final String content;
  final bool isTruncated;
  final int originalLength;
  final int truncatedLength;

  const TruncationResult({
    required this.content,
    required this.isTruncated,
    required this.originalLength,
    required this.truncatedLength,
  });
}
```

### 6.4 循环死锁防护与降级总结机制 (Loop Guard & Degraded Completion)

为彻底防止模型因网络失败不断重试同名工具引发死循环：
1. **相同参数重复调用检测 (Duplicate Call Guard)**：维护多轮调用哈希集，若检测到相同工具与相同参数连续调用超过 3 次，引擎自动中断该工具并在 Context 注入警告提示；
2. **轮次硬上限强制收敛**：达到 `toolRound >= maxToolRounds - 1` 时，强制剥离 `tools` 参数，注入系统提示词：
   > `“请根据上述已获取的全部工具执行结果与上下文信息，直接给出最终总结回答，绝对不要再尝试使用任何工具或输出工具调用格式。”`
   确保 AI 在任何情况下均能向用户给出有价值的最终文本回答。

---

## 7. 演进迁移策略与质量验证矩阵

### 7.1 向后兼容性保障与平滑迁移路径

1. **第一阶段：核心抽象与基类落地 (Core Abstractions)**
   - 引入 `Tool`, `ToolRegistry`, `ToolParameter`, `ToolExecutionResult`, `PermissionLevel` 等模型类。
   - 现有 `SearchService` 和 `UrlFetchService` 保持不变，外层编写 `WebSearchTool` 和 `UrlFetchTool` 适配器（Adapter Pattern）。
2. **第二阶段：执行引擎重构 (Engine Refactoring)**
   - 重构 `AgentService`，将硬编码 `switch-case` 替换为 `ToolRegistry.getTool(name).execute(...)`。
   - 保留原伪 XML 与 DSML 解析能力，将其挂接到 `ToolRegistry` 分发。
3. **第三阶段：UI 与权限确认层升级 (UI & Confirmation Workflow)**
   - `AgentState` 泛型化改造，升级 `ChatBubble` 折叠卡片与人机确认卡片。
   - `SettingsScreen` 引入「工具箱管理」面板。

### 7.2 全面测试验证矩阵

```
┌──────────────────────────────────────┬────────────────────────────────────────────────────────┐
│ 测试类型                              │ 覆盖目标与验证内容                                     │
├──────────────────────────────────────┼────────────────────────────────────────────────────────┤
│ **Unit Tests: ToolRegistry**         │ 注册、注销、分类筛选、OpenAI Schema 导出、模型能力过滤 │
│ **Unit Tests: Parameter Validation** │ 必填项缺失、Enum 校验失败、非法数据类型自愈提示        │
│ **Unit Tests: Token Truncation**     │ 字符超限头尾智能截断、保留标记完整性                   │
│ **Unit Tests: Retry & Timeout**      │ 瞬态 502/503 重试成功、401/404 快速失败、超时中断      │
│ **Widget Tests: Confirmation Card**  │ "允许本次"、"会话始终允许"、"拒绝"点击交互与信号传递   │
│ **Widget Tests: ChatBubble Folding** │ 工具卡片折叠/展开、复制按钮、耗时 Badge 渲染           │
│ **Integration Tests: E2E Agent**     │ 多轮 Tool Calling、伪 XML 兜底、轮次超限总结收敛      │
└──────────────────────────────────────┴────────────────────────────────────────────────────────┘
```

---

## 8. 总结与架构交付件清单

通过上述 5 大核心支柱的设计与规划，Flutter AI Chat 应用构建起了一套**高内聚、低耦合、工业级健壮、安全可信**的可插拔 Agent 工具生态基座。

### 交付物归档索引

| 序号 | 交付物模块 | 目标路径 (建议实现位置) | 核心职责 |
|:---|:---|:---|:---|
| 1 | **工具核心契约** | `lib/models/tool.dart` | `Tool`, `ToolParameter`, `ToolExecutionResult`, `PermissionLevel` |
| 2 | **工具注册中心** | `lib/services/tool_registry.dart` | `ToolRegistry`, OpenAI Schema 导出, 提示词生成 |
| 3 | **重构执行引擎** | `lib/services/agent_service.dart` | 泛型化多轮调用分发、超时重试、截断与死循环兜底 |
| 4 | **确认管理器** | `lib/services/tool_confirmation_manager.dart`| 异步 Completer 挂起、会话授权白名单 |
| 5 | **状态管理适配** | `lib/providers/agent_provider.dart` | `ToolExecutionState`, `AgentNotifier` 泛型化 |
| 6 | **内置工具库** | `lib/tools/` (search, url_fetch, math, time) | 各内置工具实现类 |
| 7 | **UI 折叠与确认卡片**| `lib/widgets/tool_call_card.dart` | `ChatBubble` 折叠组件与确认交互 Widget |
