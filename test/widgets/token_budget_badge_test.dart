import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/agent_step_telemetry.dart';
import 'package:chat/services/agent_service.dart';
import 'package:chat/widgets/token_budget_badge.dart';

void main() {
  group('TokenBudgetBadge Tests', () {
    testWidgets('Renders green badge when token usage is under 70%', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 6400,
        budgetCap: 32000,
        usageRatio: 0.20,
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

      expect(find.text('6,400 / 32,000 Tokens'), findsOneWidget);
      expect(find.text('20.0%'), findsOneWidget);
      expect(TokenBudgetBadge.getStatusColor(0.20), const Color(0xFF388E3C)); // Green
      expect(TokenBudgetBadge.getStatusLabel(0.20, false), '预算充裕');
    });

    testWidgets('Renders amber badge and warning chip when usage is between 70% and 89%', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 25600,
        budgetCap: 32000,
        usageRatio: 0.80,
        isWarning: true,
        isCircuitBreakerTriggered: false,
        tokensSaved: 1200,
        compressionCount: 1,
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

      expect(find.text('25,600 / 32,000 Tokens'), findsOneWidget);
      expect(find.text('80.0%'), findsOneWidget);
      expect(find.text('接近上限'), findsOneWidget);
      expect(find.text('滑动窗口已节省 1,200 Tokens (1次压缩)'), findsOneWidget);
      expect(TokenBudgetBadge.getStatusColor(0.80), const Color(0xFFF57C00)); // Orange/Amber
      expect(TokenBudgetBadge.getStatusLabel(0.80, false), '较高消耗');
    });

    testWidgets('Renders red badge and tripped chip when usage is >= 90%', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 30000,
        budgetCap: 32000,
        usageRatio: 0.9375,
        isWarning: true,
        isCircuitBreakerTriggered: true,
        tokensSaved: 4800,
        compressionCount: 3,
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

      expect(find.text('30,000 / 32,000 Tokens'), findsOneWidget);
      expect(find.text('93.8%'), findsOneWidget);
      expect(find.text('熔断中'), findsOneWidget);
      expect(find.text('滑动窗口已节省 4,800 Tokens (3次压缩)'), findsOneWidget);
      expect(TokenBudgetBadge.getStatusColor(0.9375), const Color(0xFFD32F2F)); // Red
      expect(TokenBudgetBadge.getStatusLabel(0.9375, true), '高消耗/熔断保护');
    });

    testWidgets('Hides detail row when showDetails is false', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 10000,
        budgetCap: 32000,
        usageRatio: 0.3125,
        tokensSaved: 2000,
        compressionCount: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: budget,
              showDetails: false,
            ),
          ),
        ),
      );

      expect(find.text('10,000 / 32,000 Tokens'), findsOneWidget);
      expect(find.textContaining('滑动窗口已节省'), findsNothing);
    });

    testWidgets('Renders compact pill badge with prompt and completion tokens', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge.compact(
              promptTokens: 850,
              completionTokens: 400,
            ),
          ),
        ),
      );

      expect(find.text('🪙 1,250 Tokens (↑850 / ↓400)'), findsOneWidget);
    });

    testWidgets('Renders compact pill badge with warning ratio chip', (tester) async {
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 25000,
        budgetCap: 32000,
        usageRatio: 0.78125,
        isWarning: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: budget,
              isCompact: true,
            ),
          ),
        ),
      );

      expect(find.text('🪙 25,000 / 32,000 Tokens'), findsOneWidget);
      expect(find.text('⚠️ 78%'), findsOneWidget);
    });

    testWidgets('TokenBudgetBadge.fromEvent factory instantiates correctly', (tester) async {
      const telemetry = TokenBudgetTelemetry(
        currentEstimatedTokens: 16000,
        budgetCap: 32000,
        usageRatio: 0.50,
      );
      const event = TokenBudgetTelemetryEvent(telemetry);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge.fromEvent(event),
          ),
        ),
      );

      expect(find.text('16,000 / 32,000 Tokens'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
    });

    testWidgets('Triggers onTap callback when clicked', (tester) async {
      bool tapped = false;
      const budget = TokenBudgetTelemetry(
        currentEstimatedTokens: 5000,
        budgetCap: 32000,
        usageRatio: 0.156,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TokenBudgetBadge(
              budget: budget,
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TokenBudgetBadge));
      expect(tapped, isTrue);
    });
  });

  group('CircuitBreakerAlertCard Tests', () {
    testWidgets('Renders circuit breaker warning banner, explanation and token counts', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertCard(
              reason: '上下文 Token 数量达到 30,500，触发 90% 硬上限熔断',
              currentTokens: 30500,
              budgetCap: 32000,
            ),
          ),
        ),
      );

      expect(find.text('🚨 Token 预算熔断保护已触发 · 已生成总结收尾'), findsOneWidget);
      expect(find.text('当前估算: 30,500 / 32,000 Tokens'), findsOneWidget);
      expect(
        find.text('已达到上下文安全上限，系统已自动剥离后续工具调用，大模型将生成最终总结文本以确保对话安全与稳定性。'),
        findsOneWidget,
      );
      expect(find.text('上下文 Token 数量达到 30,500，触发 90% 硬上限熔断'), findsOneWidget);
    });

    testWidgets('Triggers onDismiss callback when close icon is pressed', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CircuitBreakerAlertCard(
              reason: '熔断提示',
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

    testWidgets('Adapts gracefully to Dark theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const Scaffold(
            body: CircuitBreakerAlertCard(
              reason: '暗黑主题熔断测试',
              currentTokens: 31000,
              budgetCap: 32000,
            ),
          ),
        ),
      );

      expect(find.text('🚨 Token 预算熔断保护已触发 · 已生成总结收尾'), findsOneWidget);
      expect(find.text('暗黑主题熔断测试'), findsOneWidget);
    });
  });
}
