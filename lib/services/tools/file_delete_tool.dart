import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/tool/tool.dart';
import '../path_sanitizer.dart';

/// Sandboxed file delete tool [Level 2 Sensitive Confirmation].
///
/// Safely deletes a file or directory inside the local sandbox workspace,
/// protecting the sandbox root from accidental deletion and requiring recursive confirmation.
class FileDeleteTool extends Tool {
  final PathSanitizer pathSanitizer;

  FileDeleteTool({PathSanitizer? pathSanitizer})
      : pathSanitizer = pathSanitizer ??
            PathSanitizer(
              sandboxDir: Directory(p.join(Directory.systemTemp.path, 'chat_app_sandbox')),
            );

  @override
  String get name => 'file_delete';

  @override
  String get displayName => '删除文件';

  @override
  String get description =>
      'Deletes a file or directory inside the local sandbox workspace with user confirmation and recursive safeguards.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.sensitiveConfirm;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'path',
          type: 'string',
          description: '沙箱内待删除的文件或目录相对路径 (例如 "temp/cache.txt", "old_folder")',
          required: true,
        ),
        ToolParameter(
          name: 'recursive',
          type: 'boolean',
          description: '若目标是包含内容的目录，是否递归删除其所有子文件和子目录 (默认为 false)',
          required: false,
          defaultValue: false,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final rawPath = arguments['path']?.toString() ?? '';
    final recursive = arguments['recursive'] as bool? ?? false;

    if (rawPath.trim().isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '待删除路径不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final sanitizedRel = pathSanitizer.sanitizeRelativePath(rawPath);

      if (sanitizedRel == '.' || sanitizedRel.isEmpty) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '禁止删除沙箱根目录自身',
          content: '删除失败: 出于系统安全保护，禁止删除沙箱根目录',
          executionDuration: stopwatch.elapsed,
        );
      }

      // Check if target is directory
      final dir = pathSanitizer.resolveSafeDirectory(rawPath);
      final file = pathSanitizer.resolveSafeFile(rawPath);

      if (dir.existsSync()) {
        // Target is directory
        final entities = dir.listSync(followLinks: false);
        if (entities.isNotEmpty && !recursive) {
          return ToolExecutionResult.failure(
            toolName: name,
            errorMessage: '目录非空: "$sanitizedRel" (包含 ${entities.length} 个子项，请设置 recursive: true 以确认递归删除)',
            content: '删除失败: 目录 "$sanitizedRel" 包含子项，若需连同子项一并删除请设置 recursive: true',
            executionDuration: stopwatch.elapsed,
            rawData: {'path': sanitizedRel, 'isDirectory': true, 'itemCount': entities.length},
          );
        }

        await dir.delete(recursive: recursive);
        stopwatch.stop();

        return ToolExecutionResult.success(
          toolName: name,
          content: '🗑️ **目录删除成功**: `$sanitizedRel` (递归删除: $recursive)',
          rawData: {
            'path': sanitizedRel,
            'isDirectory': true,
            'recursive': recursive,
            'deleted': true,
          },
          executionDuration: stopwatch.elapsed,
          metadata: {'path': sanitizedRel},
        );
      } else if (file.existsSync()) {
        // Target is file
        final sizeBytes = file.lengthSync();
        await file.delete();
        stopwatch.stop();

        return ToolExecutionResult.success(
          toolName: name,
          content: '🗑️ **文件删除成功**: `$sanitizedRel` (已释放 $sizeBytes 字节)',
          rawData: {
            'path': sanitizedRel,
            'isDirectory': false,
            'sizeBytes': sizeBytes,
            'deleted': true,
          },
          executionDuration: stopwatch.elapsed,
          metadata: {'path': sanitizedRel},
        );
      } else {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '文件或目录不存在: "$sanitizedRel"',
          content: '删除失败: 沙箱中未找到待删除的目标 "$sanitizedRel"',
          executionDuration: stopwatch.elapsed,
          rawData: {'path': sanitizedRel, 'found': false},
        );
      }
    } on PathSanitizerException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '删除失败 (安全限制): ${e.message}',
        executionDuration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '删除操作异常: $e',
        content: '删除操作发生未知异常: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}
