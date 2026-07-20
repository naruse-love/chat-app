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

    // ===================== SearXNG Tests =====================

    test('SearXNG search succeeds', () async {
      mockAdapter.handler = (options) {
        expect(options.path, 'https://searxng.local/search');
        expect(options.method, 'GET');
        expect(options.queryParameters['q'], 'flutter agent');
        expect(options.queryParameters['format'], 'json');

        final mockResponse = {
          'results': [
            {
              'title': 'SearXNG Result',
              'url': 'https://example.com',
              'content': 'SearXNG search result content',
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
        searxngUrl: 'https://searxng.local',
        searchBackend: 'searxng',
      );

      expect(results, hasLength(1));
      expect(results[0].title, 'SearXNG Result');
      expect(results[0].url, 'https://example.com');
      expect(results[0].content, 'SearXNG search result content');
    });

    test('SearXNG empty URL throws SearchException', () async {
      try {
        await searchService.search(
          query: 'test',
          searxngUrl: '',
          searchBackend: 'searxng',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'SearXNG');
        expect(e.message, contains('未配置 SearXNG 地址'));
      }
    });

    test('SearXNG null URL throws SearchException', () async {
      try {
        await searchService.search(
          query: 'test',
          searxngUrl: null,
          searchBackend: 'searxng',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'SearXNG');
        expect(e.message, contains('未配置 SearXNG 地址'));
      }
    });

    test('SearXNG 403 throws SearchException with JSON format hint', () async {
      mockAdapter.handler = (options) {
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
          searxngUrl: 'https://searxng.local',
          searchBackend: 'searxng',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'SearXNG');
        expect(e.statusCode, 403);
        expect(e.message, contains('SearXNG 拒绝了 JSON 接口'));
        expect(e.message, contains('formats: [html, json]'));
      }
    });

    test('SearXNG returns empty results', () async {
      mockAdapter.handler = (options) {
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
        searxngUrl: 'https://searxng.local',
        searchBackend: 'searxng',
      );

      expect(results, isEmpty);
    });

    test('SearXNG URL normalization works', () async {
      mockAdapter.handler = (options) {
        // Expect normalized URL with trailing slash removed and /search appended
        expect(options.path, 'https://searxng.local/search');
        return ResponseBody.fromString(
          json.encode({'results': []}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      };

      final results = await searchService.search(
        query: 'test',
        searxngUrl: 'https://searxng.local/',
        searchBackend: 'searxng',
      );

      expect(results, isEmpty);
    });

    // ===================== Bing Tests =====================

    test('Bing search succeeds with valid HTML', () async {
      mockAdapter.handler = (options) {
        expect(options.uri.toString(), startsWith('https://www.bing.com/search'));
        expect(options.uri.queryParameters['q'], 'flutter');

        const mockHtml = '''
<html>
<body>
<ol id="b_results">
  <li class="b_algo">
    <h2><a href="https://flutter.dev">Flutter Official</a></h2>
    <div class="b_caption"><p>Build apps for any screen with Flutter.</p></div>
  </li>
  <li class="b_algo">
    <h2><a href="https://dart.dev">Dart Programming</a></h2>
    <div class="b_caption"><p>A client-optimized language for fast apps.</p></div>
  </li>
</ol>
</body>
</html>
''';
        return ResponseBody.fromString(
          mockHtml,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      };

      final results = await searchService.search(
        query: 'flutter',
        searchBackend: 'bing',
      );

      expect(results, hasLength(2));
      expect(results[0].title, 'Flutter Official');
      expect(results[0].url, 'https://flutter.dev');
      expect(results[0].content, 'Build apps for any screen with Flutter.');
      expect(results[1].title, 'Dart Programming');
      expect(results[1].url, 'https://dart.dev');
    });

    test('Bing search returns empty results for no-match HTML', () async {
      mockAdapter.handler = (options) {
        const mockHtml = '<html><body><ol id="b_results"></ol></body></html>';
        return ResponseBody.fromString(
          mockHtml,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      };

      try {
        await searchService.search(
          query: 'asdfghjklzxcvbnm',
          searchBackend: 'bing',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'Bing');
        expect(e.message, contains('Bing 搜索失败'));
      }
    });

    test('Bing search passes bingCookie in headers and decodes redirect URLs', () async {
      String? sentCookie;
      mockAdapter.handler = (options) {
        sentCookie = options.headers['Cookie'];
        const mockHtml = '''
<html>
  <body>
    <ol id="b_results">
      <li class="b_algo">
        <h2><a href="/ck/a?!&u=a1aHR0cHM6Ly9leGFtcGxlLmNvbS9hcnRpY2xl">Redirect Link</a></h2>
        <div class="b_caption"><p>Snippet content</p></div>
      </li>
    </ol>
  </body>
</html>
''';
        return ResponseBody.fromString(mockHtml, 200);
      };

      final results = await searchService.search(
        query: 'test',
        searchBackend: 'bing',
        bingCookie: 'MUID=123456; SRCHD=AF=NOFORM;',
      );

      expect(sentCookie, equals('MUID=123456; SRCHD=AF=NOFORM;'));
      expect(results, hasLength(1));
      expect(results[0].title, equals('Redirect Link'));
      expect(results[0].url, equals('https://example.com/article'));
    });

    test('Bing search HTTP error throws SearchException', () async {
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
          searchBackend: 'bing',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'Bing');
        expect(e.message, contains('Bing 搜索失败'));
      }
    });

    test('SearXNG dual-page fetching and URL deduplication', () async {
      mockAdapter.handler = (options) {
        final pageno = options.queryParameters['pageno'];
        if (pageno == 1) {
          return ResponseBody.fromString(
            json.encode({
              'results': [
                {'title': 'Doc 1', 'url': 'https://a.com', 'content': 'Content A'},
                {'title': 'Doc 2', 'url': 'https://b.com', 'content': 'Content B'},
              ]
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        } else {
          return ResponseBody.fromString(
            json.encode({
              'results': [
                {'title': 'Doc 2 Duplicate', 'url': 'https://b.com', 'content': 'Content B Duplicate'},
                {'title': 'Doc 3', 'url': 'https://c.com', 'content': 'Content C'},
              ]
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        }
      };

      final results = await searchService.search(
        query: 'test',
        searxngUrl: 'https://searxng.local',
        searchBackend: 'searxng',
      );

      expect(results, hasLength(3));
      expect(results[0].url, 'https://a.com');
      expect(results[1].url, 'https://b.com');
      expect(results[2].url, 'https://c.com');
    });

    test('SearXNG partial page timeout resilience', () async {
      mockAdapter.handler = (options) {
        final pageno = options.queryParameters['pageno'];
        if (pageno == 1) {
          return ResponseBody.fromString(
            json.encode({
              'results': [
                {'title': 'Doc 1', 'url': 'https://a.com', 'content': 'Content A'},
              ]
            }),
            200,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
          );
        } else {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        }
      };

      final results = await searchService.search(
        query: 'test',
        searxngUrl: 'https://searxng.local',
        searchBackend: 'searxng',
      );

      expect(results, hasLength(1));
      expect(results[0].title, 'Doc 1');
    });

    // ===================== Google Grounding Tests =====================

    test('Google Grounding search succeeds', () async {
      mockAdapter.handler = (options) {
        expect(options.path, contains('/v1beta/models/gemini-2.5-flash:generateContent'));
        expect(options.method, 'POST');
        expect(options.queryParameters['key'], 'google_key');

        final mockResponse = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Grounded AI summary text'}
                ]
              },
              'groundingMetadata': {
                'webSearchQueries': ['flutter agent'],
                'groundingChunks': [
                  {
                    'web': {
                      'uri': 'https://google.com/search-result',
                      'title': 'Google Grounded Page'
                    }
                  }
                ]
              }
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
        searchBackend: 'google',
        googleApiKey: 'google_key',
        googleBaseUrl: 'https://generativelanguage.googleapis.com',
      );

      expect(results, hasLength(2));
      expect(results[0].title, 'Google 搜索总结 (AI)');
      expect(results[0].url, '');
      expect(results[0].content, 'Grounded AI summary text');

      expect(results[1].title, 'Google Grounded Page');
      expect(results[1].url, 'https://google.com/search-result');
      expect(results[1].content, '来自 Google 搜索的网页来源。');
    });

    test('Google Grounding search succeeds with custom model', () async {
      mockAdapter.handler = (options) {
        expect(options.path, contains('/v1beta/models/custom-model-name:generateContent'));
        expect(options.method, 'POST');
        expect(options.queryParameters['key'], 'google_key');

        final mockResponse = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Custom model response'}
                ]
              }
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
        query: 'test query',
        searchBackend: 'google',
        googleApiKey: 'google_key',
        googleSearchModel: 'custom-model-name',
      );

      expect(results, hasLength(1));
      expect(results[0].content, 'Custom model response');
    });

    test('Google Grounding search throws exception on missing API Key', () async {
      try {
        await searchService.search(
          query: 'test',
          searchBackend: 'google',
          googleApiKey: '',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'Google Grounding');
        expect(e.message, contains('未配置 Google AI Studio API 密钥'));
      }
    });

    test('Google Grounding HTTP error throws SearchException', () async {
      mockAdapter.handler = (options) {
        return ResponseBody.fromString('Error body', 400);
      };

      try {
        await searchService.search(
          query: 'test',
          searchBackend: 'google',
          googleApiKey: 'key',
        );
        fail('Expected SearchException was not thrown');
      } on SearchException catch (e) {
        expect(e.source, 'Google Grounding');
        expect(e.statusCode, 400);
        expect(e.message, contains('Google 搜索接地'));
        expect(e.message, contains('失败'));
      }
    });

    // ===================== Common Tests =====================

    test('Formatting context string works correctly (Chinese)', () {
      final results = [
        SearchResult(title: 'A', url: 'https://a.com', content: 'Info A'),
        SearchResult(title: 'B', url: 'https://b.com', content: 'Info B'),
      ];

      final context = searchService.formatSearchResultsForContext(results);

      expect(context, contains('1. [A](https://a.com)'));
      expect(context, contains('摘要: Info A'));
      expect(context, contains('2. [B](https://b.com)'));
      expect(context, isNot(contains('以下是网络搜索结果。')));
    });

    test('google_bing search combines Google and Bing results in parallel', () async {
      int apiRequestsCount = 0;
      mockAdapter.handler = (options) {
        apiRequestsCount++;
        if (options.path.contains('/v1beta/models/')) {
          // Google response
          return ResponseBody.fromString(
            json.encode({
              'candidates': [
                {
                  'content': {
                    'parts': [{'text': 'Google Summary'}]
                  }
                }
              ]
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        } else {
          // Bing response
          return ResponseBody.fromString(
            '<html><body><ol id="b_results"><li class="b_algo"><h2><a href="https://bing.com/res">Bing Title</a></h2><p>Bing Snippet</p></li></ol></body></html>',
            200,
          );
        }
      };

      final results = await searchService.search(
        query: 'dual search test',
        searchBackend: 'google_bing',
        googleApiKey: 'google_key',
      );

      expect(apiRequestsCount, 2);
      expect(results, hasLength(2));
      expect(results[0].content, 'Google Summary');
      expect(results[1].title, 'Bing Title');
    });

    test('Empty results formatting returns Chinese message', () {
      final context = searchService.formatSearchResultsForContext([]);
      expect(context, '未找到相关网络搜索结果。');
    });
  });
}
