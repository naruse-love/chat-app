import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool_call.dart';
import 'package:chat/models/tool/tool_confirmation.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chat/screens/settings_screen.dart';
import 'package:chat/widgets/chat_bubble.dart';
import 'package:chat/widgets/tool_confirmation_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestableWidget(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );
  }

  group('MCP Badges and UI Rendering Tests', () {
    testWidgets('ChatBubble renders intermediate assistant panel with mcp_ tool', (tester) async {
      final msg = ChatMessage(
        id: 'msg-mcp-1',
        conversationId: 'conv-1',
        role: 'assistant',
        content: '我正在为您调用 MCP 动态工具...',
        timestamp: DateTime(2026, 8, 31, 12, 0),
        toolCalls: [
          ToolCall(
            id: 'call-mcp-1',
            type: 'function',
            functionName: 'mcp_filesystem_read_file',
            arguments: '{"path":"/workspace/data.json"}',
          ),
        ],
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: msg)));
      await tester.pumpAndSettle();

      // Summary title in collapsed header
      expect(find.text('思考与工具调用 [MCP: filesystem_read_file]'), findsOneWidget);

      // Expand panel
      await tester.tap(find.byIcon(Icons.auto_awesome));
      await tester.pumpAndSettle();

      expect(find.text('MCP: filesystem_read_file'), findsOneWidget);
      expect(find.text('MCP 扩展工具'), findsOneWidget);
      expect(find.text('MCP'), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
      expect(find.text('mcp_filesystem_read_file({"path":"/workspace/data.json"})'), findsOneWidget);
    });

    testWidgets('ChatBubble renders tool execution response with MCP badge and markdown content', (tester) async {
      final toolMsg = ChatMessage(
        id: 'msg-mcp-tool-res',
        conversationId: 'conv-1',
        role: 'tool',
        toolCallId: 'call-mcp-1',
        content: '### MCP 执行成功\n- 状态: 正常\n- 数据量: 1024 字节',
        timestamp: DateTime(2026, 8, 31, 12, 1),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: toolMsg)));
      await tester.pumpAndSettle();

      expect(find.text('工具执行结果'), findsOneWidget);

      // Expand tool result
      await tester.tap(find.text('工具执行结果'));
      await tester.pumpAndSettle();

      expect(find.textContaining('MCP 执行成功'), findsOneWidget);
    });

    testWidgets('ToolConfirmationCard renders MCP dynamic tool with deep purple styling and preview', (tester) async {
      bool? decision;
      String? rejectReason;

      final request = ToolConfirmationRequest(
        confirmationId: 'conf-mcp-1',
        toolCallId: 'call-mcp-confirm-1',
        toolName: 'mcp_database_execute_query',
        displayName: '[MCP: Database] execute_query',
        description: '执行远程 SQL 写入操作',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {
          'query': 'INSERT INTO users VALUES (1, "Alice")',
          'database': 'production_db',
        },
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ToolConfirmationCard(
            request: request,
            onDecision: ({required allow, reason}) {
              decision = allow;
              rejectReason = reason;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and MCP chip
      expect(find.text('[MCP: Database] execute_query'), findsOneWidget);
      expect(find.text('MCP 动态工具'), findsWidgets);
      expect(find.text('敏感确认'), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsWidgets);

      // Verify parameter preview
      expect(find.text('MCP 远程参数调用:'), findsOneWidget);
      expect(find.text('• query: INSERT INTO users VALUES (1, "Alice")'), findsOneWidget);
      expect(find.text('• database: production_db'), findsOneWidget);

      // Test reject with reason
      await tester.tap(find.text('拒绝理由'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '不具备执行权限');
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();

      expect(decision, false);
      expect(rejectReason, '不具备执行权限');
    });

    testWidgets('ToolConfirmationCard allows authorizing MCP tool execution', (tester) async {
      bool? decision;

      final request = ToolConfirmationRequest(
        confirmationId: 'conf-mcp-2',
        toolCallId: 'call-mcp-confirm-2',
        toolName: 'mcp_remote_exec',
        displayName: '[MCP: Remote] exec_cmd',
        description: '执行远程脚本',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'cmd': 'ls -la'},
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ToolConfirmationCard(
            request: request,
            onDecision: ({required allow, reason}) {
              decision = allow;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap allow
      await tester.tap(find.text('允许执行'));
      await tester.pumpAndSettle();

      expect(decision, true);
    });

    testWidgets('SettingsScreen renders MCP Server Management ListTile', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('MCP 服务管理'), findsOneWidget);
      expect(find.text('管理 Model Context Protocol 服务器与扩展工具'), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
    });
  });
}
