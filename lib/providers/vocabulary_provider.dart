import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/vocabulary_dao.dart';
import '../models/vocabulary_entry.dart';
import '../services/vocabulary_service.dart';
import '../services/weblio_service.dart';
import 'api_config_provider.dart';
import 'model_provider.dart';

/// 单词本状态
class VocabularyState {
  final List<VocabularyEntry> entries;
  final VocabularyEntry? currentResult;
  final bool isLoading;
  final String? error;
  final String searchQuery;

  const VocabularyState({
    this.entries = const [],
    this.currentResult,
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
  });

  VocabularyState copyWith({
    List<VocabularyEntry>? entries,
    VocabularyEntry? currentResult,
    bool clearCurrentResult = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? searchQuery,
  }) {
    return VocabularyState(
      entries: entries ?? this.entries,
      currentResult: clearCurrentResult ? null : (currentResult ?? this.currentResult),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

/// 单词本 StateNotifier 状态管理器
class VocabularyNotifier extends StateNotifier<VocabularyState> {
  final VocabularyService vocabularyService;
  final VocabularyDao vocabularyDao;

  VocabularyNotifier(this.vocabularyService, this.vocabularyDao)
      : super(const VocabularyState()) {
    loadEntries();
  }

  /// 加载生词列表（带可选搜索过滤）
  Future<void> loadEntries() async {
    try {
      final list = await vocabularyDao.getAll(searchQuery: state.searchQuery);
      if (!mounted) return;
      state = state.copyWith(entries: list);
    } catch (_) {}
  }

  /// 查词主流程
  Future<void> lookupWord(String rawWord, {bool forceRefresh = false}) async {
    final word = rawWord.trim();
    if (word.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final result = await vocabularyService.lookupWord(
        word,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;

      final freshList = await vocabularyDao.getAll(searchQuery: state.searchQuery);
      if (!mounted) return;

      state = state.copyWith(
        isLoading: false,
        currentResult: result,
        entries: freshList,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 删除指定单词
  Future<void> deleteEntry(int id) async {
    await vocabularyDao.delete(id);
    if (!mounted) return;

    final shouldClear = state.currentResult?.id == id;
    final freshList = await vocabularyDao.getAll(searchQuery: state.searchQuery);
    if (!mounted) return;

    state = state.copyWith(
      entries: freshList,
      clearCurrentResult: shouldClear,
    );
  }

  /// 设置搜索关键词
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    loadEntries();
  }

  /// 选中历史单词并在卡片中展示详情
  void selectEntry(VocabularyEntry entry) {
    state = state.copyWith(currentResult: entry, clearError: true);
  }

  /// 清除当前卡片展示
  void clearCurrentResult() {
    state = state.copyWith(clearCurrentResult: true);
  }
}

// === Riverpod Providers ===

final vocabularyDaoProvider = Provider<VocabularyDao>((ref) {
  final dbHelper = ref.watch(dbHelperProvider);
  return VocabularyDao(dbHelper: dbHelper);
});

final weblioServiceProvider = Provider<WeblioService>((ref) => WeblioService());

final vocabularyServiceProvider = Provider<VocabularyService>((ref) {
  final dao = ref.watch(vocabularyDaoProvider);
  final weblio = ref.watch(weblioServiceProvider);
  final chatSvc = ref.watch(chatServiceProvider);
  final apiDao = ref.watch(apiConfigDaoProvider);
  return VocabularyService(
    vocabularyDao: dao,
    weblioService: weblio,
    chatService: chatSvc,
    apiConfigDao: apiDao,
    ref: ref,
  );
});

final vocabularyProvider =
    StateNotifierProvider<VocabularyNotifier, VocabularyState>((ref) {
  final service = ref.watch(vocabularyServiceProvider);
  final dao = ref.watch(vocabularyDaoProvider);
  return VocabularyNotifier(service, dao);
});
