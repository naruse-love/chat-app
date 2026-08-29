import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/tool_call.dart';
import 'package:chat/widgets/chat_bubble.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  group('ChatBubble Tool Rendering Stress Tests — All 8 Tool Types & Metas', () {
    final toolTypes = [
      {'name': 'math_eval', 'label': '数学计算', 'category': '基础计算', 'badge': '安全 Level 0'},
      {'name': 'time_calculator', 'label': '时间/时区计算', 'category': '时间工具', 'badge': '安全 Level 0'},
      {'name': 'weather_query', 'label': '天气查询', 'category': '生活服务', 'badge': '安全 Level 0'},
      {'name': 'wiki_lookup', 'label': '维基百科检索', 'category': '知识检索', 'badge': '安全 Level 0'},
      {'name': 'web_search', 'label': '网络搜索', 'category': '搜索引擎', 'badge': '只读 Level 1'},
      {'name': 'google_search', 'label': 'Google 搜索', 'category': '搜索引擎', 'badge': '只读 Level 1'},
      {'name': 'bing_search', 'label': 'Bing 搜索', 'category': '搜索引擎', 'badge': '只读 Level 1'},
      {'name': 'url_fetch', 'label': '网页抓取', 'category': '网页内容', 'badge': '只读 Level 1'},
      {'name': 'custom_unknown_tool', 'label': 'custom_unknown_tool', 'category': '自定义工具', 'badge': '工具'},
    ];

    for (final tool in toolTypes) {
      testWidgets('Renders tool card correctly for ${tool['name']}', (tester) async {
        final message = ChatMessage(
          id: 'msg_${tool['name']}',
          conversationId: 'conv_1',
          role: 'assistant',
          content: '正在处理中...',
          toolCalls: [
            ToolCall(
              id: 'call_${tool['name']}',
              type: 'function',
              functionName: tool['name']!,
              arguments: '{"param": "test_value"}',
            ),
          ],
          timestamp: DateTime(2026, 8, 28, 14, 30),
        );

        await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));

        // Summary title should include tool display name
        expect(find.textContaining('思考与工具调用 [${tool['label']}]'), findsOneWidget);

        // Tap to expand the accordion panel
        await tester.tap(find.textContaining('思考与工具调用'));
        await tester.pumpAndSettle();

        // Check tool card metadata
        expect(find.text(tool['label']!), findsOneWidget);
        expect(find.text(tool['category']!), findsOneWidget);
        expect(find.text(tool['badge']!), findsOneWidget);
        expect(find.text('${tool['name']!}({"param": "test_value"})'), findsOneWidget);
      });
    }
  });

  group('ChatBubble Stress Tests — Malformed, Null & Extreme Arguments', () {
    testWidgets('Handles empty arguments string without crashing', (tester) async {
      final message = ChatMessage(
        id: 'msg_empty_args',
        conversationId: 'conv_1',
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(
            id: 'call_empty',
            type: 'function',
            functionName: 'math_eval',
            arguments: '',
          ),
        ],
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));
      await tester.tap(find.textContaining('思考与工具调用'));
      await tester.pumpAndSettle();

      expect(find.text('math_eval()'), findsOneWidget);
    });

    testWidgets('Handles malformed JSON arguments string gracefully', (tester) async {
      final message = ChatMessage(
        id: 'msg_malformed_args',
        conversationId: 'conv_1',
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(
            id: 'call_malformed',
            type: 'function',
            functionName: 'weather_query',
            arguments: '{"city": "Beijing", unclosed...',
          ),
        ],
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));
      await tester.tap(find.textContaining('思考与工具调用'));
      await tester.pumpAndSettle();

      expect(find.text('weather_query({"city": "Beijing", unclosed...)'), findsOneWidget);
    });

    testWidgets('Handles deeply nested complex arguments without UI distortion', (tester) async {
      const complexArgs = '{"query":{"nested":{"level1":{"level2":[1,2,3,"deep"]}}}}';
      final message = ChatMessage(
        id: 'msg_complex_args',
        conversationId: 'conv_1',
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(
            id: 'call_complex',
            type: 'function',
            functionName: 'wiki_lookup',
            arguments: complexArgs,
          ),
        ],
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));
      await tester.tap(find.textContaining('思考与工具调用'));
      await tester.pumpAndSettle();

      expect(find.text('wiki_lookup($complexArgs)'), findsOneWidget);
    });

    testWidgets('Handles extraordinarily long arguments string (4000+ chars) in scrollable container', (tester) async {
      final longArgs = '{"data": "${'A' * 4000}"}';
      final message = ChatMessage(
        id: 'msg_long_args',
        conversationId: 'conv_1',
        role: 'assistant',
        content: '',
        toolCalls: [
          ToolCall(
            id: 'call_long',
            type: 'function',
            functionName: 'url_fetch',
            arguments: longArgs,
          ),
        ],
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));
      await tester.tap(find.textContaining('思考与工具调用'));
      await tester.pumpAndSettle();

      expect(find.text('url_fetch($longArgs)'), findsOneWidget);
    });

    testWidgets('Renders multiple simultaneous tool calls in single assistant message', (tester) async {
      final message = ChatMessage(
        id: 'msg_multi_tools',
        conversationId: 'conv_1',
        role: 'assistant',
        content: '正在并行执行多工具...',
        reasoningContent: '先查询天气，再换算摄氏度，最后获取当前时间。',
        toolCalls: [
          ToolCall(id: 'c1', type: 'function', functionName: 'weather_query', arguments: '{"city":"Tokyo"}'),
          ToolCall(id: 'c2', type: 'function', functionName: 'math_eval', arguments: '{"expression":"25*9/5+32"}'),
          ToolCall(id: 'c3', type: 'function', functionName: 'time_calculator', arguments: '{"operation":"now","timezone":"Asia/Tokyo"}'),
        ],
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));

      expect(find.textContaining('天气查询, 数学计算, 时间/时区计算'), findsOneWidget);

      await tester.tap(find.textContaining('思考与工具调用'));
      await tester.pumpAndSettle();

      expect(find.text('天气查询'), findsOneWidget);
      expect(find.text('数学计算'), findsOneWidget);
      expect(find.text('时间/时区计算'), findsOneWidget);
      expect(find.text('思考过程:'), findsOneWidget);
      expect(find.text('先查询天气，再换算摄氏度，最后获取当前时间。'), findsOneWidget);
      expect(find.text('过程输出:'), findsOneWidget);
    });
  });

  group('ChatBubble Stress Tests — Tool Output Panel (role == tool)', () {
    testWidgets('Renders tool output bubble with toolCallId and collapsible content', (tester) async {
      final message = ChatMessage(
        id: 'msg_tool_res',
        conversationId: 'conv_1',
        role: 'tool',
        toolCallId: 'call_math_123',
        content: '### 计算结果\n`25 * 9 / 5 + 32 = 77`\n单位: °F',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));

      expect(find.text('工具输出: call_math_123'), findsOneWidget);
      expect(find.text('工具执行结果'), findsOneWidget);
      expect(find.byIcon(Icons.build_circle_outlined), findsOneWidget);

      // Expand tool output panel
      await tester.tap(find.text('工具执行结果'));
      await tester.pumpAndSettle();

      expect(find.textContaining('77'), findsOneWidget);
    });

    testWidgets('Handles null toolCallId on tool message without error', (tester) async {
      final message = ChatMessage(
        id: 'msg_tool_null_id',
        conversationId: 'conv_1',
        role: 'tool',
        toolCallId: null,
        content: '执行成功',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));
      expect(find.text('工具输出: '), findsOneWidget);
      expect(find.text('工具执行结果'), findsOneWidget);
    });

    testWidgets('Handles massive tool output (10,000 chars markdown) without UI overflow', (tester) async {
      final repeatText = '这是段落内容，包含大量测试文本和分析。\n\n' * 200;
      final largeMarkdown = '## 维基百科长篇条目\n\n$repeatText';
      final message = ChatMessage(
        id: 'msg_tool_large',
        conversationId: 'conv_1',
        role: 'tool',
        toolCallId: 'call_wiki_large',
        content: largeMarkdown,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));
      await tester.tap(find.text('工具执行结果'));
      await tester.pumpAndSettle();

      expect(find.textContaining('维基百科长篇条目'), findsOneWidget);
    });

    testWidgets('Renders tool failure / error message correctly in markdown', (tester) async {
      final message = ChatMessage(
        id: 'msg_tool_error',
        conversationId: 'conv_1',
        role: 'tool',
        toolCallId: 'call_error_1',
        content: '工具 [math_eval] 执行失败: 参数校验失败: 表达式不能为空',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestableWidget(ChatBubble(message: message)));
      await tester.tap(find.text('工具执行结果'));
      await tester.pumpAndSettle();

      expect(find.textContaining('工具 [math_eval] 执行失败'), findsOneWidget);
    });
  });
}
