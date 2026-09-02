import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import '../../models/tool/tool.dart';
import '../path_sanitizer.dart';
import '../rune_safe_json_truncator.dart';

/// Sandboxed file read tool [Level 1 Read-Only].
///
/// Safely reads text content from a file inside the local sandbox workspace,
/// with support for line-range pagination and encoding selection.
class FileReadTool extends Tool {
  final PathSanitizer pathSanitizer;

  FileReadTool({PathSanitizer? pathSanitizer})
      : pathSanitizer = pathSanitizer ??
            PathSanitizer(
              sandboxDir: Directory(p.join(Directory.systemTemp.path, 'chat_app_sandbox')),
            );

  @override
  String get name => 'file_read';

  @override
  String get displayName => '读取文件';

  @override
  String get description =>
      'Reads text content from a file inside the local sandbox workspace. Supports slicing by start_line and end_line for large files, and selecting character encoding.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'path',
          type: 'string',
          description: '沙箱内文件的相对路径 (例如 "notes/todo.md", "src/config.json")',
          required: true,
        ),
        ToolParameter(
          name: 'start_line',
          type: 'integer',
          description: '起始行号 (1-based，包含该行，默认为 1)',
          required: false,
          defaultValue: 1,
        ),
        ToolParameter(
          name: 'end_line',
          type: 'integer',
          description: '结束行号 (1-based，包含该行，若不传则读取至文件末尾)',
          required: false,
        ),
        ToolParameter(
          name: 'encoding',
          type: 'string',
          description: '字符编码 (支持 utf-8, latin1, ascii，默认为 utf-8)',
          required: false,
          defaultValue: 'utf-8',
          enumValues: ['utf-8', 'latin1', 'ascii'],
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final rawPath = arguments['path']?.toString() ?? '';

    if (rawPath.trim().isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '文件路径不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final isExternal = pathSanitizer.isExternalPath(rawPath);
      final enableSandbox = arguments['__enableSandbox'] as bool? ?? true;
      final allowExternal = arguments['__allowExternal'] as bool? ?? false;

      final File file;
      final String displayPath;
      if (isExternal && (!enableSandbox || allowExternal)) {
        file = File(rawPath);
        displayPath = rawPath;
      } else {
        file = pathSanitizer.resolveSafeFile(rawPath);
        displayPath = pathSanitizer.getRelativePath(file);
      }

      if (!file.existsSync()) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '文件未找到: "$rawPath"',
          content: '读取失败: 未找到文件 "$rawPath"',
          executionDuration: stopwatch.elapsed,
          rawData: {'path': rawPath, 'found': false},
        );
      }

      if (FileSystemEntity.isDirectorySync(file.path)) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '指定路径是目录而非文件: "$rawPath"',
          content: '读取失败: "$rawPath" 是一个目录，请使用 file_list 工具查看目录内容',
          executionDuration: stopwatch.elapsed,
        );
      }

      final encodingName = (arguments['encoding']?.toString() ?? 'utf-8').toLowerCase();
      Encoding encoding = utf8;
      if (encodingName == 'latin1') {
        encoding = latin1;
      } else if (encodingName == 'ascii') {
        encoding = ascii;
      }

      final bytes = await file.readAsBytes();
      final String fullText = encodingName == 'utf-8'
          ? utf8.decode(bytes, allowMalformed: true)
          : encoding.decode(bytes);
      final lines = fullText.split('\n');
      final totalLines = lines.length;

      final startLineArg = arguments['start_line'];
      final endLineArg = arguments['end_line'];

      int startLine = 1;
      if (startLineArg != null) {
        if (startLineArg is num) {
          startLine = math.max(1, startLineArg.toInt());
        } else if (startLineArg is String) {
          startLine = math.max(1, int.tryParse(startLineArg) ?? 1);
        }
      }

      int endLine = totalLines;
      if (endLineArg != null) {
        if (endLineArg is num) {
          endLine = math.min(totalLines, math.max(startLine, endLineArg.toInt()));
        } else if (endLineArg is String) {
          final parsed = int.tryParse(endLineArg);
          if (parsed != null) {
            endLine = math.min(totalLines, math.max(startLine, parsed));
          }
        }
      }

      final selectedLines = <String>[];
      if (startLine <= totalLines) {
        for (int i = startLine - 1; i < endLine && i < totalLines; i++) {
          selectedLines.add(lines[i]);
        }
      }

      stopwatch.stop();

      final ext = p.extension(rawPath).replaceAll('.', '');
      final langTag = ext.isNotEmpty ? ext : '';

      final buffer = StringBuffer();
      buffer.writeln('📁 **文件路径**: `$displayPath` (共 $totalLines 行, ${bytes.length} 字节)');
      buffer.writeln('📖 **读取范围**: 第 $startLine 行 ~ 第 $endLine 行 (共 ${selectedLines.length} 行)');
      buffer.writeln();
      buffer.writeln('```$langTag');
      for (int i = 0; i < selectedLines.length; i++) {
        final lineNum = (startLine + i).toString().padLeft(4, ' ');
        buffer.writeln('$lineNum | ${selectedLines[i]}');
      }
      buffer.writeln('```');

      final formattedContent = buffer.toString();
      final truncatedContent = RuneSafeJsonTruncator.truncateString(formattedContent, 16000);

      return ToolExecutionResult.success(
        toolName: name,
        content: truncatedContent,
        rawData: {
          'path': displayPath,
          'totalLines': totalLines,
          'startLine': startLine,
          'endLine': endLine,
          'linesRead': selectedLines.length,
          'sizeBytes': bytes.length,
          'content': selectedLines.join('\n'),
        },
        executionDuration: stopwatch.elapsed,
        metadata: {
          'path': rawPath,
          'encoding': encodingName,
        },
      );
    } on PathSanitizerException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '读取失败 (安全限制): ${e.message}',
        executionDuration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '读取文件异常: $e',
        content: '读取文件发生未知异常: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}
