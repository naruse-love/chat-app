// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vocabulary_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VocabularyEntry _$VocabularyEntryFromJson(Map<String, dynamic> json) =>
    VocabularyEntry(
      id: (json['id'] as num?)?.toInt(),
      vocabKanji: json['vocabKanji'] as String,
      vocabFurigana: json['vocabFurigana'] as String? ?? '',
      vocabPitch: json['vocabPitch'] as String? ?? '',
      vocabDefJa: json['vocabDefJa'] as String? ?? '',
      vocabDefSc: json['vocabDefSc'] as String? ?? '',
      vocabPoS: json['vocabPoS'] as String? ?? '',
      sentKanji1: json['sentKanji1'] as String?,
      sentFurigana1: json['sentFurigana1'] as String?,
      sentDefSc1: json['sentDefSc1'] as String?,
      sentKanji2: json['sentKanji2'] as String?,
      sentFurigana2: json['sentFurigana2'] as String?,
      sentDefSc2: json['sentDefSc2'] as String?,
      sourceDict: json['sourceDict'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      exportedToAnki: json['exportedToAnki'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$VocabularyEntryToJson(VocabularyEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'vocabKanji': instance.vocabKanji,
      'vocabFurigana': instance.vocabFurigana,
      'vocabPitch': instance.vocabPitch,
      'vocabDefJa': instance.vocabDefJa,
      'vocabDefSc': instance.vocabDefSc,
      'vocabPoS': instance.vocabPoS,
      'sentKanji1': instance.sentKanji1,
      'sentFurigana1': instance.sentFurigana1,
      'sentDefSc1': instance.sentDefSc1,
      'sentKanji2': instance.sentKanji2,
      'sentFurigana2': instance.sentFurigana2,
      'sentDefSc2': instance.sentDefSc2,
      'sourceDict': instance.sourceDict,
      'sourceUrl': instance.sourceUrl,
      'exportedToAnki': instance.exportedToAnki,
      'createdAt': instance.createdAt.toIso8601String(),
    };
