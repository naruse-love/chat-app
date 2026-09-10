import 'dart:io';
import 'package:dio/dio.dart';
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

    test('formatFurigana and stripFurigana produce valid Anki ruby syntax without mangling kana', () {
      const sentence = 'ご飯(はん)を美味(おい)しく食(た)べる';
      final formatted = WeblioService.formatFurigana(sentence);
      final stripped = WeblioService.stripFurigana(sentence);

      expect(stripped, 'ご飯を美味しく食べる');
      expect(formatted, 'ご 飯[はん]を 美味[おい]しく 食[た]べる');

      const singleKanji = '生(なま)で食べる';
      expect(WeblioService.formatFurigana(singleKanji), '生[なま]で食べる');
      expect(WeblioService.stripFurigana(singleKanji), '生で食べる');
    });

    test('parseHtml correctly differentiates stem (―・) and headword (―) in examples', () {
      const html = '''
        <!DOCTYPE html>
        <html>
        <body>
          <div class="kijiWrp">
            <div class="kiji">
              <h2 class="midashigo">た・べる【食べる】</h2>
              <div class="Sgkdj">
                <span class="hinshi">［動バ下一］</span>
                <p>１ 食物を口に入れる。「生で―・べる」「朝夕―」</p>
                <p>２ 「食う」の謙譲語。いただく。</p>
              </div>
            </div>
          </div>
        </body>
        </html>
      ''';

      final result = service.parseHtml(html, '食べる');
      expect(result.examples.length, 2);
      expect(result.examples[0].kanji, '生で食べる');
      expect(result.examples[1].kanji, '朝夕食べる'); // Correctly restored with full headword, not '朝夕食'
      expect(result.definition, contains('「食う」の謙譲語')); // Preserved definition cross reference
      expect(result.definition, isNot(contains('「生で―・べる」'))); // Stripped example
    });

    test('parseHtml correctly scopes midashigo when another dictionary precedes SGKDJ', () {
      const multiDictHtml = '''
        <!DOCTYPE html>
        <html>
        <body>
          <div class="pbarT">Wikipedia 索引トップ</div>
          <div class="kijiWrp">
            <div class="kiji">
              <h2 class="midashigo">ウィキペディア見出し</h2>
              <p>百科事典の概要。</p>
            </div>
          </div>

          <a name="SGKDJ"></a>
          <div class="pbarT">デジタル大辞泉</div>
          <div class="kijiWrp">
            <div class="kiji">
              <h2 class="midashigo">うつく・しい【美しい】</h2>
              <div class="Sgkdj">
                <span class="hinshi">［形］</span>
                <p>色・形・音などの調和がとれていて快く感じられるさま。「―・しい花」</p>
              </div>
            </div>
          </div>
        </body>
        </html>
      ''';

      final result = service.parseHtml(multiDictHtml, '美しい');
      expect(result.sourceDict, 'デジタル大辞泉');
      expect(result.reading, 'うつくしい');
      expect(result.word, '美しい');
      expect(result.partOfSpeech, '形');
      expect(result.examples.first.kanji, '美しい花');
    });

    test('parseHtml falls back to first valid kiji when SGKDJ div is empty', () {
      const emptySgkdjHtml = '''
        <!DOCTYPE html>
        <html>
        <body>
          <a name="SGKDJ"></a>
          <div class="Sgkdj"></div>

          <div class="pbarT">三省堂国語辞典</div>
          <div class="kijiWrp">
            <div class="kiji">
              <h2 class="midashigo">テスト【test】</h2>
              <span class="hinshi">［名］</span>
              <p>実地に行う試み。</p>
            </div>
          </div>
        </body>
        </html>
      ''';

      final result = service.parseHtml(emptySgkdjHtml, 'テスト');
      expect(result.sourceDict, '三省堂国語辞典');
      expect(result.definition, contains('実地に行う試み。'));
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

    test('isRedirectDefinition correctly identifies grammatical redirects and distinguishes substantive definitions', () {
      expect(WeblioService.isRedirectDefinition('「こう（講）ずる」（サ変）の上一段化。'), isTrue);
      expect(WeblioService.isRedirectDefinition('「しん（信）ずる」（サ変）の上一段化。'), isTrue);
      expect(WeblioService.isRedirectDefinition('『講ずる』の上一段活用。'), isTrue);
      expect(WeblioService.isRedirectDefinition('「おっしゃる」に同じ。'), isTrue);
      expect(WeblioService.isRedirectDefinition('終止形\n書く » 「書く」の意味を調べる'), isTrue);
      expect(WeblioService.isRedirectDefinition('終止形\n愛す » 「愛す」の意味を調べる\n終止形\n愛する » 「愛する」の意味を調べる'), isTrue);

      // Substantive definition with numbered entries should not be considered pure redirect
      expect(WeblioService.isRedirectDefinition('［文］かう・ず［サ変］\n１ 講義をする。\n２ 問題を解決するために、考えをめぐらして適当な方法をとる。'), isFalse);
      expect(WeblioService.isRedirectDefinition('色・形・音などの調和がとれていて快く感じられるさま。'), isFalse);
      expect(WeblioService.isRedirectDefinition('２ 「食う」の謙譲語。いただく。'), isFalse);
      expect(WeblioService.isRedirectDefinition(''), isFalse);
    });

    test('hasSubstantiveDefinition identifies rich dictionary entries and rejects pure redirects or empty strings', () {
      expect(WeblioService.hasSubstantiveDefinition('［文］かう・ず［サ変］\n１ 講義をする。\n２ 適切な方法をとる。'), isTrue);
      expect(WeblioService.hasSubstantiveDefinition('色・形・音などの調和がとれていて快く感じられるさま。'), isTrue);
      expect(WeblioService.hasSubstantiveDefinition('「こう（講）ずる」（サ変）の上一段化。'), isFalse);
      expect(WeblioService.hasSubstantiveDefinition('終止形\n書く » 「書く」の意味を調べる'), isFalse);
      expect(WeblioService.hasSubstantiveDefinition(''), isFalse);
    });

    test('extractRedirectCandidates correctly extracts kanji and kana candidates from redirect text', () {
      final koujiruCands = WeblioService.extractRedirectCandidates('「こう（講）ずる」（サ変）の上一段化。', '講じる');
      expect(koujiruCands, contains('講ずる'));
      expect(koujiruCands, contains('こうずる'));

      // Adversarial test: Headword with middle dot morpheme separator must NOT truncate to 'こう'
      final dotKanaCands = WeblioService.extractRedirectCandidates('「こう・ずる」（サ変）の上一段化。', '講じる');
      expect(dotKanaCands, contains('こうずる'));
      expect(dotKanaCands, isNot(contains('こう')));

      // Headword with bracketed kanji headword notation 【...】
      final bracketHeadwordCands = WeblioService.extractRedirectCandidates('「こう・ずる【講ずる】」の上一段化。', '講じる');
      expect(bracketHeadwordCands, contains('講ずる'));
      expect(bracketHeadwordCands, contains('こうずる'));

      // Headword with kanji and kana in parentheses 講ずる（こうずる）
      final kanjiFirstCands = WeblioService.extractRedirectCandidates('「講ずる（こうずる）」の上一段化。', '講じる');
      expect(kanjiFirstCands, contains('講ずる'));
      expect(kanjiFirstCands, contains('こうずる'));

      // Arrow and unquoted redirects
      final arrowCands = WeblioService.extractRedirectCandidates('⇒ 講ずる［動サ変］', '講じる');
      expect(arrowCands, contains('講ずる'));

      final unbracketedCands = WeblioService.extractRedirectCandidates('講ずるの上一段活用。', '講じる');
      expect(unbracketedCands, contains('講ずる'));

      final shinjiruCands = WeblioService.extractRedirectCandidates('「しん（信）ずる」（サ変）の上一段化。', '信じる');
      expect(shinjiruCands, contains('信ずる'));
      expect(shinjiruCands, contains('しんずる'));

      final kakuCands = WeblioService.extractRedirectCandidates('終止形\n書く » 「書く」の意味を調べる', '書いて');
      expect(kakuCands, contains('書く'));

      final aisuCands = WeblioService.extractRedirectCandidates(
        '終止形\n愛す » 「愛す」の意味を調べる\n終止形\n愛する » 「愛する」の意味を調べる',
        '愛される',
      );
      expect(aisuCands, contains('愛す'));
      expect(aisuCands, contains('愛する'));

      final onajiCands = WeblioService.extractRedirectCandidates('「おっしゃる」に同じ。', '仰る');
      expect(onajiCands, contains('おっしゃる'));
    });

    test('isRedirectDefinition correctly handles numbered redirect lines and arrows', () {
      expect(WeblioService.isRedirectDefinition('１ 「こう（講）ずる」（サ変）の上一段化。'), isTrue);
      expect(WeblioService.isRedirectDefinition('１ 「講ずる」に同じ。'), isTrue);
      expect(WeblioService.isRedirectDefinition('⇒ 講ずる'), isTrue);
      expect(WeblioService.isRedirectDefinition('講ずるの上一段活用。'), isTrue);
    });

    test('parseHtml restores okurigana accurately without duplication when dash is followed by okurigana', () {
      const html = '''
        <!DOCTYPE html>
        <html>
        <body>
          <div class="kijiWrp">
            <div class="kiji">
              <h2 class="midashigo">こう・じる【講じる】</h2>
              <div class="Sgkdj">
                <span class="hinshi">［動ザ上一］</span>
                <p>「こう（講）ずる」（サ変）の上一段化。「適切な処置を―じる」</p>
              </div>
            </div>
          </div>
        </body>
        </html>
      ''';

      final result = service.parseHtml(html, '講じる');
      expect(result.examples.isNotEmpty, isTrue);
      // Must NOT be 適切な処置を講じるじる
      expect(result.examples.first.kanji, '適切な処置を講じる');
    });

    test('mergeRedirectResult preserves original headword and combines definitions and examples', () {
      const original = WeblioResult(
        word: '講じる',
        reading: 'こうじる',
        definition: '「こう（講）ずる」（サ変）の上一段化。',
        partOfSpeech: '動ザ上一',
        examples: [
          WeblioExample(kanji: '適切な処置を講じる', furigana: '適切な処置を講じる'),
        ],
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/%E8%AC%9B%E3%81%98%E3%82%8B',
      );

      const target = WeblioResult(
        word: '講ずる',
        reading: 'こうずる',
        definition: '１ 講義をする。\n２ 問題を解決するために、考えをめぐらして適当な方法をとる。',
        partOfSpeech: '動サ変',
        examples: [
          WeblioExample(kanji: '近代経済学を講ずる', furigana: '近代経済学を講ずる'),
          WeblioExample(kanji: '策を講ずる', furigana: '策を講ずる'),
        ],
        sourceDict: 'デジタル大辞泉',
        sourceUrl: 'https://www.weblio.jp/content/%E8%AC%9B%E3%81%9A%E3%82%8B',
      );

      final merged = WeblioService.mergeRedirectResult(original: original, target: target);

      expect(merged.word, '講じる');
      expect(merged.reading, 'こうじる');
      expect(merged.partOfSpeech, '動ザ上一');
      expect(merged.definition, contains('「こう（講）ずる」（サ変）の上一段化。'));
      expect(merged.definition, contains('１ 講義をする。'));
      expect(merged.definition, contains('２ 問題を解決するために'));
      expect(merged.examples.length, 2);
      expect(merged.examples[0].kanji, '適切な処置を講じる');
      expect(merged.examples[1].kanji, '近代経済学を講ずる');
    });

    test('lookupWord recursively traces redirect to root word (查到底) using Mock Dio', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final uriStr = options.uri.toString();
          if (uriStr.contains('%E8%AC%9B%E3%81%98%E3%82%8B')) { // 講じる
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: '''
                <!DOCTYPE html>
                <html>
                <body>
                  <div class="kijiWrp">
                    <div class="kiji">
                      <h2 class="midashigo">こう・じる【講じる】</h2>
                      <div class="Sgkdj">
                        <span class="hinshi">［動ザ上一］</span>
                        <p>「こう（講）ずる」（サ変）の上一段化。「適切な処置を―・じる」</p>
                      </div>
                    </div>
                  </div>
                </body>
                </html>
              ''',
            ));
          } else if (uriStr.contains('%E8%AC%9B%E3%81%9A%E3%82%8B')) { // 講ずる
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: '''
                <!DOCTYPE html>
                <html>
                <body>
                  <div class="kijiWrp">
                    <div class="kiji">
                      <h2 class="midashigo">こう・ずる【講ずる】</h2>
                      <div class="Sgkdj">
                        <span class="hinshi">［動サ変］</span>
                        <p>１ 講義をする。「近代経済学を―・ずる」</p>
                        <p>２ 適切な方法をとる。「策を―・ずる」</p>
                      </div>
                    </div>
                  </div>
                </body>
                </html>
              ''',
            ));
          }
          return handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
          ));
        },
      ));

      final mockService = WeblioService(dio: dio);
      final result = await mockService.lookupWord('講じる');

      expect(result.word, '講じる');
      expect(result.reading, 'こうじる');
      expect(result.partOfSpeech, contains('動ザ上一'));
      expect(result.definition, contains('「こう（講）ずる」（サ変）の上一段化。'));
      expect(result.definition, contains('１ 講義をする。'));
      expect(result.definition, contains('２ 適切な方法をとる。'));
      expect(result.examples.length, 2);
      expect(result.examples[0].kanji, '適切な処置を講じる');
      expect(result.examples[1].kanji, '近代経済学を講ずる');
    });

    test('lookupWord handles redirection loops safely without stack overflow', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final uriStr = options.uri.toString();
          if (uriStr.contains('wordA')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: '''
                <!DOCTYPE html>
                <html><body><div class="kiji"><p>「wordB」に同じ。</p></div></body></html>
              ''',
            ));
          } else if (uriStr.contains('wordB')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: '''
                <!DOCTYPE html>
                <html><body><div class="kiji"><p>「wordA」に同じ。</p></div></body></html>
              ''',
            ));
          }
          return handler.reject(DioException(requestOptions: options));
        },
      ));

      final mockService = WeblioService(dio: dio);
      final result = await mockService.lookupWord('wordA');
      expect(result.word, 'wordA');
      expect(result.definition, contains('wordB'));
    });
  });
}
