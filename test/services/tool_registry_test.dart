import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:chat/models/tool/tool.dart';
import 'package:chat/services/tool_registry.dart';
import 'package:chat/services/tools/legacy_tool_adapters.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/services/url_fetch_service.dart';

/// Test tool with controllable behavior.
class SimpleMockTool extends Tool {
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

  const SimpleMockTool({
    required this.name,
    this.displayName = 'Mock Tool',
    this.description = 'A mock tool for testing',
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
      content: 'Mock executed for $name',
      rawData: arguments,
    );
  }
}

/// Mock search service for testing legacy adapters.
class MockSearchService extends SearchService {
  List<SearchResult> mockResults = [];
  SearchException? exceptionToThrow;
  Exception? otherExceptionToThrow;

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
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    if (otherExceptionToThrow != null) {
      throw otherExceptionToThrow!;
    }
    return mockResults;
  }

  @override
  String formatSearchResultsForContext(List<SearchResult> results) {
    if (results.isEmpty) return 'No results found.';
    return results.map((r) => '1. [${r.title}](${r.url})\n   摘要: ${r.content}').join('\n\n');
  }
}

/// Mock url fetch service for testing UrlFetchTool.
class MockUrlFetchService extends UrlFetchService {
  FetchResult? mockResult;
  Exception? exceptionToThrow;

  @override
  Future<FetchResult> fetchUrl(
    String url, {
    CancelToken? cancelToken,
    int maxCharacters = UrlFetchService.defaultMaxCharacters,
  }) async {
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    return mockResult ??
        FetchResult(
          url: url,
          status: 'success',
          pageType: 'article',
          truncated: false,
          originalLength: 100,
          maxLength: 15000,
          contentRatio: 0.8,
          mainContent: 'Mock page content for $url',
          metadata: const FetchMetadata(title: 'Mock Page'),
          totalLinks: 0,
          internalLinks: 0,
          externalLinks: 0,
          warnings: const [],
        );
  }
}

