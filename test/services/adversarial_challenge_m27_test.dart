import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/services/token_budget_manager.dart';
import 'package:chat/services/agent_fault_tolerance.dart';

void main() {
  group('Adversarial Challenge 1: TokenBudgetManager Edge Cases & Stress', () {
    late TokenBudgetManager defaultManager;

    setUp(() {
      defaultManager = TokenBudgetManager();
    });

    test('1.1 Extreme text mixtures & Unicode boundary stress', () {
      expect(defaultManager.estimateTokens(''), equals(0));
      expect(defaultManager.estimateTokens('     '), equals(2));
      expect(defaultManager.estimateTokens('\n\n\t\r\n'), equals(2));

      const complexMix = '👩‍💻 Flutter 架构师 ⚡ 在 2026 年处理 1,000,000 tokens！🇨🇳 🚀';
      final tokens = defaultManager.estimateTokens(complexMix);
      expect(tokens, greaterThan(15));
      expect(tokens, lessThan(80));

      final stopwatch = Stopwatch()..start();
      final massiveCjk = '测' * 100000;
      final massiveTokens = defaultManager.estimateTokens(massiveCjk);
      stopwatch.stop();

      expect(massiveTokens, equals(85000));
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('1.2 CJK Rune coverage across Extension blocks and punctuation', () {
      expect(TokenBudgetManager.isCjk(0x3400), isTrue);
      expect(TokenBudgetManager.isCjk(0x4DBF), isTrue);
      expect(TokenBudgetManager.isCjk(0x20000), isTrue);
      expect(TokenBudgetManager.isCjk(0x2A6DF), isTrue);
      expect(TokenBudgetManager.isCjk(0x3001), isTrue);
      expect(TokenBudgetManager.isCjk(0x3002), isTrue);
      expect(TokenBudgetManager.isCjk(0xFF01), isTrue);
      expect(TokenBudgetManager.isCjk(0xFF0C), isTrue);
      expect(TokenBudgetManager.isCjk(0x0041), isFalse);
      expect(TokenBudgetManager.isCjk(0x00E9), isFalse);
    });

    test('1.3 Inverted / Degenerate TokenBudgetConfig parameters', () {
      final degenerateManager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 1000,
          maxOutputTokens: 2000,
          compressionThresholdRatio: 0.5,
          circuitBreakerThresholdRatio: 0.8,
        ),
      );

      final messages = [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: 'user',
          content: '中' * 800,
          timestamp: DateTime.now(),
        ),
      ];

      final result = degenerateManager.evaluateAndCompact(messages: messages);
      expect(result.estimatedPromptTokens, greaterThan(600));
    });

    test('1.4 Sliding window compaction with Multibyte Unicode boundary slicing', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 10000,
          preserveRecentRounds: 1,
          compressedHeadRunes: 5,
          compressedTailRunes: 5,
        ),
      );

      final cjkPart = '中' * 100;
      final emojiToolMessage = '🌟🎉🚀🔥💡$cjkPart🍎🍊🍋🍇🍉';
      final messages = [
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Objective', timestamp: DateTime.now()),
        ChatMessage(id: 'a1', conversationId: 'c1', role: 'assistant', content: 'Calling tool', timestamp: DateTime.now()),
        ChatMessage(id: 't1', conversationId: 'c1', role: 'tool', toolCallId: 'c1', content: emojiToolMessage, timestamp: DateTime.now()),
        ChatMessage(id: 'a2', conversationId: 'c1', role: 'assistant', content: 'Second call', timestamp: DateTime.now()),
        ChatMessage(id: 't2', conversationId: 'c1', role: 'tool', toolCallId: 'c2', content: 'Protected recent tool', timestamp: DateTime.now()),
      ];

      final compacted = manager.compactIntermediateToolHistory(messages);

      expect(compacted.compressionCount, 1);
      final compactedTool = compacted.messages.firstWhere((m) => m.id == 't1');
      expect(compactedTool.content, contains('🌟🎉🚀🔥💡'));
      expect(compactedTool.content, contains('🍎🍊🍋🍇🍉'));
      expect(compactedTool.content, contains('[中间执行结果已压缩'));

      final protectedTool = compacted.messages.firstWhere((m) => m.id == 't2');
      expect(protectedTool.content, equals('Protected recent tool'));
    });

    test('1.5 Sliding window with keepLastNRounds = 0 and huge list', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 50000,
          preserveRecentRounds: 0,
          compressedHeadRunes: 10,
          compressedTailRunes: 10,
        ),
      );

      final messages = <ChatMessage>[
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Goal', timestamp: DateTime.now()),
      ];

      for (int i = 0; i < 20; i++) {
        final dataRepeat = 'Data ' * 100;
        messages.add(ChatMessage(
          id: 't_$i',
          conversationId: 'c1',
          role: 'tool',
          toolCallId: 'call_$i',
          content: 'Output of step $i: $dataRepeat',
          timestamp: DateTime.now(),
        ));
      }

      final result = manager.compactIntermediateToolHistory(messages);
      expect(result.compressionCount, 20);
      expect(result.tokensSaved, greaterThan(1000));
      expect(result.messages.first.content, 'Goal');
    });

    test('1.6 Circuit breaker boundary conditions (Warning vs Tripped)', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 1000,
          compressionThresholdRatio: 0.70,
          circuitBreakerThresholdRatio: 0.90,
        ),
      );

      final cjk823 = '字' * 823;
      final msgWarning = [
        ChatMessage(id: '1', conversationId: 'c', role: 'user', content: cjk823, timestamp: DateTime.now()),
      ];
      final evalWarning = manager.evaluateCircuitBreaker(msgWarning);
      expect(evalWarning.state, CircuitBreakerState.warning);
      expect(evalWarning.shouldStripTools, isFalse);

      final cjk1100 = '字' * 1100;
      final msgTripped = [
        ChatMessage(id: '1', conversationId: 'c', role: 'user', content: cjk1100, timestamp: DateTime.now()),
      ];
      final evalTripped = manager.evaluateCircuitBreaker(msgTripped);
      expect(evalTripped.state, CircuitBreakerState.tripped);
      expect(evalTripped.shouldStripTools, isTrue);
      expect(evalTripped.forcedConclusionPrompt, contains('【系统安全熔断】'));
    });

    test('1.7 Exact rune-level truncation border verification (maxAllowed + 30 vs maxAllowed + 31)', () {
      // 1. Default config: head = 200, tail = 100, maxAllowed = 300
      final defaultManager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 10000,
          preserveRecentRounds: 1,
          compressedHeadRunes: 200,
          compressedTailRunes: 100,
        ),
      );

      // Border A: exactly 330 runes (maxAllowed + 30) -> Should NOT compress
      final content330 = 'A' * 330;
      final msgs330 = [
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Objective', timestamp: DateTime.now()),
        ChatMessage(id: 'a1', conversationId: 'c1', role: 'assistant', content: 'Running tool 1', timestamp: DateTime.now()),
        ChatMessage(id: 't1', conversationId: 'c1', role: 'tool', toolCallId: 'c1', content: content330, timestamp: DateTime.now()),
        ChatMessage(id: 'a2', conversationId: 'c1', role: 'assistant', content: 'Running tool 2', timestamp: DateTime.now()),
        ChatMessage(id: 't2', conversationId: 'c1', role: 'tool', toolCallId: 'c2', content: 'Protected tail', timestamp: DateTime.now()),
      ];
      final res330 = defaultManager.compactIntermediateToolHistory(msgs330);
      expect(res330.compressionCount, equals(0));
      expect(res330.messages[2].content, equals(content330));

      // Border B: exactly 331 runes (maxAllowed + 31) -> MUST compress
      final content331 = 'A' * 331;
      final msgs331 = [
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Objective', timestamp: DateTime.now()),
        ChatMessage(id: 'a1', conversationId: 'c1', role: 'assistant', content: 'Running tool 1', timestamp: DateTime.now()),
        ChatMessage(id: 't1', conversationId: 'c1', role: 'tool', toolCallId: 'c1', content: content331, timestamp: DateTime.now()),
        ChatMessage(id: 'a2', conversationId: 'c1', role: 'assistant', content: 'Running tool 2', timestamp: DateTime.now()),
        ChatMessage(id: 't2', conversationId: 'c1', role: 'tool', toolCallId: 'c2', content: 'Protected tail', timestamp: DateTime.now()),
      ];
      final res331 = defaultManager.compactIntermediateToolHistory(msgs331);
      expect(res331.compressionCount, equals(1));
      expect(res331.messages[2].content, contains('[中间执行结果已压缩，关键输出摘要: '));
      expect(res331.messages[2].content, contains('...[已智能省略 31 字符]...'));
      final expectedHead = 'A' * 200;
      final expectedTail = 'A' * 100;
      expect(res331.messages[2].content, startsWith('[中间执行结果已压缩，关键输出摘要: $expectedHead'));
      expect(res331.messages[2].content, endsWith('$expectedTail]'));

      // 2. Custom config: head = 15, tail = 10, maxAllowed = 25 -> threshold = 55 vs 56
      final customManager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 10000,
          preserveRecentRounds: 1,
          compressedHeadRunes: 15,
          compressedTailRunes: 10,
        ),
      );

      final cjk55 = '字' * 55;
      final msgs55 = [
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Objective', timestamp: DateTime.now()),
        ChatMessage(id: 'a1', conversationId: 'c1', role: 'assistant', content: 'Call 1', timestamp: DateTime.now()),
        ChatMessage(id: 't1', conversationId: 'c1', role: 'tool', toolCallId: 'c1', content: cjk55, timestamp: DateTime.now()),
        ChatMessage(id: 'a2', conversationId: 'c1', role: 'assistant', content: 'Call 2', timestamp: DateTime.now()),
        ChatMessage(id: 't2', conversationId: 'c1', role: 'tool', toolCallId: 'c2', content: 'Protected', timestamp: DateTime.now()),
      ];
      final res55 = customManager.compactIntermediateToolHistory(msgs55);
      expect(res55.compressionCount, equals(0));
      expect(res55.messages[2].content, equals(cjk55));

      final cjk56 = '字' * 56;
      final msgs56 = [
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Objective', timestamp: DateTime.now()),
        ChatMessage(id: 'a1', conversationId: 'c1', role: 'assistant', content: 'Call 1', timestamp: DateTime.now()),
        ChatMessage(id: 't1', conversationId: 'c1', role: 'tool', toolCallId: 'c1', content: cjk56, timestamp: DateTime.now()),
        ChatMessage(id: 'a2', conversationId: 'c1', role: 'assistant', content: 'Call 2', timestamp: DateTime.now()),
        ChatMessage(id: 't2', conversationId: 'c1', role: 'tool', toolCallId: 'c2', content: 'Protected', timestamp: DateTime.now()),
      ];
      final res56 = customManager.compactIntermediateToolHistory(msgs56);
      expect(res56.compressionCount, equals(1));
      expect(res56.messages[2].content, contains('...[已智能省略 31 字符]...'));

      // 3. Multi-byte Emoji runes border: head = 4, tail = 4, maxAllowed = 8 -> threshold = 38 vs 39
      final emojiManager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 10000,
          preserveRecentRounds: 1,
          compressedHeadRunes: 4,
          compressedTailRunes: 4,
        ),
      );

      final emoji38 = '🚀' * 38;
      final msgsEmoji38 = [
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Objective', timestamp: DateTime.now()),
        ChatMessage(id: 'a1', conversationId: 'c1', role: 'assistant', content: 'Call 1', timestamp: DateTime.now()),
        ChatMessage(id: 't1', conversationId: 'c1', role: 'tool', toolCallId: 'c1', content: emoji38, timestamp: DateTime.now()),
        ChatMessage(id: 'a2', conversationId: 'c1', role: 'assistant', content: 'Call 2', timestamp: DateTime.now()),
        ChatMessage(id: 't2', conversationId: 'c1', role: 'tool', toolCallId: 'c2', content: 'Protected', timestamp: DateTime.now()),
      ];
      final resEmoji38 = emojiManager.compactIntermediateToolHistory(msgsEmoji38);
      expect(resEmoji38.compressionCount, equals(0));
      expect(resEmoji38.messages[2].content, equals(emoji38));

      final emoji39 = '🚀' * 39;
      final msgsEmoji39 = [
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: 'Objective', timestamp: DateTime.now()),
        ChatMessage(id: 'a1', conversationId: 'c1', role: 'assistant', content: 'Call 1', timestamp: DateTime.now()),
        ChatMessage(id: 't1', conversationId: 'c1', role: 'tool', toolCallId: 'c1', content: emoji39, timestamp: DateTime.now()),
        ChatMessage(id: 'a2', conversationId: 'c1', role: 'assistant', content: 'Call 2', timestamp: DateTime.now()),
        ChatMessage(id: 't2', conversationId: 'c1', role: 'tool', toolCallId: 'c2', content: 'Protected', timestamp: DateTime.now()),
      ];
      final resEmoji39 = emojiManager.compactIntermediateToolHistory(msgsEmoji39);
      expect(resEmoji39.compressionCount, equals(1));
      expect(resEmoji39.messages[2].content, contains('...[已智能省略 31 字符]...'));
    });

    test('1.8 Multi-tool calls in a single turn vs preserveRecentRounds sliding window compaction', () {
      final manager = TokenBudgetManager(
        config: const TokenBudgetConfig(
          maxContextTokens: 32000,
          preserveRecentRounds: 2,
          compressedHeadRunes: 200,
          compressedTailRunes: 100,
        ),
      );

      final chunkA = '数据块A ' * 100;
      final longOutput1 = '搜索结果：$chunkA';
      final chunkB = '内容块B ' * 200;
      final longOutput2 = '网页全文：$chunkB';
      final chunkC = '公式推导C ' * 80;
      final longOutput3 = '计算详情：$chunkC';
      final chunkD = '气象数据D ' * 90;
      final longOutput4 = '天气预报：$chunkD';
      final chunkE = '词条历史E ' * 110;
      final longOutput5 = '维基百科：$chunkE';
      const shortOutput6 = '文件写入成功，路径: /data/out.txt';

      final messages = <ChatMessage>[
        ChatMessage(id: 'u1', conversationId: 'c1', role: 'user', content: '综合研究金融与气候并保存', timestamp: DateTime.now()),
        ChatMessage(id: 'a1', conversationId: 'c1', role: 'assistant', content: '第一轮调用3个工具', reasoningContent: '首先需要检索网络、抓取页面并计算数据。' * 8, timestamp: DateTime.now()),
        ChatMessage(id: 't1', conversationId: 'c1', role: 'tool', toolCallId: 'call_search', content: longOutput1, timestamp: DateTime.now()),
        ChatMessage(id: 't2', conversationId: 'c1', role: 'tool', toolCallId: 'call_fetch', content: longOutput2, timestamp: DateTime.now()),
        ChatMessage(id: 't3', conversationId: 'c1', role: 'tool', toolCallId: 'call_math', content: longOutput3, timestamp: DateTime.now()),
        ChatMessage(id: 'a2', conversationId: 'c1', role: 'assistant', content: '第二轮调用2个工具', reasoningContent: '接下来查询实时天气并补充百科背景知识。' * 8, timestamp: DateTime.now()),
        ChatMessage(id: 't4', conversationId: 'c1', role: 'tool', toolCallId: 'call_weather', content: longOutput4, timestamp: DateTime.now()),
        ChatMessage(id: 't5', conversationId: 'c1', role: 'tool', toolCallId: 'call_wiki', content: longOutput5, timestamp: DateTime.now()),
        ChatMessage(id: 'a3', conversationId: 'c1', role: 'assistant', content: '第三轮保存结果', reasoningContent: '将整合后的结果持久化到文件。', timestamp: DateTime.now()),
        ChatMessage(id: 't6', conversationId: 'c1', role: 'tool', toolCallId: 'call_write', content: shortOutput6, timestamp: DateTime.now()),
      ];

      // 1. With preserveRecentRounds = 2:
      // Tool messages from tail: t6 (count 1), t5 (count 2).
      // Cutoff index is t5 (index 7).
      // Older tool messages t1, t2, t3, t4 are compressed!
      // t5 is protected in recent tail, t6 is protected in recent tail.
      final resultRounds2 = manager.compactIntermediateToolHistory(messages, keepLastNRounds: 2);
      expect(resultRounds2.compressionCount, equals(4));
      expect(resultRounds2.tokensSaved, greaterThan(500));

      final msgMap = {for (var m in resultRounds2.messages) m.id: m};
      expect(msgMap['u1']!.content, equals('综合研究金融与气候并保存'));
      expect(msgMap['a1']!.reasoningContent, equals('[中间思考过程已压缩折叠]'));
      expect(msgMap['a2']!.reasoningContent, equals('[中间思考过程已压缩折叠]'));
      expect(msgMap['a3']!.reasoningContent, equals('将整合后的结果持久化到文件。')); // Protected recent assistant

      expect(msgMap['t1']!.content, contains('[中间执行结果已压缩'));
      expect(msgMap['t2']!.content, contains('[中间执行结果已压缩'));
      expect(msgMap['t3']!.content, contains('[中间执行结果已压缩'));
      expect(msgMap['t4']!.content, contains('[中间执行结果已压缩'));

      expect(msgMap['t5']!.content, equals(longOutput5)); // Protected recent tool
      expect(msgMap['t6']!.content, equals(shortOutput6)); // Protected recent tool

      // 2. With preserveRecentRounds = 4:
      // Tool messages from tail: t6 (1), t5 (2), t4 (3), t3 (4).
      // Cutoff index is t3 (index 4).
      // Only t1 and t2 are compressed!
      final resultRounds4 = manager.compactIntermediateToolHistory(messages, keepLastNRounds: 4);
      expect(resultRounds4.compressionCount, equals(2));
      final msgMap4 = {for (var m in resultRounds4.messages) m.id: m};
      expect(msgMap4['t1']!.content, contains('[中间执行结果已压缩'));
      expect(msgMap4['t2']!.content, contains('[中间执行结果已压缩'));
      expect(msgMap4['t3']!.content, equals(longOutput3));
      expect(msgMap4['t4']!.content, equals(longOutput4));
      expect(msgMap4['t5']!.content, equals(longOutput5));
      expect(msgMap4['t6']!.content, equals(shortOutput6));
    });
  });

  group('Adversarial Challenge 2: AgentFaultTolerance Malformed JSON & Invocations', () {
    late AgentFaultTolerance faultTolerance;

    setUp(() {
      faultTolerance = AgentFaultTolerance();
    });

    test('2.1 Deeply nested unclosed JSON structures', () {
      const deeplyNested = '{"level1": {"level2": {"level3": {"items": [1, 2, 3';
      final map = faultTolerance.repairAndParseArguments(deeplyNested);
      expect(map['level1']['level2']['level3']['items'], equals([1, 2, 3]));
    });

    test('2.2 Single quotes and unquoted keys parsing', () {
      const singleQuotes = "{'path': 'data/user.json', 'count': 42}";
      final map = faultTolerance.repairAndParseArguments(singleQuotes);
      expect(map['path'], equals('data/user.json'));
      expect(map['count'], equals(42));
    });

    test('2.3 Unquoted keys with alphanumeric and underscores', () {
      const raw = '{user_id: 1001, auth_token_str: "abc-123", is_admin: true, retry_count: 3}';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['user_id'], equals(1001));
      expect(map['auth_token_str'], equals('abc-123'));
      expect(map['is_admin'], equals(true));
      expect(map['retry_count'], equals(3));
    });

    test('2.4 Trailing commas in nested objects and arrays', () {
      const raw = '{"query": "search term", "limit": 10, "nested": {"tag": "ai", }, "items": [1, 2, ], }';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['query'], equals('search term'));
      expect(map['limit'], equals(10));
      expect(map['nested']['tag'], equals('ai'));
      expect(map['items'], equals([1, 2]));
    });

    test('2.5 Multiple tool calls in a single DSML v2 block', () {
      const multipleDsml = '''
<｜tool calls begin｜>
<｜tool call begin｜>function<｜tool sep｜>math_eval
```json
{"expression": "1 + 1"}
```
<｜tool call end｜>
<｜tool call begin｜>function<｜tool sep｜>weather_query
```json
{"city": "Beijing"}
```
<｜tool call end｜>
<｜tool calls end｜>
''';

      final calls = faultTolerance.parseToolCalls(multipleDsml);
      expect(calls.length, equals(2));
      expect(calls[0].toolName, equals('math_eval'));
      expect(calls[0].arguments['expression'], equals('1 + 1'));
      expect(calls[1].toolName, equals('weather_query'));
      expect(calls[1].arguments['city'], equals('Beijing'));

      final stripped = faultTolerance.stripToolCallBlocks(multipleDsml);
      expect(stripped, isEmpty);
    });

    test('2.6 Multiple tool calls in Llama 3 array', () {
      const llamaMultiple = '''
[TOOL_CALLS] [
  {"name": "file_read", "arguments": {"path": "a.txt"}},
  {"name": "file_write", "arguments": {"path": "b.txt", "content": "hello"}}
]
''';

      final calls = faultTolerance.parseToolCalls(llamaMultiple);
      expect(calls.length, equals(2));
      expect(calls[0].toolName, equals('file_read'));
      expect(calls[0].arguments['path'], equals('a.txt'));
      expect(calls[1].toolName, equals('file_write'));
      expect(calls[1].arguments['content'], equals('hello'));
    });

    test('2.7 HTML entities with quotes, angle brackets and ampersands in arguments', () {
      const entityJson = '{"query": "&lt;tag key=&quot;val&quot;&gt; &amp; &apos;test&#39;"}';
      final map = faultTolerance.repairAndParseArguments(entityJson);
      expect(map['query'], equals('<tag key="val"> & \'test\''));
    });

    test('2.8 Jitter bounds verification in RetryPolicy', () {
      const policy = RetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 1600),
        backoffMultiplier: 2.0,
        jitterFactor: 0.25,
      );

      for (int attempt = 0; attempt < 5; attempt++) {
        final baseMs = (100 * math.pow(2.0, attempt)).clamp(100.0, 1600.0);
        final minExpected = (baseMs * 0.75).round();
        final maxExpected = (baseMs * 1.25).round();

        for (int i = 0; i < 50; i++) {
          final delay = policy.calculateDelay(attempt);
          expect(delay.inMilliseconds, greaterThanOrEqualTo(math.max(10, minExpected)));
          expect(delay.inMilliseconds, lessThanOrEqualTo(maxExpected + 2));
        }
      }
    });

    test('2.9 High attempt count does not overflow duration or math.pow', () {
      const policy = RetryPolicy(
        initialDelay: Duration(milliseconds: 500),
        maxDelay: Duration(milliseconds: 8000),
      );

      final delay = policy.calculateDelay(100);
      expect(delay.inMilliseconds, greaterThanOrEqualTo(6000));
      expect(delay.inMilliseconds, lessThanOrEqualTo(10000));
    });

    test('2.10 Chinese Self-Healing diagnostic feedback formatting and Chinese alignment', () {
      final feedback = AgentFaultTolerance.buildSelfHealingFeedback(
        toolName: 'code_eval',
        arguments: {'code': 'import "dart:io"; exit(1);'},
        errorMessage: '沙箱禁止系统级 exit 调用',
        suggestion: '请使用纯算法逻辑，避免调用系统中断函数。',
      );

      expect(feedback.startsWith('【工具执行异常与自愈引导】'), isTrue);
      expect(feedback, contains('- 调用的工具: `code_eval`'));
      expect(feedback, contains('- 传入的参数: `{"code":"import \\"dart:io\\"; exit(1);"}`'));
      expect(feedback, contains('- 失败原因: 沙箱禁止系统级 exit 调用'));
      expect(feedback, contains('- 修复建议: 请使用纯算法逻辑，避免调用系统中断函数。'));
    });

    test('2.11 Tool Call Stripping on mixed user content and tool calls', () {
      const mixedContent = '''
先让我检查一下当前目录：
<tool_call>
{"name": "file_list", "arguments": {"path": "lib"}}
</tool_call>
文件列表如下所示。
''';

      final stripped = faultTolerance.stripToolCallBlocks(mixedContent);
      expect(stripped, contains('先让我检查一下当前目录：'));
      expect(stripped, contains('文件列表如下所示。'));
      expect(stripped, isNot(contains('<tool_call>')));
      expect(stripped, isNot(contains('file_list')));
    });

    test('2.12 Multi-Format parser extracts correctly from Hermes XML, Qwen Tagged XML, and DSML v1', () {
      const hermes = '<functioncall> {"name": "calc", "arguments": {"x": 10}} </functioncall>';
      final hermesCalls = faultTolerance.parseToolCalls(hermes);
      expect(hermesCalls.length, 1);
      expect(hermesCalls.first.toolName, 'calc');
      expect(hermesCalls.first.syntaxFormat, 'hermes_xml');

      const qwenTagged = '<tool_call><function=fetch_news><parameter=topic>AI</parameter><parameter=count>5</parameter></function></tool_call>';
      final qwenCalls = faultTolerance.parseToolCalls(qwenTagged);
      expect(qwenCalls.length, 1);
      expect(qwenCalls.first.toolName, 'fetch_news');
      expect(qwenCalls.first.arguments['topic'], 'AI');
      expect(qwenCalls.first.arguments['count'], 5);

      const dsmlV1 = '<｜｜DSML｜｜tool_calls><｜｜DSML｜｜invoke name="ping"><｜｜DSML｜｜parameter name="host">example.com</｜｜DSML｜｜parameter></｜｜DSML｜｜invoke></｜｜DSML｜｜tool_calls>';
      final dsmlCalls = faultTolerance.parseToolCalls(dsmlV1);
      expect(dsmlCalls.length, 1);
      expect(dsmlCalls.first.toolName, 'ping');
      expect(dsmlCalls.first.arguments['host'], 'example.com');
    });

    test('2.13 Non-ASCII and Chinese parameter key handling in JSON repair and arguments parsing', () {
      // 1. Unquoted Chinese keys with mixed types
      const unquotedChinese = '{城市: "北京", 气温: 25.5, 预报天数: 7, 穿衣建议: "适宜穿T恤", 空气指数: 42, 是否降雨: false}';
      final mapChinese = faultTolerance.repairAndParseArguments(unquotedChinese);
      expect(mapChinese['城市'], equals('北京'));
      expect(mapChinese['气温'], equals(25.5));
      expect(mapChinese['预报天数'], equals(7));
      expect(mapChinese['穿衣建议'], equals('适宜穿T恤'));
      expect(mapChinese['空气指数'], equals(42));
      expect(mapChinese['是否降雨'], equals(false));

      // 2. Single-quoted Chinese keys & mixed unquoted keys with trailing commas
      const singleQuotedMixed = "{'地理信息': {经度: 116.4074, 纬度: 39.9042, '行政区': '北京市', }, 标签列表: ['首都', '直辖市', ], 启用状态: true, }";
      final mapNested = faultTolerance.repairAndParseArguments(singleQuotedMixed);
      expect(mapNested['地理信息']['经度'], equals(116.4074));
      expect(mapNested['地理信息']['纬度'], equals(39.9042));
      expect(mapNested['地理信息']['行政区'], equals('北京市'));
      expect(mapNested['标签列表'], equals(['首都', '直辖市']));
      expect(mapNested['启用状态'], equals(true));

      // 3. Non-ASCII Japanese, Korean, and Unicode symbols in parameter keys
      const multilingualKeys = "{ユーザー名: '山田太郎', 地域: '東京', 사용자_ID: 9981, 状态_FLAG: true, 🎯目标: '完成M27'}";
      final mapMulti = faultTolerance.repairAndParseArguments(multilingualKeys);
      expect(mapMulti['ユーザー名'], equals('山田太郎'));
      expect(mapMulti['地域'], equals('東京'));
      expect(mapMulti['사용자_ID'], equals(9981));
      expect(mapMulti['状态_FLAG'], equals(true));
      expect(mapMulti['🎯目标'], equals('完成M27'));

      // 4. Non-ASCII keys inside DSML v1 XML format
      const dsmlV1Chinese = '''
<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="custom_tool">
<｜｜DSML｜｜parameter name="目标城市">深圳</｜｜DSML｜｜parameter>
<｜｜DSML｜｜parameter name="执行次数">3</｜｜DSML｜｜parameter>
<｜｜DSML｜｜parameter name="强制刷新">true</｜｜DSML｜｜parameter>
</｜｜DSML｜｜invoke>
</｜｜DSML｜｜tool_calls>
''';
      final dsmlCalls = faultTolerance.parseToolCalls(dsmlV1Chinese);
      expect(dsmlCalls.length, equals(1));
      expect(dsmlCalls.first.toolName, equals('custom_tool'));
      expect(dsmlCalls.first.arguments['目标城市'], equals('深圳'));
      expect(dsmlCalls.first.arguments['执行次数'], equals(3));
      expect(dsmlCalls.first.arguments['强制刷新'], equals(true));
    });

    test('2.14 DSML v2 format without markdown code fences & standalone single calls', () {
      // 1. Standard DSML v2 block with raw JSON without ```json ... ``` markdown fences
      const dsmlV2NoFences = '''
<｜tool calls begin｜>
<｜tool call begin｜>function<｜tool sep｜>math_eval
{"expression": "100 * 3.14159", "precision": 4}
<｜tool call end｜>
<｜tool calls end｜>
''';
      final callsNoFences = faultTolerance.parseToolCalls(dsmlV2NoFences);
      expect(callsNoFences.length, equals(1));
      expect(callsNoFences[0].toolName, equals('math_eval'));
      expect(callsNoFences[0].arguments['expression'], equals('100 * 3.14159'));
      expect(callsNoFences[0].arguments['precision'], equals(4));
      expect(callsNoFences[0].syntaxFormat, equals('dsml_v2'));

      final strippedNoFences = faultTolerance.stripToolCallBlocks(dsmlV2NoFences);
      expect(strippedNoFences, isEmpty);

      // 2. Standalone DSML v2 single call without outer <｜tool calls begin｜> and without code fences
      const dsmlV2Standalone = '''
我将为您查询杭州的天气情况：
<｜tool call begin｜>function<｜tool sep｜>weather_query
{"city": "Hangzhou", "days": 5}
<｜tool call end｜>
请稍候，我正在获取最新气象数据。
''';
      final callsStandalone = faultTolerance.parseToolCalls(dsmlV2Standalone);
      expect(callsStandalone.length, equals(1));
      expect(callsStandalone[0].toolName, equals('weather_query'));
      expect(callsStandalone[0].arguments['city'], equals('Hangzhou'));
      expect(callsStandalone[0].arguments['days'], equals(5));

      final strippedStandalone = faultTolerance.stripToolCallBlocks(dsmlV2Standalone);
      expect(strippedStandalone, contains('我将为您查询杭州的天气情况：'));
      expect(strippedStandalone, contains('请稍候，我正在获取最新气象数据。'));
      expect(strippedStandalone, isNot(contains('<｜tool call begin｜>')));
      expect(strippedStandalone, isNot(contains('weather_query')));

      // 3. Multiple DSML v2 calls without code fences and with unquoted Chinese parameter keys
      const dsmlV2MultipleNoFences = '''
<｜tool calls begin｜>
<｜tool call begin｜>function<｜tool sep｜>time_calculator
{时区: "Asia/Shanghai", 相对天数: 3}
<｜tool call end｜>
<｜tool call begin｜>function<｜tool sep｜>wiki_lookup
{条目: "量子力学", 语言: "zh"}
<｜tool call end｜>
<｜tool calls end｜>
''';
      final callsMulti = faultTolerance.parseToolCalls(dsmlV2MultipleNoFences);
      expect(callsMulti.length, equals(2));
      expect(callsMulti[0].toolName, equals('time_calculator'));
      expect(callsMulti[0].arguments['时区'], equals('Asia/Shanghai'));
      expect(callsMulti[0].arguments['相对天数'], equals(3));
      expect(callsMulti[1].toolName, equals('wiki_lookup'));
      expect(callsMulti[1].arguments['条目'], equals('量子力学'));
      expect(callsMulti[1].arguments['语言'], equals('zh'));

      // 4. ASCII pipe characters (<|tool calls begin|>) with raw JSON and code fences
      const dsmlV2AsciiPipes = '''
<|tool calls begin|>
<|tool call begin|>function<|tool sep|>code_eval
{"language": "dart", "code": "print(42);"}
<|tool call end|>
<|tool calls end|>
''';
      final callsAscii = faultTolerance.parseToolCalls(dsmlV2AsciiPipes);
      expect(callsAscii.length, equals(1));
      expect(callsAscii[0].toolName, equals('code_eval'));
      expect(callsAscii[0].arguments['language'], equals('dart'));
      expect(callsAscii[0].arguments['code'], equals('print(42);'));
    });
  });
}
