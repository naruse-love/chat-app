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
