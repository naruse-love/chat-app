import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

class UrlFetchService {
  final Dio _dio;

  UrlFetchService({Dio? dio}) : _dio = dio ?? Dio();

  /// Fetches webpage content from [url], extracts title/metadata/tables/links,
  /// formats block elements with Markdown structures, and truncates output to 8000 characters.
  Future<String> fetchUrlContent(String url, {CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
            'Sec-Ch-Ua': '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"',
            'Sec-Ch-Ua-Mobile': '?0',
            'Sec-Ch-Ua-Platform': '"Windows"',
          },
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );

      String htmlContent = '';
      if (response.data is List<int>) {
        htmlContent = utf8.decode(response.data as List<int>, allowMalformed: true);
      } else if (response.data is String) {
        htmlContent = response.data as String;
      }

      if (htmlContent.trim().isEmpty) {
        return '网页内容为空';
      }

      final document = html_parser.parse(htmlContent);

      // Extract metadata before stripping tags
      final title = _extractTitle(document);
      final description = _extractMeta(document, ['description', 'og:description', 'twitter:description']);
      final author = _extractMeta(document, ['author', 'article:author', 'og:article:author']);
      final keywords = _extractMeta(document, ['keywords']);

      // Strip non-content tags
      for (final tag in ['script', 'style', 'noscript', 'svg', 'iframe']) {
        document.getElementsByTagName(tag).toList().forEach((element) => element.remove());
      }

      final bodyElement = document.body ?? document.documentElement;
      if (bodyElement == null) {
        return '提取网页正文内容为空';
      }

      final structuredText = _parseHtmlToStructuredMarkdown(bodyElement);
      final cleanedText = structuredText
          .split('\n')
          .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
          .join('\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();

      if (cleanedText.isEmpty) {
        return '提取网页正文内容为空';
      }

      final metadataBuffer = StringBuffer();
      if (title.isNotEmpty) {
        metadataBuffer.writeln('# $title\n');
      }

      final metaList = <String>[];
      if (author.isNotEmpty) metaList.add('作者: $author');
      if (description.isNotEmpty) metaList.add('描述: $description');
      if (keywords.isNotEmpty) metaList.add('关键词: $keywords');

      if (metaList.isNotEmpty) {
        metadataBuffer.writeln('> **元数据**: ${metaList.join(' | ')}\n');
      }

      final fullOutput = metadataBuffer.toString() + cleanedText;

      if (fullOutput.length > 8000) {
        return fullOutput.substring(0, 8000);
      }

      return fullOutput;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return '读取网页超时：请检查网络或目标 URL 是否可达';
      }
      if (e.response?.statusCode == 403) {
        return '读取网页被阻断：目标网站存在反爬虫防护或防火墙拦截 (HTTP 403)';
      }
      return '读取网页失败：${e.message ?? e.toString()}';
    } catch (e) {
      return '解析网页失败：$e';
    }
  }

  String _extractTitle(html_dom.Document document) {
    final titleTag = document.querySelector('title')?.text.trim();
    if (titleTag != null && titleTag.isNotEmpty) return titleTag;

    final ogTitle = document.querySelector('meta[property="og:title"]')?.attributes['content']?.trim();
    if (ogTitle != null && ogTitle.isNotEmpty) return ogTitle;

    return '';
  }

  String _extractMeta(html_dom.Document document, List<String> names) {
    for (final name in names) {
      final meta = document.querySelector('meta[name="$name"]') ??
          document.querySelector('meta[property="$name"]');
      final content = meta?.attributes['content']?.trim();
      if (content != null && content.isNotEmpty) return content;
    }
    return '';
  }

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
            buffer.write('\n\n');
            for (final child in current.nodes) {
              traverse(child);
            }
            buffer.write('\n\n');
            break;
          case 'br':
            buffer.write('\n');
            break;
          case 'li':
            buffer.write('\n- ');
            for (final child in current.nodes) {
              traverse(child);
            }
            buffer.write('\n');
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
