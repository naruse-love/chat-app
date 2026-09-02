import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/tool/tool.dart';
import '../../utils/diff_helper.dart';
import '../path_sanitizer.dart';

/// Preview information for a file write operation, used in HITL confirmation cards.
class FileWritePreview {
  final String relativePath;
  final String oldContent;
  final String newContent;
  final List<DiffLine> diffLines;
  final DiffSummary diffSummary;
  final bool fileExisted;
  final String mode;

  const FileWritePreview({
    required this.relativePath,
    required this.oldContent,
    required this.newContent,
    required this.diffLines,
    required this.diffSummary,
    required this.fileExisted,
    required this.mode,
  });

  Map<String, dynamic> toJson() {
    return {
      'relativePath': relativePath,
      'oldContent': oldContent,
      'newContent': newContent,
      'diffLines': diffLines.map((e) => e.toJson()).toList(),
      'diffSummary': diffSummary.toJson(),
      'fileExisted': fileExisted,
      'mode': mode,
    };
  }
}

/// Sandboxed file write tool [Level 2 Sensitive Confirmation].
///
/// Creates or updates a file inside the local sandbox workspace, with support for
/// overwrite, append, and create_new modes, and generates diff previews for HITL verification.
class FileWriteTool extends Tool {
  final PathSanitizer pathSanitizer;

  FileWriteTool({PathSanitizer? pathSanitizer})
      : pathSanitizer = pathSanitizer ??
            PathSanitizer(
              sandboxDir: Directory(p.join(Directory.systemTemp.path, 'chat_app_sandbox')),
            );

  @override
  String get name => 'file_write';

  @override
  String get displayName => '写入文件';

  @override
  String get description =>
      'Writes text content to a file inside the local sandbox workspace. Supports overwrite, append, and create_new modes, and generates unified diff previews for confirmation.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.sensitiveConfirm;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'path',
          type: 'string',
          description: '沙箱内文件的相对路径 (例如 "notes/todo.md", "src/main.dart")',
          required: true,
        ),
        ToolParameter(
          name: 'content',
          type: 'string',
          description: '待写入文件的完整文本内容',
          required: true,
        ),
        ToolParameter(
          name: 'mode',
          type: 'string',
          description: '写入模式: overwrite (覆盖写入，默认), append (追加至末尾), create_new (仅当文件不存在时新建)',
          required: false,
          defaultValue: 'overwrite',
          enumValues: ['overwrite', 'append', 'create_new'],
        ),
        ToolParameter(
          name: 'create_directories',
          type: 'boolean',
          description: '若父级目录不存在，是否自动递归创建 (默认为 true)',
          required: false,
          defaultValue: true,
        ),
      ];

  /// Generates a diff preview snapshot comparing current file content with the intended write payload.
  FileWritePreview generateDiffPreview(
    String rawPath,
    String content, {
    String mode = 'overwrite',
  }) {
    final isExternal = pathSanitizer.isExternalPath(rawPath);
    final File file;
    final String displayPath;
    if (isExternal) {
      file = File(rawPath);
      displayPath = rawPath;
    } else {
      file = pathSanitizer.resolveSafeFile(rawPath);
      displayPath = pathSanitizer.getRelativePath(file);
    }

    String oldContent = '';
    bool fileExisted = false;

    if (file.existsSync()) {
      fileExisted = true;
      try {
        oldContent = file.readAsStringSync();
      } catch (_) {
        oldContent = '';
      }
    }

    String effectiveNewContent = content;
    if (mode == 'append' && fileExisted) {
      effectiveNewContent = '$oldContent$content';
    }

    final diffLines = DiffHelper.computeDiff(oldContent, effectiveNewContent);
    final diffSummary = DiffHelper.summarize(diffLines);

    return FileWritePreview(
      relativePath: displayPath,
      oldContent: oldContent,
      newContent: effectiveNewContent,
      diffLines: diffLines,
      diffSummary: diffSummary,
      fileExisted: fileExisted,
      mode: mode,
    );
  }

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final rawPath = arguments['path']?.toString() ?? '';
    final content = arguments['content']?.toString() ?? '';
    final mode = (arguments['mode']?.toString() ?? 'overwrite').toLowerCase();
    final createDirectories = arguments['create_directories'] as bool? ?? true;

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
      final exists = file.existsSync();

      // Check create_new constraint
      if (mode == 'create_new' && exists) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '文件已存在: "$displayPath" (create_new 模式拒绝覆盖已有文件)',
          content: '写入失败: 文件 "$displayPath" 已存在，若要覆盖请使用 mode: "overwrite"',
          executionDuration: stopwatch.elapsed,
          rawData: {'path': displayPath, 'exists': true},
        );
      }

      // Check if target is a directory
      if (exists && FileSystemEntity.isDirectorySync(file.path)) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '目标路径是已有目录而非文件: "$displayPath"',
          executionDuration: stopwatch.elapsed,
        );
      }

      final contentBytes = utf8.encode(content);
      final existingBytes = exists ? file.lengthSync() : 0;
      final isAppend = mode == 'append';

      // 1. Validate single file quota
      pathSanitizer.validateFileWriteSize(
        existingBytes: existingBytes,
        bytesToWrite: contentBytes.length,
        isAppend: isAppend,
      );

      // 2. Validate workspace total quota
      final bytesToAdd = isAppend ? contentBytes.length : (contentBytes.length - existingBytes);
      if (bytesToAdd > 0) {
        await pathSanitizer.validateWorkspaceCapacity(bytesToAdd);
      }

      // 3. Create parent directories if requested
      if (createDirectories) {
        final parent = file.parent;
        if (!parent.existsSync()) {
          parent.createSync(recursive: true);
        }
      }

      // 4. Generate Diff summary for execution result
      final preview = generateDiffPreview(rawPath, content, mode: mode);

      // 5. Perform the actual write
      final fileMode = isAppend ? FileMode.append : FileMode.write;
      await file.writeAsBytes(contentBytes, mode: fileMode, flush: true);

      stopwatch.stop();

      final totalSizeBytes = file.lengthSync();
      final modeLabel = mode == 'append' ? '追加' : (exists ? '覆盖更新' : '新建');

      final buffer = StringBuffer();
      buffer.writeln('✅ **文件写入成功**: `$displayPath`');
      buffer.writeln('- **操作类型**: $modeLabel (模式: `$mode`)');
      buffer.writeln('- **写入数据**: ${contentBytes.length} 字节');
      buffer.writeln('- **当前文件总大小**: $totalSizeBytes 字节');
      buffer.writeln('- **变更统计**: ${preview.diffSummary.formattedSummary}');

      return ToolExecutionResult.success(
        toolName: name,
        content: buffer.toString(),
        rawData: {
          'path': displayPath,
          'bytesWritten': contentBytes.length,
          'totalSizeBytes': totalSizeBytes,
          'mode': mode,
          'fileExisted': exists,
          'diffSummary': preview.diffSummary.toJson(),
        },
        executionDuration: stopwatch.elapsed,
        metadata: {
          'path': displayPath,
          'mode': mode,
        },
      );
    } on PathSanitizerException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '写入失败 (安全限制): ${e.message}',
        executionDuration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '写入文件异常: $e',
        content: '写入文件发生未知异常: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}
