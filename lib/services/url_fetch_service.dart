import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

class UrlFetchService {
  final Dio _dio;

  UrlFetchService({Dio? dio}) : _dio = dio ?? Dio();

  /// Fetches webpage content from [url], strips scripts/styles/nav/footer, extracts body text,
  /// formats block elements with Markdown structures, and truncates output to 8000 characters.
  Future<String> fetchUrlContent(String url, {CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<dynamic>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-Hans,zh;q=0.9,en;q=0.8',
          },
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
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

      if (cleanedText.length > 8000) {
        return cleanedText.substring(0, 8000);
      }

      return cleanedText;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return '读取网页超时：请检查网络或目标 URL 是否可达';
      }
      return '读取网页失败：${e.message ?? e.toString()}';
    } catch (e) {
      return '解析网页失败：$e';
    }
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
          case 'tr':
            buffer.write('\n');
            for (final child in current.nodes) {
              traverse(child);
            }
            break;
          case 'td':
          case 'th':
            buffer.write(' | ');
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
}
