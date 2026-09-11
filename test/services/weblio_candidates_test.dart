import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/services/weblio_service.dart';
import 'package:chat/models/word_candidate.dart';

void main() {
  group('WeblioService Candidate Extraction Tests', () {
    test('extractCandidatesFromHtml parses multiple homonym candidates', () {
      const homonymHtml = '''
        <!DOCTYPE html>
        <html>
        <body>
          <div class="kiji">
            <h2 class="midashigo">はし【箸】</h2>
            <span class="hinshi">［名］</span>
            <p>１ 食事の時に用いる二本一組の棒。</p>
          </div>
          <div class="kiji">
            <h2 class="midashigo">はし【橋】</h2>
            <span class="hinshi">［名］</span>
            <p>川や谷などの上に架け渡して人や車を通す構造物。</p>
          </div>
          <div class="kiji">
            <h2 class="midashigo">はし【端】</h2>
            <span class="hinshi">［名］</span>
            <p>物の中心から最も離れた部分。境目。</p>
          </div>
        </body>
        </html>
      ''';

      final candidates = WeblioService.extractCandidatesFromHtml(homonymHtml, 'はし');

      expect(candidates.length, 3);

      expect(candidates[0].kanji, '箸');
      expect(candidates[0].reading, 'はし');
      expect(candidates[0].partOfSpeech, contains('名'));
      expect(candidates[0].definition, contains('食事の時に用いる'));
      expect(candidates[0].source, CandidateSource.weblio);

      expect(candidates[1].kanji, '橋');
      expect(candidates[1].reading, 'はし');
      expect(candidates[1].definition, contains('川や谷'));

      expect(candidates[2].kanji, '端');
      expect(candidates[2].reading, 'はし');
      expect(candidates[2].definition, contains('物の中心'));
    });

    test('extractCandidatesFromHtml handles slashed multiple kanji like 嘴／喙', () {
      const slashedHtml = '''
        <!DOCTYPE html>
        <html>
        <body>
          <div class="kiji">
            <h2 class="midashigo">はし【嘴／喙】</h2>
            <span class="hinshi">［名］</span>
            <p>鳥類の口の先。くちばし。</p>
          </div>
        </body>
        </html>
      ''';

      final candidates = WeblioService.extractCandidatesFromHtml(slashedHtml, 'はし');
      expect(candidates.length, 2);
      expect(candidates[0].kanji, '嘴');
      expect(candidates[1].kanji, '喙');
    });

    test('extractCandidatesFromHtml handles middle dot separated kanji like 暑い・熱い', () {
      const dotHtml = '''
        <!DOCTYPE html>
        <html>
        <body>
          <div class="kiji">
            <h2 class="midashigo">あつい【暑い・熱い】</h2>
            <span class="hinshi">［形］</span>
            <p>気温が高い。また、温度が高い。</p>
          </div>
        </body>
        </html>
      ''';

      final candidates = WeblioService.extractCandidatesFromHtml(dotHtml, 'あつい');
      expect(candidates.length, 2);
      expect(candidates[0].kanji, '暑い');
      expect(candidates[1].kanji, '熱い');
    });

    test('extractCandidatesFromHtml parses single entry from real taberu fixture', () {
      final file = File('test/fixtures/weblio_taberu.html');
      expect(file.existsSync(), isTrue);

      final html = file.readAsStringSync();
      final candidates = WeblioService.extractCandidatesFromHtml(html, '食べる');

      expect(candidates, isNotEmpty);
      expect(candidates.any((c) => c.kanji == '食べる'), isTrue);
      final taberu = candidates.firstWhere((c) => c.kanji == '食べる');
      expect(taberu.reading, 'たべる');
      expect(taberu.definition, contains('食物'));
    });

    test('extractCandidatesFromHtml returns empty when word not found', () {
      const notFoundHtml = '''
        <!DOCTYPE html>
        <html>
        <body>
          <p>一致する見出し語は見つかりませんでした</p>
        </body>
        </html>
      ''';

      final candidates = WeblioService.extractCandidatesFromHtml(notFoundHtml, 'xyznotfound');
      expect(candidates, isEmpty);
    });
  });
}
