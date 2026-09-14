import 'dart:io';
import 'package:ankidroid_for_flutter/ankidroid_for_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vocabulary_entry.dart';
import 'anki_export_service_interface.dart';
import 'weblio_service.dart';

export 'anki_export_service_interface.dart';

/// AnkiDroid 底层操作抽象网桥（方便在单元测试与桌面环境进行纯内存 Mock）
abstract class AnkidroidBridge {
  bool get isPlatformSupported;
  Future<bool> requestPermission();
  Future<void> init();
  Future<Map<int, String>> getDeckList();
  Future<int> addNewDeck(String name);
  Future<Map<int, String>> getModelList();
  Future<List<String>> getFieldList(int modelId);
  Future<int> addNewCustomModel({
    required String name,
    required List<String> fields,
    required List<String> cards,
    required List<String> qfmt,
    required List<String> afmt,
    String css = '',
    int? did,
    int? sortf,
  });
  Future<List<dynamic>> findDuplicateNotesWithKey(int mid, String key);
  Future<int> addNote({
    required int mid,
    required int did,
    required List<String> fields,
    required List<String> tags,
  });
  Future<void> dispose();
}

/// 基于 ankidroid_for_flutter 的真实原生网桥
class NativeAnkidroidBridge implements AnkidroidBridge {
  Ankidroid? _isolate;

  @override
  bool get isPlatformSupported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!isPlatformSupported) return false;
    try {
      return await Ankidroid.askForPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> init() async {
    if (!isPlatformSupported) {
      throw UnsupportedError('AnkiDroid 仅支持 Android 平台');
    }
    _isolate ??= await Ankidroid.createAnkiIsolate();
  }

  @override
  Future<Map<int, String>> getDeckList() async {
    await init();
    final result = await _isolate!.deckList();
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    final map = result.asValue?.value;
    if (map == null) return {};
    final res = <int, String>{};
    map.forEach((k, v) {
      final id = k is int ? k : int.tryParse(k.toString());
      if (id != null) {
        res[id] = v.toString();
      }
    });
    return res;
  }

  @override
  Future<int> addNewDeck(String name) async {
    await init();
    final result = await _isolate!.addNewDeck(name);
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    return result.asValue!.value;
  }

  @override
  Future<Map<int, String>> getModelList() async {
    await init();
    final result = await _isolate!.modelList();
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    final map = result.asValue?.value;
    if (map == null) return {};
    final res = <int, String>{};
    map.forEach((k, v) {
      final id = k is int ? k : int.tryParse(k.toString());
      if (id != null) {
        res[id] = v.toString();
      }
    });
    return res;
  }

  @override
  Future<List<String>> getFieldList(int modelId) async {
    await init();
    final result = await _isolate!.getFieldList(modelId);
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    final list = result.asValue?.value;
    if (list == null) return [];
    return list.map((e) => e.toString()).toList();
  }

  @override
  Future<int> addNewCustomModel({
    required String name,
    required List<String> fields,
    required List<String> cards,
    required List<String> qfmt,
    required List<String> afmt,
    String css = '',
    int? did,
    int? sortf,
  }) async {
    await init();
    final result = await _isolate!.addNewCustomModel(
      name,
      fields,
      cards,
      qfmt,
      afmt,
      css,
      did,
      sortf,
    );
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    return result.asValue!.value;
  }

  @override
  Future<List<dynamic>> findDuplicateNotesWithKey(int mid, String key) async {
    await init();
    final result = await _isolate!.findDuplicateNotesWithKey(mid, key);
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    return result.asValue!.value;
  }

  @override
  Future<int> addNote({
    required int mid,
    required int did,
    required List<String> fields,
    required List<String> tags,
  }) async {
    await init();
    final result = await _isolate!.addNote(mid, did, fields, tags);
    if (result.isError) {
      throw Exception(result.asError!.error.toString());
    }
    return result.asValue!.value;
  }

  @override
  Future<void> dispose() async {
    try {
      _isolate?.killIsolate();
      _isolate = null;
    } catch (_) {}
  }
}

