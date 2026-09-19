import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/vocabulary_dao.dart';
import '../models/vocabulary_entry.dart';
import '../models/word_candidate.dart';
import '../services/anki_export_service.dart';
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

  /// 候选词确认列表（纯假名多汉字/AI推测候选）
  final List<WordCandidate>? candidates;

  /// 触发候选确认的原始输入单词
  final String? pendingCandidateWord;

  /// 触发候选确认的原因类型
  final CandidateReason? candidateReason;

  /// AnkiDroid 导出中状态
  final bool isExporting;

  /// 未导出到 Anki 的单词数量
  final int unexportedCount;

  const VocabularyState({
    this.entries = const [],
    this.currentResult,
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.candidates,
    this.pendingCandidateWord,
    this.candidateReason,
    this.isExporting = false,
    this.unexportedCount = 0,
  });

  VocabularyState copyWith({
    List<VocabularyEntry>? entries,
    VocabularyEntry? currentResult,
    bool clearCurrentResult = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? searchQuery,
    List<WordCandidate>? candidates,
    bool clearCandidates = false,
    String? pendingCandidateWord,
    bool clearPendingCandidateWord = false,
    CandidateReason? candidateReason,
    bool clearCandidateReason = false,
    bool? isExporting,
    int? unexportedCount,
  }) {
    return VocabularyState(
      entries: entries ?? this.entries,
      currentResult:
          clearCurrentResult ? null : (currentResult ?? this.currentResult),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      candidates: clearCandidates ? null : (candidates ?? this.candidates),
      pendingCandidateWord: clearPendingCandidateWord
          ? null
          : (pendingCandidateWord ?? this.pendingCandidateWord),
      candidateReason: clearCandidateReason
          ? null
          : (candidateReason ?? this.candidateReason),
      isExporting: isExporting ?? this.isExporting,
      unexportedCount: unexportedCount ?? this.unexportedCount,
    );
  }
}

/// 单词本 StateNotifier 状态管理器
class VocabularyNotifier extends StateNotifier<VocabularyState> {
  final VocabularyService vocabularyService;
  final VocabularyDao vocabularyDao;
  final AnkiExportServiceInterface ankiExportService;

  VocabularyNotifier(
    this.vocabularyService,
    this.vocabularyDao, [
    AnkiExportServiceInterface? ankiExportService,
  ])  : ankiExportService = ankiExportService ?? AnkiExportService(),
        super(const VocabularyState()) {
    loadEntries();
    loadUnexportedCount();
  }

  /// 加载生词列表（带可选搜索过滤）
  Future<void> loadEntries() async {
    try {
      final list = await vocabularyDao.getAll(searchQuery: state.searchQuery);
      final count = await vocabularyDao.unexportedCount();
      if (!mounted) return;
      state = state.copyWith(entries: list, unexportedCount: count);
    } catch (_) {}
  }

  /// 加载未导出计数
  Future<void> loadUnexportedCount() async {
    try {
      final count = await vocabularyDao.unexportedCount();
      if (!mounted) return;
      state = state.copyWith(unexportedCount: count);
    } catch (_) {}
  }

  /// 查词主流程（支持候选词消歧与推测确认）：
  /// - [checkConfirmation]: 当为 true 且用户输入纯假名且存在多个汉字含义时，或词典未收录且 AI 推测出候选时，暂停自动入库，呈现候选列表供用户确认
  /// - [forceDirect]: 强制跳过候选词确认直接查词入库（例如用户在候选列表中已选中目标词或明确坚持原输入）
  Future<void> lookupWord(
    String rawWord, {
    bool forceRefresh = false,
    bool checkConfirmation = false,
    bool forceDirect = false,
    String? targetReading,
  }) async {
    final extracted = VocabularyService.extractWordAndReading(rawWord);
    final word = extracted.word;
    final effectiveTargetReading = targetReading ?? extracted.reading;
    if (word.isEmpty) return;

    // 清理先前的候选状态与错误
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
    );

