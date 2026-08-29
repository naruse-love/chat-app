import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/tool/tool.dart';
import '../path_sanitizer.dart';
import '../rune_safe_json_truncator.dart';

/// Sandboxed file list tool [Level 1 Read-Only].
///
/// Lists files and directories inside the local sandbox workspace with metadata,
/// supporting recursive search, glob matching, and depth limits.
class FileListTool extends Tool {
  final PathSanitizer pathSanitizer;

  FileListTool({PathSanitizer? pathSanitizer})
      : pathSanitizer = pathSanitizer ??
            PathSanitizer(
              sandboxDir: Directory(p.join(Directory.systemTemp.path, 'chat_app_sandbox')),
            );

  @override
  String get name => 'file_list';

  @override
  String get displayName => '列出文件';

  @override
  String get description =>
      'Lists files and directories inside the local sandbox workspace with file sizes, modified timestamps, recursive navigation, and pattern filtering.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
        ToolParameter(
          name: 'directory',
          type: 'string',
          description: '沙箱内待查询的相对目录路径 (默认为根目录 ".")',
          required: false,
          defaultValue: '.',
        ),
        ToolParameter(
          name: 'recursive',
          type: 'boolean',
          description: '是否递归遍历子目录 (默认为 false)',
          required: false,
          defaultValue: false,
        ),
        ToolParameter(
          name: 'pattern',
          type: 'string',
          description: '文件名通配符过滤模式 (例如 "*.dart", "*.json", "note*")',
          required: false,
        ),
        ToolParameter(
          name: 'max_depth',
          type: 'integer',
          description: '最大递归深度 (默认为 3 层)',
          required: false,
          defaultValue: 3,
        ),
      ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final rawDirectory = arguments['directory']?.toString() ?? '.';
    final recursive = arguments['recursive'] as bool? ?? false;
    final pattern = arguments['pattern']?.toString();
    final maxDepthArg = arguments['max_depth'];
    int maxDepth = 3;
    if (maxDepthArg is num) {
      maxDepth = maxDepthArg.toInt().clamp(1, 10);
    } else if (maxDepthArg is String) {
      maxDepth = (int.tryParse(maxDepthArg) ?? 3).clamp(1, 10);
    }

    try {
      final sanitizedRel = pathSanitizer.sanitizeRelativePath(rawDirectory);
      final targetDir = pathSanitizer.resolveSafeDirectory(rawDirectory);

      if (!targetDir.existsSync()) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: '目录未找到: "$sanitizedRel"',
          content: '列出失败: 沙箱中未找到目录 "$sanitizedRel"',
          executionDuration: stopwatch.elapsed,
          rawData: {'directory': sanitizedRel, 'found': false},
        );
      }

      RegExp? patternRegex;
      if (pattern != null && pattern.trim().isNotEmpty) {
        patternRegex = _globToRegex(pattern.trim());
      }

      final canonicalTarget = p.canonicalize(targetDir.path);
      final items = <Map<String, dynamic>>[];

      _walkDirectory(
        targetDir,
        canonicalTarget,
        currentDepth: 1,
        maxDepth: recursive ? maxDepth : 1,
        recursive: recursive,
        patternRegex: patternRegex,
        collected: items,
      );

      // Sort directories first, then alphabetically by path
      items.sort((a, b) {
        if (a['isDirectory'] == true && b['isDirectory'] != true) return -1;
        if (a['isDirectory'] != true && b['isDirectory'] == true) return 1;
        return (a['path'] as String).compareTo(b['path'] as String);
      });

      stopwatch.stop();

      final buffer = StringBuffer();
      buffer.writeln('📁 **目录列表**: `${sanitizedRel == '.' ? '沙箱根目录' : sanitizedRel}`');
      buffer.writeln('- **项目总数**: ${items.length} 个 (递归: $recursive, 最大深度: $maxDepth)');
      if (pattern != null && pattern.isNotEmpty) {
        buffer.writeln('- **匹配模式**: `$pattern`');
      }
      buffer.writeln();

      if (items.isEmpty) {
        buffer.writeln('*该目录下未找到任何匹配的文件或子目录。*');
      } else {
        buffer.writeln('| 类型 | 相对路径 | 大小 | 最后修改时间 |');
        buffer.writeln('|---|---|---|---|');
        for (final item in items) {
          final isDir = item['isDirectory'] == true;
          final typeIcon = isDir ? '📁 目录' : '📄 文件';
          final pathStr = item['path'] as String;
          final sizeStr = isDir ? '-' : _formatBytes(item['sizeBytes'] as int? ?? 0);
          final modifiedStr = item['modified'] as String? ?? '-';
          buffer.writeln('| $typeIcon | `$pathStr` | $sizeStr | $modifiedStr |');
        }
      }

      final formattedText = buffer.toString();
      final truncatedContent = RuneSafeJsonTruncator.truncateString(formattedText, 16000);

      return ToolExecutionResult.success(
        toolName: name,
        content: truncatedContent,
        rawData: {
          'directory': sanitizedRel,
          'count': items.length,
          'items': items,
        },
        executionDuration: stopwatch.elapsed,
        metadata: {
          'directory': sanitizedRel,
          'recursive': recursive,
          'pattern': pattern,
        },
      );
    } on PathSanitizerException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '列出文件失败 (安全限制): ${e.message}',
        executionDuration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '列出文件异常: $e',
        content: '列出文件发生未知异常: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }

  void _walkDirectory(
    Directory currentDir,
    String canonicalTarget, {
    required int currentDepth,
    required int maxDepth,
    required bool recursive,
    required RegExp? patternRegex,
    required List<Map<String, dynamic>> collected,
  }) {
    if (currentDepth > maxDepth) return;

    List<FileSystemEntity> entities;
    try {
      entities = currentDir.listSync(followLinks: false);
    } catch (_) {
      return;
    }

    for (final entity in entities) {
      final isDir = entity is Directory;
      final fileName = p.basename(entity.path);
      final relPath = pathSanitizer.getRelativePath(entity);

      bool matches = true;
      if (patternRegex != null) {
        matches = patternRegex.hasMatch(fileName) || patternRegex.hasMatch(relPath);
      }

      if (matches || isDir) {
        if (matches) {
          int sizeBytes = 0;
          DateTime? modified;
          try {
            final stat = entity.statSync();
            sizeBytes = isDir ? 0 : stat.size;
            modified = stat.modified;
          } catch (_) {}

          final dateStr = modified != null
              ? '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} ${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}'
              : '-';

          collected.add({
            'name': fileName,
            'path': relPath,
            'isDirectory': isDir,
            'sizeBytes': sizeBytes,
            'modified': dateStr,
          });
        }
      }

      if (isDir && recursive && currentDepth < maxDepth) {
        _walkDirectory(
          entity,
          canonicalTarget,
          currentDepth: currentDepth + 1,
          maxDepth: maxDepth,
          recursive: recursive,
          patternRegex: patternRegex,
          collected: collected,
        );
      }
    }
  }

  RegExp _globToRegex(String glob) {
    final regexStr = glob
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp('^$regexStr\$', caseSensitive: false);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
