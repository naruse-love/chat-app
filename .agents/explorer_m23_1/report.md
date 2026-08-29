# Milestone 23.1 Design Specification: Pluggable Tool Architecture & ToolRegistry

## 1. Executive Summary

Milestone 23.1 establishes the foundational architecture for pluggable tools in the Flutter AI Agent application (`chat-app`). It introduces:
1. **Model Layer (`lib/models/tool/`)**:
   - `tool_security_level.dart`: 4-level security model (`safe`, `readOnly`, `sensitiveConfirm`, `privilegedNative`).
   - `tool_parameter.dart`: Standardized parameter descriptor with type validation, enum constraints, and OpenAI JSON schema export.
   - `tool_execution_result.dart`: Structured execution result with success/failure factories, markdown rendering, raw data encapsulation, and execution duration metrics.
   - `tool.dart`: Abstract base class `Tool` defining name, displayName, description, security level, parameters, schema generation, argument validation, and async execution.
2. **Registry Layer (`lib/services/tool_registry.dart`)**:
   - `ToolRegistry`: Dynamic and static tool registration, deregistration, lookup, runtime enable/disable state management, OpenAI Function Calling JSON Schema export with security level & name filtering, and safe execution dispatching with validation and exception handling.
   - Global Riverpod provider `toolRegistryProvider`.
3. **Legacy Tool Adapters (`lib/services/tools/legacy_tool_adapters.dart`)**:
   - `WebSearchTool` (`web_search`), `GoogleSearchTool` (`google_search`), `BingSearchTool` (`bing_search`), and `UrlFetchTool` (`url_fetch`).
   - 100% backward compatible with existing OpenAI function calling parameters, `SearchService`, and `UrlFetchService`.
4. **Comprehensive Test Suite**:
   - `test/models/tool_model_test.dart` (data models, parameter validation, schema export, serialization).
   - `test/services/tool_registry_test.dart` (registry CRUD, enablement toggling, schema export filtering, execution dispatcher, legacy adapter integration, Riverpod provider).

---

## 2. Architecture & Class Hierarchy

```
lib/
├── models/
│   └── tool/
│       ├── tool_security_level.dart   <-- 4-level security classification enum
│       ├── tool_parameter.dart        <-- Parameter descriptors & validator
│       ├── tool_execution_result.dart <-- Structured execution result
│       └── tool.dart                  <-- Abstract Tool base class (exports all tool models)
└── services/
    ├── tool_registry.dart             <-- Central ToolRegistry & toolRegistryProvider
    └── tools/
        └── legacy_tool_adapters.dart  <-- WebSearchTool, GoogleSearchTool, BingSearchTool, UrlFetchTool
```

```
           +----------------------------------------------------+
           |                       Tool                         |
           |----------------------------------------------------|
           | + name: String                                     |
           | + displayName: String                              |
           | + description: String                              |
           | + securityLevel: ToolSecurityLevel                 |
           | + parameters: List<ToolParameter>                  |
           | + toOpenAiSchema(): Map<String, dynamic>           |
           | + validateArguments(args): String?                 |
           | + execute(args): Future<ToolExecutionResult>       |
           +----------------------------------------------------+
                                     ▲
                                     │ (extends)
         +-----------------+---------+---------+------------------+
         |                 |                   |                  |
+-----------------+ +------------------+ +----------------+ +----------------+
|  WebSearchTool  | | GoogleSearchTool | | BingSearchTool | |  UrlFetchTool  |
+-----------------+ +------------------+ +----------------+ +----------------+
```

---

## 3. Concrete Code Specifications

### 3.1 Model Layer: `lib/models/tool/tool_security_level.dart`

