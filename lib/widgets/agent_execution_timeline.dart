import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/agent_step_telemetry.dart';
import 'markdown_renderer.dart';

/// Category color mapping and metadata for the 4 core dimensions and custom categories.
class ToolCategoryTheme {
  final String category;
  final Color primaryColor;
  final Color backgroundColor;
  final IconData icon;

  const ToolCategoryTheme({
    required this.category,
    required this.primaryColor,
    required this.backgroundColor,
    required this.icon,
  });

  /// Resolves the visual theme for a given tool category string adhering to 4D colors.
  factory ToolCategoryTheme.fromCategory(String category, {bool isDark = false}) {
    switch (category) {
      case '基础实用':
      case '基础计算':
      case '时间工具':
      case '生活服务':
      case '知识检索':
      case '搜索引擎':
      case '网页内容':
        return ToolCategoryTheme(
          category: category,
          primaryColor: const Color(0xFF00897B), // Teal 600
          backgroundColor: isDark ? const Color(0xFF004D40).withValues(alpha: 0.35) : const Color(0xFFE0F2F1),
          icon: Icons.auto_awesome,
        );
      case '沙箱与代码':
      case '文件系统':
      case '代码执行':
      case '系统交互':
        return ToolCategoryTheme(
          category: category,
          primaryColor: const Color(0xFFE64A19), // Deep Orange 600
          backgroundColor: isDark ? const Color(0xFFBF360C).withValues(alpha: 0.35) : const Color(0xFFFBE9E7),
          icon: Icons.terminal,
        );
      case '移动原生':
      case '设备日历':
      case '系统通知':
      case '设备通讯录':
      case '设备定位':
      case '地理服务':
        return ToolCategoryTheme(
          category: category,
          primaryColor: const Color(0xFFC62828), // Crimson Red 700
          backgroundColor: isDark ? const Color(0xFF880E4F).withValues(alpha: 0.35) : const Color(0xFFFFEBEE),
          icon: Icons.phone_android,
        );
      case '动态MCP':
      case 'MCP 扩展':
      case 'MCP 扩展工具':
        return ToolCategoryTheme(
          category: category,
          primaryColor: const Color(0xFF7B1FA2), // Deep Purple 700
          backgroundColor: isDark ? const Color(0xFF4A148C).withValues(alpha: 0.35) : const Color(0xFFF3E5F5),
          icon: Icons.hub_outlined,
        );
      default:
        return ToolCategoryTheme(
          category: category.isNotEmpty ? category : '未分类',
          primaryColor: const Color(0xFF455A64), // Blue Grey
          backgroundColor: isDark ? const Color(0xFF263238).withValues(alpha: 0.35) : const Color(0xFFECEFF1),
          icon: Icons.build_circle_outlined,
        );
    }
  }
}

/// A collapsible, multi-step execution timeline widget displaying agent workflow steps.
class AgentExecutionTimelineWidget extends StatefulWidget {
  /// The sequential execution steps to render.
  final List<AgentStepTelemetry> steps;

  /// Whether the entire timeline container is expanded initially.
  final bool initiallyExpanded;

  /// Optional custom title for the timeline header.
  final String? title;

  /// Optional header tap callback.
  final VoidCallback? onHeaderTap;

  const AgentExecutionTimelineWidget({
    super.key,
    required this.steps,
    this.initiallyExpanded = false,
    this.title,
    this.onHeaderTap,
  });

  @override
  State<AgentExecutionTimelineWidget> createState() => _AgentExecutionTimelineWidgetState();
}

class _AgentExecutionTimelineWidgetState extends State<AgentExecutionTimelineWidget> {
  late bool _isExpanded;
  final Set<int> _expandedSteps = <int>{};
  final Set<int> _expandedOutputs = <int>{};

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  int get _totalDurationMs {
    return widget.steps.fold<int>(0, (sum, step) => sum + step.durationMs);
  }

  int get _successCount {
    return widget.steps.where((s) => s.isSuccess).length;
  }

