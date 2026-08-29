import 'package:dio/dio.dart';
import '../../models/tool/tool.dart';
import '../search_service.dart';
import '../url_fetch_service.dart';

/// Legacy adapter for standard SearXNG web search (`web_search`).
class WebSearchTool extends Tool {
  final SearchService searchService;
  final String? searxngUrl;

  WebSearchTool({
    SearchService? searchService,
    this.searxngUrl,
  }) : searchService = searchService ?? SearchService();

  @override
  String get name => 'web_search';

  @override
  String get displayName => '网络搜索';

  @override
  String get description => 'Search the web for up-to-date information on a given topic.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'query',
      type: 'string',
      description: 'The query to search for on the web.',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final query = (arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '搜索关键词不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final effectiveSearxngUrl = arguments['searxngUrl'] as String? ??
          arguments['__searxngUrl'] as String? ??
          searxngUrl;

      final results = await searchService.search(
        query: query,
        searxngUrl: effectiveSearxngUrl,
        searchBackend: 'searxng',
      );
      stopwatch.stop();

      final formatted = searchService.formatSearchResultsForContext(results);
      return ToolExecutionResult.success(
        toolName: name,
        content: formatted,
        rawData: results,
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'resultCount': results.length,
          'backend': 'searxng',
        },
      );
    } on SearchException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '搜索失败：${e.message}',
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'source': e.source,
          'statusCode': e.statusCode,
          'details': e.details,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '搜索出现未知异常: $e',
        content: '搜索失败：$e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}

/// Legacy adapter for Google Grounding search (`google_search`).
class GoogleSearchTool extends Tool {
  final SearchService searchService;
  final String? googleApiKey;
  final String? googleBaseUrl;
  final String? googleSearchModel;

  GoogleSearchTool({
    SearchService? searchService,
    this.googleApiKey,
    this.googleBaseUrl,
    this.googleSearchModel,
  }) : searchService = searchService ?? SearchService();

  @override
  String get name => 'google_search';

  @override
  String get displayName => 'Google 搜索';

  @override
  String get description => 'Search Google for up-to-date information on a given topic.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'query',
      type: 'string',
      description: 'The search query for Google.',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final query = (arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '搜索关键词不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final apiKey = arguments['googleApiKey'] as String? ??
          arguments['__googleApiKey'] as String? ??
          googleApiKey;
      final baseUrl = arguments['googleBaseUrl'] as String? ??
          arguments['__googleBaseUrl'] as String? ??
          googleBaseUrl;
      final model = arguments['googleSearchModel'] as String? ??
          arguments['__googleSearchModel'] as String? ??
          googleSearchModel;

      final results = await searchService.search(
        query: query,
        searchBackend: 'google',
        googleApiKey: apiKey,
        googleBaseUrl: baseUrl,
        googleSearchModel: model,
      );
      stopwatch.stop();

      final formatted = searchService.formatSearchResultsForContext(results);
      return ToolExecutionResult.success(
        toolName: name,
        content: formatted,
        rawData: results,
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'resultCount': results.length,
          'backend': 'google',
        },
      );
    } on SearchException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '搜索失败：${e.message}',
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'source': e.source,
          'statusCode': e.statusCode,
          'details': e.details,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: 'Google 搜索出现异常: $e',
        content: '搜索失败：$e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}

/// Legacy adapter for Bing search (`bing_search`).
class BingSearchTool extends Tool {
  final SearchService searchService;
  final String? bingCookie;

  BingSearchTool({
    SearchService? searchService,
    this.bingCookie,
  }) : searchService = searchService ?? SearchService();

  @override
  String get name => 'bing_search';

  @override
  String get displayName => 'Bing 搜索';

