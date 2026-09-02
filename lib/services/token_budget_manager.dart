import 'dart:convert';
import '../models/chat_message.dart';
import '../models/agent_step_telemetry.dart';

/// Circuit breaker evaluation state for token budgets.
enum CircuitBreakerState {
  normal,
  warning,
  tripped,
}

/// Action status after evaluating token budget and sliding window compaction.
enum BudgetActionStatus {
  normal,
  compressionApplied,
  circuitBreakerTriggered,
}

/// Configuration parameters for TokenBudgetManager.
class TokenBudgetConfig {
  /// Maximum context window in tokens (default 32000).
  final int maxContextTokens;

  /// Reserved tokens for model output completion (default 4096).
  final int maxOutputTokens;

  /// Ratio to trigger sliding window history compaction (default 0.75).
  final double compressionThresholdRatio;

  /// Ratio to trip global circuit breaker (default 0.90).
  final double circuitBreakerThresholdRatio;

  /// Number of recent interactive rounds to preserve uncompressed (default 2).
  final int preserveRecentRounds;

  /// Number of initial runes (code points) to preserve in compressed tool output.
  final int compressedHeadRunes;

  /// Number of trailing runes (code points) to preserve in compressed tool output.
  final int compressedTailRunes;

  const TokenBudgetConfig({
    this.maxContextTokens = 32000,
    this.maxOutputTokens = 4096,
    this.compressionThresholdRatio = 0.75,
    this.circuitBreakerThresholdRatio = 0.90,
    this.preserveRecentRounds = 2,
    this.compressedHeadRunes = 200,
    this.compressedTailRunes = 100,
  });
}

/// Result of sliding window history compaction.
class CompactedHistoryResult {
  final List<ChatMessage> messages;
  final int tokensSaved;
  final int compressionCount;

  const CompactedHistoryResult({
    required this.messages,
    required this.tokensSaved,
    required this.compressionCount,
  });
}

/// Result of evaluating global circuit breaker.
class CircuitBreakerEvaluation {
  final CircuitBreakerState state;
  final bool shouldStripTools;
  final int estimatedTokens;
  final double usageRatio;
  final String? forcedConclusionPrompt;

  const CircuitBreakerEvaluation({
    required this.state,
    required this.shouldStripTools,
    required this.estimatedTokens,
    required this.usageRatio,
    this.forcedConclusionPrompt,
  });
}

/// Complete evaluation result returned by TokenBudgetManager.
class BudgetEvaluationResult {
  final BudgetActionStatus status;
  final int estimatedPromptTokens;
  final int maxContextTokens;
  final double usageRatio;
  final List<ChatMessage> effectiveMessages;
  final String? forcedConclusionPrompt;
  final int tokensSavedByCompression;
  final int compressionCount;

  const BudgetEvaluationResult({
    required this.status,
    required this.estimatedPromptTokens,
    required this.maxContextTokens,
    required this.usageRatio,
    required this.effectiveMessages,
    this.forcedConclusionPrompt,
    this.tokensSavedByCompression = 0,
    this.compressionCount = 0,
  });

  /// Whether tool schemas should be stripped when dispatching request to model.
  bool get shouldStripTools => status == BudgetActionStatus.circuitBreakerTriggered;

  /// Converts evaluation result into a TokenBudgetTelemetry model.
  TokenBudgetTelemetry toTelemetry() {
    return TokenBudgetTelemetry(
      currentEstimatedTokens: estimatedPromptTokens,
      budgetCap: maxContextTokens,
      usageRatio: usageRatio,
      isWarning: usageRatio >= 0.75 && status != BudgetActionStatus.circuitBreakerTriggered,
      isCircuitBreakerTriggered: status == BudgetActionStatus.circuitBreakerTriggered,
      compressionCount: compressionCount,
      tokensSaved: tokensSavedByCompression,
    );
  }
}

/// Pure-Dart Hybrid Token Estimator and Token Budget Manager.
class TokenBudgetManager {
  final TokenBudgetConfig config;

  TokenBudgetManager({TokenBudgetConfig? config})
      : config = config ?? const TokenBudgetConfig();

  // ==========================================
  // 1. Pure-Dart Hybrid Token Estimator
  // ==========================================

