import 'package:flutter_test/flutter_test.dart';
import 'package:chat/models/word_candidate.dart';

void main() {
  group('WordCandidate Model Tests', () {
    test('constructs correctly with default source', () {
      const candidate = WordCandidate(
        kanji: '箸',
        reading: 'はし',
        definition: '筷子',
        partOfSpeech: '名',
      );

      expect(candidate.kanji, '箸');
      expect(candidate.reading, 'はし');
      expect(candidate.definition, '筷子');
      expect(candidate.partOfSpeech, '名');
      expect(candidate.source, CandidateSource.weblio);
    });

    test('toJson and fromJson work bidirectionally for weblio', () {
      const original = WordCandidate(
        kanji: '橋',
        reading: 'はし',
        definition: '桥梁',
        partOfSpeech: '名',
        source: CandidateSource.weblio,
      );

      final json = original.toJson();
      final revived = WordCandidate.fromJson(json);

      expect(revived.kanji, original.kanji);
      expect(revived.reading, original.reading);
      expect(revived.definition, original.definition);
      expect(revived.partOfSpeech, original.partOfSpeech);
      expect(revived.source, original.source);
      expect(revived, equals(original));
      expect(revived.hashCode, equals(original.hashCode));
    });

    test('toJson and fromJson work bidirectionally for aiInference', () {
      const original = WordCandidate(
        kanji: '食べる',
        reading: 'たべる',
        definition: '进食、吃（推测为たべまる笔误）',
        partOfSpeech: '動バ下一',
        source: CandidateSource.aiInference,
      );

      final json = original.toJson();
      final revived = WordCandidate.fromJson(json);

      expect(revived.kanji, '食べる');
      expect(revived.source, CandidateSource.aiInference);
      expect(revived, equals(original));
    });

    test('fromJson handles missing or malformed fields gracefully', () {
      final candidate = WordCandidate.fromJson({
        'kanji': ' 端 ',
        'reading': ' はし ',
      });

      expect(candidate.kanji, '端');
      expect(candidate.reading, 'はし');
      expect(candidate.definition, '');
      expect(candidate.partOfSpeech, '');
      expect(candidate.source, CandidateSource.weblio);
    });

    test('toString contains relevant fields', () {
      const candidate = WordCandidate(
        kanji: '端',
        reading: 'はし',
        definition: '边缘',
        partOfSpeech: '名',
      );

      final str = candidate.toString();
      expect(str, contains('端'));
      expect(str, contains('はし'));
      expect(str, contains('边缘'));
    });
  });
}
