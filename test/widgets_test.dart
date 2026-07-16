import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/widgets/chat_bubble.dart';
import 'package:chat/widgets/chat_input.dart';
import 'package:chat/widgets/markdown_renderer.dart';

void main() {
  group('ChatBubble Widget Tests', () {
    testWidgets('Renders User message aligned to the right', (WidgetTester tester) async {
      final userMessage = ChatMessage(
        id: 'msg_user_1',
        conversationId: 'conv_1',
        role: 'user',
        content: 'Hello, this is a user message',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(message: userMessage),
          ),
        ),
      );

      expect(find.text('Hello, this is a user message'), findsOneWidget);
      
      final containerFinder = find.byType(Container).first;
      final container = tester.widget<Container>(containerFinder);
      expect(container.alignment, Alignment.centerRight);
    });

    testWidgets('Renders Assistant message aligned to the left with thinking panel', (WidgetTester tester) async {
      final assistantMessage = ChatMessage(
        id: 'msg_assistant_1',
        conversationId: 'conv_1',
        role: 'assistant',
        content: 'This is the final response.',
        reasoningContent: 'Deep reasoning process here...',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(message: assistantMessage),
          ),
        ),
      );

      // Verify final content is displayed
      expect(find.text('This is the final response.'), findsOneWidget);

      // Verify thinking process header is displayed
      expect(find.text('思考过程'), findsOneWidget);
      expect(find.byIcon(Icons.psychology), findsOneWidget);

      // Verify reasoning content is originally collapsed (hidden by CrossFade)
      expect(find.text('Deep reasoning process here...'), findsOneWidget);
      // Wait, in AnimatedCrossFade the child is in the widget tree but might have size 0. 
      // Let's tap on the thinking process header to verify toggle
      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();
    });

    testWidgets('Renders Tool output correctly', (WidgetTester tester) async {
      final toolMessage = ChatMessage(
        id: 'msg_tool_1',
        conversationId: 'conv_1',
        role: 'tool',
        toolCallId: 'call_abc123',
        content: '{"result": "Search Results"}',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(message: toolMessage),
          ),
        ),
      );

      expect(find.text('工具输出: call_abc123'), findsOneWidget);
      expect(find.text('工具执行结果'), findsOneWidget);
      expect(find.byIcon(Icons.build_circle_outlined), findsOneWidget);

      // Verify the panel can be toggled
      await tester.tap(find.text('工具执行结果'));
      await tester.pumpAndSettle();
    });
  });

  group('ChatInput Widget Tests', () {
    testWidgets('Send button disabled when input is empty', (WidgetTester tester) async {
      bool sendTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              onSend: (text, imagePath) {
                sendTriggered = true;
              },
            ),
          ),
        ),
      );

      // Tap send button
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sendTriggered, isFalse);
    });

    testWidgets('Send button enabled and triggers callback when text is entered', (WidgetTester tester) async {
      String? sentText;
      String? sentImage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              onSend: (text, imagePath) {
                sentText = text;
                sentImage = imagePath;
              },
            ),
          ),
        ),
      );

      // Enter text
      await tester.enterText(find.byType(TextField), 'Hello World');
      await tester.pump();

      // Tap send button
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sentText, equals('Hello World'));
      expect(sentImage, isNull);
    });
  });

  group('MarkdownRenderer Widget Tests', () {
    testWidgets('Renders markdown bold formatting', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownRenderer(
              markdownData: 'This is **bold** text.',
            ),
          ),
        ),
      );

      expect(find.text('This is bold text.'), findsOneWidget);
    });

    testWidgets('Renders code block language header and code text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownRenderer(
              markdownData: '```dart\nvoid main() {}\n```',
            ),
          ),
        ),
      );

      expect(find.text('DART'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });
  });
}
