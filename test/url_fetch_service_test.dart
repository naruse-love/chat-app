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
<html lang="zh-CN">
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

    test('P0-1: Truncates extracted content at maxCharacters and appends explicit warning', () async {
      mockAdapter.handler = (options) {
        final longContent = 'A' * 20000;
        final html = '<html><body><p>$longContent</p></body></html>';
        return ResponseBody.fromString(
          html,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      };

      final result = await fetchService.fetchUrl('https://example.com/long', maxCharacters: 15000);
      expect(result.truncated, isTrue);
      expect(result.maxLength, equals(15000));
      expect(result.originalLength, greaterThan(15000));
      expect(result.mainContent.length, equals(15000));

      final markdown = result.toStructuredMarkdown();
      expect(markdown, contains('⚠️ **内容已截断**'));
      expect(markdown, contains('已截取前 15000 字符'));
    });

    test('P0-1: Does not mark as truncated when content length is below maxCharacters', () async {
      mockAdapter.handler = (options) {
        const html = '<html><body><p>Short content within limits.</p></body></html>';
        return ResponseBody.fromString(
          html,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      };

      final result = await fetchService.fetchUrl('https://example.com/short');
      expect(result.truncated, isFalse);
      final markdown = result.toStructuredMarkdown();
      expect(markdown, isNot(contains('内容已截断')));
    });

    test('P0-2: Detects Captcha / anti-bot challenge pages (e.g. Cloudflare / Juejin)', () async {
      mockAdapter.handler = (options) {
        const html = '''
<html>
  <head><title>Please wait...</title></head>
  <body>
    <div id="challenge">Checking your browser before accessing the website. Please wait...</div>
  </body>
</html>
''';
        return ResponseBody.fromString(
          html,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      };

      final result = await fetchService.fetchUrl('https://juejin.cn/challenge');
      expect(result.pageType, equals('captcha'));
      expect(result.warnings, anyElement(contains('反爬/人机验证')));
      final markdown = result.toStructuredMarkdown();
      expect(markdown, contains('页面类型: captcha'));
      expect(markdown, contains('反爬/人机验证'));
    });

    test('P0-2: Detects Login Wall pages (e.g. Zhihu / restricted forum)', () async {
      mockAdapter.handler = (options) {
        const html = '''
<html>
  <head><title>知乎 - 有问题，就会有答案</title></head>
  <body>
    <div>
      <h2>登录知乎以查看完整内容</h2>
      <form>
        <input type="text" name="username" placeholder="手机号或邮箱" />
        <input type="password" name="password" placeholder="密码" />
        <button type="submit">登录</button>
      </form>
    </div>
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

      final result = await fetchService.fetchUrl('https://zhihu.com/login');
      expect(result.pageType, equals('login_wall'));
      expect(result.warnings, anyElement(contains('登录拦截墙')));
      final markdown = result.toStructuredMarkdown();
      expect(markdown, contains('页面类型: login_wall'));
      expect(markdown, contains('登录拦截墙'));
    });

    test('P0-3 & P2-1: Extracts JSON-LD, OpenGraph, time, and structured metadata', () async {
      mockAdapter.handler = (options) {
        const html = '''
<html lang="zh-CN">
  <head>
    <title>2026编程技术新趋势 - 博客园</title>
    <meta property="og:title" content="2026编程技术新趋势详解" />
    <meta property="og:description" content="年中技术栈盘点与全面分析指南" />
    <meta property="og:site_name" content="博客园" />
    <meta property="og:type" content="article" />
    <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "BlogPosting",
        "headline": "2026编程技术新趋势详解",
        "author": {
          "@type": "Person",
          "name": "凡尘——雨落凡尘"
        },
        "datePublished": "2026-07-22T20:45:00+08:00",
        "description": "年中技术栈盘点与全面分析指南",
        "publisher": {
          "@type": "Organization",
          "name": "博客园"
        }
      }
    </script>
  </head>
  <body>
    <article>
      <h1>2026编程技术新趋势详解</h1>
      <p>每年年中，都是开发者梳理技术栈的关键时刻。本文将深入探讨 AI Agent 与 Dart 生态。</p>
    </article>
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

      final result = await fetchService.fetchUrl('https://cnblogs.com/post/123');
      expect(result.metadata.title, equals('2026编程技术新趋势详解'));
      expect(result.metadata.author, equals('凡尘——雨落凡尘'));
      expect(result.metadata.publishedAt, equals('2026-07-22T20:45:00+08:00'));
      expect(result.metadata.siteName, equals('博客园'));
      expect(result.metadata.language, equals('zh-CN'));
      expect(result.metadata.ogType, equals('article'));

      final markdown = result.toStructuredMarkdown();
      expect(markdown, contains('作者: 凡尘——雨落凡尘'));
      expect(markdown, contains('发布时间: 2026-07-22T20:45:00+08:00'));
      expect(markdown, contains('站点: 博客园'));
      expect(markdown, contains('语言: zh-CN'));
    });

    test('P1-1: Prioritizes <article> / <main> container and strips noise elements (nav, footer, sidebar)', () async {
      mockAdapter.handler = (options) {
        const html = '''
<html>
  <head><title>MDN JavaScript Reference</title></head>
  <body>
    <header class="header">
      <nav class="navbar"><a href="/home">Home</a> | <a href="/docs">Docs</a></nav>
    </header>
    <aside class="sidebar">
      <ul>
        <li><a href="/doc1">Object 1</a></li>
        <li><a href="/doc2">Object 2</a></li>
        <li><a href="/doc3">Object 3</a></li>
      </ul>
    </aside>
    <article class="article-content">
      <h2>JavaScript Standard Built-in Objects</h2>
      <p>This chapter documents all of JavaScript's standard built-in objects, including their methods and properties in detail.</p>
      <table>
        <tr><th>Name</th><th>Type</th></tr>
        <tr><td>Array</td><td>Constructor</td></tr>
      </table>
    </article>
    <footer class="footer">
      <p>© 2026 Mozilla. All rights reserved.</p>
    </footer>
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

      final content = await fetchService.fetchUrlContent('https://developer.mozilla.org/js');
      expect(content, contains('JavaScript Standard Built-in Objects'));
      expect(content, contains('| Name | Type |'));
      expect(content, isNot(contains('Object 1')));
      expect(content, isNot(contains('© 2026 Mozilla')));
    });

    test('P1-2: Analyzes and computes internal and external link statistics', () async {
      mockAdapter.handler = (options) {
        const html = '''
<html>
  <head><title>Link Test</title></head>
  <body>
    <article>
      <h2>Resource Links</h2>
      <p>Check out <a href="/guide">Internal Guide</a> and <a href="https://example.com/about">Internal About</a>.</p>
      <p>External sources: <a href="https://github.com/flutter/flutter">Flutter GitHub</a> and <a href="https://dart.dev">Dart Official</a>.</p>
    </article>
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

      final result = await fetchService.fetchUrl('https://example.com/links');
      expect(result.totalLinks, equals(4));
      expect(result.internalLinks, equals(2));
      expect(result.externalLinks, equals(2));

      final markdown = result.toStructuredMarkdown();
      expect(markdown, contains('页面链接: 共 4 个 (站内 2 / 站外 2)'));
    });

    test('P0-2: Detects nav_hub when page has many links and minimal body content (e.g. Portal homepages)', () async {
      mockAdapter.handler = (options) {
        final links = List.generate(60, (i) => '<a href="/news/$i">News Title $i</a>').join('\n');
        final html = '<html><head><title>Portal News</title></head><body>$links</body></html>';
        return ResponseBody.fromString(
          html,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        );
      };

      final result = await fetchService.fetchUrl('https://163.com');
      expect(result.pageType, equals('nav_hub'));
      expect(result.warnings, anyElement(contains('导航/门户索引页')));
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

    test('Handles 404 Not Found error gracefully', () async {
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
      expect(content, contains('404'));
    });

    test('Handles 403 WAF response with friendly Chinese message and captcha diagnostic', () async {
      mockAdapter.handler = (options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 403,
            statusMessage: 'Forbidden',
          ),
        );
      };

      final content = await fetchService.fetchUrlContent('https://example.com/forbidden');
      expect(content, contains('读取网页被阻断'));
      expect(content, contains('HTTP 403'));
    });
  });
}