/// AnkiDroid 导出生词服务核心实现类
class AnkiExportService implements AnkiExportServiceInterface {
  static const String defaultDeckName = '日语生词本';
  static const String defaultModelName = '日语生词本-AI';

  /// 13 个标准 Anki 卡片字段（首字段为唯一主键 VocabKanji，确保 AnkiDroid 重复检测与卡片标题精准匹配）
  static const List<String> ankiFields = [
    'VocabKanji',
    'VocabFurigana',
    'VocabPoS',
    'VocabDefSC',
    'VocabDefJa',
    'SentKanji1',
    'SentFurigana1',
    'SentDefSC1',
    'SentKanji2',
    'SentFurigana2',
    'SentDefSC2',
    'SourceDict',
    'NoteID',
  ];

  static const String defaultQfmt = '''
<main id="FrontSide" class="CardSide">
  <div class="Top">
    <span class="Level">{{Tags}}</span>
  </div>
  <header class="Question">
    <h1 class="VocabKanji">
      <span lang="ja">{{furigana:VocabKanji}}</span>
    </h1>
  </header>
  <ul class="SentenceList">
    {{#SentKanji1}}
    <li class="Sentence">
      <h3 class="SentKanji" lang="ja">
        {{#SentFurigana1}}{{kanji:SentFurigana1}}{{/SentFurigana1}}
        {{^SentFurigana1}}{{kanji:SentKanji1}}{{/SentFurigana1}}
      </h3>
    </li>
    {{/SentKanji1}}
    {{#SentKanji2}}
    <li class="Sentence">
      <h3 class="SentKanji" lang="ja">
        {{#SentFurigana2}}{{kanji:SentFurigana2}}{{/SentFurigana2}}
        {{^SentFurigana2}}{{kanji:SentKanji2}}{{/SentFurigana2}}
      </h3>
    </li>
    {{/SentKanji2}}
  </ul>
</main>
''';

  static const String defaultAfmt = '''
{{FrontSide}}
<hr id="answer">
<main id="BackSide" class="CardSide">
  <section class="Answer">
    <h2 class="VocabFurigana">
      <span lang="ja">{{kana:VocabFurigana}}</span>
    </h2>
    <h3 class="VocabPoS">
      <span class="VocabDef">{{#VocabPoS}}[{{VocabPoS}}] {{/VocabPoS}}{{VocabDefSC}}</span>
    </h3>
    {{#VocabDefJa}}
    <p class="VocabDefJa" style="color: #666; font-size: 0.9em; margin: 4px 0;">{{VocabDefJa}}</p>
    {{/VocabDefJa}}
  </section>
  <ul class="SentenceList">
    {{#SentKanji1}}
    <li class="Sentence">
      <div class="SentGroup">
        <h3 class="SentFurigana" lang="ja">
          {{#SentFurigana1}}{{furigana:SentFurigana1}}{{/SentFurigana1}}
          {{^SentFurigana1}}{{furigana:SentKanji1}}{{/SentFurigana1}}
        </h3>
        <h3 class="SentDef">{{SentDefSC1}}</h3>
      </div>
    </li>
    {{/SentKanji1}}
    {{#SentKanji2}}
    <li class="Sentence">
      <div class="SentGroup">
        <h3 class="SentFurigana" lang="ja">
          {{#SentFurigana2}}{{furigana:SentFurigana2}}{{/SentFurigana2}}
          {{^SentFurigana2}}{{furigana:SentKanji2}}{{/SentFurigana2}}
        </h3>
        <h3 class="SentDef">{{SentDefSC2}}</h3>
      </div>
    </li>
    {{/SentKanji2}}
  </ul>
</main>
''';

