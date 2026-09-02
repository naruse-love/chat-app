import 'package:flutter/material.dart';
import '../models/agent_step_telemetry.dart';
import '../services/agent_service.dart';

/// Visual token usage metric badge and progress bar derived from TokenBudgetTelemetry.
class TokenBudgetBadge extends StatelessWidget {
  /// The token budget telemetry metrics to visualize.
  final TokenBudgetTelemetry? budget;

  /// Prompt tokens count (optional).
  final int? promptTokens;

  /// Completion tokens count (optional).
  final int? completionTokens;

  /// Total tokens count (optional).
  final int? totalTokens;

  /// Whether to display in compact pill chip mode.
  final bool isCompact;

  /// Whether to display full breakdown details (e.g., token saved & compression counts).
  final bool showDetails;

  /// Optional tap callback.
  final VoidCallback? onTap;

  const TokenBudgetBadge({
    super.key,
    this.budget,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.isCompact = false,
    this.showDetails = true,
    this.onTap,
  });

  /// Convenience constructor creating a compact pill badge.
  factory TokenBudgetBadge.compact({
    Key? key,
    TokenBudgetTelemetry? budget,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
    VoidCallback? onTap,
  }) {
    return TokenBudgetBadge(
      key: key,
      budget: budget,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: totalTokens,
      isCompact: true,
      onTap: onTap,
    );
  }

  /// Convenience constructor creating a badge from a TokenBudgetTelemetryEvent.
  factory TokenBudgetBadge.fromEvent(
    TokenBudgetTelemetryEvent event, {
    Key? key,
    bool isCompact = false,
    bool showDetails = true,
    VoidCallback? onTap,
  }) {
    return TokenBudgetBadge(
      key: key,
      budget: event.telemetry,
      isCompact: isCompact,
      showDetails: showDetails,
      onTap: onTap,
    );
  }

  /// Calculates the appropriate color coding:
  /// - Green: < 70%
  /// - Amber/Orange: 70% - 89%
  /// - Red: >= 90%
  static Color getStatusColor(double usageRatio) {
    if (usageRatio >= 0.90) {
      return const Color(0xFFD32F2F); // Red 700
    } else if (usageRatio >= 0.70) {
      return const Color(0xFFF57C00); // Orange 700 / Amber
    } else {
      return const Color(0xFF388E3C); // Green 700
    }
  }

  /// Returns a Chinese label describing the budget state.
  static String getStatusLabel(double usageRatio, bool isCircuitBreakerTriggered) {
    if (isCircuitBreakerTriggered || usageRatio >= 0.90) {
      return '高消耗/熔断保护';
    } else if (usageRatio >= 0.70) {
      return '较高消耗';
    } else {
      return '预算充裕';
    }
  }

