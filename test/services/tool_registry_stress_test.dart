import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/tool/tool.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/tools/legacy_tool_adapters.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/url_fetch_service.dart';

/// Configurable test tool for stress and edge testing.
class StressTestTool extends Tool {
  @override
  final String name;
  @override
  final String displayName;
  @override
  final String description;
  @override
  final ToolSecurityLevel securityLevel;
  @override
  final List<ToolParameter> parameters;

  final Future<ToolExecutionResult> Function(Map<String, dynamic> args)? executionHandler;

  const StressTestTool({
    required this.name,
    this.displayName = 'Stress Test Tool',
    this.description = 'A tool for empirical stress testing',
    this.securityLevel = ToolSecurityLevel.safe,
    this.parameters = const [],
    this.executionHandler,
  });

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    if (executionHandler != null) {
      return executionHandler!(arguments);
    }
    return ToolExecutionResult.success(
      toolName: name,
      content: 'Executed $name with ${arguments.length} args',
      rawData: arguments,
    );
  }
}

/// Mock search service for legacy adapter testing.
class StressMockSearchService extends SearchService {
  List<SearchResult> searchResults = [];
  SearchException? searchException;
  Exception? genericException;
  String? capturedBackend;
  String? capturedSearxngUrl;
  String? capturedGoogleApiKey;
  String? capturedGoogleBaseUrl;
  String? capturedGoogleModel;
  String? capturedBingCookie;

  @override
  Future<List<SearchResult>> search({
    required String query,
    String? searxngUrl,
    String searchBackend = 'searxng',
    String? googleApiKey,
    String? googleBaseUrl,
    String? googleSearchModel,
    String? bingCookie,
  }) async {
    capturedBackend = searchBackend;
    capturedSearxngUrl = searxngUrl;
    capturedGoogleApiKey = googleApiKey;
    capturedGoogleBaseUrl = googleBaseUrl;
    capturedGoogleModel = googleSearchModel;
    capturedBingCookie = bingCookie;

    if (searchException != null) throw searchException!;
    if (genericException != null) throw genericException!;
    return searchResults;
  }

  @override
  String formatSearchResultsForContext(List<SearchResult> results) {
    if (results.isEmpty) return 'No results found.';
    return results.map((r) => '1. [${r.title}](${r.url})\n   摘要: ${r.content}').join('\n\n');
  }
}

/// Mock url fetch service for testing UrlFetchTool.
class StressMockUrlFetchService extends UrlFetchService {
  FetchResult? fetchResult;
  Exception? exceptionToThrow;
  int? capturedMaxCharacters;
  CancelToken? capturedCancelToken;

  @override
  Future<FetchResult> fetchUrl(
    String url, {
    CancelToken? cancelToken,
    int maxCharacters = UrlFetchService.defaultMaxCharacters,
  }) async {
    capturedCancelToken = cancelToken;
    capturedMaxCharacters = maxCharacters;

    if (exceptionToThrow != null) throw exceptionToThrow!;
    return fetchResult ??
        FetchResult(
          url: url,
          status: 'success',
          pageType: 'article',
          truncated: false,
          originalLength: 100,
          maxLength: 15000,
          contentRatio: 0.8,
          mainContent: 'Mock content for $url',
          metadata: const FetchMetadata(title: 'Mock Title'),
          totalLinks: 0,
          internalLinks: 0,
          externalLinks: 0,
          warnings: const [],
        );
  }
}

