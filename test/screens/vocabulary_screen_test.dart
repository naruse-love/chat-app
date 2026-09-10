import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat/screens/vocabulary_screen.dart';
import 'package:chat/providers/vocabulary_provider.dart';
import 'package:chat/models/vocabulary_entry.dart';
import 'package:chat/services/vocabulary_service.dart';
import 'package:chat/data/vocabulary_dao.dart';

class MockVocabularyNotifier extends StateNotifier<VocabularyState>
    implements VocabularyNotifier {
  MockVocabularyNotifier(super.state);

  String? lastLookedUpWord;
  int? lastDeletedId;
  bool? lastForceRefresh;

  @override
  VocabularyService get vocabularyService => throw UnimplementedError();

  @override
  VocabularyDao get vocabularyDao => throw UnimplementedError();

  @override
  Future<void> loadEntries() async {}

  @override
  Future<void> lookupWord(String rawWord, {bool forceRefresh = false}) async {
    lastLookedUpWord = rawWord;
    lastForceRefresh = forceRefresh;
    state = state.copyWith(
      currentResult: VocabularyEntry(
        id: 1,
        vocabKanji: rawWord,
        vocabFurigana: 'ふりがな',
        vocabDefJa: '日文释义内容',
        vocabDefSc: '中文翻译内容',
        vocabPoS: '動バ下一',
        sentKanji1: '例句1',
        sentDefSc1: '例句1翻译',
        sourceDict: 'デジタル大辞泉',
        createdAt: DateTime.now(),
      ),
      entries: [
        VocabularyEntry(
          id: 1,
          vocabKanji: rawWord,
          vocabFurigana: 'ふりがな',
          vocabDefJa: '日文释义内容',
          vocabDefSc: '中文翻译内容',
          vocabPoS: '動バ下一',
          sentKanji1: '例句1',
          sentDefSc1: '例句1翻译',
          sourceDict: 'デジタル大辞泉',
          createdAt: DateTime.now(),
        ),
      ],
    );
  }

  @override
  Future<void> deleteEntry(int id) async {
    lastDeletedId = id;
    state = state.copyWith(
      entries: state.entries.where((e) => e.id != id).toList(),
      clearCurrentResult: state.currentResult?.id == id,
    );
  }

  @override
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  @override
  void selectEntry(VocabularyEntry entry) {
    state = state.copyWith(currentResult: entry);
  }

  @override
  void clearCurrentResult() {
    state = state.copyWith(clearCurrentResult: true);
  }
}

void main() {
  testWidgets('VocabularyScreen renders search bar, empty hint and help dialog', (tester) async {
    final mockNotifier = MockVocabularyNotifier(const VocabularyState());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyProvider.overrideWith((ref) => mockNotifier),
        ],
        child: const MaterialApp(
          home: VocabularyScreen(),
        ),
      ),
    );

    expect(find.text('📚 单词本'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('查询'), findsOneWidget);
    expect(find.text('单词本暂无记录，输入单词即可查询并保存'), findsOneWidget);

    // Tap help button
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(find.text('关于单词本'), findsOneWidget);
    expect(find.text('了解'), findsOneWidget);
    await tester.tap(find.text('了解'));
    await tester.pumpAndSettle();
  });

  testWidgets('VocabularyScreen input triggers lookup and displays result card', (tester) async {
    final mockNotifier = MockVocabularyNotifier(const VocabularyState());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyProvider.overrideWith((ref) => mockNotifier),
        ],
        child: const MaterialApp(
          home: VocabularyScreen(),
        ),
      ),
    );

    // Enter word
    await tester.enterText(find.byType(TextField), '食べる');
    await tester.pump();

    // Tap query button
    await tester.tap(find.text('查询'));
    await tester.pumpAndSettle();

    expect(mockNotifier.lastLookedUpWord, '食べる');
    expect(find.text('食べる'), findsNWidgets(3)); // TextField + Card + List item
    expect(find.text('ふりがな'), findsNWidgets(2));
    expect(find.text('動バ下一'), findsNWidgets(2));
    expect(find.text('中文释义'), findsOneWidget);
    expect(find.text('中文翻译内容'), findsNWidgets(2));
    expect(find.text('例句'), findsOneWidget);
    expect(find.text('例句1'), findsOneWidget);

    // Tap refresh button on the card
    final refreshBtn = find.byTooltip('重新抓取与翻译');
    expect(refreshBtn, findsOneWidget);
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();

    expect(mockNotifier.lastLookedUpWord, '食べる');
    expect(mockNotifier.lastForceRefresh, isTrue);
  });

  testWidgets('VocabularyScreen swipe-to-delete triggers deleteEntry and shows SnackBar', (tester) async {
    final mockNotifier = MockVocabularyNotifier(VocabularyState(
      entries: [
        VocabularyEntry(
          id: 42,
          vocabKanji: '走る',
          vocabFurigana: 'はしる',
          vocabDefJa: '走る释义',
          createdAt: DateTime.now(),
        ),
      ],
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyProvider.overrideWith((ref) => mockNotifier),
        ],
        child: const MaterialApp(
          home: VocabularyScreen(),
        ),
      ),
    );

    expect(find.text('走る'), findsOneWidget);

    // Swipe dismissible to delete
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(mockNotifier.lastDeletedId, 42);
    expect(find.text('已删除「走る」'), findsOneWidget);
  });
}
