import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Weblio 抓取异常
class WeblioException implements Exception {
  final String message;
  WeblioException(this.message);

  @override
  String toString() => message;
}

/// Weblio 例句结构（包含汉字版与假名标注版）
class WeblioExample {
  final String kanji;
  final String furigana;

  const WeblioExample({
    required this.kanji,
    required this.furigana,
  });
}

/// Weblio 查词结果
class WeblioResult {
  final String word;
  final String reading;
  final String definition;
  final String partOfSpeech;
  final List<WeblioExample> examples;
  final String sourceDict;
  final String sourceUrl;

  const WeblioResult({
    required this.word,
    required this.reading,
    required this.definition,
    required this.partOfSpeech,
    this.examples = const [],
    required this.sourceDict,
    required this.sourceUrl,
  });
}

/// Weblio (https://www.weblio.jp) 日语词典抓取与解析服务
/// 优先解析小学馆《デジタル大辞泉》（SGKDJ），缺失时平滑降级至首个可用词典
class WeblioService {
  final Dio _dio;

  WeblioService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8,zh-CN;q=0.7,zh;q=0.6',
                },
              ),
            );

  /// 查词主入口
  Future<WeblioResult> lookupWord(String rawWord) async {
    final word = rawWord.trim();
    if (word.isEmpty) {
      throw WeblioException('查询单词不能为空');
    }

    final encoded = Uri.encodeComponent(word);
    final url = 'https://www.weblio.jp/content/$encoded';

    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );

      if (response.statusCode != 200 || response.data == null) {
        throw WeblioException('Weblio 请求失败 (HTTP ${response.statusCode})');
      }

      return parseHtml(response.data!, word, url);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw WeblioException('Weblio 连接超时，请检查网络连接');
      }
      throw WeblioException('Weblio 网络请求异常: ${e.message}');
    } catch (e) {
      if (e is WeblioException) rethrow;
      throw WeblioException('解析 Weblio 词典数据失败: $e');
    }
  }

  /// 纯 HTML 解析逻辑（支持无网络单元测试）
  WeblioResult parseHtml(String html, String word, [String? sourceUrl]) {
    final doc = html_parser.parse(html);
    final effectiveUrl = sourceUrl ?? 'https://www.weblio.jp/content/${Uri.encodeComponent(word)}';

    // 检查是否有未收录提示
    final bodyText = doc.body?.text ?? '';
    if (bodyText.contains('一致する見出し語は見つかりませんでした') ||
        bodyText.contains('に一致する項目は見つかりませんでした')) {
      throw WeblioException('未在 Weblio 找到「$word」的相关释义');
    }

    // 1. 优先定位小学馆《デジタル大辞泉》(SGKDJ)
    final sgkdjAnchor = doc.querySelector('a[name="SGKDJ"]');
    final sgkdjDiv = doc.querySelector('.Sgkdj');

    if (sgkdjAnchor != null || sgkdjDiv != null) {
      return _parseSgkdj(doc, word, effectiveUrl);
    }

    // 2. 降级回退：首个可用词典条目 (.kiji)
    final firstKiji = doc.querySelector('.kiji');
    if (firstKiji != null) {
      return _parseFallbackKiji(doc, firstKiji, word, effectiveUrl);
    }

    throw WeblioException('未在 Weblio 找到「$word」的词典释义');
  }

  /// 解析小学馆《デジタル大辞泉》
  WeblioResult _parseSgkdj(dom.Document doc, String word, String sourceUrl) {
    final sgkdjDiv = doc.querySelector('.Sgkdj');
    final midashigoH2 = doc.querySelector('.midashigo');
    final midashigoText = midashigoH2?.text.trim() ?? '';

    // 1. 假名读音 (Reading)
    String reading = '';
    if (sgkdjDiv != null) {
      for (final p in sgkdjDiv.querySelectorAll('p')) {
        final t = p.text.trim();
        if (t.startsWith('読み方：')) {
          reading = t.replaceFirst('読み方：', '').trim();
          reading = reading.split(RegExp(r'[\s\[［]')).first;
          break;
        }
      }
    }

    if (reading.isEmpty && midashigoText.isNotEmpty) {
      final kanaPart = midashigoText.split('【').first.trim();
      reading = kanaPart.replaceAll('・', '').replaceAll(RegExp(r'〔[^〕]*〕'), '').trim();
    }

    if (reading.isEmpty) {
      reading = word;
    }

    // 2. 词性 (PoS)
    String pos = '';
    final hinshiSpan = sgkdjDiv?.querySelector('.hinshi');
    if (hinshiSpan != null) {
      pos = hinshiSpan.text.trim().replaceAll(RegExp(r'[\s\[\]［］]'), '');
    } else if (sgkdjDiv != null) {
      final posMatch = RegExp(r'［([^］]+)］').firstMatch(sgkdjDiv.text);
      if (posMatch != null) {
        pos = posMatch.group(1)!.trim();
      }
    }

    // 3. 词干推断 (用于还原例句中的 ―・ 或 ―)
    String stem = '';
    final kanaPart = midashigoText.split('【').first;
    if (kanaPart.contains('・')) {
      final okurigana = kanaPart.split('・').last.replaceAll(RegExp(r'〔[^〕]*〕'), '').trim();
      if (word.endsWith(okurigana)) {
        stem = word.substring(0, word.length - okurigana.length);
      }
    }
    if (stem.isEmpty) {
      stem = word.replaceAll(RegExp(r'[\u3040-\u309f]+$'), '');
    }
    if (stem.isEmpty) {
      stem = word;
    }

    // 4. 日语释义与例句提取
    final defLines = <String>[];
    final examples = <WeblioExample>[];

    if (sgkdjDiv != null) {
      final ps = sgkdjDiv.querySelectorAll('p');
      for (final p in ps) {
        final text = p.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (text.isEmpty) continue;

        // 跳过纯粹的辅助与语法信息行
        if (text.startsWith('読み方：') ||
            text.startsWith('[補説]') ||
            text.startsWith('[派生]') ||
            text.startsWith('[用法]')) {
          continue;
        }

        // 跳过仅标明词性分类的短行
        if ((text.startsWith('［形］') || text.startsWith('［動') || text.startsWith('［名］')) &&
            !RegExp(r'[0-9０-９１２３４５６７８９]').hasMatch(text) &&
            !text.contains('。') &&
            !text.contains('「')) {
          continue;
        }

        // 提取例句 「...」
        final exMatches = RegExp(r'「([^」]+)」').allMatches(text);
        for (final m in exMatches) {
          final raw = m.group(1)!.trim();
          if (raw.length < 2) continue;

          // 仅处理包含连接符或包含单词本体的有效例句
          if (raw.contains('―') || raw.contains(word) || (stem.isNotEmpty && raw.contains(stem))) {
            var restored = raw.replaceAll('―・', stem).replaceAll('―', stem);
            final kanji = restored.replaceAll(RegExp(r'\([^\)]+\)'), '').trim();
            final furigana = restored.replaceAllMapped(
              RegExp(r'([^\(\s]+)\(([^\)]+)\)'),
              (match) => '${match.group(1)}[${match.group(2)}]',
            ).trim();

            if (kanji.isNotEmpty && !examples.any((e) => e.kanji == kanji)) {
              examples.add(WeblioExample(kanji: kanji, furigana: furigana));
            }
          }
        }

        // 清洗纯释义文本（剥离例句与引用出处）
        var cleanDef = text
            .replaceAll(RegExp(r'「[^」]*」'), '')
            .replaceAll(RegExp(r'〈[^〉]*〉'), '')
            .trim();

        // 移除开头的词性标记
        cleanDef = cleanDef.replaceFirst(RegExp(r'^［[^］]+］\s*'), '').trim();

        if (cleanDef.isNotEmpty &&
            !cleanDef.startsWith('読み方：') &&
            !cleanDef.startsWith('[補説]') &&
            !cleanDef.startsWith('[派生]') &&
            !cleanDef.startsWith('[用法]')) {
          defLines.add(cleanDef);
        }
      }
    }

    // 5. 若例句不足 2 条，尝试从 Weblio 例文用例辞书 (WNRYJ) 中补充
    if (examples.length < 2) {
      final wnryjLis = doc.querySelectorAll('.wnryj li');
      for (final li in wnryjLis) {
        if (examples.length >= 2) break;
        final rawSent = li.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (rawSent.isNotEmpty && !examples.any((e) => e.kanji == rawSent)) {
          examples.add(WeblioExample(kanji: rawSent, furigana: rawSent));
        }
      }
    }

    final definition = defLines.join('\n').trim();

    return WeblioResult(
      word: word,
      reading: reading,
      definition: definition,
      partOfSpeech: pos,
      examples: examples.take(2).toList(),
      sourceDict: 'デジタル大辞泉',
      sourceUrl: sourceUrl,
    );
  }

  /// 解析回退词典 (首个可用 .kiji)
  WeblioResult _parseFallbackKiji(
    dom.Document doc,
    dom.Element kiji,
    String word,
    String sourceUrl,
  ) {
    // 1. 尝试从前置 .pbarT 获取词典名
    String sourceDict = 'Weblio辞書';
    final pbarT = doc.querySelector('.pbarT');
    if (pbarT != null) {
      final text = pbarT.text.trim();
      if (text.isNotEmpty) {
        sourceDict = text.split(RegExp(r'\s+')).first;
      }
    }

    // 2. 读音
    String reading = '';
    final midashigo = kiji.querySelector('.midashigo')?.text.trim() ?? '';
    if (midashigo.isNotEmpty) {
      reading = midashigo.split('【').first.replaceAll('・', '').trim();
    }
    if (reading.isEmpty) {
      final readingMatch = RegExp(r'読み方：([^\s\n\r<]+)').firstMatch(kiji.text);
      if (readingMatch != null) {
        reading = readingMatch.group(1)!.trim();
      }
    }
    if (reading.isEmpty) {
      reading = word;
    }

    // 3. 词性
    String pos = '';
    final hinshi = kiji.querySelector('.hinshi')?.text.trim();
    if (hinshi != null && hinshi.isNotEmpty) {
      pos = hinshi.replaceAll(RegExp(r'[\s\[\]［］]'), '');
    }

    // 4. 释义文本
    final pElements = kiji.querySelectorAll('p');
    final defLines = <String>[];
    for (final p in pElements) {
      final t = p.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.isNotEmpty &&
          !t.startsWith('読み方：') &&
          !t.startsWith('[補説]') &&
          !t.startsWith('出典:')) {
        defLines.add(t);
      }
    }

    final definition = defLines.isNotEmpty
        ? defLines.join('\n').trim()
        : kiji.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    // 5. 例句补充
    final examples = <WeblioExample>[];
    final wnryjLis = doc.querySelectorAll('.wnryj li');
    for (final li in wnryjLis) {
      if (examples.length >= 2) break;
      final rawSent = li.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (rawSent.isNotEmpty) {
        examples.add(WeblioExample(kanji: rawSent, furigana: rawSent));
      }
    }

    return WeblioResult(
      word: word,
      reading: reading,
      definition: definition,
      partOfSpeech: pos,
      examples: examples.take(2).toList(),
      sourceDict: sourceDict,
      sourceUrl: sourceUrl,
    );
  }
}