void main() {
  group('1. Boundary Parameters & Malformed Inputs Stress Tests', () {
    test('ToolParameter type validation across all primitive types with valid/invalid inputs', () {
      // String parameter
      const strParam = ToolParameter(name: 'str', type: 'string', description: 'String test');
      expect(strParam.validate('hello'), isNull);
      expect(strParam.validate(''), isNull);
      expect(strParam.validate('你好 世界 🚀 \u0000 \t\n'), isNull);
      expect(strParam.validate(123), contains("应为字符串类型"));
      expect(strParam.validate(true), contains("应为字符串类型"));
      expect(strParam.validate(['list']), contains("应为字符串类型"));
      expect(strParam.validate({'k': 'v'}), contains("应为字符串类型"));

      // Integer parameter
      const intParam = ToolParameter(name: 'num_int', type: 'integer', description: 'Int test');
      expect(intParam.validate(0), isNull);
      expect(intParam.validate(-99999999), isNull);
      expect(intParam.validate(99999999), isNull);
      expect(intParam.validate('42'), isNull);
      expect(intParam.validate('-100'), isNull);
      expect(intParam.validate('3.14'), contains("应为整数类型"));
      expect(intParam.validate(3.14), contains("应为整数类型"));
      expect(intParam.validate('not_a_num'), contains("应为整数类型"));
      expect(intParam.validate(true), contains("应为整数类型"));

      // Number parameter (double/int/stringified)
      const numParam = ToolParameter(name: 'num_val', type: 'number', description: 'Number test');
      expect(numParam.validate(0), isNull);
      expect(numParam.validate(3.1415926535), isNull);
      expect(numParam.validate(-0.0001), isNull);
      expect(numParam.validate('3.14'), isNull);
      expect(numParam.validate('-1.23e4'), isNull);
      expect(numParam.validate('abc'), contains("应为数值类型"));
      expect(numParam.validate(false), contains("应为数值类型"));
      expect(numParam.validate([]), contains("应为数值类型"));

      // Boolean parameter
      const boolParam = ToolParameter(name: 'is_active', type: 'boolean', description: 'Bool test');
      expect(boolParam.validate(true), isNull);
      expect(boolParam.validate(false), isNull);
      expect(boolParam.validate('true'), isNull);
      expect(boolParam.validate('false'), isNull);
      expect(boolParam.validate('TRUE'), contains("应为布尔类型"));
      expect(boolParam.validate(1), contains("应为布尔类型"));
      expect(boolParam.validate(0), contains("应为布尔类型"));
      expect(boolParam.validate('yes'), contains("应为布尔类型"));

      // Array parameter
      const arrParam = ToolParameter(name: 'items', type: 'array', description: 'Array test');
      expect(arrParam.validate([]), isNull);
      expect(arrParam.validate(['a', 1, true, {}]), isNull);
      expect(arrParam.validate('a,b,c'), contains("应为列表类型"));
      expect(arrParam.validate({'a': 1}), contains("应为列表类型"));
      expect(arrParam.validate(123), contains("应为列表类型"));

      // Object parameter
      const objParam = ToolParameter(name: 'config', type: 'object', description: 'Object test');
      expect(objParam.validate({}), isNull);
      expect(objParam.validate({'nested': {'a': 1}}), isNull);
      expect(objParam.validate(['a']), contains("应为对象类型"));
      expect(objParam.validate('{"a":1}'), contains("应为对象类型"));
    });

    test('Enum constraint boundary checks (exact matching, outside enum, empty enum)', () {
      const enumParam = ToolParameter(
        name: 'mode',
        type: 'string',
        description: 'Mode',
        enumValues: ['strict', 'lenient'],
      );

      expect(enumParam.validate('strict'), isNull);
      expect(enumParam.validate('lenient'), isNull);
      expect(enumParam.validate('STRICT'), contains("不在允许的枚举范围"));
      expect(enumParam.validate('auto'), contains("不在允许的枚举范围"));

      // Optional enum with null value should pass
      const optEnumParam = ToolParameter(
        name: 'opt_mode',
        type: 'string',
        description: 'Optional Mode',
        required: false,
        enumValues: ['a', 'b'],
      );
      expect(optEnumParam.validate(null), isNull);
    });

    test('Default values, null handling, and schema generation fidelity', () {
      const paramWithDefaults = ToolParameter(
        name: 'limit',
        type: 'integer',
        description: 'Limit count',
        required: false,
        defaultValue: 50,
      );

      final schema = paramWithDefaults.toOpenAiSchema();
      expect(schema['type'], equals('integer'));
      expect(schema['description'], equals('Limit count'));
      expect(schema['default'], equals(50));

      const paramWithoutDefaults = ToolParameter(
        name: 'search_term',
        type: 'string',
        description: 'Search keyword',
      );
      final schemaNoDefault = paramWithoutDefaults.toOpenAiSchema();
      expect(schemaNoDefault.containsKey('default'), isFalse);
      expect(schemaNoDefault.containsKey('enum'), isFalse);
    });

    test('Tool.validateArguments ignores extra arguments and validates all declared parameters', () {
      const tool = StressTestTool(
        name: 'multi_param_tool',
        parameters: [
          ToolParameter(name: 'req_str', type: 'string', description: 'Required string', required: true),
          ToolParameter(name: 'req_int', type: 'integer', description: 'Required int', required: true),
          ToolParameter(name: 'opt_bool', type: 'boolean', description: 'Optional bool', required: false),
        ],
      );

      // All valid with extra parameters
      final validResult = tool.validateArguments({
        'req_str': 'hello',
        'req_int': 42,
        'opt_bool': true,
        'extra_unknown_field_1': 'should be ignored by validator',
        'extra_unknown_field_2': 9999,
      });
      expect(validResult, isNull);

      // Missing first required parameter
      final missingFirst = tool.validateArguments({
        'req_int': 42,
      });
      expect(missingFirst, contains("缺少必需参数 'req_str'"));

      // Missing second required parameter
      final missingSecond = tool.validateArguments({
        'req_str': 'hello',
      });
      expect(missingSecond, contains("缺少必需参数 'req_int'"));

      // Invalid optional parameter type
      final invalidOptional = tool.validateArguments({
        'req_str': 'hello',
        'req_int': 42,
        'opt_bool': 'not_a_bool',
      });
      expect(invalidOptional, contains("应为布尔类型"));
    });
  });

  group('2. ToolRegistry Lifecycle & Edge Cases Stress Tests', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry();
    });

    test('Duplicate tool registration overrides previous instance and resets enablement', () {
      const toolV1 = StressTestTool(name: 'dup_tool', displayName: 'Version 1');
      const toolV2 = StressTestTool(name: 'dup_tool', displayName: 'Version 2');

      registry.register(toolV1, enabled: true);
      expect(registry.getTool('dup_tool')?.displayName, equals('Version 1'));
      expect(registry.isToolEnabled('dup_tool'), isTrue);

      // Re-register with disabled
      registry.register(toolV2, enabled: false);
      expect(registry.getTool('dup_tool')?.displayName, equals('Version 2'));
      expect(registry.isToolEnabled('dup_tool'), isFalse);
      expect(registry.getAllTools().length, equals(1));
    });

    test('Unregister non-existent tool and re-unregistering does not throw', () {
      expect(registry.unregister('ghost_1'), isFalse);
      expect(registry.unregister('ghost_2'), isFalse);
      expect(registry.getAllTools(), isEmpty);

      const tool = StressTestTool(name: 'temp_tool');
      registry.register(tool);
      expect(registry.unregister('temp_tool'), isTrue);
      expect(registry.unregister('temp_tool'), isFalse);
      expect(registry.hasTool('temp_tool'), isFalse);
    });

    test('setToolEnabled on non-existent tool does not create phantom entries', () {
      registry.setToolEnabled('phantom', true);
      expect(registry.hasTool('phantom'), isFalse);
      expect(registry.isToolEnabled('phantom'), isFalse);
      expect(registry.getRegisteredNames(), isEmpty);
    });

    test('Execution of disabled tool returns explicit Chinese failure message', () async {
      const tool = StressTestTool(name: 'disabled_calc');
      registry.register(tool, enabled: false);

      final result = await registry.execute('disabled_calc', {});
      expect(result.success, isFalse);
      expect(result.errorMessage, equals("工具 'disabled_calc' 当前已被禁用。"));
      expect(result.executionDuration >= Duration.zero, isTrue);
    });

    test('Context injection preserves context with and without prefix', () async {
      Map<String, dynamic>? executedArgs;
      final tool = StressTestTool(
        name: 'ctx_tool',
        executionHandler: (args) async {
          executedArgs = args;
          return ToolExecutionResult.success(toolName: 'ctx_tool', content: 'OK');
        },
      );
      registry.register(tool);

      final userArgs = {'user_input': 'hello'};
      final contextData = {'sessionId': 'session_abc', 'userId': 12345};

      final result = await registry.execute('ctx_tool', userArgs, context: contextData);
      expect(result.success, isTrue);

      expect(executedArgs?['user_input'], equals('hello'));
      expect(executedArgs?['sessionId'], equals('session_abc'));
      expect(executedArgs?['__sessionId'], equals('session_abc'));
      expect(executedArgs?['userId'], equals(12345));
      expect(executedArgs?['__userId'], equals(12345));

      // Original userArgs should not be mutated
      expect(userArgs.containsKey('sessionId'), isFalse);
    });

    test('100 concurrent asynchronous tool executions execute cleanly without race conditions', () async {
      final registry = ToolRegistry();
      for (int i = 0; i < 10; i++) {
        registry.register(
          StressTestTool(
            name: 'worker_$i',
            executionHandler: (args) async {
              final id = args['id'] as int;
              await Future.delayed(const Duration(milliseconds: 5));
              return ToolExecutionResult.success(
                toolName: 'worker_$i',
                content: 'Result for $id',
                rawData: {'id': id, 'worker': i},
              );
            },
          ),
        );
      }

      final futures = <Future<ToolExecutionResult>>[];
      for (int i = 0; i < 100; i++) {
        final workerId = i % 10;
        futures.add(registry.execute('worker_$workerId', {'id': i}));
      }

      final results = await Future.wait(futures);
      expect(results.length, equals(100));
      for (int i = 0; i < 100; i++) {
        final res = results[i];
        expect(res.success, isTrue);
        expect(res.content, equals('Result for $i'));
        expect(res.rawData['id'], equals(i));
        expect(res.executionDuration >= Duration.zero, isTrue);
      }
    });
  });

  group('3. Security Level Boundaries & Schema Filter Stress Tests', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry();
      registry.registerTools([
        const StressTestTool(name: 'lvl0_tool', securityLevel: ToolSecurityLevel.safe),
        const StressTestTool(name: 'lvl1_tool', securityLevel: ToolSecurityLevel.readOnly),
        const StressTestTool(name: 'lvl2_tool', securityLevel: ToolSecurityLevel.sensitiveConfirm),
        const StressTestTool(name: 'lvl3_tool', securityLevel: ToolSecurityLevel.privilegedNative),
      ]);
    });

    test('ToolSecurityLevel enum properties and deserialization edge cases', () {
      expect(ToolSecurityLevel.safe.level, equals(0));
      expect(ToolSecurityLevel.safe.isSafeToAutoExecute, isTrue);
      expect(ToolSecurityLevel.safe.requiresConfirmation, isFalse);

      expect(ToolSecurityLevel.readOnly.level, equals(1));
      expect(ToolSecurityLevel.readOnly.isSafeToAutoExecute, isTrue);
      expect(ToolSecurityLevel.readOnly.requiresConfirmation, isFalse);

      expect(ToolSecurityLevel.sensitiveConfirm.level, equals(2));
      expect(ToolSecurityLevel.sensitiveConfirm.isSafeToAutoExecute, isFalse);
      expect(ToolSecurityLevel.sensitiveConfirm.requiresConfirmation, isTrue);

      expect(ToolSecurityLevel.privilegedNative.level, equals(3));
      expect(ToolSecurityLevel.privilegedNative.isSafeToAutoExecute, isFalse);
      expect(ToolSecurityLevel.privilegedNative.requiresConfirmation, isTrue);

      // Deserialization with case insensitivity & fallback
      expect(ToolSecurityLevel.fromJson('SAFE'), equals(ToolSecurityLevel.safe));
      expect(ToolSecurityLevel.fromJson('readOnly'), equals(ToolSecurityLevel.readOnly));
      expect(ToolSecurityLevel.fromJson('SensitiveConfirm'), equals(ToolSecurityLevel.sensitiveConfirm));
      expect(ToolSecurityLevel.fromJson('PRIVILEGEDNATIVE'), equals(ToolSecurityLevel.privilegedNative));
      expect(ToolSecurityLevel.fromJson('non_existent_security_level'), equals(ToolSecurityLevel.safe));

      // Deserialization from integer level & fallback
      expect(ToolSecurityLevel.fromLevel(0), equals(ToolSecurityLevel.safe));
      expect(ToolSecurityLevel.fromLevel(1), equals(ToolSecurityLevel.readOnly));
      expect(ToolSecurityLevel.fromLevel(2), equals(ToolSecurityLevel.sensitiveConfirm));
      expect(ToolSecurityLevel.fromLevel(3), equals(ToolSecurityLevel.privilegedNative));
      expect(ToolSecurityLevel.fromLevel(-1), equals(ToolSecurityLevel.safe));
      expect(ToolSecurityLevel.fromLevel(100), equals(ToolSecurityLevel.safe));
    });

    test('exportOpenAiSchemas filter combinations (maxSecurityLevel, onlyEnabled, toolNames)', () {
      // Level 0 only
      final lvl0 = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.safe);
      expect(lvl0.map((s) => s['function']['name']), equals(['lvl0_tool']));

      // Level <= 1
      final lvl1 = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.readOnly);
      expect(lvl1.map((s) => s['function']['name']), equals(['lvl0_tool', 'lvl1_tool']));

      // Level <= 2
      final lvl2 = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.sensitiveConfirm);
      expect(lvl2.map((s) => s['function']['name']), equals(['lvl0_tool', 'lvl1_tool', 'lvl2_tool']));

      // Level <= 3 (all)
      final lvl3 = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.privilegedNative);
      expect(lvl3.length, equals(4));

      // Disable lvl1_tool, then export maxSecurityLevel: readOnly with onlyEnabled: true
      registry.setToolEnabled('lvl1_tool', false);
      final enabledReadOnly = registry.exportOpenAiSchemas(
        maxSecurityLevel: ToolSecurityLevel.readOnly,
        onlyEnabled: true,
      );
      expect(enabledReadOnly.map((s) => s['function']['name']), equals(['lvl0_tool']));

      // 3-way filter: toolNames + onlyEnabled + maxSecurityLevel
      final tripleFilter = registry.exportOpenAiSchemas(
        toolNames: ['lvl0_tool', 'lvl2_tool', 'lvl3_tool'],
        onlyEnabled: true,
        maxSecurityLevel: ToolSecurityLevel.sensitiveConfirm,
      );
      expect(tripleFilter.map((s) => s['function']['name']), equals(['lvl0_tool', 'lvl2_tool']));
    });
  });

  group('4. Legacy Tool Adapters Robustness Stress Tests', () {
    late StressMockSearchService mockSearch;
    late StressMockUrlFetchService mockFetch;

    setUp(() {
      mockSearch = StressMockSearchService();
      mockFetch = StressMockUrlFetchService();
    });

    test('WebSearchTool parameter parsing, context override, and exception handling', () async {
      final tool = WebSearchTool(searchService: mockSearch, searxngUrl: 'https://default.searx');

      // Whitespace query
      final emptyRes = await tool.execute({'query': '   \t\n  '});
      expect(emptyRes.success, isFalse);
      expect(emptyRes.errorMessage, contains('搜索关键词不能为空'));

      // Context override for SearXNG URL
      mockSearch.searchResults = [
        SearchResult(title: 'Title 1', url: 'https://t1.com', content: 'Snippet 1'),
      ];
      final res = await tool.execute({
        'query': 'flutter agent',
        '__searxngUrl': 'https://custom.searx',
      });
      expect(res.success, isTrue);
      expect(mockSearch.capturedSearxngUrl, equals('https://custom.searx'));
      expect(mockSearch.capturedBackend, equals('searxng'));

      // Generic exception handling
      mockSearch.genericException = Exception('Connection reset by peer');
      final failRes = await tool.execute({'query': 'test'});
      expect(failRes.success, isFalse);
      expect(failRes.errorMessage, contains('搜索出现未知异常'));
    });

    test('GoogleSearchTool arguments & context override parameters', () async {
      final tool = GoogleSearchTool(searchService: mockSearch);

      mockSearch.searchResults = [
        SearchResult(title: 'Google Result', url: 'https://g.com', content: 'G-Snippet'),
      ];

      final res = await tool.execute({
        'query': 'deep learning',
        '__googleApiKey': 'secret_key_123',
        '__googleBaseUrl': 'https://custom.google.api',
        '__googleSearchModel': 'gemini-1.5-pro',
      });

      expect(res.success, isTrue);
      expect(mockSearch.capturedGoogleApiKey, equals('secret_key_123'));
      expect(mockSearch.capturedGoogleBaseUrl, equals('https://custom.google.api'));
      expect(mockSearch.capturedGoogleModel, equals('gemini-1.5-pro'));
      expect(mockSearch.capturedBackend, equals('google'));
    });

    test('BingSearchTool arguments & context override parameters', () async {
      final tool = BingSearchTool(searchService: mockSearch);

      mockSearch.searchResults = [
        SearchResult(title: 'Bing Result', url: 'https://b.com', content: 'B-Snippet'),
      ];

      final res = await tool.execute({
        'query': 'microsoft',
        '__bingCookie': 'auth_cookie_xyz',
      });

      expect(res.success, isTrue);
      expect(mockSearch.capturedBingCookie, equals('auth_cookie_xyz'));
      expect(mockSearch.capturedBackend, equals('bing'));
    });

    test('UrlFetchTool arguments, maxCharacters context, and error status handling', () async {
      final tool = UrlFetchTool(urlFetchService: mockFetch);

      // Empty url
      final emptyUrl = await tool.execute({'url': '  '});
      expect(emptyUrl.success, isFalse);
      expect(emptyUrl.errorMessage, contains('URL 不能为空'));

      // Success url fetch with custom maxCharacters
      final success = await tool.execute({
        'url': 'https://dart.dev',
        '__maxCharacters': 8000,
      });
      expect(success.success, isTrue);
      expect(mockFetch.capturedMaxCharacters, equals(8000));
      expect(success.content, contains('Mock content for https://dart.dev'));

      // Service throwing generic exception
      mockFetch.exceptionToThrow = Exception('SocketException: Connection refused');
      final exRes = await tool.execute({'url': 'https://broken.link'});
      expect(exRes.success, isFalse);
      expect(exRes.errorMessage, contains('抓取网页异常: Exception: SocketException: Connection refused'));
    });
  });

  group('5. ToolExecutionResult Edge Cases & JSON Integrity', () {
    test('ToolExecutionResult serialization with nulls and special characters', () {
      final result = ToolExecutionResult(
        toolName: 'complex_tool',
        success: false,
        content: 'Special chars: <>&"\'\n\t🚀',
        errorMessage: 'Something broke: \u0000',
        executionDuration: const Duration(seconds: 2, milliseconds: 500),
        metadata: {'k1': null, 'k2': [1, 2, 3]},
      );

      final json = result.toJson();
      expect(json['toolName'], equals('complex_tool'));
      expect(json['success'], isFalse);
      expect(json['content'], equals('Special chars: <>&"\'\n\t🚀'));
      expect(json['errorMessage'], equals('Something broke: \u0000'));
      expect(json['executionDurationMs'], equals(2500));

      final restored = ToolExecutionResult.fromJson(json);
      expect(restored.toolName, equals(result.toolName));
      expect(restored.success, equals(result.success));
      expect(restored.content, equals(result.content));
      expect(restored.errorMessage, equals(result.errorMessage));
      expect(restored.executionDuration.inMilliseconds, equals(2500));
    });

    test('ToolExecutionResult.fromJson handles missing fields with safe fallbacks', () {
      final restored = ToolExecutionResult.fromJson({});
      expect(restored.toolName, equals(''));
      expect(restored.success, isFalse);
      expect(restored.content, equals(''));
      expect(restored.errorMessage, isNull);
      expect(restored.executionDuration, equals(Duration.zero));
      expect(restored.timestamp, isNotNull);
    });
  });
}
