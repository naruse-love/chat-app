import 'dart:convert';
import 'package:chat/services/agent_loop_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test helper class with toJson
class _MockJsonSerializable {
  final String key;
  final int value;
  const _MockJsonSerializable(this.key, this.value);
  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}

/// Test helper class without toJson
class _MockPlainObject {
  final String label;
  const _MockPlainObject(this.label);
  @override
  String toString() => 'MockPlainObject($label)';
}

void main() {
  group('Challenger 2 — Empirical Stress Testing for AgentLoopGuard', () {
    // ========================================================================
    // Group 1: RFC 1321 Standard MD5 Vectors & Byte Boundary Stress
    // ========================================================================
    group('Group 1: RFC 1321 Standard MD5 Vectors & Byte Boundary Stress', () {
      test('C2.1.1: Official RFC 1321 Section A.5 standard 7 test vectors', () {
        // 1. MD5 ("") = d41d8cd98f00b204e9800998ecf8427e
        expect(computeMd5Hex(''), equals('d41d8cd98f00b204e9800998ecf8427e'));

        // 2. MD5 ("a") = 0cc175b9c0f1b6a831c399e269772661
        expect(computeMd5Hex('a'), equals('0cc175b9c0f1b6a831c399e269772661'));

        // 3. MD5 ("abc") = 900150983cd24fb0d6963f7d28e17f72
        expect(computeMd5Hex('abc'), equals('900150983cd24fb0d6963f7d28e17f72'));

        // 4. MD5 ("message digest") = f96b697d7cb7938d525a2f31aaf161d0
        expect(computeMd5Hex('message digest'), equals('f96b697d7cb7938d525a2f31aaf161d0'));

        // 5. MD5 ("abcdefghijklmnopqrstuvwxyz") = c3fcd3d76192e4007dfb496cca67e13b
        expect(computeMd5Hex('abcdefghijklmnopqrstuvwxyz'), equals('c3fcd3d76192e4007dfb496cca67e13b'));

        // 6. MD5 ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") = d174ab98d277d9f5a5611c2c9f419d9f
        expect(
          computeMd5Hex('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'),
          equals('d174ab98d277d9f5a5611c2c9f419d9f'),
        );

        // 7. MD5 ("12345678901234567890123456789012345678901234567890123456789012345678901234567890") = 57edf4a22be3c955ac49da2e2107b67a
        expect(
          computeMd5Hex('12345678901234567890123456789012345678901234567890123456789012345678901234567890'),
          equals('57edf4a22be3c955ac49da2e2107b67a'),
        );
      });

      test('C2.1.2: MD5 buffer padding boundary cases (55, 56, 63, 64, 119, 120, 128 bytes)', () {
        // Reference standard MD5 digests for known repeating characters:
        // 'A' * 55 (55 bytes: exact 1-block single-boundary fit)
        expect(computeMd5Hex('A' * 55), equals('e38a93ffe074a99b3fed47dfbe37db21'));

        // 'A' * 56 (56 bytes: spills padding over to 2nd 64-byte block)
        expect(computeMd5Hex('A' * 56), equals('a2f3e2024931bd470555002aa5ccc010'));

        // 'A' * 63
        expect(computeMd5Hex('A' * 63), equals('5f1c4bb2970471a5c75b7ba1dc9ee3ed'));

        // 'A' * 64 (exact 64-byte boundary)
        expect(computeMd5Hex('A' * 64), equals('d289a97565bc2d27ac8b8545a5ddba45'));

        // 'A' * 119 (119 bytes: 2nd block boundary fit)
        expect(computeMd5Hex('A' * 119), equals('4f428c9ec478ab46260c143f95b68bd6'));

        // 'A' * 120 (120 bytes: spills over to 3rd 64-byte block)
        expect(computeMd5Hex('A' * 120), equals('2fc9840470860d0d8e67a2207d15c4c9'));

        // 'A' * 128 (exact 2 full 64-byte blocks)
        expect(computeMd5Hex('A' * 128), equals('af35b0d348e5162036e183339d385b0c'));
      });

      test('C2.1.3: Multi-byte UTF-8 characters and multi-language strings', () {
        // UTF-8 Chinese: '你好，世界！' (18 bytes in UTF-8)
        final zhUtf8 = utf8.encode('你好，世界！');
        expect(zhUtf8.length, equals(18));
        expect(computeMd5Hex('你好，世界！'), equals('5082079d92a8ef985f59e001d445ff20'));

        // 4-byte UTF-8 Emoji: '🤖🔥' (8 bytes in UTF-8)
        expect(computeMd5Hex('🤖🔥'), equals('2fb85eaddba2b8fb6ad88e6f21447a15'));

        // Complex mixed script
        const mixed = 'Tool: math_eval; args: {"expr":"2+2", "desc":"测试中文与Emoji🚀"}';
        final hash = computeMd5Hex(mixed);
        expect(hash.length, equals(32));
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(hash), isTrue);
      });

      test('C2.1.4: Large text payload (25,000 repetitions ~1MB) MD5 performance & integrity', () {
        final text = 'AgentLoopGuardLargeDataTestVector' * 25000; // ~825KB
        final stopwatch = Stopwatch()..start();
        final digest = computeMd5Hex(text);
        stopwatch.stop();

        expect(digest.length, equals(32));
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(digest), isTrue);
        // Execution must complete in under 500ms
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
      });
    });

    // ========================================================================
    // Group 2: Max Tool Round Limits (Default 8, Custom, Boundaries)
    // ========================================================================
    group('Group 2: Max Tool Round Limits & Boundaries', () {
      test('C2.2.1: Default maxToolRounds = 8 allows exactly rounds 0..7 and blocks round 8', () {
        final guard = AgentLoopGuard(); // default maxToolRounds = 8
        expect(guard.maxToolRounds, equals(8));

        // Rounds 0 through 7 (8 unique invocations)
        for (int r = 0; r < 8; r++) {
          final verdict = guard.checkBeforeExecution('tool_$r', {'index': r}, currentRound: r);
          expect(verdict.isAllowed, isTrue, reason: 'Round $r should be allowed');
          expect(verdict.isBlocked, isFalse);
          expect(verdict.status, equals(LoopCheckStatus.allowed));
          expect(verdict.currentRound, equals(r));
          expect(verdict.maxRounds, equals(8));
        }

        // Round 8 (the 9th invocation) must be blocked with maxRoundsReached
        final blockedVerdict = guard.checkBeforeExecution('tool_8', {'index': 8}, currentRound: 8);
        expect(blockedVerdict.isBlocked, isTrue);
        expect(blockedVerdict.isAllowed, isFalse);
        expect(blockedVerdict.isMaxRoundsReached, isTrue);
        expect(blockedVerdict.status, equals(LoopCheckStatus.maxRoundsReached));
        expect(blockedVerdict.currentRound, equals(8));
        expect(blockedVerdict.maxRounds, equals(8));
        expect(blockedVerdict.reason, equals('达到工具调用轮次上限 (8 / 8 轮)'));

        // Round 9 (beyond max) is also blocked
        final verdict9 = guard.checkBeforeExecution('tool_9', {'index': 9}, currentRound: 9);
        expect(verdict9.isBlocked, isTrue);
        expect(verdict9.isMaxRoundsReached, isTrue);
        expect(verdict9.reason, equals('达到工具调用轮次上限 (9 / 8 轮)'));
      });

      test('C2.2.2: Custom maxToolRounds = 1 blocks on round 1', () {
        final guard = AgentLoopGuard(maxToolRounds: 1);

        final v0 = guard.recordAndCheck('tool_a', {'a': 1}, 0);
        expect(v0.isAllowed, isTrue);

        final v1 = guard.recordAndCheck('tool_b', {'b': 2}, 1);
        expect(v1.isBlocked, isTrue);
        expect(v1.isMaxRoundsReached, isTrue);
      });

      test('C2.2.3: Custom maxToolRounds = 0 blocks immediately on round 0', () {
        final guard = AgentLoopGuard(maxToolRounds: 0);

        final v0 = guard.recordAndCheck('tool_init', {'init': true}, 0);
        expect(v0.isBlocked, isTrue);
        expect(v0.isMaxRoundsReached, isTrue);
      });

      test('C2.2.4: Sequential recordAndCheck without explicit currentRound uses history length', () {
        final guard = AgentLoopGuard(maxToolRounds: 4);

        final r0 = guard.recordAndCheck('t0', {'i': 0}); // history len becomes 1
        expect(r0.isAllowed, isTrue);
        expect(r0.currentRound, equals(0));

        final r1 = guard.recordAndCheck('t1', {'i': 1}); // history len becomes 2
        expect(r1.isAllowed, isTrue);
        expect(r1.currentRound, equals(1));

        final r2 = guard.recordAndCheck('t2', {'i': 2}); // history len becomes 3
        expect(r2.isAllowed, isTrue);
        expect(r2.currentRound, equals(2));

        final r3 = guard.recordAndCheck('t3', {'i': 3}); // history len becomes 4
        expect(r3.isAllowed, isTrue);
        expect(r3.currentRound, equals(3));

        // 5th call: history length is 4 == maxToolRounds
        final r4 = guard.recordAndCheck('t4', {'i': 4});
        expect(r4.isBlocked, isTrue);
        expect(r4.isMaxRoundsReached, isTrue);
        expect(r4.currentRound, equals(4));
        expect(r4.maxRounds, equals(4));
      });
    });

    // ========================================================================
    // Group 3: Tool Stripping Triggers & Fallback Predicates
    // ========================================================================
    group('Group 3: Tool Stripping Triggers & Fallback Predicates', () {
      test('C2.3.1: shouldStripTools and shouldTerminate round threshold (maxToolRounds - 1)', () {
        final guard = AgentLoopGuard(maxToolRounds: 8);

        // For maxToolRounds = 8:
        // Round 0..6: tools are NOT stripped (shouldStripTools == false)
        for (int r = 0; r <= 6; r++) {
          expect(guard.shouldStripTools(r), isFalse, reason: 'Round $r should not strip tools');
          expect(guard.shouldTerminate(r), isFalse);
        }

        // Round 7 (8 - 1 = 7): tools MUST be stripped to force text synthesis
        expect(guard.shouldStripTools(7), isTrue);
        expect(guard.shouldTerminate(7), isTrue);

        // Round 8: tools stripped
        expect(guard.shouldStripTools(8), isTrue);
        expect(guard.shouldTerminate(8), isTrue);

        // Round 10+: tools stripped
        expect(guard.shouldStripTools(10), isTrue);
        expect(guard.shouldTerminate(10), isTrue);
      });

      test('C2.3.2: shouldStripTools triggers immediately when consecutive duplicate is detected', () {
        final guard = AgentLoopGuard(maxToolRounds: 20, duplicateThreshold: 3);

        expect(guard.shouldStripTools(0), isFalse);
        guard.recordAndCheck('math_eval', {'expr': '42'});
        expect(guard.shouldStripTools(1), isFalse);
        guard.recordAndCheck('math_eval', {'expr': '42'});
        expect(guard.shouldStripTools(2), isFalse);

        // 3rd duplicate invocation -> triggers loop verdict
        final result = guard.recordAndCheck('math_eval', {'expr': '42'}, 3);
        expect(result.isBlocked, isTrue);
        expect(guard.hasTriggeredLoop, isTrue);

        // Now shouldStripTools must return true even at round 3 (< 19)
        expect(guard.shouldStripTools(3), isTrue);
        expect(guard.shouldTerminate(3), isTrue);
        expect(guard.shouldStripTools(0), isTrue);
      });

      test('C2.3.3: shouldStripTools triggers immediately when oscillation is detected', () {
        final guard = AgentLoopGuard(maxToolRounds: 20);

        guard.recordAndCheck('toolA', {'x': 1});
        guard.recordAndCheck('toolB', {'y': 2});
        guard.recordAndCheck('toolA', {'x': 1});
        expect(guard.shouldStripTools(3), isFalse);

        // 4th call completes A-B-A-B cycle
        final oscResult = guard.recordAndCheck('toolB', {'y': 2}, 3);
        expect(oscResult.isBlocked, isTrue);
        expect(oscResult.isOscillation, isTrue);
        expect(guard.hasTriggeredLoop, isTrue);

        // Immediate tool stripping
        expect(guard.shouldStripTools(3), isTrue);
        expect(guard.shouldTerminate(3), isTrue);
      });
    });

    // ========================================================================
    // Group 4: Forced Conclusion Prompt Generation
    // ========================================================================
    group('Group 4: Forced Conclusion Prompt Generation', () {
      test('C2.4.1: Prompt for LoopCheckStatus.consecutiveDuplicate', () {
        final guard = AgentLoopGuard();
        final prompt = guard.getForcedConclusionPrompt(status: LoopCheckStatus.consecutiveDuplicate);

        expect(prompt, contains('检测到连续多次使用相同参数调用同一工具'));
        expect(prompt, contains('直接给出最终的综合回答'));
        expect(prompt, contains('绝对不要再尝试重复调用工具'));
      });

      test('C2.4.2: Prompt for LoopCheckStatus.oscillation', () {
        final guard = AgentLoopGuard();
        final prompt = guard.getForcedConclusionPrompt(status: LoopCheckStatus.oscillation);

        expect(prompt, contains('检测到工具间的循环振荡调用'));
        expect(prompt, contains('请立即停止调用任何工具'));
        expect(prompt, contains('直接给出最终分析与解答'));
      });

      test('C2.4.3: Prompt for LoopCheckStatus.maxRoundsReached dynamically embeds maxToolRounds', () {
        final guard8 = AgentLoopGuard(maxToolRounds: 8);
        final prompt8 = guard8.getForcedConclusionPrompt(status: LoopCheckStatus.maxRoundsReached);
        expect(prompt8, contains('已达到工具调用轮次上限（最大 8 轮）'));
        expect(prompt8, contains('<tool_call>'));

        final guard15 = AgentLoopGuard(maxToolRounds: 15);
        final prompt15 = guard15.getForcedConclusionPrompt(status: LoopCheckStatus.maxRoundsReached);
        expect(prompt15, contains('已达到工具调用轮次上限（最大 15 轮）'));
      });

      test('C2.4.4: getForcedConclusionPrompt automatically infers status from _lastVerdict', () {
        final guard = AgentLoopGuard(duplicateThreshold: 2);
        guard.recordAndCheck('tool_dup', {'k': 'v'});
        guard.recordAndCheck('tool_dup', {'k': 'v'}); // triggers consecutiveDuplicate

        // Call without arguments
        final prompt = guard.getForcedConclusionPrompt();
        expect(prompt, contains('检测到连续多次使用相同参数调用同一工具'));
      });

      test('C2.4.5: getTerminationReason returns descriptive text or default', () {
        final guard = AgentLoopGuard();
        expect(guard.getTerminationReason(), equals('正常执行'));

        guard.recordAndCheck('t', {'x': 1});
        guard.recordAndCheck('t', {'x': 1});
        guard.recordAndCheck('t', {'x': 1}); // 3rd consecutive
        expect(guard.getTerminationReason(), contains('连续 3 次使用相同参数调用工具 [t]'));
        expect(guard.lastTerminationReason, contains('连续 3 次使用相同参数调用工具 [t]'));
      });
    });

    // ========================================================================
    // Group 5: ToolCallSignature & Canonicalization Edge Cases
    // ========================================================================
    group('Group 5: ToolCallSignature & Canonicalization Edge Cases', () {
      test('C2.5.1: Empty arguments map creates deterministic signature', () {
        final sig1 = ToolCallSignature.create('no_arg_tool', {});
        final sig2 = ToolCallSignature.create('no_arg_tool', <String, dynamic>{});

        expect(sig1.canonicalJson, equals('{}'));
        expect(sig1.hash, equals(computeMd5Hex('no_arg_tool:{}')));
        expect(sig1, equals(sig2));
      });

      test('C2.5.2: Complex data structures (primitives, nested lists, bools, nulls)', () {
        final args = {
          'null_field': null,
          'int_field': 12345,
          'double_field': 3.14,
          'bool_true': true,
          'bool_false': false,
          'list_of_primitives': [1, 'two', 3.0, true, null],
          'nested_map': {'b': 2, 'a': 1},
        };

        final sig = ToolCallSignature.create('complex_tool', args);
        expect(sig.canonicalJson, contains('"null_field":null'));
        expect(sig.canonicalJson, contains('"nested_map":{"a":1,"b":2}'));
        expect(sig.canonicalJson, contains('"list_of_primitives":[1,"two",3.0,true,null]'));
        expect(sig.hash.length, equals(32));
      });

      test('C2.5.3: Custom serializable objects via toJson and toString fallback', () {
        const jsonObj = _MockJsonSerializable('alpha', 99);
        const plainObj = _MockPlainObject('beta');

        final sig = ToolCallSignature.create('obj_tool', {
          'json_obj': jsonObj,
          'plain_obj': plainObj,
        });

        expect(sig.canonicalJson, contains('"json_obj":{"key":"alpha","value":99}'));
        expect(sig.canonicalJson, contains('"plain_obj":"MockPlainObject(beta)"'));
      });

      test('C2.5.4: Value canonicalization preserves list ordering while canonicalizing elements', () {
        final sigA = ToolCallSignature.create('sort_tool', {
          'items': [
            {'z': 2, 'a': 1},
            {'y': 4, 'b': 3},
          ]
        });
        final sigB = ToolCallSignature.create('sort_tool', {
          'items': [
            {'a': 1, 'z': 2},
            {'b': 3, 'y': 4},
          ]
        });

        expect(sigA.canonicalJson, equals(sigB.canonicalJson));
        expect(sigA, equals(sigB));
      });
    });

    // ========================================================================
    // Group 6: Complete Guard Lifecycle & State Reset
    // ========================================================================
    group('Group 6: Complete Guard Lifecycle & State Reset', () {
      test('C2.6.1: reset() completely purges history, lastVerdict and loop flags', () {
        final guard = AgentLoopGuard(duplicateThreshold: 2);
        guard.recordAndCheck('tool_1', {'k': 1});
        guard.recordAndCheck('tool_1', {'k': 1}); // loop triggered

        expect(guard.callCount, equals(2));
        expect(guard.hasTriggeredLoop, isTrue);
        expect(guard.lastVerdict, isNotNull);
        expect(guard.lastTerminationReason, isNotNull);

        guard.reset();

        expect(guard.callCount, equals(0));
        expect(guard.history.isEmpty, isTrue);
        expect(guard.hasTriggeredLoop, isFalse);
        expect(guard.lastVerdict, isNull);
        expect(guard.lastTerminationReason, isNull);
        expect(guard.getTerminationReason(), equals('正常执行'));
      });

      test('C2.6.2: Independent instances do not share state', () {
        final g1 = AgentLoopGuard(maxToolRounds: 5);
        final g2 = AgentLoopGuard(maxToolRounds: 10);

        g1.recordToolCall('t1', {'a': 1});
        expect(g1.callCount, equals(1));
        expect(g2.callCount, equals(0));

        g2.recordToolCall('t2', {'b': 2});
        g2.recordToolCall('t3', {'c': 3});
        expect(g1.callCount, equals(1));
        expect(g2.callCount, equals(2));
      });
    });
  });
}
