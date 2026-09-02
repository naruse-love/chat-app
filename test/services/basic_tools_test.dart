import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/tool/tool.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/tools/math_eval_tool.dart';
import 'package:chat/services/tools/time_calculator_tool.dart';
import 'package:chat/services/tools/weather_query_tool.dart';

/// Mock HTTP Adapter for Dio to intercept Open-Meteo and Wikipedia requests deterministically.
class MockHttpClientAdapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(RequestOptions options) handler;

  MockHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = handler(options);

    final statusCode = result['statusCode'] as int? ?? 200;
    final data = result['data'];
    final headers = (result['headers'] as Map<String, List<String>>?) ??
        {
          'content-type': ['application/json; charset=utf-8'],
        };

    if (result['throwDioException'] == true) {
      throw DioException(
        requestOptions: options,
        type: result['dioExceptionType'] as DioExceptionType? ?? DioExceptionType.badResponse,
        response: Response(
          requestOptions: options,
          statusCode: statusCode,
          data: data,
        ),
      );
    }

    final jsonString = data is String ? data : jsonEncode(data);
    final responseBytes = utf8.encode(jsonString);

    return ResponseBody.fromBytes(
      responseBytes,
      statusCode,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('MathEvalTool Tests', () {
    const mathTool = MathEvalTool();

    test('Tool metadata and OpenAI schema export', () {
      expect(mathTool.name, equals('math_eval'));
      expect(mathTool.displayName, equals('数学计算器'));
      expect(mathTool.securityLevel, equals(ToolSecurityLevel.safe));
      expect(mathTool.parameters.length, equals(1));
      expect(mathTool.parameters.first.name, equals('expression'));

      final schema = mathTool.toOpenAiSchema();
      expect(schema['type'], equals('function'));
      expect(schema['function']['name'], equals('math_eval'));
      expect(schema['function']['parameters']['required'], contains('expression'));
    });

    test('Basic arithmetic operations with operator precedence', () async {
      final res1 = await mathTool.execute({'expression': '(3 + 5) * 2 ^ 3'});
      expect(res1.success, isTrue);
      expect(res1.rawData['result'], equals(64));
      expect(res1.content, contains('64'));

      final res2 = await mathTool.execute({'expression': '10 + 20 / 4 - 3 * 2'});
      expect(res2.success, isTrue);
      expect(res2.rawData['result'], equals(9));

      final res3 = await mathTool.execute({'expression': '100 % 7'});
      expect(res3.success, isTrue);
      expect(res3.rawData['result'], equals(2));

      // Right-associative exponentiation: 2 ^ 3 ^ 2 = 2 ^ 9 = 512
      final res4 = await mathTool.execute({'expression': '2 ^ 3 ^ 2'});
      expect(res4.success, isTrue);
      expect(res4.rawData['result'], equals(512));

      // Python style ** power operator
      final res5 = await mathTool.execute({'expression': '3 ** 3'});
      expect(res5.success, isTrue);
      expect(res5.rawData['result'], equals(27));
    });

    test('Unary operators, floating point, and scientific notation', () async {
      final res1 = await mathTool.execute({'expression': '-5 + +3'});
      expect(res1.success, isTrue);
      expect(res1.rawData['result'], equals(-2));

      final res2 = await mathTool.execute({'expression': '0.1 + 0.2'});
      expect(res2.success, isTrue);
      final double val = (res2.rawData['result'] as num).toDouble();
      expect(val, closeTo(0.3, 0.0001));

      final res3 = await mathTool.execute({'expression': '1e3 * 2.5e-2'});
      expect(res3.success, isTrue);
      expect(res3.rawData['result'], equals(25));
    });

    test('Trigonometric, logarithmic, and advanced math functions', () async {
      final sqrtRes = await mathTool.execute({'expression': 'sqrt(16)'});
      expect(sqrtRes.success, isTrue);
      expect(sqrtRes.rawData['result'], equals(4.0));

      final cbrtRes = await mathTool.execute({'expression': 'cbrt(27)'});
      expect(cbrtRes.success, isTrue);
      expect((cbrtRes.rawData['result'] as num).toDouble(), closeTo(3.0, 0.0001));

      final sinRes = await mathTool.execute({'expression': 'sin(pi / 2)'});
      expect(sinRes.success, isTrue);
      expect((sinRes.rawData['result'] as num).toDouble(), closeTo(1.0, 0.0001));

      final cosRes = await mathTool.execute({'expression': 'cos(0)'});
      expect(cosRes.success, isTrue);
      expect((cosRes.rawData['result'] as num).toDouble(), closeTo(1.0, 0.0001));

      final tanRes = await mathTool.execute({'expression': 'tan(pi / 4)'});
      expect(tanRes.success, isTrue);
      expect((tanRes.rawData['result'] as num).toDouble(), closeTo(1.0, 0.0001));

      final expRes = await mathTool.execute({'expression': 'exp(1)'});
      expect(expRes.success, isTrue);
      expect((expRes.rawData['result'] as num).toDouble(), closeTo(2.71828, 0.001));

      final lnRes = await mathTool.execute({'expression': 'ln(e)'});
      expect(lnRes.success, isTrue);
      expect((lnRes.rawData['result'] as num).toDouble(), closeTo(1.0, 0.0001));

      final log10Res = await mathTool.execute({'expression': 'log10(100)'});
      expect(log10Res.success, isTrue);
      expect((log10Res.rawData['result'] as num).toDouble(), closeTo(2.0, 0.0001));

      final log2Res = await mathTool.execute({'expression': 'log2(8)'});
      expect(log2Res.success, isTrue);
      expect((log2Res.rawData['result'] as num).toDouble(), closeTo(3.0, 0.0001));

      final absRes = await mathTool.execute({'expression': 'abs(-42.5)'});
      expect(absRes.success, isTrue);
      expect(absRes.rawData['result'], equals(42.5));

      final roundRes = await mathTool.execute({'expression': 'round(3.14159, 2)'});
      expect(roundRes.success, isTrue);
      expect(roundRes.rawData['result'], equals(3.14));

      final floorRes = await mathTool.execute({'expression': 'floor(4.9)'});
      expect(floorRes.success, isTrue);
      expect(floorRes.rawData['result'], equals(4.0));

      final ceilRes = await mathTool.execute({'expression': 'ceil(4.1)'});
      expect(ceilRes.success, isTrue);
      expect(ceilRes.rawData['result'], equals(5.0));

      final factRes = await mathTool.execute({'expression': 'factorial(5)'});
      expect(factRes.success, isTrue);
      expect(factRes.rawData['result'], equals(120.0));

      final factRes2 = await mathTool.execute({'expression': '6!'});
      expect(factRes2.success, isTrue);
      expect(factRes2.rawData['result'], equals(720.0));
    });

    test('Statistical functions on list literals and multiple arguments', () async {
      // mean
      final meanRes = await mathTool.execute({'expression': 'mean([1, 2, 3, 4, 5])'});
      expect(meanRes.success, isTrue);
      expect(meanRes.rawData['result'], equals(3.0));

      final meanRes2 = await mathTool.execute({'expression': 'mean(10, 20, 30)'});
      expect(meanRes2.success, isTrue);
      expect(meanRes2.rawData['result'], equals(20.0));

      // stddev & variance: stddev([2, 4, 4, 4, 5, 5, 7, 9]) => 2.0
      final stddevRes = await mathTool.execute({'expression': 'stddev([2, 4, 4, 4, 5, 5, 7, 9])'});
      expect(stddevRes.success, isTrue);
      expect(stddevRes.rawData['result'], equals(2.0));

      final varRes = await mathTool.execute({'expression': 'variance([2, 4, 4, 4, 5, 5, 7, 9])'});
      expect(varRes.success, isTrue);
      expect(varRes.rawData['result'], equals(4.0));

      // median
      final medRes1 = await mathTool.execute({'expression': 'median([5, 1, 3])'});
      expect(medRes1.success, isTrue);
      expect(medRes1.rawData['result'], equals(3.0));

      final medRes2 = await mathTool.execute({'expression': 'median([1, 2, 3, 4])'});
      expect(medRes2.success, isTrue);
      expect(medRes2.rawData['result'], equals(2.5));

      // mode
      final modeRes = await mathTool.execute({'expression': 'mode([1, 2, 2, 3, 4])'});
      expect(modeRes.success, isTrue);
      expect(modeRes.rawData['result'], equals(2.0));

      // sum, min, max, count
      final sumRes = await mathTool.execute({'expression': 'sum([10, 20, 30])'});
      expect(sumRes.success, isTrue);
      expect(sumRes.rawData['result'], equals(60.0));

      final minRes = await mathTool.execute({'expression': 'min([4, 2, 8])'});
      expect(minRes.success, isTrue);
      expect(minRes.rawData['result'], equals(2.0));

      final maxRes = await mathTool.execute({'expression': 'max([4, 2, 8])'});
      expect(maxRes.success, isTrue);
      expect(maxRes.rawData['result'], equals(8.0));

      final countRes = await mathTool.execute({'expression': 'count([10, 20, 30, 40])'});
      expect(countRes.success, isTrue);
      expect(countRes.rawData['result'], equals(4.0));
    });

    test('Unit conversions across multiple categories', () async {
      // Temperature
      final c2f = await mathTool.execute({'expression': 'convert(37, "C", "F")'});
      expect(c2f.success, isTrue);
      expect((c2f.rawData['result'] as num).toDouble(), closeTo(98.6, 0.01));

      final f2c = await mathTool.execute({'expression': 'convert(212, "F", "C")'});
      expect(f2c.success, isTrue);
      expect((f2c.rawData['result'] as num).toDouble(), closeTo(100.0, 0.01));

      final c2k = await mathTool.execute({'expression': 'convert(0, "C", "K")'});
      expect(c2k.success, isTrue);
      expect((c2k.rawData['result'] as num).toDouble(), closeTo(273.15, 0.01));

      // Length
      final km2mi = await mathTool.execute({'expression': 'convert(100, "km", "mi")'});
      expect(km2mi.success, isTrue);
      expect((km2mi.rawData['result'] as num).toDouble(), closeTo(62.1371, 0.01));

      final m2cm = await mathTool.execute({'expression': 'convert(1.5, "m", "cm")'});
      expect(m2cm.success, isTrue);
      expect(m2cm.rawData['result'], equals(150.0));

      // Weight
      final kg2lb = await mathTool.execute({'expression': 'convert(1, "kg", "lb")'});
      expect(kg2lb.success, isTrue);
      expect((kg2lb.rawData['result'] as num).toDouble(), closeTo(2.20462, 0.01));

      final g2kg = await mathTool.execute({'expression': 'convert(1000, "g", "kg")'});
      expect(g2kg.success, isTrue);
      expect(g2kg.rawData['result'], equals(1.0));

      // Storage
      final mb2gb = await mathTool.execute({'expression': 'convert(1024, "MB", "GB")'});
      expect(mb2gb.success, isTrue);
      expect(mb2gb.rawData['result'], equals(1.0));

      final tb2gb = await mathTool.execute({'expression': 'convert(2, "TB", "GB")'});
      expect(tb2gb.success, isTrue);
      expect(tb2gb.rawData['result'], equals(2048.0));

      // Speed & Area
      final kph2mps = await mathTool.execute({'expression': 'convert(36, "km/h", "m/s")'});
      expect(kph2mps.success, isTrue);
      expect((kph2mps.rawData['result'] as num).toDouble(), closeTo(10.0, 0.01));

      final km2m2 = await mathTool.execute({'expression': 'convert(1, "km2", "m2")'});
      expect(km2m2.success, isTrue);
      expect(km2m2.rawData['result'], equals(1000000.0));
    });

    test('Chinese error diagnostics for edge cases and syntax errors', () async {
      // Empty
      final emptyRes = await mathTool.execute({'expression': ''});
      expect(emptyRes.success, isFalse);
      expect(emptyRes.errorMessage, contains('表达式不能为空'));

      // Divide by zero
      final divZero = await mathTool.execute({'expression': '10 / 0'});
      expect(divZero.success, isFalse);
      expect(divZero.errorMessage, contains('除数不能为零'));

      // Negative sqrt
      final negSqrt = await mathTool.execute({'expression': 'sqrt(-9)'});
      expect(negSqrt.success, isFalse);
      expect(negSqrt.errorMessage, contains('负数不能在实数范围内开平方根'));

      // Log of non-positive
      final zeroLn = await mathTool.execute({'expression': 'ln(0)'});
      expect(zeroLn.success, isFalse);
      expect(zeroLn.errorMessage, contains('对数真数必须大于零'));

      // Syntax error (unclosed paren)
      final unclosed = await mathTool.execute({'expression': '(3 + 5 * 2'});
      expect(unclosed.success, isFalse);
      expect(unclosed.errorMessage, contains('缺少闭合括号'));

      // Unknown identifier
      final unknownFunc = await mathTool.execute({'expression': 'unsupported_func(123)'});
      expect(unknownFunc.success, isFalse);
      expect(unknownFunc.errorMessage, contains('未知函数或常量'));

      // Incompatible unit conversion
      final unitMismatch = await mathTool.execute({'expression': 'convert(10, "km", "kg")'});
      expect(unitMismatch.success, isFalse);
      expect(unitMismatch.errorMessage, contains('无法在不同类别单位间转换'));

      // Unsupported unit
      final unsupportedUnit = await mathTool.execute({'expression': 'convert(10, "foo_unit", "bar_unit")'});
      expect(unsupportedUnit.success, isFalse);
      expect(unsupportedUnit.errorMessage, contains('不支持的单位'));
    });
  });

  group('TimeCalculatorTool Tests', () {
    final fixedTime = DateTime.utc(2026, 8, 28, 12, 0, 0); // UTC 2026-08-28 12:00:00
    final timeTool = TimeCalculatorTool(nowProvider: () => fixedTime);

    test('Tool metadata and schema', () {
      expect(timeTool.name, equals('time_calculator'));
      expect(timeTool.displayName, equals('时区与时间计算器'));
      expect(timeTool.securityLevel, equals(ToolSecurityLevel.safe));
      expect(timeTool.parameters.any((p) => p.name == 'operation'), isTrue);
    });

    test('Operation "now" with various timezone aliases and offsets', () async {
      // Beijing / Asia/Shanghai (+08:00): 12:00 UTC -> 20:00
      final bjRes = await timeTool.execute({'operation': 'now', 'timezone': '北京'});
      expect(bjRes.success, isTrue);
      expect(bjRes.rawData['datetime'], equals('2026-08-28 20:00:00'));
      expect(bjRes.rawData['offsetString'], equals('+08:00'));
      expect(bjRes.rawData['weekday'], equals('星期五'));

      // Tokyo (+09:00): 12:00 UTC -> 21:00
      final tokyoRes = await timeTool.execute({'operation': 'now', 'timezone': '东京'});
      expect(tokyoRes.success, isTrue);
      expect(tokyoRes.rawData['datetime'], equals('2026-08-28 21:00:00'));

      // New York (-05:00): 12:00 UTC -> 07:00
      final nyRes = await timeTool.execute({'operation': 'now', 'timezone': '纽约'});
      expect(nyRes.success, isTrue);
      expect(nyRes.rawData['datetime'], equals('2026-08-28 07:00:00'));

      // London / UTC (0): 12:00
      final londonRes = await timeTool.execute({'operation': 'now', 'timezone': '伦敦'});
      expect(londonRes.success, isTrue);
      expect(londonRes.rawData['datetime'], equals('2026-08-28 12:00:00'));

      // Direct offset +08:00 and -05:00
      final offsetRes = await timeTool.execute({'operation': 'now', 'timezone': '+08:00'});
      expect(offsetRes.success, isTrue);
      expect(offsetRes.rawData['datetime'], equals('2026-08-28 20:00:00'));

      // Abbreviations PST (-08:00): 12:00 UTC -> 04:00
      final pstRes = await timeTool.execute({'operation': 'now', 'timezone': 'pst'});
      expect(pstRes.success, isTrue);
      expect(pstRes.rawData['datetime'], equals('2026-08-28 04:00:00'));
    });

    test('Operation "convert" between timezones', () async {
      final convertRes = await timeTool.execute({
        'operation': 'convert',
        'datetime': '2026-08-28 20:00:00',
        'fromTimezone': '北京',
        'toTimezone': '纽约',
      });
      expect(convertRes.success, isTrue);
      expect(convertRes.rawData['sourceDatetime'], equals('2026-08-28 20:00:00'));
      // Beijing 20:00 is 12:00 UTC, which is 07:00 in New York
      expect(convertRes.rawData['targetDatetime'], equals('2026-08-28 07:00:00'));
      expect(convertRes.content, contains('2026-08-28 07:00:00'));
    });

    test('Operation "offset" with relative durations', () async {
      // +3 days
      final plus3d = await timeTool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': '+3d',
        'timezone': 'Asia/Shanghai',
      });
      expect(plus3d.success, isTrue);
      expect(plus3d.rawData['resultDatetime'], equals('2026-08-31 12:00:00'));

      // -5h30m
      final minus5h30m = await timeTool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': '-5h30m',
      });
      expect(minus5h30m.success, isTrue);
      expect(minus5h30m.rawData['resultDatetime'], equals('2026-08-28 06:30:00'));

      // +1w (1 week = 7 days)
      final plus1w = await timeTool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': '+1w',
      });
      expect(plus1w.success, isTrue);
      expect(plus1w.rawData['resultDatetime'], equals('2026-09-04 12:00:00'));

      // +2M (2 months)
      final plus2M = await timeTool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': '+2M',
      });
      expect(plus2M.success, isTrue);
      expect(plus2M.rawData['resultDatetime'], equals('2026-10-28 12:00:00'));

      // -1y (1 year)
      final minus1y = await timeTool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': '-1y',
      });
      expect(minus1y.success, isTrue);
      expect(minus1y.rawData['resultDatetime'], equals('2025-08-28 12:00:00'));
    });

    test('Operation "duration" calculates difference between two datetimes', () async {
      final durRes = await timeTool.execute({
        'operation': 'duration',
        'time1': '2026-08-25 10:00:00',
        'time2': '2026-08-28 14:30:15',
      });
      expect(durRes.success, isTrue);
      expect(durRes.rawData['days'], equals(3));
      expect(durRes.rawData['hours'], equals(4));
      expect(durRes.rawData['minutes'], equals(30));
      expect(durRes.rawData['seconds'], equals(15));
      expect(durRes.rawData['differenceText'], equals('3天 4小时 30分钟 15秒'));
      expect(durRes.rawData['isNegative'], isFalse);

      // Negative duration
      final negDur = await timeTool.execute({
        'operation': 'duration',
        'time1': '2026-08-28 12:00:00',
        'time2': '2026-08-28 10:00:00',
      });
      expect(negDur.success, isTrue);
      expect(negDur.rawData['isNegative'], isTrue);
      expect(negDur.rawData['differenceText'], contains('负 2小时'));
    });

    test('Chinese error diagnostics for time calculation', () async {
      // Invalid operation
      final badOp = await timeTool.execute({'operation': 'invalid_operation'});
      expect(badOp.success, isFalse);
      expect(badOp.errorMessage, contains('不支持的时间计算操作'));

      // Unknown timezone
      final badTz = await timeTool.execute({'operation': 'now', 'timezone': 'Atlantis/Unknown'});
      expect(badTz.success, isFalse);
      expect(badTz.errorMessage, contains('未知时区或无法解析时区'));

      // Missing duration parameters
      final missingDur = await timeTool.execute({'operation': 'duration', 'time1': '2026-08-28'});
      expect(missingDur.success, isFalse);
      expect(missingDur.errorMessage, contains('需要提供 "time1" 和 "time2" 参数'));

      // Invalid date string
      final badDate = await timeTool.execute({
        'operation': 'offset',
        'datetime': 'invalid_date_format',
        'offset': '+3d',
      });
      expect(badDate.success, isFalse);
      expect(badDate.errorMessage, contains('无法解析时间格式'));

      // Invalid offset string
      final badOffset = await timeTool.execute({
        'operation': 'offset',
        'datetime': '2026-08-28 12:00:00',
        'offset': 'invalid_offset',
      });
      expect(badOffset.success, isFalse);
      expect(badOffset.errorMessage, contains('无法解析相对偏移量'));
    });
  });

  group('WeatherQueryTool Tests', () {
    test('Tool metadata and parameters', () {
      final weatherTool = WeatherQueryTool();
      expect(weatherTool.name, equals('weather_query'));
      expect(weatherTool.displayName, equals('天气查询'));
      expect(weatherTool.securityLevel, equals(ToolSecurityLevel.readOnly));
      expect(weatherTool.parameters.any((p) => p.name == 'city'), isTrue);
      expect(weatherTool.parameters.any((p) => p.name == 'forecastDays'), isTrue);
    });

    test('Successful weather query with mocked Open-Meteo response', () async {
      final mockDio = Dio();
      mockDio.httpClientAdapter = MockHttpClientAdapter((options) {
        final uri = options.uri.toString();
        if (uri.contains('geocoding-api.open-meteo.com')) {
          return {
            'statusCode': 200,
            'data': {
              'results': [
                {
                  'name': '北京',
                  'country': '中国',
                  'admin1': '北京市',
                  'latitude': 39.9075,
                  'longitude': 116.3972,
                }
              ]
            }
          };
        } else if (uri.contains('api.open-meteo.com/v1/forecast')) {
          return {
            'statusCode': 200,
            'data': {
              'current_weather': {
                'temperature': 26.5,
                'windspeed': 12.0,
                'winddirection': 180,
                'weathercode': 1,
                'time': '2026-08-28T12:00',
              },
              'hourly': {
                'time': ['2026-08-28T12:00'],
                'apparent_temperature': [27.2],
                'relative_humidity_2m': [58],
              },
              'daily': {
                'time': ['2026-08-28', '2026-08-29', '2026-08-30'],
                'weathercode': [1, 61, 95],
                'temperature_2m_max': [30.5, 27.0, 25.0],
                'temperature_2m_min': [20.0, 19.5, 18.0],
                'precipitation_sum': [0.0, 4.5, 18.0],
                'windspeed_10m_max': [15.0, 18.2, 22.0],
              }
            }
          };
        }
        return {'statusCode': 404, 'data': {}};
      });

      final tool = WeatherQueryTool(dio: mockDio);
      final result = await tool.execute({'city': '北京', 'forecastDays': 3});

      expect(result.success, isTrue);
      expect(result.rawData['location']['name'], equals('北京'));
      expect(result.rawData['current']['temperature'], equals(26.5));
      expect(result.rawData['current']['condition'], equals('大部晴朗'));
      expect(result.rawData['current']['icon'], equals('🌤️'));
      expect(result.rawData['daily'].length, equals(3));
      expect(result.content, contains('北京 (北京市, 中国) 实时天气与预报'));
      expect(result.content, contains('🌤️ 大部晴朗'));
      expect(result.content, contains('🌦️ 小雨'));
      expect(result.content, contains('⛈️ 雷暴'));
    });

    test('Handles city not found in geocoding', () async {
      final mockDio = Dio();
      mockDio.httpClientAdapter = MockHttpClientAdapter((options) {
        return {
          'statusCode': 200,
          'data': {'results': []},
        };
      });

      final tool = WeatherQueryTool(dio: mockDio);
      final result = await tool.execute({'city': 'NonExistentCityXYZ'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('未找到城市 "NonExistentCityXYZ" 的地理位置信息'));
    });

    test('Handles network timeout / 500 error gracefully', () async {
      final mockDio = Dio();
      mockDio.httpClientAdapter = MockHttpClientAdapter((options) {
        return {
          'throwDioException': true,
          'dioExceptionType': DioExceptionType.connectionTimeout,
          'statusCode': 500,
          'data': 'Internal Server Error',
        };
      });

      final tool = WeatherQueryTool(dio: mockDio);
      final result = await tool.execute({'city': '北京'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('超时'));
    });

    test('Validation failure when city parameter is empty', () async {
      final tool = WeatherQueryTool();
      final result = await tool.execute({'city': ''});
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('城市名称不能为空'));
    });
  });

  group('ToolRegistry Integration Tests for Safe Basic Tools', () {
    test('Default registry contains all 21 registered tools', () {
      final registry = ToolRegistry.defaultRegistry();
      expect(registry.getAllTools().length, equals(21));
      expect(
        registry.getRegisteredNames(),
        containsAll([
          'web_search',
          'google_search',
          'bing_search',
          'url_fetch',
          'math_eval',
          'time_calculator',
          'weather_query',
          'file_read',
          'file_write',
          'file_list',
          'file_delete',
          'code_eval',
          'clipboard_read',
          'clipboard_write',
          'calendar_query_events',
          'calendar_create_event',
          'notification_schedule',
          'notification_cancel',
          'contacts_search',
          'geolocation_get',
          'reverse_geocode',
        ]),
      );
    });

    test('Dispatch execution for math_eval and time_calculator via ToolRegistry', () async {
      final registry = ToolRegistry.defaultRegistry();

      final mathResult = await registry.execute('math_eval', {'expression': '10 * 10 + 5'});
      expect(mathResult.success, isTrue);
      expect(mathResult.rawData['result'], equals(105));

      final timeResult = await registry.execute('time_calculator', {
        'operation': 'duration',
        'time1': '2026-08-28 10:00:00',
        'time2': '2026-08-28 11:30:00',
      });
      expect(timeResult.success, isTrue);
      expect(timeResult.rawData['differenceText'], equals('1小时 30分钟'));
    });

    test('Export OpenAI schemas with security level filtering across all tools', () {
      final registry = ToolRegistry.defaultRegistry();

      // Safe tools only (Level 0) -> math_eval, time_calculator
      final safeSchemas = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.safe);
      final safeNames = safeSchemas.map((s) => s['function']['name']).toList();
      expect(safeNames, containsAll(['math_eval', 'time_calculator']));
      expect(safeNames, isNot(contains('web_search')));
      expect(safeNames, isNot(contains('weather_query')));

      // ReadOnly tools (Level 1) -> 11 tools (Level 0 + Level 1, including reverse_geocode)
      final readOnlySchemas = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.readOnly);
      expect(readOnlySchemas.length, equals(11));
    });
  });
}
