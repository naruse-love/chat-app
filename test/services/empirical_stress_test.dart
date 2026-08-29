import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/services/tools/math_eval_tool.dart';
import 'package:chat/services/tools/time_calculator_tool.dart';

void main() {
  group('Challenger 1 Empirical Stress Tests: MathEvalTool', () {
    const mathTool = MathEvalTool();

    test('Parentheses stress test: 60 levels of nested parentheses', () async {
      final open = '(' * 60;
      final close = ')' * 60;
      final expr = '$open 2 + 3 $close * 4';
      final res = await mathTool.execute({'expression': expr});
      expect(res.success, isTrue);
      expect(res.rawData?['formattedResult'], '20');
    });

    test('Operator associativity: power is right-associative (2 ^ 3 ^ 2 == 512, 2 ** 3 ** 2 == 512)', () async {
      final res1 = await mathTool.execute({'expression': '2 ^ 3 ^ 2'});
      expect(res1.success, isTrue);
      expect(res1.rawData?['formattedResult'], '512');

      final res2 = await mathTool.execute({'expression': '2 ** 3 ** 2'});
      expect(res2.success, isTrue);
      expect(res2.rawData?['formattedResult'], '512');

      // Left associative minus & divide
      final res3 = await mathTool.execute({'expression': '20 - 5 - 3'});
      expect(res3.success, isTrue);
      expect(res3.rawData?['formattedResult'], '12');

      final res4 = await mathTool.execute({'expression': '48 / 6 / 2'});
      expect(res4.success, isTrue);
      expect(res4.rawData?['formattedResult'], '4');
    });

    test('Unary operators & factorials chaining: -(3!) and 3!!', () async {
      final res1 = await mathTool.execute({'expression': '-3!'});
      expect(res1.success, isTrue);
      expect(res1.rawData?['formattedResult'], '-6');

      final res2 = await mathTool.execute({'expression': '3!!'});
      expect(res2.success, isTrue); // (3!)! = 6! = 720
      expect(res2.rawData?['formattedResult'], '720');

      final res3 = await mathTool.execute({'expression': '0!'});
      expect(res3.success, isTrue);
      expect(res3.rawData?['formattedResult'], '1');

      final res4 = await mathTool.execute({'expression': '170!'});
      expect(res4.success, isTrue);
      expect(res4.rawData?['result'], isA<double>());

      final res5 = await mathTool.execute({'expression': '171!'});
      expect(res5.success, isFalse);
      expect(res5.errorMessage, contains('>170!'));
    });

    test('Trig and Advanced Math functions with boundary and edge values', () async {
      // sqrt(0), sqrt(-4)
      final sqrt0 = await mathTool.execute({'expression': 'sqrt(0)'});
      expect(sqrt0.success, isTrue);
      expect(sqrt0.rawData?['formattedResult'], '0');

      final sqrtNeg = await mathTool.execute({'expression': 'sqrt(-4)'});
      expect(sqrtNeg.success, isFalse);
      expect(sqrtNeg.errorMessage, contains('负数不能在实数范围内开平方根'));

      // cbrt(8), cbrt(-8), cbrt(-27)
      final cbrtPos = await mathTool.execute({'expression': 'cbrt(8)'});
      expect(cbrtPos.success, isTrue);
      expect(cbrtPos.rawData?['formattedResult'], '2');

      final cbrtNeg = await mathTool.execute({'expression': 'cbrt(-8)'});
      expect(cbrtNeg.success, isTrue);
      expect(cbrtNeg.rawData?['formattedResult'], '-2');

      final cbrtNeg27 = await mathTool.execute({'expression': 'cbrt(-27)'});
      expect(cbrtNeg27.success, isTrue);
      expect(cbrtNeg27.rawData?['formattedResult'], '-3');

      // abs, floor, ceil, round
      final roundDec = await mathTool.execute({'expression': 'round(3.14159265, 4)'});
      expect(roundDec.success, isTrue);
      expect(roundDec.rawData?['formattedResult'], '3.1416');

      final floorNeg = await mathTool.execute({'expression': 'floor(-3.2)'});
      expect(floorNeg.success, isTrue);
      expect(floorNeg.rawData?['formattedResult'], '-4');

      final ceilNeg = await mathTool.execute({'expression': 'ceil(-3.2)'});
      expect(ceilNeg.success, isTrue);
      expect(ceilNeg.rawData?['formattedResult'], '-3');

      // Trig domains
      final asinOk = await mathTool.execute({'expression': 'asin(1)'});
      expect(asinOk.success, isTrue);
      expect((asinOk.rawData?['result'] as double) - math.pi / 2, lessThan(1e-9));

      final asinOut = await mathTool.execute({'expression': 'asin(1.001)'});
      expect(asinOut.success, isFalse);
      expect(asinOut.errorMessage, contains('[-1, 1]'));

      final acosOut = await mathTool.execute({'expression': 'acos(-1.5)'});
      expect(acosOut.success, isFalse);
      expect(acosOut.errorMessage, contains('[-1, 1]'));

      // Logs
      final lnE = await mathTool.execute({'expression': 'ln(e)'});
      expect(lnE.success, isTrue);
      expect(lnE.rawData?['formattedResult'], '1');

      final ln0 = await mathTool.execute({'expression': 'ln(0)'});
      expect(ln0.success, isFalse);
      expect(ln0.errorMessage, contains('对数真数必须大于零'));

      final logCustom = await mathTool.execute({'expression': 'log(8, 2)'});
      expect(logCustom.success, isTrue);
      expect(logCustom.rawData?['formattedResult'], '3');

      final logBase1 = await mathTool.execute({'expression': 'log(10, 1)'});
      expect(logBase1.success, isFalse);
      expect(logBase1.errorMessage, contains('对数参数无效'));
    });

    test('Statistical functions: empty list, single item, large list, and varargs', () async {
      // Empty list
      final meanEmpty = await mathTool.execute({'expression': 'mean([])'});
      expect(meanEmpty.success, isFalse);
      expect(meanEmpty.errorMessage, contains('参数列表不能为空'));

      final stddevEmpty = await mathTool.execute({'expression': 'stddev([])'});
      expect(stddevEmpty.success, isFalse);
      expect(stddevEmpty.errorMessage, contains('参数列表不能为空'));

      // Single item list
      final meanSingle = await mathTool.execute({'expression': 'mean([42])'});
      expect(meanSingle.success, isTrue);
      expect(meanSingle.rawData?['formattedResult'], '42');

      final medianSingle = await mathTool.execute({'expression': 'median([42])'});
      expect(medianSingle.success, isTrue);
      expect(medianSingle.rawData?['formattedResult'], '42');

      final modeSingle = await mathTool.execute({'expression': 'mode([42])'});
      expect(modeSingle.success, isTrue);
      expect(modeSingle.rawData?['formattedResult'], '42');

      final varSingle = await mathTool.execute({'expression': 'variance([42])'});
      expect(varSingle.success, isTrue);
      expect(varSingle.rawData?['formattedResult'], '0');

      final stddevSingle = await mathTool.execute({'expression': 'stddev([42])'});
      expect(stddevSingle.success, isTrue);
      expect(stddevSingle.rawData?['formattedResult'], '0');

      // Two items
      final medianTwo = await mathTool.execute({'expression': 'median([10, 20])'});
      expect(medianTwo.success, isTrue);
      expect(medianTwo.rawData?['formattedResult'], '15');

      final varTwo = await mathTool.execute({'expression': 'variance([10, 20])'});
      expect(varTwo.success, isTrue);
      expect(varTwo.rawData?['formattedResult'], '25');

      final stddevTwo = await mathTool.execute({'expression': 'stddev([10, 20])'});
      expect(stddevTwo.success, isTrue);
      expect(stddevTwo.rawData?['formattedResult'], '5');

      // Large dataset: 1000 sequential numbers [1..1000]
      final numbers = List.generate(1000, (i) => i + 1);
      final largeExpr = 'sum([${numbers.join(',')}])';
      final largeRes = await mathTool.execute({'expression': largeExpr});
      expect(largeRes.success, isTrue);
      expect(largeRes.rawData?['formattedResult'], '500500'); // 1000 * 1001 / 2

      final largeMean = await mathTool.execute({'expression': 'mean([${numbers.join(',')}])'});
      expect(largeMean.success, isTrue);
      expect(largeMean.rawData?['formattedResult'], '500.5');

      // Varargs syntax
      final varargsMean = await mathTool.execute({'expression': 'mean(10, 20, 30, 40, 50)'});
      expect(varargsMean.success, isTrue);
      expect(varargsMean.rawData?['formattedResult'], '30');

      final varargsMin = await mathTool.execute({'expression': 'min(99, 12, 45, 8, 77)'});
      expect(varargsMin.success, isTrue);
      expect(varargsMin.rawData?['formattedResult'], '8');

      final varargsMax = await mathTool.execute({'expression': 'max(99, 12, 45, 8, 77)'});
      expect(varargsMax.success, isTrue);
      expect(varargsMax.rawData?['formattedResult'], '99');
    });

    test('Division by zero and modulo by zero detection', () async {
      final div0 = await mathTool.execute({'expression': '10 / 0'});
      expect(div0.success, isFalse);
      expect(div0.errorMessage, contains('除数不能为零'));

      final mod0 = await mathTool.execute({'expression': '10 % 0'});
      expect(mod0.success, isFalse);
      expect(mod0.errorMessage, contains('模运算除数不能为零'));

      final nestedDiv0 = await mathTool.execute({'expression': '100 / (5 * 2 - 10)'});
      expect(nestedDiv0.success, isFalse);
      expect(nestedDiv0.errorMessage, contains('除数不能为零'));
    });

    test('Unit conversion: extreme conversions, Chinese aliases, and invalid units', () async {
      // Temperature
      final c2k = await mathTool.execute({'expression': 'convert(0, "c", "k")'});
      expect(c2k.success, isTrue);
      expect(c2k.rawData?['formattedResult'], '273.15');

      final f2c = await mathTool.execute({'expression': 'convert(32, "f", "c")'});
      expect(f2c.success, isTrue);
      expect(f2c.rawData?['formattedResult'], '0');

      final c2fNeg40 = await mathTool.execute({'expression': 'convert(-40, "c", "f")'});
      expect(c2fNeg40.success, isTrue);
      expect(c2fNeg40.rawData?['formattedResult'], '-40');

      // Chinese units
      final jin2g = await mathTool.execute({'expression': 'convert(2, "市斤", "克")'});
      expect(jin2g.success, isTrue);
      expect(jin2g.rawData?['formattedResult'], '1000');

      final liang2g = await mathTool.execute({'expression': 'convert(5, "两", "克")'});
      expect(liang2g.success, isTrue);
      expect(liang2g.rawData?['formattedResult'], '250');

      final km2m = await mathTool.execute({'expression': 'convert(3.5, "公里", "米")'});
      expect(km2m.success, isTrue);
      expect(km2m.rawData?['formattedResult'], '3500');

      final storage = await mathTool.execute({'expression': 'convert(1, "tb", "gb")'});
      expect(storage.success, isTrue);
      expect(storage.rawData?['formattedResult'], '1024');

      // Incompatible category conversion
      final cross = await mathTool.execute({'expression': 'convert(100, "km", "kg")'});
      expect(cross.success, isFalse);
      expect(cross.errorMessage, contains('无法在不同类别单位间转换'));

      // Unknown units
      final unknownUnit = await mathTool.execute({'expression': 'convert(100, "lightyear", "m")'});
      expect(unknownUnit.success, isFalse);
      expect(unknownUnit.errorMessage, contains('不支持的单位'));

      // Wrong argument count
      final wrongArg = await mathTool.execute({'expression': 'convert(100, "km")'});
      expect(wrongArg.success, isFalse);
      expect(wrongArg.errorMessage, contains('convert 函数需要 3 个参数'));
    });

    test('Syntax error robustness: unmatched symbols, unclosed strings, and bad tokens', () async {
      final unclosedParen = await mathTool.execute({'expression': '(3 + 5 * 2'});
      expect(unclosedParen.success, isFalse);
      expect(unclosedParen.errorMessage, contains('缺少闭合括号'));

      final unclosedBracket = await mathTool.execute({'expression': 'mean([1, 2, 3'});
      expect(unclosedBracket.success, isFalse);
      expect(unclosedBracket.errorMessage, contains('缺少闭合方括号'));

      final unclosedStr = await mathTool.execute({'expression': 'convert(10, \'km, \'m\')'});
      expect(unclosedStr.success, isFalse);
      expect(unclosedStr.errorMessage, contains('字符串未闭合'));

      final empty = await mathTool.execute({'expression': '   '});
      expect(empty.success, isFalse);
      expect(empty.errorMessage, contains('表达式不能为空'));

      final extraTokens = await mathTool.execute({'expression': '2 + 3 4'});
      expect(extraTokens.success, isFalse);
      expect(extraTokens.errorMessage, contains('语法错误'));
    });
  });

  group('Challenger 1 Empirical Stress Tests: TimeCalculatorTool', () {
    final fixedTime = DateTime.utc(2024, 2, 29, 12, 0, 0); // Leap year leap day
    final tool = TimeCalculatorTool(nowProvider: () => fixedTime);

    test('Leap year edge cases: Feb 29 arithmetic and end-of-month day clamping', () async {
      // 2024-02-29 + 1y -> 2025-02-28
      final res1 = await tool.execute({
        'operation': 'offset',
        'datetime': '2024-02-29 15:30:00',
        'offset': '+1y',
        'timezone': 'UTC',
      });
      expect(res1.success, isTrue);
      expect(res1.rawData?['resultDatetime'], '2025-02-28 15:30:00');

      // 2024-02-29 - 1y -> 2023-02-28
      final res2 = await tool.execute({
        'operation': 'offset',
        'datetime': '2024-02-29 15:30:00',
        'offset': '-1y',
        'timezone': 'UTC',
      });
      expect(res2.success, isTrue);
      expect(res2.rawData?['resultDatetime'], '2023-02-28 15:30:00');

      // 2024-02-29 + 4y -> 2028-02-29 (2028 is leap year)
      final res3 = await tool.execute({
        'operation': 'offset',
        'datetime': '2024-02-29 15:30:00',
        'offset': '+4y',
        'timezone': 'UTC',
      });
      expect(res3.success, isTrue);
      expect(res3.rawData?['resultDatetime'], '2028-02-29 15:30:00');

      // 2024-01-31 + 1M -> 2024-02-29 (leap year Feb has 29 days)
      final res4 = await tool.execute({
        'operation': 'offset',
        'datetime': '2024-01-31 10:00:00',
        'offset': '+1M',
        'timezone': 'UTC',
      });
      expect(res4.success, isTrue);
      expect(res4.rawData?['resultDatetime'], '2024-02-29 10:00:00');

      // 2023-01-31 + 1M -> 2023-02-28 (non-leap year Feb has 28 days)
      final res5 = await tool.execute({
        'operation': 'offset',
        'datetime': '2023-01-31 10:00:00',
        'offset': '+1M',
        'timezone': 'UTC',
      });
      expect(res5.success, isTrue);
      expect(res5.rawData?['resultDatetime'], '2023-02-28 10:00:00');

      // 2024-03-31 - 1M -> 2024-02-29
      final res6 = await tool.execute({
        'operation': 'offset',
        'datetime': '2024-03-31 10:00:00',
        'offset': '-1M',
        'timezone': 'UTC',
      });
      expect(res6.success, isTrue);
      expect(res6.rawData?['resultDatetime'], '2024-02-29 10:00:00');
    });

    test('Negative and compound offsets with Chinese and English units', () async {
      // Compound negative offset: -5h30m
      final res1 = await tool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': '-5h30m',
        'timezone': 'UTC',
      });
      expect(res1.success, isTrue);
      expect(res1.rawData?['resultDatetime'], '2026-08-28 06:30:00');

      // Compound positive offset: +3d12h45s
      final res2 = await tool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': '+3d12h45s',
        'timezone': 'UTC',
      });
      expect(res2.success, isTrue);
      expect(res2.rawData?['resultDatetime'], '2026-08-31 24:00:45' == '2026-09-01 00:00:45' ? '2026-09-01 00:00:45' : '2026-09-01 00:00:45');
      expect(res2.rawData?['resultDatetime'], '2026-09-01 00:00:45');

      // Chinese units: -2天4小时30分钟
      final res3 = await tool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': '-2天4小时30分钟',
        'timezone': 'UTC',
      });
      expect(res3.success, isTrue);
      expect(res3.rawData?['resultDatetime'], '2026-08-26 07:30:00');
    });

    test('Extreme timezone conversions & raw offsets (e.g. +14:00 to -12:00, 26h diff)', () async {
      // Convert between UTC+14 and UTC-12
      final res = await tool.execute({
        'operation': 'convert',
        'fromTimezone': '+14:00',
        'toTimezone': '-12:00',
        'datetime': '2026-08-29 10:00:00',
      });
      expect(res.success, isTrue);
      expect(res.rawData?['fromOffsetMinutes'], 840); // 14 * 60
      expect(res.rawData?['toOffsetMinutes'], -720); // -12 * 60
      // 2026-08-29 10:00:00 (+14) is 2026-08-28 20:00:00 UTC, which is 2026-08-28 08:00:00 (-12)
      expect(res.rawData?['targetDatetime'], '2026-08-28 08:00:00');
    });

    test('Duration calculation: forward, reverse (negative), and timestamp inputs', () async {
      // Forward duration
      final res1 = await tool.execute({
        'operation': 'duration',
        'time1': '2026-08-28 08:00:00',
        'time2': '2026-08-30 11:30:15',
      });
      expect(res1.success, isTrue);
      expect(res1.rawData?['isNegative'], isFalse);
      expect(res1.rawData?['days'], 2);
      expect(res1.rawData?['hours'], 3);
      expect(res1.rawData?['minutes'], 30);
      expect(res1.rawData?['seconds'], 15);
      expect(res1.rawData?['differenceText'], '2天 3小时 30分钟 15秒');

      // Reverse (negative) duration
      final res2 = await tool.execute({
        'operation': 'duration',
        'time1': '2026-08-30 11:30:15',
        'time2': '2026-08-28 08:00:00',
      });
      expect(res2.success, isTrue);
      expect(res2.rawData?['isNegative'], isTrue);
      expect(res2.rawData?['differenceText'], '负 2天 3小时 30分钟 15秒');
      expect(res2.rawData?['totalDays'], -2);

      // Milliseconds timestamp duration
      final res3 = await tool.execute({
        'operation': 'duration',
        'time1': '1700000000000',
        'time2': '1700003600000', // 1 hour difference (3600s)
      });
      expect(res3.success, isTrue);
      expect(res3.rawData?['hours'], 1);
      expect(res3.rawData?['totalSeconds'], 3600);
    });

    test('Error handling: invalid operations, missing parameters, bad timezones, and malformed dates', () async {
      // Invalid operation
      final res1 = await tool.execute({'operation': 'magic_time'});
      expect(res1.success, isFalse);
      expect(res1.errorMessage, contains('不支持的时间计算操作'));

      // Unknown timezone
      final res2 = await tool.execute({'operation': 'now', 'timezone': 'Mars/Olympus'});
      expect(res2.success, isFalse);
      expect(res2.errorMessage, contains('未知时区'));

      // Missing offset in offset operation
      final res3 = await tool.execute({'operation': 'offset'});
      expect(res3.success, isFalse);
      expect(res3.errorMessage, contains('缺少必需的 "offset" 参数'));

      // Missing time1/time2 in duration operation
      final res4 = await tool.execute({'operation': 'duration', 'time1': '2026-08-28'});
      expect(res4.success, isFalse);
      expect(res4.errorMessage, contains('需要提供 "time1" 和 "time2" 参数'));

      // Malformed datetime string
      final res5 = await tool.execute({'operation': 'offset', 'datetime': 'not-a-valid-date', 'offset': '+1d'});
      expect(res5.success, isFalse);
      expect(res5.errorMessage, contains('无法解析时间格式'));

      // Invalid offset string
      final res6 = await tool.execute({'operation': 'offset', 'datetime': '2026-08-28 12:00:00', 'offset': '+invalid'});
      expect(res6.success, isFalse);
      expect(res6.errorMessage, contains('无法解析相对偏移量'));
    });

    test('Century leap year rules: 1900 (non-leap) vs 2000 (leap)', () async {
      // 1900 is not leap year -> 1900-02-28 + 1d = 1900-03-01
      final res1900 = await tool.execute({
        'operation': 'offset',
        'datetime': '1900-02-28 12:00:00',
        'offset': '+1d',
        'timezone': 'UTC',
      });
      expect(res1900.success, isTrue);
      expect(res1900.rawData?['resultDatetime'], '1900-03-01 12:00:00');

      // 2000 is leap year -> 2000-02-28 + 1d = 2000-02-29
      final res2000 = await tool.execute({
        'operation': 'offset',
        'datetime': '2000-02-28 12:00:00',
        'offset': '+1d',
        'timezone': 'UTC',
      });
      expect(res2000.success, isTrue);
      expect(res2000.rawData?['resultDatetime'], '2000-02-29 12:00:00');
    });

    test('Cross-year month boundary arithmetic & compound offsets', () async {
      // 2024-12-31 + 2M -> 2025-02-28
      final res1 = await tool.execute({
        'operation': 'offset',
        'datetime': '2024-12-31 00:00:00',
        'offset': '+2M',
        'timezone': 'UTC',
      });
      expect(res1.success, isTrue);
      expect(res1.rawData?['resultDatetime'], '2025-02-28 00:00:00');

      // Compound offset with all units combined: +1y2M3w4d5h6m7s
      // 2020-01-01 00:00:00 -> +1y (2021-01-01) -> +2M (2021-03-01) -> +21d (2021-03-22) -> +4d (2021-03-26) -> +5h6m7s
      final res2 = await tool.execute({
        'operation': 'offset',
        'datetime': '2020-01-01 00:00:00',
        'offset': '+1y2M3w4d5h6m7s',
        'timezone': 'UTC',
      });
      expect(res2.success, isTrue);
      expect(res2.rawData?['resultDatetime'], '2021-03-26 05:06:07');

      // Zero offset
      final res3 = await tool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:34:56',
        'offset': '+0d',
        'timezone': 'UTC',
      });
      expect(res3.success, isTrue);
      expect(res3.rawData?['resultDatetime'], '2026-08-28 12:34:56');
    });

    test('All timezone alias families (Chinese, English abbreviations, and canonical IANA)', () async {
      const aliasMap = {
        '北京': 'Asia/Shanghai',
        '上海': 'Asia/Shanghai',
        '香港': 'Asia/Hong_Kong',
        '台北': 'Asia/Taipei',
        '东京': 'Asia/Tokyo',
        '首尔': 'Asia/Seoul',
        '伦敦': 'Europe/London',
        '巴黎': 'Europe/Paris',
        '柏林': 'Europe/Berlin',
        '纽约': 'America/New_York',
        '洛杉矶': 'America/Los_Angeles',
        '悉尼': 'Australia/Sydney',
        'PST': 'America/Los_Angeles',
        'EST': 'America/New_York',
        'CST': 'Asia/Shanghai',
        'JST': 'Asia/Tokyo',
        'GMT': 'UTC',
        'UTC': 'UTC',
        'UTC+8': 'UTC+08:00',
        '+08:00': 'UTC+08:00',
        '-05:00': 'UTC-05:00',
      };

      for (final entry in aliasMap.entries) {
        final res = await tool.execute({
          'operation': 'now',
          'timezone': entry.key,
        });
        expect(res.success, isTrue, reason: 'Failed for timezone alias: ${entry.key}');
        expect(res.rawData?['timezone'], entry.value, reason: 'Mismatch canonical name for alias: ${entry.key}');
      }
    });

  });
}
