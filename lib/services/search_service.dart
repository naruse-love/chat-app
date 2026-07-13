import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';

/// Represents a single search result returned from 9Router or SearXNG.
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

  /// Which search source produced the error: '9Router', 'SearXNG', or 'combined'.
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
/// Implements a dual-mode fallback search flow:
/// 1. Queries 9Router's search API.
/// 2. Falls back to SearXNG if the 9Router endpoint fails or returns a 404/not supported.
class SearchService {
  final Dio _dio;

  static const Map<String, String> _commonHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
  };

  SearchService({Dio? dio}) : _dio = dio ?? Dio();

  /// Performs the search, returning a list of parsed [SearchResult]s.
  ///
  /// Throws [SearchException] when all search sources fail with a detectable error.
  /// Returns an empty list only when searches succeeded but yielded no results.
  Future<List<SearchResult>> search({
    required String query,
    required String baseUrl,
    required String apiKey,
    String? searxngUrl,
  }) async {
    // Accumulate non-fatal error messages for reporting if all sources fail.
    final List<String> errorDetails = [];

    // 1. Try 9Router search API (try both /search and /v1/search)
    final List<List<String>> searchEndpoints = [
      ['/search'],
      ['/v1/search'],
    ];

    for (final endpoint in searchEndpoints) {
      try {
        final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        final url = '$cleanBaseUrl${endpoint[0]}';

        final response = await _dio.post(
          url,
          queryParameters: {'q': query},
          options: Options(
            headers: {
              ..._commonHeaders,
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          ),
        );

        if (response.statusCode == 200) {
          return _parseSearchResults(response.data);
        } else {
          errorDetails.add('9Router${endpoint[0]} 返回状态码 ${response.statusCode}');
        }
      } catch (e, stackTrace) {
        developer.log('9Router search failed at $endpoint', error: e, stackTrace: stackTrace, name: 'SearchService');
        errorDetails.add('9Router${endpoint[0]}: ${_extractErrorMessage(e)}');
      }
    }

    // 2. Fallback to SearXNG if configured
    if (searxngUrl != null && searxngUrl.isNotEmpty) {
      try {
        // Normalize SearXNG URL: strip trailing slash, ensure ends with /search
        var cleanSearxngUrl = searxngUrl.trim();
        // Remove trailing slash(es)
        while (cleanSearxngUrl.endsWith('/')) {
          cleanSearxngUrl = cleanSearxngUrl.substring(0, cleanSearxngUrl.length - 1);
        }
        // If the resulting URL does not end with /search, append it
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
              headers: {
                ..._commonHeaders,
              },
            ),
          );

          if (response.statusCode == 200) {
            return _parseSearchResults(response.data);
          } else {
            errorDetails.add('SearXNG 返回状态码 ${response.statusCode}');
          }
        } on DioException catch (e) {
          // Dio throws for non-2xx status codes by default.
          final statusCode = e.response?.statusCode;
          if (statusCode == 403 || statusCode == 400) {
            // Typical SearXNG behavior when JSON format is disabled.
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
    }

    // If we recorded any errors, throw a combined SearchException.
    if (errorDetails.isNotEmpty) {
      throw SearchException(
        source: 'combined',
        message: '所有搜索引擎均搜索失败:\n${errorDetails.join('\n')}',
        details: errorDetails.join('; '),
      );
    }

    // No errors, but also no results — return empty list.
    return [];
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