  static const String defaultCss = '''
.card {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  font-size: 18px;
  text-align: center;
  color: #212121;
  background-color: #ffffff;
  padding: 16px;
}
.Top { margin-bottom: 12px; }
.Level {
  display: inline-block;
  padding: 2px 8px;
  background: #e0f2fe;
  color: #0369a1;
  border-radius: 4px;
  font-size: 0.75em;
  font-weight: bold;
}
.VocabKanji { font-size: 1.8em; margin: 12px 0; }
ruby rt { font-size: 0.55em; color: #64748b; }
.VocabFurigana { font-size: 1.2em; color: #0284c7; margin: 8px 0; }
.VocabPoS { font-size: 1em; color: #334155; margin: 6px 0; }
.VocabDef, .VocabDefJa { white-space: pre-line; }
.SentenceList { list-style: none; padding: 0; margin: 16px 0; text-align: left; }
.Sentence { margin-bottom: 12px; padding: 8px 12px; background: #f8fafc; border-radius: 8px; }
.SentKanji, .SentFurigana { font-size: 0.95em; margin: 0 0 4px 0; font-weight: normal; color: #0f172a; }
.SentDef { font-size: 0.85em; margin: 0; color: #64748b; font-weight: normal; }
''';

  final AnkidroidBridge _bridge;

  AnkiExportService({AnkidroidBridge? bridge})
      : _bridge = bridge ?? NativeAnkidroidBridge();

  @override
  Future<bool> isAnkiDroidAvailable() async {
    if (!_bridge.isPlatformSupported) return false;
    try {
      return await _bridge.requestPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_bridge.isPlatformSupported) return false;
    try {
      return await _bridge.requestPermission();
    } catch (_) {
      return false;
    }
  }

  static const Set<String> _vocabKanjiAliases = {
    'vocabkanji',
    'vocabularykanji',
    'kanji',
    'word',
    'front',
    'front1',
    'frontside',
    'cardfront',
    'cardfront1',
    'card1front',
    'expression',
    'headword',
    'term',
    'vocab',
    'vocabulary',
    'question',
    'q',
    'japanese',
    'targetword',
    'target',
    '单词',
    '词',
    '表记',
    '词汇',
    '正面',
    '问题',
    '単語',
    '表記',
    '見出し語',
    '見出し',
    '語',
  };

  static const Set<String> _vocabFuriganaAliases = {
    'vocabfurigana',
    'vocabularyfurigana',
    'furigana',
    'reading',
    'kana',
    'hiragana',
    'pronunciation',
    'yomi',
    'vocabreading',
    'vocabularyreading',
    '读音',
    '假名',
    '读法',
    '发音',
    '平假名',
    '平仮名',
    'ひらがな',
    'ふりがな',
    '読み',
    'よみ',
    '振仮名',
    '振り仮名',
  };

  static const Set<String> _vocabPoSAliases = {
    'vocabpos',
    'vocabularypos',
    'pos',
    'partofspeech',
    '词性',
    '品詞',
  };

  static const Set<String> _vocabDefScAliases = {
    'vocabdef',
    'vocabularydef',
    'vocabdefsc',
    'vocabularydefsc',
    'defsc',
    'meaning',
    'meaningsc',
    'scmeaning',
    'definitionsc',
    'scdef',
    'defchinese',
    'meaningchinese',
    'translationchinese',
    'glossary',
    'back',
    'back1',
    'backside',
    'cardback',
    'cardback1',
    'card1back',
    'definition',
    'def',
    'translation',
    'answer',
    'a',
    'meaningcn',
    'defcn',
    'translationcn',
    '释义',
    '中文释义',
    '中文',
    '背面',
    '答案',
    '意味',
    '和訳',
    '中訳',
    '翻訳',
  };

  static const Set<String> _vocabDefJaAliases = {
    'vocabdefja',
    'vocabularydefja',
    'defja',
    'definitionja',
    'meaningja',
    'jameaning',
    'jadef',
    'defjapanese',
    'meaningjapanese',
    'translationjapanese',
    '日日释义',
    '日文释义',
    '日语释义',
    '日日',
    '国語',
    '国語释义',
  };

