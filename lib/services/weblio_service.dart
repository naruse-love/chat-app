import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../models/word_candidate.dart';

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
  final String pitch;
  final String foreignOrigin;
  final List<WeblioExample> examples;
  final String sourceDict;
  final String sourceUrl;

  const WeblioResult({
    required this.word,
    required this.reading,
    required this.definition,
    required this.partOfSpeech,
    this.pitch = '',
    this.foreignOrigin = '',
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

  /// 查询 Weblio 并抓取所有同音/同形词条候选列表（用于假名多汉字消歧）
  Future<List<WordCandidate>> fetchCandidates(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return [];

    final encoded = Uri.encodeComponent(query);
    final url = 'https://www.weblio.jp/content/$encoded';

    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode == 200 && response.data != null) {
        return extractCandidatesFromHtml(response.data!, query);
      }
    } catch (_) {
      // 网络异常或无匹配时优雅返回空列表
    }
    return [];
  }

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

  /// 判断释义或词典来源是否属于人名、专有名词或作品名（用于识别与自愈被污染的生词缓存）
  static bool isPersonOrProperNameDefinition(String def, [String? sourceDict]) {
    final text = def.trim();
    final dict = (sourceDict ?? '').trim();

    // 1. 词典来源为纯人名、固有名词或维基百科
    final isNameDict = dict.contains('人名') ||
        dict.contains('欧米人名') ||
        dict.contains('日本人名') ||
        dict.contains('外国人名') ||
        dict.contains('人物') ||
        dict.contains('著名人') ||
        dict.contains('固有名詞') ||
        dict.contains('作品名') ||
        dict.contains('ウィキペディア') ||
        dict.contains('Wikipedia') ||
        dict.contains('実名');
    if (isNameDict) return true;

    // 2. 释义内容显式为人名、角色名或维基条目
    if (text.contains('人名としての') ||
        text.contains('欧米の男性名') ||
        text.contains('ヨーロッパ系の男性名') ||
        text.contains('ヨーロッパの人名') ||
        text.contains('架空のキャラクター名') ||
        text.contains('架空の人物') ||
        (text.contains('男性名') && text.length <= 80) ||
        (text.contains('女性名') && text.length <= 80) ||
        (text.contains('姓および名') && text.length <= 80) ||
        (text.contains('フリー百科事典') && text.contains('ウィキペディア'))) {
      return true;
    }

    return false;
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
    final word = target.word.isNotEmpty ? target.word : original.word;
    final reading =
        target.reading.isNotEmpty ? target.reading : original.reading;
    final pos = original.partOfSpeech.isNotEmpty ? original.partOfSpeech : target.partOfSpeech;
    final pitch = original.pitch.isNotEmpty ? original.pitch : target.pitch;
    final foreignOrigin = original.foreignOrigin.isNotEmpty
        ? original.foreignOrigin
        : target.foreignOrigin;

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
      pitch: pitch,
      foreignOrigin: foreignOrigin,
      examples: mergedExamples,
      sourceDict: original.sourceDict,
      sourceUrl: original.sourceUrl,
    );
  }

  /// 从 Weblio HTML 中提取所有候选词项（用于假名多汉字/外来语多义项消歧）
  static List<WordCandidate> extractCandidatesFromHtml(String html, String query) {
    final doc = html_parser.parse(html);
    final candidates = <WordCandidate>[];
    final seenKeys = <String>{};

    // 检查是否有未收录提示
    final bodyText = doc.body?.text ?? '';
    if (bodyText.contains('一致する見出し語は見つかりませんでした') ||
        bodyText.contains('に一致する項目は見つかりませんでした')) {
      return candidates;
    }

    final kijiElements = doc.querySelectorAll('.kiji');
    for (final kiji in kijiElements) {
      final midashigoElem = kiji.querySelector('.midashigo');
      final midashigoText = midashigoElem?.text.trim() ?? '';
      if (midashigoText.isEmpty) continue;

      // 收集该 .kiji 下的所有实质释义段落 (过滤元数据行)
      final senseParagraphs = <String>[];
      for (final p in kiji.querySelectorAll('p')) {
        final text = p.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (text.isEmpty ||
            text.startsWith('読み方：') ||
            text.startsWith('[補説]') ||
            text.startsWith('[派生]') ||
            text.startsWith('[用法]') ||
            text.startsWith('出典:')) {
          continue;
        }
        var clean = text
            .replaceAll(RegExp(r'［[^］]+］'), '')
            .replaceAll(RegExp(r'「[^」]+」'), '')
            .replaceAll(RegExp(r'《[^》]+》'), '')
            .replaceAll(RegExp(r'【[^】]+】'), '')
            .replaceAll(RegExp(r'〔[^〕]+〕'), '')
            .trim();
        clean = clean.replaceFirst(RegExp(r'^[1-9１-９①-⑩\.\s]+'), '').trim();

        if (clean.isEmpty) continue;

        if (text.contains('［文］') ||
            text.contains('［古］') ||
            clean.startsWith('《') ||
            clean.startsWith('【') ||
            clean.startsWith('〔')) {
          continue;
        }

        if (clean.length > 50) {
          clean = '${clean.substring(0, 50)}...';
        }
        senseParagraphs.add(clean);
      }

      // 若段落内合并了 １ ２ 编号的多义项，进行分拆
      final expandedSenses = <String>[];
      for (final sp in senseParagraphs) {
        final numSplit = sp.split(RegExp(r'\s+[1-9１-９①-⑩][\.\s、\)）]'));
        if (numSplit.length > 1) {
          for (final seg in numSplit) {
            final s = seg.trim();
            if (s.isNotEmpty) {
              expandedSenses.add(s.length > 50 ? '${s.substring(0, 50)}...' : s);
            }
          }
        } else {
          expandedSenses.add(sp);
        }
      }

      // 提取假名读音与各候选条目
      String reading = '';
      final candidateEntries = <({String kanji, String reading, String? disambig, String def})>[];

      final bracketMatch = RegExp(r'^(.*?)【([^】]+)】').firstMatch(midashigoText);
      if (bracketMatch != null) {
        final kanaPart = bracketMatch
            .group(1)!
            .replaceAll('・', '')
            .replaceAll(RegExp(r'〔[^〕]*〕'), '')
            .trim();
        reading = kanaPart.isNotEmpty ? kanaPart : query;
        final kanjiRaw = bracketMatch.group(2)!.trim();
        final splitKanji = kanjiRaw
            .split(RegExp(r'[/／、・\s]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        for (int i = 0; i < splitKanji.length; i++) {
          final p = splitKanji[i];
          final hasKanji = RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(p);
          final defForEntry = (i < expandedSenses.length)
              ? expandedSenses[i]
              : (expandedSenses.isNotEmpty ? expandedSenses.first : '');

          if (hasKanji) {
            candidateEntries.add((
              kanji: p,
              reading: reading,
              disambig: p,
              def: defForEntry,
            ));
          } else {
            // 外来语 / 片假名词条的拉丁词源注记（如 アクセル【accel】、アクセル【axel】）
            candidateEntries.add((
              kanji: '$reading ($p)',
              reading: reading,
              disambig: reading,
              def: defForEntry,
            ));
          }
        }
      } else {
        final cleanMidashigo = midashigoText.replaceAll('・', '').trim();
        reading = query;
        // 检查所属词典是否为人名/专有名词词典，以便加上区分标注
        final dictName = _getDictNameForKiji(doc, kiji);
        final isNameOrSpecific = dictName.contains('人名') ||
            dictName.contains('固有名詞') ||
            dictName.contains('Wikipedia') ||
            dictName.contains('ウィキペディア') ||
            kiji.text.contains('人名としての') ||
            kiji.text.contains('男性名');

        if (isNameOrSpecific) {
          final defForEntry = expandedSenses.isNotEmpty ? expandedSenses.first : '';
          candidateEntries.add((
            kanji: '$cleanMidashigo (人名)',
            reading: reading,
            disambig: cleanMidashigo,
            def: defForEntry,
          ));
        } else if (expandedSenses.length > 1) {
          // 同一词典条目内包含多个不同核心义项（例如 １ 汽车加速踏板 ２ 花滑阿克塞尔跳）
          for (int i = 0; i < expandedSenses.length && i < 4; i++) {
            final senseDef = expandedSenses[i];
            String label = '$cleanMidashigo (${i + 1})';
            if (senseDef.contains('加速') || senseDef.contains('自動車')) {
              label = '$cleanMidashigo (加速装置)';
            } else if (senseDef.contains('スケート') || senseDef.contains('ジャンプ')) {
              label = '$cleanMidashigo (フィギュアスケート)';
            }
            candidateEntries.add((
              kanji: label,
              reading: reading,
              disambig: cleanMidashigo,
              def: senseDef,
            ));
          }
        } else {
          final defForEntry = expandedSenses.isNotEmpty ? expandedSenses.first : '';
          candidateEntries.add((
            kanji: cleanMidashigo,
            reading: reading,
            disambig: cleanMidashigo,
            def: defForEntry,
          ));
        }
      }

      if (reading.isEmpty) {
        reading = query;
      }

      // 提取词性
      String pos = '';
      final hinshiElem = kiji.querySelector('.hinshi');
      if (hinshiElem != null) {
        pos = hinshiElem.text.trim().replaceAll(RegExp(r'[\s]'), '');
      } else {
        final posMatch = RegExp(r'［([^］]+)］').firstMatch(kiji.text);
        if (posMatch != null) {
          pos = '［${posMatch.group(1)!.trim()}］';
        }
      }

      for (final entry in candidateEntries) {
        final cleanKanji = entry.kanji.replaceAll(RegExp(r'[\s\[\]［］]'), '');
        if (cleanKanji.isEmpty) continue;
        final defText = entry.def;
        final dedupeKey =
            '${cleanKanji}_${defText.length > 15 ? defText.substring(0, 15) : defText}';
        if (seenKeys.contains(dedupeKey)) continue;
        seenKeys.add(dedupeKey);

        candidates.add(
          WordCandidate(
            kanji: cleanKanji,
            reading: entry.reading,
            definition: defText,
            partOfSpeech: pos,
            source: CandidateSource.weblio,
            disambiguationWord: entry.disambig,
          ),
        );
      }
    }

    return candidates;
  }

  /// 纯 HTML 解析逻辑（支持无网络单元测试）
  /// 优先小学馆《デジタル大辞泉》，多词典冲突时根据权威度评分降级人名/固有名词
  WeblioResult parseHtml(String html, String word, [String? sourceUrl]) {
    final doc = html_parser.parse(html);
    final effectiveUrl = sourceUrl ??
        'https://www.weblio.jp/content/${Uri.encodeComponent(word)}';

    // 检查是否有未收录提示
    final bodyText = doc.body?.text ?? '';
    if (bodyText.contains('一致する見出し語は見つかりませんでした') ||
        bodyText.contains('に一致する項目は見つかりませんでした')) {
      throw WeblioException('未在 Weblio 找到「$word」的相关释义');
    }

    // 1. 优先定位小学馆《デジタル大辞泉》(SGKDJ)
    final sgkdjResult = _parseSgkdj(doc, word, effectiveUrl);
    if (sgkdjResult != null) {
      return sgkdjResult;
    }

    // 2. 降级回退：智能评估所有可用词典条目 (.kiji)，严格优先权威一般语言词典，降级人名/固有名词
    final bestResult = _parseBestKiji(doc, word, effectiveUrl);
    if (bestResult != null) {
      return bestResult;
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

  static const Map<String, String> _pitchCircleMap = {
    '0': '⓪', '1': '①', '2': '②', '3': '③', '4': '④',
    '5': '⑤', '6': '⑥', '7': '⑦', '8': '⑧', '9': '⑨',
    '10': '⑩',
    '０': '⓪', '１': '①', '２': '②', '３': '③', '４': '④',
    '５': '⑤', '６': '⑥', '７': '⑦', '８': '⑧', '９': '⑨',
    '１０': '⑩',
  };

  /// 将原生数字音调（如 0、1、2、〔0〕）转换为标准圆圈数字（⓪、①、② 等）
  static String formatPitchCircle(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (_pitchCircleMap.containsKey(trimmed)) {
      return _pitchCircleMap[trimmed]!;
    }
    if (RegExp(r'^[⓪①②③④⑤⑥⑦⑧⑨⑩]$').hasMatch(trimmed)) {
      return trimmed;
    }
    final numMatch = RegExp(r'[0-9０-９]+').firstMatch(trimmed);
    if (numMatch != null) {
      final n = numMatch.group(0)!;
      return _pitchCircleMap[n] ?? '⓪';
    }
    return '';
  }

  /// 清洗平假名/片假名读音中的连字符与词素分界符（如「いと‐も」->「いとも」）
  /// 保留片假名长音符号「ー」(U+30FC)
  static String cleanReading(String rawReading) {
    var r = rawReading.trim();
    if (r.isEmpty) return r;
    r = r.replaceAll(RegExp(r'〔[^〕]*〕'), '');
    r = r.replaceAll(RegExp(r'[\[［][0-9０-９]+(?:[・,、/][0-9０-９]+)*[\]］]'), '');
    r = r.replaceAll(RegExp(r'[\(（][0-9０-９]+(?:[・,、/][0-9０-９]+)*[\)）]'), '');
    r = r.replaceAll(RegExp(r'[\u2010-\u2015\uFF0D\-]'), '');
    r = r.replaceAll(RegExp(r'[\u30FB\uFF65\u00B7\u2022]'), '');
    return r.trim();
  }

  /// 判断词条是否为纯片假名外来语
  static bool isKatakana(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[\u30A0-\u30FF\u30FC\u30FB\s]+$').hasMatch(trimmed);
  }

  /// 从词典条目或释义中提取外来语英文/原语原词（如 ［英語: thrill］ -> thrill, 【thrill】 -> thrill）
  static String extractForeignOriginWord(String text) {
    if (text.isEmpty) return '';

    // 1. 【thrill】 / ［thrill］ / [thrill] / 《thrill》
    final bracketEnMatch = RegExp(r"[【［\[《]([a-zA-Z\s\-'\.]+)[】］\]》]").firstMatch(text);
    if (bracketEnMatch != null) {
      final w = bracketEnMatch.group(1)!.trim();
      if (w.isNotEmpty && w.length >= 2) return w;
    }

    // 2. ［英語: thrill］ / [英語: thrill] / ［英: thrill］ / 【英語: thrill】 / ［(英) thrill］ / [(英) thrill]
    final langMatch = RegExp(
      r"[［\[（(〔【]*\s*(?:英語|英|米|フランス語|仏|ドイツ語|独|オランダ語|蘭|イタリア語|伊|ラテン語|拉)[］\]）)〕】]*[:：\s]+([a-zA-Z\s\-'\.]+?)(?:[;/／，,\s］\]）)〕】]|$)",
      caseSensitive: false,
    ).firstMatch(text);
    if (langMatch != null) {
      final w = langMatch.group(1)!.trim();
      if (w.isNotEmpty && w.length >= 2) return w;
    }

    // 3. （英）thrill / [英] thrill / (英) thrill
    final shortLangMatch = RegExp(
      r"[［\[（(](?:英語|英|米)[］\]）)]\s*([a-zA-Z\s\-'\.]{2,40})",
      caseSensitive: false,
    ).firstMatch(text);
    if (shortLangMatch != null) {
      final w = shortLangMatch.group(1)!.trim();
      if (w.isNotEmpty) return w;
    }

    // 4. 片假名后直接跟圆括号英文：(thrill) / （thrill）
    final parenEnMatch = RegExp(r"[（\(]([a-zA-Z\s\-'\.]{2,40})[）\)]").firstMatch(text);
    if (parenEnMatch != null) {
      final w = parenEnMatch.group(1)!.trim();
      if (w.isNotEmpty) return w;
    }

    return '';
  }

  /// 在例句振假名文本中，将目标生词关键词包裹在 <b>...</b> 中高亮显示
  static String highlightKeywordInFurigana(String sentence, String keyword) {
    final sent = sentence.trim();
    final word = keyword.trim();
    if (sent.isEmpty || word.isEmpty) return sent;
    if (sent.contains('<b>') || sent.contains('<strong>')) return sent;

    // 1. 纯假名或词条直接精准匹配（且确保不在 ruby 方括号 [...] 内部，且后方不是 [ 注音）
    final exactPattern = RegExp(RegExp.escape(word));
    for (final m in exactPattern.allMatches(sent)) {
      final beforeMatch = sent.substring(0, m.start);
      final openCount = '['.allMatches(beforeMatch).length;
      final closeCount = ']'.allMatches(beforeMatch).length;
      if (openCount == closeCount && !sent.substring(m.end).startsWith('[')) {
        // 若词首为汉字，前驱不能紧贴汉字（防止如 "行く" 误匹配 compound 中的 "銀行"）
        if (m.start > 0 && RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(word[0])) {
          final prevChar = sent[m.start - 1];
          if (RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(prevChar)) {
            continue;
          }
        }
        return '${sent.substring(0, m.start)}<b>$word</b>${sent.substring(m.end)}';
      }
    }

    // 2. 带振假名注音的汉字生词匹配（如 講[こう]じる 或 青空[あおぞら]）
    final buffer = StringBuffer();
    for (int i = 0; i < word.length; i++) {
      final char = word[i];
      final isKanji = RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(char);
      if (isKanji) {
        buffer.write(RegExp.escape(char));
        buffer.write(r'(?:\s*\[[^\]]+\])?\s*');
      } else {
        buffer.write(RegExp.escape(char));
        buffer.write(r'\s*');
      }
    }
    final rubyPattern = RegExp(buffer.toString().trim());
    for (final rubyMatch in rubyPattern.allMatches(sent)) {
      final start = rubyMatch.start;
      final beforeMatch = sent.substring(0, start);
      final openCount = '['.allMatches(beforeMatch).length;
      final closeCount = ']'.allMatches(beforeMatch).length;
      if (openCount != closeCount) continue;

      if (start > 0) {
        final prevChar = sent[start - 1];
        if (RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(prevChar)) {
          continue;
        }
      }
      final matchedText = rubyMatch.group(0)!;
      if (matchedText.isNotEmpty) {
        return '${sent.substring(0, start)}<b>$matchedText</b>${sent.substring(rubyMatch.end)}';
      }
    }

    // 3. 活用动词/形容词词干匹配（如 食べた / 食べて 匹配 食べる；行きました 匹配 行く；たべた 匹配 たべる）
    String stem = word.replaceAll(RegExp(r'[\u3040-\u309f]+$'), '');
    if (stem.isEmpty && word.length > 1) {
      stem = word.substring(0, word.length - 1);
    }
    if (stem.isNotEmpty) {
      final stemBuffer = StringBuffer();
      for (int i = 0; i < stem.length; i++) {
        final char = stem[i];
        final isKanji = RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(char);
        if (isKanji) {
          stemBuffer.write(RegExp.escape(char));
          stemBuffer.write(r'(?:\s*\[[^\]]+\])?\s*');
        } else {
          stemBuffer.write(RegExp.escape(char));
          stemBuffer.write(r'\s*');
        }
      }
      final inflectionPattern = RegExp('${stemBuffer.toString().trim()}[\\u3040-\\u309f]{0,4}');
      for (final infMatch in inflectionPattern.allMatches(sent)) {
        if (infMatch.group(0)!.isEmpty) continue;
        final start = infMatch.start;
        final beforeMatch = sent.substring(0, start);
        final openCount = '['.allMatches(beforeMatch).length;
        final closeCount = ']'.allMatches(beforeMatch).length;
        if (openCount != closeCount) continue;

        if (start > 0) {
          final prevChar = sent[start - 1];
          if (RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(prevChar)) {
            continue; // 前方是汉字，跳过复合词
          }
          if (prevChar == ']') {
            final lastOpen = beforeMatch.lastIndexOf('[');
            if (lastOpen > 0 && RegExp(r'[\u4e00-\u9faf\u3400-\u4dbfヶ々]').hasMatch(beforeMatch[lastOpen - 1])) {
              continue; // 是前置汉字的注音，属于复合词，跳过
            }
          }
        }

        final matchedText = infMatch.group(0)!;
        return '${sent.substring(0, start)}<b>$matchedText</b>${sent.substring(infMatch.end)}';
      }
    }

    return sent;
  }

  /// 解析小学馆《デジタル大辞泉》
  WeblioResult? _parseSgkdj(dom.Document doc, String word, String sourceUrl) {
    dom.Element? sgkdjDiv = doc.querySelector('.Sgkdj');

    // 1. 若未直接匹配到 .Sgkdj，尝试从 name 包含 SGKDJ 的锚点查找
    if (sgkdjDiv == null) {
      final anchors = doc.querySelectorAll('a');
      for (final a in anchors) {
        final name = a.attributes['name'] ?? '';
        if (name.toUpperCase().contains('SGKDJ')) {
          var next = a.nextElementSibling;
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
          if (sgkdjDiv != null) break;
        }
      }
    }

    // 2. 尝试从包含「大辞泉」或「小学館」的 .pbarT 标题查找
    if (sgkdjDiv == null) {
      final pbars = doc.querySelectorAll('.pbarT');
      for (final pb in pbars) {
        final pbText = pb.text;
        if (pbText.contains('大辞泉') || pbText.contains('小学館')) {
          var next = pb.nextElementSibling;
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
          if (sgkdjDiv != null) break;
        }
      }
    }

    // 3. 尝试从包含「大辞泉」或「小学館」的 .kiji 或 .crossl 查找
    if (sgkdjDiv == null) {
      for (final kiji in doc.querySelectorAll('.kiji')) {
        final crossl = kiji.querySelector('.crossl');
        final crosslText = crossl?.text.trim() ?? '';
        if (crosslText.contains('大辞泉') || crosslText.contains('小学館')) {
          sgkdjDiv = kiji.querySelector('.Sgkdj') ?? kiji;
          break;
        }
      }
    }

    if (sgkdjDiv == null) {
      return null;
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
    for (final p in sgkdjDiv.querySelectorAll('p')) {
      final t = p.text.trim();
      if (t.startsWith('読み方：')) {
        reading = t.replaceFirst('読み方：', '').trim();
        reading = reading.split(RegExp(r'[\s\[［]')).first;
        break;
      }
    }

    if (reading.isEmpty && midashigoText.isNotEmpty) {
      final kanaPart = midashigoText.split('【').first.trim();
      reading = kanaPart;
    }

    reading = cleanReading(reading);
    if (reading.isEmpty) {
      reading = word;
    }

    // 1.1 声调 (Pitch)
    String pitch = '';
    final pitchMatch = RegExp(r'[〔\[［\(（]([0-9０-９]+(?:[・,、/][0-9０-９]+)*)[〕\]］\)）]').firstMatch(midashigoText) ??
        RegExp(r'[〔\[［\(（]([0-9０-９]+(?:[・,、/][0-9０-９]+)*)[〕\]］\)）]').firstMatch(kijiParent?.text ?? sgkdjDiv.text);
    if (pitchMatch != null) {
      pitch = formatPitchCircle(pitchMatch.group(1)!);
    }

    // 1.2 外来语英文/原语原词 (Foreign Origin Word)
    String foreignOrigin = extractForeignOriginWord(midashigoText);
    if (foreignOrigin.isEmpty) {
      foreignOrigin = extractForeignOriginWord(kijiParent?.text ?? sgkdjDiv.text);
    }

    // 2. 词性 (PoS)
    String pos = '';
    final hinshiSpan = sgkdjDiv.querySelector('.hinshi');
    if (hinshiSpan != null) {
      pos = hinshiSpan.text.trim().replaceAll(RegExp(r'[\s\[\]［］]'), '');
    } else {
      final posMatch = RegExp(r'［([名副形動接続感動詞・スル自他上一下一五段四段サ変カ変]+(?:[（\(][^）\)]+[）\)])?)］')
          .firstMatch(kijiParent?.text ?? sgkdjDiv.text);
      if (posMatch != null) {
        pos = posMatch.group(1)!.trim().replaceAll(RegExp(r'[\s\[\]［］]'), '');
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

        // 仅处理包含连接符/波浪线或包含单词本体的有效例句
        if (raw.contains(RegExp(r'[―—～〜]')) ||
            (raw.contains(word) && raw.length > word.length)) {
          matchedExBrackets.add(m.group(0)!);

          // 「―・」替换为词干，「―/—/～/〜」替换为完整词头或词干
          var restored = raw.replaceAll(RegExp(r'[―—～〜]・'), stem);

          // 若破折号后直接紧随送假名，替换为词干 stem 防止重复
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

          // 其余独立破折号替换为完整词头
          restored = restored.replaceAll(RegExp(r'[―—～〜]'), word);

          final kanji = stripFurigana(restored);
          final furigana = formatFurigana(restored);

          if (kanji.isNotEmpty && !examples.any((e) => e.kanji == kanji)) {
            examples.add(WeblioExample(kanji: kanji, furigana: furigana));
          }
        }
      }

      // 清洗释义文本
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
      pitch: pitch,
      foreignOrigin: foreignOrigin,
      examples: examples.take(2).toList(),
      sourceDict: 'デジタル大辞泉',
      sourceUrl: sourceUrl,
    );
  }

  /// 获取指定 .kiji 元素所属词典的规范名称
  static String _getDictNameForKiji(dom.Document doc, dom.Element kiji) {
    if (kiji.classes.contains('Sgkdj') || kiji.querySelector('.Sgkdj') != null) {
      return 'デジタル大辞泉';
    }

    final crossl = kiji.querySelector('.crossl');
    if (crossl != null && crossl.text.trim().isNotEmpty) {
      return crossl.text.trim();
    }

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
        if (prev.localName == 'a') {
          final name = prev.attributes['name'] ?? '';
          if (name.toUpperCase().contains('SGKDJ')) return 'デジタル大辞泉';
          if (name.toUpperCase().contains('DJRIN')) return '大辞林';
        }
        prev = prev.previousElementSibling;
      }
      curr = curr.parent;
    }

    pbarT ??= doc.querySelector('.pbarT');
    if (pbarT != null) {
      final text = pbarT.text.trim();
      if (text.isNotEmpty) {
        return text.split(RegExp(r'\s+')).first;
      }
    }

    return 'Weblio辞書';
  }

  /// 计算词典条目的权威度优先级（严防人名/固有名词篡夺普通语言条目）
  static int _scoreKiji(String dictName, String kijiText, dom.Element kiji) {
    int score = 500;
    final lower = dictName.toLowerCase();

    // 1. 权威一般国语与外来语辞典（高优先级）
    if (dictName.contains('大辞泉') || lower.contains('sgkdj') || kiji.classes.contains('Sgkdj')) {
      score = 1000;
    } else if (dictName.contains('大辞林') || lower.contains('djrin')) {
      score = 900;
    } else if (dictName.contains('国語辞典') ||
        dictName.contains('広辞苑') ||
        dictName.contains('明鏡') ||
        dictName.contains('日本語大辞典') ||
        dictName.contains('精選版')) {
      score = 800;
    } else if (dictName.contains('カタカナ') || dictName.contains('外来語')) {
      score = 750;
    } else if (dictName.contains('Wiktionary') || dictName.contains('ウィクショナリー')) {
      score = 700;
    }

    // 2. 人名、固有名词、作品名、Wikipedia 降级（极低优先级）
    final isNameOrProper = dictName.contains('人名') ||
        dictName.contains('欧米人名') ||
        dictName.contains('日本人名') ||
        dictName.contains('外国人名') ||
        dictName.contains('人物') ||
        dictName.contains('著名人') ||
        dictName.contains('固有名詞') ||
        dictName.contains('作品名') ||
        dictName.contains('アニメ') ||
        dictName.contains('ゲーム') ||
        dictName.contains('映画') ||
        dictName.contains('音楽') ||
        dictName.contains('楽曲') ||
        dictName.contains('ウィキペディア') ||
        dictName.contains('Wikipedia');

    if (isNameOrProper) {
      score = 50;
    }

    // 3. 内容惩罚/加分：若条目文本显式指代具体人名，大幅扣分
    if (kijiText.contains('人名としての') ||
        kijiText.contains('男性名') ||
        kijiText.contains('女性名') ||
        (kijiText.contains('アメリカの') && kijiText.contains('歌手')) ||
        kijiText.contains('サッカー選手') ||
        kijiText.contains('デンマーク語形')) {
      score -= 300;
    }

    // 规范词典多义项编号加分
    if (kijiText.contains('［名］') ||
        kijiText.contains('［動') ||
        kijiText.contains('［形') ||
        RegExp(r'[１-９①-⑩]').hasMatch(kijiText)) {
      score += 100;
    }

    return score;
  }

  /// 智能评估所有可用词典条目 (.kiji)，严格优先一般语言词典，降级人名/固有名词
  WeblioResult? _parseBestKiji(
    dom.Document doc,
    String word,
    String sourceUrl,
  ) {
    final kijis = doc.querySelectorAll('.kiji');
    if (kijis.isEmpty) return null;

    dom.Element? bestKiji;
    int highestScore = -9999;
    String bestDict = 'Weblio辞書';

    for (final kiji in kijis) {
      final dictName = _getDictNameForKiji(doc, kiji);
      final score = _scoreKiji(dictName, kiji.text, kiji);
      if (score > highestScore) {
        highestScore = score;
        bestKiji = kiji;
        bestDict = dictName;
      }
    }

    if (bestKiji != null) {
      return _parseSingleKiji(doc, bestKiji, word, bestDict, sourceUrl);
    }
    return null;
  }


  /// 解析指定的单条 .kiji 条目
  WeblioResult _parseSingleKiji(
    dom.Document doc,
    dom.Element kiji,
    String word,
    String sourceDict,
    String sourceUrl,
  ) {
    // 1. 读音
    String reading = '';
    final midashigo = kiji.querySelector('.midashigo')?.text.trim() ?? '';
    if (midashigo.isNotEmpty) {
      reading = midashigo.split('【').first.trim();
    }
    if (reading.isEmpty) {
      final readingMatch = RegExp(r'読み方：([^\s\n\r<]+)').firstMatch(kiji.text);
      if (readingMatch != null) {
        reading = readingMatch.group(1)!.trim();
      }
    }
    reading = cleanReading(reading);
    if (reading.isEmpty) {
      reading = word;
    }

    // 1.1 声调 (Pitch)
    String pitch = '';
    final pitchMatch = RegExp(r'[〔\[［\(（]([0-9０-９]+(?:[・,、/][0-9０-９]+)*)[〕\]］\)）]').firstMatch(midashigo) ??
        RegExp(r'[〔\[［\(（]([0-9０-９]+(?:[・,、/][0-9０-９]+)*)[〕\]］\)）]').firstMatch(kiji.text);
    if (pitchMatch != null) {
      pitch = formatPitchCircle(pitchMatch.group(1)!);
    }

    // 1.2 外来语英文/原语原词 (Foreign Origin Word)
    String foreignOrigin = extractForeignOriginWord(midashigo);
    if (foreignOrigin.isEmpty) {
      foreignOrigin = extractForeignOriginWord(kiji.text);
    }

    // 2. 词性
    String pos = '';
    final hinshi = kiji.querySelector('.hinshi')?.text.trim();
    if (hinshi != null && hinshi.isNotEmpty) {
      pos = hinshi.replaceAll(RegExp(r'[\s\[\]［］]'), '');
    } else {
      final posMatch = RegExp(r'［([名副形動接続感動詞・スル自他上一下一五段四段サ変カ変]+(?:[（\(][^）\)]+[）\)])?)］').firstMatch(kiji.text);
      if (posMatch != null) {
        pos = posMatch.group(1)!.trim().replaceAll(RegExp(r'[\s\[\]［］]'), '');
      }
    }

    // 3. 释义文本与例句提取
    final pElements = kiji.querySelectorAll('p');
    final defLines = <String>[];
    final examples = <WeblioExample>[];

    String stem = word.replaceAll(RegExp(r'[\u3040-\u309f]+$'), '');
    if (stem.isEmpty) stem = word;

    for (final p in pElements) {
      final t = p.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.isEmpty ||
          t.startsWith('読み方：') ||
          t.startsWith('[補説]') ||
          t.startsWith('[派生]') ||
          t.startsWith('出典:')) {
        continue;
      }

      // 提取例句 「...」
      final exMatches = RegExp(r'「([^」]+)」').allMatches(t);
      final matchedExBrackets = <String>[];
      for (final m in exMatches) {
        final raw = m.group(1)!.trim();
        if (raw.length >= 2 &&
            (raw.contains(RegExp(r'[―—～〜]')) ||
                (raw.contains(word) && raw.length > word.length))) {
          matchedExBrackets.add(m.group(0)!);

          if (examples.length < 2) {
            var restored = raw.replaceAll(RegExp(r'[―—～〜]・'), stem);
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
            restored = restored.replaceAll(RegExp(r'[―—～〜]'), word);
            final kanji = stripFurigana(restored);
            final furigana = formatFurigana(restored);
            if (kanji.isNotEmpty && !examples.any((e) => e.kanji == kanji)) {
              examples.add(WeblioExample(kanji: kanji, furigana: furigana));
            }
          }
        }
      }

      var cleanDef = t;
      for (final exBracket in matchedExBrackets) {
        cleanDef = cleanDef.replaceAll(exBracket, '');
      }
      cleanDef = cleanDef.replaceFirst(RegExp(r'^［[^］]+］\s*'), '').trim();
      if (cleanDef.isNotEmpty) {
        defLines.add(cleanDef);
      }
    }

    final definition = defLines.isNotEmpty
        ? defLines.join('\n').trim()
        : kiji.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    // 4. 若不足 2 条例句，补充 WNRYJ 例文
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

    return WeblioResult(
      word: word,
      reading: reading,
      definition: definition,
      partOfSpeech: pos,
      pitch: pitch,
      foreignOrigin: foreignOrigin,
      examples: examples.take(2).toList(),
      sourceDict: sourceDict,
      sourceUrl: sourceUrl,
    );
  }
}
