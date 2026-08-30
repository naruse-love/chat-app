import 'package:flutter/material.dart';
import '../models/tool/tool.dart';
import '../models/tool/tool_confirmation.dart';
import '../services/tools/file_write_tool.dart';
import 'diff_viewer_widget.dart';

/// Interactive confirmation card displayed to the user when a sensitive (Level 2+)
/// tool execution requires explicit authorization.
class ToolConfirmationCard extends StatefulWidget {
  final ToolConfirmationRequest request;
  final void Function({required bool allow, String? reason}) onDecision;
  final VoidCallback? onCancel;

  const ToolConfirmationCard({
    super.key,
    required this.request,
    required this.onDecision,
    this.onCancel,
  });

  @override
  State<ToolConfirmationCard> createState() => _ToolConfirmationCardState();
}

class _ToolConfirmationCardState extends State<ToolConfirmationCard> {
  bool _showReasonInput = false;
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _handleApprove() {
    widget.onDecision(allow: true);
  }

  void _handleReject() {
    final reason = _reasonController.text.trim();
    widget.onDecision(
      allow: false,
      reason: reason.isNotEmpty ? reason : null,
    );
  }

  Color _getSecurityColor(ToolSecurityLevel level) {
    switch (level) {
      case ToolSecurityLevel.safe:
        return const Color(0xFF2E7D32);
      case ToolSecurityLevel.readOnly:
        return const Color(0xFF1976D2);
      case ToolSecurityLevel.sensitiveConfirm:
        return const Color(0xFFE65100);
      case ToolSecurityLevel.privilegedNative:
        return const Color(0xFFC62828);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final securityColor = _getSecurityColor(widget.request.securityLevel);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202124) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: securityColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, isDark, securityColor),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildToolDescription(context, isDark),
                const SizedBox(height: 10),
                _buildToolSpecificPreview(context, isDark),
                if (_showReasonInput) ...[
                  const SizedBox(height: 10),
                  _buildReasonInput(context, isDark),
                ],
                const SizedBox(height: 12),
                _buildActionButtons(context, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, Color securityColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: securityColor.withValues(alpha: isDark ? 0.2 : 0.1),
      child: Row(
        children: [
          Icon(
            Icons.security_outlined,
            size: 20,
            color: securityColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.request.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: securityColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.request.securityLevel.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: securityColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.onCancel != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onCancel,
              tooltip: '取消',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  Widget _buildToolDescription(BuildContext context, bool isDark) {
    final desc = widget.request.description;
    return Text(
      (desc != null && desc.isNotEmpty)
          ? desc
          : '模型请求执行受限操作，需要您的明确确认。',
      style: TextStyle(
        fontSize: 12.5,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
    );
  }

  Widget _buildToolSpecificPreview(BuildContext context, bool isDark) {
    final name = widget.request.toolName;
    final preview = widget.request.previewData;

    if (name == 'file_write') {
      return _buildFileWritePreview(context, isDark, preview);
    } else if (name == 'file_delete') {
      return _buildFileDeletePreview(context, isDark, preview);
    } else if (name == 'code_eval') {
      return _buildCodeEvalPreview(context, isDark, preview);
    } else if (name == 'clipboard_write') {
      return _buildClipboardWritePreview(context, isDark, preview);
    } else if (name == 'calendar_create_event') {
      return _buildCalendarCreatePreview(context, isDark, preview);
    } else if (name == 'notification_schedule') {
      return _buildNotificationSchedulePreview(context, isDark, preview);
    } else {
      return _buildGenericArgumentsPreview(context, isDark);
    }
  }

  Widget _buildFileWritePreview(BuildContext context, bool isDark, dynamic preview) {
    if (preview is FileWritePreview) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_open, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '写入路径: ${preview.relativePath}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  !preview.fileExisted ? '新建文件' : (preview.mode == 'append' ? '追加内容' : '覆盖写入'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DiffViewerWidget(
            diffLines: preview.diffLines,
            summary: preview.diffSummary,
            filePath: preview.relativePath,
            maxHeight: 240,
          ),
        ],
      );
    } else if (preview is Map) {
      final path = preview['path']?.toString() ?? widget.request.arguments['path']?.toString() ?? '';
      final content = preview['content']?.toString() ?? widget.request.arguments['content']?.toString() ?? '';
      return _buildCodeBox(context, isDark, title: '写入目标: $path', code: content);
    }

    return _buildGenericArgumentsPreview(context, isDark);
  }

  Widget _buildFileDeletePreview(BuildContext context, bool isDark, dynamic preview) {
    final path = (preview is Map) ? (preview['path']?.toString() ?? '') : (widget.request.arguments['path']?.toString() ?? '');
    final recursive = (preview is Map) ? (preview['recursive'] == true) : (widget.request.arguments['recursive'] == true);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A1C1C) : const Color(0xFFFDE8E8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF8B2525) : const Color(0xFFF8B4B4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFE53935), size: 18),
              SizedBox(width: 6),
              Text(
                '警告：此操作将永久删除本地文件或目录',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE53935),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '目标路径: $path',
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          if (recursive)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                '模式: 递归删除子项 (recursive=true)',
                style: TextStyle(fontSize: 11, color: Colors.redAccent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCodeEvalPreview(BuildContext context, bool isDark, dynamic preview) {
    final code = (preview is Map)
        ? (preview['code']?.toString() ?? '')
        : (widget.request.arguments['code']?.toString() ?? '');
    final timeout = (preview is Map)
        ? (preview['timeout_ms']?.toString() ?? '3000')
        : (widget.request.arguments['timeout_ms']?.toString() ?? '3000');

    return _buildCodeBox(
      context,
      isDark,
      title: '执行代码沙箱 (超时: ${timeout}ms)',
      code: code,
    );
  }

  Widget _buildClipboardWritePreview(BuildContext context, bool isDark, dynamic preview) {
    final text = (preview is Map)
        ? (preview['text']?.toString() ?? '')
        : (widget.request.arguments['text']?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.content_paste_go, size: 16),
              const SizedBox(width: 6),
              const Text(
                '写入系统剪贴板内容:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${text.length} 字符',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCreatePreview(BuildContext context, bool isDark, dynamic preview) {
    final args = widget.request.arguments;
    final title = (preview is Map ? preview['title']?.toString() : null) ??
        args['title']?.toString() ??
        '(无标题日程)';
    final startTime = (preview is Map ? preview['start_time']?.toString() : null) ??
        args['start_time']?.toString() ??
        '';
    final endTime = (preview is Map ? preview['end_time']?.toString() : null) ??
        args['end_time']?.toString() ??
        '';
    final location = (preview is Map ? preview['location']?.toString() : null) ??
        args['location']?.toString();
    final description = (preview is Map ? preview['description']?.toString() : null) ??
        args['description']?.toString();
    final reminderMinutes = (preview is Map ? preview['reminder_minutes']?.toString() : null) ??
        args['reminder_minutes']?.toString() ??
        args['remind_minutes_before']?.toString();
    final isAllDay = (preview is Map && preview['is_all_day'] == true) || args['is_all_day'] == true;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2634) : const Color(0xFFEBF3FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF2C4A6F) : const Color(0xFFB9D7F6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event, color: Color(0xFF1976D2), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAllDay)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '全天',
                    style: TextStyle(fontSize: 10, color: Color(0xFF1976D2)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: Colors.blueGrey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '时间: $startTime 至 $endTime',
                  style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('地点: $location', style: const TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ],
          if (reminderMinutes != null && reminderMinutes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text('提前 $reminderMinutes 分钟提醒', style: const TextStyle(fontSize: 11.5)),
              ],
            ),
          ],
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '备注: $description',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationSchedulePreview(BuildContext context, bool isDark, dynamic preview) {
    final args = widget.request.arguments;
    final title = (preview is Map ? preview['title']?.toString() : null) ??
        args['title']?.toString() ??
        '(无标题提醒)';
    final body = (preview is Map ? preview['body']?.toString() : null) ??
        args['body']?.toString() ??
        '';
    final scheduledTime = (preview is Map ? preview['scheduled_time']?.toString() : null) ??
        (preview is Map ? preview['trigger_time']?.toString() : null) ??
        args['scheduled_time']?.toString() ??
        args['trigger_time']?.toString() ??
        '';
    final isExact = (preview is Map && preview['is_exact_alarm'] == false)
        ? false
        : (args['is_exact_alarm'] != false);
    final payload = (preview is Map ? preview['payload']?.toString() : null) ??
        args['payload']?.toString();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF332211) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF664422) : const Color(0xFFFED7AA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alarm, color: Color(0xFFE65100), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isExact ? '精确闹钟' : '普通通知',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4A3018) : const Color(0xFFFFEDD5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              scheduledTime.isNotEmpty ? '预定时间: $scheduledTime' : '预定提醒',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFC2410C),
              ),
            ),
          ),
          if (payload != null && payload.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '附加数据: $payload',
              style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white54 : Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGenericArgumentsPreview(BuildContext context, bool isDark) {
    final args = widget.request.arguments;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '参数详情:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ...args.entries.map((entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${entry.key}: ${entry.value}',
              style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace'),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildCodeBox(BuildContext context, bool isDark, {required String title, required String code}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                code,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonInput(BuildContext context, bool isDark) {
    return TextField(
      controller: _reasonController,
      decoration: InputDecoration(
        hintText: '输入拒绝理由（可选，将反馈给模型）...',
        hintStyle: const TextStyle(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: const TextStyle(fontSize: 12),
      maxLines: 2,
    );
  }

  Widget _buildActionButtons(BuildContext context, bool isDark) {
    return Row(
      children: [
        TextButton(
          onPressed: () {
            setState(() {
              _showReasonInput = !_showReasonInput;
            });
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            _showReasonInput ? '隐藏理由' : '拒绝理由',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _handleReject,
          icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
          label: const Text('拒绝', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.redAccent),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _handleApprove,
          icon: const Icon(Icons.check, size: 16),
          label: const Text('允许执行', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            minimumSize: Size.zero,
          ),
        ),
      ],
    );
  }
}
