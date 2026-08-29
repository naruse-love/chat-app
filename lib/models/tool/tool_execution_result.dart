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
