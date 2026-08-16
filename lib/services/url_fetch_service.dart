import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import '../models/fetch_result.dart';

export '../models/fetch_result.dart';

/// Service class for fetching and intelligently parsing webpage content.
///
/// Features:
/// - P0: Truncation awareness with explicit markers & stats (up to 15,000 chars)
/// - P0: Page type & security challenge detection (captcha, login_wall, nav_hub, article, error_page)
/// - P0: Rich structured metadata extraction (title, author, date, site, language, OG, JSON-LD)
/// - P1: Main content prioritization (`<article>`, `<main>`, `.markdown-body`, etc.) & noise stripping (`<nav>`, `<footer>`, `<aside>`)
/// - P1: Link statistics (total / internal / external)
/// - P2: JSON-LD structured data parser
class UrlFetchService {
  final Dio _dio;
  static const int defaultMaxCharacters = 15000;

  UrlFetchService({Dio? dio}) : _dio = dio ?? Dio();

  /// Fetches webpage content from [url] and returns a formatted Markdown string.
  /// Backward-compatible with AgentService and other callers.
  Future<String> fetchUrlContent(
    String url, {
    CancelToken? cancelToken,
  }) async {
    final result = await fetchUrl(url, cancelToken: cancelToken);
    return result.toStructuredMarkdown();
  }

  /// Fetches webpage content from [url] and returns a rich [FetchResult] object.
  Future<FetchResult> fetchUrl(
    String url, {
    CancelToken? cancelToken,
    int maxCharacters = defaultMaxCharacters,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
            'Sec-Ch-Ua': '"Not/A)Brand";v="8", "Chromium";v="126", "Google Chrome";v="126"',
            'Sec-Ch-Ua-Mobile': '?0',
            'Sec-Ch-Ua-Platform': '"Windows"',
          },
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );

      String rawContent = '';
      if (response.data is List<int>) {
        rawContent = utf8.decode(response.data as List<int>, allowMalformed: true);
      } else if (response.data is String) {
        rawContent = response.data as String;
      }

      if (rawContent.trim().isEmpty) {
        return FetchResult(
          url: url,
          status: 'error',
          pageType: 'error_page',
          truncated: false,
          originalLength: 0,
          maxLength: maxCharacters,
          contentRatio: 0.0,
          metadata: const FetchMetadata(),
          mainContent: '网页内容为空',
          warnings: const ['网页返回内容为空白'],
        );
      }

