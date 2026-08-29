import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/tool/tool_confirmation.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/services/tools/file_write_tool.dart';
import 'package:chat/utils/diff_helper.dart';
import 'package:chat/widgets/tool_confirmation_card.dart';

void main() {
  group('ToolConfirmationCard Tests', () {
    testWidgets('Renders file_write preview with DiffViewer and triggers approval', (tester) async {
      bool? approvedResult;
      String? rejectedReasonResult;

      const preview = FileWritePreview(
        relativePath: 'notes.txt',
        oldContent: 'old notes',
        newContent: 'new notes',
        diffLines: [
          DiffLine(type: DiffLineType.deleted, text: 'old notes', oldLineNumber: 1),
          DiffLine(type: DiffLineType.added, text: 'new notes', newLineNumber: 1),
        ],
        diffSummary: DiffSummary(additions: 1, deletions: 1, unchanged: 0),
        fileExisted: true,
        mode: 'overwrite',
      );

      final request = ToolConfirmationRequest(
        confirmationId: 'req_1',
        toolCallId: 'call_1',
        toolName: 'file_write',
        displayName: '沙箱文件写入',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'path': 'notes.txt', 'content': 'new notes'},
        description: '写入沙箱文件',
        previewData: preview,
        status: ToolConfirmationStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolConfirmationCard(
              request: request,
              onDecision: ({required bool allow, String? reason}) {
                approvedResult = allow;
                rejectedReasonResult = reason;
              },
            ),
          ),
        ),
      );

      expect(find.text('沙箱文件写入'), findsOneWidget);
      expect(find.text('敏感确认'), findsOneWidget);
      expect(find.text('写入路径: notes.txt'), findsOneWidget);
      expect(find.text('覆盖写入'), findsOneWidget);
      expect(find.text('old notes'), findsOneWidget);
      expect(find.text('new notes'), findsOneWidget);

      // Tap Allow button
      await tester.tap(find.text('允许执行'));
      await tester.pumpAndSettle();

      expect(approvedResult, isTrue);
      expect(rejectedReasonResult, isNull);
    });

    testWidgets('Renders file_delete danger preview and triggers rejection with custom reason', (tester) async {
      bool? approvedResult;
      String? rejectedReasonResult;

      final request = ToolConfirmationRequest(
        confirmationId: 'req_del',
        toolCallId: 'call_del',
        toolName: 'file_delete',
        displayName: '沙箱文件删除',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'path': 'important.db', 'recursive': true},
        description: '删除沙箱中的重要数据库',
        previewData: {'path': 'important.db', 'recursive': true},
        status: ToolConfirmationStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ToolConfirmationCard(
                request: request,
                onDecision: ({required bool allow, String? reason}) {
                  approvedResult = allow;
                  rejectedReasonResult = reason;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('沙箱文件删除'), findsOneWidget);
      expect(find.text('警告：此操作将永久删除本地文件或目录'), findsOneWidget);
      expect(find.text('目标路径: important.db'), findsOneWidget);
      expect(find.text('模式: 递归删除子项 (recursive=true)'), findsOneWidget);

      // Tap '拒绝理由' button to show textfield
      await tester.tap(find.text('拒绝理由'));
      await tester.pumpAndSettle();

      // Enter rejection reason
      await tester.enterText(find.byType(TextField), '重要文件不可删除');
      await tester.pumpAndSettle();

      // Tap Reject button
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();

      expect(approvedResult, isFalse);
      expect(rejectedReasonResult, equals('重要文件不可删除'));
    });

    testWidgets('Renders code_eval sandbox preview', (tester) async {
      final request = ToolConfirmationRequest(
        confirmationId: 'req_code',
        toolCallId: 'call_code',
        toolName: 'code_eval',
        displayName: '代码沙箱执行',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'code': 'print("hello eval")', 'timeout_ms': 5000},
        description: '执行 Python 脚本',
        previewData: {'code': 'print("hello eval")', 'timeout_ms': 5000},
        status: ToolConfirmationStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolConfirmationCard(
              request: request,
              onDecision: ({required bool allow, String? reason}) {},
            ),
          ),
        ),
      );

      expect(find.text('代码沙箱执行'), findsOneWidget);
      expect(find.text('执行代码沙箱 (超时: 5000ms)'), findsOneWidget);
      expect(find.text('print("hello eval")'), findsOneWidget);
    });

    testWidgets('Renders clipboard_write preview', (tester) async {
      final request = ToolConfirmationRequest(
        confirmationId: 'req_clip',
        toolCallId: 'call_clip',
        toolName: 'clipboard_write',
        displayName: '写入剪贴板',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'text': 'copied token 123456'},
        description: '写入凭证到剪贴板',
        previewData: {'text': 'copied token 123456'},
        status: ToolConfirmationStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolConfirmationCard(
              request: request,
              onDecision: ({required bool allow, String? reason}) {},
            ),
          ),
        ),
      );

      expect(find.text('写入剪贴板'), findsOneWidget);
      expect(find.text('写入系统剪贴板内容:'), findsOneWidget);
      expect(find.text('copied token 123456'), findsOneWidget);
    });

    testWidgets('Triggers onCancel callback when close icon button is tapped', (tester) async {
      bool cancelCalled = false;
      final request = ToolConfirmationRequest(
        confirmationId: 'req_canc',
        toolCallId: 'call_canc',
        toolName: 'file_delete',
        displayName: '沙箱文件删除',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'path': 'cancel_me.txt'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolConfirmationCard(
              request: request,
              onDecision: ({required bool allow, String? reason}) {},
              onCancel: () {
                cancelCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      expect(cancelCalled, isTrue);
    });

    testWidgets('Renders default fallback description when request description is null', (tester) async {
      final request = ToolConfirmationRequest(
        confirmationId: 'req_nodesc',
        toolCallId: 'call_nodesc',
        toolName: 'custom_native_tool',
        displayName: '自定义特权工具',
        securityLevel: ToolSecurityLevel.privilegedNative,
        arguments: {'action': 'reboot', 'force': true},
        description: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolConfirmationCard(
              request: request,
              onDecision: ({required bool allow, String? reason}) {},
            ),
          ),
        ),
      );

      expect(find.text('模型请求执行受限操作，需要您的明确确认。'), findsOneWidget);
      expect(find.text('特权原生'), findsOneWidget);
      expect(find.textContaining('action: reboot'), findsOneWidget);
    });

    testWidgets('Renders properly in Dark Theme without overflow', (tester) async {
      final request = ToolConfirmationRequest(
        confirmationId: 'req_dark',
        toolCallId: 'call_dark',
        toolName: 'code_eval',
        displayName: '代码沙箱执行',
        securityLevel: ToolSecurityLevel.sensitiveConfirm,
        arguments: {'code': 'return 42;'},
        description: '暗色主题测试',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: ToolConfirmationCard(
              request: request,
              onDecision: ({required bool allow, String? reason}) {},
            ),
          ),
        ),
      );

      expect(find.text('代码沙箱执行'), findsOneWidget);
      expect(find.text('暗色主题测试'), findsOneWidget);
    });
  });
}