    // 1. 若开启候选确认且非强制直查：检查是否为纯假名输入或汉字同形多音词
    if (checkConfirmation && !forceDirect && effectiveTargetReading == null) {
      if (VocabularyService.isPureKana(word)) {
        try {
          final kanaCandidates =
              await vocabularyService.getPureKanaCandidates(word);
          if (!mounted) return;

          // 若发现存在多个不同汉字/释义候选，呈现供用户选择
          if (kanaCandidates.length > 1) {
            state = state.copyWith(
              isLoading: false,
              candidates: kanaCandidates,
              pendingCandidateWord: word,
              candidateReason: CandidateReason.pureKana,
            );
            return;
          }
        } catch (_) {
          if (!mounted) return;
        }
      } else {
        // 汉字同形多音词消歧（如「盛る」存在「さかる」和「もる」）
        try {
          final candidates =
              await vocabularyService.weblioService.fetchCandidates(word);
          if (!mounted) return;

          final matchedCandidates = candidates.where((c) {
            return c.searchWord == word ||
                c.kanji == word ||
                c.kanji.startsWith('$word ') ||
                c.kanji.startsWith('$word(') ||
                c.kanji.startsWith('$word（');
          }).toList();

          final distinctReadings = <String>{};
          for (final c in matchedCandidates) {
            final r = WeblioService.cleanReading(c.reading);
            if (r.isNotEmpty && r != word) {
              distinctReadings.add(r);
            }
          }

          if (distinctReadings.length > 1) {
            // 过滤有效候选：排除读音缺失、读音等于原词汉字或释义为空的项
            final validCandidates = matchedCandidates.where((c) {
              final r = WeblioService.cleanReading(c.reading);
              return r.isNotEmpty && r != word && c.definition.trim().isNotEmpty;
            }).toList();

            state = state.copyWith(
              isLoading: false,
              candidates: validCandidates.isNotEmpty ? validCandidates : matchedCandidates,
              pendingCandidateWord: word,
              candidateReason: CandidateReason.heteronym,
            );
            return;
          }
        } catch (_) {
          if (!mounted) return;
        }
      }
    }

