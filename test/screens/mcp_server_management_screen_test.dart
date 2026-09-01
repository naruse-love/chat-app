import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/mcp/mcp_server_config.dart';
import 'package:chat/models/mcp/mcp_server_state.dart';
import 'package:chat/models/mcp/mcp_tool_info.dart';
import 'package:chat/models/mcp/mcp_transport_type.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/providers/mcp_provider.dart';
import 'package:chat/screens/mcp_server_management_screen.dart';

class MockMcpNotifier extends StateNotifier<McpState> implements McpNotifier {
  final List<String> connectedServerIds = [];
  final List<String> disconnectedServerIds = [];
  final List<McpServerConfig> addedConfigs = [];
  final List<McpServerConfig> updatedConfigs = [];
  final List<String> deletedServerIds = [];
  final Map<String, bool> toggledServers = {};

  MockMcpNotifier([McpState? initial]) : super(initial ?? const McpState());

  void setState(McpState s) => state = s;

  @override
  Future<void> loadServers() async {}

  @override
  Future<void> addServer(McpServerConfig config, {Map<String, String>? headers}) async {
    addedConfigs.add(config);
    state = state.copyWith(servers: [
      ...state.servers,
      McpServerState(config: config, status: McpConnectionStatus.disconnected),
    ]);
  }

  @override
  Future<void> updateServer(McpServerConfig config, {Map<String, String>? headers}) async {
    updatedConfigs.add(config);
    state = state.copyWith(
      servers: state.servers.map((s) => s.config.id == config.id ? s.copyWith(config: config) : s).toList(),
    );
  }

  @override
  Future<void> deleteServer(String id) async {
    deletedServerIds.add(id);
    state = state.copyWith(
      servers: state.servers.where((s) => s.config.id != id).toList(),
    );
  }

  @override
  Future<void> toggleServerEnabled(String id, bool isEnabled) async {
    toggledServers[id] = isEnabled;
    state = state.copyWith(
      servers: state.servers.map((s) {
        if (s.config.id == id) {
          return s.copyWith(config: s.config.copyWith(isEnabled: isEnabled));
        }
        return s;
      }).toList(),
    );
  }

  @override
  Future<void> connectServer(String id) async {
    connectedServerIds.add(id);
    state = state.copyWith(
      servers: state.servers.map((s) {
        if (s.config.id == id) {
          return s.copyWith(status: McpConnectionStatus.connected);
        }
        return s;
      }).toList(),
    );
  }

  @override
  Future<void> disconnectServer(String id) async {
    disconnectedServerIds.add(id);
    state = state.copyWith(
      servers: state.servers.map((s) {
        if (s.config.id == id) {
          return s.copyWith(status: McpConnectionStatus.disconnected);
        }
        return s;
      }).toList(),
    );
  }

