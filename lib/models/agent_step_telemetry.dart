/// Represents a single execution step in a multi-step agent workflow.
class AgentStepTelemetry {
  /// Step index (1-based or 0-based sequential counter).
  final int stepIndex;

  /// Tool identifier (e.g. 'math_eval', 'file_read', 'mcp_git_status').
  final String toolName;

  /// Tool category (e.g. '基础实用', '文件系统', '代码执行', '移动原生', 'MCP 扩展').
  final String toolCategory;

  /// Execution duration in milliseconds.
  final int durationMs;

  /// Model's intent or reasoning thought before invoking the tool.
  final String? intent;

  /// Arguments passed to the tool.
  final Map<String, dynamic> arguments;

  /// Brief preview snippet of the tool output.
  final String? outputPreview;

  /// Full output text of the tool execution.
  final String? fullOutput;

  /// Whether the execution completed successfully.
  final bool isSuccess;

  /// Error message if execution failed.
  final String? errorMessage;

  /// Whether this step's historical output has been compacted by sliding window.
  final bool isCompressed;

  /// Whether this step triggered the token budget circuit breaker.
  final bool isCircuitBreakerTriggered;

  /// Estimated or actual prompt tokens consumed for this step.
  final int? promptTokens;

  /// Estimated or actual completion tokens consumed for this step.
  final int? completionTokens;

  /// Timestamp when this step was executed.
  final DateTime timestamp;