```dart
/// 4-level security classification for Agent tools.
enum ToolSecurityLevel {
  /// Level 0: Safe / Pure computation.
  /// Zero permissions, zero side effects, purely deterministic, idempotent.
  /// Safe to auto-execute without confirmation (e.g., math_eval, time_calculator).
  safe(0, '安全', '纯本地计算与无副作用工具，可直接自动执行'),

  /// Level 1: Read-only network or system query.
  /// Network requests or read-only information retrieval with no state mutation.
  /// (e.g., web_search, google_search, bing_search, url_fetch, weather_query, wiki_lookup).
  readOnly(1, '只读', '只读网络或本地信息检索，不修改任何持久化状态'),

  /// Level 2: Sensitive state mutation / write operations.
  /// Modifies local or remote user state; requires user UI confirmation before execution.
  /// (e.g., local file write, calendar event create, reminder schedule).
  sensitiveConfirm(2, '敏感确认', '涉及状态修改或敏感操作，执行前需用户显式确认'),

  /// Level 3: Privileged native / system execution.
  /// High-risk device or operating system level privileges.
  /// (e.g., shell command execution, camera/contacts export, device settings).
  privilegedNative(3, '特权原生', '涉及系统级特权或原生设备权限，高风险操作');

  final int level;
  final String label;
  final String description;

  const ToolSecurityLevel(this.level, this.label, this.description);

  /// Whether this tool requires user confirmation before execution.
  bool get requiresConfirmation => level >= 2;

  /// Whether this tool is safe for automated execution without UI interruption.
  bool get isSafeToAutoExecute => level < 2;

  /// Serialization helper.
  String toJson() => name;

  /// Deserialization from String name.
  static ToolSecurityLevel fromJson(String name) {
    return ToolSecurityLevel.values.firstWhere(
      (e) => e.name == name || e.name.toLowerCase() == name.toLowerCase(),
      orElse: () => ToolSecurityLevel.safe,
    );
  }

  /// Deserialization from integer level value.
  static ToolSecurityLevel fromLevel(int level) {
    return ToolSecurityLevel.values.firstWhere(
      (e) => e.level == level,
      orElse: () => ToolSecurityLevel.safe,
    );
  }
}
```

---

### 3.2 Model Layer: `lib/models/tool/tool_parameter.dart`

