import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/utils/diff_helper.dart';
import 'package:chat/widgets/diff_viewer_widget.dart';

void main() {
  group('DiffViewerWidget Tests', () {
    testWidgets('Renders empty diff state gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiffViewerWidget(diffLines: []),
          ),
        ),
      );

      expect(find.text('无差异内容'), findsOneWidget);
      expect(find.text('+0'), findsOneWidget);
      expect(find.text('-0'), findsOneWidget);
    });

    testWidgets('Renders added, deleted, and unchanged diff lines correctly', (tester) async {
      const diffLines = [
        DiffLine(type: DiffLineType.unchanged, text: 'line 1 unchanged', oldLineNumber: 1, newLineNumber: 1),
        DiffLine(type: DiffLineType.deleted, text: 'line 2 deleted', oldLineNumber: 2, newLineNumber: null),
        DiffLine(type: DiffLineType.added, text: 'line 2 added', oldLineNumber: null, newLineNumber: 2),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiffViewerWidget(
              diffLines: diffLines,
              filePath: 'src/main.dart',
            ),
          ),
        ),
      );

      expect(find.text('src/main.dart'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
      expect(find.text('line 1 unchanged'), findsOneWidget);
      expect(find.text('line 2 deleted'), findsOneWidget);
      expect(find.text('line 2 added'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
    });

    testWidgets('Tapping header toggles expand/collapse state', (tester) async {
      const diffLines = [
        DiffLine(type: DiffLineType.added, text: 'new line of code', newLineNumber: 1),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DiffViewerWidget(
              diffLines: diffLines,
              filePath: 'test.txt',
              initiallyExpanded: true,
            ),
          ),
        ),
      );

      expect(find.text('new line of code'), findsOneWidget);

      // Tap header to collapse
      await tester.tap(find.text('test.txt'));
      await tester.pumpAndSettle();

      expect(find.text('new line of code'), findsNothing);

      // Tap header to expand again
      await tester.tap(find.text('test.txt'));
      await tester.pumpAndSettle();

      expect(find.text('new line of code'), findsOneWidget);
    });
  });
}
