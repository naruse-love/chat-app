import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/update_model.dart';
import '../providers/update_provider.dart';

/// 版本更新提示弹窗
class UpdateDialog extends ConsumerWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  /// 便捷展示更新弹窗
  static Future<void> show(
    BuildContext context, {
    required UpdateInfo updateInfo,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);
    final theme = Theme.of(context);
    final isDownloading = updateState.status == UpdateStatus.downloading;
    final isDownloaded = updateState.status == UpdateStatus.downloaded;
    final isError = updateState.status == UpdateStatus.error;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.system_update_rounded,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '发现新版本',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${updateInfo.currentVersion} → ${updateInfo.latestVersion}',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (updateInfo.fileSize != null && updateInfo.fileSize! > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_zip_outlined,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '包体大小: ${updateInfo.formattedFileSize}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),

            // 更新日志展示区域
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: updateInfo.releaseNotes.trim().isNotEmpty
                        ? MarkdownBody(
                            data: updateInfo.releaseNotes,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                              p: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                            ),
                          )
                        : const Text(
                            '本次更新包含多项稳定性改进与体验优化。',
                            style: TextStyle(fontSize: 13),
                          ),
                  ),
                ),
              ),
            ),

            // 下载进度指示器
            if (isDownloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: updateState.downloadProgress > 0
                    ? updateState.downloadProgress
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '正在下载 ${(updateState.downloadProgress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (updateState.totalBytes > 0)
                    Text(
                      '${(updateState.receivedBytes / (1024 * 1024)).toStringAsFixed(1)}MB / ${(updateState.totalBytes / (1024 * 1024)).toStringAsFixed(1)}MB',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ],

            // 错误提示
            if (isError && updateState.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        updateState.errorMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (isDownloading)
          TextButton(
            onPressed: () {
              ref.read(updateProvider.notifier).cancelDownload();
            },
            child: const Text('取消下载'),
          )
        else ...[
          TextButton(
            onPressed: () {
              ref.read(updateProvider.notifier).dismissUpdate();
              Navigator.of(context).pop();
            },
            child: const Text('稍后再说'),
          ),
          TextButton(
            onPressed: () {
              ref.read(updateProvider.notifier).openReleaseInBrowser();
            },
            child: const Text('前往发布页'),
          ),
          FilledButton.icon(
            icon: Icon(
              isDownloaded ? Icons.install_mobile : Icons.download_rounded,
              size: 18,
            ),
            label: Text(isDownloaded ? '立即安装' : '立即更新'),
            onPressed: () {
              ref.read(updateProvider.notifier).downloadAndInstall();
            },
          ),
        ],
      ],
    );
  }
}