  static const Set<String> _sentKanji1Aliases = {
    'sentkanji1',
    'sentkanji',
    'sent1kanji',
    'sentence1kanji',
    'sentence1',
    'sentence',
    'example1',
    'example',
    'examplesentence1',
    'examplesentence',
    'sent1',
    'sent',
    '例句1',
    '例句',
    '例文1',
    '例文',
  };

  static const Set<String> _sentFurigana1Aliases = {
    'sentfurigana1',
    'sentfurigana',
    'sent1furigana',
    'sentence1furigana',
    'sentreading1',
    'sentreading',
    'sent1reading',
    'sentencefurigana1',
    'sentencefurigana',
    'sentencereading1',
    'sentencereading',
    'sentence1reading',
    'examplereading1',
    'examplereading',
    '例句假名1',
    '例句假名',
    '例句读音1',
    '例句读音',
    '例文假名1',
    '例文假名',
    '例文読み1',
    '例文読み',
  };

  static const Set<String> _sentDefSc1Aliases = {
    'sentdefsc1',
    'sentdefsc',
    'sent1defsc',
    'sentence1defsc',
    'sentdef1',
    'sentdef',
    'sent1def',
    'senttrans1',
    'senttrans',
    'sent1trans',
    'sentence1trans',
    'sentmeaning1',
    'sentmeaning',
    'sent1meaning',
    'sentence1meaning',
    'examplesentencedef1',
    'examplesentencedef',
    'sentencetranslation1',
    'sentencetranslation',
    'sentence1translation',
    'sentencemeaning',
    'sentencemeaning1',
    'examplemeaning1',
    'examplemeaning',
    'exampletrans1',
    'exampletrans',
    '例句翻译1',
    '例句释义1',
    '例句翻译',
    '例句释义',
    '例文訳1',
    '例文訳',
  };

  static const Set<String> _sentKanji2Aliases = {
    'sentkanji2',
    'sent2kanji',
    'sentence2kanji',
    'sentence2',
    'example2',
    'examplesentence2',
    'sent2',
    '例句2',
    '例文2',
  };

  static const Set<String> _sentFurigana2Aliases = {
    'sentfurigana2',
    'sent2furigana',
    'sentence2furigana',
    'sentreading2',
    'sent2reading',
    'sentencefurigana2',
    'sentencereading2',
    'sentence2reading',
    'examplereading2',
    '例句假名2',
    '例句读音2',
    '例文假名2',
    '例文読み2',
  };

  static const Set<String> _sentDefSc2Aliases = {
    'sentdefsc2',
    'sent2defsc',
    'sentence2defsc',
    'sentdef2',
    'sent2def',
    'senttrans2',
    'sent2trans',
    'sentence2trans',
    'sentmeaning2',
    'sent2meaning',
    'sentence2meaning',
    'examplesentencedef2',
    'sentencetranslation2',
    'sentence2translation',
    'sentencemeaning2',
    'examplemeaning2',
    'exampletrans2',
    '例句翻译2',
    '例句释义2',
    '例文訳2',
  };

  static const Set<String> _sourceDictAliases = {
    'sourcedict',
    'source',
    'dict',
    'dictionary',
    '来源',
    '词典',
    '词典来源',
    '辞書',
    '出典',
  };

  static const Set<String> _noteIdAliases = {
    'noteid',
    'id',
    'uid',
    '编号',
    '卡片编号',
  };

  static const Set<String> _tagsAliases = {
    'tags',
    'tag',
    'level',
    '标签',
    '分类',
    'タグ',
  };

  static const Set<String> _sourceUrlAliases = {
    'sourceurl',
    'url',
    'link',
    '来源链接',
    '链接',
  };

  static const Set<String> _vocabPitchAliases = {
    'vocabpitch',
    'vocabularypitch',
    'pitch',
    'pitchaccent',
    'accent',
    'vocabaccent',
    '声调',
    '音调',
    '音调核',
    '音調',
    'アクセント',
    'アクセント核',
  };

