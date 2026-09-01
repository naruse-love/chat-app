import 'dart:async';
import '../../../models/mcp/mcp_transport_type.dart';

/// MCP 传输通道抽象基类
/// 定义 MCP 客户端与 MCP 服务器之间的底层双向消息传输契约
abstract class McpTransport {
  /// 传输通道类型
  McpTransportType get transportType;

  /// 当前连接状态
  McpConnectionStatus get status;

  /// 是否处于已连接状态
  bool get isConnected => status == McpConnectionStatus.connected;

  /// 连接状态变更流
  Stream<McpConnectionStatus> get statusStream;

  /// 接收到的 JSON-RPC 消息流
  Stream<Map<String, dynamic>> get messageStream;

  /// 建立连接
  Future<void> connect();

  /// 发送 JSON-RPC 消息（已编码为 Map 字典）
  Future<void> send(Map<String, dynamic> message);

  /// 关闭连接并释放所有资源
  Future<void> close();
}
