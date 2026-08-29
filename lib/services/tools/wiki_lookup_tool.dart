import 'package:dio/dio.dart';
import '../../models/tool/tool.dart';

/// Exception thrown when Wikipedia lookup operations fail.
class WikiLookupException implements Exception {
  final String message;
  final int? statusCode;
  const WikiLookupException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Wiki Lookup Tool fetching article summaries, encyclopedia entries, and disambiguations from Wikipedia.
class WikiLookupTool extends Tool {
  final Dio _dio;

  WikiLookupTool({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                headers: {
                  'User-Agent': 'ChatApp/1.0 (https://github.com/naruse-love/chat-app; naruse@chat-app.org)',
                  'Accept': 'application/json',
                },
              ),
            );

  @override
  String get name => 'wiki_lookup';

  @override
  String get displayName => '维基百科检索';

  @override
  String get description =>
      'Search and retrieve summaries, encyclopedia descriptions, facts, and disambiguation links from Chinese and English Wikipedia.';

  @override
  ToolSecurityLevel get securityLevel => ToolSecurityLevel.readOnly;

  @override
  List<ToolParameter> get parameters => const [
    ToolParameter(
      name: 'query',
      type: 'string',
      description:
          'The topic, concept, term, or person to look up in Wikipedia (e.g. "人工智能", "量子力学", "Flutter", "Albert Einstein").',
      required: true,
    ),
    ToolParameter(
      name: 'language',
      type: 'string',
      description: 'Language edition of Wikipedia ("zh" for Chinese, "en" for English). Default: "zh".',
      required: false,
      enumValues: ['zh', 'en'],
      defaultValue: 'zh',
    ),
    ToolParameter(
      name: 'extractLength',
      type: 'integer',
      description: 'Maximum character length of the summary extract. Default: 1000.',
      required: false,
      defaultValue: 1000,
    ),
  ];

  @override
  Future<ToolExecutionResult> execute(Map<String, dynamic> arguments) async {
    final stopwatch = Stopwatch()..start();
    final query = (arguments['query'] as String? ?? '').trim();

    if (query.isEmpty) {
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '查询关键词不能为空',
        executionDuration: stopwatch.elapsed,
      );
    }

    final lang = (arguments['language'] as String? ?? 'zh').trim().toLowerCase() == 'en' ? 'en' : 'zh';
    final rawLength = arguments['extractLength'];
    int maxLength = 1000;
    if (rawLength is int) {
      maxLength = rawLength > 0 ? rawLength : 1000;
    } else if (rawLength is String) {
      maxLength = int.tryParse(rawLength) ?? 1000;
    }

