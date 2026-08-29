import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool/tool.dart';
import 'tools/legacy_tool_adapters.dart';
import 'tools/math_eval_tool.dart';
import 'tools/time_calculator_tool.dart';
import 'tools/weather_query_tool.dart';
import 'tools/wiki_lookup_tool.dart';
import 'tools/file_read_tool.dart';
import 'tools/file_write_tool.dart';
import 'tools/file_list_tool.dart';
import 'tools/file_delete_tool.dart';
import 'tools/code_eval_tool.dart';
import 'tools/clipboard_tools.dart';
import 'path_sanitizer.dart';
import 'code_execution_service.dart';
import 'search_service.dart';
import 'url_fetch_service.dart';

/// Central registry managing registration, state, schema export, and execution dispatching for all Agent tools.
class ToolRegistry {
  final Map<String, Tool> _tools = {};
  final Map<String, bool> _enabledStates = {};

  ToolRegistry();

  /// Pre-populates a default registry containing built-in search, fetch, safe basic, file, code, and clipboard tools.
  factory ToolRegistry.defaultRegistry({
    SearchService? searchService,
    UrlFetchService? urlFetchService,
    Dio? dio,
    PathSanitizer? pathSanitizer,
    CodeExecutionService? codeExecutionService,
  }) {
    final registry = ToolRegistry();
    registry.registerTools([
      // Legacy network adapters
      WebSearchTool(searchService: searchService),
      GoogleSearchTool(searchService: searchService),
      BingSearchTool(searchService: searchService),
      UrlFetchTool(urlFetchService: urlFetchService),
      // Safe built-in tools (Milestone 23.2)
      const MathEvalTool(),
      TimeCalculatorTool(),
      WeatherQueryTool(dio: dio),
      WikiLookupTool(dio: dio),
      // Local sandboxed file tools & code execution & clipboard (Milestone 24)
      FileReadTool(pathSanitizer: pathSanitizer),
      FileWriteTool(pathSanitizer: pathSanitizer),
      FileListTool(pathSanitizer: pathSanitizer),
      FileDeleteTool(pathSanitizer: pathSanitizer),
      CodeEvalTool(codeExecutionService: codeExecutionService),
      const ClipboardReadTool(),
      const ClipboardWriteTool(),
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
