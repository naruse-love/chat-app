import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../services/path_sanitizer.dart';
import '../services/tool_registry.dart';
import '../services/tools/file_read_tool.dart';

/// Sandbox File Management & Export Screen.
/// Allows the user to view, inspect, preview, export, and clear files created in the AI sandbox.
class SandboxManagementScreen extends ConsumerStatefulWidget {
  const SandboxManagementScreen({super.key});

  @override
  ConsumerState<SandboxManagementScreen> createState() => _SandboxManagementScreenState();
}

class _SandboxManagementScreenState extends ConsumerState<SandboxManagementScreen> {
  late PathSanitizer _pathSanitizer;
  List<FileSystemEntity> _entities = [];
  int _totalBytes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSandboxFiles();
  }

  Future<void> _loadSandboxFiles() async {
    setState(() => _isLoading = true);
    try {
      final registry = ref.read(toolRegistryProvider);
      final fileTool = registry.getTool('file_read');
      if (fileTool != null && fileTool is FileReadTool) {
        _pathSanitizer = fileTool.pathSanitizer;
      } else {
        _pathSanitizer = await PathSanitizer.createDefault();
      }

      final entities = _pathSanitizer.listSandboxEntities(recursive: true);
      final totalSize = await _pathSanitizer.computeCurrentWorkspaceSize();

      if (!mounted) return;
      setState(() {
        _entities = entities;
        _totalBytes = totalSize;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDate(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  IconData _getFileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':
      case 'js':
      case 'ts':
      case 'py':
      case 'json':
      case 'html':
      case 'css':
      case 'xml':
        return Icons.code;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
        return Icons.image;
      case 'txt':
      case 'md':
      case 'log':
        return Icons.description;
      case 'pdf':
        return Icons.picture_as_pdf;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _previewFile(File file) {
    final relPath = _pathSanitizer.getRelativePath(file);
    final ext = p.extension(file.path).replaceAll('.', '').toLowerCase();
    final isImage = ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(_getFileIcon(ext), size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                p.basename(file.path),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: isImage
                ? Center(
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text('无法预览图片'),
                    ),
                  )
                : FutureBuilder<String>(
                    future: file.readAsString(encoding: utf8).catchError((_) async {
                      final bytes = await file.readAsBytes();
                      return latin1.decode(bytes);
                    }),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final text = snapshot.data ?? '';
                      return SingleChildScrollView(
                        child: SelectableText(
                          text.isEmpty ? '（空文件）' : text,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                      );
                    },
                  ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制内容'),
            onPressed: () async {
              try {
                final text = await file.readAsString();
                await Clipboard.setData(ClipboardData(text: text));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已复制 $relPath 的内容')),
                  );
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('二进制文件无法直接复制为文本')),
                  );
                }
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
            label: const Text('删除', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await file.delete();
                _loadSandboxFiles();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除文件: $relPath')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除失败: $e')),
                  );
                }
              }
            },
          ),
          TextButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.pop(dialogCtx),
          ),
        ],
      ),
    );
  }

  void _confirmClearSandbox() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('清空沙箱工作区'),
        content: const Text('确定要清空沙箱内的所有文件和子目录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(dialogCtx),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _pathSanitizer.clearSandbox();
              _loadSandboxFiles();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('沙箱工作区已清空')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const maxQuota = PathSanitizer.defaultMaxWorkspaceSize;
    final usageRatio = (_totalBytes / maxQuota).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('沙箱文件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _loadSandboxFiles,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空沙箱',
            onPressed: _entities.isEmpty ? null : _confirmClearSandbox,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Workspace Quota Header Card
                Container(
                  margin: const EdgeInsets.all(12.0),
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                '沙箱存储配额',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Text(
                            '${_formatBytes(_totalBytes)} / ${_formatBytes(maxQuota)} (${(usageRatio * 100).toStringAsFixed(1)}%)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: usageRatio > 0.8 ? Colors.amber[800] : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: usageRatio,
                        borderRadius: BorderRadius.circular(4.0),
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          usageRatio > 0.9
                              ? Colors.red
                              : (usageRatio > 0.75 ? Colors.amber : theme.colorScheme.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '沙箱根路径: ${_pathSanitizer.sandboxDir.path}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // File List Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Row(
                    children: [
                      Text(
                        '文件与目录列表 (${_entities.length})',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),

                // File Entities List
                Expanded(
                  child: _entities.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open,
                                size: 56,
                                color: theme.colorScheme.outline.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '沙箱内暂无文件',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'AI 执行 file_write 等工具创建的文件将保存在此',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _entities.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                          itemBuilder: (context, index) {
                            final entity = _entities[index];
                            final isDir = entity is Directory;
                            final relPath = _pathSanitizer.getRelativePath(entity);
                            final ext = isDir ? '' : p.extension(entity.path).replaceAll('.', '');

                            int fileSize = 0;
                            DateTime? modified;
                            try {
                              final stat = entity.statSync();
                              fileSize = stat.size;
                              modified = stat.modified;
                            } catch (_) {}

                            return ListTile(
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isDir
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : theme.colorScheme.primary.withValues(alpha: 0.12),
                                child: Icon(
                                  isDir ? Icons.folder : _getFileIcon(ext),
                                  size: 18,
                                  color: isDir ? Colors.amber[800] : theme.colorScheme.primary,
                                ),
                              ),
                              title: Text(
                                relPath,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${isDir ? "目录" : _formatBytes(fileSize)}${modified != null ? " • ${_formatDate(modified)}" : ""}',
                                style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                              ),
                              trailing: isDir
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.remove_red_eye_outlined, size: 20),
                                      tooltip: '查看预览',
                                      onPressed: () => _previewFile(entity as File),
                                    ),
                              onTap: isDir ? null : () => _previewFile(entity as File),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
