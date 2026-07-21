import 'dart:convert';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:uuid/uuid.dart';

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
    String? bingCookie,
  }) async {
    switch (searchBackend) {
      case 'bing':
        return _searchBing(query, bingCookie);
      case 'google':
        return _searchGoogle(query, googleApiKey, googleBaseUrl, googleSearchModel);
      case 'google_bing':
        final googleFuture = _searchGoogle(query, googleApiKey, googleBaseUrl, googleSearchModel)
            .catchError((e) {
              developer.log('Dual search (Google part) failed: $e', name: 'SearchService');
              return <SearchResult>[];
            });
        final bingFuture = _searchBing(query, bingCookie)
            .catchError((e) {
              developer.log('Dual search (Bing part) failed: $e', name: 'SearchService');
              return <SearchResult>[];
            });
        final List<List<SearchResult>> results = await Future.wait([googleFuture, bingFuture]);
        return [...results[0], ...results[1]];
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

  /// Clean and format raw Cookie strings (remove "Cookie:" prefix, line breaks).
  static String cleanCookieString(String? rawCookie) {
    if (rawCookie == null) return '';
    var cleaned = rawCookie.trim();
    if (cleaned.toLowerCase().startsWith('cookie:')) {
      cleaned = cleaned.substring(7).trim();
    }
    cleaned = cleaned.replaceAll('\r', '').replaceAll('\n', ' ');
    return cleaned.trim();
  }

  /// Merges Set-Cookie response headers into existing Cookie header.
  static String _mergeCookies(String? existingCookieHeader, List<String> setCookieHeaders) {
    final cookieMap = <String, String>{};
    if (existingCookieHeader != null && existingCookieHeader.isNotEmpty) {
      for (final pair in existingCookieHeader.split(';')) {
        final kv = pair.split('=');
        if (kv.length >= 2) {
          cookieMap[kv[0].trim()] = kv.sublist(1).join('=').trim();
        }
      }
    }
    for (final header in setCookieHeaders) {
      final firstPart = header.split(';').first;
      final kv = firstPart.split('=');
      if (kv.length >= 2) {
        cookieMap[kv[0].trim()] = kv.sublist(1).join('=').trim();
      }
    }
    return cookieMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Searches via Bing — scrapes the HTML search results page with Cookie support,
  /// desktop browser headers, and Bing cvid tracking parameters for account search history.
  Future<List<SearchResult>> _searchBing(String query, String? bingCookie) async {
    try {
      final cleanQuery = query.trim();
      final encodedQuery = Uri.encodeComponent(cleanQuery).replaceAll('%20', '+');
      final cvid = const Uuid().v4().replaceAll('-', '');

      // Append cc=us and setlang=zh-hans to bypass domestic strict keyword filtering on cn.bing.com
      final url = 'https://www.bing.com/search?q=$encodedQuery&form=QBLH&pq=$encodedQuery&sc=10-0&qs=n&sk=&cvid=$cvid&sp=-1&cc=us&setlang=zh-hans';

      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
        'Sec-Ch-Ua': '"Not/A)Brand";v="8", "Chromium";v="126", "Google Chrome";v="126"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Sec-Ch-Ua-Platform': '"Windows"',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Upgrade-Insecure-Requests': '1',
      };

      final sanitizedCookie = cleanCookieString(bingCookie);
      if (sanitizedCookie.isNotEmpty) {
        headers['Cookie'] = sanitizedCookie;
      }

      // Intercept redirects up to 5 hops to forward Cookie headers, as Dio drops Cookie cross-domain/subdomain
      String currentUrl = url;
      Response response;
      int redirectCount = 0;
      while (true) {
        response = await _dio.get(
          currentUrl,
          options: Options(
            headers: headers,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        final statusCode = response.statusCode ?? 200;
        if ((statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308) &&
            redirectCount < 5) {
          final location = response.headers.value('location');
          if (location != null && location.isNotEmpty) {
            final nextUri = Uri.parse(currentUrl).resolve(location);
            currentUrl = nextUri.toString();
            redirectCount++;

            final setCookieHeaders = response.headers['set-cookie'];
            if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
              headers['Cookie'] = _mergeCookies(headers['Cookie'], setCookieHeaders);
            }
            continue;
          }
        }
        break;
      }

      if (response.statusCode != 200) {
        throw SearchException(
          source: 'Bing',
          statusCode: response.statusCode,
          message: 'Bing 搜索失败（HTTP ${response.statusCode}）。可尝试设置 Bing Cookie。',
        );
      }

      final body = response.data is String ? response.data as String : json.encode(response.data);
      final document = html_parser.parse(body);

      // Detect WAF block (Azure FrontDoor)
      final isWafBlocked = body.contains('request is blocked') || body.contains('Ref A:');
      if (isWafBlocked) {
        throw SearchException(
          source: 'Bing',
          message: 'Bing 搜索请求被防火墙拦截 (The request is blocked)。建议检查 Cookie 或稍后重试。',
        );
      }

      // Detect anti-bot / CAPTCHA challenge pages
      final isCaptcha = body.contains('g-recaptcha') ||
          body.contains('client_captcha') ||
          body.contains('验证码') ||
          document.querySelector('#challenge') != null ||
          document.querySelector('.b_captcha') != null;

      if (isCaptcha) {
        throw SearchException(
          source: 'Bing',
          message: 'Bing 触发了反爬验证码拦截。建议在设置中刷新并填入最新的 Bing 登录 Cookie 或改用 SearXNG。',
        );
      }

      final results = _parseBingResults(document);
      final hasCookie = sanitizedCookie.isNotEmpty;

      if (results.isEmpty) {
        throw SearchException(
          source: 'Bing',
          message: hasCookie
              ? 'Bing 搜索未提取到有效结果。可能是 Cookie 已失效过期或 Bing 变更了页面结构，建议重新获取 Cookie 或切换搜索后端。'
              : 'Bing 搜索失败（未提取到结果）。可在设置中配置 Bing 登录 Cookie。',
        );
      }

      return results;
    } on DioException catch (e) {
      throw SearchException(
        source: 'Bing',
        statusCode: e.response?.statusCode,
        message: 'Bing 搜索失败（网络或反爬拦截）。建议在设置中填入 Bing 登录 Cookie 或改用 SearXNG。',
        details: _extractErrorMessage(e),
      );
    } on SearchException {
      rethrow;
    } catch (e, stackTrace) {
      developer.log('Bing search failed', error: e, stackTrace: stackTrace, name: 'SearchService');
      throw SearchException(
        source: 'Bing',
        message: 'Bing 搜索失败（解析异常）。建议配置 Bing 登录 Cookie。',
        details: e.toString(),
      );
    }
  }

  /// Parses Bing HTML search results page with multi-selector fallbacks & link decoding.
  List<SearchResult> _parseBingResults(html_dom.Document document) {
    final results = <SearchResult>[];
    final seenUrls = <String>{};

    // Try to extract Bing AI summary from `.cht_root` or `div[data-scenario="nrt"]` or `[data-scenario="nrt"]`
    final chatRoot = document.querySelector('.cht_root') ??
        document.querySelector('div[data-scenario="nrt"]') ??
        document.querySelector('[data-scenario="nrt"]');
    if (chatRoot != null) {
      final tempDiv = chatRoot.clone(true);
      tempDiv.querySelectorAll('script, style, noscript').forEach((el) => el.remove());
      final summaryText = tempDiv.text.trim();
      if (summaryText.isNotEmpty) {
        final cleanSummary = summaryText.replaceAll(RegExp(r'\s+'), ' ');
        results.add(SearchResult(
          title: 'Bing AI 搜索总结',
          url: '',
          content: cleanSummary,
        ));
      }
    }

    var items = document.querySelectorAll('li.b_algo');
    if (items.isEmpty) {
      items = document.querySelectorAll('.b_algo');
    }
    if (items.isEmpty) {
      items = document.querySelectorAll('ol#b_results > li');
    }
    if (items.isEmpty) {
      items = document.querySelectorAll('#b_results > li');
    }

    for (final item in items) {
      try {
        final heading = item.querySelector('h2') ?? item.querySelector('h3') ?? item.querySelector('.b_title') ?? item.querySelector('.b_algoHeader');
        final link = heading?.querySelector('a') ?? item.querySelector('a.tilk') ?? item.querySelector('a');
        if (link == null) continue;

        var title = link.text.trim();
        if (title.isEmpty && heading != null) {
          title = heading.text.trim();
        }
        if (title.isEmpty) {
          title = link.attributes['title']?.trim() ?? '';
        }

        var rawUrl = link.attributes['href']?.trim() ?? '';
        if (title.isEmpty || rawUrl.isEmpty || rawUrl.startsWith('javascript:') || rawUrl == '#') continue;

        final url = _decodeBingUrl(rawUrl);
        if (seenUrls.contains(url)) continue;

        String snippet = '';
        final selectors = ['.b_caption p', '.b_algoSlug', '.b_lineclamp2', '.b_lineclamp3', '.b_snippet', '.b_attribution', '.b_factrow', 'p', '.b_paractl'];
        for (final sel in selectors) {
          final el = item.querySelector(sel);
          if (el != null && el.text.trim().isNotEmpty) {
            snippet = el.text.trim();
            break;
          }
        }

        seenUrls.add(url);
        results.add(SearchResult(
          title: title.replaceAll(RegExp(r'\s+'), ' '),
          url: url,
          content: snippet,
        ));
      } catch (_) {
        // Skip malformed items
      }
    }

    return results;
  }

  /// Decodes Bing tracking/redirect URLs (e.g., /ck/a?!...&u=a1aHR0cHM6...) to direct URLs.
  String _decodeBingUrl(String href) {
    var url = href;
    if (url.startsWith('/')) {
      url = 'https://www.bing.com$url';
    }

    try {
      final uri = Uri.parse(url);
      final rawU = uri.queryParameters['u'];
      if (rawU != null && rawU.isNotEmpty) {
        var cleanU = rawU;
        if (cleanU.startsWith('a1')) {
          cleanU = cleanU.substring(2);
        }
        final normalized = base64.normalize(cleanU);
        final decodedBytes = base64.decode(normalized);
        final decodedUrl = utf8.decode(decodedBytes, allowMalformed: true);
        if (decodedUrl.startsWith('http://') || decodedUrl.startsWith('https://')) {
          return decodedUrl;
        }
      }
    } catch (_) {}

    return url;
  }

  /// Formats a list of [SearchResult]s into a markdown-like text structure
  /// suitable for injecting into the LLM system/user context.
  String formatSearchResultsForContext(List<SearchResult> results) {
    if (results.isEmpty) {
      return '未找到相关网络搜索结果。';
    }

    final buffer = StringBuffer();
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