```dart
/// Structured definition for an Agent tool parameter.
class ToolParameter {
  /// Parameter identifier (e.g. 'query', 'url', 'expression', 'timezone').
  final String name;

  /// JSON Schema primitive type: 'string', 'number', 'integer', 'boolean', 'array', 'object'.
  final String type;

  /// Human-readable and LLM-targeted description of this parameter.
  final String description;

  /// Whether this parameter is mandatory for tool execution. Default: true.
  final bool required;

  /// Optional enum constraints (allowed string values).
  final List<String>? enumValues;

  /// Optional default value if omitted by LLM.
  final dynamic defaultValue;

  /// Optional item type if [type] == 'array' (e.g. 'string', 'object').
  final String? arrayItemType;

  const ToolParameter({
    required this.name,
    required this.description,
    this.type = 'string',
    this.required = true,
    this.enumValues,
    this.defaultValue,
    this.arrayItemType,
  });

  /// Converts this parameter descriptor into an OpenAI Function Calling JSON Schema property map.
  Map<String, dynamic> toOpenAiSchema() {
    final map = <String, dynamic>{
      'type': type,
      'description': description,
    };
    if (enumValues != null && enumValues!.isNotEmpty) {
      map['enum'] = enumValues;
    }
    if (defaultValue != null) {
      map['default'] = defaultValue;
    }
    if (type == 'array' && arrayItemType != null) {
      map['items'] = {'type': arrayItemType};
    }
    return map;
  }

  /// Serialization to standard Map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'description': description,
      'required': required,
      if (enumValues != null) 'enumValues': enumValues,
      if (defaultValue != null) 'defaultValue': defaultValue,
      if (arrayItemType != null) 'arrayItemType': arrayItemType,
    };
  }

  /// Deserialization from Map.
  factory ToolParameter.fromJson(Map<String, dynamic> json) {
    return ToolParameter(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'string',
      required: json['required'] as bool? ?? true,
      enumValues: (json['enumValues'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      defaultValue: json['defaultValue'],
      arrayItemType: json['arrayItemType'] as String?,
    );
  }

  /// Validates a supplied runtime argument against this parameter's constraints.
  /// Returns null if valid, or a descriptive Chinese error string if invalid.
  String? validate(dynamic value) {
    if (value == null) {
      if (required) {
        return "缺少必需参数 '$name'";
      }
      return null;
    }

    switch (type) {
      case 'string':
        if (value is! String) {
          return "参数 '$name' 应为字符串类型 (string)，实际为 ${value.runtimeType}";
        }
        if (enumValues != null && enumValues!.isNotEmpty && !enumValues!.contains(value)) {
          return "参数 '$name' 值 '$value' 不在允许的枚举范围 [${enumValues!.join(', ')}] 内";
        }
        break;
      case 'number':
        if (value is! num && (value is! String || num.tryParse(value) == null)) {
          return "参数 '$name' 应为数值类型 (number)，实际为 '$value'";
        }
        break;
      case 'integer':
        if (value is! int && (value is! String || int.tryParse(value) == null)) {
          return "参数 '$name' 应为整数类型 (integer)，实际为 '$value'";
        }
        break;
      case 'boolean':
        if (value is! bool && value != 'true' && value != 'false') {
          return "参数 '$name' 应为布尔类型 (boolean)，实际为 '$value'";
        }
        break;
      case 'array':
        if (value is! List) {
          return "参数 '$name' 应为列表类型 (array)，实际为 ${value.runtimeType}";
        }
        break;
      case 'object':
        if (value is! Map) {
          return "参数 '$name' 应为对象类型 (object)，实际为 ${value.runtimeType}";
        }
        break;
    }
    return null;
  }
}
```

---

### 3.3 Model Layer: `lib/models/tool/tool_execution_result.dart`

```dart
/// Structured output returned after an Agent tool execution.
class ToolExecutionResult {
  /// Unique identifier of the tool that generated this result.
  final String toolName;

  /// Whether the execution completed successfully.
  final bool success;

  /// Formatted text/markdown content to inject into LLM context and render in UI.
  final String content;

  /// Structured / raw output data (Map, List, or domain object) for programmatic inspection.
  final dynamic rawData;

  /// User-facing error message in Chinese if execution failed (null on success).
  final String? errorMessage;

  /// Execution duration measured via Stopwatch.
  final Duration executionDuration;

  /// Execution timestamp.
  final DateTime timestamp;

  /// Additional metadata (e.g. backend, HTTP status, page count, warnings).
  final Map<String, dynamic>? metadata;

  ToolExecutionResult({
    required this.toolName,
    required this.success,
    required this.content,
    this.rawData,
    this.errorMessage,
    this.executionDuration = Duration.zero,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Factory for successful execution.
  factory ToolExecutionResult.success({
    required String toolName,
    required String content,
    dynamic rawData,
    Duration executionDuration = Duration.zero,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return ToolExecutionResult(
      toolName: toolName,
      success: true,
      content: content,
      rawData: rawData,
      errorMessage: null,
      executionDuration: executionDuration,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Factory for failed execution.
  factory ToolExecutionResult.failure({
    required String toolName,
    required String errorMessage,
    String? content,
    dynamic rawData,
    Duration executionDuration = Duration.zero,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return ToolExecutionResult(
      toolName: toolName,
      success: false,
      content: content ?? '执行失败: $errorMessage',
      rawData: rawData,
      errorMessage: errorMessage,
      executionDuration: executionDuration,
      timestamp: timestamp,
      metadata: metadata,
    );
  }

  /// Converts this result into a map for serialization.
  Map<String, dynamic> toJson() {
    return {
      'toolName': toolName,
      'success': success,
      'content': content,
      if (rawData != null) 'rawData': rawData,
      if (errorMessage != null) 'errorMessage': errorMessage,
      'executionDurationMs': executionDuration.inMilliseconds,
      'timestamp': timestamp.toIso8601String(),
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Deserializes a result from a map.
  factory ToolExecutionResult.fromJson(Map<String, dynamic> json) {
    return ToolExecutionResult(
      toolName: json['toolName'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      content: json['content'] as String? ?? '',
      rawData: json['rawData'],
      errorMessage: json['errorMessage'] as String?,
      executionDuration: Duration(milliseconds: json['executionDurationMs'] as int? ?? 0),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Returns the text content for a ChatMessage(role: 'tool').
  String toToolMessageContent() => content;

  @override
  String toString() {
    return 'ToolExecutionResult(tool: $toolName, success: $success, duration: ${executionDuration.inMilliseconds}ms)';
  }
}
```

