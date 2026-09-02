import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/services/agent_fault_tolerance.dart';

void main() {
  group('AgentFaultTolerance — Multi-format Tool Call Parser Tests', () {
    late AgentFaultTolerance faultTolerance;

    setUp(() {
      faultTolerance = AgentFaultTolerance();
    });

    test('Parses DeepSeek DSML v2 official format', () {
      const content = '''
思考：我需要读取沙箱配置文件。
<｜tool calls begin｜><｜tool call begin｜>function<｜tool sep｜>file_read
```json
{
  "path": "config/settings.json"
}
```<｜tool call end｜><｜tool calls end｜>
请稍候，我正在读取文件。
''';

      final toolCalls = faultTolerance.parseToolCalls(content);
      expect(toolCalls.length, equals(1));
      expect(toolCalls.first.toolName, equals('file_read'));
      expect(toolCalls.first.syntaxFormat, equals('dsml_v2'));
      expect(toolCalls.first.arguments['path'], equals('config/settings.json'));

      final stripped = faultTolerance.stripToolCallBlocks(content);
      expect(stripped, contains('思考：我需要读取沙箱配置文件。'));
      expect(stripped, contains('请稍候，我正在读取文件。'));
      expect(stripped, isNot(contains('<｜tool calls begin｜>')));
    });

    test('Parses DeepSeek DSML v1 XML format with typed parameters', () {
      const content = '''
<｜｜DSML｜｜tool_calls><｜｜DSML｜｜invoke name="math_eval"><｜｜DSML｜｜parameter name="expression">2^10 + 24</｜｜DSML｜｜parameter><｜｜DSML｜｜parameter name="exact">true</｜｜DSML｜｜parameter><｜｜DSML｜｜parameter name="precision">4</｜｜DSML｜｜parameter></｜｜DSML｜｜invoke></｜｜DSML｜｜tool_calls>
''';

      final toolCalls = faultTolerance.parseToolCalls(content);
      expect(toolCalls.length, equals(1));
      expect(toolCalls.first.toolName, equals('math_eval'));
      expect(toolCalls.first.syntaxFormat, equals('dsml_v1'));
      expect(toolCalls.first.arguments['expression'], equals('2^10 + 24'));
      expect(toolCalls.first.arguments['exact'], equals(true));
      expect(toolCalls.first.arguments['precision'], equals(4));

      final stripped = faultTolerance.stripToolCallBlocks(content);
      expect(stripped, isEmpty);
    });

    test('Parses Qwen XML with enclosed JSON format', () {
      const content = '''
我来为你查询北京今天的天气：
<tool_call>
```json
{
  "name": "weather_query",
  "arguments": {
    "city": "北京",
    "days": 3
  }
}
```
</tool_call>
''';

      final toolCalls = faultTolerance.parseToolCalls(content);
      expect(toolCalls.length, equals(1));
      expect(toolCalls.first.toolName, equals('weather_query'));
      expect(toolCalls.first.syntaxFormat, equals('qwen_xml'));
      expect(toolCalls.first.arguments['city'], equals('北京'));
      expect(toolCalls.first.arguments['days'], equals(3));
    });

    test('Parses Qwen Tagged XML format', () {
      const content = '''
<tool_call>
<function=web_search>
<parameter=query>Flutter 状态管理最佳实践</parameter>
<parameter=limit>5</parameter>
</function>
</tool_call>
''';

      final toolCalls = faultTolerance.parseToolCalls(content);
      expect(toolCalls.length, equals(1));
      expect(toolCalls.first.toolName, equals('web_search'));
      expect(toolCalls.first.syntaxFormat, equals('qwen_tagged_xml'));
      expect(toolCalls.first.arguments['query'], equals('Flutter 状态管理最佳实践'));
      expect(toolCalls.first.arguments['limit'], equals(5));
    });

    test('Parses Llama 3 [TOOL_CALLS] array format', () {
      const content = '''
[TOOL_CALLS] [{"name": "time_calculator", "arguments": {"operation": "current_time", "timezone": "Asia/Tokyo"}}]
''';

      final toolCalls = faultTolerance.parseToolCalls(content);
      expect(toolCalls.length, equals(1));
      expect(toolCalls.first.toolName, equals('time_calculator'));
      expect(toolCalls.first.syntaxFormat, equals('llama_json'));
      expect(toolCalls.first.arguments['operation'], equals('current_time'));
      expect(toolCalls.first.arguments['timezone'], equals('Asia/Tokyo'));
    });

    test('Parses Hermes <functioncall> format', () {
      const content = '''
<functioncall> {"name": "wiki_lookup", "arguments": {"query": "图灵机"}} </functioncall>
''';

      final toolCalls = faultTolerance.parseToolCalls(content);
      expect(toolCalls.length, equals(1));
      expect(toolCalls.first.toolName, equals('wiki_lookup'));
      expect(toolCalls.first.syntaxFormat, equals('hermes_xml'));
      expect(toolCalls.first.arguments['query'], equals('图灵机'));
    });

    test('Parses raw OpenAI JSON code block', () {
      const content = '''
```json
{
  "name": "code_eval",
  "arguments": {
    "code": "print(1 + 1);"
  }
}
```
''';

      final toolCalls = faultTolerance.parseToolCalls(content);
      expect(toolCalls.length, equals(1));
      expect(toolCalls.first.toolName, equals('code_eval'));
      expect(toolCalls.first.syntaxFormat, equals('openai_json'));
      expect(toolCalls.first.arguments['code'], equals('print(1 + 1);'));
    });
  });

  group('AgentFaultTolerance — Resilient JSON Argument Auto-Repair Tests', () {
    late AgentFaultTolerance faultTolerance;

    setUp(() {
      faultTolerance = AgentFaultTolerance();
    });

    test('Glitch 1: Markdown code fences removal', () {
      const raw = '```json\n{"query": "Dart isolates"}\n```';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['query'], equals('Dart isolates'));
    });

    test('Glitch 2: Unescaped literal newlines in string literals', () {
      const raw = '{"content": "First line\nSecond line\r\nThird line", "mode": "write"}';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['mode'], equals('write'));
      expect(map['content'], contains('First line'));
      expect(map['content'], contains('Second line'));
    });

    test('Glitch 3: Single-quoted keys and string values', () {
      const raw = "{'path': 'data/user.json', 'backup': true, 'tags': ['vip', 'admin']}";
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['path'], equals('data/user.json'));
      expect(map['backup'], equals(true));
      expect(map['tags'], equals(['vip', 'admin']));
    });

    test('Glitch 4: Unquoted object keys', () {
      const raw = '{query: "Flutter widgets", limit: 10, is_active: false}';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['query'], equals('Flutter widgets'));
      expect(map['limit'], equals(10));
      expect(map['is_active'], equals(false));
    });

    test('Glitch 5: Trailing commas in objects and arrays', () {
      const raw = '{"a": 1, "b": [10, 20, 30, ], "c": {"nested": "val", }, }';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['a'], equals(1));
      expect(map['b'], equals([10, 20, 30]));
      expect(map['c']['nested'], equals('val'));
    });

    test('Glitch 6: Unclosed bracket and brace stacks', () {
      const raw = '{"path": "lib/main.dart", "lines": [10, 20, 30';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['path'], equals('lib/main.dart'));
      expect(map['lines'], equals([10, 20, 30]));
    });

    test('Glitch 7: Unclosed double quotes and truncated JSON', () {
      const raw = '{"title": "Flutter App Architecture Guide", "summary": "This article explains how to struct';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['title'], equals('Flutter App Architecture Guide'));
      expect(map['summary'], contains('This article explains'));
    });

    test('Glitch 8: HTML / XML entity decoding in JSON strings', () {
      const raw = '{"query": "C++ &amp; Rust &quot;benchmark&quot; &lt;2026&gt; &#39;fast&#39;"}';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['query'], equals('C++ & Rust "benchmark" <2026> \'fast\''));
    });

    test('Fallback wraps plain string argument into query map', () {
      const raw = '2026年诺贝尔奖';
      final map = faultTolerance.repairAndParseArguments(raw);
      expect(map['query'], equals('2026年诺贝尔奖'));
    });
  });

  group('AgentFaultTolerance — Exponential Backoff Retry with Jitter Tests', () {
    late AgentFaultTolerance faultTolerance;

    setUp(() {
      faultTolerance = AgentFaultTolerance(
        retryPolicy: const RetryPolicy(
          maxRetries: 3,
          initialDelay: Duration(milliseconds: 50),
          maxDelay: Duration(milliseconds: 200),
          backoffMultiplier: 2.0,
          jitterFactor: 0.1,
        ),
      );
    });

    test('Executes immediately and returns value on success with 0 retries', () async {
      int calls = 0;
      final result = await faultTolerance.executeWithRetry(() async {
        calls++;
        return 'success';
      });

      expect(result, equals('success'));
      expect(calls, equals(1));
    });

    test('Retries on retryable transient DioException 503 and succeeds on 3rd attempt', () async {
      int calls = 0;
      final retryAttempts = <int>[];

      final result = await faultTolerance.executeWithRetry(
        () async {
          calls++;
          if (calls < 3) {
            throw DioException(
              requestOptions: RequestOptions(path: '/api/v1/chat'),
              response: Response(
                requestOptions: RequestOptions(path: '/api/v1/chat'),
                statusCode: 503,
              ),
              type: DioExceptionType.badResponse,
            );
          }
          return 'recovered';
        },
        onRetry: (attempt, delay, error) {
          retryAttempts.add(attempt);
        },
      );

      expect(result, equals('recovered'));
      expect(calls, equals(3));
      expect(retryAttempts, equals([1, 2]));
    });

    test('Retries on SocketException and TimeoutException', () async {
      int calls = 0;
      final result = await faultTolerance.executeWithRetry(() async {
        calls++;
        if (calls == 1) {
          throw const SocketException('Connection reset by peer');
        }
        if (calls == 2) {
          throw TimeoutException('Request timed out');
        }
        return 'online';
      });

      expect(result, equals('online'));
      expect(calls, equals(3));
    });

    test('Non-retryable 400 Bad Request throws immediately without retrying', () async {
      int calls = 0;
      expect(
        () async => await faultTolerance.executeWithRetry(() async {
          calls++;
          throw DioException(
            requestOptions: RequestOptions(path: '/api/v1/chat'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/v1/chat'),
              statusCode: 400,
            ),
            type: DioExceptionType.badResponse,
          );
        }),
        throwsA(isA<DioException>()),
      );

      expect(calls, equals(1));
    });

    test('Respects HTTP 429 Retry-After header duration', () async {
      int calls = 0;
      Duration? recordedDelay;

      final result = await faultTolerance.executeWithRetry(
        () async {
          calls++;
          if (calls == 1) {
            throw DioException(
              requestOptions: RequestOptions(path: '/api/v1/chat'),
              response: Response(
                requestOptions: RequestOptions(path: '/api/v1/chat'),
                statusCode: 429,
                headers: Headers.fromMap({
                  'retry-after': ['1'],
                }),
              ),
              type: DioExceptionType.badResponse,
            );
          }
          return 'rate_limit_recovered';
        },
        onRetry: (attempt, delay, error) {
          recordedDelay = delay;
        },
      );

      expect(result, equals('rate_limit_recovered'));
      expect(recordedDelay, equals(const Duration(seconds: 1)));
    });

    test('Aborts when CancelToken is cancelled', () async {
      final cancelToken = CancelToken();
      cancelToken.cancel();

      expect(
        () async => await faultTolerance.executeWithRetry(
          () async => 'data',
          cancelToken: cancelToken,
        ),
        throwsA(isA<DioException>().having((e) => e.type, 'type', equals(DioExceptionType.cancel))),
      );
    });
  });

  group('AgentFaultTolerance — Structured Self-Healing Chinese Diagnostic Tests', () {
    test('generateSelfHealingFeedback produces structured diagnostic context with custom suggestion', () {
      final feedback = AgentFaultTolerance.buildSelfHealingFeedback(
        toolName: 'file_read',
        arguments: {'path': '/etc/passwd'},
        errorMessage: '路径安全沙箱拦截：禁止使用绝对路径越权访问。',
        suggestion: '请使用相对路径如 "lib/main.dart" 或 "data/config.json" 再次读取。',
      );

      expect(feedback, contains('【工具执行异常与自愈引导】'));
      expect(feedback, contains('- 调用的工具: `file_read`'));
      expect(feedback, contains('- 传入的参数: `{"path":"/etc/passwd"}`'));
      expect(feedback, contains('- 失败原因: 路径安全沙箱拦截：禁止使用绝对路径越权访问。'));
      expect(feedback, contains('- 修复建议: 请使用相对路径如 "lib/main.dart" 或 "data/config.json" 再次读取。'));
    });

    test('generateSelfHealingFeedback produces default Chinese suggestion when none provided', () {
      final feedback = AgentFaultTolerance().generateSelfHealingFeedback(
        toolName: 'math_eval',
        arguments: {'expression': '10 / 0'},
        errorMessage: '除零错误：分母不能为零。',
      );

      expect(feedback, contains('【工具执行异常与自愈引导】'));
      expect(feedback, contains('- 调用的工具: `math_eval`'));
      expect(feedback, contains('- 失败原因: 除零错误：分母不能为零。'));
      expect(feedback, contains('请根据上述错误原因检查参数类型或有效性'));
    });
  });
}
