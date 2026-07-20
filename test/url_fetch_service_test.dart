import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:chat/services/url_fetch_service.dart';

class MockFetchAdapter implements HttpClientAdapter {
  ResponseBody Function(RequestOptions options)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (handler != null) {
      return handler!(options);
    }
    throw UnimplementedError('MockFetchAdapter handler is not configured');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('UrlFetchService Tests', () {
    late Dio dio;
    late MockFetchAdapter mockAdapter;
    late UrlFetchService fetchService;

    setUp(() {
      dio = Dio();
      mockAdapter = MockFetchAdapter();
      dio.httpClientAdapter = mockAdapter;
      fetchService = UrlFetchService(dio: dio);
    });

    test('Strips script, style, and noscript tags and returns clean body text', () async {
      mockAdapter.handler = (options) {
        expect(options.headers['User-Agent'], contains('Mozilla/5.0'));
        const html = '''
<html>
  <head>
    <style>body { color: red; }</style>
    <script>console.log('secret');</script>
  </head>
  <body>
    <noscript>Please enable JS</noscript>
    <h1>Title Header</h1>
    <p>This is the main body text of the article.</p>
  </body>
</html>
''';
        return ResponseBody.fromString(
          html,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html; charset=utf-8'],
          },
        );
      };

      final content = await fetchService.fetchUrlContent('https://example.com/page');
      expect(content, contains('Title Header'));
      expect(content, contains('This is the main body text of the article.'));
      expect(content, isNot(contains('secret')));
      expect(content, isNot(contains('color: red')));
      expect(content, isNot(contains('Please enable JS')));
    });

    test('Truncates extracted content to max 8000 characters', () async {
      mockAdapter.handler = (options) {
        final longContent = 'A' * 10000;
        final html = '<html><body><p>$longContent</p></body></html>';
        return ResponseBody.fromString(
          html,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      };

      final content = await fetchService.fetchUrlContent('https://example.com/long');
      expect(content.length, equals(8000));
    });

    test('Handles Dio timeout exceptions gracefully with clear error text', () async {
      mockAdapter.handler = (options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          error: 'Connection timeout',
        );
      };

      final content = await fetchService.fetchUrlContent('https://example.com/timeout');
      expect(content, contains('读取网页超时'));
    });

    test('Handles general Dio network errors gracefully', () async {
      mockAdapter.handler = (options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 404,
            statusMessage: 'Not Found',
          ),
        );
      };

      final content = await fetchService.fetchUrlContent('https://example.com/404');
      expect(content, contains('读取网页失败'));
    });
  });
}
