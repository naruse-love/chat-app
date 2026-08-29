# Milestone 23.3 Architecture & Design Report: AgentLoopGuard

## 1. Executive Summary

Milestone 23.3 introduces **`AgentLoopGuard`** (`lib/services/agent_loop_guard.dart`), a high-performance, deterministic invocation safety layer for the AI Agent tool execution pipeline. It defends against infinite loops, oscillation traps (such as ping-ponging between tools `A -> B -> A -> B`), duplicate argument spamming, and unbounded round exhaustion.

This document establishes the formal architecture, canonical signature algorithms, cycle detection mathematics, Chinese prompt templates, and comprehensive test specifications for `lib/services/agent_loop_guard.dart` and `test/services/agent_loop_guard_test.dart`.

---

## 2. Architecture & Pipeline Integration

### 2.1 Placement in the System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       AgentService                          │
│                                                             │
│   1. Receives LLM streaming chunks                         │
│   2. Parses tool_calls (JSON or pseudo-XML)                 │
│   3. Evaluates tool calls against AgentLoopGuard            │
│      ├── Allowed ──> ToolRegistry.execute(...)              │
│      └── Blocked ──> Strip tools & inject Conclusion Prompt │
└──────────────┬──────────────────────────────▲───────────────┘
               │                              │
               ▼                              │ LoopCheckResult
┌──────────────────────────────────────────┐  │ (allowed / blocked)
│             AgentLoopGuard               ├──┘
│                                          │
│  ├── ToolCallSignature (Canonical JSON + MD5)
│  ├── Consecutive Duplicate Detector (>=3)
│  ├── Oscillation & Cycle Detector (P=2, 3)
│  ├── Max Tool Rounds Guard (Default 8)
│  └── Forced Conclusion Prompt Provider   │
└──────────────────────────────────────────┘
```

### 2.2 Contract Definitions

```dart
/// Result status of loop evaluation
enum LoopCheckStatus {
  allowed,
  consecutiveDuplicate,
  oscillation,
  maxRoundsReached,
}

/// Evaluation verdict containing status and diagnostics
class LoopCheckResult {
  final LoopCheckStatus status;
  final String? reason;
  final int currentRound;
  final int maxRounds;
  final String? detectedPattern;
  final ToolCallSignature? triggeringSignature;
  final int? cyclePeriod;
  ...
}

/// Invocation signature of a tool call
class ToolCallSignature {
  final String toolName;
  final Map<String, dynamic> rawArguments;
  final String canonicalJson;
  final String hash;
  ...
}

