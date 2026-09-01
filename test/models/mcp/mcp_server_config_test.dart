import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/mcp/mcp_server_config.dart';
import 'package:chat/models/mcp/mcp_server_state.dart';
import 'package:chat/models/mcp/mcp_tool_info.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/models/tool/tool_security_level.dart';

void main() {
  group('McpServerConfig Tests', () {
    test('Constructs with defaults and properties', () {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'server_1',
        name: 'Local Python MCP',
        transportType: McpTransportType.stdio,
        command: 'python',
        arguments: ['-m', 'mcp_server'],
        environment: {'PYTHONUNBUFFERED': '1'},
        workingDirectory: '/path/to/dir',
        createdAt: now,
        updatedAt: now,
      );

      expect(config.id, 'server_1');
      expect(config.name, 'Local Python MCP');
      expect(config.transportType, McpTransportType.stdio);
      expect(config.command, 'python');
      expect(config.arguments, ['-m', 'mcp_server']);
      expect(config.environment, {'PYTHONUNBUFFERED': '1'});
      expect(config.workingDirectory, '/path/to/dir');
      expect(config.isEnabled, isTrue);
      expect(config.autoConnect, isTrue);
      expect(config.defaultSecurityLevel, ToolSecurityLevel.readOnly);
      expect(config.createdAt, now);
      expect(config.updatedAt, now);
    });

    test('copyWith works correctly', () {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'server_1',
        name: 'Old Name',
        transportType: McpTransportType.sse,
        url: 'http://localhost:8080/sse',
        createdAt: now,
        updatedAt: now,
      );

      final updated = config.copyWith(
        name: 'New Name',
        isEnabled: false,
        autoConnect: false,
        defaultSecurityLevel: ToolSecurityLevel.sensitiveConfirm,
      );

      expect(updated.id, 'server_1');
      expect(updated.name, 'New Name');
      expect(updated.transportType, McpTransportType.sse);
      expect(updated.url, 'http://localhost:8080/sse');
      expect(updated.isEnabled, isFalse);
      expect(updated.autoConnect, isFalse);
      expect(updated.defaultSecurityLevel, ToolSecurityLevel.sensitiveConfirm);
    });

    test('toMap and fromMap with stdio serialization', () {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'stdio_srv',
        name: 'Stdio Server',
        transportType: McpTransportType.stdio,
        command: 'npx',
        arguments: ['-y', '@modelcontextprotocol/server-everything'],
        environment: {'DEBUG': 'true'},
        workingDirectory: '/app',
        headersRef: 'mcp_headers_stdio_srv',
        isEnabled: true,
        autoConnect: false,
        defaultSecurityLevel: ToolSecurityLevel.privilegedNative,
        createdAt: now,
        updatedAt: now,
      );

      final map = config.toMap();
      expect(map['id'], 'stdio_srv');
      expect(map['name'], 'Stdio Server');
      expect(map['transportType'], 'stdio');
      expect(map['command'], 'npx');
      expect(map['arguments'], '["-y","@modelcontextprotocol/server-everything"]');
      expect(map['environment'], '{"DEBUG":"true"}');
      expect(map['isEnabled'], 1);
      expect(map['autoConnect'], 0);
      expect(map['defaultSecurityLevel'], 3);

      final restored = McpServerConfig.fromMap(map, headers: {'X-Custom': 'val'});
      expect(restored.id, config.id);
      expect(restored.name, config.name);
      expect(restored.transportType, McpTransportType.stdio);
      expect(restored.command, 'npx');
      expect(restored.arguments, ['-y', '@modelcontextprotocol/server-everything']);
      expect(restored.environment, {'DEBUG': 'true'});
      expect(restored.workingDirectory, '/app');
      expect(restored.headersRef, 'mcp_headers_stdio_srv');
      expect(restored.headers, {'X-Custom': 'val'});
      expect(restored.isEnabled, isTrue);
      expect(restored.autoConnect, isFalse);
      expect(restored.defaultSecurityLevel, ToolSecurityLevel.privilegedNative);
    });

    test('toJson and fromJson with SSE and headers', () {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'sse_srv',
        name: 'Remote SSE',
        transportType: McpTransportType.sse,
        url: 'https://api.example.com/mcp/sse',
        headers: {'Authorization': 'Bearer test-token'},
        headersRef: 'mcp_headers_sse_srv',
        isEnabled: true,
        autoConnect: true,
        defaultSecurityLevel: ToolSecurityLevel.safe,
        createdAt: now,
        updatedAt: now,
      );

      final json = config.toJson();
      expect(json['id'], 'sse_srv');
      expect(json['transportType'], 'sse');
      expect(json['url'], 'https://api.example.com/mcp/sse');
      expect(json['headers'], {'Authorization': 'Bearer test-token'});
      expect(json['defaultSecurityLevel'], 0);

      final restored = McpServerConfig.fromJson(json);
      expect(restored, equals(config));
      expect(restored.hashCode, equals(config.hashCode));
    });

    test('Equality and hashCode', () {
      final now = DateTime.now();
      final cfg1 = McpServerConfig(
        id: 'id1',
        name: 'Name',
        transportType: McpTransportType.websocket,
        url: 'ws://localhost:9000',
        arguments: ['a', 'b'],
        environment: {'k': 'v'},
        headers: {'h': '1'},
        createdAt: now,
        updatedAt: now,
      );

      final cfg2 = McpServerConfig(
        id: 'id1',
        name: 'Name',
        transportType: McpTransportType.websocket,
        url: 'ws://localhost:9000',
        arguments: ['a', 'b'],
        environment: {'k': 'v'},
        headers: {'h': '1'},
        createdAt: now,
        updatedAt: now,
      );

      final cfg3 = cfg1.copyWith(name: 'Different Name');

      expect(cfg1, equals(cfg2));
      expect(cfg1.hashCode, equals(cfg2.hashCode));
      expect(cfg1, isNot(equals(cfg3)));
    });
  });

  group('McpServerState Tests', () {
    test('State properties and getters', () {
      final now = DateTime.now();
      final config = McpServerConfig(
        id: 'srv_state',
        name: 'State Server',
        transportType: McpTransportType.sse,
        url: 'http://localhost:3000/sse',
        createdAt: now,
        updatedAt: now,
      );

      const tool1 = McpToolInfo(name: 'calc', description: 'calculate');
      const tool2 = McpToolInfo(name: 'search', description: 'search web');
      const res1 = McpResourceInfo(uri: 'file:///log.txt', name: 'log');
      const prompt1 = McpPromptInfo(name: 'summary');

      final state = McpServerState(
        config: config,
        status: McpConnectionStatus.connected,
        tools: const [tool1, tool2],
        resources: const [res1],
        prompts: const [prompt1],
        serverInfo: const McpServerInfo(name: 'demo-server', version: '2.0.0'),
        capabilities: const McpServerCapabilities(tools: {}),
        lastConnectedAt: now,
      );

      expect(state.isConnected, isTrue);
      expect(state.isConnecting, isFalse);
      expect(state.isDisconnected, isFalse);
      expect(state.hasError, isFalse);
      expect(state.toolCount, 2);
      expect(state.resourceCount, 1);
      expect(state.promptCount, 1);
      expect(state.serverInfo?.name, 'demo-server');
      expect(state.capabilities?.supportsTools, isTrue);

      final errorState = state.copyWith(
        status: McpConnectionStatus.error,
        errorMessage: 'Network timeout',
      );
      expect(errorState.hasError, isTrue);
      expect(errorState.errorMessage, 'Network timeout');

      final clearedState = errorState.copyWith(clearError: true, status: McpConnectionStatus.disconnected);
      expect(clearedState.hasError, isFalse);
      expect(clearedState.errorMessage, isNull);
    });
  });
}