---

### 3.4 Model Layer: `lib/models/tool/tool.dart`

```dart
import 'tool_parameter.dart';
import 'tool_security_level.dart';
import 'tool_execution_result.dart';

export 'tool_parameter.dart';
export 'tool_security_level.dart';
export 'tool_execution_result.dart';

/// Abstract base contract for all pluggable Agent tools.
abstract class Tool {
  const Tool();

  /// Unique programmatic identifier (e.g. 'web_search', 'math_eval', 'wiki_lookup').
  String get name;

  /// Human-friendly localized display name (e.g. '网络搜索', '数学计算器').
  String get displayName;

  /// Functional description passed to LLM for function calling matching.
  String get description;

  /// Security classification level (Level 0 safe to Level 3 privileged).
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.safe;

  /// List of parameter descriptors accepted by this tool.
  List<ToolParameter> get parameters => const [];

  /// Exports standard OpenAI Function Calling JSON Schema.
  Map<String, dynamic> toOpenAiSchema() {
    final properties = <String, dynamic>{};
    final requiredList = <String>[];

    for (final param in parameters) {
      properties[param.name] = param.toOpenAiSchema();
      if (param.required) {
        requiredList.add(param.name);
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
          'required': requiredList,
        },
      },
    };
  }

  /// Validates input arguments against defined [parameters].
  /// Returns `null` if arguments are valid, or a descriptive Chinese error message.
  String? validateArguments(Map<String, dynamic> arguments) {
    for (final param in parameters) {
      final value = arguments[param.name];
      final error = param.validate(value);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  /// Executes the tool logic with arguments.
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments);
}
```

---

### 3.5 Registry Layer: `lib/services/tool_registry.dart`

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool/tool.dart';
import 'tools/legacy_tool_adapters.dart';
import 'search_service.dart';
import 'url_fetch_service.dart';

/// Central registry managing registration, state, schema export, and execution dispatching for all Agent tools.
class ToolRegistry {
  final Map<String, Tool> _tools = {};
  final Map<String, bool> _enabledStates = {};

  ToolRegistry();

  /// Pre-populates a default registry containing built-in search and fetch adapters.
  factory ToolRegistry.defaultRegistry({
    SearchService? searchService,
    UrlFetchService? urlFetchService,
  }) {
    final registry = ToolRegistry();
    registry.registerTools([
      WebSearchTool(searchService: searchService),
      GoogleSearchTool(searchService: searchService),
      BingSearchTool(searchService: searchService),
      UrlFetchTool(urlFetchService: urlFetchService),
    ]);
    return registry;
  }

  /// Registers a tool. If a tool with the same [tool.name] exists, it will be updated.
  void register(Tool tool, {bool enabled = true}) {
    _tools[tool.name] = tool;
    _enabledStates[tool.name] = enabled;
  }

  /// Alias for [register].
  void registerTool(Tool tool, {bool enabled = true}) => register(tool, enabled: enabled);

