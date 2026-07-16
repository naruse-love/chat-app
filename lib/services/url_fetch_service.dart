import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

class UrlFetchService {
  final Dio _dio;

  UrlFetchService({Dio? dio}) : _dio = dio ?? Dio();

  /// Fetches webpage content from [url], strips scripts/styles/noscript, extracts body text,
  /// normalizes whitespace, and truncates output to 8000 characters.
  Future<String> fetchUrlContent(String url, {CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<String>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final htmlContent = response.data ?? '';
      if (htmlContent.trim().isEmpty) {
        return '网页内容为空';
      }

      final document = html_parser.parse(htmlContent);

      for (final tag in ['script', 'style', 'noscript']) {
        document.getElementsByTagName(tag).toList().forEach((element) => element.remove());
      }

      final rawText = document.body?.text ?? document.documentElement?.text ?? '';
      final cleanedText = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();

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
}