      return _parseHtml(url, rawContent, maxCharacters);
    } on DioException catch (e) {
      String errorMessage;
      String pageType = 'error_page';
      final warnings = <String>[];

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        errorMessage = '读取网页超时：请检查网络连接或目标 URL 是否可达';
        warnings.add('请求超时');
      } else if (e.response?.statusCode == 403) {
        errorMessage = '读取网页被阻断：目标网站存在反爬虫防护或防火墙拦截 (HTTP 403)';
        pageType = 'captcha';
        warnings.add('目标网站返回 HTTP 403，可能存在 Cloudflare / WAF 反爬防护');
      } else if (e.response?.statusCode == 404) {
        errorMessage = '网页不存在：目标页面返回 404 Not Found';
        warnings.add('HTTP 404 页面不存在');
      } else {
        errorMessage = '读取网页失败：${e.message ?? e.toString()}';
        warnings.add('HTTP 请求异常');
      }

      return FetchResult(
        url: url,
        status: 'error',
        pageType: pageType,
        truncated: false,
        originalLength: errorMessage.length,
        maxLength: maxCharacters,
        contentRatio: 0.0,
        metadata: const FetchMetadata(),
        mainContent: errorMessage,
        warnings: warnings,
      );
    } catch (e) {
      final errorMsg = '解析网页失败：$e';
      return FetchResult(
        url: url,
        status: 'error',
        pageType: 'error_page',
        truncated: false,
        originalLength: errorMsg.length,
        maxLength: maxCharacters,
        contentRatio: 0.0,
        metadata: const FetchMetadata(),
        mainContent: errorMsg,
        warnings: [errorMsg],
      );
    }
  }

  FetchResult _parseHtml(String url, String htmlContent, int maxCharacters) {
    final document = html_parser.parse(htmlContent);
    final warnings = <String>[];

    // 1. Check link statistics across the entire raw document
    final linkStats = _analyzeLinks(document, url);

    // 2. Extract rich metadata (HTML Meta, OpenGraph, JSON-LD, Twitter)
    final metadata = _extractRichMetadata(document);

    // 3. Detect page security challenges & page type
    final rawLower = htmlContent.toLowerCase();
    final pageType = _detectPageType(document, rawLower, linkStats);

    if (pageType == 'captcha') {
      warnings.add('检测到反爬/人机验证页面（如 Cloudflare, 极验, 验证码等），未获取到真实正文');
    } else if (pageType == 'login_wall') {
      warnings.add('检测到登录拦截墙（Login Wall），页面内容仅包含登录/注册入口');
    } else if (pageType == 'nav_hub') {
      warnings.add('该页面为导航/门户索引页，正文较少，链接较多');
    }

    // 4. Strip non-content script / style / svg / noscript / iframe elements
    for (final tag in ['script', 'style', 'noscript', 'svg', 'iframe', 'canvas']) {
      document.getElementsByTagName(tag).toList().forEach((el) => el.remove());
    }

    // 5. Locate main content container or fallback to body with noise stripped
    final bodyElement = document.body ?? document.documentElement;
    if (bodyElement == null) {
      return FetchResult(
        url: url,
        status: 'error',
        pageType: 'error_page',
        truncated: false,
        originalLength: 0,
        maxLength: maxCharacters,
        contentRatio: 0.0,
        metadata: metadata,
        mainContent: '提取网页正文内容为空',
        warnings: const ['未能找到 HTML body 或根节点'],
      );
    }

    final mainContainer = _findMainContentContainer(bodyElement);
    final structuredText = _parseHtmlToStructuredMarkdown(mainContainer);

    final cleanedText = structuredText
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (cleanedText.isEmpty) {
      return FetchResult(
        url: url,
        status: 'success',
        pageType: pageType,
        truncated: false,
        originalLength: 0,
        maxLength: maxCharacters,
        contentRatio: 0.0,
        metadata: metadata,
        mainContent: '提取网页正文内容为空',
        totalLinks: linkStats.total,
        internalLinks: linkStats.internal,
        externalLinks: linkStats.external,
        warnings: ['正文提取结果为空'],
      );
    }

    // 6. Calculate Content Ratio (Text characters / Total raw HTML characters)
    final contentRatio = (cleanedText.length / (htmlContent.isNotEmpty ? htmlContent.length : 1))
        .clamp(0.0, 1.0);

    // 7. Handle truncation
    final originalLength = cleanedText.length;
    final isTruncated = originalLength > maxCharacters;
    final finalContent = isTruncated ? cleanedText.substring(0, maxCharacters) : cleanedText;

    if (isTruncated) {
      warnings.add('正文超出 $maxCharacters 字符上限，已截断展示');
    }

    return FetchResult(
      url: url,
      status: 'success',
      pageType: pageType,
      truncated: isTruncated,
      originalLength: originalLength,
      maxLength: maxCharacters,
      contentRatio: double.parse(contentRatio.toStringAsFixed(3)),
      metadata: metadata,
      mainContent: finalContent,
      totalLinks: linkStats.total,
      internalLinks: linkStats.internal,
      externalLinks: linkStats.external,
      warnings: warnings,
    );
  }

  /// Finds the best main content container node or cleans noise from body.
  html_dom.Element _findMainContentContainer(html_dom.Element body) {
    // 1. Look for explicit semantic tags with substantial content
    final semanticSelectors = [
      'article',
      'main',
      '[role="main"]',
      '.post-content',
      '.article-content',
      '.article-body',
      '.entry-content',
      '.markdown-body',
      '.topic-content',
      '.content-body',
      '#content',
      '#main-content',
      '#article',
      '#article-content',
      '.blog-content',
      '.cnblogs-post-body',
    ];

    for (final selector in semanticSelectors) {
      final elements = body.querySelectorAll(selector);
      for (final el in elements) {
        // Must contain meaningful text length (> 80 characters)
        if (el.text.trim().length > 80) {
          // Remove inner noise elements (nav, footer, aside, ads)
          _stripNoiseElements(el);
          return el;
        }
      }
    }

    // 2. If no semantic container matched, clone body and strip outer noise
    final clonedBody = body.clone(true);
    _stripNoiseElements(clonedBody);
    return clonedBody;
  }

  /// Removes navigation bars, headers, footers, sidebars, advertisements and cookie notices.
  void _stripNoiseElements(html_dom.Element element) {
    final noiseSelectors = [
      'nav',
      'header',
      'footer',
      'aside',
      '[role="navigation"]',
      '[role="banner"]',
      '[role="contentinfo"]',
      '[role="complementary"]',
      '.nav',
      '.navbar',
      '.header',
      '.footer',
      '.sidebar',
      '.aside',
      '.menu',
      '.ad',
      '.ads',
      '.advertisement',
      '.banner',
      '.cookie-banner',
      '.popup',
      '.modal',
      '.comment-form',
      '.share-buttons',
    ];

    for (final selector in noiseSelectors) {
      try {
        final matches = element.querySelectorAll(selector);
        for (final match in matches) {
          match.remove();
        }
      } catch (_) {
        // Ignore invalid selector errors
      }
    }
  }

  /// Detects the page category based on keywords, forms, and ratios.
  String _detectPageType(html_dom.Document document, String rawLower, _LinkStats linkStats) {
    // 1. Captcha / Anti-bot challenge detection
    final isCaptcha = rawLower.contains('please wait') ||
        rawLower.contains('checking your browser') ||
        rawLower.contains('cf-browser-verification') ||
        rawLower.contains('g-recaptcha') ||
        rawLower.contains('client_captcha') ||
        rawLower.contains('验证码') ||
        rawLower.contains('安全验证') ||
        rawLower.contains('人机身份验证') ||
        rawLower.contains('waf') ||
        document.querySelector('#challenge') != null ||
        document.querySelector('.b_captcha') != null ||
        document.querySelector('.geetest') != null;

    if (isCaptcha && document.body != null && document.body!.text.trim().length < 600) {
      return 'captcha';
    }

    // 2. Login Wall detection
    final hasPasswordInput = document.querySelector('input[type="password"]') != null;
    final isLoginPrompt = rawLower.contains('请登录') ||
        rawLower.contains('登录后查看') ||
        rawLower.contains('sign in to continue') ||
        rawLower.contains('log in');
    if (hasPasswordInput && (isLoginPrompt || (document.body?.text.trim().length ?? 0) < 500)) {
      return 'login_wall';
    }

    // 3. Error page detection
    final title = document.querySelector('title')?.text.toLowerCase() ?? '';
    if (title.contains('404') ||
        title.contains('not found') ||
        title.contains('500 internal server') ||
        title.contains('403 forbidden')) {
      return 'error_page';
    }

    // 4. Nav Hub / Portal detection (Lots of links, low plain text ratio)
    final bodyText = document.body?.text.trim() ?? '';
    if (linkStats.total > 40 && bodyText.isNotEmpty) {
      final averageTextPerLink = bodyText.length / linkStats.total;
      if (averageTextPerLink < 35) {
        return 'nav_hub';
      }
    }

    // 5. Documentation or Article
    if (document.querySelector('pre code, .highlight, .markdown-body') != null) {
      return 'doc';
    }

    if (document.querySelector('article, [role="main"], .post-content, .article-content') != null) {
      return 'article';
    }

    return 'article';
  }

  /// Extracts rich structured metadata from HTML tags, OG tags, Twitter cards, and JSON-LD.
  FetchMetadata _extractRichMetadata(html_dom.Document document) {
    // 1. Title
    String title = '';
    final ogTitle = document.querySelector('meta[property="og:title"]')?.attributes['content']?.trim();
    final metaTitle = document.querySelector('meta[name="title"]')?.attributes['content']?.trim();
    final tagTitle = document.querySelector('title')?.text.trim();
    final h1Title = document.querySelector('h1')?.text.trim();

    if (ogTitle != null && ogTitle.isNotEmpty) {
      title = ogTitle;
    } else if (tagTitle != null && tagTitle.isNotEmpty) {
      title = tagTitle;
    } else if (metaTitle != null && metaTitle.isNotEmpty) {
      title = metaTitle;
    } else if (h1Title != null && h1Title.isNotEmpty) {
      title = h1Title;
    }

    // 2. Description
    String description = '';
    final descSelectors = [
      'meta[property="og:description"]',
      'meta[name="description"]',
      'meta[name="twitter:description"]',
    ];
    for (final sel in descSelectors) {
      final desc = document.querySelector(sel)?.attributes['content']?.trim();
      if (desc != null && desc.isNotEmpty) {
        description = desc;
        break;
      }
    }

    // 3. Author
    String author = '';
    final authorSelectors = [
      'meta[name="author"]',
      'meta[property="article:author"]',
      'meta[property="og:article:author"]',
      'meta[name="twitter:creator"]',
      '.author',
      '.post-author',
      '.article-author',
      '#author',
    ];
    for (final sel in authorSelectors) {
      final el = document.querySelector(sel);
      final val = el?.attributes['content']?.trim() ?? el?.text.trim();
      if (val != null && val.isNotEmpty && val.length < 60) {
        author = val;
        break;
      }
    }

    // 4. Published Date
    String? publishedAt;
    final dateSelectors = [
      'meta[property="article:published_time"]',
      'meta[name="pubdate"]',
      'meta[name="publishdate"]',
      'meta[name="date"]',
      'meta[name="dc.date"]',
      'time[datetime]',
      '.post-date',
      '.publish-time',
    ];
    for (final sel in dateSelectors) {
      final el = document.querySelector(sel);
      final dateVal = el?.attributes['content']?.trim() ??
          el?.attributes['datetime']?.trim() ??
          el?.text.trim();
      if (dateVal != null && dateVal.isNotEmpty && dateVal.length < 50) {
        publishedAt = dateVal;
        break;
      }
    }

    // 5. Site Name
    String? siteName;
    final siteSelectors = [
      'meta[property="og:site_name"]',
      'meta[name="application-name"]',
      'meta[name="publisher"]',
    ];
    for (final sel in siteSelectors) {
      final val = document.querySelector(sel)?.attributes['content']?.trim();
      if (val != null && val.isNotEmpty) {
        siteName = val;
        break;
      }
    }

    // 6. Language
    String? language = document.documentElement?.attributes['lang']?.trim() ??
        document.querySelector('meta[http-equiv="content-language"]')?.attributes['content']?.trim();

    // 7. Keywords
    String? keywords = document.querySelector('meta[name="keywords"]')?.attributes['content']?.trim() ??
        document.querySelector('meta[name="news_keywords"]')?.attributes['content']?.trim();

    // 8. OG Type & Image
    String? ogType = document.querySelector('meta[property="og:type"]')?.attributes['content']?.trim();
    String? ogImage = document.querySelector('meta[property="og:image"]')?.attributes['content']?.trim();

    // 9. JSON-LD fallback enrichment
    final jsonLdData = _extractJsonLd(document);
    if (jsonLdData != null) {
      if (title.isEmpty && jsonLdData['headline'] != null) {
        title = jsonLdData['headline'].toString();
      }
      if (description.isEmpty && jsonLdData['description'] != null) {
        description = jsonLdData['description'].toString();
      }
      if (author.isEmpty && jsonLdData['author'] != null) {
        final ldAuthor = jsonLdData['author'];
        if (ldAuthor is Map) {
          author = ldAuthor['name']?.toString() ?? '';
        } else if (ldAuthor is String) {
          author = ldAuthor;
        }
      }
      if (publishedAt == null && jsonLdData['datePublished'] != null) {
        publishedAt = jsonLdData['datePublished'].toString();
      }
      if (siteName == null && jsonLdData['publisher'] != null) {
        final ldPublisher = jsonLdData['publisher'];
        if (ldPublisher is Map) {
          siteName = ldPublisher['name']?.toString();
        } else if (ldPublisher is String) {
          siteName = ldPublisher;
        }
      }
    }

    return FetchMetadata(
      title: title,
      description: description,
      author: author,
      publishedAt: publishedAt,
      language: language,
      siteName: siteName,
      keywords: keywords,
      ogType: ogType,
      ogImage: ogImage,
    );
  }

  /// Extracts structured data from `<script type="application/ld+json">`.
  Map<String, dynamic>? _extractJsonLd(html_dom.Document document) {
    final scripts = document.querySelectorAll('script[type="application/ld+json"]');
    for (final script in scripts) {
      final text = script.text.trim();
      if (text.isEmpty) continue;
      try {
        final decoded = json.decode(text);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        } else if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
          return decoded.first as Map<String, dynamic>;
        }
      } catch (_) {
        // Skip invalid JSON-LD
      }
    }
    return null;
  }

  /// Analyzes link counts and distinguishes between internal and external links.
  _LinkStats _analyzeLinks(html_dom.Document document, String baseUrl) {
    final links = document.querySelectorAll('a[href]');
    int internal = 0;
    int external = 0;
    Uri? baseUri;
    try {
      baseUri = Uri.parse(baseUrl);
    } catch (_) {}

    for (final link in links) {
      final href = link.attributes['href']?.trim();
      if (href == null || href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) {
        continue;
      }
      if (href.startsWith('http://') || href.startsWith('https://')) {
        try {
          final uri = Uri.parse(href);
          if (baseUri != null && uri.host.toLowerCase() == baseUri.host.toLowerCase()) {
            internal++;
          } else {
            external++;
          }
        } catch (_) {
          external++;
        }
      } else {
        internal++;
      }
    }

    return _LinkStats(total: internal + external, internal: internal, external: external);
  }

  /// Recursively parses HTML DOM elements into clean, readable Markdown format.
  String _parseHtmlToStructuredMarkdown(html_dom.Node node) {
    final buffer = StringBuffer();

    void traverse(html_dom.Node current) {
      if (current is html_dom.Text) {
        buffer.write(current.text);
        return;
      }

      if (current is html_dom.Element) {
        final tag = current.localName?.toLowerCase() ?? '';

        if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
          final level = int.parse(tag.substring(1));
          final prefix = '#' * level;
          buffer.write('\n\n$prefix ');
          for (final child in current.nodes) {
            traverse(child);
          }
          buffer.write('\n\n');
          return;
        }

        switch (tag) {
          case 'p':
          case 'div':
          case 'article':
          case 'section':
          case 'header':
          case 'footer':
            buffer.write('\n\n');
            for (final child in current.nodes) {
              traverse(child);
            }
            buffer.write('\n\n');
            break;
          case 'br':
            buffer.write('\n');
            break;
          case 'hr':
            buffer.write('\n\n---\n\n');
            break;
          case 'li':
            buffer.write('\n- ');
            for (final child in current.nodes) {
              traverse(child);
            }
            buffer.write('\n');
            break;
          case 'blockquote':
            buffer.write('\n\n> ');
            final subBuffer = StringBuffer();
            for (final child in current.nodes) {
              final text = _parseHtmlToStructuredMarkdown(child);
              subBuffer.write(text);
            }
            buffer.write(subBuffer.toString().trim().replaceAll('\n', '\n> '));
            buffer.write('\n\n');
            break;
          case 'pre':
            buffer.write('\n\n```\n');
            buffer.write(current.text.trim());
            buffer.write('\n```\n\n');
            break;
          case 'code':
            if (current.parent?.localName?.toLowerCase() != 'pre') {
              buffer.write(' `');
              buffer.write(current.text.trim());
              buffer.write('` ');
            }
            break;
          case 'table':
            buffer.write('\n\n');
            _parseTable(current, buffer);
            buffer.write('\n\n');
            break;
          case 'tr':
          case 'td':
          case 'th':
            buffer.write(' ');
            for (final child in current.nodes) {
              traverse(child);
            }
            break;
          case 'a':
            final href = current.attributes['href'];
            final text = current.text.trim();
            if (href != null && href.startsWith('http') && text.isNotEmpty) {
              buffer.write(' [$text]($href) ');
            } else {
              for (final child in current.nodes) {
                traverse(child);
              }
            }
            break;
          case 'strong':
          case 'b':
            buffer.write(' **');
            for (final child in current.nodes) {
              traverse(child);
            }
            buffer.write('** ');
            break;
          case 'em':
          case 'i':
            buffer.write(' *');
            for (final child in current.nodes) {
              traverse(child);
            }
            buffer.write('* ');
            break;
          default:
            for (final child in current.nodes) {
              traverse(child);
            }
            break;
        }
      }
    }

    traverse(node);
    return buffer.toString();
  }

  void _parseTable(html_dom.Element table, StringBuffer buffer) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return;

    bool isFirstRow = true;
    for (final row in rows) {
      final cells = row.querySelectorAll('th, td');
      if (cells.isEmpty) continue;

      final rowTexts = cells.map((cell) => cell.text.replaceAll('\n', ' ').trim()).toList();
      buffer.writeln('| ${rowTexts.join(' | ')} |');

      if (isFirstRow) {
        final divider = List.filled(cells.length, '---').join(' | ');
        buffer.writeln('| $divider |');
        isFirstRow = false;
      }
    }
  }
}

class _LinkStats {
  final int total;
  final int internal;
  final int external;

  const _LinkStats({required this.total, required this.internal, required this.external});
}
