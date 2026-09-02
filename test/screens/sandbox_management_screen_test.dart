import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat/screens/sandbox_management_screen.dart';
import 'package:chat/services/path_sanitizer.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/tools/file_read_tool.dart';

void main() {
  late Directory tempDir;
  late PathSanitizer pathSanitizer;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sandbox_ui_test_');
    pathSanitizer = PathSanitizer(sandboxDir: tempDir);
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('SandboxManagementScreen renders storage quota and file list correctly', (tester) async {
    // Create some sample files in sandbox
    final sampleFile = File('${tempDir.path}/hello.txt');
    sampleFile.writeAsStringSync('Hello, Sandbox World!');

    final customRegistry = ToolRegistry();
    customRegistry.registerTool(FileReadTool(pathSanitizer: pathSanitizer));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          toolRegistryProvider.overrideWithValue(customRegistry),
        ],
        child: const MaterialApp(
          home: SandboxManagementScreen(),
        ),
      ),
    );

    // _loadSandboxFiles uses real async I/O (computeCurrentWorkspaceSize).
    // runAsync lets real I/O complete, then pump rebuilds the widget.
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(find.text('沙箱文件管理'), findsOneWidget);
    expect(find.text('沙箱存储配额'), findsOneWidget);
    expect(find.text('hello.txt'), findsOneWidget);
    expect(find.byIcon(Icons.description), findsOneWidget);

    // Tap the preview button inside runAsync so the FutureBuilder's
    // file.readAsString() future is created in real async zone
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.remove_red_eye_outlined));
      await tester.pump();
      // Allow file.readAsString() to complete in real async
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump(); // Rebuild with resolved FutureBuilder

    // Dialog should show action buttons
    expect(find.text('复制内容'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);

    // Verify the file content is rendered via SelectableText
    expect(find.byType(SelectableText), findsOneWidget);
    final selectableText = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(selectableText.data, contains('Hello, Sandbox World!'));

    // Close preview dialog
    await tester.tap(find.text('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('关闭'), findsNothing);
  });
}