  static const Set<String> _vocabDefTcAliases = {
    'vocabdeftc',
    'vocabularydeftc',
    'deftc',
    'meaningtc',
    'tcmeaning',
    'definitiontc',
    'tcdef',
    'glossarytc',
    'traditionalchinese',
    '繁体',
    '繁体释义',
    '繁体中文',
    '繁體',
    '繁體釋義',
    '繁體中文',
  };

  static const Set<String> _vocabPlusAliases = {
    'vocabplus',
    'vocabularyplus',
    'plus',
    'supplement',
    'addition',
    '补充',
    '补充说明',
    '追記',
  };

  static const Set<String> _vocabAudioAliases = {
    'vocabaudio',
    'vocabularyaudio',
    'audio',
    'sound',
    'sound1',
    'vocabsound',
    'pronunciationsound',
    'wordaudio',
    'wordsound',
    '音频',
    '单词音频',
    '发音音频',
    '音声',
    '発音',
  };

  static const Set<String> _sentType1Aliases = {
    'senttype1',
    'senttype',
    'sentencetype1',
    'sentencetype',
    'type1',
    '例句类型1',
    '例句类型',
  };

  static const Set<String> _sentType2Aliases = {
    'senttype2',
    'sentencetype2',
    'type2',
    '例句类型2',
  };

  static const Set<String> _sentAudio1Aliases = {
    'sentaudio1',
    'sentaudio',
    'sentenceaudio1',
    'sentenceaudio',
    'sentsound1',
    'sentsound',
    'sentencesound1',
    'sentencesound',
    '例句音频1',
    '例句音频',
  };

  static const Set<String> _sentAudio2Aliases = {
    'sentaudio2',
    'sentenceaudio2',
    'sentsound2',
    'sentencesound2',
    '例句音频2',
  };

  static const Set<String> _sentDefTc1Aliases = {
    'sentdeftc1',
    'sent1deftc',
    'sentdeftc',
    'sentencedeftc1',
    'sentence1deftc',
    'senttranstc1',
    'sent1transtc',
    'sentencetranstc1',
    'sentence1transtc',
    '例句繁体1',
    '例句繁体翻译1',
    '例句繁体',
    '例句繁体翻译',
  };

  static const Set<String> _sentDefTc2Aliases = {
    'sentdeftc2',
    'sent2deftc',
    'sentencedeftc2',
    'sentence2deftc',
    'senttranstc2',
    'sent2transtc',
    'sentencetranstc2',
    'sentence2transtc',
    '例句繁体2',
    '例句繁体翻译2',
  };

  /// 根据字段名将 VocabularyEntry 属性精准映射为对应字段值
  /// 彻底废除索引盲目回退，未识别的扩展字段统一安全填充空字符串，防止错位
  static String mapFieldValue(
    String fieldName,
    VocabularyEntry entry, [
    int? fallbackIndex,
  ]) {
    final norm = fieldName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5\u3040-\u30ff\u3400-\u4dbf]'), '');

