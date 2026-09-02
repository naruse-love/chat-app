import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool_call.dart';
import 'package:chat/models/agent_step_telemetry.dart';
import 'package:chat/services/token_budget_manager.dart';

void main() {
  group('TokenBudgetTelemetry & AgentStepTelemetry Model Tests', () {
    test('AgentStepTelemetry serialization and deserialization', () {
      final now = DateTime.now();
      final telemetry = AgentStepTelemetry(
        stepIndex: 1,
        toolName: 'math_eval',
        toolCategory: '基础实用',
        durationMs: 120,
        intent: '计算复杂数学公式',
        arguments: {'expression': '1024 * 768 / 1000'},
        outputPreview: '786.432',
        fullOutput: '786.432',
        isSuccess: true,
        isCompressed: false,
        isCircuitBreakerTriggered: false,
        promptTokens: 450,
        completionTokens: 28,
        timestamp: now,
      );

      expect(telemetry.duration, const Duration(milliseconds: 120));
      final jsonMap = telemetry.toJson();
      expect(jsonMap['toolName'], 'math_eval');
      expect(jsonMap['durationMs'], 120);
      expect(jsonMap['intent'], '计算复杂数学公式');

      final restored = AgentStepTelemetry.fromJson(jsonMap);
      expect(restored.stepIndex, 1);
      expect(restored.toolName, 'math_eval');
      expect(restored.arguments['expression'], '1024 * 768 / 1000');
      expect(restored.promptTokens, 450);
      expect(restored.completionTokens, 28);
      expect(restored.isSuccess, isTrue);

      final copied = restored.copyWith(durationMs: 250, isCompressed: true);
      expect(copied.durationMs, 250);
      expect(copied.isCompressed, isTrue);
      expect(copied.stepIndex, 1);
    });

    test('TokenBudgetTelemetry calculate and serialization', () {
      final telemetry = TokenBudgetTelemetry.calculate(
        currentEstimatedTokens: 25000,
        budgetCap: 32000,
        warningThreshold: 0.75,
        circuitBreakerThreshold: 0.90,
        compressionCount: 2,
        tokensSaved: 4800,
      );

      expect(telemetry.currentEstimatedTokens, 25000);
      expect(telemetry.budgetCap, 32000);
      expect(telemetry.usageRatio, closeTo(25000 / 32000, 0.001));
      expect(telemetry.isWarning, isTrue);
      expect(telemetry.isCircuitBreakerTriggered, isFalse);
      expect(telemetry.compressionCount, 2);
      expect(telemetry.tokensSaved, 4800);

      final jsonMap = telemetry.toJson();
      final restored = TokenBudgetTelemetry.fromJson(jsonMap);
      expect(restored.currentEstimatedTokens, 25000);
      expect(restored.isWarning, isTrue);
      expect(restored.tokensSaved, 4800);
    });
  });

  group('TokenBudgetManager — Token Estimation Tests', () {
    late TokenBudgetManager manager;

    setUp(() {
      manager = TokenBudgetManager();
    });

    test('CJK character detection works for Chinese, Japanese, Korean, and fullwidth forms', () {
      expect(TokenBudgetManager.isCjk('中'.runes.first), isTrue);
      expect(TokenBudgetManager.isCjk('文'.runes.first), isTrue);
      expect(TokenBudgetManager.isCjk('あ'.runes.first), isTrue); // Hiragana
      expect(TokenBudgetManager.isCjk('ア'.runes.first), isTrue); // Katakana
      expect(TokenBudgetManager.isCjk('한'.runes.first), isTrue); // Hangul
      expect(TokenBudgetManager.isCjk('，'.runes.first), isTrue); // Fullwidth comma
      expect(TokenBudgetManager.isCjk('A'.runes.first), isFalse);
      expect(TokenBudgetManager.isCjk('1'.runes.first), isFalse);
      expect(TokenBudgetManager.isCjk(' '.runes.first), isFalse);
    });

    test('estimateTokens handles empty and trivial strings', () {
      expect(manager.estimateTokens(''), equals(0));
      expect(manager.estimateTokens('A'), equals(1));
      expect(manager.estimateTokens('中'), equals(1));
    });

    test('estimateTokens calculates CJK text (~0.85 tok/char)', () {
      final chinese100Chars = '这是一段用于测试中文Token估算精确度的文本。' * 5; // 120 chars
      final tokens = manager.estimateTokens(chinese100Chars);
      expect(tokens, greaterThan(80));
      expect(tokens, lessThan(130));
    });

    test('estimateTokens calculates English / ASCII words (~3.8 char/tok)', () {
      const englishText = 'The quick brown fox jumps over the lazy dog and runs across the open green field.';
      final tokens = manager.estimateTokens(englishText);
      expect(tokens, greaterThan(15));
      expect(tokens, lessThan(30));
    });

    test('estimateTokens handles Emojis and mixed Unicode', () {
      const mixedText = '🚀 Flutter AI Agent 移动端助手 🤖 正在执行多步推理！';
      final tokens = manager.estimateTokens(mixedText);
      expect(tokens, greaterThan(15));
    });

    test('estimateMessageTokens calculates ChatML, reasoning, toolCalls, and vision', () {
      final textMsg = ChatMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        role: 'user',
        content: '你好，请帮我查询天气',
        timestamp: DateTime.now(),
      );
      final textTokens = manager.estimateMessageTokens(textMsg);
      expect(textTokens, greaterThan(10));

      final reasoningMsg = textMsg.copyWith(
        reasoningContent: '用户想要查询今天的天气预报，我需要调用 weather_query 工具。',
      );
      expect(manager.estimateMessageTokens(reasoningMsg), greaterThan(textTokens));

      final toolCallMsg = textMsg.copyWith(
        toolCalls: [
          ToolCall(
            id: 'call_1',
            type: 'function',
            functionName: 'weather_query',
            arguments: '{"city": "上海"}',
          ),
        ],
      );
      expect(manager.estimateMessageTokens(toolCallMsg), greaterThan(textTokens + 10));

      final visionMsg = textMsg.copyWith(imagePath: '/data/images/photo.jpg');
      expect(manager.estimateMessageTokens(visionMsg), equals(textTokens + 85));
    });

    test('estimateConversationTokens calculates system prompt, messages, and tools schema', () {
      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c',
          role: 'user',
          content: '请写一个排序算法',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          conversationId: 'c',
          role: 'assistant',
          content: '这里是快速排序的 Dart 实现代码：\n```dart\nvoid quickSort() {}\n```',
          timestamp: DateTime.now(),
        ),
      ];

      const systemPrompt = '你是一个高水平的 Flutter 架构专家。';
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'code_eval',
            'description': '执行 Dart 代码',
            'parameters': {
              'type': 'object',
              'properties': {
                'code': {'type': 'string'},
              },
            },
          },
        }
      ];

      final totalTokens = manager.estimateConversationTokens(
        messages,
        systemPrompt: systemPrompt,
        tools: tools,
      );

      expect(totalTokens, greaterThan(50));
    });
  });

  group('TokenBudgetManager — Sliding Window History Compaction Tests', () {
    late TokenBudgetManager manager;

    setUp(() {
      manager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 32000,
          preserveRecentRounds: 2,
          compressedHeadRunes: 50,
          compressedTailRunes: 30,
        ),
      );
    });

    test('Short message list (< 3 messages) is untouched', () {
      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c',
          role: 'user',
          content: '你好',
          timestamp: DateTime.now(),
        ),
      ];

      final result = manager.compactIntermediateToolHistory(messages);
      expect(result.messages.length, 1);
      expect(result.tokensSaved, 0);
      expect(result.compressionCount, 0);
    });

    test('Multi-round conversation protects first user message and last N rounds while compacting old tool outputs', () {
      final firstUserMsg = ChatMessage(
        id: 'u1',
        conversationId: 'c',
        role: 'user',
        content: '请深度调研 Flutter WebAssembly 并总结核心优缺点',
        timestamp: DateTime.now(),
      );

      // Old Round 0: wiki_lookup output with 2000 chars
      final oldAssistantMsg0 = ChatMessage(
        id: 'a0',
        conversationId: 'c',
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(id: 'call_0', type: 'function', functionName: 'wiki_lookup', arguments: '{"query": "WebAssembly"}'),
        ],
        timestamp: DateTime.now(),
      );
      final oldToolMsg0 = ChatMessage(
        id: 't0',
        conversationId: 'c',
        role: 'tool',
        toolCallId: 'call_0',
        content: '【维基百科条目】${'WebAssembly 是一种在现代 Web 浏览器中运行的低级字节码格式...' * 50}',
        timestamp: DateTime.now(),
      );

      // Old Round 1: url_fetch output with 2000 chars
      final oldAssistantMsg1 = ChatMessage(
        id: 'a1',
        conversationId: 'c',
        role: 'assistant',
        content: '',
        reasoningContent: '需要先抓取官方文档' * 20, // > 100 chars
        toolCalls: [
          ToolCall(id: 'call_1', type: 'function', functionName: 'url_fetch', arguments: '{"url": "https://flutter.dev/wasm"}'),
        ],
        timestamp: DateTime.now(),
      );
      final oldToolMsg1 = ChatMessage(
        id: 't1',
        conversationId: 'c',
        role: 'tool',
        toolCallId: 'call_1',
        content: '【Flutter WebAssembly 官方技术规范】${'详细文档段落内容包含GC与SIMD支持分析及性能基准...' * 50}',
        timestamp: DateTime.now(),
      );

      // Old Round 2: search output with 1500 chars
      final oldAssistantMsg2 = ChatMessage(
        id: 'a2',
        conversationId: 'c',
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(id: 'call_2', type: 'function', functionName: 'web_search', arguments: '{"query": "Wasm benchmark"}'),
        ],
        timestamp: DateTime.now(),
      );
      final oldToolMsg2 = ChatMessage(
        id: 't2',
        conversationId: 'c',
        role: 'tool',
        toolCallId: 'call_2',
        content: '【搜索结果】${'1. Wasm 性能评测结果对比 JS 运行提速 2.5 倍...' * 40}',
        timestamp: DateTime.now(),
      );

      // Recent Protected Round 3
      final recentAssistantMsg = ChatMessage(
        id: 'a3',
        conversationId: 'c',
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(id: 'call_3', type: 'function', functionName: 'math_eval', arguments: '{"expression": "2.5 * 100"}'),
        ],
        timestamp: DateTime.now(),
      );
      final recentToolMsg = ChatMessage(
        id: 't3',
        conversationId: 'c',
        role: 'tool',
        toolCallId: 'call_3',
        content: '250',
        timestamp: DateTime.now(),
      );

      // Recent Protected Final Assistant
      final activeAssistant = ChatMessage(
        id: 'a4',
        conversationId: 'c',
        role: 'assistant',
        content: '正在生成最终技术总结...',
        timestamp: DateTime.now(),
      );

      final fullConversation = [
        firstUserMsg,
        oldAssistantMsg0,
        oldToolMsg0,
        oldAssistantMsg1,
        oldToolMsg1,
        oldAssistantMsg2,
        oldToolMsg2,
        recentAssistantMsg,
        recentToolMsg,
        activeAssistant,
      ];

      final result = manager.compactIntermediateToolHistory(fullConversation);

      // 1. First user message must be intact
      expect(result.messages.first.content, equals(firstUserMsg.content));

      // 2. Old tool outputs must be compressed
      final compactedTool1 = result.messages.firstWhere((m) => m.id == 't1');
      expect(compactedTool1.content, contains('[中间执行结果已压缩'));
      expect(compactedTool1.content, contains('已智能省略'));

      // 3. Old reasoning must be folded
      final compactedAssistant1 = result.messages.firstWhere((m) => m.id == 'a1');
      expect(compactedAssistant1.reasoningContent, equals('[中间思考过程已压缩折叠]'));

      // 4. Recent tool message must remain intact
      final protectedRecentTool = result.messages.firstWhere((m) => m.id == 't3');
      expect(protectedRecentTool.content, equals('250'));

      // 5. Compression count & tokens saved
      expect(result.compressionCount, greaterThanOrEqualTo(2));
      expect(result.tokensSaved, greaterThan(200));
    });
  });

  group('TokenBudgetManager — Global Circuit Breaker Tests', () {
    test('evaluateCircuitBreaker returns normal when budget is well within bounds', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(maxContextTokens: 32000),
      );

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c',
          role: 'user',
          content: '简短问题',
          timestamp: DateTime.now(),
        ),
      ];

      final eval = manager.evaluateCircuitBreaker(messages);
      expect(eval.state, equals(CircuitBreakerState.normal));
      expect(eval.shouldStripTools, isFalse);
      expect(eval.forcedConclusionPrompt, isNull);
    });

    test('evaluateCircuitBreaker triggers warning when usage is >= 75%', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 1000,
          compressionThresholdRatio: 0.70,
          circuitBreakerThresholdRatio: 0.90,
        ),
      );

      final largeContent = '这' * 900; // ~765 tokens -> ~76% of 1000
      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c',
          role: 'user',
          content: largeContent,
          timestamp: DateTime.now(),
        ),
      ];

      final eval = manager.evaluateCircuitBreaker(messages);
      expect(eval.state, equals(CircuitBreakerState.warning));
      expect(eval.shouldStripTools, isFalse);
    });

    test('evaluateCircuitBreaker trips when usage is >= 90% and provides Chinese conclusion prompt', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 1000,
          circuitBreakerThresholdRatio: 0.90,
        ),
      );

      final massiveContent = '中' * 1200; // ~1020 tokens -> >100% of 1000
      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c',
          role: 'user',
          content: massiveContent,
          timestamp: DateTime.now(),
        ),
      ];

      final eval = manager.evaluateCircuitBreaker(messages);
      expect(eval.state, equals(CircuitBreakerState.tripped));
      expect(eval.shouldStripTools, isTrue);
      expect(eval.forcedConclusionPrompt, contains('【系统安全熔断】'));
      expect(eval.forcedConclusionPrompt, contains('禁止再次调用任何工具'));
    });
  });

  group('TokenBudgetManager — evaluateAndCompact Pipeline Tests', () {
    test('evaluateAndCompact passes normally for low token usage', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(maxContextTokens: 32000, maxOutputTokens: 4000),
      );

      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c',
          role: 'user',
          content: '你好',
          timestamp: DateTime.now(),
        ),
      ];

      final result = manager.evaluateAndCompact(messages: messages);
      expect(result.status, equals(BudgetActionStatus.normal));
      expect(result.shouldStripTools, isFalse);
      expect(result.tokensSavedByCompression, equals(0));

      final telemetry = result.toTelemetry();
      expect(telemetry.isWarning, isFalse);
      expect(telemetry.isCircuitBreakerTriggered, isFalse);
    });

    test('evaluateAndCompact applies compaction and trips circuit breaker when necessary', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 500,
          maxOutputTokens: 100,
          compressionThresholdRatio: 0.50,
          circuitBreakerThresholdRatio: 0.80,
          compressedHeadRunes: 20,
          compressedTailRunes: 20,
        ),
      );

      final longToolOutput = '长' * 1000;
      final messages = [
        ChatMessage(
          id: '1',
          conversationId: 'c',
          role: 'user',
          content: '开始',
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '2',
          conversationId: 'c',
          role: 'tool',
          toolCallId: 'c1',
          content: longToolOutput,
          timestamp: DateTime.now(),
        ),
        ChatMessage(
          id: '3',
          conversationId: 'c',
          role: 'assistant',
          content: '下步',
          timestamp: DateTime.now(),
        ),
      ];

      final result = manager.evaluateAndCompact(messages: messages);
      expect(result.tokensSavedByCompression, greaterThan(0));
      expect(result.effectiveMessages[1].content, contains('[中间执行结果已压缩'));
    });
  });
}