    // 2. 执行核心查词
    try {
      final result = await vocabularyService.lookupWord(
        word,
        forceRefresh: forceRefresh,
        allowLlmFallback: !checkConfirmation || forceDirect,
        targetReading: effectiveTargetReading,
      );
      if (!mounted) return;

      final freshList =
          await vocabularyDao.getAll(searchQuery: state.searchQuery);
      final count = await vocabularyDao.unexportedCount();
      if (!mounted) return;

      state = state.copyWith(
        isLoading: false,
        currentResult: result,
        entries: freshList,
        unexportedCount: count,
        clearCandidates: true,
        clearPendingCandidateWord: true,
        clearCandidateReason: true,
      );
    } catch (e) {
      if (!mounted) return;

      // 3. 若核心查词失败（词典未收录或异常），且开启了候选确认且配置了 AI：尝试 AI 纠错与智能推测
      if (checkConfirmation &&
          !forceDirect &&
          vocabularyService.hasLlmConfigured) {
        try {
          final inferred = await vocabularyService.inferTypoCandidates(word);
          if (!mounted) return;

          if (inferred.isNotEmpty) {
            state = state.copyWith(
              isLoading: false,
              candidates: inferred,
              pendingCandidateWord: word,
              candidateReason: CandidateReason.typoOrNotFound,
            );
            return;
          }
        } catch (_) {
          if (!mounted) return;
        }
      }

      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        clearCandidates: true,
        clearPendingCandidateWord: true,
        clearCandidateReason: true,
      );
    }
  }

  /// 用户从候选列表中选中具体单词
  Future<void> selectCandidate(WordCandidate candidate) async {
    state = state.copyWith(
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
    );
    await lookupWord(
      candidate.searchWord,
      forceDirect: true,
      forceRefresh: true,
      targetReading: candidate.reading,
    );
  }

  /// 用户坚持按原输入（无论假名还是笔误）强制查询
  Future<void> confirmOriginalWord() async {
    final original = state.pendingCandidateWord;
    state = state.copyWith(
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
    );
    if (original != null && original.isNotEmpty) {
      await lookupWord(original, forceDirect: true);
    }
  }

  /// 关闭/取消候选词选择
  void dismissCandidates() {
    state = state.copyWith(
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
    );
  }

  /// 删除指定单词
  Future<void> deleteEntry(int id) async {
    // 立即从当前内存列表中剔除，保证 Dismissible 动画完成后同步树状态
    final updatedList = state.entries.where((e) => e.id != id).toList();
    final shouldClear = state.currentResult?.id == id;
    state = state.copyWith(
      entries: updatedList,
      clearCurrentResult: shouldClear,
    );

    try {
      await vocabularyDao.delete(id);
    } catch (_) {}

    if (!mounted) return;
    final freshList =
        await vocabularyDao.getAll(searchQuery: state.searchQuery);
    final count = await vocabularyDao.unexportedCount();
    if (!mounted) return;

    state = state.copyWith(
      entries: freshList,
      unexportedCount: count,
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
    state = state.copyWith(
      currentResult: entry,
      clearError: true,
      clearCandidates: true,
      clearPendingCandidateWord: true,
      clearCandidateReason: true,
    );
  }

  /// 清除当前卡片展示
  void clearCurrentResult() {
    state = state.copyWith(clearCurrentResult: true);
  }

  /// 对已存入生词本但缺少中文释义的单词重新调用 LLM 进行翻译
  Future<void> retranslateEntry(VocabularyEntry entry) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final updated = await vocabularyService.retranslateEntry(entry);
      if (!mounted) return;
      final freshList =
          await vocabularyDao.getAll(searchQuery: state.searchQuery);
      final count = await vocabularyDao.unexportedCount();
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        currentResult: updated,
        entries: freshList,
        unexportedCount: count,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 清除当前错误提示
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// 导出所有未导出的生词到 AnkiDroid（若 [forceAll] 为 true，全量检查所有生词并利用 Anki 原生查重机制补漏）
  Future<AnkiExportResult> exportToAnki({
    String? deckName,
    String? modelName,
    bool forceAll = false,
  }) async {
    state = state.copyWith(isExporting: true, clearError: true);
    try {
      final List<VocabularyEntry> entriesToExport;
      if (forceAll) {
        entriesToExport = await vocabularyDao.getAll();
      } else {
        entriesToExport = await vocabularyDao.getUnexported();
      }
      if (entriesToExport.isEmpty) {
        if (!mounted) return const AnkiExportResult();
        state = state.copyWith(isExporting: false);
        return const AnkiExportResult();
      }

      final result = await ankiExportService.exportEntries(
        entriesToExport,
        deckName: deckName,
        modelName: modelName,
      );

      final failedIds =
          result.failedEntries.map((e) => e.id).whereType<int>().toSet();
      final idsToMark = entriesToExport
          .where((e) => e.id != null && !failedIds.contains(e.id))
          .map((e) => e.id!)
          .toList();

      if (idsToMark.isNotEmpty) {
        await vocabularyDao.markAllAsExported(idsToMark);
      }

      if (!mounted) return result;
      final freshList =
          await vocabularyDao.getAll(searchQuery: state.searchQuery);
      final count = await vocabularyDao.unexportedCount();
      VocabularyEntry? updatedCurrent = state.currentResult;
      if (updatedCurrent != null && updatedCurrent.id != null) {
        updatedCurrent = freshList.firstWhere(
          (e) => e.id == updatedCurrent!.id,
          orElse: () => updatedCurrent!,
        );
      }
      if (!mounted) return result;
      state = state.copyWith(
        isExporting: false,
        entries: freshList,
        unexportedCount: count,
        currentResult: updatedCurrent,
      );
      return result;
    } catch (e) {
      if (!mounted) {
        return AnkiExportResult(
          failedEntries: const [],
          errors: [e.toString()],
        );
      }
      state = state.copyWith(isExporting: false, error: e.toString());
      return AnkiExportResult(
        failedEntries: const [],
        errors: [e.toString()],
      );
    }
  }

  /// 单独导出单个生词到 AnkiDroid（支持重复导出，借助 Anki 原生查重防重与删后补漏）
  Future<AnkiExportResult> exportSingleEntry(
    VocabularyEntry entry, {
    String? deckName,
    String? modelName,
  }) async {
    state = state.copyWith(isExporting: true, clearError: true);
    try {
      final result = await ankiExportService.exportEntries(
        [entry],
        deckName: deckName,
        modelName: modelName,
      );

      if (entry.id != null && result.failedEntries.isEmpty) {
        await vocabularyDao.markAsExported(entry.id!);
      }

      if (!mounted) return result;
      final freshList =
          await vocabularyDao.getAll(searchQuery: state.searchQuery);
      final count = await vocabularyDao.unexportedCount();
      VocabularyEntry? updatedCurrent = state.currentResult;
      if (updatedCurrent != null && updatedCurrent.id == entry.id) {
        updatedCurrent = freshList.firstWhere(
          (e) => e.id == entry.id,
          orElse: () => entry.copyWith(exportedToAnki: true),
        );
      }
      if (!mounted) return result;
      state = state.copyWith(
        isExporting: false,
        entries: freshList,
        unexportedCount: count,
        currentResult: updatedCurrent,
      );
      return result;
    } catch (e) {
      if (!mounted) {
        return AnkiExportResult(
          failedEntries: [entry],
          errors: [e.toString()],
        );
      }
      state = state.copyWith(isExporting: false, error: e.toString());
      return AnkiExportResult(
        failedEntries: [entry],
        errors: [e.toString()],
      );
    }
  }

  /// 重置所有生词的 Anki 导出状态
  Future<void> resetExportStatus() async {
    try {
      await vocabularyDao.resetExportStatus();
      if (!mounted) return;
      final freshList =
          await vocabularyDao.getAll(searchQuery: state.searchQuery);
      final count = await vocabularyDao.unexportedCount();
      if (!mounted) return;
      state = state.copyWith(
        entries: freshList,
        unexportedCount: count,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: e.toString());
    }
  }
}

// === Riverpod Providers ===

final ankiExportServiceProvider =
    Provider<AnkiExportServiceInterface>((ref) => AnkiExportService());

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
  final ankiExport = ref.watch(ankiExportServiceProvider);
  return VocabularyNotifier(service, dao, ankiExport);
});
