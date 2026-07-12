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
        if (requestCount == 1) {
          // First request should be to 9Router, we fail it with 404
          expect(options.path, endsWith('/search'));
          return ResponseBody.fromString(
            'Not Found',
            404,
            headers: {
              Headers.contentTypeHeader: [Headers.textPlainContentType],
            },
          );
        } else {
          // Second request should fall back to SearXNG
          expect(options.path, 'https://searxng.local');
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

      expect(requestCount, 2);
      expect(results, hasLength(1));
      expect(results[0].title, 'SearXNG Results');
      expect(results[0].url, 'https://searxng.org');
      expect(results[0].content, 'Fallback SearXNG search result');
    });

    test('Formatting context string works correctly', () {
      final results = [
        SearchResult(title: 'A', url: 'https://a.com', content: 'Info A'),
        SearchResult(title: 'B', url: 'https://b.com', content: 'Info B'),
      ];

      final context = searchService.formatSearchResultsForContext(results);

      expect(context, contains('1. Title: A'));
      expect(context, contains('URL: https://a.com'));
      expect(context, contains('Snippet: Info A'));
      expect(context, contains('2. Title: B'));
    });
  });
}
