import 'dart:convert';
import 'dart:typed_data';

/// Result status of loop guard evaluation.
enum LoopCheckStatus {
  /// Invocation is safe and allowed to proceed.
  allowed,

  /// Same tool invoked with identical arguments consecutively >= threshold times.
  consecutiveDuplicate,

  /// Repetitive periodic cycle (e.g. A -> B -> A -> B or A -> B -> C -> A -> B -> C) detected.
  oscillation,

  /// Tool execution rounds reached the configured maximum limit.
  maxRoundsReached,
}

/// Evaluation verdict for a tool call check.
class LoopCheckResult {
  final LoopCheckStatus status;
  final String? reason;
  final int currentRound;
  final int maxRounds;
  final String? detectedPattern;
  final ToolCallSignature? triggeringSignature;
  final int? cyclePeriod;

  const LoopCheckResult({
    required this.status,
    this.reason,
    required this.currentRound,
    required this.maxRounds,
    this.detectedPattern,
    this.triggeringSignature,
    this.cyclePeriod,
  });

  bool get isAllowed => status == LoopCheckStatus.allowed;
  bool get isBlocked => !isAllowed;
  bool get isTerminated => isBlocked;
  bool get isConsecutiveDuplicate =>
      status == LoopCheckStatus.consecutiveDuplicate;
  bool get isOscillation => status == LoopCheckStatus.oscillation;
  bool get isMaxRoundsReached => status == LoopCheckStatus.maxRoundsReached;

  String? get toolName => triggeringSignature?.toolName;
  ToolCallSignature? get signature => triggeringSignature;
  int? get cycleLength => cyclePeriod;

  factory LoopCheckResult.allowed({
    int currentRound = 0,
    int maxRounds = 8,
  }) {
    return LoopCheckResult(
      status: LoopCheckStatus.allowed,
      currentRound: currentRound,
      maxRounds: maxRounds,
    );
  }

  factory LoopCheckResult.consecutiveDuplicate({
    required ToolCallSignature signature,
    required int count,
    int currentRound = 0,
    int maxRounds = 8,
  }) {
    return LoopCheckResult(
      status: LoopCheckStatus.consecutiveDuplicate,
      reason: '连续 $count 次使用相同参数调用工具 [${signature.toolName}]',
      detectedPattern: '${signature.toolName} x $count',
      triggeringSignature: signature,
      currentRound: currentRound,
      maxRounds: maxRounds,
    );
  }

  factory LoopCheckResult.oscillation({
    required List<ToolCallSignature> cycle,
    required int period,
    required int repetitions,
    int currentRound = 0,
    int maxRounds = 8,
  }) {
    final pattern = cycle.map((s) => s.toolName).join(' -> ');
    return LoopCheckResult(
      status: LoopCheckStatus.oscillation,
      reason: '检测到周期为 $period 的工具循环振荡调用 ($pattern)',
      detectedPattern: pattern,
      triggeringSignature: cycle.isNotEmpty ? cycle.last : null,
      cyclePeriod: period,
      currentRound: currentRound,
      maxRounds: maxRounds,
    );
  }

  factory LoopCheckResult.maxRoundsReached({
    required int currentRound,
    required int maxRounds,
  }) {
    return LoopCheckResult(
      status: LoopCheckStatus.maxRoundsReached,
      reason: '达到工具调用轮次上限 ($currentRound / $maxRounds 轮)',
      currentRound: currentRound,
      maxRounds: maxRounds,
    );
  }

  @override
  String toString() =>
      'LoopCheckResult(status: $status, reason: $reason, round: $currentRound/$maxRounds)';
}

/// Represents the normalized, canonical signature of a single tool invocation.
class ToolCallSignature {
  final String toolName;
  final Map<String, dynamic> rawArguments;
  final String canonicalJson;
  final String hash;

  ToolCallSignature._({
    required this.toolName,
    required this.rawArguments,
    required this.canonicalJson,
    required this.hash,
  });

  factory ToolCallSignature.create(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final canonicalMap =
        canonicalizeValue(arguments) as Map<String, dynamic>;
    final canonicalJson = jsonEncode(canonicalMap);
    final inputToHash = '$toolName:$canonicalJson';
    final hash = computeMd5Hex(inputToHash);

    return ToolCallSignature._(
      toolName: toolName,
      rawArguments: arguments,
      canonicalJson: canonicalJson,
      hash: hash,
    );
  }

