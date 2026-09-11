import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_config_dao.dart';
import '../data/vocabulary_dao.dart';
import '../models/chat_message.dart';
import '../models/vocabulary_entry.dart';
import '../models/word_candidate.dart';
import '../providers/api_config_provider.dart';
import '../providers/model_provider.dart';
import 'chat_service.dart';
import 'weblio_service.dart';

/// 单词管理服务
/// 整合本地 SQLite 缓存去重、Weblio 释义抓取与 LLM 智能翻译
class VocabularyService {
  final VocabularyDao vocabularyDao;
  final WeblioService weblioService;
  final ChatService chatService;
  final ApiConfigDao apiConfigDao;
  final Ref? ref;

  VocabularyService({
    required this.vocabularyDao,
    required this.weblioService,
    required this.chatService,
    required this.apiConfigDao,
    this.ref,
  });

  /// 是否已配置可用的 LLM
  bool get hasLlmConfigured {
    final currentRef = ref;
    if (currentRef == null) return false;

    final activeConfig = currentRef.read(apiConfigProvider).activeConfig;
    final modelState = currentRef.read(modelProvider);
    final selectedModel = modelState.selectedModel ??
        (modelState.models.isNotEmpty ? modelState.models.first : null);

    return activeConfig != null && selectedModel != null;
  }

  /// 判断输入文本是否为纯假名（平假名/片假名/长音符/中黑点）
  static bool isPureKana(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[\u3040-\u309f\u30a0-\u30ffー・]+$').hasMatch(trimmed);
  }

  /// 获取纯假名对应的多汉字/多义项候选列表
  Future<List<WordCandidate>> getPureKanaCandidates(String kana) async {
    final trimmed = kana.trim();
    if (trimmed.isEmpty) return [];

    // 1. 若配置了 LLM，优先使用 AI 获取具备清晰中文释义的高质量同音汉字候选项
    if (hasLlmConfigured) {
      try {
        final currentRef = ref!;
        final activeConfig = currentRef.read(apiConfigProvider).activeConfig!;
        final modelState = currentRef.read(modelProvider);
        final selectedModel =
            modelState.selectedModel ?? modelState.models.first;
        final apiKey =
            await apiConfigDao.getApiKey(activeConfig.apiKeyRef) ?? '';

        final prompt = '''
你是一位资深日语语言学专家与词典编纂者。
用户输入了纯日语假名「$trimmed」。在日语中，纯假名通常对应多个不同的日文汉字词汇或具有多种截然不同的常用含义（例如：はし 对应 箸、橋、端）。
请列出该假名最常用、最主要的 2 至 6 个汉字候选词项及其对应简明中文释义，供用户确认选择。
要求：
1. kanji：对应汉字词（若为无汉字的常用纯假名词则写假名原形）。
2. reading：标准假名读音（即「$trimmed」）。
3. partOfSpeech：词性标记（如［名］、［動上一］、［副］等）。
4. definition：简明地道的简体中文释义（例如：筷子。用餐时夹取食物的双根餐具）。
5. 请严格输出以下 JSON 数组格式，不要包含任何 markdown 代码块或解释说明：
[
  {
    "kanji": "汉字词",
    "reading": "$trimmed",
    "partOfSpeech": "词性标记",
    "definition": "简明中文释义"
  }
]
''';

        final messages = [
          ChatMessage(
            id: 'vocab_kana_candidates',
            conversationId: 'vocab_kana',
            role: 'user',
            content: prompt,
            timestamp: DateTime.now(),
          ),
        ];

        final response = await chatService.getCompletion(
          baseUrl: activeConfig.baseUrl,
          apiKey: apiKey,
          model: selectedModel.id,
          messages: messages,
        );

        final aiCandidates = parseCandidatesJson(
          response,
          trimmed,
          CandidateSource.aiInference,
        );
        if (aiCandidates.isNotEmpty) {
          return aiCandidates;
        }
      } catch (_) {
        // AI 异常时平滑降级至词典提取
      }
    }

    // 2. 词典兜底提取
    try {
      final weblioCandidates = await weblioService.fetchCandidates(trimmed);
      if (weblioCandidates.isNotEmpty) {
        return weblioCandidates;
      }
    } catch (_) {}

    return [];
  }

