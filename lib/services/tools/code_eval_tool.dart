import '../../models/tool/tool.dart';
import '../code_execution_service.dart';
import '../rune_safe_json_truncator.dart';

/// Code execution tool [Level 2 Sensitive Confirmation].
///
/// Runs pure Dart scripts and expressions inside an isolated Worker Isolate
/// sandbox with hard 3000ms timeout protection.
class CodeEvalTool extends Tool {
  final CodeExecutionService codeExecutionService;

  CodeEvalTool({CodeExecutionService? codeExecutionService})
      : codeExecutionService = codeExecutionService ?? CodeExecutionService();

  @override
  String get name => 'code_eval';

  @override
  String get displayName => '代码执行';

  @override
  String get description =>
      'Executes pure Dart code, algorithms, and data transformations inside an isolated Worker Isolate sandbox with 3000ms hard timeout protection.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.sensitiveConfirm;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'code',
          type: 'string',
          description: '待在隔离沙箱中执行的 Dart 脚本代码或表达式',
          required: true,
        ),
        ToolParameter(
          name: 'timeout_ms',
          type: 'integer',
          description: '执行硬超时时间 (毫秒，默认为 3000ms，最高支持 5000ms)',
          required: false,
          defaultValue: 3000,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final code = arguments['code']?.toString() ?? '';
    final timeoutMsArg = arguments['timeout_ms'];

    int timeoutMs = 3000;
    if (timeoutMsArg is num) {
      timeoutMs = timeoutMsArg.toInt().clamp(500, 5000);
    } else if (timeoutMsArg is String) {
      timeoutMs = (int.tryParse(timeoutMsArg) ?? 3000).clamp(500, 5000);
    }

    if (code.trim().isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '待执行代码不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final execResult = await codeExecutionService.execute(
        code: code,
        timeout: Duration(milliseconds: timeoutMs),
      );
      stopwatch.stop();

      final buffer = StringBuffer();
      buffer.writeln('⚡ **沙箱代码执行完成** (耗时: ${execResult.executionDuration.inMilliseconds}ms)');
      buffer.writeln();
      buffer.writeln('```dart');
      buffer.writeln(code.trim());
      buffer.writeln('```');
      buffer.writeln();

      if (execResult.isTimedOut) {
        buffer.writeln('⏱️ **执行状态**: ❌ **超时终止** (${timeoutMs}ms 硬限制)');
        buffer.writeln('```');
        buffer.writeln(execResult.output);
        buffer.writeln('```');

        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: execResult.errorMessage ?? '代码执行超时',
          content: RuneSafeJsonTruncator.truncateString(buffer.toString(), 16000),
          rawData: execResult.toJson(),
          executionDuration: execResult.executionDuration,
          metadata: {'code': code, 'isTimedOut': true},
        );
      }

      if (!execResult.success) {
        buffer.writeln('⚠️ **执行状态**: ❌ **执行失败**');
        buffer.writeln('```');
        buffer.writeln(execResult.output);
        buffer.writeln('```');

        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: execResult.errorMessage ?? '代码执行异常',
          content: RuneSafeJsonTruncator.truncateString(buffer.toString(), 16000),
          rawData: execResult.toJson(),
          executionDuration: execResult.executionDuration,
          metadata: {'code': code, 'success': false},
        );
      }

      buffer.writeln('✅ **执行状态**: **成功**');
      if (execResult.stdout.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('**标准输出 (stdout)**:');
        buffer.writeln('```text');
        buffer.writeln(execResult.stdout);
        buffer.writeln('```');
      }

      if (execResult.result != null) {
        buffer.writeln();
        buffer.writeln('**返回值 (result)**:');
        buffer.writeln('```json');
        buffer.writeln(CodeExecutionService.formatResult(execResult.result));
        buffer.writeln('```');
      }

      final truncatedContent = RuneSafeJsonTruncator.truncateString(buffer.toString(), 16000);

      return ToolExecutionResult.success(
        toolName: name,
        content: truncatedContent,
        rawData: execResult.toJson(),
        executionDuration: execResult.executionDuration,
        metadata: {'code': code, 'success': true},
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '代码执行服务异常: $e',
        content: '代码执行时发生未捕获异常: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}
