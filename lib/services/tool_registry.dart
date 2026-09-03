import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tool/tool.dart';
import 'tools/legacy_tool_adapters.dart';
import 'tools/math_eval_tool.dart';
import 'tools/time_calculator_tool.dart';
import 'tools/weather_query_tool.dart';
import 'tools/file_read_tool.dart';
import 'tools/file_write_tool.dart';
import 'tools/file_list_tool.dart';
import 'tools/file_delete_tool.dart';
import 'tools/code_eval_tool.dart';
import 'tools/clipboard_tools.dart';
import 'tools/native/native_tools.dart';
import 'native/native_services.dart';
import 'path_sanitizer.dart';
import 'code_execution_service.dart';
import 'search_service.dart';
import 'url_fetch_service.dart';

/// Central registry managing registration, state, schema export, and execution dispatching for all Agent tools.
class ToolRegistry {
  final Map<String, Tool> _tools = {};
  final Map<String, bool> _enabledStates = {};

  ToolRegistry();

  /// Pre-populates a default registry containing built-in search, fetch, safe basic, file, code, clipboard, and native tools.
  factory ToolRegistry.defaultRegistry({
    SearchService? searchService,
    UrlFetchService? urlFetchService,
    Dio? dio,
    PathSanitizer? pathSanitizer,
    CodeExecutionService? codeExecutionService,
    ICalendarService? calendarService,
    INotificationService? notificationService,
    IContactsService? contactsService,
    ILocationService? locationService,
    ContactsSanitizer? contactsSanitizer,
    PermissionManagerService? permissionManagerService,
  }) {
    final effectiveCalendar = calendarService ?? InMemoryCalendarService(seedDefaults: false);
    final effectiveNotification = notificationService ?? InMemoryNotificationService();
    final effectiveContacts = contactsService ?? InMemoryContactsService(seedDefaults: false);
    final effectiveLocation = locationService ?? RealLocationService();
    final effectiveSanitizer = contactsSanitizer ?? const ContactsSanitizer();
    final effectivePermission = permissionManagerService ?? PermissionManagerService();
    final effectivePathSanitizer = pathSanitizer ??
        PathSanitizer(sandboxDir: PathSanitizer.defaultDirectory);

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
      // Local sandboxed file tools & code execution & clipboard (Milestone 24)
      FileReadTool(pathSanitizer: effectivePathSanitizer),
      FileWriteTool(pathSanitizer: effectivePathSanitizer),
      FileListTool(pathSanitizer: effectivePathSanitizer),
      FileDeleteTool(pathSanitizer: effectivePathSanitizer),
      CodeEvalTool(codeExecutionService: codeExecutionService),
      const ClipboardReadTool(),
      const ClipboardWriteTool(),
      // Native Privileged Tools (Milestone 25)
      CalendarQueryEventsTool(
        calendarService: effectiveCalendar,
        permissionService: effectivePermission,
      ),
      CalendarCreateEventTool(
        calendarService: effectiveCalendar,
        permissionService: effectivePermission,
      ),
      NotificationScheduleTool(
        notificationService: effectiveNotification,
        permissionService: effectivePermission,
      ),
      NotificationCancelTool(
        notificationService: effectiveNotification,
        permissionService: effectivePermission,
      ),
      ContactsSearchTool(
        contactsService: effectiveContacts,
        contactsSanitizer: effectiveSanitizer,
        permissionService: effectivePermission,
      ),
      GeolocationGetTool(
        locationService: effectiveLocation,
        permissionService: effectivePermission,
      ),
      ReverseGeocodeTool(
        locationService: effectiveLocation,
      ),
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

  /// Dynamically updates the active workspace root for all registered file tools.
  void updateWorkspacePath(String newWorkspacePath) {
    final cleanPath = newWorkspacePath.trim();
    if (cleanPath.isEmpty) return;
    final newDir = Directory(cleanPath);
    if (!newDir.existsSync()) {
      try {
        newDir.createSync(recursive: true);
      } catch (_) {}
    }

    final newSanitizer = PathSanitizer(sandboxDir: newDir);
    register(FileReadTool(pathSanitizer: newSanitizer), enabled: isToolEnabled('file_read'));
    register(FileWriteTool(pathSanitizer: newSanitizer), enabled: isToolEnabled('file_write'));
    register(FileListTool(pathSanitizer: newSanitizer), enabled: isToolEnabled('file_list'));
    register(FileDeleteTool(pathSanitizer: newSanitizer), enabled: isToolEnabled('file_delete'));
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
    final rawMergedArgs = Map<String, dynamic>.from(arguments);
    if (context != null) {
      for (final entry in context.entries) {
        rawMergedArgs.putIfAbsent('__${entry.key}', () => entry.value);
        rawMergedArgs.putIfAbsent(entry.key, () => entry.value);
      }
    }

    final effectiveArgs = _normalizeArguments(rawMergedArgs);

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

  /// Normalizes common parameter name aliases across multiple LLM tool calling formats.
  static Map<String, dynamic> _normalizeArguments(Map<String, dynamic> args) {
    final normalized = Map<String, dynamic>.from(args);

    // 1. title aliases
    if (!normalized.containsKey('title') || normalized['title'] == null || normalized['title'].toString().trim().isEmpty) {
      for (final alias in ['summary', 'name', 'event_name', 'event_title', 'topic', 'subject', 'headline']) {
        if (normalized.containsKey(alias) && normalized[alias] != null && normalized[alias].toString().trim().isNotEmpty) {
          normalized['title'] = normalized[alias];
          break;
        }
      }
    }

    // 2. start_time aliases
    if (!normalized.containsKey('start_time') || normalized['start_time'] == null || normalized['start_time'].toString().trim().isEmpty) {
      for (final alias in ['start', 'startTime', 'start_date', 'begin_time', 'beginTime', 'time']) {
        if (normalized.containsKey(alias) && normalized[alias] != null && normalized[alias].toString().trim().isNotEmpty) {
          normalized['start_time'] = normalized[alias];
          break;
        }
      }
    }

    // 3. end_time aliases
    if (!normalized.containsKey('end_time') || normalized['end_time'] == null || normalized['end_time'].toString().trim().isEmpty) {
      for (final alias in ['end', 'endTime', 'end_date', 'finish_time', 'finishTime']) {
        if (normalized.containsKey(alias) && normalized[alias] != null && normalized[alias].toString().trim().isNotEmpty) {
          normalized['end_time'] = normalized[alias];
          break;
        }
      }
    }

    // 4. body aliases
    if (!normalized.containsKey('body') || normalized['body'] == null || normalized['body'].toString().trim().isEmpty) {
      for (final alias in ['content', 'message', 'text', 'description', 'payload']) {
        if (normalized.containsKey(alias) && normalized[alias] != null && normalized[alias].toString().trim().isNotEmpty) {
          normalized['body'] = normalized[alias];
          break;
        }
      }
    }

    // 5. scheduled_time aliases
    if (!normalized.containsKey('scheduled_time') || normalized['scheduled_time'] == null || normalized['scheduled_time'].toString().trim().isEmpty) {
      for (final alias in ['trigger_time', 'triggerTime', 'time', 'scheduledTime', 'datetime', 'date']) {
        if (normalized.containsKey(alias) && normalized[alias] != null && normalized[alias].toString().trim().isNotEmpty) {
          normalized['scheduled_time'] = normalized[alias];
          break;
        }
      }
    }

    // 6. path aliases
    if (!normalized.containsKey('path') || normalized['path'] == null || normalized['path'].toString().trim().isEmpty) {
      for (final alias in ['file_path', 'filePath', 'filepath', 'filename', 'name']) {
        if (normalized.containsKey(alias) && normalized[alias] != null && normalized[alias].toString().trim().isNotEmpty) {
          normalized['path'] = normalized[alias];
          break;
        }
      }
    }

    // 7. code aliases
    if (!normalized.containsKey('code') || normalized['code'] == null || normalized['code'].toString().trim().isEmpty) {
      for (final alias in ['script', 'source', 'expression', 'snippet']) {
        if (normalized.containsKey(alias) && normalized[alias] != null && normalized[alias].toString().trim().isNotEmpty) {
          normalized['code'] = normalized[alias];
          break;
        }
      }
    }

    // 8. query aliases
    if (!normalized.containsKey('query') || normalized['query'] == null || normalized['query'].toString().trim().isEmpty) {
      for (final alias in ['q', 'keyword', 'keywords', 'search', 'prompt']) {
        if (normalized.containsKey(alias) && normalized[alias] != null && normalized[alias].toString().trim().isNotEmpty) {
          normalized['query'] = normalized[alias];
          break;
        }
      }
    }

    return normalized;
  }
}

/// Global Riverpod Provider for ToolRegistry.
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  final calendarSvc = ref.watch(calendarServiceProvider);
  final notificationSvc = ref.watch(notificationServiceProvider);
  final contactsSvc = ref.watch(contactsServiceProvider);
  final locationSvc = ref.watch(locationServiceProvider);
  final sanitizer = ref.watch(contactsSanitizerProvider);
  final permissionMgr = ref.watch(permissionManagerServiceProvider);

  return ToolRegistry.defaultRegistry(
    calendarService: calendarSvc,
    notificationService: notificationSvc,
    contactsService: contactsSvc,
    locationService: locationSvc,
    contactsSanitizer: sanitizer,
    permissionManagerService: permissionMgr,
  );
});