  @override
  Future<McpServerState> testConnection(McpServerConfig config, {Map<String, String>? headers}) async {
    if (config.url != null && config.url!.contains('fail')) {
      throw StateError('Connection refused');
    }
    return McpServerState(
      config: config,
      status: McpConnectionStatus.connected,
      tools: const [
        McpToolInfo(name: 'test_tool', description: 'Test tool description'),
      ],
      resources: const [
        McpResourceInfo(uri: 'file:///test.log', name: 'Test Log'),
      ],
      prompts: const [
        McpPromptInfo(name: 'test_prompt', description: 'Test prompt'),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createWidgetUnderTest(MockMcpNotifier notifier) {
    return ProviderScope(
      overrides: [
        mcpProvider.overrideWith((ref) => notifier),
      ],
      child: const MaterialApp(
        home: McpServerManagementScreen(),
      ),
    );
  }

  group('McpServerManagementScreen Deep & Adversarial Tests', () {
    testWidgets('Renders empty state placeholder when no servers configured', (tester) async {
      final notifier = MockMcpNotifier(const McpState(servers: []));

      await tester.pumpWidget(createWidgetUnderTest(notifier));
      await tester.pumpAndSettle();

      expect(find.text('MCP 服务管理'), findsOneWidget);
      expect(find.text('暂无 MCP 服务器配置'), findsOneWidget);
      expect(find.text('点击右下角按钮添加 MCP 服务，支持 SSE、WebSocket 与 Stdio 传输通道'), findsOneWidget);
      expect(find.text('添加服务'), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Renders loading spinner when loading with empty list', (tester) async {
      final notifier = MockMcpNotifier(const McpState(isLoading: true, servers: []));

      await tester.pumpWidget(createWidgetUnderTest(notifier));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Renders server cards with diverse transport types and status chips', (tester) async {
      final now = DateTime(2026, 8, 31);
      final server1 = McpServerState(
        config: McpServerConfig(
          id: 'srv-1',
          name: 'Filesystem SSE',
          transportType: McpTransportType.sse,
          url: 'http://localhost:8000/sse',
          createdAt: now,
          updatedAt: now,
        ),
        status: McpConnectionStatus.connected,
        tools: const [
          McpToolInfo(name: 'read_file', description: 'Read a file'),
          McpToolInfo(name: 'write_file', description: 'Write a file'),
        ],
      );

      final server2 = McpServerState(
        config: McpServerConfig(
          id: 'srv-2',
          name: 'Python Stdio',
          transportType: McpTransportType.stdio,
          command: 'python',
          arguments: ['server.py', '--verbose'],
          createdAt: now,
          updatedAt: now,
        ),
        status: McpConnectionStatus.error,
        errorMessage: 'Process exited with code 1',
      );

      final server3 = McpServerState(
        config: McpServerConfig(
          id: 'srv-3',
          name: 'WS Server',
          transportType: McpTransportType.websocket,
          url: 'ws://127.0.0.1:8080/mcp',
          createdAt: now,
          updatedAt: now,
        ),
        status: McpConnectionStatus.disconnected,
      );

      final notifier = MockMcpNotifier(McpState(servers: [server1, server2, server3]));

      await tester.pumpWidget(createWidgetUnderTest(notifier));
      await tester.pumpAndSettle();

      // Titles & Badges
      expect(find.text('Filesystem SSE'), findsOneWidget);
      expect(find.text('SSE'), findsOneWidget);
      expect(find.text('http://localhost:8000/sse'), findsOneWidget);
      expect(find.text('已连接 · 2 个工具'), findsOneWidget);

      expect(find.text('Python Stdio'), findsOneWidget);
      expect(find.text('Stdio'), findsOneWidget);
      expect(find.text('python server.py --verbose'), findsOneWidget);
      expect(find.text('连接失败: Process exited with code 1'), findsOneWidget);

      expect(find.text('WS Server'), findsOneWidget);
      expect(find.text('WebSocket'), findsOneWidget);
      expect(find.text('ws://127.0.0.1:8080/mcp'), findsOneWidget);
      expect(find.text('未连接'), findsOneWidget);
    });

    testWidgets('Opens Add Server dialog, validates fields, switches protocols, tests connection, and saves', (tester) async {
      final notifier = MockMcpNotifier(const McpState(servers: []));

      await tester.pumpWidget(createWidgetUnderTest(notifier));
      await tester.pumpAndSettle();

      // Tap FAB
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('添加 MCP 服务器'), findsOneWidget);
      expect(find.text('服务器名称 *'), findsOneWidget);

      // Validate required name
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入服务器名称'), findsOneWidget);

      // Enter name
      await tester.enterText(find.widgetWithText(TextFormField, '服务器名称 *'), 'My Stdio Server');

      // Switch protocol to Stdio
      await tester.tap(find.text('Server-Sent Events (SSE)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标准进程 (Stdio)').last);
      await tester.pumpAndSettle();

      // Verify Stdio form fields appear
      expect(find.text('可执行命令 (Command) *'), findsOneWidget);
      expect(find.text('命令行参数 (Arguments，可选)'), findsOneWidget);
      expect(find.text('工作目录 (Working Directory，可选)'), findsOneWidget);
      expect(find.text('环境变量 (Environment Variables，可选)'), findsOneWidget);

      // Fill in Stdio fields
      await tester.enterText(find.widgetWithText(TextFormField, '可执行命令 (Command) *'), 'python');
      await tester.enterText(find.widgetWithText(TextFormField, '命令行参数 (Arguments，可选)'), '-m server_module');
      await tester.pumpAndSettle();

      // Test connection button
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();

      // Expect connection success feedback
      expect(find.textContaining('连接成功！已探测到'), findsOneWidget);

      // Save
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(notifier.addedConfigs.length, 1);
      expect(notifier.addedConfigs.first.name, 'My Stdio Server');
      expect(notifier.addedConfigs.first.transportType, McpTransportType.stdio);
      expect(notifier.addedConfigs.first.command, 'python');
      expect(notifier.addedConfigs.first.arguments, ['-m', 'server_module']);
    });

    testWidgets('Toggles server enabled switch', (tester) async {
      final now = DateTime(2026, 8, 31);
      final server = McpServerState(
        config: McpServerConfig(
          id: 'srv-toggle-1',
          name: 'Toggle Server',
          transportType: McpTransportType.sse,
          url: 'http://localhost:8000/sse',
          isEnabled: true,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final notifier = MockMcpNotifier(McpState(servers: [server]));

      await tester.pumpWidget(createWidgetUnderTest(notifier));
      await tester.pumpAndSettle();

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(notifier.toggledServers['srv-toggle-1'], false);
    });

    testWidgets('Deletes server after confirmation dialog', (tester) async {
      final now = DateTime(2026, 8, 31);
      final server = McpServerState(
        config: McpServerConfig(
          id: 'srv-del-1',
          name: 'Delete Me Server',
          transportType: McpTransportType.sse,
          url: 'http://localhost:8000/sse',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final notifier = MockMcpNotifier(McpState(servers: [server]));

      await tester.pumpWidget(createWidgetUnderTest(notifier));
      await tester.pumpAndSettle();

      // Open popup menu
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      // Tap delete
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('删除 MCP 服务器'), findsOneWidget);
      expect(find.text('确定要删除服务器 "Delete Me Server" 吗？此操作将断开连接并注销其注入的所有动态工具。'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.widgetWithText(ElevatedButton, '删除'));
      await tester.pumpAndSettle();

      expect(notifier.deletedServerIds, contains('srv-del-1'));
    });

    testWidgets('Opens tools bottom sheet and displays discovered tools, resources, and prompts', (tester) async {
      final now = DateTime(2026, 8, 31);
      final server = McpServerState(
        config: McpServerConfig(
          id: 'srv-tools-1',
          name: 'Filesystem Server',
          transportType: McpTransportType.stdio,
          command: 'npx',
          defaultSecurityLevel: ToolSecurityLevel.readOnly,
          createdAt: now,
          updatedAt: now,
        ),
        status: McpConnectionStatus.connected,
        tools: const [
          McpToolInfo(
            name: 'read_file',
            description: 'Read the contents of a file',
            inputSchema: {
              'type': 'object',
              'properties': {
                'path': {'type': 'string', 'description': 'The path of the file to read'}
              },
              'required': ['path']
            },
          ),
        ],
        resources: const [
          McpResourceInfo(
            uri: 'file:///workspace/logs',
            name: 'Workspace Logs',
            mimeType: 'text/plain',
          ),
        ],
        prompts: const [
          McpPromptInfo(
            name: 'summarize_file',
            description: 'Summarize file contents',
            arguments: [
              McpPromptArgument(name: 'file_path', description: 'Path to file', required: true),
            ],
          ),
        ],
      );

      final notifier = MockMcpNotifier(McpState(servers: [server]));

      await tester.pumpWidget(createWidgetUnderTest(notifier));
      await tester.pumpAndSettle();

      // Tap on card to open bottom sheet
      await tester.tap(find.text('Filesystem Server'));
      await tester.pumpAndSettle();

      expect(find.text('状态: 已连接 · 发现 1 个工具'), findsOneWidget);
      expect(find.text('read_file'), findsOneWidget);
      expect(find.text('Read the contents of a file'), findsOneWidget);
      expect(find.text('• path'), findsOneWidget);
      expect(find.text('(string)'), findsOneWidget);

      // Switch to Resources Tab
      await tester.tap(find.text('资源 (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Workspace Logs'), findsOneWidget);
      expect(find.text('file:///workspace/logs'), findsOneWidget);

      // Switch to Prompts Tab
      await tester.tap(find.text('提示词 (1)'));
      await tester.pumpAndSettle();

      expect(find.text('summarize_file'), findsOneWidget);
      expect(find.text('Summarize file contents'), findsOneWidget);
      expect(find.text('1 个参数'), findsOneWidget);
    });
  });
}
