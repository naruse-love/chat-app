import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';

/// Parsed standardized tool invocation extracted from LLM text.
class ParsedToolInvocation {
  /// Name of the tool function to call (e.g. 'math_eval', 'file_read').
  final String toolName;

  /// Cleaned and repaired arguments Map.
  final Map<String, dynamic> arguments;

  /// Verbatim raw block matched from LLM output.
  final String rawBlock;

  /// Format identifier ('dsml_v2', 'dsml_v1', 'qwen_xml', 'qwen_tagged_xml', 'llama_json', 'openai_json', 'hermes_xml').
  final String syntaxFormat;

  const ParsedToolInvocation({
    required this.toolName,
    required this.arguments,
    required this.rawBlock,
    required this.syntaxFormat,
  });

  @override
  String toString() {
    return 'ParsedToolInvocation(tool: $toolName, format: $syntaxFormat, args: $arguments)';
  }
}

/// Retry policy configuration for network and API fault tolerance.
class RetryPolicy {
  /// Maximum number of retry attempts (default 3).
  final int maxRetries;

  /// Initial retry backoff delay (default 500ms).
  final Duration initialDelay;

  /// Maximum ceiling for backoff delay (default 8000ms).
  final Duration maxDelay;

  /// Exponential backoff multiplier (default 2.0).
  final double backoffMultiplier;

  /// Random jitter factor applied to backoff (default ±0.25).
  final double jitterFactor;

  const RetryPolicy({
    this.maxRetries = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(milliseconds: 8000),
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.25,
  });

  /// Evaluates whether an exception is transient and retryable.
  bool isRetryable(dynamic error) {
    if (error is SocketException || error is TimeoutException || error is HttpException) {
      return true;
    }

    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return true;
      }
      final statusCode = error.response?.statusCode;
      if (statusCode == 429 || (statusCode != null && statusCode >= 500 && statusCode <= 504)) {
        return true;
      }
    }

    return false;
  }

  /// Calculates exponential backoff duration with random jitter.
  Duration calculateDelay(int attempt, [Duration? retryAfter]) {
    if (retryAfter != null) return retryAfter;

    final baseMs = initialDelay.inMilliseconds * math.pow(backoffMultiplier, attempt);
    final clampedMs = baseMs.clamp(
      initialDelay.inMilliseconds.toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );

    // Apply jitter ±jitterFactor
    final random = math.Random();
    final jitter = (random.nextDouble() * 2 - 1) * jitterFactor; // -0.25 .. +0.25
    final finalMs = (clampedMs * (1 + jitter)).round();

    return Duration(milliseconds: math.max(10, finalMs));
  }
}

/// Resilient Cross-Model Fault Tolerance, Multi-format Tool Parsing, and Self-Healing Gateway.
class AgentFaultTolerance {
  final RetryPolicy retryPolicy;

  AgentFaultTolerance({RetryPolicy? retryPolicy})
      : retryPolicy = retryPolicy ?? const RetryPolicy();

  // ==========================================
  // 1. Multi-format Tool Call Parser
  // ==========================================

  // 1. DeepSeek DSML v2 official tags: <｜tool calls begin｜> ... <｜tool calls end｜>
  static final RegExp _dsmlV2BlockRegex = RegExp(
    r'<[|｜]tool calls begin[|｜]>([\s\S]*?)<[|｜]tool calls end[|｜]>',
    multiLine: true,
  );
  static final RegExp _dsmlV2SingleCallRegex = RegExp(
    r'<[|｜]tool call begin[|｜]>(?:function<[|｜]tool sep[|｜]>)?([^\s<`]+)\s*(?:```(?:json)?\s*)?([\s\S]*?)(?:\s*```)?\s*<[|｜]tool call end[|｜]>',
    multiLine: true,
  );

