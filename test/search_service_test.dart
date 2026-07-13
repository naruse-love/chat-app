import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/services/search_service.dart';

class MockAdapter implements HttpClientAdapter {
  ResponseBody Function(RequestOptions options)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (handler != null) {
      return handler!(options);
    }
    throw UnimplementedError('MockAdapter handler is not configured');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('SearchService Tests', () {
    late Dio dio;
    late MockAdapter mockAdapter;
    late SearchService searchService;

    setUp(() {
      dio = Dio();
      mockAdapter = MockAdapter();
      dio.httpClientAdapter = mockAdapter;
      searchService = SearchService(dio: dio);
    });

    test('9Router search succeeds', () async {
      mockAdapter.handler = (options) {
        expect(options.path, endsWith('/search'));
        expect(options.method, 'POST');
        expect(options.queryParameters['q'], 'flutter agent');

        final mockResponse = {
          'results': [
            {
              'title': '9Router Guide',
              'url': 'https://9router.com',
              'content': 'Guide about 9Router',
            }
          ]
        };

        return ResponseBody.fromString(
          json.encode(mockResponse),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final results = await searchService.search(
        query: 'flutter agent',
        baseUrl: 'https://api.9router.com/v1',
        apiKey: 'test-key',
        searxngUrl: 'https://searxng.local',
      );

      expect(results, hasLength(1));
      expect(results[0].title, '9Router Guide');
      expect(results[0].url, 'https://9router.com');
      expect(results[0].content, 'Guide about 9Router');
    });

    test('9Router search fails, falls back to SearXNG', () async {
      int requestCount = 0;
      mockAdapter.handler = (options) {
        requestCount++;
        if (requestCount <= 2) {
          // First two requests should be to 9Router (/search and /v1/search), fail both
          return ResponseBody.fromString(
            'Not Found',
            404,
            headers: {
              Headers.contentTypeHeader: [Headers.textPlainContentType],
            },
          );
        } else {
          // Third request should fall back to SearXNG with /search appended
          expect(options.path, 'https://searxng.local/search');
          expect(options.method, 'GET');
          expect(options.queryParameters['q'], 'flutter agent');
          expect(options.queryParameters['format'], 'json');

          final mockResponse = {
            'results': [
              {
                'title': 'SearXNG Results',
                'url': 'https://searxng.org',
                'content': 'Fallback SearXNG search result',
              }
            ]
          };

          return ResponseBody.fromString(
            json.encode(mockResponse),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
      };

      final results = await searchService.search(
        query: 'flutter agent',
        baseUrl: 'https://api.9router.com/v1',
        apiKey: 'test-key',
        searxngUrl: 'https://searxng.local',
      );

      expect(requestCount, 3);
      expect(results, hasLength(1));
      expect(results[0].title, 'SearXNG Results');
      expect(results[0].url, 'https://searxng.org');
      expect(results[0].content, 'Fallback SearXNG search result');
    });

    test('Formatting context string works correctly (Chinese)', () {
      final results = [
        SearchResult(title: 'A', url: 'https://a.com', content: 'Info A'),
        SearchResult(title: 'B', url: 'https://b.com', content: 'Info B'),
      ];

      final context = searchService.formatSearchResultsForContext(results);

      expect(context, contains('1. 标题: A'));
      expect(context, contains('网址: https://a.com'));
      expect(context, contains('摘要: Info A'));
      expect(context, contains('2. 标题: B'));
    });

    test('Empty results formatting returns Chinese message', () {
      final context = searchService.formatSearchResultsForContext([]);
      expect(context, '未找到相关网络搜索结果。');
    });

    test('SearXNG 403 throws SearchException with JSON format hint', () async {
      mockAdapter.handler = (options) {
        // Fail 9Router endpoints first
        if (options.method == 'POST') {
          return ResponseBody.fromString(
            'Not Found',
            404,
            headers: {
              Headers.contentTypeHeader: [Headers.textPlainContentType],
            },
          );
        }
        // SearXNG returns 403 Forbidden (JSON format disabled)
        expect(options.queryParameters['format'], 'json');
        return ResponseBody.fromString(
          '403 Forbidden - Invalid search format',
          403,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      };

      try {
        await searchService.search(
          query: 'test',
          baseUrl: 'https://api.9router.com/v1',
          apiKey: 'test-key',
          searxngUrl: 'https://searxng.local',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'SearXNG');
        expect(e.statusCode, 403);
        expect(e.message, contains('SearXNG 拒绝了 JSON 接口'));
        expect(e.message, contains('formats: [html, json]'));
      }
    });

    test('All sources fail throws combined SearchException', () async {
      mockAdapter.handler = (options) {
        return ResponseBody.fromString(
          'Service Unavailable',
          503,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      };

      try {
        await searchService.search(
          query: 'test',
          baseUrl: 'https://api.9router.com/v1',
          apiKey: 'test-key',
          searxngUrl: 'https://searxng.local',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'combined');
        expect(e.message, contains('所有搜索引擎均搜索失败'));
      }
    });

    test('No searxngUrl, all 9Router endpoints fail throws SearchException', () async {
      mockAdapter.handler = (options) {
        return ResponseBody.fromString(
          'Not Found',
          404,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      };

      try {
        await searchService.search(
          query: 'test',
          baseUrl: 'https://api.9router.com/v1',
          apiKey: 'test-key',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'combined');
        expect(e.message, contains('所有搜索引擎均搜索失败'));
      }
    });

    test('9Router returns empty results', () async {
      mockAdapter.handler = (options) {
        expect(options.method, 'POST');
        expect(options.queryParameters['q'], 'flutter agent');

        return ResponseBody.fromString(
          json.encode({'results': []}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final results = await searchService.search(
        query: 'flutter agent',
        baseUrl: 'https://api.9router.com/v1',
        apiKey: 'test-key',
      );

      expect(results, isEmpty);
    });
  });
}
