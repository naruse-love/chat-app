import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

/// Represents a single search result returned from SearXNG or Bing.
class SearchResult {
  final String title;
  final String url;
  final String content;

  SearchResult({
    required this.title,
    required this.url,
    required this.content,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      content: json['content'] as String? ?? json['snippet'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'content': content,
    };
  }
}

/// Exception thrown when a search operation fails with a detectable error.
class SearchException implements Exception {
  /// User-facing message in Chinese.
  final String message;

  /// Which search source produced the error: 'SearXNG', 'Bing', or 'combined'.
  final String source;

  /// HTTP status code if the error came from an HTTP response.
  final int? statusCode;

  /// Optional detail string (e.g. response body snippet).
  final String? details;

  SearchException({
    required this.message,
    required this.source,
    this.statusCode,
    this.details,
  });

  @override
  String toString() => message;
}

/// Service class for performing web searches.
/// Supports SearXNG (default) and Bing (experimental) backends.
class SearchService {
  final Dio _dio;

  static const Map<String, String> _commonHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
  };

  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-Hans,zh;q=0.9,en;q=0.8',
  };

  SearchService({Dio? dio}) : _dio = dio ?? Dio();

  /// Performs the search, returning a list of parsed [SearchResult]s.
  ///
  /// Throws [SearchException] when the configured search source fails.
  /// Returns an empty list only when the search succeeded but yielded no results.
  ///
  /// [searchBackend] can be `'searxng'` (default) or `'bing'` (experimental).
  Future<List<SearchResult>> search({
    required String query,
    String? searxngUrl,
    String searchBackend = 'searxng',
    String? googleApiKey,
    String? googleBaseUrl,
    String? googleSearchModel,
  }) async {
    switch (searchBackend) {
      case 'bing':
        return _searchBing(query);
      case 'google':
        return _searchGoogle(query, googleApiKey, googleBaseUrl, googleSearchModel);
      case 'searxng':
      default:
        return _searchSearxng(query, searxngUrl);
    }
  }

  /// Searches via SearXNG JSON API using concurrent multi-page requests (pageno 1 & 2).
  Future<List<SearchResult>> _searchSearxng(String query, String? searxngUrl) async {
    if (searxngUrl == null || searxngUrl.trim().isEmpty) {
      throw SearchException(
        source: 'SearXNG',
        message: '未配置 SearXNG 地址。请在设置中填写 SearXNG 基础 URL。',
      );
    }

    // Normalize SearXNG URL: strip trailing slash, ensure ends with /search
    var cleanSearxngUrl = searxngUrl.trim();
    while (cleanSearxngUrl.endsWith('/')) {
      cleanSearxngUrl = cleanSearxngUrl.substring(0, cleanSearxngUrl.length - 1);
    }
    if (!cleanSearxngUrl.endsWith('/search')) {
      cleanSearxngUrl = '$cleanSearxngUrl/search';
    }

    final List<String> errorDetails = [];

    Future<List<SearchResult>> fetchPage(int page) async {
      try {
        final response = await _dio.get(
          cleanSearxngUrl,
          queryParameters: {
            'q': query,
            'format': 'json',
            'pageno': page,
          },
          options: Options(
            headers: {..._commonHeaders},
          ),
        );

        if (response.statusCode == 200) {
          return _parseSearchResults(response.data);
        } else {
          errorDetails.add('SearXNG (page $page) 返回状态码 ${response.statusCode}');
          return [];
        }
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        if (statusCode == 403 || statusCode == 400) {
          final body = _safeResponseBody(e.response?.data);
          throw SearchException(
            source: 'SearXNG',
            statusCode: statusCode,
            message:
                'SearXNG 拒绝了 JSON 接口（HTTP $statusCode）。请在服务器 settings.yml 中启用 formats 的 json，例如 formats: [html, json]。',
            details: body,
          );
        }
        errorDetails.add('SearXNG (page $page): ${_extractErrorMessage(e)}');
        return [];
      } catch (e) {
        errorDetails.add('SearXNG (page $page): ${_extractErrorMessage(e)}');
        return [];
      }
    }

    try {
      final pageResults = await Future.wait([fetchPage(1), fetchPage(2)]);
      final combined = [...pageResults[0], ...pageResults[1]];

      final seenUrls = <String>{};
      final deduplicated = <SearchResult>[];
      for (final result in combined) {
        if (result.url.isNotEmpty) {
          if (seenUrls.add(result.url)) {
            deduplicated.add(result);
          }
        } else {
          deduplicated.add(result);
        }
      }

      if (deduplicated.isEmpty && errorDetails.isNotEmpty) {
        throw SearchException(
          source: 'SearXNG',
          message: 'SearXNG 搜索失败:\n${errorDetails.join('\n')}',
          details: errorDetails.join('; '),
        );
      }

      return deduplicated;
    } on SearchException {
      rethrow;
    } catch (e, stackTrace) {
      developer.log('SearXNG search failed', error: e, stackTrace: stackTrace, name: 'SearchService');
      throw SearchException(
        source: 'SearXNG',
        message: 'SearXNG 搜索失败:\n${_extractErrorMessage(e)}',
        details: e.toString(),
      );
    }
  }

  /// Searches via Bing (experimental) — scrapes the HTML search results page.
  Future<List<SearchResult>> _searchBing(String query) async {
    try {
      final response = await _dio.get(
        'https://www.bing.com/search',
        queryParameters: {
          'q': query,
          'setlang': 'zh-Hans',
        },
        options: Options(
          headers: {..._browserHeaders},
        ),
      );

      if (response.statusCode != 200) {
        throw SearchException(
          source: 'Bing',
          statusCode: response.statusCode,
          message: 'Bing 搜索失败（可能被反爬拦截）。建议改用 SearXNG。',
        );
      }

      final body = response.data is String ? response.data as String : json.encode(response.data);
      final document = html_parser.parse(body);
      final results = _parseBingResults(document);

      if (results.isEmpty) {
        throw SearchException(
          source: 'Bing',
          message: 'Bing 搜索失败（可能被反爬拦截）。建议改用 SearXNG。',
        );
      }

      return results;
    } on DioException catch (e) {
      throw SearchException(
        source: 'Bing',
        statusCode: e.response?.statusCode,
        message: 'Bing 搜索失败（可能被反爬拦截）。建议改用 SearXNG。',
        details: _extractErrorMessage(e),
      );
    } on SearchException {
      rethrow;
    } catch (e, stackTrace) {
      developer.log('Bing search failed', error: e, stackTrace: stackTrace, name: 'SearchService');
      throw SearchException(
        source: 'Bing',
        message: 'Bing 搜索失败（可能被反爬拦截）。建议改用 SearXNG。',
        details: e.toString(),
      );
    }
  }

  /// Parses Bing HTML search results page.
  List<SearchResult> _parseBingResults(html_dom.Document document) {
    final results = <SearchResult>[];

    // Bing common structure: li.b_algo > h2 > a, .b_caption p, .b_algoSlug
    final items = document.querySelectorAll('li.b_algo');
    for (final item in items) {
      try {
        // Title and URL from <h2><a>
        final heading = item.querySelector('h2');
        final link = heading?.querySelector('a');
        final title = link?.text.trim() ?? '';
        final url = link?.attributes['href']?.trim() ?? '';

        if (title.isEmpty || url.isEmpty) continue;

        // Snippet from .b_caption p or .b_algoSlug
        String snippet = '';
        final caption = item.querySelector('.b_caption p');
        if (caption != null) {
          snippet = caption.text.trim();
        }
        if (snippet.isEmpty) {
          final slug = item.querySelector('.b_algoSlug');
          if (slug != null) {
            snippet = slug.text.trim();
          }
        }

        results.add(SearchResult(
          title: title,
          url: url,
          content: snippet,
        ));
      } catch (_) {
        // Skip malformed items
      }
    }

    return results;
  }

  /// Formats a list of [SearchResult]s into a markdown-like text structure
  /// suitable for injecting into the LLM system/user context.
  String formatSearchResultsForContext(List<SearchResult> results) {
    if (results.isEmpty) {
      return '未找到相关网络搜索结果。';
    }

    final buffer = StringBuffer();
    buffer.writeln('以下是网络搜索结果。请仔细阅读后基于这些信息回答用户问题。');
    buffer.writeln('如果需要更详细的信息，请使用 url_fetch 工具读取相关页面全文。');
    buffer.writeln('回答时请引用来源 URL。');
    buffer.writeln();
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. [${r.title}](${r.url})');
      buffer.writeln('   摘要: ${r.content}');
      if (i < results.length - 1) {
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  /// Searches via Google AI Studio's Search Grounding tool.
  Future<List<SearchResult>> _searchGoogle(
    String query,
    String? apiKey,
    String? baseUrl,
    String? googleSearchModel,
  ) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw SearchException(
        source: 'Google Grounding',
        message: '未配置 Google AI Studio API 密钥。请在设置中填写。',
      );
    }

    final cleanBaseUrl = baseUrl == null || baseUrl.trim().isEmpty
        ? 'https://generativelanguage.googleapis.com'
        : baseUrl.trim();

    // Ensure no trailing slash
    var url = cleanBaseUrl;
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    // Default model to gemini-2.5-flash as it is fast and supports search grounding
    final model = googleSearchModel == null || googleSearchModel.trim().isEmpty
        ? 'gemini-2.5-flash'
        : googleSearchModel.trim();
    final requestUrl = '$url/v1beta/models/$model:generateContent';

    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': query}
          ]
        }
      ],
      'tools': [
        {'google_search': {}}
      ]
    };

    try {
      final response = await _dio.post(
        requestUrl,
        queryParameters: {'key': apiKey},
        data: body,
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );

      if (response.statusCode != 200) {
        throw SearchException(
          source: 'Google Grounding',
          statusCode: response.statusCode,
          message: 'Google 搜索接地失败（HTTP ${response.statusCode}）。',
          details: response.data?.toString(),
        );
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw SearchException(
          source: 'Google Grounding',
          message: '返回的数据格式不正确',
        );
      }

      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return [];
      }

      final firstCandidate = candidates[0] as Map<String, dynamic>;
      final results = <SearchResult>[];

      // 1. Extract the grounded AI summary text if available
      final contentObj = firstCandidate['content'] as Map<String, dynamic>?;
      if (contentObj != null) {
        final parts = contentObj['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          final firstPart = parts[0] as Map<String, dynamic>?;
          final text = firstPart?['text'] as String?;
          if (text != null && text.trim().isNotEmpty) {
            results.add(SearchResult(
              title: 'Google 搜索总结 (AI)',
              url: '',
              content: text.trim(),
            ));
          }
        }
      }

      // 2. Extract grounding chunks (the search links)
      final metadata = firstCandidate['groundingMetadata'] as Map<String, dynamic>?;
      if (metadata != null) {
        final chunks = metadata['groundingChunks'] as List<dynamic>?;
        if (chunks != null) {
          for (final chunk in chunks) {
            if (chunk is Map<String, dynamic>) {
              final web = chunk['web'] as Map<String, dynamic>?;
              if (web != null) {
                final title = web['title'] as String? ?? '';
                final uri = web['uri'] as String? ?? web['url'] as String? ?? '';
                if (uri.isNotEmpty) {
                  results.add(SearchResult(
                    title: title.isNotEmpty ? title : uri,
                    url: uri,
                    content: '来自 Google 搜索的网页来源。',
                  ));
                }
              }
            }
          }
        }
      }

      return results;
    } on DioException catch (e) {
      throw SearchException(
        source: 'Google Grounding',
        statusCode: e.response?.statusCode,
        message: 'Google 搜索接地请求失败：${_extractErrorMessage(e)}',
        details: e.response?.data?.toString(),
      );
    } catch (e, stackTrace) {
      developer.log('Google search grounding failed', error: e, stackTrace: stackTrace, name: 'SearchService');
      throw SearchException(
        source: 'Google Grounding',
        message: 'Google 搜索接地解析失败：${_extractErrorMessage(e)}',
        details: e.toString(),
      );
    }
  }

  /// Safely extracts a short human-readable message from an exception.
  String _extractErrorMessage(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return '连接超时';
      }
      if (error.type == DioExceptionType.connectionError) {
        return '连接失败';
      }
      if (error.response != null) {
        return 'HTTP ${error.response!.statusCode}';
      }
      return error.message ?? '未知 Dio 错误';
    }
    return error.toString();
  }

  /// Returns a snippet of the response body safe for display in error messages.
  String? _safeResponseBody(dynamic data) {
    if (data == null) return null;
    try {
      final s = data is String ? data : json.encode(data);
      return s.length > 300 ? '${s.substring(0, 300)}...' : s;
    } catch (_) {
      return null;
    }
  }

  /// Normalizes and parses the raw response data (can be Map, List, or JSON string).
  List<SearchResult> _parseSearchResults(dynamic data) {
    if (data == null) return [];

    List<dynamic> rawResults = [];
    if (data is List) {
      rawResults = data;
    } else if (data is Map) {
      rawResults = data['results'] as List<dynamic>? ??
          data['data'] as List<dynamic>? ??
          data['items'] as List<dynamic>? ??
          [];
    } else if (data is String) {
      try {
        final decoded = json.decode(data);
        return _parseSearchResults(decoded);
      } catch (_) {
        return [];
      }
    }

    return rawResults
        .map((item) {
          if (item is Map<String, dynamic>) {
            return SearchResult.fromJson(item);
          }
          return null;
        })
        .whereType<SearchResult>()
        .toList();
  }
}