  // 2. DeepSeek DSML v1 XML format: <｜｜DSML｜｜tool_calls> ... </｜｜DSML｜｜tool_calls>
  static final RegExp _dsmlV1BlockRegex = RegExp(
    r'<[|｜]{2}DSML[|｜]{2}tool_calls>([\s\S]*?)</[|｜]{2}DSML[|｜]{2}tool_calls>',
    multiLine: true,
  );
  static final RegExp _dsmlV1InvokeRegex = RegExp(
    r'<[|｜]{2}DSML[|｜]{2}invoke name="([^">]+)">([\s\S]*?)</[|｜]{2}DSML[|｜]{2}invoke>',
    multiLine: true,
  );
  static final RegExp _dsmlV1ParamRegex = RegExp(
    r'<[|｜]{2}DSML[|｜]{2}parameter name="([^">]+)"[^>]*>([\s\S]*?)</[|｜]{2}DSML[|｜]{2}parameter>',
    multiLine: true,
  );

  // 3. Qwen XML with enclosed JSON: <tool_call>\n{"name": "...", "arguments": {...}}\n</tool_call>
  static final RegExp _qwenXmlJsonRegex = RegExp(
    r'<tool_call>\s*(?:```(?:json)?\s*)?(\{[\s\S]*?\})(?:\s*```)?\s*</tool_call>',
    multiLine: true,
  );

  // 4. Qwen Tagged XML: <tool_call>\n<function=name>\n<parameter=key>val</parameter>\n</function>\n</tool_call>
  static final RegExp _qwenTaggedXmlRegex = RegExp(
    r'<tool_call>\s*<function=([^>]+)>([\s\S]*?)</function>\s*</tool_call>',
    multiLine: true,
  );
  static final RegExp _xmlParamRegex = RegExp(
    r'<parameter=([^>]+)>([\s\S]*?)</parameter>',
    multiLine: true,
  );

  // 5. Llama 3 [TOOL_CALLS] format: [TOOL_CALLS] [...] or [TOOL_CALLS] {...}
  static final RegExp _llamaToolCallsRegex = RegExp(
    r'\[TOOL_CALLS\]\s*(\[[\s\S]*?\]|\{[\s\S]*?\})',
    multiLine: true,
  );

  // 6. Hermes / Nous format: <functioncall> {...} </functioncall>
  static final RegExp _hermesFunctionCallRegex = RegExp(
    r'<functioncall>\s*(?:```(?:json)?\s*)?(\{[\s\S]*?\})(?:\s*```)?\s*</functioncall>',
    multiLine: true,
  );

