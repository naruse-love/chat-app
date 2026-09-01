/// MCP 传输通道类型与连接状态枚举
enum McpTransportType {
  /// 基于本地进程的标准输入输出（Stdio）
  stdio,

  /// 基于 HTTP Server-Sent Events (SSE) + POST
  sse,

  /// 基于全双工 WebSocket
  websocket,
}

/// MCP 连接生命周期状态
enum McpConnectionStatus {
  /// 已断开连接
  disconnected,

  /// 正在建立连接
  connecting,

  /// 已成功连接
  connected,

  /// 连接出错
  error,
}

extension McpTransportTypeExtension on McpTransportType {
  String get nameString {
    switch (this) {
      case McpTransportType.stdio:
        return 'stdio';
      case McpTransportType.sse:
        return 'sse';
      case McpTransportType.websocket:
        return 'websocket';
    }
  }

  String get displayName {
    switch (this) {
      case McpTransportType.stdio:
        return '标准进程 (Stdio)';
      case McpTransportType.sse:
        return 'Server-Sent Events (SSE)';
      case McpTransportType.websocket:
        return 'WebSocket';
    }
  }

  static McpTransportType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'stdio':
        return McpTransportType.stdio;
      case 'sse':
        return McpTransportType.sse;
      case 'websocket':
      case 'ws':
        return McpTransportType.websocket;
      default:
        return McpTransportType.stdio;
    }
  }
}

extension McpConnectionStatusExtension on McpConnectionStatus {
  String get displayName {
    switch (this) {
      case McpConnectionStatus.disconnected:
        return '未连接';
      case McpConnectionStatus.connecting:
        return '连接中...';
      case McpConnectionStatus.connected:
        return '已连接';
      case McpConnectionStatus.error:
        return '连接异常';
    }
  }
}