  factory ToolCallSignature(
    String toolName,
    Map<String, dynamic> arguments,
  ) =>
      ToolCallSignature.create(toolName, arguments);

  /// Recursively normalizes Maps (sorted keys), Lists, and primitives.
  static dynamic canonicalizeValue(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final result = <String, dynamic>{};
      for (final key in sortedKeys) {
        result[key] = canonicalizeValue(value[key]);
      }
      return result;
    } else if (value is List) {
      return value.map((item) => canonicalizeValue(item)).toList();
    } else if (value is num || value is bool || value is String || value == null) {
      return value;
    } else {
      try {
        // Handle custom objects with toJson
        final dynamic jsonVal = (value as dynamic).toJson();
        return canonicalizeValue(jsonVal);
      } catch (_) {
        return value.toString();
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCallSignature &&
          runtimeType == other.runtimeType &&
          toolName == other.toolName &&
          canonicalJson == other.canonicalJson;

  @override
  int get hashCode => Object.hash(toolName, canonicalJson);

  @override
  String toString() => '$toolName($canonicalJson)';
}

/// Pure Dart MD5 implementation producing a 32-character lowercase hex digest (RFC 1321).
String computeMd5Hex(String input) {
  final bytes = utf8.encode(input);
  final bitLength = bytes.length * 8;

  final paddedLength = ((bytes.length + 8) ~/ 64 + 1) * 64;
  final padded = Uint8List(paddedLength);
  padded.setRange(0, bytes.length, bytes);
  padded[bytes.length] = 0x80;

  final byteData = ByteData.view(padded.buffer);
  byteData.setUint32(paddedLength - 8, bitLength & 0xFFFFFFFF, Endian.little);
  byteData.setUint32(
      paddedLength - 4, (bitLength >> 32) & 0xFFFFFFFF, Endian.little);

  int a0 = 0x67452301;
  int b0 = 0xefcdab89;
  int c0 = 0x98badcfe;
  int d0 = 0x10325476;

  const s = <int>[
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  const k = <int>[
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];

  for (var offset = 0; offset < paddedLength; offset += 64) {
    final m = List<int>.generate(
      16,
      (i) => byteData.getUint32(offset + i * 4, Endian.little),
    );

    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;

    for (var i = 0; i < 64; i++) {
      int f, g;
      if (i < 16) {
        f = (b & c) | ((~b) & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | ((~d) & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d));
        g = (7 * i) % 16;
      }

      final temp = d;
      d = c;
      c = b;
      final rot = (a + f + k[i] + m[g]) & 0xFFFFFFFF;
      b = (b +
              (((rot << s[i]) & 0xFFFFFFFF) |
                  ((rot & 0xFFFFFFFF) >> (32 - s[i])))) &
          0xFFFFFFFF;
      a = temp;
    }

    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  String toHex(int val) {
    final bd = ByteData(4)..setUint32(0, val, Endian.little);
    return List.generate(
      4,
      (i) => bd.getUint8(i).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  return '${toHex(a0)}${toHex(b0)}${toHex(c0)}${toHex(d0)}';
}

/// Invocation safety guard defending against infinite loops, oscillations, and round exhaustion.
class AgentLoopGuard {
  final int maxToolRounds;
  final int duplicateThreshold;
  final int oscillationHistoryDepth;
  final List<int> cyclePeriodsToCheck;
  final int minCycleRepetitions;

  final List<ToolCallSignature> _history = [];
  LoopCheckResult? _lastVerdict;

  AgentLoopGuard({
    this.maxToolRounds = 8,
    this.duplicateThreshold = 3,
    this.oscillationHistoryDepth = 12,
    this.cyclePeriodsToCheck = const [2, 3],
    this.minCycleRepetitions = 2,
  });

  List<ToolCallSignature> get history => List.unmodifiable(_history);
  int get callCount => _history.length;
  LoopCheckResult? get lastVerdict => _lastVerdict;
  bool get hasTriggeredLoop => _lastVerdict != null && !_lastVerdict!.isAllowed;
  String? get lastTerminationReason => _lastVerdict?.reason;

  ToolCallSignature createSignature(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    return ToolCallSignature.create(toolName, arguments);
  }

  LoopCheckResult checkBeforeExecution(
    String toolName,
    Map<String, dynamic> arguments, {
    int? currentRound,
  }) {
    final round = currentRound ?? _history.length;
    if (round >= maxToolRounds) {
      return LoopCheckResult.maxRoundsReached(
        currentRound: round,
        maxRounds: maxToolRounds,
      );
    }

    final sig = createSignature(toolName, arguments);

    // 1. Consecutive Duplicate Detection
    int trailingMatches = 0;
    for (int i = _history.length - 1; i >= 0; i--) {
      if (_history[i] == sig) {
        trailingMatches++;
      } else {
        break;
      }
    }
    if (trailingMatches + 1 >= duplicateThreshold) {
      return LoopCheckResult.consecutiveDuplicate(
        signature: sig,
        count: trailingMatches + 1,
        currentRound: round,
        maxRounds: maxToolRounds,
      );
    }

    // 2. Oscillation & Cycle Detection
    final tempHistory = [..._history, sig];
    final oscillationResult = _detectOscillation(tempHistory, round);
    if (oscillationResult != null) {
      return oscillationResult;
    }

    return LoopCheckResult.allowed(
      currentRound: round,
      maxRounds: maxToolRounds,
    );
  }

  LoopCheckResult checkNextCall(
    String toolName,
    Map<String, dynamic> arguments, [
    int? currentRound,
  ]) =>
      checkBeforeExecution(toolName, arguments, currentRound: currentRound);

  LoopCheckResult? _detectOscillation(
    List<ToolCallSignature> fullHistory,
    int round,
  ) {
    final windowLen = fullHistory.length > oscillationHistoryDepth
        ? oscillationHistoryDepth
        : fullHistory.length;
    final window = fullHistory.sublist(fullHistory.length - windowLen);

    for (final period in cyclePeriodsToCheck) {
      final minRequiredLen = period * minCycleRepetitions;
      if (window.length < minRequiredLen) {
        continue;
      }

      final sub = window.sublist(window.length - minRequiredLen);
      final candidatePattern = sub.take(period).toList();

      // Ensure pattern is non-degenerate (not all identical items)
      final distinctCount =
          candidatePattern.map((s) => s.hash).toSet().length;
      if (distinctCount <= 1) {
        continue;
      }

      bool isCycle = true;
      for (int i = 0; i < minRequiredLen - period; i++) {
        if (sub[i] != sub[i + period]) {
          isCycle = false;
          break;
        }
      }

      if (isCycle) {
        return LoopCheckResult.oscillation(
          cycle: candidatePattern,
          period: period,
          repetitions: minCycleRepetitions,
          currentRound: round,
          maxRounds: maxToolRounds,
        );
      }
    }
    return null;
  }

  void recordToolCall(String toolName, Map<String, dynamic> arguments) {
    _history.add(createSignature(toolName, arguments));
  }

  LoopCheckResult recordAndCheck(
    String toolName,
    Map<String, dynamic> arguments, [
    int? currentRound,
  ]) {
    final verdict =
        checkBeforeExecution(toolName, arguments, currentRound: currentRound);
    _lastVerdict = verdict;
    _history.add(createSignature(toolName, arguments));
    return verdict;
  }

  bool shouldStripTools(int currentRound) {
    if (hasTriggeredLoop) return true;
    if (currentRound >= maxToolRounds - 1) return true;
    return false;
  }

  bool shouldTerminate(int currentRound) => shouldStripTools(currentRound);

  String getTerminationReason() => _lastVerdict?.reason ?? '正常执行';

  String getForcedConclusionPrompt({
    LoopCheckResult? verdict,
    LoopCheckStatus? status,
    String? reason,
  }) {
    final effectiveStatus = status ?? verdict?.status ?? _lastVerdict?.status;
    switch (effectiveStatus) {
      case LoopCheckStatus.consecutiveDuplicate:
        return '检测到连续多次使用相同参数调用同一工具。请根据当前已获取的全部工具执行结果与上下文信息，直接给出最终的综合回答，绝对不要再尝试重复调用工具。';
      case LoopCheckStatus.oscillation:
        return '检测到工具间的循环振荡调用（例如交替重复调用不同工具）。请立即停止调用任何工具，根据现有收集到的全部信息直接给出最终分析与解答。';
      case LoopCheckStatus.maxRoundsReached:
      default:
        return '已达到工具调用轮次上限（最大 $maxToolRounds 轮）。请根据上述已获取的所有搜索结果、计算数据和上下文，直接给出最终的总结回答，绝对不要再尝试使用任何工具或输出形如 <tool_call> 的工具调用格式。';
    }
  }

  void reset() {
    _history.clear();
    _lastVerdict = null;
  }
}