    if (_vocabPitchAliases.contains(norm)) {
      return entry.vocabPitch;
    }
    if (_vocabKanjiAliases.contains(norm)) {
      return entry.vocabKanji.trim();
    }
    if (_vocabFuriganaAliases.contains(norm)) {
      return entry.vocabFurigana;
    }
    if (_vocabPoSAliases.contains(norm)) {
      return entry.vocabPoS;
    }
    if (_vocabDefScAliases.contains(norm)) {
      return entry.vocabDefSc;
    }
    if (_vocabDefTcAliases.contains(norm)) {
      return '';
    }
    if (_vocabPlusAliases.contains(norm)) {
      return '';
    }
    if (_vocabAudioAliases.contains(norm)) {
      return '';
    }
    if (_vocabDefJaAliases.contains(norm)) {
      return entry.vocabDefJa;
    }
    if (_sentType1Aliases.contains(norm) || _sentType2Aliases.contains(norm)) {
      return '';
    }
    if (_sentAudio1Aliases.contains(norm) || _sentAudio2Aliases.contains(norm)) {
      return '';
    }
    if (_sentDefTc1Aliases.contains(norm) || _sentDefTc2Aliases.contains(norm)) {
      return '';
    }
    if (_sentKanji1Aliases.contains(norm)) {
      return entry.sentKanji1 ?? '';
    }
    if (_sentFurigana1Aliases.contains(norm)) {
      return WeblioService.highlightKeywordInFurigana(
        entry.sentFurigana1 ?? '',
        entry.vocabKanji,
      );
    }
    if (_sentDefSc1Aliases.contains(norm)) {
      return entry.sentDefSc1 ?? '';
    }
    if (_sentKanji2Aliases.contains(norm)) {
      return entry.sentKanji2 ?? '';
    }
    if (_sentFurigana2Aliases.contains(norm)) {
      return WeblioService.highlightKeywordInFurigana(
        entry.sentFurigana2 ?? '',
        entry.vocabKanji,
      );
    }
    if (_sentDefSc2Aliases.contains(norm)) {
      return entry.sentDefSc2 ?? '';
    }
    if (_sourceDictAliases.contains(norm)) {
      return entry.sourceDict;
    }
    if (_noteIdAliases.contains(norm)) {
      return entry.id?.toString() ?? '';
    }
    if (_sourceUrlAliases.contains(norm)) {
      return entry.sourceUrl;
    }
    if (_tagsAliases.contains(norm)) {
      return entry.sourceDict.isNotEmpty ? entry.sourceDict : 'AI生词本';
    }

