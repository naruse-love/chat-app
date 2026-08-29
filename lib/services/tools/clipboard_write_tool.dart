import 'package:flutter/services.dart';
import '../../models/tool/tool.dart';
import '../rune_safe_json_truncator.dart';

/// Clipboard write tool [Level 2 Sensitive Confirmation].
///
/// Writes plain text to the system clipboard upon user confirmation.
class ClipboardWriteTool extends Tool {
  const ClipboardWriteTool();

  @override
  String get name => 'clipboard_write';

  @override
  String get displayName => '写入剪贴板';

  @override
  String get description =>
      'Writes plain text to the system clipboard upon user confirmation, updating clipboard content.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.sensitiveConfirm;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'text',
          type: 'string',
          description: '待写入系统剪贴板的纯文本内容',
          required: true,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final text = arguments['text']?.toString() ?? '';

    try {
      await Clipboard.setData(ClipboardData(text: text));
      stopwatch.stop();

      final preview = RuneSafeJsonTruncator.truncateString(text, 500);
      final buffer = StringBuffer();
      buffer.writeln('📋 **已成功将文本写入系统剪贴板** (共 ${text.length} 字符):');
      buffer.writeln();
      buffer.writeln('```text');
      buffer.writeln(preview);
      buffer.writeln('```');

      return ToolExecutionResult.success(
        toolName: name,
        content: buffer.toString(),
        rawData: {
          'text': text,
          'length': text.length,
          'written': true,
        },
        executionDuration: stopwatch.elapsed,
        metadata: {'length': text.length},
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '写入剪贴板失败: $e',
        content: '写入剪贴板时发生异常: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}
