import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat/services/weblio_service.dart';

void main() {
  late WeblioService service;

  setUp(() {
    service = WeblioService();
  });

  group('WeblioService HTML Parsing Tests', () {
    test('parseHtml correctly extracts SGKDJ verb (食べる)', () {
      final file = File('test/fixtures/weblio_taberu.html');
      expect(file.existsSync(), isTrue);

      final html = file.readAsStringSync();
      final result = service.parseHtml(html, '食べる');

      expect(result.word, '食べる');
      expect(result.reading, 'たべる');
      expect(result.partOfSpeech, contains('動バ下一'));
      expect(result.sourceDict, 'デジタル大辞泉');
      expect(result.definition, contains('食物をかんで、のみこむ'));
      expect(result.definition, contains('暮らしを立てる'));
      expect(result.examples.length, greaterThanOrEqualTo(1));

      // Check restored example sentence
      final ex1 = result.examples.first;
      expect(ex1.kanji, '生で食べる');
      expect(ex1.furigana, '生[なま]で食べる');

      if (result.examples.length > 1) {
        final ex2 = result.examples[1];
        expect(ex2.kanji, 'ひと口食べてみる');
      }
    });

    test('parseHtml correctly extracts SGKDJ adjective (美しい)', () {
      final file = File('test/fixtures/weblio_utsukushii.html');
      expect(file.existsSync(), isTrue);

      final html = file.readAsStringSync();
      final result = service.parseHtml(html, '美しい');

      expect(result.word, '美しい');
      expect(result.reading, 'うつくしい');
      expect(result.partOfSpeech, '形');
      expect(result.sourceDict, 'デジタル大辞泉');
      expect(result.definition, contains('調和がとれていて快く感じられるさま'));
      expect(result.examples.length, greaterThanOrEqualTo(1));

      final firstEx = result.examples.first;
      expect(firstEx.kanji, contains('美しい'));
    });

    test('parseHtml correctly falls back to non-SGKDJ dictionary when SGKDJ is absent', () {
      const fallbackHtml = '''
        <!DOCTYPE html>
        <html>
        <body>
          <div class="pbarT">Wiktionary日本語版 索引トップ</div>
          <div class="kijiWrp">
            <div class="kiji">
              <h2 class="midashigo">テスト【test】</h2>
              <span class="hinshi">［名］</span>
              <p>試験。試行。実地に行ってみること。</p>
            </div>
          </div>
        </body>
        </html>
      ''';

      final result = service.parseHtml(fallbackHtml, 'テスト');
      expect(result.word, 'テスト');
      expect(result.reading, 'テスト');
      expect(result.partOfSpeech, '名');
      expect(result.sourceDict, 'Wiktionary日本語版');
      expect(result.definition, contains('試験。試行。実地に行ってみること。'));
    });

    test('parseHtml throws WeblioException when word is not found', () {
      const notFoundHtml = '''
        <!DOCTYPE html>
        <html>
        <body>
          <div class="main">
            <p>一致する見出し語は見つかりませんでした</p>
          </div>
        </body>
        </html>
      ''';

      expect(
        () => service.parseHtml(notFoundHtml, 'xyznotfound'),
        throwsA(isA<WeblioException>().having(
          (e) => e.message,
          'message',
          contains('未在 Weblio 找到「xyznotfound」的相关释义'),
        )),
      );
    });

    test('lookupWord with empty or whitespace string throws WeblioException', () async {
      expect(
        () => service.lookupWord('   '),
        throwsA(isA<WeblioException>().having(
          (e) => e.message,
          'message',
          contains('查询单词不能为空'),
        )),
      );
    });
  });
}