  String _formatNumber(int number) {
    final str = number.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i != 0) {
        buffer.write(',');
      }
    }
    return buffer.toString().split('').reversed.join('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveBudget = budget;
    final ratio = effectiveBudget?.usageRatio ?? 0.0;
    final statusColor = getStatusColor(ratio);
    final isWarning = effectiveBudget?.isWarning ?? (ratio >= 0.75);
    final isCircuitBreaker = effectiveBudget?.isCircuitBreakerTriggered ?? false;

    // Compact Pill Chip Mode
    if (isCompact) {
      final pTokens = promptTokens ?? effectiveBudget?.currentEstimatedTokens;
      final cTokens = completionTokens;
      final tTokens = totalTokens ?? (pTokens != null && cTokens != null ? (pTokens + cTokens) : pTokens);

      String tokenText;
      if (promptTokens != null && completionTokens != null) {
        tokenText = '🪙 ${_formatNumber(tTokens ?? 0)} Tokens (↑${_formatNumber(promptTokens!)} / ↓${_formatNumber(completionTokens!)})';
      } else if (effectiveBudget != null) {
        tokenText = '🪙 ${_formatNumber(effectiveBudget.currentEstimatedTokens)} / ${_formatNumber(effectiveBudget.budgetCap)} Tokens';
      } else if (tTokens != null) {
        tokenText = '🪙 ${_formatNumber(tTokens)} Tokens';
      } else {
        tokenText = '🪙 ? Tokens';
      }

      return InkWell(
        borderRadius: BorderRadius.circular(6.0),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(6.0),
            border: Border.all(
              color: statusColor.withValues(alpha: isDark ? 0.4 : 0.25),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tokenText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? theme.colorScheme.onSurface : statusColor,
                  fontSize: 10.0,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
              if (isWarning || isCircuitBreaker) ...[
                const SizedBox(width: 4.0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: (isCircuitBreaker ? Colors.red : Colors.orange).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3.0),
                  ),
                  child: Text(
                    isCircuitBreaker ? '🚨 熔断' : '⚠️ ${(ratio * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isCircuitBreaker ? Colors.red[700] : Colors.orange[800],
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Detailed Bar Mode
    final currentTokens = effectiveBudget?.currentEstimatedTokens ?? (totalTokens ?? 0);
    final budgetCap = effectiveBudget?.budgetCap ?? 32000;
    final clampedRatio = ratio.clamp(0.0, 1.0);
    final percentStr = (ratio * 100).toStringAsFixed(1);

    return InkWell(
      borderRadius: BorderRadius.circular(10.0),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.5),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(
            color: statusColor.withValues(alpha: isDark ? 0.4 : 0.3),
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Row: Icon, Tokens, Percentage, and Status Chip
            Row(
              children: [
                Icon(
                  Icons.toll_outlined,
                  size: 16.0,
                  color: statusColor,
                ),
                const SizedBox(width: 6.0),
                Expanded(
                  child: Text(
                    '${_formatNumber(currentTokens)} / ${_formatNumber(budgetCap)} Tokens',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6.0),
                // Percentage badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    '$percentStr%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6.0),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3.0),
              child: LinearProgressIndicator(
                value: clampedRatio,
                minHeight: 5.0,
                backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),

            // Detail line: Tokens saved via sliding window compaction & warnings
            if (showDetails && effectiveBudget != null && (effectiveBudget.tokensSaved > 0 || effectiveBudget.compressionCount > 0 || effectiveBudget.isWarning || effectiveBudget.isCircuitBreakerTriggered)) ...[
              const SizedBox(height: 5.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (effectiveBudget.tokensSaved > 0 || effectiveBudget.compressionCount > 0)
                    Row(
                      children: [
                        Icon(
                          Icons.compress_rounded,
                          size: 13.0,
                          color: Colors.blue[600],
                        ),
                        const SizedBox(width: 3.0),
                        Text(
                          '滑动窗口已节省 ${_formatNumber(effectiveBudget.tokensSaved)} Tokens (${effectiveBudget.compressionCount}次压缩)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.blue[700],
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  if (effectiveBudget.isCircuitBreakerTriggered)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3.0),
                      ),
                      child: Text(
                        '熔断中',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.red[700],
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else if (effectiveBudget.isWarning)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3.0),
                      ),
                      child: Text(
                        '接近上限',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange[800],
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Alert banner/card indicating the agent token budget circuit breaker has been tripped.
class CircuitBreakerAlertCard extends StatelessWidget {
  /// Optional title for the alert banner.
  final String? title;

  /// The reason or context diagnostic message for the circuit breaker trigger.
  final String reason;

  /// Estimated tokens when the circuit breaker tripped.
  final int? currentTokens;

  /// The budget cap for the conversation.
  final int? budgetCap;

  /// Optional dismissal callback.
  final VoidCallback? onDismiss;

  const CircuitBreakerAlertCard({
    super.key,
    this.title,
    required this.reason,
    this.currentTokens,
    this.budgetCap,
    this.onDismiss,
  });

  String _formatNumber(int number) {
    final str = number.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i != 0) {
        buffer.write(',');
      }
    }
    return buffer.toString().split('').reversed.join('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF371212) : const Color(0xFFFFF3F3),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: const Color(0xFFE53935).withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 10.0, 8.0, 6.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6.0),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    size: 20.0,
                    color: Color(0xFFD32F2F),
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? '🚨 Token 预算熔断保护已触发 · 已生成总结收尾',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
                        ),
                      ),
                      if (currentTokens != null || budgetCap != null) ...[
                        const SizedBox(height: 2.0),
                        Text(
                          '当前估算: ${currentTokens != null ? _formatNumber(currentTokens!) : "上限"} / ${budgetCap != null ? _formatNumber(budgetCap!) : "32,000"} Tokens',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white70 : const Color(0xFF757575),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18.0),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: theme.colorScheme.outline,
                    onPressed: onDismiss,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x33E53935)),

          // Explanation & Reason Body
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 15.0,
                      color: Color(0xFFD32F2F),
                    ),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        '已达到上下文安全上限，系统已自动剥离后续工具调用，大模型将生成最终总结文本以确保对话安全与稳定性。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? const Color(0xFFFFCDD2) : const Color(0xFFB71C1C),
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                if (reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 8.0),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      reason.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        fontSize: 11.0,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Backwards compatibility alias for CircuitBreakerAlertCard.
typedef CircuitBreakerAlertWidget = CircuitBreakerAlertCard;
