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

/// Service class for performing web searches.
/// Implements a dual-mode fallback search flow:
/// 1. Queries 9Router's search API.
/// 2. Falls back to SearXNG if the 9Router endpoint fails or returns a 404/not supported.
class SearchService {
  final Dio _dio;

  SearchService({Dio? dio}) : _dio = dio ?? Dio();

  /// Performs the search, returning a list of parsed [SearchResult]s.
  /// If [searxngUrl] is provided, it is used as the fallback endpoint.
  Future<List<SearchResult>> search({
    required String query,
    required String baseUrl,
    required String apiKey,
    String? searxngUrl,
  }) async {
    // 1. Try 9Router search API
    try {
      final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final url = '$cleanBaseUrl/search';

      final response = await _dio.post(
        url,
        queryParameters: {'q': query},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        return _parseSearchResults(response.data);
      }
    } catch (e, stackTrace) {
      // Log error and fall through to SearXNG fallback
      developer.log('9Router search failed, falling back to SearXNG', error: e, stackTrace: stackTrace, name: 'SearchService');
    }

    // 2. Fallback to SearXNG if configured
    if (searxngUrl != null && searxngUrl.isNotEmpty) {
      try {
        final response = await _dio.get(
          searxngUrl,
          queryParameters: {
            'q': query,
            'format': 'json',
          },
        );

        if (response.statusCode == 200) {
          return _parseSearchResults(response.data);
        }
      } catch (e, stackTrace) {
        developer.log('SearXNG search failed', error: e, stackTrace: stackTrace, name: 'SearchService');
      }
    }

    return [];
  }

  /// Formats a list of [SearchResult]s into a markdown-like text structure
  /// suitable for injecting into the LLM system/user context.
  String formatSearchResultsForContext(List<SearchResult> results) {
    if (results.isEmpty) {
      return 'No web search results found.';
    }

    final buffer = StringBuffer();
    buffer.writeln('Here are the web search results:');
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('${i + 1}. Title: ${r.title}');
      buffer.writeln('   URL: ${r.url}');
      buffer.writeln('   Snippet: ${r.content}');
      buffer.writeln();
    }
    return buffer.toString().trim();
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
