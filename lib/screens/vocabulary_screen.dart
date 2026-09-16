import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/vocabulary_entry.dart';
import '../models/word_candidate.dart';
import '../providers/vocabulary_provider.dart';
import '../providers/persistent_notification_provider.dart';
import '../providers/vocabulary_config_provider.dart';
import '../providers/anki_config_provider.dart';
import '../widgets/vocabulary_model_selector_dialog.dart';
import '../services/native/native_services.dart';

/// 单词本界面
/// 提供日语生词查询、Weblio 抓取展示、LLM 中文释义以及本地单词库管理
class VocabularyScreen extends ConsumerStatefulWidget {
  final bool autoFocusLookup;

  const VocabularyScreen({super.key, this.autoFocusLookup = false});

  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  final TextEditingController _lookupController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _lookupFocusNode = FocusNode();
  StreamSubscription<String>? _notificationSub;
  bool _isSearchingHistory = false;

  @override
  void initState() {
    super.initState();
    // 预热持久化 Anki 配置加载
    ref.read(ankiConfigProvider.notifier).ensureLoaded();

    final notificationService =
        ref.read(persistentNotificationServiceProvider);
    _notificationSub =
        notificationService.onNotificationTapped.listen((payload) {
      if (payload == '/vocabulary' && mounted) {
        _lookupFocusNode.requestFocus();
      }
    });

    if (widget.autoFocusLookup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _lookupFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    _lookupController.dispose();
    _searchController.dispose();
    _lookupFocusNode.dispose();
    super.dispose();
  }

  void _handleLookup({bool forceRefresh = false}) {
    final text = _lookupController.text.trim();
    if (text.isEmpty) return;

    _lookupFocusNode.unfocus();
    ref.read(vocabularyProvider.notifier).lookupWord(
          text,
          forceRefresh: forceRefresh,
          checkConfirmation: !forceRefresh,
        );
  }

  Future<void> _launchWeblioUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleExportToAnki() async {
    // 强制等待持久化配置就绪，避免重进应用后时序竞争回退默认牌组/模板
    await ref.read(ankiConfigProvider.notifier).ensureLoaded();
    if (!mounted) return;

    final vocabState = ref.read(vocabularyProvider);
    final count = vocabState.unexportedCount;

    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无未导出的新词'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final ankiConfig = ref.read(ankiConfigProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出新词到 AnkiDroid'),
        content: Text(
          '即将导出 $count 个新词到 AnkiDroid 牌组「${ankiConfig.deckName}」，是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认导出'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await ref.read(vocabularyProvider.notifier).exportToAnki(
          deckName: ankiConfig.deckName,
          modelName: ankiConfig.modelName,
        );

    if (!mounted) return;

    if (result.modelUpgradedTo != null) {
      await ref
          .read(ankiConfigProvider.notifier)
          .updateModelName(result.modelUpgradedTo!);
    }

    if (!mounted) return;

    final upgradeMsg = result.modelUpgradedFrom != null
        ? '\n已自动从旧模板「${result.modelUpgradedFrom}」升级为「${result.modelUpgradedTo}」，旧卡片不受影响'
        : '';

    if (result.errors.isNotEmpty &&
        result.successCount == 0 &&
        result.skipCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: ${result.errors.join("; ")}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    } else if (result.successCount == 0 && result.skipCount > 0 && result.failedEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '全部 ${result.skipCount} 个新词在 AnkiDroid 中已存在，已自动跳过$upgradeMsg',
          ),
          duration: Duration(seconds: result.modelUpgradedFrom != null ? 5 : 3),
        ),
      );
    } else {
      final skipMsg =
          result.skipCount > 0 ? '（${result.skipCount} 个已跳过）' : '';
      final failMsg = result.failedEntries.isNotEmpty
          ? '，${result.failedEntries.length} 个失败'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已成功导出 ${result.successCount} 个新词到 Anki$skipMsg$failMsg$upgradeMsg',
          ),
          duration: Duration(seconds: result.modelUpgradedFrom != null ? 5 : 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vocabularyProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: const Text('📚 单词本'),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final vocabCfg = ref.watch(vocabularyConfigProvider);
              final modelName = vocabCfg.model?.modelName ??
                  vocabCfg.model?.id ??
                  '专属模型';
              return IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '生词本专属翻译模型: $modelName',
                icon: const Icon(Icons.psychology_outlined),
                onPressed: () => showVocabularyModelSelectorDialog(context),
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) {
              final notifState = ref.watch(persistentNotificationProvider);
              final isEnabled = notifState.isEnabled;
              return IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: isEnabled ? '关闭通知栏常驻查词' : '开启通知栏常驻查词快捷入口',
                icon: Icon(
                  isEnabled
                      ? Icons.notifications_active
                      : Icons.notifications_none,
                  color: isEnabled ? colorScheme.primary : null,
                ),
                onPressed: () async {
                  await ref
                      .read(persistentNotificationProvider.notifier)
                      .togglePersistentNotification(!isEnabled);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          !isEnabled ? '已开启通知栏快捷常驻入口' : '已关闭通知栏常驻入口',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) {
              final vocabState = ref.watch(vocabularyProvider);
              final isExporting = vocabState.isExporting;
              final unexportedCount = vocabState.unexportedCount;

              if (isExporting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              return Badge(
                isLabelVisible: unexportedCount > 0,
                label: Text(
                  '$unexportedCount',
                  style: const TextStyle(fontSize: 10),
                ),
                offset: const Offset(-4, 4),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: unexportedCount > 0
                      ? '导出 $unexportedCount 个新词到 Anki'
                      : '导出新词到 Anki（当前无新词）',
                  icon: const Icon(Icons.send_to_mobile),
                  onPressed: _handleExportToAnki,
                ),
              );
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: _isSearchingHistory ? '关闭搜索' : '搜索本地单词',
            icon: Icon(_isSearchingHistory ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _isSearchingHistory = !_isSearchingHistory;
                if (!_isSearchingHistory) {
                  _searchController.clear();
                  ref.read(vocabularyProvider.notifier).setSearchQuery('');
                }
              });
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '帮助说明',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部输入查词区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lookupController,
                    focusNode: _lookupFocusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _handleLookup(),
                    decoration: InputDecoration(
                      hintText: '输入日语单词（如：食べる、美しい）',
                      prefixIcon: const Icon(Icons.translate),
                      suffixIcon: _lookupController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                _lookupController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: state.isLoading ? null : () => _handleLookup(),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('查询'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 生词本专属翻译模型指示与快捷切换
          Consumer(
            builder: (context, ref, _) {
              final vocabCfg = ref.watch(vocabularyConfigProvider);
              final providerName = vocabCfg.config?.name ?? '默认供应商';
              final modelName = vocabCfg.model?.modelName ??
                  vocabCfg.model?.id ??
                  '自动选择';
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '翻译模型: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                        fontSize: 12,
                      ),
                    ),
                    Flexible(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => showVocabularyModelSelectorDialog(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  '$providerName · $modelName',
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.arrow_drop_down,
                                  size: 16, color: colorScheme.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // 历史搜索过滤栏（展开时展示）
          if (_isSearchingHistory)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '在已存单词中过滤（汉字、假名、释义）',
                  prefixIcon: const Icon(Icons.filter_list, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(vocabularyProvider.notifier).setSearchQuery('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withAlpha(128),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (val) {
                  ref.read(vocabularyProvider.notifier).setSearchQuery(val);
                },
              ),
            ),

          // 候选词消歧与确认卡片 (以 Flexible 约束最大高度，内部列表自适应滚动杜绝溢出)
          if (state.candidates != null && state.candidates!.isNotEmpty)
            Flexible(
              flex: 4,
              fit: FlexFit.loose,
              child: _buildCandidateConfirmationCard(context, state),
            ),

          // 加载进度指示器
          if (state.isLoading) ...[
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '正在从 Weblio 抓取并调用大模型翻译...',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 错误卡片
          if (state.error != null && !state.isLoading)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: colorScheme.onErrorContainer,
                    onPressed: () {
                      ref.read(vocabularyProvider.notifier).clearError();
                    },
                  ),
                ],
              ),
            ),

          // 当前查词结果卡片 (以 Flexible 约束最大高度，配合卡片内部滚动杜绝任何屏幕尺寸下的溢出)
          if (state.currentResult != null &&
              !state.isLoading &&
              (state.candidates == null || state.candidates!.isEmpty))
            Flexible(
              flex: 4,
              fit: FlexFit.loose,
              child: _buildCurrentResultCard(context, state.currentResult!),
            ),

          // 单词列表标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Text(
                  '单词列表 (${state.entries.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (state.searchQuery.isNotEmpty)
                  Text(
                    '过滤结果',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),

          // 单词列表主体
          Expanded(
            flex: 3,
            child: state.entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 48,
                          color: colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.searchQuery.isNotEmpty
                              ? '未找到匹配的单词'
                              : '单词本暂无记录，输入单词即可查询并保存',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: state.entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = state.entries[index];
                      final isSelected = state.currentResult?.id == entry.id;

                      return Dismissible(
                        key: ValueKey(entry.id ?? entry.vocabKanji),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: colorScheme.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete, color: Colors.white),
                              SizedBox(width: 4),
                              Text('删除', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        onDismissed: (_) {
                          if (entry.id != null) {
                            ref
                                .read(vocabularyProvider.notifier)
                                .deleteEntry(entry.id!);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已删除「${entry.vocabKanji}」'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          selected: isSelected,
                          selectedTileColor: colorScheme.primaryContainer.withAlpha(60),
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                            child: Text(
                              entry.vocabKanji.characters.isNotEmpty
                                  ? entry.vocabKanji.characters.first
                                  : '?',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              Text(
                                entry.vocabKanji,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (entry.vocabFurigana.isNotEmpty)
                                Text(
                                  entry.vocabFurigana,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.secondary,
                                  ),
                                ),
                              if (entry.vocabPitch.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry.vocabPitch,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              if (entry.vocabPoS.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry.vocabPoS,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            entry.vocabDefSc.isNotEmpty
                                ? entry.vocabDefSc
                                : entry.vocabDefJa,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (entry.exportedToAnki)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              Text(
                                _formatDate(entry.createdAt),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            ref
                                .read(vocabularyProvider.notifier)
                                .selectEntry(entry);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建当前展示的生词卡片
  Widget _buildCurrentResultCard(BuildContext context, VocabularyEntry entry) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoading =
        ref.watch(vocabularyProvider.select((s) => s.isLoading));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(128),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 卡片头部：单词、假名、词性、来源
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      SelectableText(
                        entry.vocabKanji,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      if (entry.vocabFurigana.isNotEmpty)
                        SelectableText(
                          entry.vocabFurigana,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.secondary,
                          ),
                        ),
                       if (entry.vocabPitch.isNotEmpty)
                        Chip(
                          label: Text(
                            entry.vocabPitch,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: colorScheme.primaryContainer,
                        ),
                      if (entry.vocabPoS.isNotEmpty)
                        Chip(
                          label: Text(
                            entry.vocabPoS,
                            style: theme.textTheme.labelSmall,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: colorScheme.secondaryContainer,
                        ),
                    ],
                  ),
                ),
                if (entry.sourceUrl.isNotEmpty)
                  IconButton(
                    tooltip: '在 Weblio 打开网页版',
                    icon: const Icon(Icons.open_in_new, size: 20),
                    onPressed: () => _launchWeblioUrl(entry.sourceUrl),
                  ),
                IconButton(
                  tooltip: '重新抓取与翻译',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    _lookupController.text = entry.vocabKanji;
                    ref.read(vocabularyProvider.notifier).lookupWord(
                          entry.vocabKanji,
                          forceRefresh: true,
                        );
                  },
                ),
                IconButton(
                  tooltip: '关闭当前卡片',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    ref.read(vocabularyProvider.notifier).clearCurrentResult();
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 卡片内容：释义与例句 (以 Flexible 和 SingleChildScrollView 包裹，杜绝长文本布局溢出)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 中文释义
                  if (entry.vocabDefSc.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.translate, size: 16, color: colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              '中文释义',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 16),
                          tooltip: '使用专属模型重新生成释义',
                          visualDensity: VisualDensity.compact,
                          onPressed: isLoading
                              ? null
                              : () => ref
                                  .read(vocabularyProvider.notifier)
                                  .retranslateEntry(entry),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      entry.vocabDefSc,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ] else ...[
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: colorScheme.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '未配置 API 模型或暂无中文释义',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.translate, size: 14),
                          label: const Text('生成释义', style: TextStyle(fontSize: 12)),
                          onPressed: isLoading
                              ? null
                              : () => ref
                                  .read(vocabularyProvider.notifier)
                                  .retranslateEntry(entry),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 日语原文释义
                  if (entry.vocabDefJa.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.menu_book, size: 16, color: colorScheme.secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '日语释义 (${entry.sourceDict.isNotEmpty ? entry.sourceDict : "Weblio"})',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      entry.vocabDefJa,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],

                  // 例句模块
                  if (entry.sentKanji1 != null || entry.sentKanji2 != null) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Text(
                      '例句',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (entry.sentKanji1 != null)
                      _buildExampleRow(
                        context,
                        kanji: entry.sentKanji1!,
                        furigana: entry.sentFurigana1,
                        translation: entry.sentDefSc1,
                      ),
                    if (entry.sentKanji2 != null) ...[
                      const SizedBox(height: 6),
                      _buildExampleRow(
                        context,
                        kanji: entry.sentKanji2!,
                        furigana: entry.sentFurigana2,
                        translation: entry.sentDefSc2,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleRow(
    BuildContext context, {
    required String kanji,
    String? furigana,
    String? translation,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            furigana ?? kanji,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          if (translation != null && translation.isNotEmpty) ...[
            const SizedBox(height: 2),
            SelectableText(
              translation,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$m-$d $h:$min';
  }

  Widget _buildCandidateConfirmationCard(
      BuildContext context, VocabularyState state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPureKana = state.candidateReason == CandidateReason.pureKana;
    final candidates = state.candidates ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPureKana
              ? colorScheme.primary.withAlpha(128)
              : colorScheme.secondary.withAlpha(128),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isPureKana ? Icons.alt_route : Icons.auto_fix_high,
                color: isPureKana ? colorScheme.primary : colorScheme.secondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isPureKana ? '假名同音多义词确认' : '词典未收录 · AI 智能推测',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isPureKana
                        ? colorScheme.primary
                        : colorScheme.secondary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: '取消选择',
                onPressed: () {
                  ref.read(vocabularyProvider.notifier).dismissCandidates();
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            isPureKana
                ? '您输入的是纯假名「${state.pendingCandidateWord}」，可能对应以下汉字与含义，请选择您的目标词：'
                : '未在词典中检索到「${state.pendingCandidateWord}」，AI 为您智能推测了以下可能的目标词：',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final candidate = candidates[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    _lookupController.text = candidate.searchWord;
                    ref
                        .read(vocabularyProvider.notifier)
                        .selectCandidate(candidate);
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 70, maxWidth: 130),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                candidate.kanji,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                candidate.reading,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: [
                                  if (candidate.partOfSpeech.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.secondaryContainer,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        candidate.partOfSpeech,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ),
                                  if (candidate.source ==
                                      CandidateSource.aiInference)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'AI推测',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              colorScheme.onTertiaryContainer,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                candidate.definition,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: colorScheme.outline,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: TextButton(
                  onPressed: () {
                    ref.read(vocabularyProvider.notifier).confirmOriginalWord();
                  },
                  child: Text(
                    '仍按原输入「${state.pendingCandidateWord}」查询',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于单词本'),
        content: const SingleChildScrollView(
          child: Text(
            '1. 数据源：释义与例句抓取自 Weblio 国语辞典（优先解析小学馆《デジタル大辞泉》）。\n\n'
            '2. 中文翻译：自动调用应用中当前启用的 AI 模型进行精炼翻译。\n\n'
            '3. 缓存去重：已经查过的单词将直接从本地 SQLite 数据库读取。\n\n'
            '4. 字段兼容：底层数据结构与 Anki 模板对齐，为后续导出牌组做好准备。\n\n'
            '5. 操作技巧：左滑单词列表条目可快速删除。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }
}