  int get _failedCount {
    return widget.steps.where((s) => !s.isSuccess).length;
  }

  void _toggleStep(int index) {
    setState(() {
      if (_expandedSteps.contains(index)) {
        _expandedSteps.remove(index);
      } else {
        _expandedSteps.add(index);
      }
    });
  }

  void _toggleOutput(int index) {
    setState(() {
      if (_expandedOutputs.contains(index)) {
        _expandedOutputs.remove(index);
      } else {
        _expandedOutputs.add(index);
      }
    });
  }

  String _formatDuration(int ms) {
    if (ms < 1000) {
      return '$ms ms';
    } else {
      return '${(ms / 1000).toStringAsFixed(2)} s';
    }
  }

  String _formatJsonArgs(Map<String, dynamic> arguments) {
    if (arguments.isEmpty) return '{}';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(arguments);
    } catch (_) {
      return arguments.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalSteps = widget.steps.length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.45),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Timeline Header
          InkWell(
            borderRadius: BorderRadius.circular(12.0),
            onTap: () {
              widget.onHeaderTap?.call();
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6.0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.bolt_rounded,
                      size: 18.0,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title ?? 'Agent 执行时间线 ($totalSteps 步)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Row(
                          children: [
                            Text(
                              '共耗时: ${_formatDuration(_totalDurationMs)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontSize: 11,
                              ),
                            ),
                            if (_failedCount > 0) ...[
                              const SizedBox(width: 8.0),
                              Text(
                                '• $_failedCount 步失败',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Summary badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: (_failedCount == 0 ? Colors.green : Colors.amber).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6.0),
                    ),
                    child: Text(
                      '$_successCount/$totalSteps 成功',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _failedCount == 0 ? Colors.green[700] : Colors.amber[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20.0,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),

          // Collapsible Steps Timeline Body
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12.0, 0.0, 12.0, 12.0),
                    child: Column(
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 8.0),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: widget.steps.length,
                          itemBuilder: (context, index) {
                            final step = widget.steps[index];
                            final isLast = index == widget.steps.length - 1;
                            final isStepExpanded = _expandedSteps.contains(index);
                            final isOutputExpanded = _expandedOutputs.contains(index);
                            return _buildTimelineStepItem(
                              context: context,
                              step: step,
                              index: index,
                              isLast: isLast,
                              isExpanded: isStepExpanded,
                              isOutputExpanded: isOutputExpanded,
                              isDark: isDark,
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStepItem({
    required BuildContext context,
    required AgentStepTelemetry step,
    required int index,
    required bool isLast,
    required bool isExpanded,
    required bool isOutputExpanded,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    final categoryTheme = ToolCategoryTheme.fromCategory(step.toolCategory, isDark: isDark);
    final stepNum = step.stepIndex > 0 ? step.stepIndex : index + 1;
    final outputContent = step.fullOutput ?? step.outputPreview ?? '';
    final isLongOutput = outputContent.length > 250 || outputContent.contains('\n\n');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator rail
          SizedBox(
            width: 28.0,
            child: Column(
              children: [
                // Step node dot/icon
                Container(
                  width: 22.0,
                  height: 22.0,
                  decoration: BoxDecoration(
                    color: step.isSuccess
                        ? categoryTheme.primaryColor
                        : theme.colorScheme.error,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (step.isSuccess ? categoryTheme.primaryColor : theme.colorScheme.error)
                            .withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$stepNum',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Connecting vertical line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.0,
                      margin: const EdgeInsets.symmetric(vertical: 2.0),
                      color: categoryTheme.primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8.0),

          // Step content card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: categoryTheme.primaryColor.withValues(alpha: 0.25),
                  width: 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step Header
                  InkWell(
                    borderRadius: BorderRadius.circular(8.0),
                    onTap: () => _toggleStep(index),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Icon(
                            categoryTheme.icon,
                            size: 16.0,
                            color: categoryTheme.primaryColor,
                          ),
                          const SizedBox(width: 6.0),
                          Expanded(
                            child: Text(
                              step.toolName,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4.0),

                          // Category Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: categoryTheme.backgroundColor,
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(
                                color: categoryTheme.primaryColor.withValues(alpha: 0.3),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              step.toolCategory,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: categoryTheme.primaryColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6.0),

                          // Duration Chip
                          Text(
                            _formatDuration(step.durationMs),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontSize: 10.0,
                            ),
                          ),
                          const SizedBox(width: 4.0),

                          // Status icon
                          Icon(
                            step.isSuccess ? Icons.check_circle : Icons.cancel,
                            size: 14.0,
                            color: step.isSuccess ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 2.0),
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 16.0,
                            color: theme.colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Intent preview line (if present and not expanded)
                  if (!isExpanded && step.intent != null && step.intent!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 6.0),
                      child: Text(
                        '意图: ${step.intent!.trim()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.0,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // Badges line (isCompressed, isCircuitBreakerTriggered, tokens)
                  if (step.isCompressed || step.isCircuitBreakerTriggered || step.promptTokens != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 6.0),
                      child: Wrap(
                        spacing: 4.0,
                        runSpacing: 2.0,
                        children: [
                          if (step.isCompressed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3.0),
                              ),
                              child: Text(
                                '已压缩历史',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.blue[700],
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (step.isCircuitBreakerTriggered)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3.0),
                              ),
                              child: Text(
                                '触发熔断',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.red[700],
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (step.promptTokens != null)
                            Text(
                              '🪙 ${step.promptTokens} tok',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontSize: 9.5,
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Expanded Details
                  if (isExpanded) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Intent
                          if (step.intent != null && step.intent!.trim().isNotEmpty) ...[
                            Text(
                              '推理意图:',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: categoryTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 2.0),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(6.0),
                              decoration: BoxDecoration(
                                color: categoryTheme.backgroundColor.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: SelectableText(
                                step.intent!,
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                              ),
                            ),
                            const SizedBox(height: 6.0),
                          ],

                          // Arguments
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '输入参数:',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: categoryTheme.primaryColor,
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: _formatJsonArgs(step.arguments)));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('已复制参数 JSON'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                  child: Text(
                                    '复制参数',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2.0),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(6.0),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                            child: SelectableText(
                              _formatJsonArgs(step.arguments),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6.0),

                          // Output / Error
                          if (!step.isSuccess && step.errorMessage != null) ...[
                            Row(
                              children: [
                                Text(
                                  '执行异常:',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                                const SizedBox(width: 6.0),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3.0),
                                  ),
                                  child: Text(
                                    '自愈诊断反馈',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.error,
                                      fontSize: 9.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2.0),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(6.0),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: SelectableText(
                                step.errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontSize: 11.0,
                                ),
                              ),
                            ),
                          ] else if (outputContent.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '执行输出:',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: categoryTheme.primaryColor,
                                  ),
                                ),
                                Row(
                                  children: [
                                    if (isLongOutput)
                                      InkWell(
                                        onTap: () => _toggleOutput(index),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                          child: Text(
                                            isOutputExpanded ? '收起完整结果 ▴' : '查看完整结果 ▾',
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              color: theme.colorScheme.secondary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 4.0),
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: outputContent));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('已复制执行输出'),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                                        child: Text(
                                          '复制输出',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 2.0),
                            Container(
                              width: double.infinity,
                              constraints: BoxConstraints(
                                maxHeight: isOutputExpanded ? 600 : 180,
                              ),
                              padding: const EdgeInsets.all(6.0),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4.0),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                                ),
                              ),
                              child: SingleChildScrollView(
                                child: outputContent.startsWith('#') || outputContent.contains('**') || outputContent.contains('```')
                                    ? MarkdownRenderer(
                                        markdownData: outputContent,
                                        isStreaming: false,
                                      )
                                    : SelectableText(
                                        outputContent,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontFamily: 'monospace',
                                          fontSize: 10.5,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
