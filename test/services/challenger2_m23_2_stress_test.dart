import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/tool/tool.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/tools/weather_query_tool.dart';
import 'package:chat/services/tools/wiki_lookup_tool.dart';

/// Configurable mock HTTP adapter for stress-testing network tools.
class StressMockAdapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(RequestOptions options) handler;

  StressMockAdapter(this.handler);

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
        message: result['dioErrorMessage'] as String? ?? 'Dio mock error',
      );
    }

    if (result['throwGenericException'] == true) {
      throw Exception(result['genericErrorMessage'] ?? 'Generic socket failure');
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
  group('Challenger 2 — WeatherQueryTool Empirical Stress Tests', () {
    test('Empty and whitespace city validation', () async {
      final tool = WeatherQueryTool();
      final r1 = await tool.execute({'city': ''});
      expect(r1.success, isFalse);
      expect(r1.errorMessage, contains('城市名称不能为空'));

      final r2 = await tool.execute({'city': '   \t\n '});
      expect(r2.success, isFalse);
      expect(r2.errorMessage, contains('城市名称不能为空'));

      final r3 = await tool.execute({});
      expect(r3.success, isFalse);
      expect(r3.errorMessage, contains('城市名称不能为空'));
    });

    test('Network error: Geocoding connection timeout', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        return {
          'throwDioException': true,
          'dioExceptionType': DioExceptionType.connectionTimeout,
        };
      });

      final tool = WeatherQueryTool(dio: dio);
      final result = await tool.execute({'city': '北京'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('天气查询网络请求超时'));
      expect(result.content, contains('查询天气失败'));
      expect(result.metadata?['dioError'], equals('connectionTimeout'));
    });

    test('Network error: Geocoding HTTP 500 server error', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        return {
          'throwDioException': true,
          'dioExceptionType': DioExceptionType.badResponse,
          'statusCode': 500,
          'data': {'error': 'Internal Server Error'},
        };
      });

      final tool = WeatherQueryTool(dio: dio);
      final result = await tool.execute({'city': 'Shanghai'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('天气服务响应异常 (HTTP 500)'));
    });

    test('Network error: Forecast API receive timeout after geocoding success', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        if (options.uri.host.contains('geocoding-api')) {
          return {
            'statusCode': 200,
            'data': {
              'results': [
                {'name': 'London', 'latitude': 51.5074, 'longitude': -0.1278, 'country': 'United Kingdom'},
              ],
            },
          };
        }
        return {
          'throwDioException': true,
          'dioExceptionType': DioExceptionType.receiveTimeout,
        };
      });

      final tool = WeatherQueryTool(dio: dio);
      final result = await tool.execute({'city': 'London'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('天气查询网络请求超时'));
      expect(result.metadata?['dioError'], equals('receiveTimeout'));
    });

    test('Geocoding: Non-existent city / empty results', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        return {
          'statusCode': 200,
          'data': {'results': []},
        };
      });

      final tool = WeatherQueryTool(dio: dio);
      final result = await tool.execute({'city': 'AtlantisCityXYZ999'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('未找到城市 "AtlantisCityXYZ999" 的地理位置信息'));
      expect(result.metadata?['city'], equals('AtlantisCityXYZ999'));
    });

    test('Geocoding: Payload without results key', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        return {
          'statusCode': 200,
          'data': {'generationtime_ms': 0.12},
        };
      });

      final tool = WeatherQueryTool(dio: dio);
      final result = await tool.execute({'city': 'NonExistent'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('未找到城市 "NonExistent" 的地理位置信息'));
    });

    test('Forecast API: Highly malformed or sparse payload survives gracefully', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        if (options.uri.host.contains('geocoding-api')) {
          return {
            'statusCode': 200,
            'data': {
              'results': [
                {'name': 'Paris', 'latitude': 48.8566, 'longitude': 2.3522},
              ],
            },
          };
        }
        // Minimal sparse forecast payload missing hourly and daily
        return {
          'statusCode': 200,
          'data': {
            'latitude': 48.8566,
            'longitude': 2.3522,
            'current_weather': {
              'temperature': 18.5,
              'windspeed': 12.0,
              'winddirection': 180,
              'weathercode': 0,
              'time': '2026-08-28T12:00',
            },
          },
        };
      });

      final tool = WeatherQueryTool(dio: dio);
      final result = await tool.execute({'city': 'Paris'});

      expect(result.success, isTrue);
      expect(result.content, contains('Paris 实时天气与预报'));
      expect(result.content, contains('18.5 °C'));
      expect(result.content, contains('南风 180°'));
      expect(result.rawData['daily'], isEmpty);
    });

    test('Forecast days parameter parsing and clamping (clamped to 1..7)', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        if (options.uri.host.contains('geocoding-api')) {
          return {
            'statusCode': 200,
            'data': {
              'results': [
                {'name': 'Tokyo', 'latitude': 35.6762, 'longitude': 139.6503, 'country': 'Japan'},
              ],
            },
          };
        }
        return {
          'statusCode': 200,
          'data': {
            'current_weather': {
              'temperature': 25.0,
              'windspeed': 5.0,
              'winddirection': 90,
              'weathercode': 1,
              'time': '2026-08-28T12:00',
            },
            'daily': {
              'time': List.generate(7, (i) => '2026-08-${28 + i}'),
              'weathercode': [1, 2, 3, 61, 71, 95, 0],
              'temperature_2m_max': [26.0, 27.0, 24.0, 22.0, 20.0, 23.0, 28.0],
              'temperature_2m_min': [19.0, 20.0, 18.0, 17.0, 15.0, 18.0, 21.0],
              'precipitation_sum': [0.0, 0.0, 1.2, 8.5, 3.0, 15.0, 0.0],
              'windspeed_10m_max': [10.0, 12.0, 15.0, 25.0, 18.0, 30.0, 8.0],
            },
          },
        };
      });

      final tool = WeatherQueryTool(dio: dio);

      // 1. Clamped upper bound: 100 days -> 7 days
      final r1 = await tool.execute({'city': 'Tokyo', 'forecastDays': 100});
      expect(r1.success, isTrue);
      final dailyList1 = r1.rawData['daily'] as List;
      expect(dailyList1.length, equals(7));

      // 2. Clamped lower bound: -5 days -> 1 day
      final r2 = await tool.execute({'city': 'Tokyo', 'forecastDays': -5});
      expect(r2.success, isTrue);
      final dailyList2 = r2.rawData['daily'] as List;
      expect(dailyList2.length, equals(1));

      // 3. String numeric parsing: "4" -> 4 days
      final r3 = await tool.execute({'city': 'Tokyo', 'forecastDays': '4'});
      expect(r3.success, isTrue);
      final dailyList3 = r3.rawData['daily'] as List;
      expect(dailyList3.length, equals(4));
    });

    test('WMO weather codes and wind direction coverage', () async {
      final testCases = [
        {'code': 0, 'text': '晴天', 'icon': '☀️', 'deg': 0, 'dir': '北风'},
        {'code': 3, 'text': '阴天', 'icon': '☁️', 'deg': 45, 'dir': '东北风'},
        {'code': 45, 'text': '大雾', 'icon': '🌫️', 'deg': 90, 'dir': '东风'},
        {'code': 65, 'text': '大雨', 'icon': '🌧️🌧️', 'deg': 135, 'dir': '东南风'},
        {'code': 75, 'text': '大雪', 'icon': '❄️❄️', 'deg': 180, 'dir': '南风'},
        {'code': 95, 'text': '雷暴', 'icon': '⛈️', 'deg': 225, 'dir': '西南风'},
        {'code': 999, 'text': '未知天气 (代码: 999)', 'icon': '❓', 'deg': 270, 'dir': '西风'},
      ];

      for (final tc in testCases) {
        final code = tc['code'] as int;
        final deg = tc['deg'] as int;
        final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
          if (options.uri.host.contains('geocoding-api')) {
            return {
              'statusCode': 200,
              'data': {
                'results': [
                  {'name': 'TestCity', 'latitude': 0.0, 'longitude': 0.0},
                ],
              },
            };
          }
          return {
            'statusCode': 200,
            'data': {
              'current_weather': {
                'temperature': 20.0,
                'windspeed': 10.0,
                'winddirection': deg,
                'weathercode': code,
                'time': '2026-08-28T12:00',
              },
            },
          };
        });

        final tool = WeatherQueryTool(dio: dio);
        final result = await tool.execute({'city': 'TestCity'});
        expect(result.success, isTrue);
        expect(result.rawData['current']['condition'], equals(tc['text']));
        expect(result.rawData['current']['icon'], equals(tc['icon']));
        expect(result.rawData['current']['windDirectionText'], equals(tc['dir']));
      }
    });
  });

  group('Challenger 2 — WikiLookupTool Empirical Stress Tests', () {
    test('Empty and whitespace query validation', () async {
      final tool = WikiLookupTool();
      final r1 = await tool.execute({'query': ''});
      expect(r1.success, isFalse);
      expect(r1.errorMessage, contains('查询关键词不能为空'));

      final r2 = await tool.execute({'query': '   \n  '});
      expect(r2.success, isFalse);
      expect(r2.errorMessage, contains('查询关键词不能为空'));
    });

    test('Network error: Summary request timeout', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        return {
          'throwDioException': true,
          'dioExceptionType': DioExceptionType.connectionTimeout,
        };
      });

      final tool = WikiLookupTool(dio: dio);
      final result = await tool.execute({'query': 'Flutter'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('维基百科网络请求超时'));
      expect(result.metadata?['dioError'], equals('connectionTimeout'));
    });

    test('Network error: HTTP 500 server error', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        return {
          'throwDioException': true,
          'dioExceptionType': DioExceptionType.badResponse,
          'statusCode': 500,
        };
      });

      final tool = WikiLookupTool(dio: dio);
      final result = await tool.execute({'query': 'Flutter'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('维基百科服务响应异常 (HTTP 500)'));
    });

    test('Summary API: Standard hit in English with extractLength truncation', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        return {
          'statusCode': 200,
          'data': {
            'type': 'standard',
            'title': 'Dart (programming language)',
            'description': 'Programming language developed by Google',
            'extract': 'Dart is a programming language designed by Lars Bak and Kasper Lund and developed by Google. It can be used to develop web and mobile apps.',
            'content_urls': {
              'desktop': {'page': 'https://en.wikipedia.org/wiki/Dart_(programming_language)'},
            },
          },
        };
      });

      final tool = WikiLookupTool(dio: dio);
      final result = await tool.execute({
        'query': 'Dart',
        'language': 'en',
        'extractLength': 40,
      });

      expect(result.success, isTrue);
      expect(result.rawData['type'], equals('summary'));
      expect(result.rawData['language'], equals('en'));
      expect(result.rawData['title'], equals('Dart (programming language)'));
      expect(result.rawData['extract'].toString().endsWith('...'), isTrue);
      expect(result.rawData['extract'].toString().length, equals(43)); // 40 chars + '...'
      expect(result.content, contains('### 📚 维基百科：Dart (programming language)'));
      expect(result.content, contains('> **描述**: Programming language developed by Google'));
    });

    test('Summary 404 falls back to MediaWiki search API with disambiguation list', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        if (options.uri.path.contains('/api/rest_v1/page/summary/')) {
          return {
            'statusCode': 404,
            'data': {'title': 'Not found', 'type': 'https://mediawiki.org/wiki/HyperSwitch/errors/not_found'},
          };
        }
        // MediaWiki search query
        return {
          'statusCode': 200,
          'data': {
            'query': {
              'search': [
                {
                  'title': '苹果公司',
                  'snippet': '一家美国的<span class="searchmatch">跨国</span>科技公司。',
                },
                {
                  'title': '苹果 (水果)',
                  'snippet': '蔷薇科苹果属植物的果实。',
                },
                {
                  'title': '苹果 (电影)',
                  'snippet': '2007年中国剧情片。',
                },
              ],
            },
          },
        };
      });

      final tool = WikiLookupTool(dio: dio);
      final result = await tool.execute({'query': '苹果', 'language': 'zh'});

      expect(result.success, isTrue);
      expect(result.rawData['type'], equals('disambiguation'));
      expect(result.content, contains('维基百科消歧义 / 相关词条: "苹果"'));
      expect(result.content, contains('1. **[苹果公司](https://zh.wikipedia.org/wiki/%E8%8B%B9%E6%9E%9C%E5%85%AC%E5%8F%B8)**: 一家美国的跨国科技公司。'));
      expect(result.content, contains('2. **[苹果 (水果)](https://zh.wikipedia.org/wiki/%E8%8B%B9%E6%9E%9C%20(%E6%B0%B4%E6%9E%9C))**: 蔷薇科苹果属植物的果实。'));
      // HTML tags should be stripped from snippets
      expect(result.content, isNot(contains('<span')));
      final optionsList = result.rawData['options'] as List;
      expect(optionsList.length, equals(3));
    });

    test('Search fallback: 0 search results returns friendly failure', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        if (options.uri.path.contains('/api/rest_v1/page/summary/')) {
          return {'statusCode': 404, 'data': {}};
        }
        return {
          'statusCode': 200,
          'data': {
            'query': {'search': []},
          },
        };
      });

      final tool = WikiLookupTool(dio: dio);
      final result = await tool.execute({'query': 'NonExistentQueryZXY999'});

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('未找到与 "NonExistentQueryZXY999" 相关的维基百科词条'));
      expect(result.content, contains('检索失败'));
    });

    test('Non-Latin queries and language fallback handling', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        final isEnglish = options.uri.host.startsWith('en.');
        return {
          'statusCode': 200,
          'data': {
            'type': 'standard',
            'title': isEnglish ? 'Tokyo' : '东京',
            'description': isEnglish ? 'Capital of Japan' : '日本首都',
            'extract': isEnglish ? 'Tokyo is the capital of Japan.' : '东京是位于日本关东平原的城市。',
          },
        };
      });

      final tool = WikiLookupTool(dio: dio);

      // 1. Language 'en'
      final rEn = await tool.execute({'query': 'Tokyo', 'language': 'en'});
      expect(rEn.success, isTrue);
      expect(rEn.rawData['title'], equals('Tokyo'));

      // 2. Language 'ZH' uppercase (should normalize to 'zh')
      final rZh = await tool.execute({'query': '东京', 'language': 'ZH'});
      expect(rZh.success, isTrue);
      expect(rZh.rawData['title'], equals('东京'));

      // 3. Unknown language defaults to 'zh'
      final rDef = await tool.execute({'query': '东京', 'language': 'fr'});
      expect(rDef.success, isTrue);
      expect(rDef.rawData['language'], equals('zh'));
    });
  });

  group('Challenger 2 — ToolRegistry Integration & Schema Export Stress Tests', () {
    test('Default registry initializes exactly 8 tools with correct security levels', () {
      final registry = ToolRegistry.defaultRegistry();

      final expectedTools = {
        'web_search': ToolSecurityLevel.readOnly,
        'google_search': ToolSecurityLevel.readOnly,
        'bing_search': ToolSecurityLevel.readOnly,
        'url_fetch': ToolSecurityLevel.readOnly,
        'math_eval': ToolSecurityLevel.safe,
        'time_calculator': ToolSecurityLevel.safe,
        'weather_query': ToolSecurityLevel.readOnly,
        'wiki_lookup': ToolSecurityLevel.readOnly,
      };

      expect(registry.getAllTools().length, equals(8));
      expect(registry.getRegisteredNames().length, equals(8));

      for (final entry in expectedTools.entries) {
        final toolName = entry.key;
        final expectedLevel = entry.value;

        expect(registry.hasTool(toolName), isTrue, reason: 'Tool $toolName should be registered');
        final tool = registry.getTool(toolName)!;
        expect(tool.securityLevel, equals(expectedLevel), reason: 'Tool $toolName security level');
        expect(tool.name, equals(toolName));
        expect(tool.displayName.isNotEmpty, isTrue);
        expect(tool.description.isNotEmpty, isTrue);
      }
    });

    test('OpenAI Schema export for all 8 tools strictly follows Function Calling spec', () {
      final registry = ToolRegistry.defaultRegistry();
      final schemas = registry.exportOpenAiSchemas();

      expect(schemas.length, equals(8));

      for (final schema in schemas) {
        expect(schema['type'], equals('function'));
        expect(schema['function'], isA<Map<String, dynamic>>());
        final fn = schema['function'] as Map<String, dynamic>;

        expect(fn['name'], isA<String>());
        expect((fn['name'] as String).isNotEmpty, isTrue);
        expect(fn['description'], isA<String>());
        expect(fn['parameters'], isA<Map<String, dynamic>>());

        final params = fn['parameters'] as Map<String, dynamic>;
        expect(params['type'], equals('object'));
        expect(params['properties'], isA<Map<String, dynamic>>());
        expect(params['required'], isA<List>());
      }
    });

    test('OpenAI Schema export filtering by maxSecurityLevel', () {
      final registry = ToolRegistry.defaultRegistry();

      // Safe only (Level 0) -> math_eval, time_calculator
      final safeSchemas = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.safe);
      expect(safeSchemas.length, equals(2));
      final safeNames = safeSchemas.map((s) => s['function']['name'] as String).toSet();
      expect(safeNames, equals({'math_eval', 'time_calculator'}));

      // ReadOnly (Level 1) -> all 8 tools
      final readOnlySchemas = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.readOnly);
      expect(readOnlySchemas.length, equals(8));
    });

    test('Dynamic enablement and execution dispatching through ToolRegistry', () async {
      final dio = Dio()..httpClientAdapter = StressMockAdapter((options) {
        if (options.uri.host.contains('geocoding-api')) {
          return {
            'statusCode': 200,
            'data': {
              'results': [
                {'name': 'Hangzhou', 'latitude': 30.2741, 'longitude': 120.1551, 'country': 'China'},
              ],
            },
          };
        }
        return {
          'statusCode': 200,
          'data': {
            'current_weather': {
              'temperature': 28.0,
              'windspeed': 8.0,
              'winddirection': 120,
              'weathercode': 0,
              'time': '2026-08-28T12:00',
            },
          },
        };
      });

      final registry = ToolRegistry.defaultRegistry(dio: dio);

      // 1. Execute enabled weather_query tool
      final exec1 = await registry.execute('weather_query', {'city': 'Hangzhou'});
      expect(exec1.success, isTrue);
      expect(exec1.content, contains('Hangzhou'));

      // 2. Disable weather_query and execute -> should fail
      registry.setToolEnabled('weather_query', false);
      expect(registry.isToolEnabled('weather_query'), isFalse);
      expect(registry.getEnabledNames(), isNot(contains('weather_query')));

      final exec2 = await registry.execute('weather_query', {'city': 'Hangzhou'});
      expect(exec2.success, isFalse);
      expect(exec2.errorMessage, contains("工具 'weather_query' 当前已被禁用"));

      // 3. Export schemas with onlyEnabled = true -> should have 7 tools
      final schemasAfterDisable = registry.exportOpenAiSchemas(onlyEnabled: true);
      expect(schemasAfterDisable.length, equals(7));
      expect(schemasAfterDisable.any((s) => s['function']['name'] == 'weather_query'), isFalse);

      // 4. Reset enablement -> re-enables weather_query
      registry.resetEnablement();
      expect(registry.isToolEnabled('weather_query'), isTrue);
      final exec3 = await registry.execute('weather_query', {'city': 'Hangzhou'});
      expect(exec3.success, isTrue);
    });

    test('Registry parameter validation on weather_query and wiki_lookup', () async {
      final registry = ToolRegistry.defaultRegistry();

      // Missing required city
      final res1 = await registry.execute('weather_query', {});
      expect(res1.success, isFalse);
      expect(res1.errorMessage, contains("缺少必需参数 'city'"));

      // Missing required query
      final res2 = await registry.execute('wiki_lookup', {});
      expect(res2.success, isFalse);
      expect(res2.errorMessage, contains("缺少必需参数 'query'"));

      // Invalid enum for language
      final res3 = await registry.execute('wiki_lookup', {'query': 'test', 'language': 'de'});
      expect(res3.success, isFalse);
      expect(res3.errorMessage, contains("不在允许的枚举范围"));
    });
  });
}