  /// Registers multiple tools at once.
  void registerTools(List<Tool> tools, {bool enabled = true}) {
    for (final tool in tools) {
      register(tool, enabled: enabled);
    }
  }

  /// Unregisters a tool by name. Returns true if removed, false otherwise.
  bool unregister(String name) {
    _enabledStates.remove(name);
    return _tools.remove(name) != null;
  }

  /// Alias for [unregister].
  bool unregisterTool(String name) => unregister(name);

  /// Clears all registered tools and their enablement states.
  void clear() {
    _tools.clear();
    _enabledStates.clear();
  }

  /// Checks whether a tool is registered.
  bool hasTool(String name) => _tools.containsKey(name);

  /// Retrieves a registered [Tool] by name, or null if not found.
  Tool? getTool(String name) => _tools[name];

  /// Returns an unmodifiable list of all registered tools.
  List<Tool> getAllTools() => List.unmodifiable(_tools.values);

  /// Returns all currently enabled tools.
  List<Tool> getEnabledTools() {
    return _tools.values.where((tool) => isToolEnabled(tool.name)).toList();
  }

  /// Returns all registered tool names.
  List<String> getRegisteredNames() => List.unmodifiable(_tools.keys);

  /// Returns names of all enabled tools.
  List<String> getEnabledNames() {
    return _tools.keys.where((name) => isToolEnabled(name)).toList();
  }

  /// Toggles enablement of a specific tool.
  void setToolEnabled(String name, bool enabled) {
    if (_tools.containsKey(name)) {
      _enabledStates[name] = enabled;
    }
  }

  /// Checks whether a tool is enabled. Returns false if tool is not registered.
  bool isToolEnabled(String name) {
    if (!_tools.containsKey(name)) return false;
    return _enabledStates[name] ?? true;
  }

  /// Enables all registered tools.
  void enableAll() {
    for (final key in _tools.keys) {
      _enabledStates[key] = true;
    }
  }

  /// Disables all registered tools.
  void disableAll() {
    for (final key in _tools.keys) {
      _enabledStates[key] = false;
    }
  }

  /// Resets all registered tools to enabled state.
  void resetEnablement() => enableAll();

  /// Exports OpenAI Function Calling JSON Schema definitions for tools.
  ///
  /// Filters:
  /// - [toolNames]: If provided, only includes tools in this list.
  /// - [onlyEnabled]: If true (default), only exports tools where [isToolEnabled] is true.
  /// - [maxSecurityLevel]: If provided, only exports tools with `securityLevel.level <= maxSecurityLevel.level`.
  List<Map<String, dynamic>> exportOpenAiSchemas({
    List<String>? toolNames,
    bool onlyEnabled = true,
    ToolSecurityLevel? maxSecurityLevel,
  }) {
    final schemas = <Map<String, dynamic>>[];

    for (final tool in _tools.values) {
      if (toolNames != null && !toolNames.contains(tool.name)) {
        continue;
      }
      if (onlyEnabled && !isToolEnabled(tool.name)) {
        continue;
      }
      if (maxSecurityLevel != null && tool.securityLevel.level > maxSecurityLevel.level) {
        continue;
      }
      schemas.add(tool.toOpenAiSchema());
    }

    return schemas;
  }