  @override
  String get description => 'Search Bing for up-to-date information on a given topic.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'query',
      type: 'string',
      description: 'The search query for Bing.',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final query = (arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '搜索关键词不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final cookie = arguments['bingCookie'] as String? ??
          arguments['__bingCookie'] as String? ??
          bingCookie;

      final results = await searchService.search(
        query: query,
        searchBackend: 'bing',
        bingCookie: cookie,
      );
      stopwatch.stop();

      final formatted = searchService.formatSearchResultsForContext(results);
      return ToolExecutionResult.success(
        toolName: name,
        content: formatted,
        rawData: results,
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'resultCount': results.length,
          'backend': 'bing',
        },
      );
    } on SearchException catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: e.message,
        content: '搜索失败：${e.message}',
        executionDuration: stopwatch.elapsed,
        metadata: {
          'query': query,
          'source': e.source,
          'statusCode': e.statusCode,
          'details': e.details,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: 'Bing 搜索出现异常: $e',
        content: '搜索失败：$e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}

/// Legacy adapter for webpage content extraction (`url_fetch`).
class UrlFetchTool extends Tool {
  final UrlFetchService urlFetchService;

  UrlFetchTool({UrlFetchService? urlFetchService})
      : urlFetchService = urlFetchService ?? UrlFetchService();

  @override
  String get name => 'url_fetch';

  @override
  String get displayName => '网页抓取';

  @override
  String get description =>
      'Fetch and extract structured content from a webpage URL. Returns metadata (title, author, published date, site name, language), page type diagnosis (article/doc/captcha/login_wall/nav_hub), truncation status & limits, link statistics, and cleaned main content in Markdown.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'url',
      type: 'string',
      description: 'The absolute HTTP or HTTPS URL of the webpage to fetch.',
      required: true,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final rawUrl = arguments['url'];
    final url = (rawUrl is String ? rawUrl : rawUrl?.toString() ?? '').trim();
    if (url.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: 'URL 不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    try {
      final cancelToken = arguments['__cancelToken'] as CancelToken? ??
          arguments['cancelToken'] as CancelToken?;
      final maxCharacters = arguments['__maxCharacters'] as int? ??
          arguments['maxCharacters'] as int? ??
          UrlFetchService.defaultMaxCharacters;

      FetchResult? fetchResult;
      String? markdownContent;

      try {
        fetchResult = await urlFetchService.fetchUrl(
          url,
          cancelToken: cancelToken,
          maxCharacters: maxCharacters,
        );
        if (fetchResult.status != 'error') {
          markdownContent = fetchResult.toStructuredMarkdown();
        }
      } catch (_) {}

      if (markdownContent == null || markdownContent.isEmpty) {
        markdownContent = await urlFetchService.fetchUrlContent(
          url,
          cancelToken: cancelToken,
        );
      }
      stopwatch.stop();

      final isSuccess = fetchResult != null
          ? fetchResult.status != 'error'
          : (!markdownContent.startsWith('抓取网页失败') && !markdownContent.startsWith('连接超时'));

      if (!isSuccess) {
        return ToolExecutionResult.failure(
          toolName: name,
          errorMessage: fetchResult?.mainContent ?? markdownContent,
          content: markdownContent,
          rawData: fetchResult,
          executionDuration: stopwatch.elapsed,
          metadata: {
            'url': url,
            if (fetchResult != null) 'pageType': fetchResult.pageType,
            if (fetchResult != null) 'status': fetchResult.status,
            if (fetchResult != null) 'warnings': fetchResult.warnings,
          },
        );
      }

      return ToolExecutionResult.success(
        toolName: name,
        content: markdownContent,
        rawData: fetchResult,
        executionDuration: stopwatch.elapsed,
        metadata: {
          'url': url,
          'title': fetchResult?.metadata.title,
          'pageType': fetchResult?.pageType,
          'truncated': fetchResult?.truncated,
          'originalLength': fetchResult?.originalLength,
          'status': fetchResult?.status,
          'warnings': fetchResult?.warnings,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '抓取网页异常: $e',
        content: '抓取网页失败: $e',
        executionDuration: stopwatch.elapsed,
      );
    }
  }
}