    try {
      // 1. Try Direct Page Summary REST API
      final summaryUrl = 'https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(query)}';
      Response? summaryResponse;
      try {
        summaryResponse = await _dio.get(
          summaryUrl,
          options: Options(
            validateStatus: (status) => status != null && (status == 200 || status == 404),
          ),
        );
      } on DioException catch (dioErr) {
        if (dioErr.response?.statusCode != 404) {
          rethrow;
        }
      }

      if (summaryResponse != null && summaryResponse.statusCode == 200 && summaryResponse.data is Map) {
        final data = summaryResponse.data as Map<String, dynamic>;
        final type = data['type'] as String? ?? 'standard';
        final extract = data['extract'] as String? ?? '';

        if (type == 'standard' && extract.isNotEmpty) {
          stopwatch.stop();
          final title = data['title'] as String? ?? query;
          final description = data['description'] as String? ?? '';
          final pageUrl = (data['content_urls']?['desktop']?['page'] as String?) ??
              'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title)}';

          String effectiveExtract = extract;
          if (effectiveExtract.length > maxLength) {
            effectiveExtract = '${effectiveExtract.substring(0, maxLength)}...';
          }

          final buffer = StringBuffer();
          buffer.writeln('### 📚 维基百科：$title\n');
          if (description.isNotEmpty) {
            buffer.writeln('> **描述**: $description');
          }
          buffer.writeln('> **词条链接**: [查看完整词条]($pageUrl)\n');
          buffer.writeln(effectiveExtract);

          final markdown = buffer.toString().trim();

          return ToolExecutionResult.success(
            toolName: name,
            content: markdown,
            rawData: {
              'type': 'summary',
              'query': query,
              'language': lang,
              'title': title,
              'description': description,
              'extract': effectiveExtract,
              'url': pageUrl,
            },
            executionDuration: stopwatch.elapsed,
            metadata: {'query': query, 'title': title, 'language': lang},
          );
        }
      }

      // 2. Fallback to MediaWiki Search API (Disambiguation or 404)
      final searchUrl =
          'https://$lang.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&format=json&utf8=1';
      final searchResponse = await _dio.get(searchUrl);
      final searchData = searchResponse.data;

      if (searchData is Map &&
          searchData['query'] != null &&
          searchData['query']['search'] != null &&
          (searchData['query']['search'] as List).isNotEmpty) {
        final searchResults = (searchData['query']['search'] as List).cast<Map<String, dynamic>>();

        // If exact or very close title found on top, try fetching that top title's summary
        final firstItem = searchResults.first;
        final firstTitle = firstItem['title'] as String? ?? '';

        if (searchResults.length == 1 || firstTitle.toLowerCase() == query.toLowerCase()) {
          try {
            final topSummaryUrl = 'https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(firstTitle)}';
            final topSummaryResp = await _dio.get(topSummaryUrl);
            if (topSummaryResp.statusCode == 200 && topSummaryResp.data is Map) {
              final topData = topSummaryResp.data as Map<String, dynamic>;
              final topExtract = topData['extract'] as String? ?? '';
              if (topExtract.isNotEmpty && (topData['type'] as String? ?? '') != 'disambiguation') {
                stopwatch.stop();
                final topDesc = topData['description'] as String? ?? '';
                final topPageUrl = (topData['content_urls']?['desktop']?['page'] as String?) ??
                    'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(firstTitle)}';

                String effectiveExtract = topExtract;
                if (effectiveExtract.length > maxLength) {
                  effectiveExtract = '${effectiveExtract.substring(0, maxLength)}...';
                }

                final buffer = StringBuffer();
                buffer.writeln('### 📚 维基百科：$firstTitle\n');
                if (topDesc.isNotEmpty) {
                  buffer.writeln('> **描述**: $topDesc');
                }
                buffer.writeln('> **词条链接**: [查看完整词条]($topPageUrl)\n');
                buffer.writeln(effectiveExtract);

                return ToolExecutionResult.success(
                  toolName: name,
                  content: buffer.toString().trim(),
                  rawData: {
                    'type': 'summary',
                    'query': query,
                    'language': lang,
                    'title': firstTitle,
                    'description': topDesc,
                    'extract': effectiveExtract,
                    'url': topPageUrl,
                  },
                  executionDuration: stopwatch.elapsed,
                  metadata: {'query': query, 'title': firstTitle, 'language': lang},
                );
              }
            }
          } catch (_) {
            // Fallback to options list formatting below
          }
        }

        // Format disambiguation / search options list
        final buffer = StringBuffer();
        buffer.writeln('### 📚 维基百科消歧义 / 相关词条: "$query"\n');
        buffer.writeln('该词条可能指代多个主题，请参考以下相关词条：\n');

        final optionsList = <Map<String, dynamic>>[];
        int rank = 1;
        for (final item in searchResults.take(6)) {
          final title = item['title'] as String? ?? '';
          final rawSnippet = item['snippet'] as String? ?? '';
          final cleanSnippet = _stripHtml(rawSnippet);
          final url = 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title)}';

          buffer.writeln('$rank. **[$title]($url)**: $cleanSnippet');
          optionsList.add({
            'rank': rank,
            'title': title,
            'url': url,
            'snippet': cleanSnippet,
          });
          rank++;
        }

        stopwatch.stop();

        return ToolExecutionResult.success(
          toolName: name,
          content: buffer.toString().trim(),
          rawData: {
            'type': 'disambiguation',
            'query': query,
            'language': lang,
            'options': optionsList,
          },
          executionDuration: stopwatch.elapsed,
          metadata: {'query': query, 'language': lang, 'optionsCount': optionsList.length},
        );
      }

      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '未找到与 "$query" 相关的维基百科词条。',
        content: '检索失败: 未找到与 "$query" 相关的维基百科词条，请尝试更精确或不同的关键词。',
        executionDuration: stopwatch.elapsed,
        metadata: {'query': query, 'language': lang},
      );
    } on DioException catch (e) {
      stopwatch.stop();
      String message;
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        message = '维基百科网络请求超时，请检查网络连接。';
      } else if (e.response?.statusCode != null) {
        message = '维基百科服务响应异常 (HTTP ${e.response?.statusCode})。';
      } else {
        message = '维基百科网络连接失败: ${e.message}';
      }
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: message,
        content: '检索失败: $message',
        executionDuration: stopwatch.elapsed,
        metadata: {'query': query, 'dioError': e.type.name},
      );
    } catch (e) {
      stopwatch.stop();
      return ToolExecutionResult.failure(
        toolName: name,
        errorMessage: '维基百科检索出现异常: $e',
        content: '检索失败: $e',
        executionDuration: stopwatch.elapsed,
        metadata: {'query': query},
      );
    }
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}
