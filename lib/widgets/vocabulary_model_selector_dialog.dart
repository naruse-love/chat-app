import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/api_config.dart';
import '../models/model_info.dart';
import '../providers/api_config_provider.dart';
import '../providers/vocabulary_config_provider.dart';

/// 弹出单词本独立模型选择对话框
Future<void> showVocabularyModelSelectorDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const VocabularyModelSelectorDialog(),
  );
}

/// 单词本独立模型选择弹窗
/// 允许用户为单词本选择专属的供应商和模型，与聊天会话完全隔离互不影响
class VocabularyModelSelectorDialog extends ConsumerStatefulWidget {
  const VocabularyModelSelectorDialog({super.key});

  @override
  ConsumerState<VocabularyModelSelectorDialog> createState() =>
      _VocabularyModelSelectorDialogState();
}

class _VocabularyModelSelectorDialogState
    extends ConsumerState<VocabularyModelSelectorDialog> {
  final TextEditingController _customModelController = TextEditingController();
  bool _isAddingCustom = false;

  @override
  void dispose() {
    _customModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final apiState = ref.watch(apiConfigProvider);
    final vocabState = ref.watch(vocabularyConfigProvider);
    final vocabNotifier = ref.read(vocabularyConfigProvider.notifier);

    // 去重供应商列表并校验当前选中项
    final Map<String, ApiConfig> uniqueConfigs = {};
    for (final c in apiState.configs) {
      uniqueConfigs.putIfAbsent(c.id, () => c);
    }
    final configs = uniqueConfigs.values.toList();
    final currentConfig = vocabState.config;
    final currentModel = vocabState.model;

    final selectedConfigId = configs.any((c) => c.id == currentConfig?.id)
        ? currentConfig?.id
        : (configs.isNotEmpty ? configs.first.id : null);

    // 去重模型列表并确保当前选中模型在选项中
    final Map<String, ModelInfo> uniqueModels = {};
    if (currentModel != null) {
      uniqueModels[currentModel.id] = currentModel;
    }
    for (final m in vocabState.availableModels) {
      uniqueModels.putIfAbsent(m.id, () => m);
    }
    final availableModels = uniqueModels.values.toList();

    final selectedModelId =
        availableModels.any((m) => m.id == currentModel?.id)
            ? currentModel?.id
            : (availableModels.isNotEmpty ? availableModels.first.id : null);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.psychology_outlined, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '生词本专属翻译模型',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '此设置仅作用于日语生词抓取、消歧与中文翻译，与聊天界面模型完全独立，供应商共享。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 供应商选择
              Text(
                '供应商 (API 配置)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              if (configs.isEmpty)
                const Text('暂无可用 API 配置，请先在设置中添加')
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('vocab_provider_dropdown_$selectedConfigId'),
                  isExpanded: true,
                  initialValue: selectedConfigId,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: configs.map((cfg) {
                    final isDefault = cfg.isDefault;
                    return DropdownMenuItem<String>(
                      value: cfg.id,
                      child: Text(
                        '${cfg.name}${isDefault ? ' (系统默认)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (selectedId) {
                    if (selectedId != null && selectedId != currentConfig?.id) {
                      final chosen =
                          configs.firstWhere((c) => c.id == selectedId);
                      vocabNotifier.setConfig(chosen);
                    }
                  },
                ),
              const SizedBox(height: 16),

              // 模型选择
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '翻译模型',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  if (vocabState.isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      tooltip: '从服务商刷新模型列表',
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        await vocabNotifier.fetchModels(forceRefresh: true);
                        if (context.mounted) {
                          final err = ref.read(vocabularyConfigProvider).error;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err ?? '已刷新模型列表'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),

              if (availableModels.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey(
                      'vocab_model_dropdown_${selectedConfigId}_$selectedModelId'),
                  isExpanded: true,
                  initialValue: selectedModelId,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: availableModels.map((m) {
                    return DropdownMenuItem<String>(
                      value: m.id,
                      child: Text(
                        m.modelName.isNotEmpty ? m.modelName : m.id,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (modelId) {
                    if (modelId != null) {
                      final match = availableModels
                          .firstWhere((m) => m.id == modelId);
                      vocabNotifier.setModel(match);
                    }
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '当前供应商暂无缓存模型列表，可手动添加或点击上方刷新',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // 自定义模型输入
              if (!_isAddingCustom)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isAddingCustom = true;
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('使用自定义模型 ID', style: TextStyle(fontSize: 12)),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customModelController,
                        decoration: const InputDecoration(
                          hintText: '如 gpt-4o-mini、qwen-plus',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () async {
                        final text = _customModelController.text.trim();
                        if (text.isNotEmpty) {
                          await vocabNotifier.addCustomModel(text);
                          _customModelController.clear();
                          setState(() {
                            _isAddingCustom = false;
                          });
                        }
                      },
                      child: const Text('应用'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await vocabNotifier.resetToDefault();
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已恢复生词本跟随默认供应商与模型'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          child: const Text('恢复默认'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