  /// 词典未收录或拼写笔误时，调用 AI 智能推测用户可能想查询的词汇候选项
  Future<List<WordCandidate>> inferTypoCandidates(String word) async {
    final trimmed = word.trim();
    if (trimmed.isEmpty || !hasLlmConfigured) return [];

    try {
      final currentRef = ref!;
      final activeConfig = currentRef.read(apiConfigProvider).activeConfig!;
      final modelState = currentRef.read(modelProvider);
      final selectedModel =
          modelState.selectedModel ?? modelState.models.first;
      final apiKey =
          await apiConfigDao.getApiKey(activeConfig.apiKeyRef) ?? '';

      final prompt = '''
你是一位资深日语教师与专业智能纠错助手。
用户在日语词典中查询「$trimmed」，但在标准词典中未收录该词。这极可能是由于拼写笔误、假名脱落/冗余、送假名错误或活用形式错误（例如：たべまる 可能是 食べる 的笔误）。
请根据日语构词法、发音相近度、键盘输入偏差与常见学习者笔误规律，推测用户最可能想查询的 2 至 5 个正确日语单词候选项。
要求：
1. kanji：推测的正确单词汉字或标准原形（如：食べる）。
2. reading：标准假名读音（如：たべる）。
3. partOfSpeech：规范词性标记（如：［動バ下一］）。
4. definition：简明中文释义并附简短推测理由（例如：进食、吃。推测为食べる的笔误）。
5. 请严格输出以下 JSON 数组格式，不要包含任何 markdown 代码块或解释说明：
[
  {
    "kanji": "推测候选词",
    "reading": "假名读音",
    "partOfSpeech": "词性标记",
    "definition": "简要中文释义与推测说明"
  }
]
''';

      final messages = [
        ChatMessage(
          id: 'vocab_typo_candidates',
          conversationId: 'vocab_typo',
          role: 'user',
          content: prompt,
          timestamp: DateTime.now(),
        ),
      ];

      final response = await chatService.getCompletion(
        baseUrl: activeConfig.baseUrl,
        apiKey: apiKey,
        model: selectedModel.id,
        messages: messages,
      );

      return parseCandidatesJson(
        response,
        trimmed,
        CandidateSource.aiInference,
      );
    } catch (_) {
      return [];
    }
  }

  /// 解析候选词列表 JSON
  List<WordCandidate> parseCandidatesJson(
    String content,
    String originalQuery,
    CandidateSource source,
  ) {
    var raw = content.trim();

    // 优先提取 Markdown 代码块
    final codeBlockMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(raw);
    if (codeBlockMatch != null) {
      raw = codeBlockMatch.group(1)!.trim();
    } else {
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      if (start != -1 && end != -1 && end > start) {
        raw = raw.substring(start, end + 1).trim();
      }
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = <WordCandidate>[];
        for (final item in decoded) {
          if (item is Map) {
            final kanji = item['kanji']?.toString().trim() ?? '';
            final reading = item['reading']?.toString().trim() ?? originalQuery;
            final definition = item['definition']?.toString().trim() ?? '';
            final pos = item['partOfSpeech']?.toString().trim() ?? '';

            if (kanji.isNotEmpty && !list.any((c) => c.kanji == kanji)) {
              list.add(
                WordCandidate(
                  kanji: kanji,
                  reading: reading.isNotEmpty ? reading : originalQuery,
                  definition: definition,
                  partOfSpeech: pos,
                  source: source,
                ),
              );
            }
          }
        }
        return list;
      }
    } catch (_) {}

