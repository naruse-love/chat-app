import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/services/rune_safe_json_truncator.dart';

void main() {
  group('RuneSafeJsonTruncator String Truncation Tests', () {
    test('returns exact string if runes count is within limit', () {
      const text = 'Hello Flutter 🚀';
      final result = RuneSafeJsonTruncator.truncateString(text, 50);
      expect(result, equals(text));
    });

    test('handles empty or zero limit inputs gracefully', () {
      expect(RuneSafeJsonTruncator.truncateString('', 10), equals(''));
      expect(RuneSafeJsonTruncator.truncateString('hello', 0), equals(''));
      expect(RuneSafeJsonTruncator.truncateString('hello', -5), equals(''));
    });

    test('never splits Unicode surrogate pairs (emojis / CJK / flags)', () {
      // 👩‍👩‍👧‍👦 has multiple code units and runes
      const emojiString = '用户A: 😀😁😂🤣😃😄 (完成度 100%)';
      // Truncate at exactly 8 runes
      final truncated = RuneSafeJsonTruncator.truncateString(emojiString, 8, suffix: '...');
      expect(truncated.endsWith('...'), isTrue);

      // Verify no lone surrogates
      expect(() => utf8.encode(truncated), returnsNormally);
      expect(truncated.startsWith('用户A: 😀😁'), isTrue);
    });

    test('custom suffix is properly appended', () {
      const text = '这是一段非常长的中文描述内容测试用例';
      final result = RuneSafeJsonTruncator.truncateString(text, 6, suffix: '[MORE]');
      expect(result, equals('这是一段非常[MORE]'));
    });
  });

  group('RuneSafeJsonTruncator JSON Truncation and Repair Tests', () {
    test('returns original JSON if within limit', () {
      final jsonStr = json.encode({'title': 'test', 'count': 42});
      final result = RuneSafeJsonTruncator.truncateJsonString(jsonStr, 100);
      expect(result, equals(jsonStr));
    });

    test('semantic object truncation for valid JSON Map and List', () {
      final largeMap = {
        'short': 'ok',
        'longString': 'A' * 500,
        'nested': {
          'items': List.generate(30, (i) => 'Item $i'),
        }
      };

      final jsonStr = json.encode(largeMap);
      final truncated = RuneSafeJsonTruncator.truncateJsonString(jsonStr, 50);

      // Must be valid parseable JSON
      expect(() => json.decode(truncated), returnsNormally);
      final parsed = json.decode(truncated) as Map<String, dynamic>;
      expect(parsed.containsKey('short'), isTrue);
    });

    test('repairs unclosed quotes, brackets, and braces on incomplete stream JSON', () {
      // Incomplete raw JSON string cut in the middle of a string
      const brokenJson = '{"status": "success", "results": [{"id": 1, "name": "DeepSeek-R1", "desc": "Very long reason';
      final repaired = RuneSafeJsonTruncator.truncateJsonString(brokenJson, 60);

      // Must be syntactically valid parseable JSON
      expect(() => json.decode(repaired), returnsNormally);
      final decoded = json.decode(repaired);
      expect(decoded, isA<Map>());
    });

    test('handles list truncation exceeding maxItems limit', () {
      final list = List.generate(40, (i) => {'index': i, 'val': 'Value $i'});
      final truncated = RuneSafeJsonTruncator.truncateObject(list, 100) as List;
      expect(truncated.length, equals(21)); // 20 items + 1 truncation marker
      expect(truncated.last, isA<Map>());
      expect(truncated.last['__truncated__'], contains('剩余 20 项已省略'));
    });
  });
}
