import 'dart:io';
import 'package:ankidroid_for_flutter/ankidroid_for_flutter.dart';
import '../models/vocabulary_entry.dart';
import 'anki_export_service_interface.dart';

export 'anki_export_service_interface.dart';

/// AnkiDroid 底层操作抽象网桥（方便在单元测试与桌面环境进行纯内存 Mock）
abstract class AnkidroidBridge {
  bool get isPlatformSupported;
  Future<bool> requestPermission();
  Future<void> init();
  Future<Map<int, String>> getDeckList();
  Future<int> addNewDeck(String name);
  Future<Map<int, String>> getModelList();
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
    final map = result.asValue!.value;
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
    final map = result.asValue!.value;
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

  /// 14 个标准 Anki 卡片字段
  static const List<String> ankiFields = [
    'NoteID',
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
    'Tags',
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
      <span class="VocabDef">[{{VocabPoS}}] {{VocabDefSC}}</span>
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

  /// 将单词实体转换为 14 个字段列表
  static List<String> entryToFields(VocabularyEntry entry) {
    return [
      entry.id?.toString() ?? '',
      entry.vocabKanji,
      entry.vocabFurigana,
      entry.vocabPoS,
      entry.vocabDefSc,
      entry.vocabDefJa,
      entry.sentKanji1 ?? '',
      entry.sentFurigana1 ?? '',
      entry.sentDefSc1 ?? '',
      entry.sentKanji2 ?? '',
      entry.sentFurigana2 ?? '',
      entry.sentDefSc2 ?? '',
      entry.sourceDict,
      entry.sourceDict.isNotEmpty ? entry.sourceDict : 'AI生词本',
    ];
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
      sortf: 1,
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
      final targetDeck = (deckName != null && deckName.trim().isNotEmpty)
          ? deckName.trim()
          : defaultDeckName;
      final targetModel = (modelName != null && modelName.trim().isNotEmpty)
          ? modelName.trim()
          : defaultModelName;

      final deckId = await getOrCreateDeck(targetDeck);
      final modelId = await getOrCreateModel(targetModel);

      int successCount = 0;
      int skipCount = 0;
      final failedEntries = <VocabularyEntry>[];
      final errors = <String>[];

      for (final entry in entries) {
        try {
          // 重复检测
          bool isDuplicate = false;
          try {
            final dupes = await _bridge.findDuplicateNotesWithKey(
              modelId,
              entry.vocabKanji,
            );
            if (dupes.isNotEmpty) {
              isDuplicate = true;
            }
          } catch (_) {
            // 重复检测异常不阻断正常创建流程
          }

          if (isDuplicate) {
            skipCount++;
            continue;
          }

          final fields = entryToFields(entry);
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
