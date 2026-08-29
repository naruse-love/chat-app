import 'package:chat/services/agent_loop_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentLoopGuard Test Suite', () {
    // ------------------------------------------------------------------------
    // Group 1: ToolCallSignature & Normalization
    // ------------------------------------------------------------------------
    group('Group 1: ToolCallSignature & Normalization', () {
      test('T1.1: Flat map key ordering normalization', () {
        final sig1 = ToolCallSignature.create('math_eval', {'b': 2, 'a': 1});
        final sig2 = ToolCallSignature.create('math_eval', {'a': 1, 'b': 2});

        expect(sig1.canonicalJson, equals('{"a":1,"b":2}'));
        expect(sig2.canonicalJson, equals('{"a":1,"b":2}'));
        expect(sig1.hash, equals(sig2.hash));
        expect(sig1, equals(sig2));
      });

      test('T1.2: Deep recursive nested map sorting', () {
        final sig1 = ToolCallSignature.create('search', {
          'meta': {'z': 9, 'y': 8, 'x': {'b': 2, 'a': 1}},
          'query': 'flutter',
        });
        final sig2 = ToolCallSignature.create('search', {
          'query': 'flutter',
          'meta': {'y': 8, 'x': {'a': 1, 'b': 2}, 'z': 9},
        });

        expect(sig1.canonicalJson, equals(sig2.canonicalJson));
        expect(sig1.hash, equals(sig2.hash));
        expect(sig1, equals(sig2));
      });

      test('T1.3: List order preservation with element canonicalization', () {
        final sig1 = ToolCallSignature.create('batch_op', {
          'items': [
            {'b': 2, 'a': 1},
            {'d': 4, 'c': 3},
          ],
        });
        final sig2 = ToolCallSignature.create('batch_op', {
          'items': [
            {'a': 1, 'b': 2},
            {'c': 3, 'd': 4},
          ],
        });
        final sig3Reversed = ToolCallSignature.create('batch_op', {
          'items': [
            {'c': 3, 'd': 4},
            {'a': 1, 'b': 2},
          ],
        });

        expect(sig1.canonicalJson, equals(sig2.canonicalJson));
        expect(sig1, equals(sig2));
        expect(sig1, isNot(equals(sig3Reversed)));
      });

      test('T1.4: Pure Dart MD5 hash validation against known RFC 1321 vectors', () {
        expect(computeMd5Hex(''), equals('d41d8cd98f00b204e9800998ecf8427e'));
        expect(computeMd5Hex('a'), equals('0cc175b9c0f1b6a831c399e269772661'));
        expect(computeMd5Hex('abc'), equals('900150983cd24fb0d6963f7d28e17f72'));
        expect(computeMd5Hex('message digest'), equals('f96b697d7cb7938d525a2f31aaf161d0'));
        expect(computeMd5Hex('abcdefghijklmnopqrstuvwxyz'), equals('c3fcd3d76192e4007dfb496cca67e13b'));
      });

      test('T1.5: ToolCallSignature equality and hashCode consistency in Sets', () {
        final sig1 = ToolCallSignature.create('time_calculator', {'zone': 'Asia/Shanghai'});
        final sig2 = ToolCallSignature.create('time_calculator', {'zone': 'Asia/Shanghai'});
        final sig3 = ToolCallSignature.create('time_calculator', {'zone': 'UTC'});

        final set = <ToolCallSignature>{sig1, sig2, sig3};
        expect(set.length, equals(2));
        expect(sig1.hashCode, equals(sig2.hashCode));
        expect(sig1.toString(), contains('time_calculator'));
      });

      test('T1.6: Different tool names or differing arguments yield distinct signatures', () {
        final s1 = ToolCallSignature.create('weather_query', {'city': 'Beijing'});
        final s2 = ToolCallSignature.create('weather_query', {'city': 'Tokyo'});
        final s3 = ToolCallSignature.create('wiki_lookup', {'query': 'Beijing'});

        expect(s1, isNot(equals(s2)));
        expect(s1.hash, isNot(equals(s2.hash)));
        expect(s1, isNot(equals(s3)));
      });
    });

    // ------------------------------------------------------------------------
    // Group 2: Consecutive Duplicate Detection
    // ------------------------------------------------------------------------
    group('Group 2: Consecutive Duplicate Detection', () {
      test('T2.1: 1st tool call is allowed with default duplicateThreshold = 3', () {
        final guard = AgentLoopGuard();
        final result = guard.recordAndCheck('math_eval', {'expr': '1 + 1'});

        expect(result.isAllowed, isTrue);
        expect(result.status, equals(LoopCheckStatus.allowed));
      });

      test('T2.2: 2nd consecutive identical tool call is allowed', () {
        final guard = AgentLoopGuard(duplicateThreshold: 3);
        guard.recordAndCheck('math_eval', {'expr': '1 + 1'});
        final result = guard.recordAndCheck('math_eval', {'expr': '1 + 1'});

        expect(result.isAllowed, isTrue);
        expect(result.status, equals(LoopCheckStatus.allowed));
      });

      test('T2.3: 3rd consecutive identical tool call is blocked with consecutiveDuplicate', () {
        final guard = AgentLoopGuard(duplicateThreshold: 3);
        guard.recordAndCheck('math_eval', {'expr': '1 + 1'});
        guard.recordAndCheck('math_eval', {'expr': '1 + 1'});
        final result = guard.recordAndCheck('math_eval', {'expr': '1 + 1'});

        expect(result.isBlocked, isTrue);
        expect(result.isConsecutiveDuplicate, isTrue);
        expect(result.status, equals(LoopCheckStatus.consecutiveDuplicate));
        expect(result.reason, contains('连续 3 次使用相同参数调用工具 [math_eval]'));
        expect(result.detectedPattern, equals('math_eval x 3'));
        expect(guard.hasTriggeredLoop, isTrue);
      });

      test('T2.4: Sequence interrupted by a different call resets consecutive count', () {
        final guard = AgentLoopGuard(duplicateThreshold: 3);
        guard.recordAndCheck('math_eval', {'expr': '1 + 1'});
        guard.recordAndCheck('math_eval', {'expr': '1 + 1'});
        // Interruption
        guard.recordAndCheck('time_calculator', {'zone': 'UTC'});
        // 3rd time calling math_eval, but only 1st consecutive after interruption
        final result = guard.recordAndCheck('math_eval', {'expr': '1 + 1'});

        expect(result.isAllowed, isTrue);
      });

      test('T2.5: Differing key order does not evade duplicate detection', () {
        final guard = AgentLoopGuard(duplicateThreshold: 3);
        guard.recordAndCheck('weather_query', {'city': 'Shanghai', 'days': 3});
        guard.recordAndCheck('weather_query', {'days': 3, 'city': 'Shanghai'});
        final result = guard.recordAndCheck('weather_query', {'city': 'Shanghai', 'days': 3});

        expect(result.isBlocked, isTrue);
        expect(result.isConsecutiveDuplicate, isTrue);
      });

      test('T2.6: Custom duplicateThreshold = 2 triggers block on 2nd call', () {
        final guard = AgentLoopGuard(duplicateThreshold: 2);
        guard.recordAndCheck('wiki_lookup', {'query': 'Dart'});
        final result = guard.recordAndCheck('wiki_lookup', {'query': 'Dart'});

        expect(result.isBlocked, isTrue);
        expect(result.isConsecutiveDuplicate, isTrue);
        expect(result.reason, contains('连续 2 次'));
      });
    });

    // ------------------------------------------------------------------------
    // Group 3: Oscillation & Cycle Detection
    // ------------------------------------------------------------------------
    group('Group 3: Oscillation & Cycle Detection', () {
      test('T3.1: Period 2 oscillation (A -> B -> A -> B) triggers on 4th call', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('math_eval', {'expr': '2^10'});
        guard.recordAndCheck('weather_query', {'city': 'Beijing'});
        guard.recordAndCheck('math_eval', {'expr': '2^10'});
        final result = guard.recordAndCheck('weather_query', {'city': 'Beijing'});

        expect(result.isBlocked, isTrue);
        expect(result.isOscillation, isTrue);
        expect(result.cyclePeriod, equals(2));
        expect(result.cycleLength, equals(2));
        expect(result.detectedPattern, equals('math_eval -> weather_query'));
        expect(result.reason, contains('周期为 2 的工具循环振荡调用'));
      });

      test('T3.2: Period 3 oscillation (A -> B -> C -> A -> B -> C) triggers on 6th call', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('tool_a', {'k': 1});
        guard.recordAndCheck('tool_b', {'k': 2});
        guard.recordAndCheck('tool_c', {'k': 3});
        guard.recordAndCheck('tool_a', {'k': 1});
        guard.recordAndCheck('tool_b', {'k': 2});
        final result = guard.recordAndCheck('tool_c', {'k': 3});

        expect(result.isBlocked, isTrue);
        expect(result.isOscillation, isTrue);
        expect(result.cyclePeriod, equals(3));
        expect(result.detectedPattern, equals('tool_a -> tool_b -> tool_c'));
      });

      test('T3.3: Same tool alternating parameters triggers oscillation', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('search', {'q': 'flutter'});
        guard.recordAndCheck('search', {'q': 'dart'});
        guard.recordAndCheck('search', {'q': 'flutter'});
        final result = guard.recordAndCheck('search', {'q': 'dart'});

        expect(result.isBlocked, isTrue);
        expect(result.isOscillation, isTrue);
        expect(result.cyclePeriod, equals(2));
        expect(result.detectedPattern, equals('search -> search'));
      });

      test('T3.4: Prefixed oscillation (X -> Y -> A -> B -> A -> B) identifies suffix', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('init_1', {'a': 1});
        guard.recordAndCheck('init_2', {'b': 2});
        guard.recordAndCheck('step_a', {'k': 'a'});
        guard.recordAndCheck('step_b', {'k': 'b'});
        guard.recordAndCheck('step_a', {'k': 'a'});
        final result = guard.recordAndCheck('step_b', {'k': 'b'});

        expect(result.isBlocked, isTrue);
        expect(result.isOscillation, isTrue);
        expect(result.cyclePeriod, equals(2));
        expect(result.detectedPattern, equals('step_a -> step_b'));
      });

      test('T3.5: Non-cyclic progressive calls (A -> B -> C -> D -> A) are allowed', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('tool_a', {'id': 1});
        guard.recordAndCheck('tool_b', {'id': 2});
        guard.recordAndCheck('tool_c', {'id': 3});
        guard.recordAndCheck('tool_d', {'id': 4});
        final result = guard.recordAndCheck('tool_a', {'id': 1});

        expect(result.isAllowed, isTrue);
      });

      test('T3.6: Pure consecutive duplicates are not misclassified as oscillation', () {
        final guard = AgentLoopGuard(duplicateThreshold: 5);
        guard.recordAndCheck('tool_x', {'val': 100});
        guard.recordAndCheck('tool_x', {'val': 100});
        guard.recordAndCheck('tool_x', {'val': 100});
        final result = guard.recordAndCheck('tool_x', {'val': 100});

        expect(result.isAllowed, isTrue);
        expect(result.isOscillation, isFalse);
      });
    });

    // ------------------------------------------------------------------------
    // Group 4: Lifecycle, Max Rounds & Tool Stripping
    // ------------------------------------------------------------------------
    group('Group 4: Lifecycle, Max Rounds & Tool Stripping', () {
      test('T4.1: Reaching maxToolRounds yields maxRoundsReached result', () {
        final guard = AgentLoopGuard(maxToolRounds: 4);
        guard.recordAndCheck('tool_1', {'i': 1});
        guard.recordAndCheck('tool_2', {'i': 2});
        guard.recordAndCheck('tool_3', {'i': 3});
        guard.recordAndCheck('tool_4', {'i': 4});

        final result = guard.checkBeforeExecution('tool_5', {'i': 5}, currentRound: 4);

        expect(result.isBlocked, isTrue);
        expect(result.isMaxRoundsReached, isTrue);
        expect(result.status, equals(LoopCheckStatus.maxRoundsReached));
        expect(result.reason, contains('达到工具调用轮次上限'));
      });

      test('T4.2: shouldStripTools returns true when currentRound >= maxToolRounds - 1', () {
        final guard = AgentLoopGuard(maxToolRounds: 8);

        expect(guard.shouldStripTools(5), isFalse);
        expect(guard.shouldStripTools(6), isFalse);
        expect(guard.shouldStripTools(7), isTrue); // 8 - 1 = 7
        expect(guard.shouldStripTools(8), isTrue);
        expect(guard.shouldTerminate(7), isTrue);
      });

      test('T4.3: shouldStripTools returns true immediately after loop verdict regardless of round', () {
        final guard = AgentLoopGuard(maxToolRounds: 8, duplicateThreshold: 3);
        expect(guard.shouldStripTools(2), isFalse);

        guard.recordAndCheck('tool_a', {'v': 1});
        guard.recordAndCheck('tool_a', {'v': 1});
        guard.recordAndCheck('tool_a', {'v': 1}); // Duplicate triggered

        expect(guard.hasTriggeredLoop, isTrue);
        expect(guard.shouldStripTools(2), isTrue);
      });

      test('T4.4: getForcedConclusionPrompt generates specific Chinese texts', () {
        final guard = AgentLoopGuard(maxToolRounds: 8);

        final dupPrompt = guard.getForcedConclusionPrompt(status: LoopCheckStatus.consecutiveDuplicate);
        expect(dupPrompt, contains('检测到连续多次使用相同参数调用同一工具'));

        final oscPrompt = guard.getForcedConclusionPrompt(status: LoopCheckStatus.oscillation);
        expect(oscPrompt, contains('检测到工具间的循环振荡调用'));

        final maxPrompt = guard.getForcedConclusionPrompt(status: LoopCheckStatus.maxRoundsReached);
        expect(maxPrompt, contains('已达到工具调用轮次上限（最大 8 轮）'));
      });

      test('T4.5: reset() fully purges history and restores initial state', () {
        final guard = AgentLoopGuard();
        guard.recordAndCheck('tool_1', {'a': 1});
        guard.recordAndCheck('tool_2', {'b': 2});
        expect(guard.callCount, equals(2));
        expect(guard.history.length, equals(2));

        guard.reset();
        expect(guard.callCount, equals(0));
        expect(guard.history.isEmpty, isTrue);
        expect(guard.lastVerdict, isNull);
        expect(guard.hasTriggeredLoop, isFalse);
      });

      test('T4.6: recordAndCheck, recordToolCall and checkNextCall consistency', () {
        final guard = AgentLoopGuard();
        guard.recordToolCall('tool_init', {'init': true});
        expect(guard.callCount, equals(1));

        final checkResult = guard.checkNextCall('tool_init', {'init': true}, 1);
        expect(checkResult.isAllowed, isTrue);
        // checkNextCall does not mutate history
        expect(guard.callCount, equals(1));

        final recordResult = guard.recordAndCheck('tool_init', {'init': true}, 1);
        expect(recordResult.isAllowed, isTrue);
        expect(guard.callCount, equals(2));

        final thirdResult = guard.recordAndCheck('tool_init', {'init': true}, 2);
        expect(thirdResult.isBlocked, isTrue);
        expect(thirdResult.isTerminated, isTrue);
        expect(thirdResult.toolName, equals('tool_init'));
        expect(thirdResult.signature, isNotNull);
        expect(guard.lastTerminationReason, contains('连续 3 次'));
        expect(guard.getTerminationReason(), contains('连续 3 次'));
      });
    });
  });
}