void main() {
  group('ToolRegistry CRUD & Query Tests', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry();
    });

    test('Register single tool and lookup', () {
      const tool1 = SimpleMockTool(name: 'tool_a', displayName: 'Tool A');
      registry.register(tool1);

      expect(registry.hasTool('tool_a'), isTrue);
      expect(registry.hasTool('tool_b'), isFalse);
      expect(registry.getTool('tool_a')?.displayName, equals('Tool A'));
      expect(registry.getRegisteredNames(), equals(['tool_a']));
      expect(registry.getAllTools().length, equals(1));
    });

    test('Bulk registration and clear', () {
      const tool1 = SimpleMockTool(name: 'tool_1');
      const tool2 = SimpleMockTool(name: 'tool_2');
      const tool3 = SimpleMockTool(name: 'tool_3');

      registry.registerTools([tool1, tool2, tool3]);
      expect(registry.getAllTools().length, equals(3));
      expect(registry.getRegisteredNames(), containsAll(['tool_1', 'tool_2', 'tool_3']));

      registry.clear();
      expect(registry.getAllTools().isEmpty, isTrue);
      expect(registry.getRegisteredNames().isEmpty, isTrue);
    });

    test('Unregister existing and non-existent tools', () {
      const tool1 = SimpleMockTool(name: 'tool_x');
      registry.register(tool1);

      expect(registry.unregister('tool_x'), isTrue);
      expect(registry.hasTool('tool_x'), isFalse);
      expect(registry.unregister('tool_x'), isFalse);
      expect(registry.unregister('non_existent'), isFalse);
    });
  });

  group('ToolRegistry Enablement Management Tests', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry();
      registry.registerTools([
        const SimpleMockTool(name: 'tool_1'),
        const SimpleMockTool(name: 'tool_2'),
        const SimpleMockTool(name: 'tool_3'),
      ]);
    });

    test('Enable/disable toggle, isToolEnabled, getEnabledTools', () {
      expect(registry.isToolEnabled('tool_1'), isTrue);
      expect(registry.getEnabledNames().length, equals(3));

      registry.setToolEnabled('tool_2', false);
      expect(registry.isToolEnabled('tool_2'), isFalse);
      expect(registry.getEnabledNames(), equals(['tool_1', 'tool_3']));
      expect(registry.getEnabledTools().map((t) => t.name), equals(['tool_1', 'tool_3']));

      // Non-existent tool returns false
      expect(registry.isToolEnabled('unknown'), isFalse);
    });

    test('EnableAll, disableAll, and resetEnablement', () {
      registry.disableAll();
      expect(registry.getEnabledNames(), isEmpty);
      expect(registry.isToolEnabled('tool_1'), isFalse);

      registry.enableAll();
      expect(registry.getEnabledNames().length, equals(3));

      registry.setToolEnabled('tool_1', false);
      registry.resetEnablement();
      expect(registry.isToolEnabled('tool_1'), isTrue);
    });
  });

  group('ToolRegistry OpenAI Schema Export Filtering Tests', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry();
      registry.registerTools([
        const SimpleMockTool(name: 'safe_tool', securityLevel: ToolSecurityLevel.safe),
        const SimpleMockTool(name: 'read_tool', securityLevel: ToolSecurityLevel.readOnly),
        const SimpleMockTool(name: 'sensitive_tool', securityLevel: ToolSecurityLevel.sensitiveConfirm),
        const SimpleMockTool(name: 'native_tool', securityLevel: ToolSecurityLevel.privilegedNative),
      ]);
    });

    test('Export OpenAI schemas with name filtering', () {
      final schemas = registry.exportOpenAiSchemas(toolNames: ['safe_tool', 'native_tool']);
      expect(schemas.length, equals(2));
      final names = schemas.map((s) => s['function']['name'] as String).toList();
      expect(names, equals(['safe_tool', 'native_tool']));
    });

    test('Export OpenAI schemas with onlyEnabled filtering', () {
      registry.setToolEnabled('read_tool', false);

      final enabledSchemas = registry.exportOpenAiSchemas(onlyEnabled: true);
      expect(enabledSchemas.length, equals(3));
      expect(enabledSchemas.any((s) => s['function']['name'] == 'read_tool'), isFalse);

      final allSchemas = registry.exportOpenAiSchemas(onlyEnabled: false);
      expect(allSchemas.length, equals(4));
    });

    test('Export OpenAI schemas with maxSecurityLevel filtering', () {
      final safeOnly = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.safe);
      expect(safeOnly.length, equals(1));
      expect(safeOnly.first['function']['name'], equals('safe_tool'));

      final upToReadOnly = registry.exportOpenAiSchemas(maxSecurityLevel: ToolSecurityLevel.readOnly);
      expect(upToReadOnly.length, equals(2));
      expect(upToReadOnly.map((s) => s['function']['name']), containsAll(['safe_tool', 'read_tool']));
    });
  });

  group('ToolRegistry Execution Dispatcher Tests', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry();
    });

    test('Execution dispatcher on success with valid args and context injection', () async {
      registry.register(
        SimpleMockTool(
          name: 'echo_tool',
          parameters: const [
            ToolParameter(name: 'text', description: 'Input text', required: true),
          ],
          onExecute: (args) async {
            return ToolExecutionResult.success(
              toolName: 'echo_tool',
              content: 'Echo: ${args['text']} | session: ${args['sessionId']}',
              rawData: args,
            );
          },
        ),
      );

      final result = await registry.execute(
        'echo_tool',
        {'text': 'Hello World'},
        context: {'sessionId': 'sess_123'},
      );

      expect(result.success, isTrue);
      expect(result.content, equals('Echo: Hello World | session: sess_123'));
      expect(result.errorMessage, isNull);
    });

    test('Execution dispatcher handles non-existent tool', () async {
      final result = await registry.execute('ghost_tool', {'arg': 1});
      expect(result.success, isFalse);
      expect(result.errorMessage, contains("未找到工具 'ghost_tool'"));
    });

    test('Execution dispatcher handles disabled tool', () async {
      const tool = SimpleMockTool(name: 'disabled_tool');
      registry.register(tool, enabled: false);

      final result = await registry.execute('disabled_tool', {});
      expect(result.success, isFalse);
      expect(result.errorMessage, contains("当前已被禁用"));
    });

    test('Execution dispatcher handles parameter validation failure', () async {
      const tool = SimpleMockTool(
        name: 'strict_tool',
        parameters: [
          ToolParameter(name: 'required_num', type: 'number', description: 'A number', required: true),
        ],
      );
      registry.register(tool);

      final result = await registry.execute('strict_tool', {'required_num': 'not_a_number'});
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('参数校验失败'));
      expect(result.errorMessage, contains('应为数值类型'));
    });

    test('Execution dispatcher catches unexpected runtime exceptions', () async {
      final tool = SimpleMockTool(
        name: 'throw_tool',
        onExecute: (args) async {
          throw Exception('Simulated network timeout crash');
        },
      );
      registry.register(tool);

      final result = await registry.execute('throw_tool', {});
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('工具执行异常: Exception: Simulated network timeout crash'));
      expect(result.metadata?['exception'], contains('Simulated network timeout crash'));
    });
  });

  group('Legacy Adapters Tests', () {
    test('WebSearchTool executes search and handles SearchException', () async {
      final mockSearchService = MockSearchService();
      final webSearch = WebSearchTool(searchService: mockSearchService, searxngUrl: 'https://searx.test');

      // 1. Empty query
      final emptyResult = await webSearch.execute({'query': '   '});
      expect(emptyResult.success, isFalse);
      expect(emptyResult.errorMessage, contains('搜索关键词不能为空'));

      // 2. Successful search
      mockSearchService.mockResults = [
        SearchResult(title: 'Flutter Dev', url: 'https://flutter.dev', content: 'Fast UI Toolkit'),
      ];
      final successResult = await webSearch.execute({'query': 'flutter'});
      expect(successResult.success, isTrue);
      expect(successResult.content, contains('Flutter Dev'));
      expect(successResult.metadata?['resultCount'], equals(1));

      // 3. SearchException
      mockSearchService.exceptionToThrow = SearchException(
        message: 'SearXNG 实例连接超时',
        source: 'SearXNG',
        statusCode: 504,
      );
      final exResult = await webSearch.execute({'query': 'timeout'});
      expect(exResult.success, isFalse);
      expect(exResult.errorMessage, equals('SearXNG 实例连接超时'));
      expect(exResult.metadata?['statusCode'], equals(504));
    });

    test('GoogleSearchTool, BingSearchTool, and UrlFetchTool integration', () async {
      final mockSearchService = MockSearchService();
      final googleTool = GoogleSearchTool(searchService: mockSearchService);
      final bingTool = BingSearchTool(searchService: mockSearchService);

      mockSearchService.mockResults = [
        SearchResult(title: 'Google Res', url: 'https://google.com', content: 'Snippet'),
      ];

      final gResult = await googleTool.execute({'query': 'ai'});
      expect(gResult.success, isTrue);
      expect(gResult.metadata?['backend'], equals('google'));

      final bResult = await bingTool.execute({'query': 'bing'});
      expect(bResult.success, isTrue);
      expect(bResult.metadata?['backend'], equals('bing'));

      // UrlFetchTool
      final mockFetchService = MockUrlFetchService();
      final urlFetch = UrlFetchTool(urlFetchService: mockFetchService);

      final emptyUrlResult = await urlFetch.execute({'url': ''});
      expect(emptyUrlResult.success, isFalse);

      final fetchSuccess = await urlFetch.execute({'url': 'https://example.com/article'});
      expect(fetchSuccess.success, isTrue);
      expect(fetchSuccess.metadata?['pageType'], equals('article'));

      // Fetch error result
      mockFetchService.mockResult = const FetchResult(
        url: 'https://example.com/error',
        status: 'error',
        pageType: 'error_page',
        truncated: false,
        originalLength: 0,
        maxLength: 15000,
        contentRatio: 0.0,
        mainContent: '403 Forbidden',
        metadata: FetchMetadata(),
        totalLinks: 0,
        internalLinks: 0,
        externalLinks: 0,
        warnings: ['HTTP 403'],
      );
      final fetchFail = await urlFetch.execute({'url': 'https://example.com/error'});
      expect(fetchFail.success, isFalse);
      expect(fetchFail.errorMessage, equals('403 Forbidden'));
    });
  });

  group('Riverpod Provider Tests', () {
    test('toolRegistryProvider initializes default registry with 22 built-in tools', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final registry = container.read(toolRegistryProvider);
      expect(registry.hasTool('web_search'), isTrue);
      expect(registry.hasTool('google_search'), isTrue);
      expect(registry.hasTool('bing_search'), isTrue);
      expect(registry.hasTool('url_fetch'), isTrue);
      expect(registry.hasTool('math_eval'), isTrue);
      expect(registry.hasTool('time_calculator'), isTrue);
      expect(registry.hasTool('weather_query'), isTrue);
      expect(registry.hasTool('wiki_lookup'), isTrue);
      expect(registry.hasTool('file_read'), isTrue);
      expect(registry.hasTool('file_write'), isTrue);
      expect(registry.hasTool('file_list'), isTrue);
      expect(registry.hasTool('file_delete'), isTrue);
      expect(registry.hasTool('code_eval'), isTrue);
      expect(registry.hasTool('clipboard_read'), isTrue);
      expect(registry.hasTool('clipboard_write'), isTrue);
      expect(registry.hasTool('calendar_query_events'), isTrue);
      expect(registry.hasTool('calendar_create_event'), isTrue);
      expect(registry.hasTool('notification_schedule'), isTrue);
      expect(registry.hasTool('notification_cancel'), isTrue);
      expect(registry.hasTool('contacts_search'), isTrue);
      expect(registry.hasTool('geolocation_get'), isTrue);
      expect(registry.hasTool('reverse_geocode'), isTrue);
      expect(registry.getAllTools().length, equals(22));
    });
  });
}
