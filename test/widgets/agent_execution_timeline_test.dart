import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/agent_step_telemetry.dart';
import 'package:chat/widgets/agent_execution_timeline.dart';

void main() {
  group('AgentExecutionTimelineWidget Tests', () {
    testWidgets('Renders nothing when steps list is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AgentExecutionTimelineWidget(
              steps: [],
            ),
          ),
        ),
      );

      expect(find.byType(AgentExecutionTimelineWidget), findsOneWidget);
      expect(find.textContaining('Agent 执行时间线'), findsNothing);
    });

    testWidgets('Renders header with step count, total duration, and success summary', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'math_eval',
          toolCategory: '基础实用',
          durationMs: 120,
          arguments: {'expression': '1 + 1'},
          outputPreview: '2',
          isSuccess: true,
        ),
        AgentStepTelemetry(
          stepIndex: 2,
          toolName: 'file_read',
          toolCategory: '沙箱与代码',
          durationMs: 380,
          arguments: {'path': 'notes.txt'},
          outputPreview: 'File content',
          isSuccess: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentExecutionTimelineWidget(
              steps: steps,
              initiallyExpanded: false,
            ),
          ),
        ),
      );

      expect(find.text('Agent 执行时间线 (2 步)'), findsOneWidget);
      expect(find.text('共耗时: 500 ms'), findsOneWidget);
      expect(find.text('2/2 成功'), findsOneWidget);
    });

    testWidgets('Header displays failed step count when some steps fail', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'weather_query',
          toolCategory: '基础实用',
          durationMs: 250,
          arguments: {'city': 'Beijing'},
          outputPreview: 'Sunny',
          isSuccess: true,
        ),
        AgentStepTelemetry(
          stepIndex: 2,
          toolName: 'code_eval',
          toolCategory: '沙箱与代码',
          durationMs: 3000,
          arguments: {'code': 'while(true){}'},
          errorMessage: '执行超时 (3000ms)',
          isSuccess: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentExecutionTimelineWidget(
              steps: steps,
              initiallyExpanded: true,
            ),
          ),
        ),
      );

      expect(find.text('• 1 步失败'), findsOneWidget);
      expect(find.text('1/2 成功'), findsOneWidget);
    });

    testWidgets('Renders all 4 dimensional category badges correctly', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'math_eval',
          toolCategory: '基础实用',
          durationMs: 50,
          arguments: {'expr': '42'},
          isSuccess: true,
        ),
        AgentStepTelemetry(
          stepIndex: 2,
          toolName: 'file_write',
          toolCategory: '沙箱与代码',
          durationMs: 150,
          arguments: {'path': 'test.txt'},
          isSuccess: true,
        ),
        AgentStepTelemetry(
          stepIndex: 3,
          toolName: 'calendar_create_event',
          toolCategory: '移动原生',
          durationMs: 200,
          arguments: {'title': 'Meeting'},
          isSuccess: true,
        ),
        AgentStepTelemetry(
          stepIndex: 4,
          toolName: 'mcp_git_status',
          toolCategory: '动态MCP',
          durationMs: 80,
          arguments: {},
          isSuccess: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentExecutionTimelineWidget(
                steps: steps,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('基础实用'), findsOneWidget);
      expect(find.text('沙箱与代码'), findsOneWidget);
      expect(find.text('移动原生'), findsOneWidget);
      expect(find.text('动态MCP'), findsOneWidget);

      expect(find.text('math_eval'), findsOneWidget);
      expect(find.text('file_write'), findsOneWidget);
      expect(find.text('calendar_create_event'), findsOneWidget);
      expect(find.text('mcp_git_status'), findsOneWidget);
    });

    testWidgets('Toggles timeline expand and collapse on header tap', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'wiki_lookup',
          toolCategory: '基础实用',
          durationMs: 100,
          arguments: {'query': 'Flutter'},
          isSuccess: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentExecutionTimelineWidget(
              steps: steps,
              initiallyExpanded: false,
            ),
          ),
        ),
      );

      // Initially collapsed: step item content is in first child (shrink)
      expect(find.text('wiki_lookup'), findsNothing);

      // Tap header to expand
      await tester.tap(find.text('Agent 执行时间线 (1 步)'));
      await tester.pumpAndSettle();

      expect(find.text('wiki_lookup'), findsOneWidget);

      // Tap header again to collapse
      await tester.tap(find.text('Agent 执行时间线 (1 步)'));
      await tester.pumpAndSettle();

      expect(find.text('wiki_lookup'), findsNothing);
    });

    testWidgets('Expanding step item shows reasoning intent, JSON arguments, and output', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'contacts_search',
          toolCategory: '移动原生',
          durationMs: 140,
          intent: '查找张三的电话号码以便发送通知',
          arguments: {'query': '张三'},
          fullOutput: '姓名: 张三\n电话: +86 138****1234',
          isSuccess: true,
          promptTokens: 150,
          isCompressed: true,
          isCircuitBreakerTriggered: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentExecutionTimelineWidget(
                steps: steps,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );

      // Intent preview is visible when unexpanded
      expect(find.text('意图: 查找张三的电话号码以便发送通知'), findsOneWidget);
      expect(find.text('已压缩历史'), findsOneWidget);
      expect(find.text('触发熔断'), findsOneWidget);
      expect(find.text('🪙 150 tok'), findsOneWidget);

      // Tap step to expand details
      await tester.tap(find.text('contacts_search'));
      await tester.pumpAndSettle();

      expect(find.text('推理意图:'), findsOneWidget);
      expect(find.text('查找张三的电话号码以便发送通知'), findsOneWidget);
      expect(find.text('输入参数:'), findsOneWidget);
      expect(find.text('复制参数'), findsOneWidget);
      expect(find.text('执行输出:'), findsOneWidget);
      expect(find.text('复制输出'), findsOneWidget);
      expect(find.textContaining('姓名: 张三'), findsOneWidget);

      // Tap copy buttons
      await tester.tap(find.text('复制参数'));
      await tester.pumpAndSettle();
      expect(find.text('已复制参数 JSON'), findsOneWidget);

      await tester.tap(find.text('复制输出'));
      await tester.pumpAndSettle();
      expect(find.text('已复制执行输出'), findsOneWidget);
    });

    testWidgets('Displays error message and self-healing diagnostic feedback when step failed', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'file_read',
          toolCategory: '沙箱与代码',
          durationMs: 45,
          arguments: {'path': 'invalid.txt'},
          isSuccess: false,
          errorMessage: '文件不存在或路径不合法',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentExecutionTimelineWidget(
                steps: steps,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );

      // Tap to expand
      await tester.tap(find.text('file_read'));
      await tester.pumpAndSettle();

      expect(find.text('执行异常:'), findsOneWidget);
      expect(find.text('自愈诊断反馈'), findsOneWidget);
      expect(find.text('文件不存在或路径不合法'), findsOneWidget);
    });

    testWidgets('Supports long markdown output with expand/collapse toggle', (tester) async {
      final items = List.generate(20, (i) => '- 项目条目 $i: 详细计算指标与状态数据').join('\n');
      final longMarkdown = '### 分析结果报告\n\n$items';
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'web_search',
          toolCategory: '基础实用',
          durationMs: 350,
          arguments: {'query': '2026 最新前沿资讯'},
          fullOutput: longMarkdown,
          isSuccess: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentExecutionTimelineWidget(
                steps: steps,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('web_search'));
      await tester.pumpAndSettle();

      expect(find.text('查看完整结果 ▾'), findsOneWidget);
      await tester.tap(find.text('查看完整结果 ▾'));
      await tester.pumpAndSettle();

      expect(find.text('收起完整结果 ▴'), findsOneWidget);
    });

    testWidgets('Adapts gracefully to dark theme and custom title', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'custom_tool',
          toolCategory: '未分类',
          durationMs: 1200,
          arguments: {},
          isSuccess: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: AgentExecutionTimelineWidget(
              steps: steps,
              title: '自定义时间线 (1 步)',
              initiallyExpanded: true,
            ),
          ),
        ),
      );

      expect(find.text('自定义时间线 (1 步)'), findsOneWidget);
      expect(find.text('共耗时: 1.20 s'), findsOneWidget);
      expect(find.text('custom_tool'), findsOneWidget);
    });
  });
}