    // 彻底废除 fallbackIndex 盲目回退！未识别字段一律安全返回空字符串，杜绝错位污染
    return '';
  }

  /// 将单词实体转换为 13 个标准字段列表
  static List<String> entryToFields(VocabularyEntry entry) {
    return [
      entry.vocabKanji.trim(),
      entry.vocabFurigana,
      entry.vocabPoS,
      entry.vocabDefSc,
      entry.vocabDefJa,
      entry.sentKanji1 ?? '',
      WeblioService.highlightKeywordInFurigana(
        entry.sentFurigana1 ?? '',
        entry.vocabKanji,
      ),
      entry.sentDefSc1 ?? '',
      entry.sentKanji2 ?? '',
      WeblioService.highlightKeywordInFurigana(
        entry.sentFurigana2 ?? '',
        entry.vocabKanji,
      ),
      entry.sentDefSc2 ?? '',
      entry.sourceDict,
      entry.id?.toString() ?? '',
    ];
  }

  /// 将单词实体按目标模型实际字段列表动态自适应映射为字段值列表
  static List<String> entryToModelFields(
    VocabularyEntry entry,
    List<String> modelFields,
  ) {
    if (modelFields.isEmpty) {
      return entryToFields(entry);
    }
    return List<String>.generate(
      modelFields.length,
      (index) => mapFieldValue(modelFields[index], entry),
    );
  }

  /// 查找或创建目标牌组，返回 deckId
  Future<int> getOrCreateDeck(String deckName) async {
    final decks = await _bridge.getDeckList();
    for (final entry in decks.entries) {
      if (entry.value.trim() == deckName.trim()) {
        return entry.key;
      }
    }
    return await _bridge.addNewDeck(deckName.trim());
  }

  /// 查找或创建卡片模型，返回 modelId
  Future<int> getOrCreateModel(String modelName) async {
    final models = await _bridge.getModelList();
    for (final entry in models.entries) {
      if (entry.value.trim() == modelName.trim()) {
        return entry.key;
      }
    }
    return await _bridge.addNewCustomModel(
      name: modelName.trim(),
      fields: ankiFields,
      cards: const ['Card 1'],
      qfmt: const [defaultQfmt],
      afmt: const [defaultAfmt],
      css: defaultCss,
      sortf: 0,
    );
  }

  @override
  Future<AnkiExportResult> exportEntries(
    List<VocabularyEntry> entries, {
    String? deckName,
    String? modelName,
  }) async {
    if (entries.isEmpty) {
      return const AnkiExportResult();
    }

    if (!_bridge.isPlatformSupported) {
      return AnkiExportResult(
        failedEntries: entries,
        errors: const ['当前平台不支持 AnkiDroid 导出（仅支持 Android）'],
      );
    }

    final hasPermission = await _bridge.requestPermission();
    if (!hasPermission) {
      return AnkiExportResult(
        failedEntries: entries,
        errors: const ['未获得 AnkiDroid 授权，无法导出'],
      );
    }

    try {
      String targetDeck = (deckName != null && deckName.trim().isNotEmpty)
          ? deckName.trim()
          : '';
      String targetModel = (modelName != null && modelName.trim().isNotEmpty)
          ? modelName.trim()
          : '';

      if (targetDeck.isEmpty || targetModel.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (targetDeck.isEmpty) {
            targetDeck = prefs.getString('anki_deck_name') ?? defaultDeckName;
          }
          if (targetModel.isEmpty) {
            targetModel = prefs.getString('anki_model_name') ?? defaultModelName;
          }
        } catch (_) {
          if (targetDeck.isEmpty) targetDeck = defaultDeckName;
          if (targetModel.isEmpty) targetModel = defaultModelName;
        }
      }

      final deckId = await getOrCreateDeck(targetDeck);
      final modelId = await getOrCreateModel(targetModel);

      List<String> modelFields;
      try {
        modelFields = await _bridge.getFieldList(modelId);
        if (modelFields.isEmpty) {
          modelFields = ankiFields;
        }
      } catch (_) {
        modelFields = ankiFields;
      }

      int successCount = 0;
      int skipCount = 0;
      final failedEntries = <VocabularyEntry>[];
      final errors = <String>[];
      final seenWordsInBatch = <String>{};

      for (final entry in entries) {
        final cleanKanji = entry.vocabKanji.trim();
        if (cleanKanji.isEmpty) continue;

        try {
          // 批次内去重（避免单次导出列表中含有同名词）
          if (seenWordsInBatch.contains(cleanKanji)) {
            skipCount++;
            continue;
          }

          // 查重键自适应：优先取目标模型首字段对应的值，回退为 cleanKanji
          final duplicateKey = (modelFields.isNotEmpty
                  ? mapFieldValue(modelFields.first, entry, 0)
                  : cleanKanji)
              .trim();
          final keyToCheck =
              duplicateKey.isNotEmpty ? duplicateKey : cleanKanji;

          // AnkiDroid 原生去重检测（以首字段为键，查询 AnkiDroid 是否已有同名卡片）
          bool isDuplicate = false;
          try {
            final dupes = await _bridge.findDuplicateNotesWithKey(
              modelId,
              keyToCheck,
            );
            if (dupes.isNotEmpty) {
              isDuplicate = true;
            }
          } catch (_) {
            // 重复检测异常不阻断正常创建流程
          }

          if (isDuplicate) {
            seenWordsInBatch.add(cleanKanji);
            skipCount++;
            continue;
          }

          final fields = entryToModelFields(entry, modelFields);
          final tags = [
            'AI生词本',
            if (entry.sourceDict.isNotEmpty) entry.sourceDict,
          ];

          await _bridge.addNote(
            mid: modelId,
            did: deckId,
            fields: fields,
            tags: tags,
          );
          seenWordsInBatch.add(cleanKanji);
          successCount++;
        } catch (e) {
          failedEntries.add(entry);
          final errorMsg = '「${entry.vocabKanji}」导出失败: $e';
          if (!errors.contains(errorMsg)) {
            errors.add(errorMsg);
          }
        }
      }

      return AnkiExportResult(
        successCount: successCount,
        skipCount: skipCount,
        failedEntries: failedEntries,
        errors: errors,
      );
    } catch (e) {
      return AnkiExportResult(
        failedEntries: entries,
        errors: ['AnkiDroid 导出异常: $e'],
      );
    } finally {
      await _bridge.dispose();
    }
  }
}
