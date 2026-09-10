import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api_config_dao.dart';
import '../data/vocabulary_dao.dart';
import '../models/chat_message.dart';
import '../models/vocabulary_entry.dart';
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

  /// 查词主流程：
  /// 1. 优先检索本地数据库，若已存在直接返回（缓存命中去重）
  /// 2. 调用 Weblio 抓取日语释义、词性与例句
  /// 3. 若配置了 LLM，则调用大模型翻译为简体中文；若未配置则降级留空
  /// 4. 存入 SQLite 并返回
  Future<VocabularyEntry> lookupWord(String rawWord, {bool forceRefresh = false}) async {
    final word = rawWord.trim();
    if (word.isEmpty) {
      throw WeblioException('查询单词不能为空');
    }

    // 1. 本地缓存命中检查
    if (!forceRefresh) {
      final cached = await vocabularyDao.findByKanji(word);
      if (cached != null) {
        return cached;
      }
    }

    // 2. Weblio 抓取
    final weblioResult = await weblioService.lookupWord(word);

    // 3. LLM 翻译（如果可用）
    String definitionSc = '';
    String exampleSc1 = '';
    String exampleSc2 = '';

    try {
      final translation = await _translateWithLlm(weblioResult);
      definitionSc = translation['definitionSc'] ?? '';
      exampleSc1 = translation['exampleSc1'] ?? '';
      exampleSc2 = translation['exampleSc2'] ?? '';
    } catch (_) {
      // 优雅降级：LLM 异常或未配置时不中断查词主流程，仅中文留空
    }

    // 4. 构建并持久化
    final entry = VocabularyEntry(
      vocabKanji: weblioResult.word,
      vocabFurigana: weblioResult.reading,
      vocabDefJa: weblioResult.definition,
      vocabDefSc: definitionSc,
      vocabPoS: weblioResult.partOfSpeech,
      sentKanji1: weblioResult.examples.isNotEmpty ? weblioResult.examples[0].kanji : null,
      sentFurigana1: weblioResult.examples.isNotEmpty ? weblioResult.examples[0].furigana : null,
      sentDefSc1: exampleSc1.isNotEmpty ? exampleSc1 : null,
      sentKanji2: weblioResult.examples.length > 1 ? weblioResult.examples[1].kanji : null,
      sentFurigana2: weblioResult.examples.length > 1 ? weblioResult.examples[1].furigana : null,
      sentDefSc2: exampleSc2.isNotEmpty ? exampleSc2 : null,
      sourceDict: weblioResult.sourceDict,
      sourceUrl: weblioResult.sourceUrl,
      createdAt: DateTime.now(),
    );

    final insertedId = await vocabularyDao.insert(entry);
    return entry.copyWith(id: insertedId);
  }

  /// 调用 LLM 翻译释义与例句
  Future<Map<String, String>> _translateWithLlm(WeblioResult result) async {
    final currentRef = ref;
    if (currentRef == null) return {};

    final activeConfig = currentRef.read(apiConfigProvider).activeConfig;
    final selectedModel = currentRef.read(modelProvider).selectedModel;

    if (activeConfig == null || selectedModel == null) {
      return {};
    }

    final apiKey = await apiConfigDao.getApiKey(activeConfig.apiKeyRef) ?? '';

    final ex1 = result.examples.isNotEmpty ? result.examples[0].kanji : '';
    final ex2 = result.examples.length > 1 ? result.examples[1].kanji : '';

    final prompt = '''
你是一位专业的日语翻译助手。请将以下日语单词的释义和例句翻译为简体中文。
要求：
1. 释义翻译简明扼要，保留原有的数字编号格式。
2. 例句翻译通顺自然。
3. 请严格按照以下 JSON 格式输出，不要包含任何 markdown 代码块或解释说明：
{
  "definitionSc": "中文释义",
  "exampleSc1": "例句1中文翻译（若无例句留空字符串）",
  "exampleSc2": "例句2中文翻译（若无例句留空字符串）"
}

日语单词：${result.word}
假名读音：${result.reading}
词性：${result.partOfSpeech}
日语释义：
${result.definition}
例句1：$ex1
例句2：$ex2
''';

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

  /// 解析 LLM 返回的 JSON 内容，具备容错处理
  Map<String, String> parseTranslationJson(String content) {
    var raw = content.trim();
    if (raw.startsWith('```')) {
      final lines = raw.split('\n');
      if (lines.length > 2) {
        raw = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'definitionSc': decoded['definitionSc']?.toString().trim() ?? '',
        'exampleSc1': decoded['exampleSc1']?.toString().trim() ?? '',
        'exampleSc2': decoded['exampleSc2']?.toString().trim() ?? '',
      };
    } catch (_) {
      // 容错：直接将整段文本作为释义
      return {
        'definitionSc': content.trim(),
        'exampleSc1': '',
        'exampleSc2': '',
      };
    }
  }
}
