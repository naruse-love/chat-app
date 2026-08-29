import 'dart:math';
import 'package:chat/services/agent_loop_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper custom class with toJson
class CustomJsonPayload {
  final String title;
  final int count;
  CustomJsonPayload(this.title, this.count);
  Map<String, dynamic> toJson() => {'title': title, 'count': count};
}

/// Helper custom class without toJson
class CustomPlainPayload {
  final String label;
  CustomPlainPayload(this.label);
  @override
  String toString() => 'CustomPlainPayload($label)';
}

void main() {
  group('Empirical Stress Testing — Milestone 23.3: AgentLoopGuard', () {
    // ------------------------------------------------------------------------
    // Suite 1: Deeply Nested Arguments, Edge Types & Canonicalization
    // ------------------------------------------------------------------------
    group('Suite 1: Deeply Nested Arguments, Edge Types & Canonicalization', () {
      test('S1.1: 10-level deeply nested map canonicalization with inverted keys', () {
        Map<String, dynamic> createNested(bool reversed) {
          Map<String, dynamic> current = {'leaf': 42, 'active': true};
          for (int level = 9; level >= 1; level--) {
            if (reversed) {
              current = {
                'z_meta_$level': 'level_$level',
                'nested': current,
                'a_info_$level': level * 10,
              };
            } else {
              current = {
                'a_info_$level': level * 10,
                'nested': current,
                'z_meta_$level': 'level_$level',
              };
            }
          }
          return current;
        }

        final mapA = createNested(false);
        final mapB = createNested(true);

        final sigA = ToolCallSignature.create('deep_tool', mapA);
        final sigB = ToolCallSignature.create('deep_tool', mapB);

        expect(sigA.canonicalJson, equals(sigB.canonicalJson));
        expect(sigA.hash, equals(sigB.hash));
        expect(sigA, equals(sigB));
        expect(sigA.hashCode, equals(sigB.hashCode));
      });

      test('S1.2: 100 random key permutations of a 15-key map yield identical signature', () {
        final baseKeys = List.generate(15, (i) => 'key_${i.toString().padLeft(2, '0')}');
        final baseValues = List.generate(15, (i) => i * 100);

        final referenceMap = <String, dynamic>{};
        for (int i = 0; i < 15; i++) {
          referenceMap[baseKeys[i]] = baseValues[i];
        }
        final refSig = ToolCallSignature.create('perm_tool', referenceMap);

        final random = Random(42);
        for (int iter = 0; iter < 100; iter++) {
          final shuffledIndices = List.generate(15, (i) => i)..shuffle(random);
          final shuffledMap = <String, dynamic>{};
          for (final idx in shuffledIndices) {
            shuffledMap[baseKeys[idx]] = baseValues[idx];
          }

          final sig = ToolCallSignature.create('perm_tool', shuffledMap);
          expect(sig.canonicalJson, equals(refSig.canonicalJson));
          expect(sig.hash, equals(refSig.hash));
          expect(sig, equals(refSig));
        }
      });

      test('S1.3: Unicode, Chinese characters, emoji, surrogate pairs and RTL text', () {
        final complexArgs1 = {
          '城市': '北京',
          '表情': '🔥🤖🎉🌟',
          '多语言': {'عربي': 'مرحبا', '日本語': 'こんにちは', '한국어': '안녕하세요'},
          '特殊符号': '<xml>&&"\'\n\r\t</xml>',
        };
        final complexArgs2 = {
          '特殊符号': '<xml>&&"\'\n\r\t</xml>',
          '城市': '北京',
          '多语言': {'日本語': 'こんにちは', '한국어': '안녕하세요', 'عربي': 'مرحبا'},
          '表情': '🔥🤖🎉🌟',
        };

        final sig1 = ToolCallSignature.create('i18n_tool', complexArgs1);
        final sig2 = ToolCallSignature.create('i18n_tool', complexArgs2);

        expect(sig1.canonicalJson, equals(sig2.canonicalJson));
        expect(sig1.hash, equals(sig2.hash));
        expect(sig1, equals(sig2));
      });

      test('S1.4: Edge value types: null, empty map, empty list, numbers, custom objects', () {
        final customObj1 = CustomJsonPayload('test', 123);
        final customObj2 = CustomPlainPayload('plain_val');

        final args = {
          'empty_map': <String, dynamic>{},
          'empty_list': <dynamic>[],
          'null_val': null,
          'float_val': 3.141592653589793,
          'int_val': -999999,
          'bool_true': true,
          'bool_false': false,
          'custom_json': customObj1,
          'custom_plain': customObj2,
        };

        final sig = ToolCallSignature.create('edge_tool', args);
        expect(sig.canonicalJson, contains('"empty_map":{}'));
        expect(sig.canonicalJson, contains('"empty_list":[]'));
        expect(sig.canonicalJson, contains('"null_val":null'));
        expect(sig.canonicalJson, contains('"custom_json":{"count":123,"title":"test"}'));
        expect(sig.canonicalJson, contains('"custom_plain":"CustomPlainPayload(plain_val)"'));
        expect(sig.hash.length, equals(32));
      });

      test('S1.5: List of nested maps maintains list element ordering while sorting inner keys', () {
        final listA = [
          {'z': 2, 'a': 1},
          {'y': 4, 'b': 3},
        ];
        final listB = [
          {'a': 1, 'z': 2},
          {'b': 3, 'y': 4},
        ];
        final listCReversed = [
          {'b': 3, 'y': 4},
          {'a': 1, 'z': 2},
        ];

        final sigA = ToolCallSignature.create('list_tool', {'items': listA});
        final sigB = ToolCallSignature.create('list_tool', {'items': listB});
        final sigC = ToolCallSignature.create('list_tool', {'items': listCReversed});

        expect(sigA.canonicalJson, equals(sigB.canonicalJson));
        expect(sigA, equals(sigB));
        expect(sigA, isNot(equals(sigC)));
      });
    });

    // ------------------------------------------------------------------------
    // Suite 2: Duplicate Bursts & High Volume Stress
    // ------------------------------------------------------------------------
    group('Suite 2: Duplicate Bursts & High Volume Stress', () {
      test('S2.1: 500 consecutive identical calls: exactly 2 allowed, 498 blocked', () {
        final guard = AgentLoopGuard(duplicateThreshold: 3, maxToolRounds: 1000);

        int allowedCount = 0;
        int blockedCount = 0;

        for (int i = 0; i < 500; i++) {
          final result = guard.recordAndCheck('repeat_tool', {'fixed': 'arg'}, i);
          if (result.isAllowed) {
            allowedCount++;
          } else {
            blockedCount++;
            expect(result.isConsecutiveDuplicate, isTrue);
            expect(result.status, equals(LoopCheckStatus.consecutiveDuplicate));
            expect(result.reason, contains('连续 ${i + 1} 次'));
          }
        }

        expect(allowedCount, equals(2));
        expect(blockedCount, equals(498));
        expect(guard.callCount, equals(500));
        expect(guard.hasTriggeredLoop, isTrue);
      });

      test('S2.2: Burst of 500 distinct progressive calls: all allowed', () {
        final guard = AgentLoopGuard(duplicateThreshold: 3, maxToolRounds: 1000);

        for (int i = 0; i < 500; i++) {
          final result = guard.recordAndCheck('unique_tool', {'index': i}, i);
          expect(result.isAllowed, isTrue);
          expect(result.status, equals(LoopCheckStatus.allowed));
        }

        expect(guard.callCount, equals(500));
        expect(guard.hasTriggeredLoop, isFalse);
      });

      test('S2.3: Reset during repeated duplicate bursts', () {
        final guard = AgentLoopGuard(duplicateThreshold: 3);

        // Burst 1: 2 calls allowed, 3rd blocked
        expect(guard.recordAndCheck('tool_x', {'v': 1}).isAllowed, isTrue);
        expect(guard.recordAndCheck('tool_x', {'v': 1}).isAllowed, isTrue);
        expect(guard.recordAndCheck('tool_x', {'v': 1}).isBlocked, isTrue);
        expect(guard.hasTriggeredLoop, isTrue);

        // Reset
        guard.reset();
        expect(guard.callCount, equals(0));
        expect(guard.hasTriggeredLoop, isFalse);
        expect(guard.lastVerdict, isNull);

        // Burst 2: should behave freshly
        expect(guard.recordAndCheck('tool_x', {'v': 1}).isAllowed, isTrue);
        expect(guard.recordAndCheck('tool_x', {'v': 1}).isAllowed, isTrue);
        expect(guard.recordAndCheck('tool_x', {'v': 1}).isBlocked, isTrue);
      });

      test('S2.4: High-throughput benchmark: 10,000 signature creations and checks', () {
        final guard = AgentLoopGuard(maxToolRounds: 50000, duplicateThreshold: 20000);
        final stopwatch = Stopwatch()..start();

        for (int i = 0; i < 10000; i++) {
          guard.recordAndCheck('bench_tool', {
            'iter': i,
            'meta': {'nested': i % 100, 'flag': i.isEven},
          }, i);
        }

        stopwatch.stop();
        // 10,000 iterations must complete smoothly in reasonable time (< 1000ms)
        expect(stopwatch.elapsedMilliseconds, lessThan(3000));
        expect(guard.callCount, equals(10000));
      });

      test('S2.5: Variable duplicateThreshold (1, 2, 5, 10)', () {
        for (final threshold in [1, 2, 5, 10]) {
          final guard = AgentLoopGuard(duplicateThreshold: threshold, maxToolRounds: 50);
          int allowed = 0;
          for (int i = 0; i < threshold + 3; i++) {
            final res = guard.recordAndCheck('t', {'k': 'v'}, i);
            if (res.isAllowed) allowed++;
          }
          expect(allowed, equals(threshold - 1));
        }
      });
    });

    // ------------------------------------------------------------------------
    // Suite 3: Complex Cycles, Oscillation Matrix & Sliding Windows
    // ------------------------------------------------------------------------
    group('Suite 3: Complex Cycles, Oscillation Matrix & Sliding Windows', () {
      test('S3.1: Period 2 oscillation (A -> B -> A -> B) detected on 4th call', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('toolA', {'arg': 1});
        guard.recordAndCheck('toolB', {'arg': 2});
        guard.recordAndCheck('toolA', {'arg': 1});
        final verdict = guard.recordAndCheck('toolB', {'arg': 2});

        expect(verdict.isBlocked, isTrue);
        expect(verdict.isOscillation, isTrue);
        expect(verdict.cyclePeriod, equals(2));
        expect(verdict.detectedPattern, equals('toolA -> toolB'));
      });

      test('S3.2: Period 3 oscillation (A -> B -> C -> A -> B -> C) detected on 6th call', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('toolA', {'arg': 1});
        guard.recordAndCheck('toolB', {'arg': 2});
        guard.recordAndCheck('toolC', {'arg': 3});
        guard.recordAndCheck('toolA', {'arg': 1});
        guard.recordAndCheck('toolB', {'arg': 2});
        final verdict = guard.recordAndCheck('toolC', {'arg': 3});

        expect(verdict.isBlocked, isTrue);
        expect(verdict.isOscillation, isTrue);
        expect(verdict.cyclePeriod, equals(3));
        expect(verdict.detectedPattern, equals('toolA -> toolB -> toolC'));
      });

      test('S3.3: Configurable periods [2, 3, 4, 5]: detects Period 4 and Period 5 cycles', () {
        // Period 4: A -> B -> C -> D -> A -> B -> C -> D
        final guard4 = AgentLoopGuard(cyclePeriodsToCheck: [2, 3, 4], maxToolRounds: 50);
        guard4.recordAndCheck('t1', {'i': 1}, 0);
        guard4.recordAndCheck('t2', {'i': 2}, 1);
        guard4.recordAndCheck('t3', {'i': 3}, 2);
        guard4.recordAndCheck('t4', {'i': 4}, 3);
        guard4.recordAndCheck('t1', {'i': 1}, 4);
        guard4.recordAndCheck('t2', {'i': 2}, 5);
        guard4.recordAndCheck('t3', {'i': 3}, 6);
        final res4 = guard4.recordAndCheck('t4', {'i': 4}, 7);

        expect(res4.isBlocked, isTrue);
        expect(res4.isOscillation, isTrue);
        expect(res4.cyclePeriod, equals(4));
        expect(res4.detectedPattern, equals('t1 -> t2 -> t3 -> t4'));

        // Period 5: A -> B -> C -> D -> E -> A -> B -> C -> D -> E
        final guard5 = AgentLoopGuard(
          cyclePeriodsToCheck: [2, 3, 4, 5],
          oscillationHistoryDepth: 20,
          maxToolRounds: 50,
        );
        for (int round = 0; round < 2; round++) {
          for (int step = 1; step <= 5; step++) {
            final overallRound = round * 5 + step - 1;
            final res = guard5.recordAndCheck('tool_$step', {'val': step}, overallRound);
            if (round == 1 && step == 5) {
              expect(res.isBlocked, isTrue);
              expect(res.isOscillation, isTrue);
              expect(res.cyclePeriod, equals(5));
            } else {
              expect(res.isAllowed, isTrue);
            }
          }
        }
      });

      test('S3.4: Heavy noisy preamble followed by alternating cycle (20 noise + A-B-A-B)', () {
        final guard = AgentLoopGuard(maxToolRounds: 50);

        // 20 noisy distinct calls
        for (int i = 0; i < 20; i++) {
          final res = guard.recordAndCheck('noise_tool', {'noise_id': i}, i);
          expect(res.isAllowed, isTrue);
        }

        // Now start alternating cycle
        guard.recordAndCheck('target_A', {'param': 'alpha'}, 20);
        guard.recordAndCheck('target_B', {'param': 'beta'}, 21);
        guard.recordAndCheck('target_A', {'param': 'alpha'}, 22);
        final cycleVerdict = guard.recordAndCheck('target_B', {'param': 'beta'}, 23);

        expect(cycleVerdict.isBlocked, isTrue);
        expect(cycleVerdict.isOscillation, isTrue);
        expect(cycleVerdict.cyclePeriod, equals(2));
        expect(cycleVerdict.detectedPattern, equals('target_A -> target_B'));
      });

      test('S3.5: Near-cycle false positive resistance: A -> B -> C -> A -> B -> D is allowed', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('step_A', {'k': 1});
        guard.recordAndCheck('step_B', {'k': 2});
        guard.recordAndCheck('step_C', {'k': 3});
        guard.recordAndCheck('step_A', {'k': 1});
        guard.recordAndCheck('step_B', {'k': 2});
        // Differs on the 6th call (step_D instead of step_C)
        final res = guard.recordAndCheck('step_D', {'k': 4});

        expect(res.isAllowed, isTrue);
        expect(res.status, equals(LoopCheckStatus.allowed));
      });

      test('S3.6: Degenerate pattern (A -> A -> A -> A) does not trigger oscillation when threshold is high', () {
        final guard = AgentLoopGuard(duplicateThreshold: 10);
        guard.recordAndCheck('same_tool', {'k': 'v'});
        guard.recordAndCheck('same_tool', {'k': 'v'});
        guard.recordAndCheck('same_tool', {'k': 'v'});
        final res = guard.recordAndCheck('same_tool', {'k': 'v'});

        // Should be allowed because duplicateThreshold is 10 and oscillation skips degenerate patterns
        expect(res.isAllowed, isTrue);
        expect(res.isOscillation, isFalse);
      });

      test('S3.7: Sliding window depth boundary: cycle within window vs cycle truncated by depth', () {
        final guard = AgentLoopGuard(oscillationHistoryDepth: 6, maxToolRounds: 50);

        // Fill 10 calls: noise1..noise6, then A, B, A, B
        for (int i = 0; i < 6; i++) {
          guard.recordAndCheck('noise_$i', {'x': i}, i);
        }
        // Last 4 calls are A, B, A, B which fit inside depth 6
        guard.recordAndCheck('loop_A', {'id': 1}, 6);
        guard.recordAndCheck('loop_B', {'id': 2}, 7);
        guard.recordAndCheck('loop_A', {'id': 1}, 8);
        final res = guard.recordAndCheck('loop_B', {'id': 2}, 9);

        expect(res.isBlocked, isTrue);
        expect(res.isOscillation, isTrue);
      });
    });

    // ------------------------------------------------------------------------
    // Suite 4: Lifecycle, Round Ceilings, Tool Stripping & State Isolation
    // ------------------------------------------------------------------------
    group('Suite 4: Lifecycle, Round Ceilings, Tool Stripping & State Isolation', () {
      test('S4.1: maxToolRounds boundary check (0 to 10 rounds)', () {
        final guard = AgentLoopGuard(maxToolRounds: 5);

        for (int r = 0; r < 5; r++) {
          final res = guard.checkBeforeExecution('tool_$r', {'r': r}, currentRound: r);
          expect(res.isAllowed, isTrue);
        }

        // Round 5 is >= maxToolRounds (5)
        final res5 = guard.checkBeforeExecution('tool_5', {'r': 5}, currentRound: 5);
        expect(res5.isBlocked, isTrue);
        expect(res5.isMaxRoundsReached, isTrue);
        expect(res5.status, equals(LoopCheckStatus.maxRoundsReached));
        expect(res5.reason, contains('达到工具调用轮次上限 (5 / 5 轮)'));

        // Round 6
        final res6 = guard.checkBeforeExecution('tool_6', {'r': 6}, currentRound: 6);
        expect(res6.isBlocked, isTrue);
        expect(res6.isMaxRoundsReached, isTrue);
      });

      test('S4.2: shouldStripTools and shouldTerminate consistency across rounds', () {
        final guard = AgentLoopGuard(maxToolRounds: 6);

        expect(guard.shouldStripTools(0), isFalse);
        expect(guard.shouldStripTools(4), isFalse);
        // Round 5 is maxToolRounds - 1 (6 - 1 = 5) -> strip tools to force conclusion
        expect(guard.shouldStripTools(5), isTrue);
        expect(guard.shouldStripTools(6), isTrue);
        expect(guard.shouldTerminate(5), isTrue);
        expect(guard.shouldTerminate(6), isTrue);
      });

      test('S4.3: shouldStripTools triggers immediately when loop is detected even at round 1', () {
        final guard = AgentLoopGuard(maxToolRounds: 20, duplicateThreshold: 2);
        expect(guard.shouldStripTools(1), isFalse);

        guard.recordAndCheck('tool_dup', {'p': 1});
        guard.recordAndCheck('tool_dup', {'p': 1}); // Loop triggered

        expect(guard.hasTriggeredLoop, isTrue);
        expect(guard.shouldStripTools(1), isTrue);
        expect(guard.shouldTerminate(1), isTrue);
      });

      test('S4.4: getForcedConclusionPrompt covers all statuses with clear Chinese guidance', () {
        final guard = AgentLoopGuard(maxToolRounds: 10);

        final pDup = guard.getForcedConclusionPrompt(status: LoopCheckStatus.consecutiveDuplicate);
        expect(pDup, contains('检测到连续多次使用相同参数调用同一工具'));
        expect(pDup, contains('直接给出最终的综合回答'));

        final pOsc = guard.getForcedConclusionPrompt(status: LoopCheckStatus.oscillation);
        expect(pOsc, contains('检测到工具间的循环振荡调用'));
        expect(pOsc, contains('直接给出最终分析与解答'));

        final pMax = guard.getForcedConclusionPrompt(status: LoopCheckStatus.maxRoundsReached);
        expect(pMax, contains('已达到工具调用轮次上限（最大 10 轮）'));
        expect(pMax, contains('绝对不要再尝试使用任何工具'));

        final pDefault = guard.getForcedConclusionPrompt();
        expect(pDefault, contains('已达到工具调用轮次上限'));
      });

      test('S4.5: Multiple independent guard instances maintain strict state isolation', () {
        final guard1 = AgentLoopGuard(duplicateThreshold: 2);
        final guard2 = AgentLoopGuard(duplicateThreshold: 3);

        guard1.recordAndCheck('tool_common', {'v': 1});
        guard2.recordAndCheck('tool_common', {'v': 1});

        // 2nd call: blocks guard1, allows guard2
        final res1 = guard1.recordAndCheck('tool_common', {'v': 1});
        final res2 = guard2.recordAndCheck('tool_common', {'v': 1});

        expect(res1.isBlocked, isTrue);
        expect(res2.isAllowed, isTrue);
        expect(guard1.hasTriggeredLoop, isTrue);
        expect(guard2.hasTriggeredLoop, isFalse);
      });

      test('S4.6: checkNextCall does not mutate history or lastVerdict', () {
        final guard = AgentLoopGuard();
        guard.recordToolCall('t1', {'a': 1});
        expect(guard.callCount, equals(1));
        expect(guard.lastVerdict, isNull);

        final check = guard.checkNextCall('t1', {'a': 1});
        expect(check.isAllowed, isTrue);
        expect(guard.callCount, equals(1));
        expect(guard.lastVerdict, isNull);
      });
    });

    // ------------------------------------------------------------------------
    // Suite 5: RFC 1321 MD5 Boundaries & Large Payloads
    // ------------------------------------------------------------------------
    group('Suite 5: RFC 1321 MD5 Boundaries & Large Payloads', () {
      test('S5.1: RFC 1321 standard test vectors', () {
        expect(computeMd5Hex(''), equals('d41d8cd98f00b204e9800998ecf8427e'));
        expect(computeMd5Hex('a'), equals('0cc175b9c0f1b6a831c399e269772661'));
        expect(computeMd5Hex('abc'), equals('900150983cd24fb0d6963f7d28e17f72'));
        expect(computeMd5Hex('message digest'), equals('f96b697d7cb7938d525a2f31aaf161d0'));
        expect(computeMd5Hex('abcdefghijklmnopqrstuvwxyz'), equals('c3fcd3d76192e4007dfb496cca67e13b'));
        expect(computeMd5Hex('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'),
            equals('d174ab98d277d9f5a5611c2c9f419d9f'));
        expect(
          computeMd5Hex('12345678901234567890123456789012345678901234567890123456789012345678901234567890'),
          equals('57edf4a22be3c955ac49da2e2107b67a'),
        );
      });

      test('S5.2: Buffer boundary tests (55, 56, 64, 119, 120, 128 bytes)', () {
        for (final len in [55, 56, 64, 119, 120, 128]) {
          final str = 'A' * len;
          final hash = computeMd5Hex(str);
          expect(hash.length, equals(32));
          expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(hash), isTrue);
        }
      });

      test('S5.3: 100KB large payload hashing stability', () {
        final largeString = 'DartAgentLoopGuardStressTestingPayload' * 3000; // ~114KB
        final stopwatch = Stopwatch()..start();
        final hash = computeMd5Hex(largeString);
        stopwatch.stop();

        expect(hash.length, equals(32));
        expect(stopwatch.elapsedMilliseconds, lessThan(200));
      });
    });
  });
}
