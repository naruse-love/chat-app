import 'package:json_annotation/json_annotation.dart';

part 'vocabulary_entry.g.dart';

/// 日语生词本条目数据模型
/// 字段结构与 Anki 模板（正面.html / 背面.html）完全对齐
@JsonSerializable()
class VocabularyEntry {
  final int? id;
  final String vocabKanji;
  final String vocabFurigana;
  final String vocabDefJa;
  final String vocabDefSc;
  final String vocabPoS;
  final String? sentKanji1;
  final String? sentFurigana1;
  final String? sentDefSc1;
  final String? sentKanji2;
  final String? sentFurigana2;
  final String? sentDefSc2;
  final String sourceDict;
  final String sourceUrl;
  final bool exportedToAnki;
  final DateTime createdAt;

  const VocabularyEntry({
    this.id,
    required this.vocabKanji,
    this.vocabFurigana = '',
    this.vocabDefJa = '',
    this.vocabDefSc = '',
    this.vocabPoS = '',
    this.sentKanji1,
    this.sentFurigana1,
    this.sentDefSc1,
    this.sentKanji2,
    this.sentFurigana2,
    this.sentDefSc2,
    this.sourceDict = '',
    this.sourceUrl = '',
    this.exportedToAnki = false,
    required this.createdAt,
  });

  factory VocabularyEntry.fromJson(Map<String, dynamic> json) =>
      _$VocabularyEntryFromJson(json);

  Map<String, dynamic> toJson() => _$VocabularyEntryToJson(this);

  /// 适用于 SQLite 数据库映射
  factory VocabularyEntry.fromMap(Map<String, dynamic> map) {
    return VocabularyEntry(
      id: map['id'] as int?,
      vocabKanji: map['vocabKanji'] as String,
      vocabFurigana: map['vocabFurigana'] as String? ?? '',
      vocabDefJa: map['vocabDefJa'] as String? ?? '',
      vocabDefSc: map['vocabDefSc'] as String? ?? '',
      vocabPoS: map['vocabPoS'] as String? ?? '',
      sentKanji1: map['sentKanji1'] as String?,
      sentFurigana1: map['sentFurigana1'] as String?,
      sentDefSc1: map['sentDefSc1'] as String?,
      sentKanji2: map['sentKanji2'] as String?,
      sentFurigana2: map['sentFurigana2'] as String?,
      sentDefSc2: map['sentDefSc2'] as String?,
      sourceDict: map['sourceDict'] as String? ?? '',
      sourceUrl: map['sourceUrl'] as String? ?? '',
      exportedToAnki: (map['exportedToAnki'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  /// 转换为 SQLite 可存储的 Map 结构
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'vocabKanji': vocabKanji,
      'vocabFurigana': vocabFurigana,
      'vocabDefJa': vocabDefJa,
      'vocabDefSc': vocabDefSc,
      'vocabPoS': vocabPoS,
      'sentKanji1': sentKanji1,
      'sentFurigana1': sentFurigana1,
      'sentDefSc1': sentDefSc1,
      'sentKanji2': sentKanji2,
      'sentFurigana2': sentFurigana2,
      'sentDefSc2': sentDefSc2,
      'sourceDict': sourceDict,
      'sourceUrl': sourceUrl,
      'exportedToAnki': exportedToAnki ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  VocabularyEntry copyWith({
    int? id,
    bool clearId = false,
    String? vocabKanji,
    String? vocabFurigana,
    String? vocabDefJa,
    String? vocabDefSc,
    String? vocabPoS,
    String? sentKanji1,
    String? sentFurigana1,
    String? sentDefSc1,
    String? sentKanji2,
    String? sentFurigana2,
    String? sentDefSc2,
    String? sourceDict,
    String? sourceUrl,
    bool? exportedToAnki,
    DateTime? createdAt,
  }) {
    return VocabularyEntry(
      id: clearId ? null : (id ?? this.id),
      vocabKanji: vocabKanji ?? this.vocabKanji,
      vocabFurigana: vocabFurigana ?? this.vocabFurigana,
      vocabDefJa: vocabDefJa ?? this.vocabDefJa,
      vocabDefSc: vocabDefSc ?? this.vocabDefSc,
      vocabPoS: vocabPoS ?? this.vocabPoS,
      sentKanji1: sentKanji1 ?? this.sentKanji1,
      sentFurigana1: sentFurigana1 ?? this.sentFurigana1,
      sentDefSc1: sentDefSc1 ?? this.sentDefSc1,
      sentKanji2: sentKanji2 ?? this.sentKanji2,
      sentFurigana2: sentFurigana2 ?? this.sentFurigana2,
      sentDefSc2: sentDefSc2 ?? this.sentDefSc2,
      sourceDict: sourceDict ?? this.sourceDict,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      exportedToAnki: exportedToAnki ?? this.exportedToAnki,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
