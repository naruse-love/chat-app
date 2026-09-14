import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/vocabulary_entry.dart';

void main() {
  group('VocabularyEntry Model Tests', () {
    test('Constructor with default values and custom fields', () {
      final now = DateTime.now();
      final entry = VocabularyEntry(
        id: 1,
        vocabKanji: '食べる',
        vocabFurigana: 'たべる',
        vocabDefJa: '食物をかんで、のみこむ。',
        vocabDefSc: '咀嚼并吞咽食物；吃。',
        vocabPoS: '動バ下一',
        sentKanji1: '生で食べる',
        sentFurigana1: '生[なま]で食べる',
        sentDefSc1: '生吃',
        sentKanji2: 'ひと口食べてみる',
        sentFurigana2: 'ひと口食べてみる',
        sentDefSc2: '尝一口吃吃看',
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/食べる',
        createdAt: now,
      );

      expect(entry.id, 1);
      expect(entry.vocabKanji, '食べる');
      expect(entry.vocabFurigana, 'たべる');
      expect(entry.vocabDefJa, '食物をかんで、のみこむ。');
      expect(entry.vocabDefSc, '咀嚼并吞咽食物；吃。');
      expect(entry.vocabPoS, '動バ下一');
      expect(entry.sentKanji1, '生で食べる');
      expect(entry.sentFurigana1, '生[なま]で食べる');
      expect(entry.sentDefSc1, '生吃');
      expect(entry.sentKanji2, 'ひと口食べてみる');
      expect(entry.sentFurigana2, 'ひと口食べてみる');
      expect(entry.sentDefSc2, '尝一口吃吃看');
      expect(entry.sourceDict, 'デジタル大辞泉');
      expect(entry.sourceUrl, 'https://www.weblio.jp/content/食べる');
      expect(entry.createdAt, now);
    });

    test('toJson and fromJson round-trip serialization', () {
      final now = DateTime.parse('2026-09-10T12:00:00.000Z');
      final entry = VocabularyEntry(
        id: 42,
        vocabKanji: '美しい',
        vocabFurigana: 'うつくしい',
        vocabDefJa: '色・形・音などの調和がとれていて快く感じられるさま。',
        vocabDefSc: '色彩、形态、声音等协调令人感到愉悦的样子；美丽。',
        vocabPoS: '形',
        sentKanji1: '日本の美しい自然',
        sentFurigana1: '日本[にほん]の美[うつく]しい自然[しぜん]',
        sentDefSc1: '日本美丽的大自然',
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/美しい',
        createdAt: now,
      );

      final json = entry.toJson();
      expect(json['id'], 42);
      expect(json['vocabKanji'], '美しい');
      expect(json['vocabFurigana'], 'うつくしい');
      expect(json['sentKanji1'], '日本の美しい自然');
      expect(json['sentKanji2'], isNull);
      expect(json['createdAt'], '2026-09-10T12:00:00.000Z');

      final deserialized = VocabularyEntry.fromJson(json);
      expect(deserialized.id, entry.id);
      expect(deserialized.vocabKanji, entry.vocabKanji);
      expect(deserialized.vocabFurigana, entry.vocabFurigana);
      expect(deserialized.vocabDefJa, entry.vocabDefJa);
      expect(deserialized.vocabDefSc, entry.vocabDefSc);
      expect(deserialized.vocabPoS, entry.vocabPoS);
      expect(deserialized.sentKanji1, entry.sentKanji1);
      expect(deserialized.sentFurigana1, entry.sentFurigana1);
      expect(deserialized.sentDefSc1, entry.sentDefSc1);
      expect(deserialized.sentKanji2, isNull);
      expect(deserialized.createdAt, entry.createdAt);
    });

    test('toMap and fromMap for SQLite database', () {
      final now = DateTime.now();
      final entry = VocabularyEntry(
        id: 10,
        vocabKanji: '走る',
        vocabFurigana: 'はしる',
        vocabDefJa: '足を速く動かして前進する。',
        vocabDefSc: '跑步，奔跑。',
        vocabPoS: '動ラ五',
        sourceDict: 'デジタル大辞泉',
        createdAt: now,
      );

      final map = entry.toMap();
      expect(map['id'], 10);
      expect(map['vocabKanji'], '走る');
      expect(map['vocabFurigana'], 'はしる');
      expect(map['createdAt'], now.toIso8601String());

      final fromDb = VocabularyEntry.fromMap(map);
      expect(fromDb.id, 10);
      expect(fromDb.vocabKanji, '走る');
      expect(fromDb.vocabFurigana, 'はしる');
      expect(fromDb.sentKanji1, isNull);
    });

    test('copyWith works correctly with and without clearId', () {
      final now = DateTime.now();
      final entry = VocabularyEntry(
        id: 5,
        vocabKanji: '本',
        vocabFurigana: 'ほん',
        createdAt: now,
      );

      final modified = entry.copyWith(vocabDefSc: '书籍');
      expect(modified.id, 5);
      expect(modified.vocabKanji, '本');
      expect(modified.vocabDefSc, '书籍');

      final withoutId = entry.copyWith(clearId: true);
      expect(withoutId.id, isNull);
      expect(withoutId.vocabKanji, '本');

      final withExported = entry.copyWith(exportedToAnki: true);
      expect(withExported.exportedToAnki, isTrue);
      expect(entry.exportedToAnki, isFalse);
    });

    test('exportedToAnki default, toMap, fromMap, and JSON serialization', () {
      final now = DateTime.now();
      final defaultEntry = VocabularyEntry(
        vocabKanji: '猫',
        createdAt: now,
      );
      expect(defaultEntry.exportedToAnki, isFalse);

      final exportedEntry = defaultEntry.copyWith(exportedToAnki: true);
      expect(exportedEntry.exportedToAnki, isTrue);

      // toMap / fromMap
      final map = exportedEntry.toMap();
      expect(map['exportedToAnki'], 1);
      final fromMap = VocabularyEntry.fromMap(map);
      expect(fromMap.exportedToAnki, isTrue);

      final unexportedMap = defaultEntry.toMap();
      expect(unexportedMap['exportedToAnki'], 0);
      final fromUnexportedMap = VocabularyEntry.fromMap(unexportedMap);
      expect(fromUnexportedMap.exportedToAnki, isFalse);

      // fromMap with missing key defaults to false
      final legacyMap = <String, dynamic>{
        'vocabKanji': '犬',
        'createdAt': now.toIso8601String(),
      };
      final fromLegacy = VocabularyEntry.fromMap(legacyMap);
      expect(fromLegacy.exportedToAnki, isFalse);

      // toJson / fromJson
      final json = exportedEntry.toJson();
      expect(json['exportedToAnki'], isTrue);
      final fromJson = VocabularyEntry.fromJson(json);
      expect(fromJson.exportedToAnki, isTrue);
    });

    test('vocabPitch default value, copyWith, toMap/fromMap and toJson/fromJson', () {
      final now = DateTime.now();
      final defaultEntry = VocabularyEntry(
        vocabKanji: 'いとも',
        createdAt: now,
      );
      expect(defaultEntry.vocabPitch, '');

      final withPitch = defaultEntry.copyWith(vocabPitch: '①');
      expect(withPitch.vocabPitch, '①');
      expect(defaultEntry.vocabPitch, '');

      // toMap / fromMap
      final map = withPitch.toMap();
      expect(map['vocabPitch'], '①');
      final fromMap = VocabularyEntry.fromMap(map);
      expect(fromMap.vocabPitch, '①');

      // fromMap legacy row without vocabPitch defaults to empty string
      final legacyMap = <String, dynamic>{
        'vocabKanji': 'いとも',
        'createdAt': now.toIso8601String(),
      };
      final fromLegacy = VocabularyEntry.fromMap(legacyMap);
      expect(fromLegacy.vocabPitch, '');

      // toJson / fromJson
      final json = withPitch.toJson();
      expect(json['vocabPitch'], '①');
      final fromJson = VocabularyEntry.fromJson(json);
      expect(fromJson.vocabPitch, '①');
    });
  });
}