  /// Determines whether a Unicode Rune belongs to CJK / East Asian scripts.
  static bool isCjk(int rune) {
    return (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK Unified Ideographs
        (rune >= 0x3400 && rune <= 0x4DBF) || // CJK Extension A
        (rune >= 0x20000 && rune <= 0x2A6DF) || // CJK Extension B
        (rune >= 0xF900 && rune <= 0xFAFF) || // CJK Compatibility
        (rune >= 0x3040 && rune <= 0x309F) || // Hiragana
        (rune >= 0x30A0 && rune <= 0x30FF) || // Katakana
        (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul Syllables
        (rune >= 0x3000 && rune <= 0x303F) || // CJK Symbols and Punctuation
        (rune >= 0xFF00 && rune <= 0xFFEF); // Halfwidth and Fullwidth Forms
  }

  /// Estimates token count for a raw text string using hybrid heuristic tokenizer.
  /// - CJK characters: ~0.85 token/char
  /// - English/ASCII (words, punctuation, whitespace): ~3.8 char/token
  /// - Emojis and other multi-byte Unicode: ~1.5 token/code point
  int estimateTokens(String text) {
    if (text.isEmpty) return 0;

    int cjkCount = 0;
    int asciiCount = 0;
    int whitespaceCount = 0;
    int otherCount = 0;

    for (final rune in text.runes) {
      if (isCjk(rune)) {
        cjkCount++;
      } else if (rune <= 0x7F) {
        if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D) {
          whitespaceCount++;
        } else {
          asciiCount++;
        }
      } else {
        otherCount++;
      }
    }

    final cjkTokens = (cjkCount * 0.85).ceil();
    final asciiTokens = ((asciiCount + whitespaceCount) / 3.8).ceil();
    final otherTokens = (otherCount * 1.5).ceil();

    final total = cjkTokens + asciiTokens + otherTokens;
    return total > 0 ? total : 1;
  }

  /// Estimates tokens consumed by a single [ChatMessage] (including ChatML overhead, tool calls, and vision).
  int estimateMessageTokens(ChatMessage message) {
    // ChatML protocol wrapper overhead: <|im_start|>role\ncontent<|im_end|>\n (approx 4 tokens)
    int tokens = 4;

    tokens += estimateTokens(message.content);

    if (message.reasoningContent != null && message.reasoningContent!.isNotEmpty) {
      tokens += estimateTokens(message.reasoningContent!);
    }

    // OpenAI Tool Calls overhead
    if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
      for (final tc in message.toolCalls!) {
        tokens += 8; // Tool call container & ID overhead
        tokens += estimateTokens(tc.functionName);
        tokens += estimateTokens(tc.arguments);
      }
    }

    // Vision Image input overhead (OpenAI standard low-res base tile: 85 tokens)
    if (message.imagePath != null && message.imagePath!.isNotEmpty) {
      tokens += 85;
    }

    return tokens;
  }

  /// Estimates total conversation tokens including system prompt and tool definitions.
  int estimateConversationTokens(
    List<ChatMessage> messages, {
    String? systemPrompt,
    List<Map<String, dynamic>>? tools,
  }) {
    int total = 3; // Top-level primer & EOS framing

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      total += 4 + estimateTokens(systemPrompt);
    }

    for (final msg in messages) {
      total += estimateMessageTokens(msg);
    }

    if (tools != null && tools.isNotEmpty) {
      total += 10; // Tool schema list wrapper overhead
      for (final tool in tools) {
        final jsonStr = jsonEncode(tool);
        total += estimateTokens(jsonStr);
      }
    }