  /// Dispatches tool execution by name with arguments and optional execution context.
  ///
  /// Guarantees:
  /// 1. Verifies existence and enablement state.
  /// 2. Performs parameter validation before execution.
  /// 3. Injects context securely.
  /// 4. Measures execution duration via Stopwatch.
  /// 5. Catches all exceptions and returns a structured failure result.
  Future<ToolExecutionResult> execute(
    String name,
    Map<String, dynamic> arguments, {
    Map<String, dynamic>? context,
  }) async {
    final stopwatch = Stopwatch()..start();

    final tool = _tools[name];
    if (tool == null) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: "未找到工具 '$name'，该工具未在注册中心注册。",
        executionDuration: stopwatch.elapsed,
      );
    }

    if (!isToolEnabled(name)) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: "工具 '$name' 当前已被禁用。",
        executionDuration: stopwatch.elapsed,
      );
    }

    // Merge context into arguments
    final effectiveArgs = Map<String, dynamic>.from(arguments);
    if (context != null) {
      for (final entry in context.entries) {
        effectiveArgs.putIfAbsent('__${entry.key}', () => entry.value);
        effectiveArgs.putIfAbsent(entry.key, () => entry.value);
      }
    }

    // Validate parameters
    final validationError = tool.validateArguments(effectiveArgs);
    if (validationError != null) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: "参数校验失败: $validationError",
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final result = await tool.execute(effectiveArgs);
      stopwatch.stop();
      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: "工具执行异常: $e",
        content: "工具 [$name] 执行失败: $e",
        executionDuration: stopwatch.elapsed,
        metadata: {'exception': e.toString(), 'stackTrace': stackTrace.toString()},
      );
    }
  }
}

/// Global Riverpod Provider for ToolRegistry.
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  return ToolRegistry.defaultRegistry();
});
```

---

### 3.6 Legacy Tool Adapters: `lib/services/tools/legacy_tool_adapters.dart`

```dart
import 'package:dio/dio.dart';
import '../../models/tool/tool.dart';
import '../search_service.dart';
import '../url_fetch_service.dart';

/// Legacy adapter for standard SearXNG web search (`web_search`).
class WebSearchTool extends Tool {
  final SearchService searchService;
  final String? searxngUrl;

  WebSearchTool({
    SearchService? searchService,
    this.searxngUrl,
  }) : searchService = searchService ?? SearchService();

  @override
  String get name => 'web_search';

  @override
  String get displayName => '网络搜索';

  @override
  String get description => 'Search the web for up-to-date information on a given topic.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'query',
      type: 'string',
      description: 'The query to search for on the web.',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final query = (arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '搜索关键词不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final effectiveSearxngUrl = arguments['searxngUrl'] as String? ??
          arguments['__searxngUrl'] as String? ??
          searxngUrl;

      final results = await searchService.search(
        query: query,
        searxngUrl: effectiveSearxngUrl,
        searchBackend: 'searxng',
      );
      stopwatch.stop();

      final formatted = searchService.formatSearchResultsForContext(results);
      return ToolExecutionResult.success(
        toolName: name,
        content: formatted,
        rawData: results,
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'resultCount': results.length,
          'backend': 'searxng',
        },
      );
    } on SearchException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '搜索失败：${e.message}',
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'source': e.source,
          'statusCode': e.statusCode,
          'details': e.details,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '搜索出现未知异常: $e',
        content: '搜索失败：$e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}

/// Legacy adapter for Google Grounding search (`google_search`).
class GoogleSearchTool extends Tool {
  final SearchService searchService;
  final String? googleApiKey;
  final String? googleBaseUrl;
  final String? googleSearchModel;

  GoogleSearchTool({
    SearchService? searchService,
    this.googleApiKey,
    this.googleBaseUrl,
    this.googleSearchModel,
  }) : searchService = searchService ?? SearchService();

  @override
  String get name => 'google_search';

  @override
  String get displayName => 'Google 搜索';

