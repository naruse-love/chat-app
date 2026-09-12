import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vocabulary_entry.dart';
import '../services/native/native_services.dart';
import '../services/vocabulary_service.dart';
import '../services/weblio_service.dart';
import 'vocabulary_provider.dart';

/// 常驻通知状态
class PersistentNotificationState {
  final bool isEnabled;
  final bool isInitializing;
  final bool isSearching;
  final String? lastSearchedWord;
  final String? lastSearchResult;
  final String? lastSearchError;

  const PersistentNotificationState({
    this.isEnabled = false,
    this.isInitializing = true,
    this.isSearching = false,
    this.lastSearchedWord,
    this.lastSearchResult,
    this.lastSearchError,
  });

  PersistentNotificationState copyWith({
    bool? isEnabled,
    bool? isInitializing,
    bool? isSearching,
    String? lastSearchedWord,
    bool clearLastSearchedWord = false,
    String? lastSearchResult,
    bool clearLastSearchResult = false,
    String? lastSearchError,
    bool clearLastSearchError = false,
  }) {
    return PersistentNotificationState(
      isEnabled: isEnabled ?? this.isEnabled,
      isInitializing: isInitializing ?? this.isInitializing,
      isSearching: isSearching ?? this.isSearching,
      lastSearchedWord: clearLastSearchedWord
          ? null
          : (lastSearchedWord ?? this.lastSearchedWord),
      lastSearchResult: clearLastSearchResult
          ? null
          : (lastSearchResult ?? this.lastSearchResult),
      lastSearchError: clearLastSearchError
          ? null
          : (lastSearchError ?? this.lastSearchError),
    );
  }
}

/// 系统通知栏常驻查词快捷入口状态管理
class PersistentNotificationNotifier
    extends StateNotifier<PersistentNotificationState> {
  static const String prefKey = 'persistent_vocab_shortcut_enabled';
  static const String notificationId = 'chat_persistent_vocab';
  static const String notificationTitle = '📚 日语生词快捷查询';
  static const String notificationBody = '点击「🔍 输入单词」直接在通知栏查词并展示释义';
  static const String notificationPayload = '/vocabulary';

  final IPersistentNotificationService _notificationService;
  final VocabularyService? vocabularyService;
  final Function? onWordSaved;
  StreamSubscription<String>? _inlineQuerySub;
  int _searchSeq = 0;

  PersistentNotificationNotifier(
    this._notificationService, {
    this.vocabularyService,
    this.onWordSaved,
  })  : super(const PersistentNotificationState()) {
    _initPreference();
    _listenToInlineQueries();
  }

  void _invokeWordSaved([VocabularyEntry? entry]) {
    final cb = onWordSaved;
    if (cb == null) return;
    if (cb is void Function(VocabularyEntry?)) {
      cb(entry);
    } else if (cb is void Function(VocabularyEntry)) {
      if (entry != null) cb(entry);
    } else if (cb is void Function()) {
      cb();
    } else {
      try {
        (cb as dynamic)(entry);
      } catch (_) {
        try {
          (cb as dynamic)();
        } catch (_) {}
      }
    }
  }

  void _listenToInlineQueries() {
    _inlineQuerySub =
        _notificationService.onInlineQuerySubmitted.listen((query) {
      handleInlineSearch(query);
    });
  }

  @override
  void dispose() {
    _inlineQuerySub?.cancel();
    super.dispose();
  }

  Future<void> _initPreference() async {
    try {
      // 1. 获取并立即处理冷启动/后台唤醒时由通知栏提交的待处理查询
      final pendingQueries =
          await _notificationService.getPendingInlineQueries();
      for (final query in pendingQueries) {
        unawaited(handleInlineSearch(query));
      }

      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final enabled = prefs.getBool(prefKey) ?? false;
      if (enabled) {
        // 仅在当前未在查词且未有查词结果时显示默认初始常驻通知，避免冲掉正在查询或最新结果卡片
        if (!state.isSearching && state.lastSearchedWord == null) {
          await _notificationService.showPersistentNotification(
            id: notificationId,
            title: notificationTitle,
            body: notificationBody,
            payload: notificationPayload,
          );
        }
        if (!mounted) return;
      }

      state = state.copyWith(
        isEnabled: enabled,
        isInitializing: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isInitializing: false);
    }
  }

  /// 切换常驻通知栏快捷入口开关
  Future<void> togglePersistentNotification(bool enable) async {
    state = state.copyWith(isEnabled: enable);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKey, enable);

      if (enable) {
        await _notificationService.showPersistentNotification(
          id: notificationId,
          title: notificationTitle,
          body: notificationBody,
          payload: notificationPayload,
        );
      } else {
        await _notificationService.cancelPersistentNotification(notificationId);
      }
    } catch (_) {}

    if (!mounted) return;
    state = state.copyWith(isEnabled: enable);
  }

  /// 在通知栏行内直接发起搜索并即时更新释义卡片
  Future<void> handleInlineSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;

    final seq = ++_searchSeq;

    state = state.copyWith(
      isSearching: true,
      lastSearchedWord: query,
      clearLastSearchError: true,
    );

    // 1. 立即更新通知栏为加载状态
    await _notificationService.updateSearchResultNotification(
      id: notificationId,
      word: query,
      isLoading: true,
    );

    final service = vocabularyService;
    if (service == null) {
      if (seq != _searchSeq || !mounted) return;
      state = state.copyWith(isSearching: false);
      await _notificationService.updateSearchResultNotification(
        id: notificationId,
        word: query,
        definitionSc: '已收到查询「$query」',
        isLoading: false,
      );
      return;
    }

    try {
      // 2. 执行查词主流程（本地缓存去重 -> Weblio 抓取 -> LLM 兜底翻译 -> SQLite 入库）
      final entry = await service.lookupWord(query);
      if (seq != _searchSeq || !mounted) return;

      final summary = entry.vocabDefSc.isNotEmpty
          ? entry.vocabDefSc
          : entry.vocabDefJa;

      state = state.copyWith(
        isSearching: false,
        lastSearchResult: summary,
      );

      // 3. 将包含读音、词性与双语释义的完整结果更新至通知栏（BigTextStyle）
      await _notificationService.updateSearchResultNotification(
        id: notificationId,
        word: entry.vocabKanji,
        reading: entry.vocabFurigana,
        definitionJa: entry.vocabDefJa,
        definitionSc: entry.vocabDefSc,
        partOfSpeech: entry.vocabPoS,
        isLoading: false,
      );

      _invokeWordSaved(entry);
    } catch (e) {
      if (seq != _searchSeq || !mounted) return;
      final errorMsg = e is WeblioException
          ? e.message
          : '未找到「$query」的相关释义或网络异常';

      state = state.copyWith(
        isSearching: false,
        lastSearchError: errorMsg,
      );

      await _notificationService.updateSearchResultNotification(
        id: notificationId,
        word: query,
        error: errorMsg,
        isLoading: false,
      );
    }
  }
}

/// Provider for PersistentNotificationNotifier
final persistentNotificationProvider = StateNotifierProvider<
    PersistentNotificationNotifier, PersistentNotificationState>((ref) {
  final service = ref.watch(persistentNotificationServiceProvider);
  final vocabService = ref.watch(vocabularyServiceProvider);
  return PersistentNotificationNotifier(
    service,
    vocabularyService: vocabService,
    onWordSaved: (entry) {
      try {
        final notifier = ref.read(vocabularyProvider.notifier);
        if (entry != null) {
          notifier.selectEntry(entry);
        }
        notifier.loadEntries();
      } catch (_) {}
    },
  );
});