    return total;
  }

  // ==========================================
  // 2. Sliding Window History Compaction
  // ==========================================

  /// Compacts older intermediate tool execution output messages (`role == 'tool'`)
  /// while strictly preserving:
  /// 1. System prompt & First user message (original user objective).
  /// 2. Active recent $N$ rounds (Assistant + Tool outputs).
  CompactedHistoryResult compactIntermediateToolHistory(
    List<ChatMessage> messages, {
    int? budgetCap,
    double? compressionTriggerRatio,
    int? keepLastNRounds,
    int? headRunes,
    int? tailRunes,
    String? systemPrompt,
    List<Map<String, dynamic>>? tools,
  }) {
    final effectiveBudget = budgetCap ?? config.maxContextTokens;
    final effectiveRounds = keepLastNRounds ?? config.preserveRecentRounds;
    final effectiveHead = headRunes ?? config.compressedHeadRunes;
    final effectiveTail = tailRunes ?? config.compressedTailRunes;

    if (messages.length <= 2) {
      return CompactedHistoryResult(
        messages: messages,
        tokensSaved: 0,
        compressionCount: 0,
      );
    }

    final rawTokens = estimateConversationTokens(
      messages,
      systemPrompt: systemPrompt,
      tools: tools,
    );

    // Locate the protection cutoff index for the most recent N tool rounds from the tail
    int protectedToolCount = 0;
    int protectionCutoffIndex = messages.length;

    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.role == 'tool') {
        protectedToolCount++;
        if (protectedToolCount > effectiveRounds) {
          protectionCutoffIndex = i + 1;
          break;
        }
      }
    }

    final compactedList = <ChatMessage>[];
    int compressionCount = 0;

    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];

      // Always protect:
      // - The first user message (i == 0 or first user role)
      // - Any message in the protected recent tail
      // - Normal user messages
      if (i == 0 || i >= protectionCutoffIndex || msg.role == 'user') {
        compactedList.add(msg);
        continue;
      }

      // Compact intermediate tool output messages
      if (msg.role == 'tool') {
        final originalContent = msg.content;
        final runes = originalContent.runes.toList();
        final maxAllowed = effectiveHead + effectiveTail;

        if (runes.length > maxAllowed + 30) {
          final headStr = String.fromCharCodes(runes.sublist(0, effectiveHead));
          final tailStr = String.fromCharCodes(runes.sublist(runes.length - effectiveTail));
          final omittedCount = runes.length - maxAllowed;

          final compactedContent =
              '[中间执行结果已压缩，关键输出摘要: $headStr\n...[已智能省略 $omittedCount 字符]...\n$tailStr]';

          compactedList.add(msg.copyWith(content: compactedContent));
          compressionCount++;
        } else {
          compactedList.add(msg);
        }
      } else if (msg.role == 'assistant' &&
          msg.reasoningContent != null &&
          msg.reasoningContent!.length > 100) {
        // Fold intermediate thinking process to save tokens
        compactedList.add(msg.copyWith(reasoningContent: '[中间思考过程已压缩折叠]'));
      } else {
        compactedList.add(msg);
      }
    }

    final compactedTokens = estimateConversationTokens(
      compactedList,
      systemPrompt: systemPrompt,
      tools: tools,
    );

    final tokensSaved = (rawTokens - compactedTokens).clamp(0, effectiveBudget);

    return CompactedHistoryResult(
      messages: compactedList,
      tokensSaved: tokensSaved,
      compressionCount: compressionCount,
    );
  }

  // ==========================================
  // 3. Global Circuit Breaker
  // ==========================================

  /// Evaluates whether current conversation context trips the global token budget circuit breaker.
  CircuitBreakerEvaluation evaluateCircuitBreaker(
    List<ChatMessage> messages, {
    int? hardCap,
    double? tripRatio,
    double? warningRatio,
    String? systemPrompt,
    List<Map<String, dynamic>>? tools,
  }) {
    final effectiveCap = hardCap ?? config.maxContextTokens;
    final effectiveTripRatio = tripRatio ?? config.circuitBreakerThresholdRatio;
    final effectiveWarningRatio = warningRatio ?? config.compressionThresholdRatio;

    final estimatedTokens = estimateConversationTokens(
      messages,
      systemPrompt: systemPrompt,
      tools: tools,
    );

    final usageRatio = estimatedTokens / effectiveCap;

    if (usageRatio >= effectiveTripRatio) {
      final tripPercentage = (effectiveTripRatio * 100).toInt();
      return CircuitBreakerEvaluation(
        state: CircuitBreakerState.tripped,
        shouldStripTools: true,
        estimatedTokens: estimatedTokens,
        usageRatio: usageRatio,
        forcedConclusionPrompt:
            '【系统安全熔断】当前会话上下文已达 $estimatedTokens Tokens（已达上下文上限 $tripPercentage%）。'
            '请立即基于前面已获得的全部工具执行数据与分析，为用户输出完整、详尽的最终总结性回答，禁止再次调用任何工具。',
      );
    }

    if (usageRatio >= effectiveWarningRatio) {
      return CircuitBreakerEvaluation(
        state: CircuitBreakerState.warning,
        shouldStripTools: false,
        estimatedTokens: estimatedTokens,
        usageRatio: usageRatio,
      );
    }

    return CircuitBreakerEvaluation(
      state: CircuitBreakerState.normal,
      shouldStripTools: false,
      estimatedTokens: estimatedTokens,
      usageRatio: usageRatio,
    );
  }

  // ==========================================
  // 4. Combined Evaluation & Compaction Pipeline
  // ==========================================

  /// Full pre-flight evaluation pipeline called before issuing completions:
  /// 1. Estimates raw tokens.
  /// 2. If <= compressionThreshold, passes normally.
  /// 3. If > compressionThreshold, executes sliding window compaction.
  /// 4. If still > circuitBreakerThreshold after compaction, trips circuit breaker.
  BudgetEvaluationResult evaluateAndCompact({
    required List<ChatMessage> messages,
    String? systemPrompt,
    List<Map<String, dynamic>>? tools,
    int currentRound = 0,
  }) {
    final rawTokens = estimateConversationTokens(
      messages,
      systemPrompt: systemPrompt,
      tools: tools,
    );

    final safeContextLimit = config.maxContextTokens - config.maxOutputTokens;
    final effectiveLimit = safeContextLimit > 0 ? safeContextLimit : config.maxContextTokens;

    final compressionThreshold = (effectiveLimit * config.compressionThresholdRatio).round();
    final circuitBreakerThreshold = (effectiveLimit * config.circuitBreakerThresholdRatio).round();

    // 1. Safe budget range -> Pass through
    if (rawTokens <= compressionThreshold) {
      return BudgetEvaluationResult(
        status: BudgetActionStatus.normal,
        estimatedPromptTokens: rawTokens,
        maxContextTokens: config.maxContextTokens,
        usageRatio: rawTokens / config.maxContextTokens,
        effectiveMessages: messages,
      );
    }

    // 2. Beyond compression threshold -> Apply sliding window compaction
    final compaction = compactIntermediateToolHistory(
      messages,
      budgetCap: config.maxContextTokens,
      keepLastNRounds: config.preserveRecentRounds,
      headRunes: config.compressedHeadRunes,
      tailRunes: config.compressedTailRunes,
      systemPrompt: systemPrompt,
      tools: tools,
    );

    final compactedTokens = estimateConversationTokens(
      compaction.messages,
      systemPrompt: systemPrompt,
      tools: tools,
    );

    final ratioAfterCompaction = compactedTokens / config.maxContextTokens;

    // 3. Still exceeds circuit breaker threshold -> Trip circuit breaker
    if (compactedTokens > circuitBreakerThreshold) {
      return BudgetEvaluationResult(
        status: BudgetActionStatus.circuitBreakerTriggered,
        estimatedPromptTokens: compactedTokens,
        maxContextTokens: config.maxContextTokens,
        usageRatio: ratioAfterCompaction,
        effectiveMessages: compaction.messages,
        tokensSavedByCompression: compaction.tokensSaved,
        compressionCount: compaction.compressionCount,
        forcedConclusionPrompt:
            '【系统安全熔断】当前会话上下文已达 $compactedTokens Tokens（超出模型安全上限）。'
            '请立即基于前面已获得的全部工具执行数据与分析，为用户输出完整、详尽的最终总结性回答，禁止再次调用任何工具。',
      );
    }

    // 4. Compaction succeeded in keeping token usage within limits
    return BudgetEvaluationResult(
      status: BudgetActionStatus.compressionApplied,
      estimatedPromptTokens: compactedTokens,
      maxContextTokens: config.maxContextTokens,
      usageRatio: ratioAfterCompaction,
      effectiveMessages: compaction.messages,
      tokensSavedByCompression: compaction.tokensSaved,
      compressionCount: compaction.compressionCount,
    );
  }
}
