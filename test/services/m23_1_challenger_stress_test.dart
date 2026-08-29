import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/tool/tool.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/tools/legacy_tool_adapters.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/url_fetch_service.dart';

/// Test mock tool for stress testing.
class ComplexStressTool extends Tool {
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

  final Future<ToolExecutionResult> Function(Map<String, dynamic> args)? onExecute;

  const ComplexStressTool({
    required this.name,
    this.displayName = 'Complex Stress Tool',
    this.description = 'A complex tool for empirical stress testing',
    this.securityLevel = ToolSecurityLevel.safe,
    this.parameters = const [],
    this.onExecute,
  });

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    if (onExecute != null) {
      return onExecute!(arguments);
    }
    return ToolExecutionResult.success(
      toolName: name,
      content: 'Stress tool executed',
      rawData: arguments,
    );
  }
}

/// Controllable mock SearchService for stress tests.
class StressMockSearchService extends SearchService {
  List<SearchResult> resultsToReturn = [];
  dynamic errorToThrow;
  Duration simulatedDelay = Duration.zero;

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
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    if (errorToThrow != null) {
      throw errorToThrow;
    }
    return resultsToReturn;
  }

  @override
  String formatSearchResultsForContext(List<SearchResult> results) {
    if (results.isEmpty) return '没有找到相关搜索结果。';
    return results.map((r) => '1. [${r.title}](${r.url})\n   摘要: ${r.content}').join('\n\n');
  }
}

/// Controllable mock UrlFetchService for stress tests.
class StressMockUrlFetchService extends UrlFetchService {
  FetchResult? resultToReturn;
  dynamic errorToThrow;
  Duration simulatedDelay = Duration.zero;

  @override
  Future<FetchResult> fetchUrl(
    String url, {
    CancelToken? cancelToken,
    int maxCharacters = UrlFetchService.defaultMaxCharacters,
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future.delayed(simulatedDelay);
    }
    if (errorToThrow != null) {
      throw errorToThrow;
    }
    return resultToReturn ??
        FetchResult(
          url: url,
          status: 'success',
          pageType: 'article',
          truncated: false,
          originalLength: 500,
          maxLength: maxCharacters,
          contentRatio: 0.9,
          mainContent: '# Sample Page\nFetched content from $url',
          metadata: const FetchMetadata(title: 'Stress Page Title', author: 'Stress Bot'),
          totalLinks: 5,
          internalLinks: 3,
          externalLinks: 2,
          warnings: const [],
        );
  }
}