  @override
  String get description => 'Search Google for up-to-date information on a given topic.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'query',
      type: 'string',
      description: 'The search query for Google.',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final query = (arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '搜索关键词不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final apiKey = arguments['googleApiKey'] as String? ??
          arguments['__googleApiKey'] as String? ??
          googleApiKey;
      final baseUrl = arguments['googleBaseUrl'] as String? ??
          arguments['__googleBaseUrl'] as String? ??
          googleBaseUrl;
      final model = arguments['googleSearchModel'] as String? ??
          arguments['__googleSearchModel'] as String? ??
          googleSearchModel;

      final results = await searchService.search(
        query: query,
        searchBackend: 'google',
        googleApiKey: apiKey,
        googleBaseUrl: baseUrl,
        googleSearchModel: model,
      );
      stopwatch.stop();

      final formatted = searchService.formatSearchResultsForContext(results);
      return ToolExecutionResult.success(
        toolName: name,
        content: formatted,
        rawData: results,
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'resultCount': results.length,
          'backend': 'google',
        },
      );
    } on SearchException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '搜索失败：${e.message}',
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'source': e.source,
          'statusCode': e.statusCode,
          'details': e.details,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: 'Google 搜索出现异常: $e',
        content: '搜索失败：$e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}

/// Legacy adapter for Bing search (`bing_search`).
class BingSearchTool extends Tool {
  final SearchService searchService;
  final String? bingCookie;

  BingSearchTool({
    SearchService? searchService,
    this.bingCookie,
  }) : searchService = searchService ?? SearchService();

  @override
  String get name => 'bing_search';

  @override
  String get displayName => 'Bing 搜索';

  @override
  String get description => 'Search Bing for up-to-date information on a given topic.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'query',
      type: 'string',
      description: 'The search query for Bing.',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final query = (arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '搜索关键词不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final cookie = arguments['bingCookie'] as String? ??
          arguments['__bingCookie'] as String? ??
          bingCookie;

      final results = await searchService.search(
        query: query,
        searchBackend: 'bing',
        bingCookie: cookie,
      );
      stopwatch.stop();

      final formatted = searchService.formatSearchResultsForContext(results);
      return ToolExecutionResult.success(
        toolName: name,
        content: formatted,
        rawData: results,
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'resultCount': results.length,
          'backend': 'bing',
        },
      );
    } on SearchException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '搜索失败：${e.message}',
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'source': e.source,
          'statusCode': e.statusCode,
          'details': e.details,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: 'Bing 搜索出现异常: $e',
        content: '搜索失败：$e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}

/// Legacy adapter for webpage content extraction (`url_fetch`).
class UrlFetchTool extends Tool {
  final UrlFetchService urlFetchService;

  UrlFetchTool({UrlFetchService? urlFetchService})
      : urlFetchService = urlFetchService ?? UrlFetchService();

  @override
  String get name => 'url_fetch';

  @override
  String get displayName => '网页抓取';

