import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chat/screens/vocabulary_screen.dart';
import 'package:chat/providers/vocabulary_provider.dart';
import 'package:chat/models/vocabulary_entry.dart';
import 'package:chat/services/vocabulary_service.dart';
import 'package:chat/data/vocabulary_dao.dart';

import 'package:chat/models/word_candidate.dart';
import 'package:chat/models/api_config.dart';
import 'package:chat/models/model_info.dart';
import 'package:chat/providers/vocabulary_config_provider.dart';
import 'package:chat/services/native/native_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockVocabularyNotifier extends StateNotifier<VocabularyState>
    implements VocabularyNotifier {
  MockVocabularyNotifier(super.state);

  String? lastLookedUpWord;
  int? lastDeletedId;
  bool? lastForceRefresh;
  WordCandidate? lastSelectedCandidate;
  bool lastConfirmedOriginal = false;
  bool lastDismissedCandidates = false;

  @override
  VocabularyService get vocabularyService => throw UnimplementedError();

  @override
  VocabularyDao get vocabularyDao => throw UnimplementedError();

  @override
  Future<void> loadEntries() async {}

  @override
  Future<void> lookupWord(
    String rawWord, {
    bool forceRefresh = false,
    bool checkConfirmation = false,
    bool forceDirect = false,
  }) async {
    lastLookedUpWord = rawWord;
    lastForceRefresh = forceRefresh;
    state = state.copyWith(
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
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
  Future<void> selectCandidate(WordCandidate candidate) async {
    lastSelectedCandidate = candidate;
    state = state.copyWith(
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
    );
    await lookupWord(candidate.searchWord, forceDirect: true);
  }

  @override
  Future<void> confirmOriginalWord() async {
    lastConfirmedOriginal = true;
    final orig = state.pendingCandidateWord;
    state = state.copyWith(
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
    );
    if (orig != null) {
      await lookupWord(orig, forceDirect: true);
    }
  }

  @override
  void dismissCandidates() {
    lastDismissedCandidates = true;
    state = state.copyWith(
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
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

  int retranslateCallCount = 0;

  @override
  Future<void> retranslateEntry(VocabularyEntry entry) async {
    retranslateCallCount++;
    state = state.copyWith(
      currentResult: entry.copyWith(vocabDefSc: '重新生成的中文释义'),
    );
  }

  @override
  void clearError() {
    state = state.copyWith(clearError: true);
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

  testWidgets('VocabularyScreen renders candidate confirmation card and selects candidate', (tester) async {
    final mockNotifier = MockVocabularyNotifier(const VocabularyState(
      pendingCandidateWord: 'はし',
      candidateReason: CandidateReason.pureKana,
      candidates: [
        WordCandidate(
          kanji: '箸',
          reading: 'はし',
          definition: '筷子。用餐工具',
          partOfSpeech: '名',
        ),
        WordCandidate(
          kanji: '橋',
          reading: 'はし',
          definition: '桥梁。过河建筑',
          partOfSpeech: '名',
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

    expect(find.text('假名同音多义词确认'), findsOneWidget);
    expect(find.text('您输入的是纯假名「はし」，可能对应以下汉字与含义，请选择您的目标词：'), findsOneWidget);
    expect(find.text('箸'), findsOneWidget);
    expect(find.text('筷子。用餐工具'), findsOneWidget);
    expect(find.text('橋'), findsOneWidget);

    // Tap candidate '箸'
    await tester.tap(find.text('箸'));
    await tester.pumpAndSettle();

    expect(mockNotifier.lastSelectedCandidate?.kanji, '箸');
  });

  testWidgets('VocabularyScreen persistent notification toggle button toggles state and shows SnackBar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final mockNotifier = MockVocabularyNotifier(const VocabularyState());
    final fakeNotifService = InMemoryPersistentNotificationService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyProvider.overrideWith((ref) => mockNotifier),
          persistentNotificationServiceProvider.overrideWithValue(fakeNotifService),
        ],
        child: const MaterialApp(
          home: VocabularyScreen(),
        ),
      ),
    );

    final notifBtn = find.byTooltip('开启通知栏常驻查词快捷入口');
    expect(notifBtn, findsOneWidget);

    await tester.tap(notifBtn);
    await tester.pumpAndSettle();

    expect(find.text('已开启通知栏快捷常驻入口'), findsOneWidget);
    expect(await fakeNotifService.isNotificationActive('chat_persistent_vocab'), isTrue);
  });

  testWidgets('VocabularyScreen error card close button clears error via clearError', (tester) async {
    final mockNotifier = MockVocabularyNotifier(const VocabularyState(
      error: '查询失败：网络不可用',
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

    expect(find.text('查询失败：网络不可用'), findsOneWidget);

    // Find and tap close button on error card
    final closeIcon = find.byIcon(Icons.close);
    expect(closeIcon, findsOneWidget);
    await tester.tap(closeIcon);
    await tester.pumpAndSettle();

    expect(mockNotifier.state.error, isNull);
    expect(find.text('查询失败：网络不可用'), findsNothing);
  });

  testWidgets('VocabularyScreen autoFocusLookup requests focus on text field', (tester) async {
    final mockNotifier = MockVocabularyNotifier(const VocabularyState());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyProvider.overrideWith((ref) => mockNotifier),
        ],
        child: const MaterialApp(
          home: VocabularyScreen(autoFocusLookup: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField).first);
    expect(textField.focusNode?.hasFocus, isTrue);
  });

  testWidgets('VocabularyScreen model indicator chip renders and does not overflow on 320px viewport with long name', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockNotifier = MockVocabularyNotifier(const VocabularyState());
    final longModel = ModelInfo(
      id: 'extremely-long-custom-model-id-for-japanese-translation-evaluation-v3-enterprise',
      provider: 'Very Long Provider Name Incorporated',
      modelName: 'extremely-long-custom-model-id-for-japanese-translation-evaluation-v3-enterprise',
      supportsVision: false,
      supportsTools: true,
    );

    final vocabConfigNotifier = MockVocabularyConfigNotifier(VocabularyConfigState(
      config: ApiConfig(
        id: 'cfg_long',
        name: 'Very Long Provider Name Incorporated',
        baseUrl: 'https://long-provider.com/v1',
        apiKeyRef: 'k_long',
        isDefault: false,
        createdAt: DateTime.now(),
      ),
      model: longModel,
      availableModels: [longModel],
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vocabularyProvider.overrideWith((ref) => mockNotifier),
          vocabularyConfigProvider.overrideWith((ref) => vocabConfigNotifier),
        ],
        child: const MaterialApp(
          home: VocabularyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify no RenderFlex overflow exception occurred!
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
  });

  testWidgets('VocabularyScreen shows 生成释义 when vocabDefSc is empty and invokes retranslateEntry on tap', (tester) async {
    final entryWithoutSc = VocabularyEntry(
      id: 10,
      vocabKanji: '青空',
      vocabFurigana: 'あおぞら',
      vocabDefJa: '晴れわたった青い空。',
      vocabDefSc: '', // Empty!
      vocabPoS: '名',
      sourceDict: '大辞泉',
      createdAt: DateTime.now(),
    );

    final mockNotifier = MockVocabularyNotifier(VocabularyState(
      currentResult: entryWithoutSc,
      entries: [entryWithoutSc],
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
    await tester.pumpAndSettle();

    expect(find.text('未配置 API 模型或暂无中文释义'), findsOneWidget);
    final generateBtn = find.text('生成释义');
    expect(generateBtn, findsOneWidget);

    await tester.tap(generateBtn);
    await tester.pumpAndSettle();

    expect(mockNotifier.retranslateCallCount, 1);
  });

  testWidgets('VocabularyScreen shows 重新生成 when vocabDefSc is present and invokes retranslateEntry on tap', (tester) async {
    final entryWithSc = VocabularyEntry(
      id: 11,
      vocabKanji: '星空',
      vocabFurigana: 'ほしぞら',
      vocabDefJa: '星の出ている夜空。',
      vocabDefSc: '繁星密布的夜空。',
      vocabPoS: '名',
      sourceDict: '大辞泉',
      createdAt: DateTime.now(),
    );

    final mockNotifier = MockVocabularyNotifier(VocabularyState(
      currentResult: entryWithSc,
      entries: [entryWithSc],
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
    await tester.pumpAndSettle();

    expect(find.text('繁星密布的夜空。'), findsAtLeastNWidgets(1));
    final regenerateBtn = find.byTooltip('使用专属模型重新生成释义');
    expect(regenerateBtn, findsOneWidget);

    await tester.tap(regenerateBtn);
    await tester.pumpAndSettle();

    expect(mockNotifier.retranslateCallCount, 1);
  });

  testWidgets('VocabularyScreen renders polysemous word with many definitions (like 君) without overflow', (tester) async {
    final multiDefEntry = VocabularyEntry(
      id: 99,
      vocabKanji: '君',
      vocabFurigana: 'きみ',
      vocabDefJa:
          '１ 主君。君主。「君に忠義を尽くす」\n'
          '２ 天皇。また、国家。\n'
          '３ 妻が夫をいう語。\n'
          '４ 遊女・芸妓などをいう語。「室の君」\n'
          '５ 敬意をもって呼ぶ語。あなた様。\n'
          '６ 同輩や後輩を親しんで呼ぶ語。きみ。「君、どう思う？」\n'
          '７ 女性が恋人や夫を親しんで呼ぶ語。\n'
          '８ 神仏などを敬っていう語。\n'
          '９ ［下接語］大君・若君・小君・我が君',
      vocabDefSc:
          '1. （古代称呼）君主，帝王。\n'
          '2. 贵人，长辈。\n'
          '3. （女性对男性恋人或丈夫的亲昵称呼）你，君。\n'
          '4. （平辈或对晚辈、后辈的第二人称代词）你。\n'
          '5. （接尾词）...君（尊称或同辈称呼）。\n'
          '6. 神明或敬仰的对象。\n'
          '7. 封建时代对领主的尊称。\n'
          '8. 艺妓、游女的雅称。\n'
          '9. （下接语）若君、小君。',
      vocabPoS: '名・代',
      sentKanji1: '君に忠義を尽くす',
      sentDefSc1: '向主君尽忠',
      sentKanji2: '君はどう思うか',
      sentDefSc2: '你觉得怎么样？',
      sourceDict: 'デジタル大辞泉',
      createdAt: DateTime.now(),
    );

    final mockNotifier = MockVocabularyNotifier(VocabularyState(
      currentResult: multiDefEntry,
      entries: [multiDefEntry],
    ));

    // Test on a standard mobile viewport (360x640)
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
    await tester.pumpAndSettle();

    // Verify it renders the word and definitions without throwing any RenderFlex overflow
    expect(find.text('君'), findsAtLeastNWidgets(2)); // Card + List
    expect(find.text('きみ'), findsAtLeastNWidgets(1));
    expect(find.text('名・代'), findsAtLeastNWidgets(1));
    expect(find.text('中文释义'), findsOneWidget);
  });
}

class MockVocabularyConfigNotifier extends StateNotifier<VocabularyConfigState>
    implements VocabularyConfigNotifier {
  @override
  late final Future<void> initialization = Future.value();

  MockVocabularyConfigNotifier(super.state);

  @override
  set initialization(Future<void> value) {}

  @override
  Future<void> addCustomModel(String modelId) async {}

  @override
  Future<void> fetchModels({bool forceRefresh = false}) async {}

  @override
  Future<void> resetToDefault() async {}

  @override
  Future<void> setConfig(ApiConfig config) async {}

  @override
  Future<void> setModel(ModelInfo model) async {}
}