  /// Parses multi-format tool invocations from text across major model families.
  List<ParsedToolInvocation> parseToolCalls(String content) {
    final results = <ParsedToolInvocation>[];
    if (content.isEmpty) return results;

    final unescapedContent = _unescapeXmlEntities(content);

    // 1. DeepSeek DSML v2
    for (final blockMatch in _dsmlV2BlockRegex.allMatches(unescapedContent)) {
      final block = blockMatch.group(1) ?? '';
      for (final callMatch in _dsmlV2SingleCallRegex.allMatches(block)) {
        final toolName = callMatch.group(1) ?? '';
        final rawArgs = callMatch.group(2) ?? '{}';
        final args = repairAndParseArguments(rawArgs);
        results.add(ParsedToolInvocation(
          toolName: toolName,
          arguments: args,
          rawBlock: callMatch.group(0) ?? '',
          syntaxFormat: 'dsml_v2',
        ));
      }
    }
    if (results.isEmpty) {
      for (final callMatch in _dsmlV2SingleCallRegex.allMatches(unescapedContent)) {
        final toolName = callMatch.group(1) ?? '';
        final rawArgs = callMatch.group(2) ?? '{}';
        final args = repairAndParseArguments(rawArgs);
        results.add(ParsedToolInvocation(
          toolName: toolName,
          arguments: args,
          rawBlock: callMatch.group(0) ?? '',
          syntaxFormat: 'dsml_v2',
        ));
      }
    }
    if (results.isNotEmpty) return results;

    // 2. DeepSeek DSML v1
    for (final blockMatch in _dsmlV1BlockRegex.allMatches(unescapedContent)) {
      final block = blockMatch.group(1) ?? '';
      for (final invokeMatch in _dsmlV1InvokeRegex.allMatches(block)) {
        final toolName = invokeMatch.group(1) ?? '';
        final invokeBody = invokeMatch.group(2) ?? '';
        final paramMap = <String, dynamic>{};
        for (final pMatch in _dsmlV1ParamRegex.allMatches(invokeBody)) {
          final pName = pMatch.group(1) ?? '';
          final pVal = pMatch.group(2)?.trim() ?? '';
          paramMap[pName] = _inferTypeOrString(pVal);
        }
        results.add(ParsedToolInvocation(
          toolName: toolName,
          arguments: paramMap,
          rawBlock: invokeMatch.group(0) ?? '',
          syntaxFormat: 'dsml_v1',
        ));
      }
    }
    if (results.isNotEmpty) return results;

    // 3. Qwen XML with JSON
    for (final match in _qwenXmlJsonRegex.allMatches(unescapedContent)) {
      final jsonBody = match.group(1) ?? '{}';
      final decoded = repairAndParseArguments(jsonBody);
      final toolName = decoded['name']?.toString() ?? decoded['function']?.toString() ?? '';
      final argsRaw = decoded['arguments'] ?? decoded['parameters'] ?? decoded;
      final args = (argsRaw is Map)
          ? Map<String, dynamic>.from(argsRaw)
          : (argsRaw is String ? repairAndParseArguments(argsRaw) : <String, dynamic>{});

      if (toolName.isNotEmpty) {
        results.add(ParsedToolInvocation(
          toolName: toolName,
          arguments: args,
          rawBlock: match.group(0) ?? '',
          syntaxFormat: 'qwen_xml',
        ));
      }
    }
    if (results.isNotEmpty) return results;

    // 4. Qwen Tagged XML
    for (final match in _qwenTaggedXmlRegex.allMatches(unescapedContent)) {
      final toolName = match.group(1) ?? '';
      final body = match.group(2) ?? '';
      final paramMap = <String, dynamic>{};
      for (final pMatch in _xmlParamRegex.allMatches(body)) {
        final pName = pMatch.group(1) ?? '';
        final pVal = pMatch.group(2)?.trim() ?? '';
        paramMap[pName] = _inferTypeOrString(pVal);
      }
      results.add(ParsedToolInvocation(
        toolName: toolName,
        arguments: paramMap,
        rawBlock: match.group(0) ?? '',
        syntaxFormat: 'qwen_tagged_xml',
      ));
    }
    if (results.isNotEmpty) return results;

    // 5. Llama 3 [TOOL_CALLS]
    for (final match in _llamaToolCallsRegex.allMatches(unescapedContent)) {
      final rawJson = match.group(1) ?? '';
      try {
        final repaired = repairJson(rawJson);
        final decoded = json.decode(repaired);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final toolName = item['name']?.toString() ?? '';
              final args = item['arguments'] is Map
                  ? Map<String, dynamic>.from(item['arguments'])
                  : repairAndParseArguments(item['arguments']);
              if (toolName.isNotEmpty) {
                results.add(ParsedToolInvocation(
                  toolName: toolName,
                  arguments: args,
                  rawBlock: match.group(0) ?? '',
                  syntaxFormat: 'llama_json',
                ));
              }
            }
          }
        } else if (decoded is Map) {
          final toolName = decoded['name']?.toString() ?? '';
          final args = decoded['arguments'] is Map
              ? Map<String, dynamic>.from(decoded['arguments'])
              : repairAndParseArguments(decoded['arguments']);
          if (toolName.isNotEmpty) {
            results.add(ParsedToolInvocation(
              toolName: toolName,
              arguments: args,
              rawBlock: match.group(0) ?? '',
              syntaxFormat: 'llama_json',
            ));
          }
        }
      } catch (_) {}
    }
    if (results.isNotEmpty) return results;

    // 6. Hermes <functioncall>
    for (final match in _hermesFunctionCallRegex.allMatches(unescapedContent)) {
      final jsonBody = match.group(1) ?? '{}';
      final decoded = repairAndParseArguments(jsonBody);
      final toolName = decoded['name']?.toString() ?? decoded['function']?.toString() ?? '';
      final args = decoded['arguments'] is Map
          ? Map<String, dynamic>.from(decoded['arguments'])
          : repairAndParseArguments(decoded['arguments']);
      if (toolName.isNotEmpty) {
        results.add(ParsedToolInvocation(
          toolName: toolName,
          arguments: args,
          rawBlock: match.group(0) ?? '',
          syntaxFormat: 'hermes_xml',
        ));
      }
    }
    if (results.isNotEmpty) return results;

    // 7. Raw OpenAI Markdown / JSON
    final trimmed = unescapedContent.trim();
    if (trimmed.startsWith('{') || trimmed.startsWith('```json') || trimmed.startsWith('```')) {
      final decoded = repairAndParseArguments(trimmed);
      if (decoded.containsKey('name') && (decoded.containsKey('arguments') || decoded.containsKey('parameters'))) {
        final toolName = decoded['name']?.toString() ?? '';
        final args = decoded['arguments'] is Map
            ? Map<String, dynamic>.from(decoded['arguments'])
            : repairAndParseArguments(decoded['arguments']);
        if (toolName.isNotEmpty) {
          results.add(ParsedToolInvocation(
            toolName: toolName,
            arguments: args,
            rawBlock: trimmed,
            syntaxFormat: 'openai_json',
          ));
        }
      }
    }

    return results;
  }

  /// Strips all tool call markers from LLM output for clean UI display.
  String stripToolCallBlocks(String content) {
    var cleaned = content;
    cleaned = cleaned.replaceAll(_dsmlV2BlockRegex, '');
    cleaned = cleaned.replaceAll(_dsmlV2SingleCallRegex, '');
    cleaned = cleaned.replaceAll(_dsmlV1BlockRegex, '');
    cleaned = cleaned.replaceAll(_qwenXmlJsonRegex, '');
    cleaned = cleaned.replaceAll(_qwenTaggedXmlRegex, '');
    cleaned = cleaned.replaceAll(_llamaToolCallsRegex, '');
    cleaned = cleaned.replaceAll(_hermesFunctionCallRegex, '');
    return cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  // ==========================================
  // 2. Resilient JSON Argument Auto-Repair
  // ==========================================

  /// Parses and repairs dynamic/string arguments into a Map<String, dynamic>.
  Map<String, dynamic> repairAndParseArguments(dynamic args) {
    if (args == null) return {};
    if (args is Map<String, dynamic>) return args;
    if (args is Map) return Map<String, dynamic>.from(args);

    if (args is String) {
      final trimmed = args.trim();
      if (trimmed.isEmpty) return {};

      // 1. Direct JSON decode
      try {
        final decoded = json.decode(trimmed);
        if (decoded is Map) return _deepUnescapeEntities(Map<String, dynamic>.from(decoded));
      } catch (_) {}

      // 2. Repaired JSON decode
      final repaired = repairJson(trimmed);
      try {
        final decoded = json.decode(repaired);
        if (decoded is Map) return _deepUnescapeEntities(Map<String, dynamic>.from(decoded));
        if (decoded is List) return {'items': decoded};
      } catch (_) {}

      // 3. Fallback wrap for plain strings (e.g. single argument)
      return {'query': _unescapeXmlEntities(trimmed)};
    }

    return {'value': args};
  }

  /// Recursively unescapes XML/HTML entities in parsed map values.
  static Map<String, dynamic> _deepUnescapeEntities(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key;
      final val = entry.value;
      if (val is String) {
        result[key] = _unescapeXmlEntities(val);
      } else if (val is Map) {
        result[key] = _deepUnescapeEntities(Map<String, dynamic>.from(val));
      } else if (val is List) {
        result[key] = val.map((item) {
          if (item is String) return _unescapeXmlEntities(item);
          if (item is Map) return _deepUnescapeEntities(Map<String, dynamic>.from(item));
          return item;
        }).toList();
      } else {
        result[key] = val;
      }
    }
    return result;
  }

  /// Repairs 8 types of deformed/malformed JSON strings:
  /// 1. Markdown code fences (` ```json ... ``` `)
  /// 2. HTML/XML entity escapes (`&quot;`, `&amp;`, `&lt;`, `&gt;`, `&#39;`)
  /// 3. Unescaped literal newlines `0x0A`, carriage returns `0x0D`, tabs `0x09` inside string literals
  /// 4. Single-quoted keys and string values (`{'key': 'val'}` -> `{"key": "val"}`)
  /// 5. Unquoted object keys (`{key: "val"}` -> `{"key": "val"}`)
  /// 6. Trailing commas in objects and arrays (`{a: 1,}` -> `{"a": 1}`)
  /// 7. Unclosed quotes and truncated bracket/brace stacks (`{"a": [1, 2` -> `{"a": [1, 2]}`)
  /// 8. Invalid backslashes and unicode escape residues
  String repairJson(String rawJson) {
    var text = rawJson.trim();
    if (text.isEmpty) return '{}';

    // 1. Strip markdown fences
    if (text.startsWith('```')) {
      final lines = text.split('\n');
      if (lines.length >= 2) {
        int start = 1;
        int end = lines.length;
        if (lines.last.trim().startsWith('```')) {
          end = lines.length - 1;
        }
        text = lines.sublist(start, end).join('\n').trim();
      }
    }

    // 2. Decode entities safely (replace &quot; with \" so JSON grammar is preserved)
    text = text
        .replaceAll('&quot;', r'\"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');

    // 3. State machine repair for string escapes, quotes, and bracket balancing
    final runes = text.runes.toList();
    final buffer = StringBuffer();
    final bracketStack = <String>[];
    bool inString = false;
    int quoteChar = 0; // 0x22 (") or 0x27 (')
    bool escapeNext = false;

    for (int i = 0; i < runes.length; i++) {
      final ch = runes[i];

      if (escapeNext) {
        buffer.writeCharCode(ch);
        escapeNext = false;
        continue;
      }

      if (ch == 0x5C && inString) {
        // Backslash '\'
        buffer.writeCharCode(ch);
        escapeNext = true;
        continue;
      }

      // Quote character check (0x22 = ", 0x27 = ')
      if (ch == 0x22 || ch == 0x27) {
        if (!inString) {
          inString = true;
          quoteChar = ch;
          buffer.writeCharCode(0x22); // Normalize to double quote
        } else if (quoteChar == ch) {
          inString = false;
          quoteChar = 0;
          buffer.writeCharCode(0x22);
        } else {
          // Nested quote inside string
          if (ch == 0x22) {
            buffer.write(r'\"');
          } else {
            buffer.writeCharCode(ch);
          }
        }
        continue;
      }

      if (inString) {
        // Unescaped literal newlines / control characters inside strings
        if (ch == 0x0A) {
          buffer.write(r'\n');
        } else if (ch == 0x0D) {
          buffer.write(r'\r');
        } else if (ch == 0x09) {
          buffer.write(r'\t');
        } else {
          buffer.writeCharCode(ch);
        }
      } else {
        // Structural brackets and braces
        if (ch == 0x7B) {
          // '{'
          bracketStack.add('}');
          buffer.writeCharCode(ch);
        } else if (ch == 0x5B) {
          // '['
          bracketStack.add(']');
          buffer.writeCharCode(ch);
        } else if (ch == 0x7D || ch == 0x5D) {
          // '}' or ']'
          if (bracketStack.isNotEmpty && bracketStack.last.codeUnitAt(0) == ch) {
            bracketStack.removeLast();
          }
          buffer.writeCharCode(ch);
        } else {
          buffer.writeCharCode(ch);
        }
      }
    }

    // If truncated inside string, close the quote
    if (inString) {
      buffer.write('"');
    }

    var result = buffer.toString().trim();

    // 4. Remove trailing commas before closing braces/brackets (loop until all nested commas are removed)
    while (result.contains(RegExp(r',\s*([\}\]])'))) {
      result = result.replaceAllMapped(
        RegExp(r',\s*([\}\]])'),
        (match) => match.group(1) ?? '',
      );
    }

    // Remove hanging colon or trailing comma at the end
    while (result.endsWith(',') || result.endsWith(':')) {
      result = result.substring(0, result.length - 1).trim();
    }

    // 5. Close unclosed brackets in stack order
    final closingBuffer = StringBuffer(result);
    for (int i = bracketStack.length - 1; i >= 0; i--) {
      var current = closingBuffer.toString().trimRight();
      if (current.endsWith(':') || current.endsWith(',')) {
        closingBuffer.clear();
        closingBuffer.write(current.substring(0, current.length - 1));
      }
      closingBuffer.write(bracketStack[i]);
    }
    result = closingBuffer.toString();

    // 6. Fix unquoted object keys: {query: "...", limit: 5} -> {"query": "...", "limit": 5}
    // Also supports Chinese / non-ASCII unquoted keys: {城市: "北京", 关键词: "AI"} -> {"城市": "北京", "关键词": "AI"}
    result = result.replaceAllMapped(
      RegExp(r'''([{,]\s*)([^\s{}[\]:,"'`]+)(\s*:)'''),
      (match) => '${match.group(1)}"${match.group(2)}"${match.group(3)}',
    );

    // Final clean check for any newly created trailing commas
    while (result.contains(RegExp(r',\s*([\}\]])'))) {
      result = result.replaceAllMapped(
        RegExp(r',\s*([\}\]])'),
        (match) => match.group(1) ?? '',
      );
    }

    return result;
  }

  // ==========================================
  // 3. Exponential Backoff Retry with Jitter
  // ==========================================

  /// Executes an asynchronous action with exponential backoff, jitter, and Retry-After handling.
  Future<T> executeWithRetry<T>(
    Future<T> Function() action, {
    CancelToken? cancelToken,
    void Function(int attempt, Duration delay, dynamic error)? onRetry,
  }) async {
    int attempt = 0;
    while (true) {
      if (cancelToken?.isCancelled ?? false) {
        throw DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
        );
      }

      try {
        return await action();
      } catch (e) {
        attempt++;
        if (attempt > retryPolicy.maxRetries || !retryPolicy.isRetryable(e)) {
          rethrow;
        }

        Duration delay = retryPolicy.calculateDelay(attempt - 1);
        if (e is DioException) {
          final retryAfterHeader = e.response?.headers.value('retry-after');
          if (retryAfterHeader != null) {
            final seconds = int.tryParse(retryAfterHeader);
            if (seconds != null && seconds > 0) {
              delay = Duration(seconds: seconds);
            }
          }
        }

        onRetry?.call(attempt, delay, e);
        await Future.delayed(delay);
      }
    }
  }

  // ==========================================
  // 4. Structured Self-Healing Chinese Diagnostic Context
  // ==========================================

  /// Generates structured Chinese diagnostic feedback for LLM self-reflection.
  String generateSelfHealingFeedback({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String errorMessage,
    String? suggestion,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('【工具执行异常与自愈引导】');
    buffer.writeln('- 调用的工具: `$toolName`');
    buffer.writeln('- 传入的参数: `${jsonEncode(arguments)}`');
    buffer.writeln('- 失败原因: $errorMessage');
    if (suggestion != null && suggestion.isNotEmpty) {
      buffer.writeln('- 修复建议: $suggestion');
    } else {
      buffer.writeln('- 修复建议: 请根据上述错误原因检查参数类型或有效性，修正参数后重试，或选用其他工具替代完成任务。');
    }
    return buffer.toString().trim();
  }

  /// Static alias for convenience.
  static String buildSelfHealingFeedback({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String errorMessage,
    String? suggestion,
  }) {
    return AgentFaultTolerance().generateSelfHealingFeedback(
      toolName: toolName,
      arguments: arguments,
      errorMessage: errorMessage,
      suggestion: suggestion,
    );
  }

  // ==========================================
  // Internal Helpers
  // ==========================================

  static String _unescapeXmlEntities(String str) {
    return str
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  static dynamic _inferTypeOrString(String val) {
    final trimmed = val.trim();
    if (trimmed.toLowerCase() == 'true') return true;
    if (trimmed.toLowerCase() == 'false') return false;
    final numVal = num.tryParse(trimmed);
    if (numVal != null) return numVal;
    return trimmed;
  }
}
