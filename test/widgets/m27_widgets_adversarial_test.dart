import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/agent_step_telemetry.dart';
import 'package:chat/widgets/agent_execution_timeline.dart';
import 'package:chat/widgets/token_budget_badge.dart';

void main() {
  group('AgentExecutionTimelineWidget Adversarial & Stress Tests', () {
    testWidgets('Boundary: Empty steps list renders SizedBox.shrink with no layout overhead', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AgentExecutionTimelineWidget(
              steps: [],
              initiallyExpanded: true,
            ),
          ),
        ),
      );

      expect(find.byType(AgentExecutionTimelineWidget), findsOneWidget);
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.textContaining('Agent 执行时间线'), findsNothing);
    });

    testWidgets('Boundary: Single step renders cleanly with no dangling connector line', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'single_tool',
          toolCategory: '基础实用',
          durationMs: 0,
          arguments: {},
          isSuccess: true,
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

      expect(find.text('Agent 执行时间线 (1 步)'), findsOneWidget);
      expect(find.text('共耗时: 0 ms'), findsOneWidget);
      expect(find.text('1/1 成功'), findsOneWidget);
      expect(find.text('single_tool'), findsOneWidget);
    });

    testWidgets('Stress: Massive 100-step execution pipeline renders without layout overflow or memory leak', (tester) async {
      final categories = [
        '基础实用',
        '沙箱与代码',
        '移动原生',
        '动态MCP',
        '未知类别_XYZ',
        '',
      ];
      final massiveSteps = List.generate(
        100,
        (i) => AgentStepTelemetry(
          stepIndex: i + 1,
          toolName: 'tool_step_$i',
          toolCategory: categories[i % categories.length],
          durationMs: i * 50,
          arguments: {'index': i, 'payload': 'data_$i'},
          outputPreview: 'Result from step $i',
          isSuccess: i % 7 != 0, // step 0, 7, 14, ... failed
          errorMessage: i % 7 == 0 ? 'Error in step $i' : null,
          promptTokens: 100 + i * 10,
          isCompressed: i % 3 == 0,
          isCircuitBreakerTriggered: i == 99,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgentExecutionTimelineWidget(
                steps: massiveSteps,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );

      // Header summary
      final failedCount = massiveSteps.where((s) => !s.isSuccess).length;
      final successCount = massiveSteps.where((s) => s.isSuccess).length;
      expect(find.text('Agent 执行时间线 (100 步)'), findsOneWidget);
      expect(find.text('• $failedCount 步失败'), findsOneWidget);
      expect(find.text('$successCount/100 成功'), findsOneWidget);

      // Verify first and intermediate steps are present
      expect(find.text('tool_step_0'), findsOneWidget);
      expect(find.text('tool_step_1'), findsOneWidget);
    });

    testWidgets('Stress & Edge Case: Massive 50,000 char output & 5,000 char intent with Unicode & JSON', (tester) async {
      final hugeOutput = 'H' * 50000;
      final repeatIntent = '长文本测试 ' * 500;
      final hugeIntent = '🚀🌟 推理意图分析: $repeatIntent';
      final complexArgs = {
        'nested': {
          'level1': {
            'array': [1, 2, 'three', {'deep': true}],
            'unicode': '💡 汉字 测试 \n\t "escapes" \\ // special',
          }
        }
      };

      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'stress_tool',
          toolCategory: '沙箱与代码',
          durationMs: 45000,
          intent: hugeIntent,
          arguments: complexArgs,
          fullOutput: hugeOutput,
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

      // Expand step
      await tester.tap(find.text('stress_tool'));
      await tester.pumpAndSettle();

      expect(find.text('推理意图:'), findsOneWidget);
      expect(find.text('输入参数:'), findsOneWidget);
      expect(find.text('执行输出:'), findsOneWidget);
      expect(find.text('共耗时: 45.00 s'), findsOneWidget);
    });

    testWidgets('Boundary: Non-serializable / circular arguments map falls back to toString gracefully', (tester) async {
      final unencodableArgs = <String, dynamic>{
        'normalKey': 'value',
      };
      // Insert non-encodable object
      unencodableArgs['customObj'] = Object();

      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'unencodable_tool',
          toolCategory: '动态MCP',
          durationMs: 10,
          arguments: unencodableArgs,
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

      await tester.tap(find.text('unencodable_tool'));
      await tester.pumpAndSettle();

      expect(find.text('输入参数:'), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
    });

    testWidgets('Boundary: Durations and StepIndex zero/negative values handled cleanly', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 0, // Non-positive index -> falls back to index + 1 = 1
          toolName: 'step_zero',
          toolCategory: '时间工具',
          durationMs: 0,
          arguments: {},
          isSuccess: true,
        ),
        AgentStepTelemetry(
          stepIndex: -10, // Negative index -> falls back to index + 1 = 2
          toolName: 'step_neg',
          toolCategory: '代码执行',
          durationMs: 999, // 999 ms
          arguments: {},
          isSuccess: true,
        ),
        AgentStepTelemetry(
          stepIndex: 3,
          toolName: 'step_sec',
          toolCategory: '设备日历',
          durationMs: 1000, // 1.00 s
          arguments: {},
          isSuccess: true,
        ),
        AgentStepTelemetry(
          stepIndex: 4,
          toolName: 'step_huge_dur',
          toolCategory: 'MCP 扩展',
          durationMs: 3600000, // 3600.00 s
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

      expect(find.text('0 ms'), findsOneWidget);
      expect(find.text('999 ms'), findsOneWidget);
      expect(find.text('1.00 s'), findsOneWidget);
      expect(find.text('3600.00 s'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('Boundary: Unknown, empty, and all 4-dimensional category themes', (tester) async {
      final allCategories = [
        '基础实用', '基础计算', '时间工具', '生活服务', '知识检索', '搜索引擎', '网页内容',
        '沙箱与代码', '文件系统', '代码执行', '系统交互',
        '移动原生', '设备日历', '系统通知', '设备通讯录', '设备定位', '地理服务',
        '动态MCP', 'MCP 扩展', 'MCP 扩展工具',
        '', '自定义分类_A', 'AlienCategory',
      ];

      for (final cat in allCategories) {
        final themeLight = ToolCategoryTheme.fromCategory(cat, isDark: false);
        final themeDark = ToolCategoryTheme.fromCategory(cat, isDark: true);
        expect(themeLight.primaryColor, isNotNull);
        expect(themeLight.backgroundColor, isNotNull);
        expect(themeLight.icon, isNotNull);
        expect(themeDark.primaryColor, isNotNull);
        expect(themeDark.backgroundColor, isNotNull);
        if (cat.isEmpty) {
          expect(themeLight.category, '未分类');
        } else {
          expect(themeLight.category, cat);
        }
      }
    });

    testWidgets('Stress: Rapid toggling of header expand/collapse 10 times consecutively', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'toggle_tool',
          toolCategory: '基础实用',
          durationMs: 100,
          arguments: {'k': 'v'},
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

      for (int i = 0; i < 10; i++) {
        await tester.tap(find.text('Agent 执行时间线 (1 步)'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // State is stable
      expect(find.byType(AgentExecutionTimelineWidget), findsOneWidget);
    });

    testWidgets('Interaction: Empty or whitespace-only intent does not render intent container', (tester) async {
      final steps = [
        AgentStepTelemetry(
          stepIndex: 1,
          toolName: 'empty_intent_tool',
          toolCategory: '基础实用',
          durationMs: 100,
          intent: '   \n \t  ',
          arguments: {},
          isSuccess: true,
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

      expect(find.textContaining('意图:'), findsNothing);

      await tester.tap(find.text('empty_intent_tool'));
      await tester.pumpAndSettle();

      expect(find.text('推理意图:'), findsNothing);
    });
  });

  group('TokenBudgetBadge Adversarial & Stress Tests', () {
    testWidgets('Boundary: Zero tokens and zero usageRatio', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 0,
        budgetCap: 32000,
        usageRatio: 0.0,
        isWarning: false,
        isCircuitBreakerTriggered: false,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: budget,
            ),
          ),
        ),
      );

      expect(find.text('0 / 32,000 Tokens'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
      expect(TokenBudgetBadge.getStatusColor(0.0), const Color(0xFF388E3C));
      expect(TokenBudgetBadge.getStatusLabel(0.0, false), '预算充裕');
    });

    testWidgets('Boundary: Critical threshold boundary transitions (69.9%, 70.0%, 89.9%, 90.0%, 100.0%)', (tester) async {
      // 69.9% -> Green
      expect(TokenBudgetBadge.getStatusColor(0.699), const Color(0xFF388E3C));
      expect(TokenBudgetBadge.getStatusLabel(0.699, false), '预算充裕');

      // 70.0% -> Amber
      expect(TokenBudgetBadge.getStatusColor(0.70), const Color(0xFFF57C00));
      expect(TokenBudgetBadge.getStatusLabel(0.70, false), '较高消耗');

      // 89.9% -> Amber
      expect(TokenBudgetBadge.getStatusColor(0.899), const Color(0xFFF57C00));
      expect(TokenBudgetBadge.getStatusLabel(0.899, false), '较高消耗');

      // 90.0% -> Red
      expect(TokenBudgetBadge.getStatusColor(0.90), const Color(0xFFD32F2F));
      expect(TokenBudgetBadge.getStatusLabel(0.90, false), '高消耗/熔断保护');

      // 100.0% -> Red
      expect(TokenBudgetBadge.getStatusColor(1.00), const Color(0xFFD32F2F));
      expect(TokenBudgetBadge.getStatusLabel(1.00, false), '高消耗/熔断保护');
    });

    testWidgets('Boundary: Over 100% tokens (e.g. 250% overflow) clamps progress without crashing', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 80000,
        budgetCap: 32000,
        usageRatio: 2.50,
        isWarning: true,
        isCircuitBreakerTriggered: true,
        tokensSaved: 15000,
        compressionCount: 5,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: budget,
            ),
          ),
        ),
      );

      expect(find.text('80,000 / 32,000 Tokens'), findsOneWidget);
      expect(find.text('250.0%'), findsOneWidget);
      expect(find.text('熔断中'), findsOneWidget);
      expect(find.text('滑动窗口已节省 15,000 Tokens (5次压缩)'), findsOneWidget);

      final progressFinder = find.byType(LinearProgressIndicator);
      expect(progressFinder, findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(progressFinder);
      expect(indicator.value, 1.0); // Clamped cleanly to 1.0
    });

    testWidgets('Boundary: Negative usage ratio clamps progress to 0.0 without crashing', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 0,
        budgetCap: 32000,
        usageRatio: -0.25,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: budget,
            ),
          ),
        ),
      );

      final progressFinder = find.byType(LinearProgressIndicator);
      expect(progressFinder, findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(progressFinder);
      expect(indicator.value, 0.0); // Clamped cleanly to 0.0
    });

    testWidgets('Stress: Extremely large numbers (billions) formatted with proper commas', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 1234567890,
        budgetCap: 9876543210,
        usageRatio: 0.125,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: budget,
            ),
          ),
        ),
      );

      expect(find.text('1,234,567,890 / 9,876,543,210 Tokens'), findsOneWidget);
      expect(find.text('12.5%'), findsOneWidget);
    });

    testWidgets('Matrix: Token saving and warning chips combination permutations', (tester) async {
      // 1. Saved > 0, warning = false, breaker = false
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: TokenBudgetTelemetry(
                currentEstimatedTokens: 10000,
                budgetCap: 32000,
                usageRatio: 0.3125,
                tokensSaved: 450,
                compressionCount: 2,
              ),
            ),
          ),
        ),
      );
      expect(find.text('滑动窗口已节省 450 Tokens (2次压缩)'), findsOneWidget);
      expect(find.text('接近上限'), findsNothing);
      expect(find.text('熔断中'), findsNothing);

      // 2. Saved == 0, warning = true, breaker = false
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: TokenBudgetTelemetry(
                currentEstimatedTokens: 25000,
                budgetCap: 32000,
                usageRatio: 0.78125,
                isWarning: true,
                isCircuitBreakerTriggered: false,
              ),
            ),
          ),
        ),
      );
      expect(find.text('接近上限'), findsOneWidget);
      expect(find.text('熔断中'), findsNothing);

      // 3. Saved == 0, warning = true, breaker = true
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: TokenBudgetTelemetry(
                currentEstimatedTokens: 31000,
                budgetCap: 32000,
                usageRatio: 0.96875,
                isWarning: true,
                isCircuitBreakerTriggered: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('熔断中'), findsOneWidget);
      expect(find.text('接近上限'), findsNothing); // Breaker takes precedence in status chip
    });
  });

  group('CircuitBreakerAlertWidget Adversarial & Stress Tests', () {
    testWidgets('Boundary: Null currentTokens and null budgetCap combinations fallback safely', (tester) async {
      // Case 1: Both null -> Sub-line is omitted
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertWidget(
              reason: '熔断测试 1',
            ),
          ),
        ),
      );
      expect(find.text('🚨 Token 预算熔断保护已触发 · 已生成总结收尾'), findsOneWidget);
      expect(find.textContaining('当前估算:'), findsNothing);

      // Case 2: currentTokens provided, budgetCap null
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertWidget(
              reason: '熔断测试 2',
              currentTokens: 29500,
            ),
          ),
        ),
      );
      expect(find.text('当前估算: 29,500 / 32,000 Tokens'), findsOneWidget);

      // Case 3: currentTokens null, budgetCap provided
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertWidget(
              reason: '熔断测试 3',
              budgetCap: 64000,
            ),
          ),
        ),
      );
      expect(find.text('当前估算: 上限 / 64,000 Tokens'), findsOneWidget);

      // Case 4: Both provided
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertWidget(
              reason: '熔断测试 4',
              currentTokens: 58000,
              budgetCap: 64000,
            ),
          ),
        ),
      );
      expect(find.text('当前估算: 58,000 / 64,000 Tokens'), findsOneWidget);
    });

    testWidgets('Boundary: Empty and whitespace-only reasons omit inner diagnostic box', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertWidget(
              reason: '   \n  \t  ',
            ),
          ),
        ),
      );

      expect(find.text('🚨 Token 预算熔断保护已触发 · 已生成总结收尾'), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('Stress: 10,000 character reason diagnostic text renders without overflow', (tester) async {
      final repeatReason = 'Token超限详述 ' * 1000;
      final hugeReason = '熔断原因: $repeatReason';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CircuitBreakerAlertWidget(
                reason: hugeReason,
                currentTokens: 35000,
                budgetCap: 32000,
              ),
            ),
          ),
        ),
      );

      expect(find.text('🚨 Token 预算熔断保护已触发 · 已生成总结收尾'), findsOneWidget);
      expect(find.text('当前估算: 35,000 / 32,000 Tokens'), findsOneWidget);
      expect(find.textContaining('熔断原因: Token超限详述'), findsOneWidget);
    });

    testWidgets('Dismissal: onDismiss null hides close button, non-null shows button and triggers callback', (tester) async {
      // 1. Null onDismiss
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertWidget(
              reason: '无关闭按钮',
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsNothing);

      // 2. Non-null onDismiss
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertWidget(
              reason: '有关闭按钮',
              onDismiss: () {
                dismissed = true;
              },
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });
  });
}