  AgentStepTelemetry({
    required this.stepIndex,
    required this.toolName,
    required this.toolCategory,
    required this.durationMs,
    this.intent,
    required this.arguments,
    this.outputPreview,
    this.fullOutput,
    this.isSuccess = true,
    this.errorMessage,
    this.isCompressed = false,
    this.isCircuitBreakerTriggered = false,
    this.promptTokens,
    this.completionTokens,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convenient duration getter.
  Duration get duration => Duration(milliseconds: durationMs);

  /// Converts this telemetry model to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'stepIndex': stepIndex,
      'toolName': toolName,
      'toolCategory': toolCategory,
      'durationMs': durationMs,
      if (intent != null) 'intent': intent,
      'arguments': arguments,
      if (outputPreview != null) 'outputPreview': outputPreview,
      if (fullOutput != null) 'fullOutput': fullOutput,
      'isSuccess': isSuccess,
      if (errorMessage != null) 'errorMessage': errorMessage,
      'isCompressed': isCompressed,
      'isCircuitBreakerTriggered': isCircuitBreakerTriggered,
      if (promptTokens != null) 'promptTokens': promptTokens,
      if (completionTokens != null) 'completionTokens': completionTokens,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Creates a telemetry instance from JSON map.
  factory AgentStepTelemetry.fromJson(Map<String, dynamic> json) {
    return AgentStepTelemetry(
      stepIndex: json['stepIndex'] as int? ?? 0,
      toolName: json['toolName'] as String? ?? '',
      toolCategory: json['toolCategory'] as String? ?? '未分类',
      durationMs: json['durationMs'] as int? ?? 0,
      intent: json['intent'] as String?,
      arguments: json['arguments'] is Map
          ? Map<String, dynamic>.from(json['arguments'] as Map)
          : <String, dynamic>{},
      outputPreview: json['outputPreview'] as String?,
      fullOutput: json['fullOutput'] as String?,
      isSuccess: json['isSuccess'] as bool? ?? true,
      errorMessage: json['errorMessage'] as String?,
      isCompressed: json['isCompressed'] as bool? ?? false,
      isCircuitBreakerTriggered: json['isCircuitBreakerTriggered'] as bool? ?? false,
      promptTokens: json['promptTokens'] as int?,
      completionTokens: json['completionTokens'] as int?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Copies instance with optional overrides.
  AgentStepTelemetry copyWith({
    int? stepIndex,
    String? toolName,
    String? toolCategory,
    int? durationMs,
    String? intent,
    Map<String, dynamic>? arguments,
    String? outputPreview,
    String? fullOutput,
    bool? isSuccess,
    String? errorMessage,
    bool? isCompressed,
    bool? isCircuitBreakerTriggered,
    int? promptTokens,
    int? completionTokens,
    DateTime? timestamp,
  }) {
    return AgentStepTelemetry(
      stepIndex: stepIndex ?? this.stepIndex,
      toolName: toolName ?? this.toolName,
      toolCategory: toolCategory ?? this.toolCategory,
      durationMs: durationMs ?? this.durationMs,
      intent: intent ?? this.intent,
      arguments: arguments ?? this.arguments,
      outputPreview: outputPreview ?? this.outputPreview,
      fullOutput: fullOutput ?? this.fullOutput,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage ?? this.errorMessage,
      isCompressed: isCompressed ?? this.isCompressed,
      isCircuitBreakerTriggered: isCircuitBreakerTriggered ?? this.isCircuitBreakerTriggered,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'AgentStepTelemetry(step: $stepIndex, tool: $toolName, duration: ${durationMs}ms, success: $isSuccess)';
  }
}

/// Telemetry metrics for token budget tracking and sliding window compaction.
class TokenBudgetTelemetry {
  /// Current estimated token count in the active prompt/context.
  final int currentEstimatedTokens;

  /// Hard or soft budget ceiling for the conversation/step (e.g. 32000).
  final int budgetCap;

  /// Ratio of consumed tokens relative to budgetCap (0.0 - 1.0+).
  final double usageRatio;

  /// Whether the usage has reached the warning / compaction threshold (e.g. >= 0.75).
  final bool isWarning;

  /// Whether the circuit breaker has been tripped (forcing tool stripping).
  final bool isCircuitBreakerTriggered;

  /// Number of intermediate tool messages that have been compressed.
  final int compressionCount;

  /// Estimated tokens saved across all compression actions.
  final int tokensSaved;

  const TokenBudgetTelemetry({
    required this.currentEstimatedTokens,
    required this.budgetCap,
    required this.usageRatio,
    this.isWarning = false,
    this.isCircuitBreakerTriggered = false,
    this.compressionCount = 0,
    this.tokensSaved = 0,
  });

  /// Factory calculating usage ratio and thresholds automatically.
  factory TokenBudgetTelemetry.calculate({
    required int currentEstimatedTokens,
    required int budgetCap,
    double warningThreshold = 0.75,
    double circuitBreakerThreshold = 0.90,
    int compressionCount = 0,
    int tokensSaved = 0,
  }) {
    final effectiveCap = budgetCap > 0 ? budgetCap : 32000;
    final ratio = currentEstimatedTokens / effectiveCap;
    return TokenBudgetTelemetry(
      currentEstimatedTokens: currentEstimatedTokens,
      budgetCap: effectiveCap,
      usageRatio: ratio,
      isWarning: ratio >= warningThreshold,
      isCircuitBreakerTriggered: ratio >= circuitBreakerThreshold,
      compressionCount: compressionCount,
      tokensSaved: tokensSaved,
    );
  }

  /// Converts this telemetry model to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'currentEstimatedTokens': currentEstimatedTokens,
      'budgetCap': budgetCap,
      'usageRatio': usageRatio,
      'isWarning': isWarning,
      'isCircuitBreakerTriggered': isCircuitBreakerTriggered,
      'compressionCount': compressionCount,
      'tokensSaved': tokensSaved,
    };
  }

  /// Creates a telemetry instance from JSON map.
  factory TokenBudgetTelemetry.fromJson(Map<String, dynamic> json) {
    return TokenBudgetTelemetry(
      currentEstimatedTokens: json['currentEstimatedTokens'] as int? ?? 0,
      budgetCap: json['budgetCap'] as int? ?? 32000,
      usageRatio: (json['usageRatio'] as num?)?.toDouble() ?? 0.0,
      isWarning: json['isWarning'] as bool? ?? false,
      isCircuitBreakerTriggered: json['isCircuitBreakerTriggered'] as bool? ?? false,
      compressionCount: json['compressionCount'] as int? ?? 0,
      tokensSaved: json['tokensSaved'] as int? ?? 0,
    );
  }

  /// Copies instance with optional overrides.
  TokenBudgetTelemetry copyWith({
    int? currentEstimatedTokens,
    int? budgetCap,
    double? usageRatio,
    bool? isWarning,
    bool? isCircuitBreakerTriggered,
    int? compressionCount,
    int? tokensSaved,
  }) {
    return TokenBudgetTelemetry(
      currentEstimatedTokens: currentEstimatedTokens ?? this.currentEstimatedTokens,
      budgetCap: budgetCap ?? this.budgetCap,
      usageRatio: usageRatio ?? this.usageRatio,
      isWarning: isWarning ?? this.isWarning,
      isCircuitBreakerTriggered: isCircuitBreakerTriggered ?? this.isCircuitBreakerTriggered,
      compressionCount: compressionCount ?? this.compressionCount,
      tokensSaved: tokensSaved ?? this.tokensSaved,
    );
  }

  @override
  String toString() {
    return 'TokenBudgetTelemetry(tokens: $currentEstimatedTokens/$budgetCap, ratio: ${(usageRatio * 100).toStringAsFixed(1)}%, warning: $isWarning, tripped: $isCircuitBreakerTriggered, saved: $tokensSaved)';
  }
}
