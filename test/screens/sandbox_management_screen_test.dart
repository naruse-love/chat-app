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

    await tester.pumpAndSettle();

    expect(find.text('沙箱文件管理'), findsOneWidget);
    expect(find.text('沙箱存储配额'), findsOneWidget);
    expect(find.text('hello.txt'), findsOneWidget);
    expect(find.byIcon(Icons.description), findsOneWidget);

    // Tap on file to trigger preview dialog
    await tester.tap(find.text('hello.txt'));
    await tester.pumpAndSettle();

    expect(find.text('Hello, Sandbox World!'), findsOneWidget);
    expect(find.text('复制内容'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);

    // Close preview dialog
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsNothing);
  });
}
