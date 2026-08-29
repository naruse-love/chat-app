import 'tool_security_level.dart';

/// Status of a Human-in-the-Loop (HITL) tool confirmation request.
enum ToolConfirmationStatus {
  /// Waiting for user decision in UI.
  pending('待确认'),

  /// User approved the execution.
  approved('已允许'),

  /// User explicitly rejected the execution.
  rejected('已拒绝'),

  /// Request cancelled (e.g. Generation aborted or session reset).
  cancelled('已取消');

  final String label;
  const ToolConfirmationStatus(this.label);

  String toJson() => name;

  static ToolConfirmationStatus fromJson(String name) {
    return ToolConfirmationStatus.values.firstWhere(
      (e) => e.name == name || e.name.toLowerCase() == name.toLowerCase(),
      orElse: () => ToolConfirmationStatus.pending,
    );
  }
}

/// User's decision regarding a tool confirmation request.
class ToolConfirmationDecision {
  /// Whether the user approved the tool execution.
  final bool isApproved;

  /// Optional explanation if rejected or cancelled.
  final String? rejectionReason;

  /// Timestamp when decision was made.
  final DateTime timestamp;

  ToolConfirmationDecision({
    required this.isApproved,
    this.rejectionReason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Whether the user explicitly rejected this request.
  bool get isRejected => !isApproved && (rejectionReason == null || !rejectionReason!.contains('取消'));

  /// Whether this request was cancelled (e.g. aborted stream).
  bool get isCancelled => !isApproved && (rejectionReason != null && rejectionReason!.contains('取消'));

  /// Factory for approval.
  factory ToolConfirmationDecision.approve({DateTime? timestamp}) {
    return ToolConfirmationDecision(
      isApproved: true,
      rejectionReason: null,
      timestamp: timestamp,
    );
  }

  /// Factory for rejection with an optional reason.
  factory ToolConfirmationDecision.reject([String? reason, DateTime? timestamp]) {
    return ToolConfirmationDecision(
      isApproved: false,
      rejectionReason: reason ?? '用户拒绝了此工具调用',
      timestamp: timestamp,
    );
  }

  /// Factory for cancellation.
  factory ToolConfirmationDecision.cancel([String? reason, DateTime? timestamp]) {
    return ToolConfirmationDecision(
      isApproved: false,
      rejectionReason: reason ?? '操作已取消',
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isApproved': isApproved,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ToolConfirmationDecision.fromJson(Map<String, dynamic> json) {
    return ToolConfirmationDecision(
      isApproved: json['isApproved'] as bool? ?? false,
      rejectionReason: json['rejectionReason'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  String toString() =>
      'ToolConfirmationDecision(isApproved: $isApproved, reason: $rejectionReason)';
}

/// A structured request presented to the user for Level 2 sensitive tool confirmation.
class ToolConfirmationRequest {
  /// Unique request identifier.
  final String confirmationId;

  /// Underlying tool call ID emitted by the LLM.
  final String toolCallId;

  /// Programmatic tool name (e.g. 'file_write', 'file_delete', 'code_eval', 'clipboard_write').
  final String toolName;

  /// Localized display name (e.g. '写入文件', '删除文件', '代码执行', '写入剪贴板').
  final String displayName;

  /// Security classification level (typically Level 2 sensitiveConfirm).
  final ToolSecurityLevel securityLevel;

  /// Parsed runtime arguments.
  final Map<String, dynamic> arguments;

  /// Human-friendly description of what this operation will do.
  final String? description;

  /// Visual preview payload (e.g. Diff data, code snippet, file path, text preview).
  final dynamic previewData;

  /// Request creation timestamp.
  final DateTime timestamp;

  /// Current confirmation status.
  final ToolConfirmationStatus status;

  /// Recorded decision once resolved.
  final ToolConfirmationDecision? decision;

  ToolConfirmationRequest({
    required this.confirmationId,
    required this.toolCallId,
    required this.toolName,
    required this.displayName,
    this.securityLevel = ToolSecurityLevel.sensitiveConfirm,
    required this.arguments,
    this.description,
    this.previewData,
    DateTime? timestamp,
    this.status = ToolConfirmationStatus.pending,
    this.decision,
  }) : timestamp = timestamp ?? DateTime.now();

  ToolConfirmationRequest copyWith({
    String? confirmationId,
    String? toolCallId,
    String? toolName,
    String? displayName,
    ToolSecurityLevel? securityLevel,
    Map<String, dynamic>? arguments,
    String? description,
    dynamic previewData,
    DateTime? timestamp,
    ToolConfirmationStatus? status,
    ToolConfirmationDecision? decision,
  }) {
    return ToolConfirmationRequest(
      confirmationId: confirmationId ?? this.confirmationId,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      displayName: displayName ?? this.displayName,
      securityLevel: securityLevel ?? this.securityLevel,
      arguments: arguments ?? this.arguments,
      description: description ?? this.description,
      previewData: previewData ?? this.previewData,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      decision: decision ?? this.decision,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'confirmationId': confirmationId,
      'toolCallId': toolCallId,
      'toolName': toolName,
      'displayName': displayName,
      'securityLevel': securityLevel.toJson(),
      'arguments': arguments,
      if (description != null) 'description': description,
      if (previewData != null) 'previewData': previewData,
      'timestamp': timestamp.toIso8601String(),
      'status': status.toJson(),
      if (decision != null) 'decision': decision!.toJson(),
    };
  }

  factory ToolConfirmationRequest.fromJson(Map<String, dynamic> json) {
    return ToolConfirmationRequest(
      confirmationId: json['confirmationId'] as String? ?? '',
      toolCallId: json['toolCallId'] as String? ?? '',
      toolName: json['toolName'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      securityLevel: json['securityLevel'] != null
          ? ToolSecurityLevel.fromJson(json['securityLevel'] as String)
          : ToolSecurityLevel.sensitiveConfirm,
      arguments: (json['arguments'] as Map<String, dynamic>?) ?? {},
      description: json['description'] as String?,
      previewData: json['previewData'],
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      status: json['status'] != null
          ? ToolConfirmationStatus.fromJson(json['status'] as String)
          : ToolConfirmationStatus.pending,
      decision: json['decision'] != null
          ? ToolConfirmationDecision.fromJson(json['decision'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  String toString() {
    return 'ToolConfirmationRequest(id: $confirmationId, tool: $toolName, status: ${status.name})';
  }
}