void main() {
  group('Empirical Stress: OpenAI Function Calling JSON Schema Compliance', () {
    test('OpenAI Schema strict structural conformance across diverse parameter types', () {
      const tool = ComplexStressTool(
        name: 'test_advanced_schema',
        displayName: '高级 Schema 测试',
        description: 'Deep parameter schema validation',
        parameters: [
          ToolParameter(
            name: 'str_required',
            type: 'string',
            description: 'Required string param',
            required: true,
          ),
          ToolParameter(
            name: 'str_enum',
            type: 'string',
            description: 'String param with enum constraints',
            required: false,
            enumValues: ['optionA', 'optionB', 'optionC'],
            defaultValue: 'optionA',
          ),
          ToolParameter(
            name: 'num_opt',
            type: 'number',
            description: 'Optional floating point number',
            required: false,
            defaultValue: 3.14159,
          ),
          ToolParameter(
            name: 'int_req',
            type: 'integer',
            description: 'Required integer count',
            required: true,
          ),
          ToolParameter(
            name: 'bool_opt',
            type: 'boolean',
            description: 'Optional boolean flag',
            required: false,
            defaultValue: true,
          ),
          ToolParameter(
            name: 'arr_strings',
            type: 'array',
            description: 'List of string tags',
            required: false,
            arrayItemType: 'string',
          ),
          ToolParameter(
            name: 'obj_metadata',
            type: 'object',
            description: 'Custom metadata object',
            required: false,
          ),
        ],
      );

      final schema = tool.toOpenAiSchema();

      // Top-level structure verification
      expect(schema['type'], equals('function'));
      expect(schema.containsKey('function'), isTrue);

      final fn = schema['function'] as Map<String, dynamic>;
      expect(fn['name'], equals('test_advanced_schema'));
      expect(fn['description'], equals('Deep parameter schema validation'));
      expect(fn.containsKey('parameters'), isTrue);

      final params = fn['parameters'] as Map<String, dynamic>;
      expect(params['type'], equals('object'));
      expect(params['properties'], isA<Map<String, dynamic>>());
      expect(params['required'], isA<List<String>>());

      final props = params['properties'] as Map<String, dynamic>;
      final required = params['required'] as List<String>;

      // Check required list
      expect(required, equals(['str_required', 'int_req']));

      // Check individual property definitions
      expect(props['str_required']['type'], equals('string'));
      expect(props['str_required']['description'], equals('Required string param'));
      expect(props['str_required'].containsKey('enum'), isFalse);
      expect(props['str_required'].containsKey('default'), isFalse);

      expect(props['str_enum']['type'], equals('string'));
      expect(props['str_enum']['enum'], equals(['optionA', 'optionB', 'optionC']));
      expect(props['str_enum']['default'], equals('optionA'));

      expect(props['num_opt']['type'], equals('number'));
      expect(props['num_opt']['default'], equals(3.14159));

      expect(props['int_req']['type'], equals('integer'));

      expect(props['bool_opt']['type'], equals('boolean'));
      expect(props['bool_opt']['default'], isTrue);

      expect(props['arr_strings']['type'], equals('array'));
      expect(props['arr_strings']['items'], equals({'type': 'string'}));

      expect(props['obj_metadata']['type'], equals('object'));

      // Ensure JSON serializability with zero errors or cycles
      final jsonString = jsonEncode(schema);
      expect(jsonString, isNotEmpty);
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      expect(decoded['function']['name'], equals('test_advanced_schema'));
    });

    test('Zero-parameter and all-optional tool schemas conform to OpenAI spec', () {
      const zeroParamTool = ComplexStressTool(
        name: 'no_params_tool',
        description: 'Tool without params',
        parameters: [],
      );

      final zeroSchema = zeroParamTool.toOpenAiSchema();
      final zeroFn = zeroSchema['function'] as Map<String, dynamic>;
      final zeroParams = zeroFn['parameters'] as Map<String, dynamic>;
      expect(zeroParams['type'], equals('object'));
      expect(zeroParams['properties'], isEmpty);
      expect(zeroParams['required'], isEmpty);

      const allOptTool = ComplexStressTool(
        name: 'all_opt_tool',
        description: 'All optional params',
        parameters: [
          ToolParameter(name: 'opt1', description: 'desc1', required: false),
          ToolParameter(name: 'opt2', description: 'desc2', required: false),
        ],
      );

      final optSchema = allOptTool.toOpenAiSchema();
      final optFn = optSchema['function'] as Map<String, dynamic>;
      final optParams = optFn['parameters'] as Map<String, dynamic>;
      expect(optParams['required'], isEmpty);
      expect((optParams['properties'] as Map).length, equals(2));
    });

    test('ToolRegistry complex exportOpenAiSchemas filtering combinations', () {
      final registry = ToolRegistry();
      registry.registerTools([
        const ComplexStressTool(name: 't_safe_1', securityLevel: ToolSecurityLevel.safe),
        const ComplexStressTool(name: 't_safe_2', securityLevel: ToolSecurityLevel.safe),
        const ComplexStressTool(name: 't_read_1', securityLevel: ToolSecurityLevel.readOnly),
        const ComplexStressTool(name: 't_sens_1', securityLevel: ToolSecurityLevel.sensitiveConfirm),
        const ComplexStressTool(name: 't_priv_1', securityLevel: ToolSecurityLevel.privilegedNative),
      ]);

      // Disable one safe tool and one sensitive tool
      registry.setToolEnabled('t_safe_2', false);
      registry.setToolEnabled('t_sens_1', false);

      // Combination 1: onlyEnabled: true, maxSecurityLevel: readOnly
      final res1 = registry.exportOpenAiSchemas(
        onlyEnabled: true,
        maxSecurityLevel: ToolSecurityLevel.readOnly,
      );
      final names1 = res1.map((s) => s['function']['name']).toList();
      expect(names1, equals(['t_safe_1', 't_read_1']));

      // Combination 2: toolNames specified with onlyEnabled: true
      final res2 = registry.exportOpenAiSchemas(
        toolNames: ['t_safe_1', 't_safe_2', 't_priv_1'],
        onlyEnabled: true,
      );
      final names2 = res2.map((s) => s['function']['name']).toList();
      expect(names2, equals(['t_safe_1', 't_priv_1']));

      // Combination 3: toolNames with onlyEnabled: false and maxSecurityLevel: safe
      final res3 = registry.exportOpenAiSchemas(
        toolNames: ['t_safe_1', 't_safe_2', 't_read_1'],
        onlyEnabled: false,
        maxSecurityLevel: ToolSecurityLevel.safe,
      );
      final names3 = res3.map((s) => s['function']['name']).toList();
      expect(names3, equals(['t_safe_1', 't_safe_2']));
    });
  });

  group('Empirical Stress: Legacy Adapters with Adversarial Inputs & Exceptions', () {
    late StressMockSearchService mockSearch;
    late StressMockUrlFetchService mockFetch;

    setUp(() {
      mockSearch = StressMockSearchService();
      mockFetch = StressMockUrlFetchService();
    });

    test('WebSearchTool stress: empty, whitespace, special chars, and massive query string', () async {
      final tool = WebSearchTool(searchService: mockSearch, searxngUrl: 'https://searxng.org');

      // Missing / null query via parameter validation
      final nullQueryRes = tool.validateArguments({});
      expect(nullQueryRes, contains("缺少必需参数 'query'"));

      // Empty string query
      final emptyRes = await tool.execute({'query': ''});
      expect(emptyRes.success, isFalse);
      expect(emptyRes.errorMessage, equals('搜索关键词不能为空'));

      // Whitespace only query
      final wsRes = await tool.execute({'query': '   \n\t  '});
      expect(wsRes.success, isFalse);
      expect(wsRes.errorMessage, equals('搜索关键词不能为空'));

      // Adversarial special characters & massive string
      final massiveQuery = '🚀 测试 Unicode 搜索! & <script>alert(1)</script> ' * 100;
      mockSearch.resultsToReturn = [
        SearchResult(title: 'Special Result', url: 'https://special.org', content: 'Escaped content & snippets'),
      ];
      final massiveRes = await tool.execute({'query': massiveQuery});
      expect(massiveRes.success, isTrue);
      expect(massiveRes.metadata?['query'], equals(massiveQuery.trim()));
      expect(massiveRes.content, contains('Special Result'));
    });

    test('WebSearchTool stress: SearXNG URL dynamic overrides via args and context', () async {
      final tool = WebSearchTool(searchService: mockSearch, searxngUrl: 'https://default-searx.com');

      mockSearch.resultsToReturn = [
        SearchResult(title: 'Test', url: 'https://test.com', content: 'snippet'),
      ];

      // Standard call
      await tool.execute({'query': 'dart'});

      // Context override with __searxngUrl
      final resWithContext = await tool.execute({
        'query': 'flutter',
        '__searxngUrl': 'https://override-context-searx.com',
      });
      expect(resWithContext.success, isTrue);

      // Direct arg override with searxngUrl
      final resWithArg = await tool.execute({
        'query': 'riverpod',
        'searxngUrl': 'https://override-arg-searx.com',
      });
      expect(resWithArg.success, isTrue);
    });

    test('WebSearchTool stress: handling SearchException, DioException, SocketException, and generic errors', () async {
      final tool = WebSearchTool(searchService: mockSearch);

      // 1. SearchException with 500 status code
      mockSearch.errorToThrow = SearchException(
        message: 'Internal SearXNG 500 Server Error',
        source: 'SearXNG',
        statusCode: 500,
        details: 'engine timeout: duckduckgo',
      );
      final searchExRes = await tool.execute({'query': 'error_test'});
      expect(searchExRes.success, isFalse);
      expect(searchExRes.errorMessage, equals('Internal SearXNG 500 Server Error'));
      expect(searchExRes.content, contains('搜索失败：Internal SearXNG 500 Server Error'));
      expect(searchExRes.metadata?['statusCode'], equals(500));
      expect(searchExRes.metadata?['source'], equals('SearXNG'));

      // 2. DioException simulation
      mockSearch.errorToThrow = DioException(
        requestOptions: RequestOptions(path: '/search'),
        message: 'Connection refused',
        type: DioExceptionType.connectionError,
      );
      final dioExRes = await tool.execute({'query': 'dio_error'});
      expect(dioExRes.success, isFalse);
      expect(dioExRes.errorMessage, contains('搜索出现未知异常'));
      expect(dioExRes.errorMessage, contains('Connection refused'));

      // 3. FormatException simulation
      mockSearch.errorToThrow = const FormatException('Invalid JSON from search backend');
      final formatExRes = await tool.execute({'query': 'format_error'});
      expect(formatExRes.success, isFalse);
      expect(formatExRes.errorMessage, contains('搜索出现未知异常: FormatException: Invalid JSON'));

      // 4. StateError / Error simulation
      mockSearch.errorToThrow = StateError('Corrupted state in search adapter');
      final stateErrRes = await tool.execute({'query': 'state_error'});
      expect(stateErrRes.success, isFalse);
      expect(stateErrRes.errorMessage, contains('搜索出现未知异常: Bad state: Corrupted state'));
    });

    test('GoogleSearchTool & BingSearchTool stress: parameter overrides and exception isolation', () async {
      final googleTool = GoogleSearchTool(
        searchService: mockSearch,
        googleApiKey: 'default_google_key',
        googleBaseUrl: 'https://default.google.api',
        googleSearchModel: 'models/gemini-pro',
      );
      final bingTool = BingSearchTool(
        searchService: mockSearch,
        bingCookie: 'default_cookie',
      );

      // GoogleSearchTool empty query
      final gEmpty = await googleTool.execute({'query': ''});
      expect(gEmpty.success, isFalse);
      expect(gEmpty.errorMessage, equals('搜索关键词不能为空'));

      // GoogleSearchTool custom overrides
      mockSearch.resultsToReturn = [
        SearchResult(title: 'Google Grounded', url: 'https://google.com/grounded', content: 'Grounded content'),
      ];
      final gSuccess = await googleTool.execute({
        'query': 'quantum computing',
        'googleApiKey': 'override_key',
        'googleBaseUrl': 'https://custom.api',
        'googleSearchModel': 'models/gemini-1.5-pro',
      });
      expect(gSuccess.success, isTrue);
      expect(gSuccess.metadata?['backend'], equals('google'));

      // GoogleSearchTool error handling
      mockSearch.errorToThrow = SearchException(
        message: 'Google Grounding Quota Exceeded',
        source: 'Google',
        statusCode: 429,
      );
      final gFail = await googleTool.execute({'query': 'rate_limit'});
      expect(gFail.success, isFalse);
      expect(gFail.errorMessage, equals('Google Grounding Quota Exceeded'));
      expect(gFail.metadata?['statusCode'], equals(429));

      // BingSearchTool error handling
      mockSearch.errorToThrow = const FormatException('Bing HTML parsing failure');
      final bFail = await bingTool.execute({'query': 'bing_parse_error'});
      expect(bFail.success, isFalse);
      expect(bFail.errorMessage, contains('Bing 搜索出现异常: FormatException: Bing HTML parsing failure'));
    });

    test('UrlFetchTool stress: malformed URLs, HTTP error statuses, and custom character limits', () async {
      final urlTool = UrlFetchTool(urlFetchService: mockFetch);

      // Missing / empty URL
      final emptyRes = await urlTool.execute({'url': '   '});
      expect(emptyRes.success, isFalse);
      expect(emptyRes.errorMessage, equals('URL 不能为空'));

      // Successful fetch with rich metadata
      mockFetch.resultToReturn = const FetchResult(
        url: 'https://dart.dev/guides/libraries',
        status: 'success',
        pageType: 'doc',
        truncated: true,
        originalLength: 25000,
        maxLength: 8000,
        contentRatio: 0.75,
        mainContent: '# Dart Libraries\nDocumentation content here...',
        metadata: FetchMetadata(
          title: 'Dart Guide',
          author: 'Google',
          publishedAt: '2026-01-01',
          siteName: 'dart.dev',
          language: 'en',
        ),
        totalLinks: 25,
        internalLinks: 20,
        externalLinks: 5,
        warnings: ['Content truncated at 8000 chars'],
      );

      final successRes = await urlTool.execute({
        'url': 'https://dart.dev/guides/libraries',
        'maxCharacters': 8000,
      });

      expect(successRes.success, isTrue);
      expect(successRes.metadata?['title'], equals('Dart Guide'));
      expect(successRes.metadata?['pageType'], equals('doc'));
      expect(successRes.metadata?['truncated'], isTrue);
      expect(successRes.metadata?['originalLength'], equals(25000));
      expect(successRes.content, contains('Dart Guide'));
      expect(successRes.content, contains('Dart Libraries'));

      // FetchResult with status == 'error' (e.g. 403 Forbidden / Captcha Block)
      mockFetch.resultToReturn = const FetchResult(
        url: 'https://protected.com',
        status: 'error',
        pageType: 'captcha',
        truncated: false,
        originalLength: 0,
        maxLength: 15000,
        contentRatio: 0.0,
        mainContent: '无法抓取该网页：检测到 Cloudflare 验证码防护拦截',
        metadata: FetchMetadata(title: 'Security Verification'),
        totalLinks: 0,
        internalLinks: 0,
        externalLinks: 0,
        warnings: ['Cloudflare WAF Block'],
      );

      final blockRes = await urlTool.execute({'url': 'https://protected.com'});
      expect(blockRes.success, isFalse);
      expect(blockRes.errorMessage, contains('检测到 Cloudflare 验证码防护拦截'));
      expect(blockRes.metadata?['pageType'], equals('captcha'));
      expect(blockRes.metadata?['status'], equals('error'));

      // Fetch throwing unexpected network exception
      mockFetch.errorToThrow = DioException(
        requestOptions: RequestOptions(path: 'https://timeout.com'),
        type: DioExceptionType.receiveTimeout,
        message: 'Receive timeout after 10000ms',
      );

      final timeoutRes = await urlTool.execute({'url': 'https://timeout.com'});
      expect(timeoutRes.success, isFalse);
      expect(timeoutRes.errorMessage, contains('抓取网页异常'));
      expect(timeoutRes.errorMessage, contains('Receive timeout'));
    });

    test('Execution duration measurement under simulated delay', () async {
      mockSearch.simulatedDelay = const Duration(milliseconds: 60);
      mockSearch.resultsToReturn = [
        SearchResult(title: 'Fast', url: 'https://fast.org', content: 'content'),
      ];

      final tool = WebSearchTool(searchService: mockSearch);
      final res = await tool.execute({'query': 'benchmark'});

      expect(res.success, isTrue);
      expect(res.executionDuration.inMilliseconds, greaterThanOrEqualTo(40));
    });
  });

  group('Empirical Stress: ToolRegistry Execution Dispatcher & Type Coercion', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry();
    });

    test('ToolRegistry parameter validation edge cases: integer, number, boolean, array, object', () async {
      registry.register(
        const ComplexStressTool(
          name: 'strict_types',
          parameters: [
            ToolParameter(name: 'int_val', type: 'integer', description: 'int value', required: true),
            ToolParameter(name: 'num_val', type: 'number', description: 'num value', required: true),
            ToolParameter(name: 'bool_val', type: 'boolean', description: 'bool value', required: true),
            ToolParameter(name: 'arr_val', type: 'array', description: 'arr value', required: true),
            ToolParameter(name: 'obj_val', type: 'object', description: 'obj value', required: true),
          ],
        ),
      );

      // 1. Missing required int_val
      final missingRes = await registry.execute('strict_types', {
        'num_val': 1.23,
        'bool_val': true,
        'arr_val': [],
        'obj_val': {},
      });
      expect(missingRes.success, isFalse);
      expect(missingRes.errorMessage, contains("缺少必需参数 'int_val'"));

      // 2. Stringified valid values should pass validation
      final stringifiedRes = await registry.execute('strict_types', {
        'int_val': '123',
        'num_val': '45.67',
        'bool_val': 'true',
        'arr_val': [1, 2, 3],
        'obj_val': {'key': 'value'},
      });
      expect(stringifiedRes.success, isTrue);

      // 3. Stringified 'false' should pass boolean validation
      final boolFalseRes = await registry.execute('strict_types', {
        'int_val': 10,
        'num_val': 20,
        'bool_val': 'false',
        'arr_val': ['a'],
        'obj_val': {'k': 'v'},
      });
      expect(boolFalseRes.success, isTrue);

      // 4. Invalid integer float string
      final invalidIntRes = await registry.execute('strict_types', {
        'int_val': '3.14',
        'num_val': 20,
        'bool_val': true,
        'arr_val': [],
        'obj_val': {},
      });
      expect(invalidIntRes.success, isFalse);
      expect(invalidIntRes.errorMessage, contains("应为整数类型 (integer)"));

      // 5. Invalid array (passed String instead of List)
      final invalidArrRes = await registry.execute('strict_types', {
        'int_val': 10,
        'num_val': 20,
        'bool_val': true,
        'arr_val': 'not_an_array',
        'obj_val': {},
      });
      expect(invalidArrRes.success, isFalse);
      expect(invalidArrRes.errorMessage, contains("应为列表类型 (array)"));

      // 6. Invalid object (passed List instead of Map)
      final invalidObjRes = await registry.execute('strict_types', {
        'int_val': 10,
        'num_val': 20,
        'bool_val': true,
        'arr_val': [],
        'obj_val': ['not_a_map'],
      });
      expect(invalidObjRes.success, isFalse);
      expect(invalidObjRes.errorMessage, contains("应为对象类型 (object)"));
    });

    test('ToolRegistry context parameter injection into execution arguments', () async {
      registry.register(
        ComplexStressTool(
          name: 'context_inspect_tool',
          parameters: const [
            ToolParameter(name: 'input', description: 'user input', required: true),
          ],
          onExecute: (args) async {
            return ToolExecutionResult.success(
              toolName: 'context_inspect_tool',
              content: 'Success',
              rawData: args,
            );
          },
        ),
      );

      final res = await registry.execute(
        'context_inspect_tool',
        {'input': 'hello'},
        context: {
          'conversationId': 'conv_999',
          'userId': 'user_888',
        },
      );

      expect(res.success, isTrue);
      final rawArgs = res.rawData as Map<String, dynamic>;
      expect(rawArgs['input'], equals('hello'));
      expect(rawArgs['conversationId'], equals('conv_999'));
      expect(rawArgs['__conversationId'], equals('conv_999'));
      expect(rawArgs['userId'], equals('user_888'));
      expect(rawArgs['__userId'], equals('user_888'));
    });

    test('ToolRegistry lifecycle: dynamic registration overwrite and clear states', () {
      expect(registry.getAllTools(), isEmpty);

      const toolV1 = ComplexStressTool(name: 'versioned_tool', description: 'v1');
      registry.register(toolV1);
      expect(registry.getTool('versioned_tool')?.description, equals('v1'));
      expect(registry.isToolEnabled('versioned_tool'), isTrue);

      // Disable v1
      registry.setToolEnabled('versioned_tool', false);
      expect(registry.isToolEnabled('versioned_tool'), isFalse);

      // Overwrite with v2 (enabled by default)
      const toolV2 = ComplexStressTool(name: 'versioned_tool', description: 'v2');
      registry.register(toolV2, enabled: true);
      expect(registry.getTool('versioned_tool')?.description, equals('v2'));
      expect(registry.isToolEnabled('versioned_tool'), isTrue);

      // Unregister
      expect(registry.unregister('versioned_tool'), isTrue);
      expect(registry.hasTool('versioned_tool'), isFalse);
      expect(registry.isToolEnabled('versioned_tool'), isFalse);
    });
  });
}
