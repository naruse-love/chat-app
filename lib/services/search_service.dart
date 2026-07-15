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
  }) async {
    switch (searchBackend) {
      case 'bing':
        return _searchBing(query);
      case 'searxng':
      default:
        return _searchSearxng(query, searxngUrl);
    }
  }

  /// Searches via SearXNG JSON API.
  Future<List<SearchResult>> _searchSearxng(String query, String? searxngUrl) async {
    if (searxngUrl == null || searxngUrl.trim().isEmpty) {
      throw SearchException(
        source: 'SearXNG',
        message: '未配置 SearXNG 地址。请在设置中填写 SearXNG 基础 URL。',
      );
    }

    final List<String> errorDetails = [];

    try {
      // Normalize SearXNG URL: strip trailing slash, ensure ends with /search
      var cleanSearxngUrl = searxngUrl.trim();
      while (cleanSearxngUrl.endsWith('/')) {
        cleanSearxngUrl = cleanSearxngUrl.substring(0, cleanSearxngUrl.length - 1);
      }
      if (!cleanSearxngUrl.endsWith('/search')) {
        cleanSearxngUrl = '$cleanSearxngUrl/search';
      }

      try {
        final response = await _dio.get(
          cleanSearxngUrl,
          queryParameters: {
            'q': query,
            'format': 'json',
          },
          options: Options(
            headers: {..._commonHeaders},
          ),
        );

        if (response.statusCode == 200) {
          final results = _parseSearchResults(response.data);
          return results;
        } else {
          errorDetails.add('SearXNG 返回状态码 ${response.statusCode}');
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
        errorDetails.add('SearXNG: ${_extractErrorMessage(e)}');
      }
    } on SearchException {
      rethrow;
    } catch (e, stackTrace) {
      developer.log('SearXNG search failed', error: e, stackTrace: stackTrace, name: 'SearchService');
      errorDetails.add('SearXNG: ${_extractErrorMessage(e)}');
    }

    if (errorDetails.isNotEmpty) {
      throw SearchException(
        source: 'SearXNG',
        message: 'SearXNG 搜索失败:\n${errorDetails.join('\n')}',
        details: errorDetails.join('; '),
      );
    }

    return [];
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
    buffer.writeln('以下是网络搜索结果:');
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. 标题: ${r.title}');
      buffer.writeln('   网址: ${r.url}');
      buffer.writeln('   摘要: ${r.content}');
      buffer.writeln();
    }
    return buffer.toString().trim();
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
