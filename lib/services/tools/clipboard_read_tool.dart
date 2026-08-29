import 'package:flutter/services.dart';
import '../../models/tool/tool.dart';
import '../rune_safe_json_truncator.dart';

/// Clipboard read tool [Level 1 Read-Only].
///
/// Safely retrieves plain text from the system clipboard.
class ClipboardReadTool extends Tool {
  const ClipboardReadTool();

  @override
  String get name => 'clipboard_read';

  @override
  String get displayName => '读取剪贴板';

  @override
  String get description =>
      'Reads plain text content from the system clipboard safely with length and encoding protection.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      stopwatch.stop();

      if (text == null || text.isEmpty) {
        return ToolExecutionResult.success(
          toolName: name,
          content: '📋 **系统剪贴板当前为空**。',
          rawData: {'text': '', 'length': 0, 'isEmpty': true},
          executionDuration: stopwatch.elapsed,
        );
      }

      final truncated = RuneSafeJsonTruncator.truncateString(text, 8000);
      final buffer = StringBuffer();
      buffer.writeln('📋 **已成功读取系统剪贴板** (共 ${text.length} 字符):');
      buffer.writeln();
      buffer.writeln('```text');
      buffer.writeln(truncated);
      buffer.writeln('```');

      return ToolExecutionResult.success(
        toolName: name,
        content: buffer.toString(),
        rawData: {
          'text': text,
          'length': text.length,
          'isEmpty': false,
        },
        executionDuration: stopwatch.elapsed,
        metadata: {'length': text.length},
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '读取剪贴板失败: $e',
        content: '读取剪贴板时发生异常: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}
