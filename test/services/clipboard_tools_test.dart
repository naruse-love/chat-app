import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/tool/tool_security_level.dart';
import 'package:chat/services/tools/clipboard_read_tool.dart';
import 'package:chat/services/tools/clipboard_write_tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ClipboardReadTool readTool;
  late ClipboardWriteTool writeTool;
  String? mockClipboardContent;

  setUp(() {
    readTool = const ClipboardReadTool();
    writeTool = const ClipboardWriteTool();
    mockClipboardContent = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          mockClipboardContent = (methodCall.arguments as Map)['text'] as String?;
          return null;
        }
        if (methodCall.method == 'Clipboard.getData') {
          return mockClipboardContent != null ? {'text': mockClipboardContent} : null;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  group('Clipboard Tools Unit Tests', () {
    test('declares correct security classification levels', () {
      expect(readTool.name, equals('clipboard_read'));
      expect(readTool.displayName, equals('读取剪贴板'));
      expect(readTool.securityLevel, equals(ToolSecurityLevel.readOnly));

      expect(writeTool.name, equals('clipboard_write'));
      expect(writeTool.displayName, equals('写入剪贴板'));
      expect(writeTool.securityLevel, equals(ToolSecurityLevel.sensitiveConfirm));
      expect(writeTool.parameters.any((p) => p.name == 'text'), isTrue);
    });

    test('writes text to clipboard and reads it back successfully', () async {
      const sampleText = 'Flutter Agent Clipboard Content 测试 123';

      // 1. Write text
      final writeRes = await writeTool.execute({'text': sampleText});
      expect(writeRes.success, isTrue);
      expect(writeRes.content, contains('已成功将文本写入系统剪贴板'));
      expect(writeRes.rawData['length'], equals(sampleText.length));

      // 2. Read back
      final readRes = await readTool.execute({});
      expect(readRes.success, isTrue);
      expect(readRes.content, contains('已成功读取系统剪贴板'));
      expect(readRes.content, contains(sampleText));
      expect(readRes.rawData['text'], equals(sampleText));
    });

    test('handles empty clipboard gracefully', () async {
      await Clipboard.setData(const ClipboardData(text: ''));

      final readRes = await readTool.execute({});
      expect(readRes.success, isTrue);
      expect(readRes.content, contains('系统剪贴板当前为空'));
      expect(readRes.rawData['isEmpty'], isTrue);
    });
  });
}
