import 'package:flutter_test/flutter_test.dart';
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
      expect(fields[6], '青空[あおぞら]が 広[ひろ]がる'); // SentFurigana1
      expect(fields[7], '晴空万里'); // SentDefSC1
      expect(fields[8], '青空の下で'); // SentKanji2
      expect(fields[9], '青空[あおぞら]の 下[した]で'); // SentFurigana2
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

    test('entryToModelFields handles case-insensitive aliases and positional fallback', () {
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
      expect(fields[5], '青空[あおぞら]が 広[ひろ]がる'); // sentencefurigana1 alias
      expect(fields[6], '晴空万里'); // senttrans1 alias
      expect(fields[7], '晴空万里'); // UNKNOWN_POS_7 fallback to ankiFields[7] (SentDefSC1)
      expect(fields[8], '青空の下で'); // UNKNOWN_POS_8 fallback to ankiFields[8] (SentKanji2)
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
  });
}