    return [];
  }

  /// 查词主流程：
  /// 1. 优先检索本地数据库，若已存在直接返回（缓存命中去重）
  /// 2. 调用 Weblio 抓取日语释义、词性与例句（支持递归“查到底”）
  /// 3. 若词典未收录或异常，通过 LLM 智能兜底生成权威词条
  /// 4. 释义完好则严格保持词典原文；若释义存在缺陷或死胡同重定向，则由 AI 自行撰写释义
  /// 5. 存入 SQLite 并返回
  Future<VocabularyEntry> lookupWord(
    String rawWord, {
    bool forceRefresh = false,
    bool allowLlmFallback = true,
  }) async {
    final word = rawWord.trim();
    if (word.isEmpty) {
      throw WeblioException('查询单词不能为空');
    }

    // 1. 本地缓存命中检查（若缓存中仅有无实质释义的重定向残留，则自动穿透重查以自愈）
    if (!forceRefresh) {
      final cached = await vocabularyDao.findByKanji(word);
      if (cached != null && WeblioService.hasSubstantiveDefinition(cached.vocabDefJa)) {
        return cached;
      }
    }

    // 2. Weblio 抓取（含“查到底”递归解析）
    WeblioResult? weblioResult;
    WeblioException? weblioError;

    try {
      weblioResult = await weblioService.lookupWord(word);
    } on WeblioException catch (e) {
      weblioError = e;
    } catch (e) {
      weblioError = WeblioException('Weblio 网络请求异常: $e');
    }

    // 3. 词典查询失败时，根据 allowLlmFallback 决定是否触发 AI 兜底
    if (weblioResult == null) {
      if (allowLlmFallback && hasLlmConfigured) {
        try {
          final aiEntry = await _generateWithLlmFallback(word);
          final insertedId = await vocabularyDao.insert(aiEntry);
          return aiEntry.copyWith(id: insertedId);
        } catch (aiError) {
          throw weblioError ?? WeblioException('AI 兜底生成失败: $aiError');
        }
      }
      throw weblioError ?? WeblioException('未在 Weblio 找到「$word」的相关释义');
    }

    // 4. 判断词典释义是否有问题（无实质解释或死胡同重定向）
    final isProblematic = weblioResult.definition.trim().isEmpty ||
        !WeblioService.hasSubstantiveDefinition(weblioResult.definition);

    String finalDefJa = weblioResult.definition;
    String finalReading = weblioResult.reading;
    String finalPos = weblioResult.partOfSpeech;
    String definitionSc = '';
    String exampleSc1 = '';
    String exampleSc2 = '';
    String? supplementKanji1;
    String? supplementFurigana1;
    String? supplementDefSc1;

    try {
      final translation = await _translateWithLlm(
        weblioResult,
        isProblematic: isProblematic,
      );
      definitionSc = translation['definitionSc'] ?? '';
      exampleSc1 = translation['exampleSc1'] ?? '';
      exampleSc2 = translation['exampleSc2'] ?? '';

      // 实在有问题的就让 AI 自己写日文释义；没有问题的保持词典原文
      final aiDefJa = translation['definitionJa'] ?? '';
      if (isProblematic && aiDefJa.isNotEmpty) {
        finalDefJa = aiDefJa;
      }

      // 若原词典缺失词性或读音，允许 AI 补全
      final aiPos = translation['partOfSpeech'] ?? '';
      if (finalPos.isEmpty && aiPos.isNotEmpty) {
        finalPos = aiPos;
      }
      final aiReading = translation['furigana'] ?? '';
      if ((finalReading.isEmpty || finalReading == word) && aiReading.isNotEmpty) {
        finalReading = aiReading;
      }

      // 补充原词典缺失的例句
      final suppK1 = translation['supplementSentKanji1'] ?? '';
      if (suppK1.isNotEmpty) {
        supplementKanji1 = suppK1;
        supplementFurigana1 = translation['supplementSentFurigana1'] ?? suppK1;
        supplementDefSc1 = translation['supplementDefSc1'] ?? '';
      }
    } catch (_) {
      // 优雅降级：LLM 异常或未配置时不中断查词主流程，仅中文留空
    }

    // 5. 构建并持久化
    final hasEx1 = weblioResult.examples.isNotEmpty;
    final hasEx2 = weblioResult.examples.length > 1;

    final sentK1 = hasEx1 ? weblioResult.examples[0].kanji : supplementKanji1;
    final sentF1 = hasEx1 ? weblioResult.examples[0].furigana : supplementFurigana1;
    final sentD1 = hasEx1
        ? (exampleSc1.isNotEmpty ? exampleSc1 : null)
        : (supplementDefSc1?.isNotEmpty == true ? supplementDefSc1 : null);

    final entry = VocabularyEntry(
      vocabKanji: weblioResult.word,
      vocabFurigana: finalReading,
      vocabDefJa: finalDefJa,
      vocabDefSc: definitionSc,
      vocabPoS: finalPos,
      sentKanji1: sentK1,
      sentFurigana1: sentF1,
      sentDefSc1: sentD1,
      sentKanji2: hasEx2 ? weblioResult.examples[1].kanji : null,
      sentFurigana2: hasEx2 ? weblioResult.examples[1].furigana : null,
      sentDefSc2: hasEx2 && exampleSc2.isNotEmpty ? exampleSc2 : null,
      sourceDict: weblioResult.sourceDict,
      sourceUrl: weblioResult.sourceUrl,
      createdAt: DateTime.now(),
    );

    final insertedId = await vocabularyDao.insert(entry);
    return entry.copyWith(id: insertedId);
  }

  /// 词典未收录或网络故障时的 AI 智能兜底生成
  Future<VocabularyEntry> _generateWithLlmFallback(String word) async {
    final currentRef = ref;
    if (currentRef == null) {
      throw WeblioException('未在 Weblio 找到「$word」的相关释义，且未配置 AI 模型');
    }

    final activeConfig = currentRef.read(apiConfigProvider).activeConfig;
    final modelState = currentRef.read(modelProvider);
    final selectedModel = modelState.selectedModel ??
        (modelState.models.isNotEmpty ? modelState.models.first : null);

    if (activeConfig == null || selectedModel == null) {
      throw WeblioException('未在 Weblio 找到「$word」的相关释义，且未配置 AI 模型');
    }

    final apiKey = await apiConfigDao.getApiKey(activeConfig.apiKeyRef) ?? '';

    final prompt = '''
你是一位资深日语词典编纂专家与专业翻译助手。
用户需要查询日语单词「$word」，但在基础词典中未收录该词。请你以权威词典（如《大辞泉》）的标准，为该单词补充完整的词条信息。

要求：
1. furigana：平假名读音（如「こうじる」）。
2. partOfSpeech：词性标记（如［動ザ上一］、［名］、［形］、［副］等规范日语词性标记）。
3. definitionJa：使用严谨地道的日语撰写清晰的释义，多义项请使用数字编号（如：１ ... ２ ...）。
4. definitionSc：翻译为简体中文释义，保留对应的数字编号（如：1. ... 2. ...）。
5. 例句（1-2条实用地道的日文例句）：
   - sentKanji1：例句1日文汉字文本
   - sentFurigana1：例句1假名注音（严格采用 Anki ruby 格式，如：策[さく]を 講[こう]じる）
   - sentDefSc1：例句1的简体中文翻译
   - sentKanji2：例句2日文汉字文本（若无可留空字符串）
   - sentFurigana2：例句2假名注音（Anki ruby 格式，若无可留空字符串）
   - sentDefSc2：例句2的简体中文翻译（若无可留空字符串）
6. 请严格输出以下 JSON，不要包含任何 markdown 代码块或解释说明：
{
  "furigana": "平假名读音",
  "partOfSpeech": "词性标记",
  "definitionJa": "地道日文释义",
  "definitionSc": "简体中文释义",
  "sentKanji1": "例句1日文汉字",
  "sentFurigana1": "例句1假名注音",
  "sentDefSc1": "例句1中文翻译",
  "sentKanji2": "例句2日文汉字",
  "sentFurigana2": "例句2假名注音",
  "sentDefSc2": "例句2中文翻译"
}
''';

    final messages = [
      ChatMessage(
        id: 'vocab_fallback_user',
        conversationId: 'vocab_fallback',
        role: 'user',
        content: prompt,
        timestamp: DateTime.now(),
      ),
    ];

    final response = await chatService.getCompletion(
      baseUrl: activeConfig.baseUrl,
      apiKey: apiKey,
      model: selectedModel.id,
      messages: messages,
    );

    return parseFallbackEntryJson(response, word);
  }

  /// 解析 AI 兜底生成的 JSON 数据
  VocabularyEntry parseFallbackEntryJson(String content, String word) {
    var raw = content.trim();

    final codeBlockMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(raw);
    if (codeBlockMatch != null) {
      raw = codeBlockMatch.group(1)!.trim();
    } else {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        raw = raw.substring(start, end + 1).trim();
      }
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final furigana = decoded['furigana']?.toString().trim() ?? word;
      final partOfSpeech = decoded['partOfSpeech']?.toString().trim() ?? '';
      final definitionJa = decoded['definitionJa']?.toString().trim() ?? '';
      final definitionSc = decoded['definitionSc']?.toString().trim() ?? '';
      final sentKanji1 = decoded['sentKanji1']?.toString().trim();
      final sentFurigana1 = decoded['sentFurigana1']?.toString().trim();
      final sentDefSc1 = decoded['sentDefSc1']?.toString().trim();
      final sentKanji2 = decoded['sentKanji2']?.toString().trim();
      final sentFurigana2 = decoded['sentFurigana2']?.toString().trim();
      final sentDefSc2 = decoded['sentDefSc2']?.toString().trim();

      final hasEx1 = sentKanji1 != null && sentKanji1.isNotEmpty;
      final hasEx2 = sentKanji2 != null && sentKanji2.isNotEmpty;

      return VocabularyEntry(
        vocabKanji: word,
        vocabFurigana: furigana.isNotEmpty ? furigana : word,
        vocabDefJa: definitionJa,
        vocabDefSc: definitionSc,
        vocabPoS: partOfSpeech,
        sentKanji1: hasEx1 ? sentKanji1 : null,
        sentFurigana1: hasEx1 ? (sentFurigana1?.isNotEmpty == true ? sentFurigana1 : sentKanji1) : null,
        sentDefSc1: hasEx1 && sentDefSc1?.isNotEmpty == true ? sentDefSc1 : null,
        sentKanji2: hasEx2 ? sentKanji2 : null,
        sentFurigana2: hasEx2 ? (sentFurigana2?.isNotEmpty == true ? sentFurigana2 : sentKanji2) : null,
        sentDefSc2: hasEx2 && sentDefSc2?.isNotEmpty == true ? sentDefSc2 : null,
        sourceDict: 'AI兜底生成',
        sourceUrl: '',
        createdAt: DateTime.now(),
      );
    } catch (_) {
      return VocabularyEntry(
        vocabKanji: word,
        vocabFurigana: word,
        vocabDefJa: '',
        vocabDefSc: content.trim(),
        vocabPoS: '',
        sourceDict: 'AI兜底生成',
        sourceUrl: '',
        createdAt: DateTime.now(),
      );
    }
  }

  /// 调用 LLM 翻译释义与例句，兼顾缺陷释义重写
  Future<Map<String, String>> _translateWithLlm(
    WeblioResult result, {
    bool isProblematic = false,
  }) async {
    final currentRef = ref;
    if (currentRef == null) return {};

    final activeConfig = currentRef.read(apiConfigProvider).activeConfig;
    final modelState = currentRef.read(modelProvider);
    final selectedModel = modelState.selectedModel ??
        (modelState.models.isNotEmpty ? modelState.models.first : null);

    if (activeConfig == null || selectedModel == null) {
      return {};
    }

    final apiKey = await apiConfigDao.getApiKey(activeConfig.apiKeyRef) ?? '';

    final ex1 = result.examples.isNotEmpty ? result.examples[0].kanji : '';
    final ex2 = result.examples.length > 1 ? result.examples[1].kanji : '';
    final needsExamples = result.examples.isEmpty;

    final String prompt;
    if (isProblematic) {
      prompt = '''
你是一位资深日语词典编纂专家与专业翻译助手。
用户正在学习日语单词「${result.word}」。由于从词典抓取的释义不完整或仅为死胡同语法重定向，请你为该词重新撰写地道权威的日文释义、中文释义${needsExamples ? '并补充例句' : ''}与规范词性标注。

要求：
1. definitionJa：使用严谨地道的日语撰写清晰的释义，多义项请使用数字编号（如：１ ... ２ ...）。
2. definitionSc：翻译为简体中文释义，保留对应的数字编号（如：1. ... 2. ...）。请直接翻译具体的词义含义，严禁仅输出“是…的活用”等元语言说明！
3. partOfSpeech：规范的日语词性标记（如［動ザ上一］、［動サ変］、［名］、［形］等）。
4. furigana：平假名读音（如「こうじる」）。
5. ${needsExamples ? 'supplementSentKanji1 / supplementSentFurigana1（Anki ruby 格式，如 策[さく]を 講[こう]じる） / supplementDefSc1：补充一条地道日文例句及其中文翻译' : 'exampleSc1 / exampleSc2：将给出的例句翻译为简体中文'}
6. 请严格输出以下 JSON，不要包含任何 markdown 代码块或解释说明：
{
  "definitionJa": "地道日文释义",
  "definitionSc": "简体中文释义",
  "partOfSpeech": "词性标记",
  "furigana": "平假名读音",
  "exampleSc1": "例句1中文翻译（若无例句留空字符串）",
  "exampleSc2": "例句2中文翻译（若无例句留空字符串）"${needsExamples ? ',\n  "supplementSentKanji1": "例句1日文汉字",\n  "supplementSentFurigana1": "例句1假名注音（如 策[さく]を 講[こう]じる）",\n  "supplementDefSc1": "例句1中文翻译"' : ''}
}

日语单词：${result.word}
假名读音：${result.reading}
词性：${result.partOfSpeech}
参考原释义：
${result.definition}
${ex1.isNotEmpty ? '例句1：$ex1' : ''}
${ex2.isNotEmpty ? '例句2：$ex2' : ''}
''';
    } else {
      prompt = '''
你是一位专业的日语翻译助手。请将以下日语单词的释义和例句翻译为简体中文。
要求：
1. 释义翻译简明扼要，保留原有的数字编号格式（如 1. 2. 或 １ ２）。
2. 【核心释义翻译规则】：请直接翻译具体实质的中文词义（例如：1. 讲授，讲学；2. 采取（措施、对策））。
   【绝对禁止】：严禁输出“是…的上一段化”、“是…的上一段活用”、“是…的活用形”、“与…相同”等元语言语法废话，必须直接给出具体的中文含义解释！
3. 例句翻译通顺自然。
${needsExamples ? '4. 原词典无例句，请在 supplementSentKanji1, supplementSentFurigana1 (Anki ruby 格式), supplementDefSc1 中补充一条实用例句与翻译。\n5. ' : '4. '}请严格按照以下 JSON 格式输出，不要包含任何 markdown 代码块或解释说明：
{
  "definitionSc": "中文释义",
  "exampleSc1": "例句1中文翻译（若无例句留空字符串）",
  "exampleSc2": "例句2中文翻译（若无例句留空字符串）"${needsExamples ? ',\n  "supplementSentKanji1": "例句1日文汉字",\n  "supplementSentFurigana1": "例句1假名注音（如 策[さく]を 講[こう]じる）",\n  "supplementDefSc1": "例句1中文翻译"' : ''}
}

日语单词：${result.word}
假名读音：${result.reading}
词性：${result.partOfSpeech}
日语释义：
${result.definition}
${ex1.isNotEmpty ? '例句1：$ex1' : ''}
${ex2.isNotEmpty ? '例句2：$ex2' : ''}
''';
    }

    final messages = [
      ChatMessage(
        id: 'vocab_trans_user',
        conversationId: 'vocab_trans',
        role: 'user',
        content: prompt,
        timestamp: DateTime.now(),
      ),
    ];

    final response = await chatService.getCompletion(
      baseUrl: activeConfig.baseUrl,
      apiKey: apiKey,
      model: selectedModel.id,
      messages: messages,
    );

    return parseTranslationJson(response);
  }

  /// 清洗中文释义：剥离可能残留的前置元语言语法说明（如“是講ずる的上一段活用。1. ...”）
  static String sanitizeDefinitionSc(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final pattern = RegExp(
      r'^(?:(?:是|“[^”]+”的|「[^」]+」的|[a-zA-Z\u4e00-\u9faf\u3040-\u309f]+的)?\s*(?:上一段|下一段|五段|サ変|カ変)?(?:活用|化|形式|同义词|变形)[。；;，,\s]+)(.+)$',
      dotAll: true,
    );
    final match = pattern.firstMatch(trimmed);
    if (match != null) {
      final remainder = match.group(1)!.trim();
      if (remainder.isNotEmpty) {
        return remainder;
      }
    }
    return trimmed;
  }

  /// 解析 LLM 返回的 JSON 内容，具备容错处理
  Map<String, String> parseTranslationJson(String content) {
    var raw = content.trim();

    // 1. 优先提取 Markdown 代码块（如 ```json ... ```）
    final codeBlockMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(raw);
    if (codeBlockMatch != null) {
      raw = codeBlockMatch.group(1)!.trim();
    } else {
      // 2. 若无代码块，提取首尾大括号范围内的 JSON 子串
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        raw = raw.substring(start, end + 1).trim();
      }
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final rawDefSc = decoded['definitionSc']?.toString().trim() ?? '';
      return {
        'definitionSc': sanitizeDefinitionSc(rawDefSc),
        'definitionJa': decoded['definitionJa']?.toString().trim() ?? '',
        'partOfSpeech': decoded['partOfSpeech']?.toString().trim() ?? '',
        'furigana': decoded['furigana']?.toString().trim() ?? '',
        'exampleSc1': decoded['exampleSc1']?.toString().trim() ?? '',
        'exampleSc2': decoded['exampleSc2']?.toString().trim() ?? '',
        'supplementSentKanji1': decoded['supplementSentKanji1']?.toString().trim() ?? '',
        'supplementSentFurigana1': decoded['supplementSentFurigana1']?.toString().trim() ?? '',
        'supplementDefSc1': decoded['supplementDefSc1']?.toString().trim() ?? '',
      };
    } catch (_) {
      // 容错：剥离可能残留的代码块符号后，将文本作为中文释义
      var fallback = content.trim();
      if (fallback.startsWith('```')) {
        final lines = fallback.split('\n');
        if (lines.length > 2) {
          fallback = lines.sublist(1, lines.length - 1).join('\n').trim();
        }
      }
      return {
        'definitionSc': sanitizeDefinitionSc(fallback),
        'definitionJa': '',
        'partOfSpeech': '',
        'furigana': '',
        'exampleSc1': '',
        'exampleSc2': '',
      };
    }
  }
}
