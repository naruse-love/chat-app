import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chat/models/vocabulary_entry.dart';
import 'package:chat/services/anki_export_service.dart';

/// 模拟可控的 AnkidroidBridge 用于全面单元测试
class MockAnkidroidBridge implements AnkidroidBridge {
  bool platformSupported = true;
  bool permissionGranted = true;
  bool initCalled = false;
  bool disposed = false;

  Map<int, String> decks = {1: '默认牌组'};
  Map<int, String> models = {1: '默认模型'};
  int nextDeckId = 10;
  int nextModelId = 20;
  int nextNoteId = 100;

  List<String> duplicateKeys = [];
  Map<String, dynamic> lastAddedNote = {};
  bool throwOnAddNote = false;
  String? throwOnWord;

  @override
  bool get isPlatformSupported => platformSupported;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> init() async {
    initCalled = true;
  }

  @override
  Future<Map<int, String>> getDeckList() async => Map.from(decks);

  @override
  Future<int> addNewDeck(String name) async {
    final id = nextDeckId++;
    decks[id] = name;
    return id;
  }

  Map<int, List<String>> modelFields = {};
  int? lastSortf;

  @override
  Future<Map<int, String>> getModelList() async => Map.from(models);

  @override
  Future<List<String>> getFieldList(int modelId) async {
    return List.from(modelFields[modelId] ?? AnkiExportService.ankiFields);
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
    final id = nextModelId++;
    models[id] = name;
    modelFields[id] = List.from(fields);
    lastSortf = sortf;
    return id;
  }

  @override
  Future<List<dynamic>> findDuplicateNotesWithKey(int mid, String key) async {
    // 模拟真实 AnkiDroid 底层：按目标模型首字段比对 key
    final fields = modelFields[mid] ?? AnkiExportService.ankiFields;
    if (fields.isNotEmpty && duplicateKeys.contains(key)) {
      return [
        {'id': 999, 'key': key}
      ];
    }
    return [];
  }