/// Main Guard Engine
class AgentLoopGuard {
  final int maxToolRounds;             // Default: 8
  final int duplicateThreshold;        // Default: 3
  final int oscillationHistoryDepth;   // Default: 10
  final List<int> cyclePeriodsToCheck; // Default: [2, 3]
  final int minCycleRepetitions;       // Default: 2
  ...
}
```

---

## 3. Canonical Normalization & Signature Algorithm

### 3.1 Motivation & Requirements
When LLMs generate tool call arguments, JSON key ordering is non-deterministic. For example:
- Call 1: `{"query": "Flutter", "limit": 10}`
- Call 2: `{"limit": 10, "query": "Flutter"}`

Both calls are semantically identical. A naive string comparison would treat them as distinct, allowing the agent to enter an infinite loop. `ToolCallSignature` solves this by recursively sorting all dictionary keys before generating a canonical JSON string and computing a standard 32-character hexadecimal MD5 digest.

### 3.2 Canonicalization Specification
1. **Map Normalization**:
   - Convert all map keys to `String`.
   - Sort keys in standard lexicographical order (`k1.compareTo(k2)`).
   - Recursively canonicalize all child values.
2. **List Normalization**:
   - Preserve item sequence.
   - Recursively canonicalize each element inside the list.
3. **Primitive Handling**:
   - `int`, `double`, `bool`, `String`, `null` are preserved.
   - Custom non-primitive objects are mapped via their JSON representation or `.toString()`.
4. **Canonical JSON Serialization**:
   - `jsonEncode(canonicalizedMap)` produces a unique, deterministic string representation.

### 3.3 Pure Dart MD5 Implementation
To ensure zero external dependencies and guaranteed consistency across all platforms (Android, iOS, Web, Desktop), `AgentLoopGuard` includes a self-contained, high-speed pure Dart MD5 implementation:
- RFC 1321 compliant 64-round transformation with standard constants $T[1..64]$.
- Standard initial vector: $A = 0x67452301, B = 0xefcdab89, C = 0x98badcfe, D = 0x10325476$.
- Produces exact standard hex digests (e.g. `d41d8cd98f00b204e9800998ecf8427e` for empty input).

---

## 4. Detection Algorithms

### 4.1 Consecutive Duplicate Detection
- **Goal**: Detect when an agent calls the exact same tool with the exact same canonical arguments $\ge N$ times in a row (default $N = 3$).
- **Algorithm**:
  1. Let proposed call signature be $S_{new}$.
  2. Inspect the tail of recorded history $H = [S_1, S_2, \dots, S_m]$.
  3. Count consecutive trailing elements equal to $S_{new}$:
     $$\text{count} = 1 + \sum_{k=0}^{m-1} \mathbb{I}(S_{m-k} == S_{new})$$
  4. If $\text{count} \ge \text{duplicateThreshold}$, return `LoopCheckResult.consecutiveDuplicate(...)`.

### 4.2 Oscillation & Periodic Cycle Detection
- **Goal**: Detect repeating cycles of tool calls (such as $A \to B \to A \to B$ of period 2, or $A \to B \to C \to A \to B \to C$ of period 3).
- **Algorithm**:
  1. Construct hypothetical history: $W = [S_1, S_2, \dots, S_m, S_{new}]$.
  2. Let window length be $L = \min(W.\text{length}, \text{oscillationHistoryDepth})$. Take the suffix $W_{suffix}$ of length $L$.
  3. For each period $p \in \text{cyclePeriodsToCheck}$ (e.g., $p = 2, 3$):
     - Minimum required length $K = p \times \text{minCycleRepetitions}$ (for $p=2$, $K=4$; for $p=3$, $K=6$).
     - If $L < K$, continue to next period.
     - Take the last $K$ elements: $C = W_{suffix}[L - K \dots L - 1]$.
     - **Non-degeneracy Check**: Check that the first $p$ elements of $C$ are not all identical (i.e. $|\{C[0], \dots, C[p-1]\}| > 1$). If they are all identical, this is a consecutive duplicate (period 1), not a multi-item oscillation.
     - **Periodic Match Check**: For each index $i \in [0, K - p - 1]$:
       $$\text{if } C[i] \neq C[i + p] \implies \text{break (no match)}$$
     - If all $i$ match, an oscillation of period $p$ is detected!
     - Format the cycle pattern (e.g. `math_eval -> weather_query -> math_eval -> weather_query`) and return `LoopCheckResult.oscillation(...)`.

### 4.3 Maximum Rounds Guard
- **Goal**: Enforce a hard ceiling on total tool execution rounds per user turn (default $\text{maxToolRounds} = 8$).
- **Rule**: If $\text{currentRound} \ge \text{maxToolRounds}$, return `LoopCheckResult.maxRoundsReached(...)`.
- **Tool Stripping**: `shouldStripTools(currentRound)` returns `true` whenever $\text{currentRound} \ge \text{maxToolRounds} - 1$ or whenever a loop verdict has been triggered.

---

## 5. Chinese Forced Conclusion Prompt Templates

In accordance with AGENTS.md Rule 5 (全中文用户界面与友好提示), `AgentLoopGuard` provides localized prompts tailored to the specific termination reason:

```dart
String getForcedConclusionPrompt({LoopCheckResult? verdict}) {
  final status = verdict?.status ?? _lastVerdict?.status;
  switch (status) {
    case LoopCheckStatus.consecutiveDuplicate:
      return '检测到连续多次使用相同参数调用同一工具。请根据当前已获取的全部工具执行结果与上下文信息，直接给出最终的综合回答，绝对不要再尝试重复调用工具。';
    case LoopCheckStatus.oscillation:
      return '检测到工具间的循环振荡调用（例如交替重复调用不同工具）。请立即停止调用任何工具，根据现有收集到的全部信息直接给出最终分析与解答。';
    case LoopCheckStatus.maxRoundsReached:
    default:
      return '已达到工具调用轮次上限（最大 8 轮）。请根据上述已获取的所有搜索结果、计算数据和上下文，直接给出最终的总结回答，绝对不要再尝试使用任何工具或输出形如 <tool_call> 的工具调用格式。';
  }
}
```

---

## 6. Comprehensive Test Specifications (24 Test Cases)

The unit test suite `test/services/agent_loop_guard_test.dart` covers 4 test groups and 24 granular scenarios:

### Group 1: ToolCallSignature & Normalization (6 Tests)
- **T1.1**: Deterministic map key sorting for flat parameter maps (`{"b": 2, "a": 1}` produces identical signature as `{"a": 1, "b": 2}`).
- **T1.2**: Deep recursive nested map sorting (`{"meta": {"z": 9, "y": 8}, "query": "test"}`).
- **T1.3**: Preservation of list ordering with internal element canonicalization.
- **T1.4**: Pure Dart MD5 hash validation against known cryptographic test vectors.
- **T1.5**: Signature equality (`==`) and `hashCode` consistency in Sets and Maps.
- **T1.6**: Different tool names or differing argument values yield distinct signatures and hashes.

### Group 2: Consecutive Duplicate Detection (6 Tests)
- **T2.1**: 1st tool call is allowed (`duplicateThreshold = 3`).
- **T2.2**: 2nd consecutive identical tool call is allowed.
- **T2.3**: 3rd consecutive identical tool call is blocked with `consecutiveDuplicate` status.
- **T2.4**: Sequence interrupted by a different call (`A -> A -> B -> A`) resets consecutive count and is allowed.
- **T2.5**: Different parameter key insertion order does NOT evade duplicate detection.
- **T2.6**: Custom `duplicateThreshold = 2` triggers block on the 2nd identical call.

### Group 3: Oscillation & Cycle Detection (6 Tests)
- **T3.1**: Period 2 oscillation (`A -> B -> A -> B`) triggers `oscillation` verdict on 4th call.
- **T3.2**: Period 3 oscillation (`A -> B -> C -> A -> B -> C`) triggers `oscillation` verdict on 6th call.
- **T3.3**: Same tool alternating different parameters (`search(q1) -> search(q2) -> search(q1) -> search(q2)`) triggers oscillation.
- **T3.4**: Prefixed oscillation (`X -> Y -> A -> B -> A -> B`) correctly identifies the cyclic suffix in history.
- **T3.5**: Non-cyclic progressive calls (`A -> B -> C -> D -> A`) are allowed without false positives.
- **T3.6**: Pure consecutive duplicates (`A -> A -> A -> A`) are NOT misclassified as period 2 oscillation.

### Group 4: Lifecycle, Max Rounds & Tool Stripping (6 Tests)
- **T4.1**: Reaching `maxToolRounds` (e.g. round 8) yields `maxRoundsReached` result.
- **T4.2**: `shouldStripTools(currentRound)` returns true when `currentRound >= maxToolRounds - 1`.
- **T4.3**: `shouldStripTools` returns true immediately after a loop/duplicate is detected regardless of round.
- **T4.4**: `getForcedConclusionPrompt` generates specific Chinese text for duplicate, oscillation, and max rounds.
- **T4.5**: `reset()` fully purges history and restores pristine initial state.
- **T4.6**: `recordAndCheck` atomic execution maintains consistency across multi-step invocations.

---

## 7. Implementation Code Blueprints

### 7.1 Source Code Blueprint (`lib/services/agent_loop_guard.dart`)

```dart
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
  bool get isConsecutiveDuplicate => status == LoopCheckStatus.consecutiveDuplicate;
  bool get isOscillation => status == LoopCheckStatus.oscillation;
  bool get isMaxRoundsReached => status == LoopCheckStatus.maxRoundsReached;

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

  factory ToolCallSignature.create(String toolName, Map<String, dynamic> arguments) {
    final canonicalMap = canonicalizeValue(arguments) as Map<String, dynamic>;
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
    } else {
      return value;
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

/// Pure Dart MD5 implementation producing 32-character lowercase hex string.
String computeMd5Hex(String input) {
  final bytes = utf8.encode(input);
  final bitLength = bytes.length * 8;

  final paddedLength = ((bytes.length + 8) ~/ 64 + 1) * 64;
  final padded = Uint8List(paddedLength);
  padded.setRange(0, bytes.length, bytes);
  padded[bytes.length] = 0x80;

  final byteData = ByteData.view(padded.buffer);
  byteData.setUint32(paddedLength - 8, bitLength & 0xFFFFFFFF, Endian.little);
  byteData.setUint32(paddedLength - 4, (bitLength >> 32) & 0xFFFFFFFF, Endian.little);

  int a0 = 0x67452301;
  int b0 = 0xefcdab89;
  int c0 = 0x98badcfe;
  int d0 = 0x10325476;

  final s = <int>[
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  final k = <int>[
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
    final m = List<int>.generate(16, (i) => byteData.getUint32(offset + i * 4, Endian.little));

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
      final rot = a + f + k[i] + m[g];
      b = (b + ((rot << s[i]) | ((rot & 0xFFFFFFFF) >> (32 - s[i])))) & 0xFFFFFFFF;
      a = temp;
    }

    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  String toHex(int val) {
    final bd = ByteData(4)..setUint32(0, val, Endian.little);
    return List.generate(4, (i) => bd.getUint8(i).toRadixString(16).padLeft(2, '0')).join();
  }

  return '${toHex(a0)}${toHex(b0)}${toHex(c0)}${toHex(d0)}';
}

/// Agent invocation safety guard defending against infinite loops, oscillations, and round exhaustion.
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
    this.oscillationHistoryDepth = 10,
    this.cyclePeriodsToCheck = const [2, 3],
    this.minCycleRepetitions = 2,
  });

  List<ToolCallSignature> get history => List.unmodifiable(_history);
  int get callCount => _history.length;
  LoopCheckResult? get lastVerdict => _lastVerdict;
  bool get hasTriggeredLoop => _lastVerdict != null && !_lastVerdict!.isAllowed;

  ToolCallSignature createSignature(String toolName, Map<String, dynamic> arguments) {
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

  LoopCheckResult? _detectOscillation(List<ToolCallSignature> fullHistory, int round) {
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
      final distinctCount = candidatePattern.map((s) => s.hash).toSet().length;
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
    Map<String, dynamic> arguments, {
    int? currentRound,
  }) {
    final verdict = checkBeforeExecution(toolName, arguments, currentRound: currentRound);
    _lastVerdict = verdict;
    _history.add(createSignature(toolName, arguments));
    return verdict;
  }

  bool shouldStripTools(int currentRound) {
    if (hasTriggeredLoop) return true;
    if (currentRound >= maxToolRounds - 1) return true;
    return false;
  }

  String getForcedConclusionPrompt({LoopCheckResult? verdict}) {
    final status = verdict?.status ?? _lastVerdict?.status;
    switch (status) {
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
```

---

## 8. Verification Plan & Quality Criteria

1. **Static Analysis**: `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` must output `No issues found!`.
2. **Test Suite**: `D:\work\flutter-sdk\flutter\bin\flutter.bat test` must pass all existing tests (296 tests) plus the 24 new unit tests ($\ge 320$ total tests, 0 failures).
3. **Execution Time**: Pure Dart algorithmic guard execution overhead per tool call $< 0.1\text{ ms}$.
