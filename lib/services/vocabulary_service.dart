import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/api_config_dao.dart';
import '../data/vocabulary_dao.dart';
import '../models/api_config.dart';
import '../models/chat_message.dart';
import '../models/vocabulary_entry.dart';
import '../models/word_candidate.dart';
import '../providers/api_config_provider.dart';
import '../providers/model_provider.dart';
import '../providers/vocabulary_config_provider.dart';
import 'chat_service.dart';
import 'weblio_service.dart';

/// 解析出的有效生词本 LLM 供应商与模型配置
class ResolvedVocabLlm {
  final ApiConfig config;
  final String modelId;
  final String apiKey;

  ResolvedVocabLlm({
    required this.config,
    required this.modelId,
    required this.apiKey,
  });
}

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

  /// 解析用于生词本翻译与推理的有效 LLM 配置（包含 ApiConfig、ModelId 与 API Key）
  /// 优先级：
  /// 1. 生词本专属配置（vocabularyConfigProvider / SharedPreferences）
  /// 2. 聊天主界面当前选中的 activeConfig 与 selectedModel
  /// 3. 数据库默认配置（getDefault / getAll.first）与默认模型
  Future<ResolvedVocabLlm?> resolveVocabLlm() async {
    final currentRef = ref;

    // 1. 若有 Ref，优先读取生词本专属配置提供者
    if (currentRef != null) {
      try {
        final vocabNotifier =
            currentRef.read(vocabularyConfigProvider.notifier);
        await vocabNotifier.initialization;
      } catch (_) {}

      try {
        final vocabCfg = currentRef.read(vocabularyConfigProvider);
        if (vocabCfg.config != null && vocabCfg.model != null) {
          final apiKey =
              await apiConfigDao.getApiKey(vocabCfg.config!.apiKeyRef) ?? '';
          return ResolvedVocabLlm(
            config: vocabCfg.config!,
            modelId: vocabCfg.model!.id,
            apiKey: apiKey,
          );
        }
      } catch (_) {}

      // 2. 尝试读取 Chat 聊天界面的 activeConfig 与 selectedModel
      try {
        final activeConfig = currentRef.read(apiConfigProvider).activeConfig;
        final modelState = currentRef.read(modelProvider);
        final selectedModel = modelState.selectedModel ??
            (modelState.models.isNotEmpty ? modelState.models.first : null);

        if (activeConfig != null && selectedModel != null) {
          final apiKey =
              await apiConfigDao.getApiKey(activeConfig.apiKeyRef) ?? '';
          return ResolvedVocabLlm(
            config: activeConfig,
            modelId: selectedModel.id,
            apiKey: apiKey,
          );
        }
      } catch (_) {}
    }

    // 若 ref 为 null（例如纯单元测试环境下），直接返回 null 保持测试隔离与降级行为
    if (currentRef == null) {
      return null;
    }

    // 3. 读取本地 SharedPreferences 中持久化的生词本配置
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedConfigId =
          prefs.getString(VocabularyConfigNotifier.keyVocabApiConfigId);
      final savedModelId =
          prefs.getString(VocabularyConfigNotifier.keyVocabModelId);
      if (savedConfigId != null && savedConfigId.isNotEmpty) {
        final config = await apiConfigDao.getById(savedConfigId);
        if (config != null) {
          final apiKey =
              await apiConfigDao.getApiKey(config.apiKeyRef) ?? '';
          final modelId = (savedModelId != null && savedModelId.isNotEmpty)
              ? savedModelId
              : (config.id == 'opencode_free'
                  ? 'deepseek-v4-flash-free'
                  : 'gpt-4o-mini');
          return ResolvedVocabLlm(
            config: config,
            modelId: modelId,
            apiKey: apiKey,
          );
        }
      }
    } catch (_) {}

    // 4. 智能兜底：从 apiConfigDao 中获取默认配置（或第一项配置）并选用适合该配置的模型
    try {
      var defaultCfg = await apiConfigDao.getDefault();
      if (defaultCfg == null) {
        final all = await apiConfigDao.getAll();
        if (all.isNotEmpty) {
          defaultCfg = all.first;
        }
      }
      if (defaultCfg != null) {
        final apiKey =
            await apiConfigDao.getApiKey(defaultCfg.apiKeyRef) ?? '';
        final modelId = defaultCfg.id == 'opencode_free'
            ? 'deepseek-v4-flash-free'
            : (defaultCfg.baseUrl.toLowerCase().contains('deepseek')
                ? 'deepseek-chat'
                : 'gpt-4o-mini');
        return ResolvedVocabLlm(
          config: defaultCfg,
          modelId: modelId,
          apiKey: apiKey,
        );
      }
    } catch (_) {}

    return null;
  }

  /// 是否已配置可用的 LLM
  bool get hasLlmConfigured {
    final currentRef = ref;
    if (currentRef == null) return false;

    // 1. 检查生词本专属配置
    try {
      final vocabCfg = currentRef.read(vocabularyConfigProvider);
      if (vocabCfg.config != null && vocabCfg.model != null) {
        return true;
      }
      if (vocabCfg.isLoading) {
        return true;
      }
    } catch (_) {}

    // 2. 检查 Chat 主界面的 activeConfig 与 selectedModel
    try {
      final activeConfig = currentRef.read(apiConfigProvider).activeConfig;
      final modelState = currentRef.read(modelProvider);
      final selectedModel = modelState.selectedModel ??
          (modelState.models.isNotEmpty ? modelState.models.first : null);
      if (activeConfig != null && selectedModel != null) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  /// 判断输入文本是否为纯假名（平假名/片假名/长音符/中黑点，且至少包含一个真实假名字符）
  static bool isPureKana(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final isAllKanaChars =
        RegExp(r'^[\u3040-\u309f\u30a0-\u30ffー・]+$').hasMatch(trimmed);
    final hasActualKanaLetter =
        RegExp(r'[\u3041-\u3096\u30a1-\u30fa]').hasMatch(trimmed);
    return isAllKanaChars && hasActualKanaLetter;
  }

  /// 获取纯假名对应的多汉字/多义项候选列表
  Future<List<WordCandidate>> getPureKanaCandidates(String kana) async {
    final trimmed = kana.trim();
    if (trimmed.isEmpty) return [];

    // 1. 若配置了 LLM，优先使用 AI 获取具备清晰中文释义的高质量同音汉字候选项
    final llm = await resolveVocabLlm();
    if (llm != null) {
      try {
        final prompt = '''
你是一位资深日语语言学专家与词典编纂者。
用户输入了纯日语假名「$trimmed」。
在日语中，部分纯假名对应多个不同汉字、外来语多重主要义项或截然不同的词义（例如：はし 对应 箸、橋、端；あめ 对应 雨、飴；こうじる 对应 高じる、講じる、興じる；アクセル 对应 加速踏板/油门、花滑阿克塞尔跳、欧美男子人名）。
请评估该假名：
- 如果该假名在标准日语中通常只对应单一汉字/单一常用词义（如：たべる 对应 食べる；ねこ 对应 猫），或者该假名本身并非有效词汇（如拼写笔误），请返回空数组 [] 或仅包含 1 个词项。
- 如果该假名确实对应多个常用的不同汉字、外来语核心义项或截然不同的词义，请列出其最常用、最主要的 2 至 5 个核心候选词项及其极其精简的核心主要意思（每个选项只保留主要意思，10-25字），供用户消歧确认。
要求：
1. kanji：对应汉字词，若为外来语/同形多义假名词请附带精炼区分标识（例如：箸、橋；或 アクセル(油门/加速器)、アクセル(阿克塞尔跳)、アクセル(人名)）。
2. reading：标准假名读音（即「$trimmed」）。
3. partOfSpeech：词性标记（如［名］、［動上一］、［副］等）。
4. definition：简明主要意思（只列出最核心主要意思，精炼短小）。
5. disambiguationWord：查词时使用的规范原词（即「$trimmed」或标准汉字形）。
6. 请严格输出以下 JSON 数组格式，不要包含任何 markdown 代码块或解释说明：
[
  {
    "kanji": "候选词",
    "reading": "$trimmed",
    "partOfSpeech": "词性标记",
    "definition": "简明主要意思",
    "disambiguationWord": "$trimmed"
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
          baseUrl: llm.config.baseUrl,
          apiKey: llm.apiKey,
          model: llm.modelId,
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
    if (trimmed.isEmpty) return [];

    final llm = await resolveVocabLlm();
    if (llm == null) return [];

    try {
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
        baseUrl: llm.config.baseUrl,
        apiKey: llm.apiKey,
        model: llm.modelId,
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
    }

    // 无论是否位于代码块中，均提取最外层的 JSON 数组 [...]
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start != -1 && end != -1 && end > start) {
      raw = raw.substring(start, end + 1).trim();
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
            final disambig = item['disambiguationWord']?.toString().trim();

            final isDuplicate = list.any((c) =>
                c.kanji == kanji &&
                (c.definition == definition ||
                    (definition.isNotEmpty && c.definition.contains(definition))));

            if (kanji.isNotEmpty && !isDuplicate) {
              list.add(
                WordCandidate(
                  kanji: kanji,
                  reading: reading.isNotEmpty ? reading : originalQuery,
                  definition: definition,
                  partOfSpeech: pos,
                  source: source,
                  disambiguationWord: disambig ??
                      (kanji.contains('(') || kanji.contains('（')
                          ? originalQuery
                          : null),
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

    // 1. 本地缓存命中检查（若缓存中仅有无实质释义的重定向残留，或属于被污染的人名/专有名词条目，则自动穿透重查以自愈）
    if (!forceRefresh) {
      final cached = await vocabularyDao.findByKanji(word);
      if (cached != null &&
          WeblioService.hasSubstantiveDefinition(cached.vocabDefJa) &&
          !WeblioService.isPersonOrProperNameDefinition(
            cached.vocabDefJa,
            cached.sourceDict,
          )) {
        // 若缓存已有但缺失中文释义，尝试通过 LLM 进行自愈补全翻译
        if (cached.vocabDefSc.isEmpty) {
          final llm = await resolveVocabLlm();
          if (llm != null) {
            try {
              final translated = await retranslateEntry(cached);
              return translated;
            } catch (_) {
              return cached;
            }
          }
        }
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
      if (allowLlmFallback) {
        final llm = await resolveVocabLlm();
        if (llm != null) {
          try {
            final aiEntry = await _generateWithLlmFallback(word);
            final insertedId = await vocabularyDao.insert(aiEntry);
            return aiEntry.copyWith(id: insertedId);
          } catch (aiError) {
            throw weblioError ?? WeblioException('AI 兜底生成失败: $aiError');
          }
        }
      }
      throw weblioError ?? WeblioException('未在 Weblio 找到「$word」的相关释义');
    }

    // 4. 判断词典释义是否有问题（无实质解释或死胡同重定向）
    final isProblematic = weblioResult.definition.trim().isEmpty ||
        !WeblioService.hasSubstantiveDefinition(weblioResult.definition);

    String finalDefJa = weblioResult.definition;
    String finalReading = weblioResult.reading;
    String finalPos = normalizePartOfSpeech(weblioResult.partOfSpeech);
    String finalPitch = weblioResult.pitch;
    final isKata = WeblioService.isKatakana(word);
    if (isKata && weblioResult.foreignOrigin.isNotEmpty) {
      finalReading = weblioResult.foreignOrigin;
    } else {
      finalReading = WeblioService.cleanReading(finalReading);
    }
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

      // 词性：优先采纳 LLM 学习者规范词性
      final aiPos = translation['partOfSpeech'] ?? '';
      if (aiPos.isNotEmpty) {
        finalPos = normalizePartOfSpeech(aiPos);
      } else {
        finalPos = normalizePartOfSpeech(finalPos);
      }
      if (finalPos.isEmpty && isKata) {
        finalPos = '名';
      }

      // 音调：词典原生优先，缺失时由 AI 补全
      final aiPitch = WeblioService.formatPitchCircle(translation['pitch'] ?? '');
      if (finalPitch.isEmpty && aiPitch.isNotEmpty) {
        finalPitch = aiPitch;
      }

      // 读音/外来语原词：片假名外来语单词优先采纳英文原语，普通词清洗平假名
      final aiForeign = translation['foreignOrigin'] ?? '';
      final aiReading = translation['furigana'] ?? '';
      if (isKata) {
        if (aiForeign.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(aiForeign)) {
          finalReading = aiForeign.trim();
        } else if (finalReading == word || finalReading.isEmpty || !RegExp(r'[a-zA-Z]').hasMatch(finalReading)) {
          if (aiReading.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(aiReading)) {
            finalReading = aiReading.trim();
          }
        }
      } else {
        if ((finalReading.isEmpty || finalReading == word) && aiReading.isNotEmpty) {
          finalReading = WeblioService.cleanReading(aiReading);
        }
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
    // 兜底保障规范词性与外来语词性
    finalPos = normalizePartOfSpeech(finalPos);
    if (finalPos.isEmpty && isKata) {
      finalPos = '名';
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
      vocabPitch: finalPitch,
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
    final llm = await resolveVocabLlm();
    if (llm == null) {
      throw WeblioException('未在 Weblio 找到「$word」的相关释义，且未配置 AI 模型');
    }

    final prompt = '''
你是一位资深日语词典编纂专家与专业翻译助手。
用户需要查询日语单词「$word」，但在基础词典中未收录该词。请你以权威词典（如《大辞泉》）的标准，为该单词补充完整的词条信息。

要求：
1. furigana：普通词输出纯平假名；片假名外来语单词（如「スリル」）必须输出其英文/原语原词（如「thrill」），严禁转写为平假名（如「すりる」）！
2. foreignOrigin：若当前单词是外来语/借词，必须提供其英文或原语原词拼写（如 thrill），非外来语则留空字符串。
3. partOfSpeech：严格输出日本语学习者规范词性（五段动词输出 他動1/自動1/自他動1；一段动词输出 他動2/自動2/自他動2；サ変输出 他動3/自動3/自他動3/動サ変；カ変输出 動カ変；名、副、形、形動、接続、感等），严禁输出“他動5”、“自動5”、“動サ五（四）”、“動バ下一”等错误或日日生僻标记！
4. pitch：日语标准音调圆圈数字（如：⓪、①、②、③等）。
5. definitionJa：使用严谨地道的日语撰写清晰的释义，多义项请使用数字编号（如：１ ... ２ ...）。
6. definitionSc：翻译为简体中文释义，保留对应的数字编号（如：1. ... 2. ...）。
7. 例句（1-2条实用地道的日文例句）：
   - sentKanji1：例句1日文汉字文本
   - sentFurigana1：例句1假名注音（严格采用 Anki ruby 格式，如：策[さく]を 講[こう]じる）
   - sentDefSc1：例句1的简体中文翻译
   - sentKanji2：例句2日文汉字文本（若无可留空字符串）
   - sentFurigana2：例句2假名注音（Anki ruby 格式，若无可留空字符串）
   - sentDefSc2：例句2的简体中文翻译（若无可留空字符串）
8. 请严格输出以下 JSON，不要包含任何 markdown 代码块或解释说明：
{
  "furigana": "读音（普通词平假名，外来语输出英文原词如 thrill）",
  "foreignOrigin": "外来语原语英文拼写（如 thrill，非外来语留空）",
  "partOfSpeech": "规范词性（如 他動1、名、副、形等）",
  "pitch": "标准音调圆圈数字（如 ⓪、①、②等）",
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
      baseUrl: llm.config.baseUrl,
      apiKey: llm.apiKey,
      model: llm.modelId,
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
      final foreignOrigin = decoded['foreignOrigin']?.toString().trim() ?? '';
      String finalFurigana = furigana;
      if (WeblioService.isKatakana(word)) {
        if (foreignOrigin.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(foreignOrigin)) {
          finalFurigana = foreignOrigin;
        } else if (furigana.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(furigana)) {
          finalFurigana = furigana;
        }
      }

      final rawPos = decoded['partOfSpeech']?.toString().trim() ?? '';
      var partOfSpeech = normalizePartOfSpeech(rawPos);
      if (partOfSpeech.isEmpty && WeblioService.isKatakana(word)) {
        partOfSpeech = '名';
      }

      final pitch = WeblioService.formatPitchCircle(decoded['pitch']?.toString().trim() ?? '');
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
        vocabFurigana: finalFurigana.isNotEmpty ? finalFurigana : word,
        vocabPitch: pitch,
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
        vocabPitch: '',
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
    final llm = await resolveVocabLlm();
    if (llm == null) return {};

    final apiKey = llm.apiKey;
    final activeConfig = llm.config;
    final selectedModelId = llm.modelId;

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
3. partOfSpeech：严格输出日本语学习者规范词性（五段动词输出 他動1/自動1/自他動1；一段动词输出 他動2/自動2/自他動2；サ変输出 他動3/自動3/自他動3/動サ変；カ変输出 動カ変；名、副、形、形動、接続、感等），严禁输出“他動5”、“自動5”、“動サ五（四）”、“動バ下一”等错误或日日生僻标记！
4. pitch：日语标准音调圆圈数字（如：⓪、①、②、③等）。
5. furigana：普通词输出纯平假名；片假名外来语单词（如「スリル」）必须输出其英文/原语原词（如「thrill」），严禁转写为平假名（如「すりる」）！
6. foreignOrigin：若当前单词是外来语/借词，必须提供其英文或原语原词拼写（如 thrill），非外来语留空。
7. ${needsExamples ? 'supplementSentKanji1 / supplementSentFurigana1（Anki ruby 格式，如 策[さく]を 講[こう]じる） / supplementDefSc1：补充一条地道日文例句及其中文翻译' : 'exampleSc1 / exampleSc2：将给出的例句翻译为简体中文'}
8. 请严格输出以下 JSON，不要包含任何 markdown 代码块或解释说明：
{
  "definitionJa": "地道日文释义",
  "definitionSc": "简体中文释义",
  "partOfSpeech": "规范词性（如 他動1、名、副、形等）",
  "pitch": "标准音调圆圈数字（如 ⓪、①、②等）",
  "furigana": "读音（普通词平假名，外来语输出英文原词如 thrill）",
  "foreignOrigin": "外来语原语英文拼写（如 thrill，非外来语留空）",
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
你是一位专业的日语翻译助手。请将以下日语单词的释义和例句翻译为简体中文，并规范词性与音调。
要求：
1. definitionSc：简明扼要翻译为简体中文释义，保留原有的数字编号格式（如 1. 2. 或 １ ２）。直接翻译具体实质的中文词义，严禁输出“是…的活用形”等废话！
2. partOfSpeech：严格输出日本语学习者规范词性（五段动词输出 他動1/自動1/自他動1；一段动词输出 他動2/自動2/自他動2；サ変输出 他動3/自動3/自他動3/動サ変；カ変输出 動カ変；名、副、形、形動、接続、感等），严禁输出“他動5”、“自動5”、“動サ五（四）”、“動バ下一”等错误或日日生僻标记！
3. pitch：日语标准音调圆圈数字（如：⓪、①、②、③等）。
4. furigana：普通词输出纯平假名；片假名外来语单词（如「スリル」）必须输出其英文/原语原词（如「thrill」），严禁转写为平假名（如「すりる」）！
5. foreignOrigin：若当前单词是外来语/借词，必须提供其英文或原语原词拼写（如 thrill），非外来语留空。
6. ${needsExamples ? 'supplementSentKanji1 / supplementSentFurigana1 (Anki ruby 格式) / supplementDefSc1：原词典无例句，请补充一条实用例句及翻译。\n7. ' : ''}exampleSc1 / exampleSc2：例句翻译为简体中文，通顺自然。
${needsExamples ? '8' : '7'}. 请严格按照以下 JSON 格式输出，不要包含任何 markdown 代码块或解释说明：
{
  "definitionSc": "中文释义",
  "partOfSpeech": "规范词性（如 他動1、名、副、形等）",
  "pitch": "标准音调圆圈数字（如 ⓪、①、②等）",
  "furigana": "读音（普通词平假名，外来语输出英文原词如 thrill）",
  "foreignOrigin": "外来语原语英文拼写（如 thrill，非外来语留空）",
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
      model: selectedModelId,
      messages: messages,
    );

    return parseTranslationJson(response);
  }

  /// 对已存入生词本但缺少中文释义的单词重新调用 LLM 进行翻译与例句补全
  Future<VocabularyEntry> retranslateEntry(VocabularyEntry entry) async {
    final isProblematic = entry.vocabDefJa.trim().isEmpty ||
        !WeblioService.hasSubstantiveDefinition(entry.vocabDefJa);

    final weblioResult = WeblioResult(
      word: entry.vocabKanji,
      reading: entry.vocabFurigana,
      partOfSpeech: entry.vocabPoS,
      definition: entry.vocabDefJa,
      examples: [
        if (entry.sentKanji1 != null && entry.sentKanji1!.isNotEmpty)
          WeblioExample(
            kanji: entry.sentKanji1!,
            furigana: entry.sentFurigana1 ?? entry.sentKanji1!,
          ),
        if (entry.sentKanji2 != null && entry.sentKanji2!.isNotEmpty)
          WeblioExample(
            kanji: entry.sentKanji2!,
            furigana: entry.sentFurigana2 ?? entry.sentKanji2!,
          ),
      ],
      sourceDict: entry.sourceDict,
      sourceUrl: entry.sourceUrl,
    );

    final translation = await _translateWithLlm(
      weblioResult,
      isProblematic: isProblematic,
    );

    if (translation.isEmpty) {
      throw WeblioException('未配置可用 AI 模型或翻译失败，请在设置中检查生词本模型配置');
    }

    final definitionSc = translation['definitionSc'] ?? '';
    final exampleSc1 = translation['exampleSc1'] ?? '';
    final exampleSc2 = translation['exampleSc2'] ?? '';
    var finalDefJa = entry.vocabDefJa;
    var finalReading = entry.vocabFurigana;
    var finalPos = entry.vocabPoS;
    var finalPitch = entry.vocabPitch;

    final aiDefJa = translation['definitionJa'] ?? '';
    if (isProblematic && aiDefJa.isNotEmpty) {
      finalDefJa = aiDefJa;
    }
    final aiPos = translation['partOfSpeech'] ?? '';
    if (aiPos.isNotEmpty) {
      finalPos = normalizePartOfSpeech(aiPos);
    } else {
      finalPos = normalizePartOfSpeech(finalPos);
    }
    if (finalPos.isEmpty && WeblioService.isKatakana(entry.vocabKanji)) {
      finalPos = '名';
    }

    final aiPitch = WeblioService.formatPitchCircle(translation['pitch'] ?? '');
    if (finalPitch.isEmpty && aiPitch.isNotEmpty) {
      finalPitch = aiPitch;
    }

    final aiForeign = translation['foreignOrigin'] ?? '';
    final aiReading = translation['furigana'] ?? '';
    if (WeblioService.isKatakana(entry.vocabKanji)) {
      if (aiForeign.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(aiForeign)) {
        finalReading = aiForeign.trim();
      } else if (finalReading == entry.vocabKanji || finalReading.isEmpty || !RegExp(r'[a-zA-Z]').hasMatch(finalReading)) {
        if (aiReading.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(aiReading)) {
          finalReading = aiReading.trim();
        }
      }
    } else {
      if ((finalReading.isEmpty || finalReading == entry.vocabKanji) &&
          aiReading.isNotEmpty) {
        finalReading = WeblioService.cleanReading(aiReading);
      }
    }

    var updated = entry.copyWith(
      vocabFurigana: finalReading,
      vocabPitch: finalPitch,
      vocabDefJa: finalDefJa,
      vocabDefSc: definitionSc.isNotEmpty ? definitionSc : entry.vocabDefSc,
      vocabPoS: finalPos,
      sentDefSc1: exampleSc1.isNotEmpty ? exampleSc1 : entry.sentDefSc1,
      sentDefSc2: exampleSc2.isNotEmpty ? exampleSc2 : entry.sentDefSc2,
    );

    if (updated.id != null) {
      await vocabularyDao.update(updated);
    } else {
      final existing = await vocabularyDao.findByKanji(updated.vocabKanji);
      if (existing?.id != null) {
        updated = updated.copyWith(id: existing!.id);
        await vocabularyDao.update(updated);
      }
    }
    return updated;
  }

  /// 判断词性标记是否属于传统日日辞书语法（如 動サ五（四）、動バ下一、動ラ五 等）
  static bool isTraditionalVerbPoS(String pos) {
    final p = pos.trim();
    if (p.isEmpty) return false;
    if (p.contains('他動') || p.contains('自動')) return false;
    return p.contains('（') ||
        p.contains('(') ||
        p.contains('動サ') ||
        p.contains('動バ') ||
        p.contains('動カ') ||
        p.contains('動マ') ||
        p.contains('動ラ') ||
        p.contains('動タ') ||
        p.contains('動ワ') ||
        p.contains('動ガ') ||
        p.contains('下一') ||
        p.contains('上一') ||
        p.contains('五段') ||
        p.contains('四段');
  }

  /// 规范化词性为日本语学习者标准词性（如 他動1、他動2、他動3、自動1、自動2、自動3、名、副、形、形動）
  static String normalizePartOfSpeech(String rawPos) {
    final p = rawPos.trim().replaceAll(RegExp(r'[\s\[\]［］]'), '');
    if (p.isEmpty) return '';

    // 纠正错误或历史遗留的“他動5 / 自動5”
    if (p == '他動5' || p == '他動五') return '他動1';
    if (p == '自動5' || p == '自動五') return '自動1';
    if (p == '自他動5' || p == '自他動五') return '自他動1';

    // 若已经是标准学习者词性，直接规范返回
    if (p == '他動1' || p == '自動1' || p == '自他動1' ||
        p == '他動2' || p == '自動2' || p == '自他動2' ||
        p == '他動3' || p == '自動3' || p == '自他動3') {
      return p;
    }

    if (p.startsWith('名') || p == '名詞') return '名';
    if (p.startsWith('副') || p == '副詞') return '副';
    if (p.startsWith('形動') || p == '形容動詞') return '形動';
    if (p.startsWith('形') || p == '形容詞') return '形';
    if (p.startsWith('接続') || p == '接続詞') return '接続';
    if (p.startsWith('感') || p == '感動詞') return '感';
    if (p.startsWith('連体') || p == '連体詞') return '連体';
    if (p.startsWith('助') || p == '助詞') return '助';

    // 1类动词（五段活用、四段活用）：他動1、自動1、自他動1
    if (p.contains('五') || p.contains('四') || p.contains('1类') || p.contains('１类') || p.contains('I类') || p.contains('Ⅰ类')) {
      if (p.contains('自他')) return '自他動1';
      if (p.contains('自')) return '自動1';
      return '他動1';
    }

    // 2类动词（一段活用、上一段、下一段）：他動2、自動2、自他動2
    if (p.contains('下一') || p.contains('上一') || p.contains('一段') || p.contains('2类') || p.contains('２类') || p.contains('II类') || p.contains('Ⅱ类')) {
      if (p.contains('自他')) return '自他動2';
      if (p.contains('自')) return '自動2';
      return '他動2';
    }

    // 3类动词（サ行変格活用、サ変）：他動3、自動3、自他動3、動サ変
    if (p.contains('サ変') || p.contains('サ行') || p.contains('3类') || p.contains('３类') || p.contains('III类') || p.contains('Ⅲ类')) {
      if (p.contains('自他')) return '自他動3';
      if (p.contains('自')) return '自動3';
      if (p.contains('他')) return '他動3';
      return '動サ変';
    }

    // カ行変格活用
    if (p.contains('カ変') || p.contains('カ行')) {
      if (p.contains('自他')) return '自他動3';
      if (p.contains('自')) return '自動3';
      if (p.contains('他')) return '他動3';
      return '動カ変';
    }

    if (p.startsWith('他動') || p.startsWith('自動') || p.startsWith('自他動')) {
      return p;
    }

    return p;
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
        'pitch': decoded['pitch']?.toString().trim() ?? '',
        'furigana': decoded['furigana']?.toString().trim() ?? '',
        'foreignOrigin': decoded['foreignOrigin']?.toString().trim() ?? '',
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
        'pitch': '',
        'furigana': '',
        'foreignOrigin': '',
        'exampleSc1': '',
        'exampleSc2': '',
      };
    }
  }
}
