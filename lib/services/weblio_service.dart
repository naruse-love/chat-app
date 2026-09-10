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

  /// 查词主入口（支持递归“查到底”，解析重定向与语法活用参照）
  Future<WeblioResult> lookupWord(
    String rawWord, {
    int maxDepth = 2,
    Set<String>? visited,
  }) async {
    final word = rawWord.trim();
    if (word.isEmpty) {
      throw WeblioException('查询单词不能为空');
    }

    final currentVisited = visited != null ? Set<String>.from(visited) : <String>{};
    currentVisited.add(word);

    final encoded = Uri.encodeComponent(word);
    final url = 'https://www.weblio.jp/content/$encoded';

    WeblioResult parsed;
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );

      if (response.statusCode != 200 || response.data == null) {
        throw WeblioException('Weblio 请求失败 (HTTP ${response.statusCode})');
      }

      parsed = parseHtml(response.data!, word, url);
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

    // 递归“查到底”：若当前释义为语法活用或重定向引用，且尚未包含实质释义，则追踪目标根词
    if (maxDepth > 0 && isRedirectDefinition(parsed.definition)) {
      final candidates = extractRedirectCandidates(parsed.definition, word);
      for (final candidate in candidates) {
        if (currentVisited.contains(candidate)) continue;
        try {
          final targetResult = await lookupWord(
            candidate,
            maxDepth: maxDepth - 1,
            visited: currentVisited,
          );
          if (hasSubstantiveDefinition(targetResult.definition)) {
            return mergeRedirectResult(
              original: parsed,
              target: targetResult,
            );
          }
        } catch (_) {
          // 目标候选词查询失败时尝试下一个候选词
        }
      }
    }

    return parsed;
  }

  /// 判断释义文本是否包含实质性的词义解释（非纯重定向或空文本）
  static bool hasSubstantiveDefinition(String def) {
    final text = def.trim();
    if (text.isEmpty) return false;

    // 若整段内容直接被判断为纯重定向，则不包含实质释义
    if (isRedirectDefinition(text)) {
      return false;
    }

    // 检查各分行：若存在非重定向的实质释义行且具有足够语义长度
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (final line in lines) {
      final s = line
          .replaceFirst(RegExp(r'^[［\[][^］\]]+[］\]]\s*'), '')
          .replaceFirst(RegExp(r'^[1-9１-９①-⑩\.\s]+'), '')
          .trim();
      if (s.length >= 4 && !_isSingleLineRedirect(s)) {
        return true;
      }
    }

    return text.length >= 10 && !isRedirectDefinition(text);
  }

  /// 判断释义文本是否为重定向或语法活用说明（如「...の上一段化」「...に同じ」）
  static bool isRedirectDefinition(String def) {
    final text = def.trim();
    if (text.isEmpty) return false;

    // 若包含编号的多义项（如 １ ２），且至少有一个义项包含实质释义（非重定向），则整体不属于纯重定向
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final substantiveLines = lines.where((line) {
      final s = line
          .replaceFirst(RegExp(r'^[［\[][^］\]]+[］\]]\s*'), '')
          .replaceFirst(RegExp(r'^[1-9１-９①-⑩\.\s]+'), '')
          .trim();
      return s.length >= 4 && !_isSingleLineRedirect(s);
    }).toList();

    if (substantiveLines.isNotEmpty && lines.any((l) => RegExp(r'^[1-9１-９①-⑩]').hasMatch(l))) {
      return false;
    }

    // 剥离外层可能存在的编号或词性标注后单行检查
    final stripped = text
        .replaceFirst(RegExp(r'^[［\[][^］\]]+[］\]]\s*'), '')
        .replaceFirst(RegExp(r'^[1-9１-９①-⑩\.\s]+'), '')
        .trim();

    return _isSingleLineRedirect(stripped);
  }

  /// 检查单行文本是否属于纯重定向引用
  static bool _isSingleLineRedirect(String s) {
    final text = s.trim();
    if (text.isEmpty) return false;

    // 屈折活用与词尾重定向（如 Weblio 的 "終止形\nxxx » 「xxx」の意味を調べる"）
    if (text.contains('の意味を調べる') ||
        text.contains('終止形') ||
        text.contains('基本形') ||
        text.contains('原形')) {
      return true;
    }

    // 箭头引用：如 ⇒ 講ずる、→「講ずる」
    if (RegExp(r'^[1-9１-９①-⑩\.\s]*[⇒→➡]').hasMatch(text)) {
      return true;
    }

    // 语法活用与重定向模式（涵盖带引号与不带引号）
    final redirectPattern = RegExp(
      r'(?:[「『]([^」』]+)[」』]|([^\s\n\r。、「『]{2,15}))\s*(?:（[^）]+）)?\s*(?:（[^）]+）\s*)?の?\s*(?:上一段化|下一段化|五段化|サ変(?:化)?|カ変(?:化)?|上一段活用|下一段活用|五段活用|サ変活用|カ変活用|連用形|未然形|已然形|仮定形|命令形|連体形|受身(?:形)?|使役(?:形)?|可能(?:形|動詞)?|口語(?:形)?|文語(?:形)?|音変化|音便|転(?:訛)?|異表記|別表記|別名|略(?:称|語)?|に同じ|(?:の?項|の?項目)?(?:を見よ|を参照)|を参照|のこと)',
    );

    if (redirectPattern.hasMatch(text)) {
      final m = redirectPattern.firstMatch(text)!;
      final matchedLen = m.group(0)!.length;
      // 若匹配到的重定向片段占了主要篇幅，或者总长度不超过50字符
      if (matchedLen >= text.length * 0.4 || text.length <= 50) {
        return true;
      }
    }

    return false;
  }

  /// 从重定向释义中提取目标候选词列表（优先汉字形，其次假名形）
  static List<String> extractRedirectCandidates(String def, [String? currentWord]) {
    final candidates = <String>[];

    // 1. » 「...」の意味を調べる
    final checkMeaningMatches = RegExp(r'»\s*[「『]([^」』]+)[」』]の意味を調べる').allMatches(def);
    for (final m in checkMeaningMatches) {
      _addCandidatesFromRaw(m.group(1)!, candidates, currentWord);
    }

    // 2. 終止形/基本形/原形\n<word> »
    final shushikeiMatches = RegExp(r'(?:終止形|基本形|原形)\s*[\n\r]+\s*([^\s»]+)\s*»').allMatches(def);
    for (final m in shushikeiMatches) {
      _addCandidatesFromRaw(m.group(1)!, candidates, currentWord);
    }

    // 3. 箭头引用：如 ⇒ 講ずる、⇒「こうずる【講ずる】」、→ 講ずる
    final arrowMatches = RegExp(r'[⇒→➡]\s*[「『]?([^\s」』\n\r]+)[」』]?').allMatches(def);
    for (final m in arrowMatches) {
      _addCandidatesFromRaw(m.group(1)!, candidates, currentWord);
    }

    // 4. 引号语法活用与重定向模式（如「こう（講）ずる」（サ変）の上一段化、「講ずる」に同じ）
    final bracketMatches = RegExp(
      r'[「『]([^」』]+)[」』]\s*(?:（[^）]+）)?\s*(?:（[^）]+）\s*)?の?\s*(?:上一段化|下一段化|五段化|サ変(?:化)?|カ変(?:化)?|上一段活用|下一段活用|五段活用|サ変活用|カ変活用|連用形|未然形|已然形|仮定形|命令形|連体形|受身(?:形)?|使役(?:形)?|可能(?:形|動詞)?|口語(?:形)?|文語(?:形)?|音変化|音便|転(?:訛)?|異表記|別表記|別名|略(?:称|語)?|に同じ|(?:の?項|の?項目)?(?:を見よ|を参照)|を参照|のこと)',
    ).allMatches(def);
    for (final m in bracketMatches) {
      _addCandidatesFromRaw(m.group(1)!, candidates, currentWord);
    }

    // 5. 简式「xxx」に同じ
    final niOnajiMatches = RegExp(r'[「『]([^」』]+)[」』]\s*(?:（[^）]+）)?\s*に同じ').allMatches(def);
    for (final m in niOnajiMatches) {
      _addCandidatesFromRaw(m.group(1)!, candidates, currentWord);
    }

    // 6. 无引号重定向模式：如 講ずるの上一段活用、講ずるに同じ
    final unbracketedMatches = RegExp(
      r'(?:^|\n|[\s。、])([^\s\n\r。、「『（\(]{2,15}?)\s*(?:（[^）]+）)?\s*の?\s*(?:上一段化|下一段化|五段化|サ変(?:化)?|カ変(?:化)?|上一段活用|下一段活用|五段活用|サ変活用|カ変活用|に同じ|(?:の?項|の?項目)?(?:を見よ|を参照))',
    ).allMatches(def);
    for (final m in unbracketedMatches) {
      _addCandidatesFromRaw(m.group(1)!, candidates, currentWord);
    }

    return candidates;
  }

  static void _addCandidatesFromRaw(String raw, List<String> list, String? currentWord) {
    // 剥离词性标注括号（如 ［動サ変］ 或 [名]）
    var text = raw.replaceAll(RegExp(r'\[[^\]]*\]|［[^］]*］'), '').trim();
    if (text.isEmpty) return;

    // 若包含斜杠或顿号多词分隔，先拆分递归添加
    if (text.contains('/') || text.contains('／') || text.contains('、')) {
      final parts = text.split(RegExp(r'[/／、]'));
      for (final part in parts) {
        _addCandidatesFromRaw(part, list, currentWord);
      }
      return;
    }

    // 处理包含【...】或〔...〕的词典规范词头：如 こう・ずる【講ずる】
    final bracketHeadwordMatch = RegExp(r'^(.*?)【([^】]+)】').firstMatch(text);
    if (bracketHeadwordMatch != null) {
      final kanaPart = bracketHeadwordMatch.group(1)!.trim();
      final kanjiPart = bracketHeadwordMatch.group(2)!.trim();
      _addCandidate(kanjiPart, list, currentWord);
      if (kanaPart.isNotEmpty) {
        _addCandidate(kanaPart.replaceAll('・', ''), list, currentWord);
      }
      return;
    }

    // 处理假名括号汉字（如 こう（講）ずる）或汉字括号假名（如 講ずる（こうずる）、打（う）ち明（あ）ける）
    if (text.contains('(') || text.contains('（')) {
      final innerMatches = RegExp(r'[\(（]([^\)）]+)[\)）]').allMatches(text);
      bool innerHasKanji = false;
      bool innerHasKana = false;
      for (final m in innerMatches) {
        final inner = m.group(1)!;
        if (RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(inner)) {
          innerHasKanji = true;
        }
        if (RegExp(r'[\u3040-\u309f\u30a0-\u30ff]').hasMatch(inner)) {
          innerHasKana = true;
        }
      }

      if (innerHasKanji) {
        // 模式 A: kana（kanji）kana，如 こう（講）ずる
        final kanjiForm = text.replaceAllMapped(
          RegExp(r'([^\(（\s]+)[\(（]([^\)）]+)[\)）]'),
          (m) => m.group(2)!,
        ).replaceAll('・', '');
        final kanaForm = text.replaceAll(RegExp(r'[\(（][^\)）]+[\)）]'), '').replaceAll('・', '');
        _addCandidate(kanjiForm, list, currentWord);
        _addCandidate(kanaForm, list, currentWord);
        return;
      } else if (innerHasKana) {
        // 模式 B: kanji（kana），如 講ずる（こうずる） 或 打（う）ち明（あ）ける
        final kanjiForm = text.replaceAll(RegExp(r'[\(（][^\)）]+[\)）]'), '').replaceAll('・', '');
        final kanaForm = text.replaceAllMapped(
          RegExp(r'([^\(（\s]+)[\(（]([^\)）]+)[\)）]'),
          (m) => m.group(2)!,
        ).replaceAll('・', '');
        _addCandidate(kanjiForm, list, currentWord);
        _addCandidate(kanaForm, list, currentWord);
        return;
      }
    }

    // 处理包含中黑点「・」的词条：
    if (text.contains('・')) {
      final parts = text.split('・').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final hasKanjiParts = parts.any((p) => RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(p));
      if (hasKanjiParts) {
        // 并列词（如 講ずる・講じる）：优先添加拆分出的各独立词
        for (final p in parts) {
          if (p.length >= 2) {
            _addCandidate(p, list, currentWord);
          }
        }
      } else {
        // 词干/送假名分隔（如 こう・ずる、た・べる）：优先整体去除「・」还原词汇
        final noDot = text.replaceAll('・', '');
        _addCandidate(noDot, list, currentWord);
      }
      return;
    }

    _addCandidate(text, list, currentWord);
  }

  static void _addCandidate(String word, List<String> list, String? currentWord) {
    var cleaned = word.trim().replaceAll(RegExp(r'[\s\[\]［］\(\)（）]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'の$'), '').trim();
    if (cleaned.isEmpty || cleaned == currentWord || list.contains(cleaned)) {
      return;
    }
    if (cleaned == '動' || cleaned == '名' || cleaned == '形' || cleaned == 'サ変') {
      return;
    }
    list.add(cleaned);
  }

  /// 合并原始词信息与目标根词释义
  static WeblioResult mergeRedirectResult({
    required WeblioResult original,
    required WeblioResult target,
  }) {
    final word = original.word;
    final reading = (original.reading.isNotEmpty && original.reading != original.word)
        ? original.reading
        : (target.reading.isNotEmpty ? target.reading : original.reading);
    final pos = original.partOfSpeech.isNotEmpty ? original.partOfSpeech : target.partOfSpeech;

    // 合并释义：保留语法说明原文，并追加目标词的实质释义（去重防止重复追加）
    final String combinedDef;
    if (original.definition.contains(target.definition)) {
      combinedDef = original.definition;
    } else {
      combinedDef = '${original.definition}\n${target.definition}'.trim();
    }

    // 合并例句：优先保留原词自带的例句，不足2条时补充目标词例句
    final mergedExamples = <WeblioExample>[...original.examples];
    for (final ex in target.examples) {
      if (mergedExamples.length >= 2) break;
      if (!mergedExamples.any((e) => e.kanji == ex.kanji)) {
        mergedExamples.add(ex);
      }
    }

    return WeblioResult(
      word: word,
      reading: reading,
      definition: combinedDef,
      partOfSpeech: pos,
      examples: mergedExamples,
      sourceDict: original.sourceDict,
      sourceUrl: original.sourceUrl,
    );
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
      final sgkdjResult = _parseSgkdj(doc, word, effectiveUrl);
      if (sgkdjResult != null) {
        return sgkdjResult;
      }
    }

    // 2. 降级回退：首个可用词典条目 (.kiji)
    final firstKiji = doc.querySelector('.kiji');
    if (firstKiji != null) {
      return _parseFallbackKiji(doc, firstKiji, word, effectiveUrl);
    }

    throw WeblioException('未在 Weblio 找到「$word」的词典释义');
  }

  /// 将日文例句中的汉字读音（如「生(なま)で」或「ご飯(はん)を美味(おい)しく」）转换为 Anki 兼容的 ruby 格式
  /// 如：生[なま]で、ご 飯[はん]を 美味[おい]しく
  static String formatFurigana(String text) {
    return text.replaceAllMapped(
      RegExp(r'([^\s\u4e00-\u9faf\u3400-\u4dbfヶ々]|^)([\u4e00-\u9faf\u3400-\u4dbfヶ々]+)[\(（]([^\)）]+)[\)）]'),
      (match) {
        final prefix = match.group(1) ?? '';
        final kanji = match.group(2)!;
        final reading = match.group(3)!.trim();
        final space = prefix.isNotEmpty ? ' ' : '';
        return '$prefix$space$kanji[$reading]';
      },
    ).trim();
  }

  /// 去除例句文本中的假名注音括号，生成纯汉字/假名原文
  static String stripFurigana(String text) {
    return text.replaceAll(RegExp(r'[\(（][^\)）]+[\)）]'), '').trim();
  }

  /// 解析小学馆《デジタル大辞泉》
  WeblioResult? _parseSgkdj(dom.Document doc, String word, String sourceUrl) {
    dom.Element? sgkdjDiv = doc.querySelector('.Sgkdj');

    // 若未直接匹配到 .Sgkdj，尝试从 <a name="SGKDJ"> 后续兄弟节点查找
    if (sgkdjDiv == null) {
      final anchor = doc.querySelector('a[name="SGKDJ"]');
      if (anchor != null) {
        var next = anchor.nextElementSibling;
        while (next != null) {
          if (next.classes.contains('kiji')) {
            sgkdjDiv = next.querySelector('.Sgkdj') ?? next;
            break;
          }
          final nested = next.querySelector('.kiji');
          if (nested != null) {
            sgkdjDiv = nested.querySelector('.Sgkdj') ?? nested;
            break;
          }
          next = next.nextElementSibling;
        }
      }
    }

    // 优先在 SGKDJ 所在的 kiji 容器内定位 midashigo，避免被排在前面的词典（如维基百科）污染
    dom.Element? kijiParent = sgkdjDiv;
    while (kijiParent != null && !kijiParent.classes.contains('kiji')) {
      kijiParent = kijiParent.parent;
    }
    final midashigoH2 = kijiParent?.querySelector('.midashigo') ?? doc.querySelector('.midashigo');
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
        if (RegExp(r'^［[^］]+］$').hasMatch(text) &&
            !RegExp(r'[0-9０-９１２３４５６７８９]').hasMatch(text)) {
          continue;
        }

        // 提取例句 「...」
        final exMatches = RegExp(r'「([^」]+)」').allMatches(text);
        final matchedExBrackets = <String>[];
        for (final m in exMatches) {
          final raw = m.group(1)!.trim();
          if (raw.length < 2) continue;

          // 仅处理包含连接符/波浪线或包含单词本体的有效例句，避免将「食う」等释义引用的同义/对义词误判为当前单词的例句
          if (raw.contains(RegExp(r'[―—～〜]')) ||
              (raw.contains(word) && raw.length > word.length)) {
            matchedExBrackets.add(m.group(0)!);

            // 「―・」替换为词干，「―/—/～/〜」替换为完整词头或词干
            var restored = raw.replaceAll(RegExp(r'[―—～〜]・'), stem);

            // 若破折号后直接紧随送假名（如「―じる」对应「講じる」），替换为词干 stem 防止「講じるじる」
            restored = restored.replaceAllMapped(
              RegExp(r'[―—～〜]([\u3040-\u309f]+)'),
              (m) {
                final okuri = m.group(1)!;
                if (word.endsWith(okuri)) {
                  return '$stem$okuri';
                }
                return '$word$okuri';
              },
            );

            // 其余独立破折号替换为完整词头（如「朝夕―」->「朝夕食べる」）
            restored = restored.replaceAll(RegExp(r'[―—～〜]'), word);

            final kanji = stripFurigana(restored);
            final furigana = formatFurigana(restored);

            if (kanji.isNotEmpty && !examples.any((e) => e.kanji == kanji)) {
              examples.add(WeblioExample(kanji: kanji, furigana: furigana));
            }
          }
        }

        // 清洗释义文本：仅剥离已识别出的例句括号，保留词义引用说明（如「食う」）
        var cleanDef = text;
        for (final exBracket in matchedExBrackets) {
          cleanDef = cleanDef.replaceAll(exBracket, '');
        }
        cleanDef = cleanDef.replaceAll(RegExp(r'〈[^〉]*〉'), '').trim();

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
    if (definition.isEmpty) {
      return null;
    }

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
    // 1. 尝试从前置同级或父级查找匹配该词条的 .pbarT 获取真实词典名
    String sourceDict = 'Weblio辞書';
    dom.Element? pbarT;
    var curr = kiji.parent;
    while (curr != null && pbarT == null) {
      var prev = curr.previousElementSibling;
      while (prev != null) {
        if (prev.classes.contains('pbarT')) {
          pbarT = prev;
          break;
        }
        final nested = prev.querySelector('.pbarT');
        if (nested != null) {
          pbarT = nested;
          break;
        }
        prev = prev.previousElementSibling;
      }
      curr = curr.parent;
    }
    pbarT ??= doc.querySelector('.pbarT');
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
    } else {
      final posMatch = RegExp(r'［([^］]+)］').firstMatch(kiji.text);
      if (posMatch != null) {
        pos = posMatch.group(1)!.trim();
      }
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