  @override
  Future<int> addNote({
    required int mid,
    required int did,
    required List<String> fields,
    required List<String> tags,
  }) async {
    if (throwOnAddNote) {
      throw Exception('模拟添加卡片失败');
    }
    if (throwOnWord != null && fields.contains(throwOnWord)) {
      throw Exception('针对单词「$throwOnWord」的模拟错误');
    }
    // 仿真真实 AnkiDroid 底层：严格校验传入字段数与 Model 字段数一致
    final expectedFields = modelFields[mid] ?? AnkiExportService.ankiFields;
    if (fields.length != expectedFields.length) {
      throw ArgumentError(
        'Incorrect flds argument : expected ${expectedFields.length}, got ${fields.length}',
      );
    }
    lastAddedNote = {
      'mid': mid,
      'did': did,
      'fields': fields,
      'tags': tags,
    };
    return nextNoteId++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  group('AnkiExportService Unit Tests', () {
    final now = DateTime(2026, 9, 14, 12, 0);
    final sampleEntry = VocabularyEntry(
      id: 7,
      vocabKanji: '青空',
      vocabFurigana: 'あおぞら',
      vocabDefJa: '晴れ渡った青い空。',
      vocabDefSc: '蔚蓝的天空；晴空。',
      vocabPoS: '名',
      sentKanji1: '青空が広がる',
      sentFurigana1: '青空[あおぞら]が 広[ひろ]がる',
      sentDefSc1: '晴空万里',
      sentKanji2: '青空の下で',
      sentFurigana2: '青空[あおぞら]の 下[した]で',
      sentDefSc2: '在蓝天下',
      sourceDict: 'デジタル大辞泉',
      sourceUrl: 'https://weblio.jp/content/青空',
      createdAt: now,
    );

    test('ankiFields has VocabKanji as first field for AnkiDroid duplicate key alignment', () {
      expect(AnkiExportService.ankiFields.first, 'VocabKanji');
      expect(AnkiExportService.ankiFields.length, 13);
      expect(AnkiExportService.ankiFields, contains('NoteID'));
      expect(AnkiExportService.ankiFields.contains('Tags'), isFalse);
    });

    test('entryToFields maps VocabularyEntry to exact 13 fields correctly with VocabKanji first', () {
      final fields = AnkiExportService.entryToFields(sampleEntry);
      expect(fields.length, 13);
      expect(fields[0], '青空'); // VocabKanji (first field for Anki duplicate key)
      expect(fields[1], 'あおぞら'); // VocabFurigana
      expect(fields[2], '名'); // VocabPoS
      expect(fields[3], '蔚蓝的天空；晴空。'); // VocabDefSC
      expect(fields[4], '晴れ渡った青い空。'); // VocabDefJa
      expect(fields[5], '青空が広がる'); // SentKanji1
      expect(fields[6], '<b>青空[あおぞら]</b>が 広[ひろ]がる'); // SentFurigana1 (keyword bolded)
      expect(fields[7], '晴空万里'); // SentDefSC1
      expect(fields[8], '青空の下で'); // SentKanji2
      expect(fields[9], '<b>青空[あおぞら]</b>の 下[した]で'); // SentFurigana2 (keyword bolded)
      expect(fields[10], '在蓝天下'); // SentDefSC2
      expect(fields[11], 'デジタル大辞泉'); // SourceDict
      expect(fields[12], '7'); // NoteID
    });

    test('entryToFields handles null id and optional fields gracefully', () {
      final minimalEntry = VocabularyEntry(
        vocabKanji: '猫',
        createdAt: DateTime(2026, 9, 14),
      );
      final fields = AnkiExportService.entryToFields(minimalEntry);
      expect(fields.length, 13);
      expect(fields[0], '猫'); // VocabKanji
      expect(fields[5], ''); // SentKanji1 empty
      expect(fields[12], ''); // NoteID empty
    });

    test('exportEntries returns error when platform is not supported', () async {
      final bridge = MockAnkidroidBridge()..platformSupported = false;
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries([sampleEntry]);
      expect(result.isSuccess, isFalse);
      expect(result.successCount, 0);
      expect(result.failedEntries.length, 1);
      expect(result.errors.first, contains('当前平台不支持'));
    });

    test('exportEntries returns error when permission is denied', () async {
      final bridge = MockAnkidroidBridge()..permissionGranted = false;
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries([sampleEntry]);
      expect(result.isSuccess, isFalse);
      expect(result.successCount, 0);
      expect(result.failedEntries.length, 1);
      expect(result.errors.first, contains('未获得 AnkiDroid 授权'));
    });

    test('exportEntries returns empty result when entries list is empty', () async {
      final bridge = MockAnkidroidBridge();
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries([]);
      expect(result.totalProcessed, 0);
      expect(result.isSuccess, isTrue);
    });

    test('exportEntries creates deck and model when they do not exist', () async {
      final bridge = MockAnkidroidBridge();
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries(
        [sampleEntry],
        deckName: '新日语牌组',
        modelName: '新日语模型',
      );

      expect(result.isSuccess, isTrue);
      expect(result.successCount, 1);
      expect(result.skipCount, 0);
      expect(result.failedEntries.isEmpty, isTrue);

      expect(bridge.decks.values, contains('新日语牌组'));
      expect(bridge.models.values, contains('新日语模型'));
      expect(bridge.lastSortf, 0); // sortf: 0 for VocabKanji primary sorting
      expect(bridge.lastAddedNote['fields'][0], '青空'); // VocabKanji is field 0
      expect(bridge.disposed, isTrue);
    });

    test('exportEntries reuses existing deck and model when already present', () async {
      final bridge = MockAnkidroidBridge()
        ..decks[5] = '已有牌组'
        ..models[6] = '已有模型';
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries(
        [sampleEntry],
        deckName: '已有牌组',
        modelName: '已有模型',
      );

      expect(result.successCount, 1);
      expect(bridge.lastAddedNote['did'], 5);
      expect(bridge.lastAddedNote['mid'], 6);
    });

    test('exportEntries skips duplicate notes existing in AnkiDroid', () async {
      final bridge = MockAnkidroidBridge()..duplicateKeys = ['青空'];
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries([sampleEntry]);
      expect(result.successCount, 0);
      expect(result.skipCount, 1);
      expect(result.failedEntries.isEmpty, isTrue);
      expect(result.isSuccess, isTrue);
    });

    test('exportEntries performs in-batch deduplication for duplicate words in same batch', () async {
      final bridge = MockAnkidroidBridge();
      final service = AnkiExportService(bridge: bridge);

      final duplicateEntry1 = sampleEntry.copyWith(id: 1, vocabKanji: '青空');
      final duplicateEntry2 = sampleEntry.copyWith(id: 2, vocabKanji: '青空');
      final uniqueEntry = sampleEntry.copyWith(id: 3, vocabKanji: '星空');

      final result = await service.exportEntries([duplicateEntry1, duplicateEntry2, uniqueEntry]);
      expect(result.successCount, 2); // 1 青空 + 1 星空
      expect(result.skipCount, 1); // 1 duplicate 青空 skipped
      expect(result.failedEntries.isEmpty, isTrue);
      expect(result.isSuccess, isTrue);
    });

    test('exportEntries handles partial failure gracefully', () async {
      final bridge = MockAnkidroidBridge()..throwOnWord = '青空';
      final service = AnkiExportService(bridge: bridge);

      final entry2 = sampleEntry.copyWith(id: 8, vocabKanji: '星空');
      final result = await service.exportEntries([sampleEntry, entry2]);

      expect(result.successCount, 1);
      expect(result.failedEntries.length, 1);
      expect(result.failedEntries.first.vocabKanji, '青空');
      expect(result.errors.length, 1);
      expect(result.isSuccess, isFalse);
      expect(result.totalProcessed, 2);
    });

    test('AnkiExportResult toString and helper getters work as expected', () {
      final res = AnkiExportResult(
        successCount: 3,
        skipCount: 2,
        failedEntries: [sampleEntry],
        errors: const ['错误1'],
      );
      expect(res.totalProcessed, 6);
      expect(res.isSuccess, isFalse);
      expect(res.toString(), contains('success: 3'));
      expect(res.toString(), contains('skipped: 2'));
    });

    test('entryToModelFields adapts to 13-field standard model', () {
      final fields = AnkiExportService.entryToModelFields(
        sampleEntry,
        AnkiExportService.ankiFields,
      );
      expect(fields.length, 13);
      expect(fields[0], '青空');
      expect(fields[1], 'あおぞら');
      expect(fields[2], '名');
      expect(fields[3], '蔚蓝的天空；晴空。');
      expect(fields[4], '晴れ渡った青い空。');
      expect(fields[11], 'デジタル大辞泉');
      expect(fields[12], '7');
    });

    test('entryToModelFields adapts to 14-field legacy model containing Tags', () {
      final legacy14Fields = [...AnkiExportService.ankiFields, 'Tags'];
      final fields = AnkiExportService.entryToModelFields(
        sampleEntry,
        legacy14Fields,
      );
      expect(fields.length, 14);
      expect(fields[0], '青空');
      expect(fields[12], '7');
      expect(fields[13], 'デジタル大辞泉');
    });

    test('entryToModelFields adapts to 2-field Basic model (Front, Back)', () {
      final fields = AnkiExportService.entryToModelFields(
        sampleEntry,
        ['Front', 'Back'],
      );
      expect(fields.length, 2);
      expect(fields[0], '青空');
      expect(fields[1], '蔚蓝的天空；晴空。');
    });

    test('entryToModelFields handles case-insensitive aliases and unknown fields map to empty string without misalignment', () {
      final mixedFields = [
        'kanji',
        'READING',
        'pos',
        'meaning',
        'example1',
        'sentencefurigana1',
        'senttrans1',
        'UNKNOWN_POS_7',
        'UNKNOWN_POS_8',
      ];
      final fields = AnkiExportService.entryToModelFields(
        sampleEntry,
        mixedFields,
      );
      expect(fields.length, 9);
      expect(fields[0], '青空'); // kanji alias
      expect(fields[1], 'あおぞら'); // READING alias
      expect(fields[2], '名'); // pos alias
      expect(fields[3], '蔚蓝的天空；晴空。'); // meaning alias
      expect(fields[4], '青空が広がる'); // example1 alias
      expect(fields[5], '<b>青空[あおぞら]</b>が 広[ひろ]がる'); // sentencefurigana1 alias (keyword bolded)
      expect(fields[6], '晴空万里'); // senttrans1 alias
      expect(fields[7], ''); // Zero misalignment: UNKNOWN_POS_7 safely maps to empty string
      expect(fields[8], ''); // Zero misalignment: UNKNOWN_POS_8 safely maps to empty string
    });

    test('entryToModelFields accurately aligns with user custom template fields without misalignments', () {
      final itomoEntry = VocabularyEntry(
        id: 1,
        vocabKanji: 'いとも',
        vocabFurigana: 'いとも',
        vocabPitch: '①',
        vocabPoS: '副',
        vocabDefSc: '非常，十分，很',
        vocabDefJa: '非常に。たいそう。まったく。',
        sentKanji1: 'いとも簡単にやってのけた',
        sentFurigana1: 'いとも 簡単[かんたん]にやってのけた',
        sentDefSc1: '轻而易举地完成',
        createdAt: now,
      );

      final userTemplateFields = [
        'VocabKanji',
        'VocabPitch',
        'VocabPoS',
        'VocabFurigana',
        'VocabDefSC',
        'VocabDefTC',
        'VocabPlus',
        'VocabAudio',
        'SentType1',
        'SentKanji1',
        'SentFurigana1',
        'SentDefSC1',
        'SentDefTC1',
      ];

      final mapped = AnkiExportService.entryToModelFields(itomoEntry, userTemplateFields);

      expect(mapped.length, 13);
      expect(mapped[0], 'いとも'); // VocabKanji
      expect(mapped[1], '①'); // VocabPitch correctly extracted and preserved!
      expect(mapped[2], '副'); // VocabPoS
      expect(mapped[3], 'いとも'); // VocabFurigana (cleaned)
      expect(mapped[4], '非常，十分，很'); // VocabDefSC
      expect(mapped[5], ''); // VocabDefTC: empty, NOT poisoned with SentKanji1!
      expect(mapped[6], '非常に。たいそう。まったく。'); // VocabPlus: correctly maps to vocabDefJa (original Japanese definition)!
      expect(mapped[7], ''); // VocabAudio: empty, NOT poisoned with SentKanji2!
      expect(mapped[8], ''); // SentType1: empty, NOT poisoned!
      expect(mapped[9], 'いとも簡単にやってのけた'); // SentKanji1
      expect(mapped[10], '<b>いとも</b> 簡単[かんたん]にやってのけた'); // SentFurigana1 (keyword bolded)
      expect(mapped[11], '轻而易举地完成'); // SentDefSC1
      expect(mapped[12], ''); // SentDefTC1: empty, NOT poisoned!
    });

    test('exportEntries dynamically queries getFieldList and exports 2-field Basic model without error', () async {
      final bridge = MockAnkidroidBridge()
        ..models[50] = '基础问答卡片'
        ..modelFields[50] = ['Front', 'Back'];
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries(
        [sampleEntry],
        modelName: '基础问答卡片',
      );

      expect(result.isSuccess, isTrue);
      expect(result.successCount, 1);
      expect(bridge.lastAddedNote['mid'], 50);
      expect(bridge.lastAddedNote['fields'].length, 2);
      expect(bridge.lastAddedNote['fields'][0], '青空');
      expect(bridge.lastAddedNote['fields'][1], '蔚蓝的天空；晴空。');
    });

    test('exportEntries dynamically queries getFieldList and exports 14-field legacy model containing Tags without error', () async {
      final bridge = MockAnkidroidBridge()
        ..models[60] = '历史14字段模型'
        ..modelFields[60] = [...AnkiExportService.ankiFields, 'Tags'];
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries(
        [sampleEntry],
        modelName: '历史14字段模型',
      );

      expect(result.isSuccess, isTrue);
      expect(result.successCount, 1);
      expect(bridge.lastAddedNote['mid'], 60);
      expect(bridge.lastAddedNote['fields'].length, 14);
      expect(bridge.lastAddedNote['fields'][0], '青空');
      expect(bridge.lastAddedNote['fields'][13], 'デジタル大辞泉');
    });

    test('exportEntries duplicate check adapts to first field value of custom model', () async {
      final bridge = MockAnkidroidBridge()
        ..models[70] = '自定义FrontBack'
        ..modelFields[70] = ['Front', 'Back']
        ..duplicateKeys = ['青空'];
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries(
        [sampleEntry],
        modelName: '自定义FrontBack',
      );

      expect(result.successCount, 0);
      expect(result.skipCount, 1);
      expect(result.isSuccess, isTrue);
      expect(result.failedEntries.isEmpty, isTrue);
    });

    test('entryToModelFields correctly handles SentDefSC without trailing 1 and sentence aliases', () {
      final fields = AnkiExportService.entryToModelFields(
        sampleEntry,
        ['SentKanji', 'SentFurigana', 'SentDefSC'],
      );
      expect(fields.length, 3);
      expect(fields[0], '青空が広がる');
      expect(fields[1], '<b>青空[あおぞら]</b>が 広[ひろ]がる');
      expect(fields[2], '晴空万里'); // Must be SentDefSC1, NOT VocabPoS

      final fields2 = AnkiExportService.entryToModelFields(
        sampleEntry,
        ['Sentence', 'SentenceReading', 'SentenceTranslation', 'SentenceMeaning'],
      );
      expect(fields2.length, 4);
      expect(fields2[0], '青空が広がる');
      expect(fields2[1], '<b>青空[あおぞら]</b>が 広[ひろ]がる');
      expect(fields2[2], '晴空万里');
      expect(fields2[3], '晴空万里');
    });

    test('entryToModelFields handles fields with punctuation, brackets, parentheses and colons', () {
      final fields = AnkiExportService.entryToModelFields(
        sampleEntry,
        [
          'Vocab (Kanji)',
          'Meaning (SC)',
          'Sent [Kanji 1]',
          'Def: Chinese',
          'Card #1 Front',
          'Card #1 Back',
        ],
      );
      expect(fields.length, 6);
      expect(fields[0], '青空');
      expect(fields[1], '蔚蓝的天空；晴空。');
      expect(fields[2], '青空が広がる');
      expect(fields[3], '蔚蓝的天空；晴空。');
      expect(fields[4], '青空');
      expect(fields[5], '蔚蓝的天空；晴空。');
    });

    test('entryToModelFields handles Yomitan standard fields and Japanese native aliases', () {
      final yomitanFields = [
        'Term',
        'Reading',
        'Glossary',
        'Sentence',
        'SentenceReading',
        'SentenceMeaning',
      ];
      final yomitanValues = AnkiExportService.entryToModelFields(
        sampleEntry,
        yomitanFields,
      );
      expect(yomitanValues.length, 6);
      expect(yomitanValues[0], '青空');
      expect(yomitanValues[1], 'あおぞら');
      expect(yomitanValues[2], '蔚蓝的天空；晴空。');
      expect(yomitanValues[3], '青空が広がる');
      expect(yomitanValues[4], '<b>青空[あおぞら]</b>が 広[ひろ]がる');
      expect(yomitanValues[5], '晴空万里');

      final jaFields = [
        '単語',
        '表記',
        '読み',
        '意味',
        '品詞',
        '国語',
        '例文',
        '出典',
      ];
      final jaValues = AnkiExportService.entryToModelFields(
        sampleEntry,
        jaFields,
      );
      expect(jaValues.length, 8);
      expect(jaValues[0], '青空');
      expect(jaValues[1], '青空');
      expect(jaValues[2], 'あおぞら');
      expect(jaValues[3], '蔚蓝的天空；晴空。');
      expect(jaValues[4], '名');
      expect(jaValues[5], '晴れ渡った青い空。');
      expect(jaValues[6], '青空が広がる');
      expect(jaValues[7], 'デジタル大辞泉');
    });

    test('entryToModelFields handles sourceUrl aliases', () {
      final fields = AnkiExportService.entryToModelFields(
        sampleEntry,
        ['Word', 'Meaning', 'URL', '来源链接'],
      );
      expect(fields.length, 4);
      expect(fields[0], '青空');
      expect(fields[1], '蔚蓝的天空；晴空。');
      expect(fields[2], 'https://weblio.jp/content/青空');
      expect(fields[3], 'https://weblio.jp/content/青空');
    });

    test('exportEntries with 3-field sentence deck (SentKanji, SentFurigana, SentDefSC)', () async {
      final bridge = MockAnkidroidBridge()
        ..models[80] = '例句卡片'
        ..modelFields[80] = ['SentKanji', 'SentFurigana', 'SentDefSC'];
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries(
        [sampleEntry],
        modelName: '例句卡片',
      );

      expect(result.isSuccess, isTrue);
      expect(result.successCount, 1);
      expect(bridge.lastAddedNote['mid'], 80);
      expect(bridge.lastAddedNote['fields'].length, 3);
      expect(bridge.lastAddedNote['fields'][0], '青空が広がる');
      expect(bridge.lastAddedNote['fields'][1], '<b>青空[あおぞら]</b>が 広[ひろ]がる');
      expect(bridge.lastAddedNote['fields'][2], '晴空万里');
    });

    test('entryToModelFields handles empty modelFields list by returning 13 standard fields', () {
      final fields = AnkiExportService.entryToModelFields(sampleEntry, []);
      expect(fields.length, 13);
      expect(fields[0], '青空');
      expect(fields[12], '7');
    });

    test('entryToModelFields safely handles unknown fields beyond 13 items without throwing OutOfBounds or misaligning', () {
      final extraFields = List<String>.generate(20, (i) => 'UNKNOWN_EXTRA_$i');
      final fields = AnkiExportService.entryToModelFields(sampleEntry, extraFields);
      expect(fields.length, 20);
      for (final val in fields) {
        expect(val, ''); // All unknown fields safely return empty string to prevent field misalignment
      }
    });

    test('entryToModelFields handles single-field model correctly', () {
      final fields = AnkiExportService.entryToModelFields(sampleEntry, ['Front']);
      expect(fields.length, 1);
      expect(fields[0], '青空');
    });

    test('entryToModelFields handles kana aliases including hiragana, yomi and furigana', () {
      final fields = AnkiExportService.entryToModelFields(
        sampleEntry,
        ['hiragana', 'ふりがな', 'よみ', '振り仮名'],
      );
      expect(fields.length, 4);
      expect(fields[0], 'あおぞら');
      expect(fields[1], 'あおぞら');
      expect(fields[2], 'あおぞら');
      expect(fields[3], 'あおぞら');
    });

    test('exportEntries falls back to SharedPreferences custom deck and model name when not provided', () async {
      SharedPreferences.setMockInitialValues({
        'anki_deck_name': '自定义收藏牌组',
        'anki_model_name': '自定义卡片模板',
      });

      final bridge = MockAnkidroidBridge();
      final service = AnkiExportService(bridge: bridge);

      final result = await service.exportEntries([sampleEntry]);
      expect(result.isSuccess, isTrue);
      expect(result.successCount, 1);
      // Verify deck was created or looked up using custom deck name from SharedPreferences
      expect(bridge.decks.values, contains('自定义收藏牌组'));
      expect(bridge.models.values, contains('自定义卡片模板'));
    });

    test('defaultQfmt contains full original template, EdgeTTS word audio and scripts', () {
      expect(AnkiExportService.defaultQfmt, contains('<main id="FrontSide" class="CardSide">'));
      expect(AnkiExportService.defaultQfmt, contains('{{furigana:VocabKanji}}'));
      expect(AnkiExportService.defaultQfmt, contains('function setEdgeTTS()'));
      expect(AnkiExportService.defaultQfmt, contains('.VocabAudio'));
      expect(AnkiExportService.defaultQfmt, contains('ja-JP-NanamiNeural'));
      expect(AnkiExportService.defaultQfmt, contains('setEdgeTTS()'));
      expect(AnkiExportService.defaultQfmt, contains('setupCard()'));
      expect(AnkiExportService.defaultQfmt, contains('function CONFIG()'));
      expect(AnkiExportService.defaultQfmt, contains('function lookUp('));
      expect(AnkiExportService.defaultQfmt, contains('function checkVersion('));
    });

    test('defaultAfmt contains definition toggle button, setupDefSwitch and EdgeTTS playback', () {
      expect(AnkiExportService.defaultAfmt, contains('<main id="BackSide" class="CardSide">'));
      expect(AnkiExportService.defaultAfmt, contains('{{FrontSide}}'));
      expect(AnkiExportService.defaultAfmt, contains('VocabDefWrap'));
      expect(AnkiExportService.defaultAfmt, contains('id="VocabDefDisplay"'));
      expect(AnkiExportService.defaultAfmt, contains('id="DefSwitchBtn"'));
      expect(AnkiExportService.defaultAfmt, contains('id="DefStoreSc"'));
      expect(AnkiExportService.defaultAfmt, contains('id="DefStoreJa"'));
      expect(AnkiExportService.defaultAfmt, contains('{{#VocabDefJa}}'));
      expect(AnkiExportService.defaultAfmt, contains('{{#VocabPlus}}'));
      expect(AnkiExportService.defaultAfmt, contains('function setupDefSwitch()'));
      expect(AnkiExportService.defaultAfmt, contains('setEdgeTTS()'));
    });

    test('defaultCss contains full original styles and toggle button css', () {
      expect(AnkiExportService.defaultCss, contains('@charset "UTF-8";'));
      expect(AnkiExportService.defaultCss, contains('--canvas: #fffaf0;'));
      expect(AnkiExportService.defaultCss, contains('night-mode'));
      expect(AnkiExportService.defaultCss, contains('.VocabDefWrap'));
      expect(AnkiExportService.defaultCss, contains('.DefSwitchBtn'));
      expect(AnkiExportService.defaultCss, contains('.replay-button'));
      expect(AnkiExportService.defaultCss, contains('.tts.replay-button'));
    });

    test('getOrCreateModel creates model with full default templates and css', () async {
      final bridge = MockAnkidroidBridge();
      final service = AnkiExportService(bridge: bridge);

      final modelId = await service.getOrCreateModel('测试新模型');
      expect(modelId, isNotNull);
      expect(bridge.models[modelId], '测试新模型');
    });
  });
}