  @override
  String get description =>
      'Fetch and extract structured content from a webpage URL. Returns metadata (title, author, published date, site name, language), page type diagnosis (article/doc/captcha/login_wall/nav_hub), truncation status & limits, link statistics, and cleaned main content in Markdown.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'url',
      type: 'string',
      description: 'The absolute HTTP or HTTPS URL of the webpage to fetch.',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final url = (arguments['url'] as String? ?? '').trim();
    if (url.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: 'URL 不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final cancelToken = arguments['__cancelToken'] as CancelToken? ??
          arguments['cancelToken'] as CancelToken?;
      final maxCharacters = arguments['__maxCharacters'] as int? ??
          arguments['maxCharacters'] as int? ??
          UrlFetchService.defaultMaxCharacters;

      final fetchResult = await urlFetchService.fetchUrl(
        url,
        cancelToken: cancelToken,
        maxCharacters: maxCharacters,
      );
      stopwatch.stop();

      final markdown = fetchResult.toStructuredMarkdown();
      final isSuccess = fetchResult.status != 'error';

      if (!isSuccess) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: fetchResult.mainContent,
          content: markdown,
          rawData: fetchResult,
          executionDuration: stopwatch.elapsed,
          metadata: {
            'url': url,
            'pageType': fetchResult.pageType,
            'status': fetchResult.status,
            'warnings': fetchResult.warnings,
          },
        );
      }

      return ToolExecutionResult.success(
        toolName: name,
        content: markdown,
        rawData: fetchResult,
        executionDuration: stopwatch.elapsed,
        metadata: {
          'url': url,
          'title': fetchResult.metadata.title,
          'pageType': fetchResult.pageType,
          'truncated': fetchResult.truncated,
          'originalLength': fetchResult.originalLength,
          'status': fetchResult.status,
          'warnings': fetchResult.warnings,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '抓取网页异常: $e',
        content: '抓取网页失败: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}
```

---

## 4. Test Specifications

### 4.1 `test/models/tool_model_test.dart`
Contains 14 comprehensive unit tests:
1. `ToolSecurityLevel: Enums, levels, labels, descriptions, and helper properties`
2. `ToolSecurityLevel: Deserialization from JSON name and integer level with safe fallback`
3. `ToolParameter: Initialization and OpenAI JSON schema generation`
4. `ToolParameter: Enum constraints and default values in schema`
5. `ToolParameter: Array type schema with items specification`
6. `ToolParameter: Serialization and deserialization roundtrip`
7. `ToolParameter.validate: Required vs optional validation`
8. `ToolParameter.validate: String type and enum constraint validation`
9. `ToolParameter.validate: Number and integer validation with stringified numbers`
10. `ToolParameter.validate: Boolean, array, and object type validations`
11. `ToolExecutionResult: Success and failure factories with properties`
12. `ToolExecutionResult: Serialization and deserialization roundtrip`
13. `Tool: Custom tool subclass, schema export, and validateArguments`
14. `Tool: Multi-parameter validation error detection`

### 4.2 `test/services/tool_registry_test.dart`
Contains 16 comprehensive unit tests:
1. `ToolRegistry: Register single tool and lookup`
2. `ToolRegistry: Bulk registration and clear`
3. `ToolRegistry: Unregister existing and non-existent tools`
4. `ToolRegistry: Enable/disable toggle, isToolEnabled, getEnabledTools`
5. `ToolRegistry: EnableAll, disableAll, and resetEnablement`
6. `ToolRegistry: Export OpenAI schemas with name filtering`
7. `ToolRegistry: Export OpenAI schemas with onlyEnabled filtering`
8. `ToolRegistry: Export OpenAI schemas with maxSecurityLevel filtering`
9. `ToolRegistry: Execution dispatcher on success with valid args`
10. `ToolRegistry: Execution dispatcher handles non-existent tool`
11. `ToolRegistry: Execution dispatcher handles disabled tool`
12. `ToolRegistry: Execution dispatcher handles parameter validation failure`
13. `ToolRegistry: Execution dispatcher catches unexpected runtime exceptions`
14. `Legacy Adapters: WebSearchTool executes search and handles SearchException`
15. `Legacy Adapters: GoogleSearchTool, BingSearchTool, and UrlFetchTool integration`
16. `Riverpod Provider: toolRegistryProvider initializes default registry`

---

## 5. Downstream Milestone Integration Plan

- **M23.2 (Basic Tools)**:
  - `MathEvalTool` in `lib/services/tools/math_eval_tool.dart`
  - `TimeCalculatorTool` in `lib/services/tools/time_calculator_tool.dart`
  - `WeatherQueryTool` in `lib/services/tools/weather_query_tool.dart`
  - `WikiLookupTool` in `lib/services/tools/wiki_lookup_tool.dart`
  - All implement `Tool` (SecurityLevel 0/1) and register into `ToolRegistry.defaultRegistry()`.
- **M23.3 (AgentLoopGuard)**:
  - `AgentLoopGuard` in `lib/services/agent_loop_guard.dart` evaluates `toolName` and arguments before `ToolRegistry.execute()` dispatch.
- **M23.4 (Agent Pipeline & UI)**:
  - `AgentService` delegates all tool calls to `toolRegistry.execute()`.
  - `ChatBubble` inspects `ToolExecutionResult` and renders rich collapsible cards with status badges and duration metrics.
