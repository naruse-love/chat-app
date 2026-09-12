import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_config.dart';
import '../models/model_info.dart';
import '../services/chat_service.dart';
import '../data/api_config_dao.dart';
import 'api_config_provider.dart';
import 'model_provider.dart';

/// 生词本独立模型配置状态
class VocabularyConfigState {
  final ApiConfig? config;
  final ModelInfo? model;
  final List<ModelInfo> availableModels;
  final bool isLoading;
  final String? error;
  final bool isCustomSelected;

  const VocabularyConfigState({
    this.config,
    this.model,
    this.availableModels = const [],
    this.isLoading = false,
    this.error,
    this.isCustomSelected = false,
  });

  VocabularyConfigState copyWith({
    ApiConfig? config,
    bool clearConfig = false,
    ModelInfo? model,
    bool clearModel = false,
    List<ModelInfo>? availableModels,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool? isCustomSelected,
  }) {
    return VocabularyConfigState(
      config: clearConfig ? null : (config ?? this.config),
      model: clearModel ? null : (model ?? this.model),
      availableModels: availableModels ?? this.availableModels,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isCustomSelected: isCustomSelected ?? this.isCustomSelected,
    );
  }
}

/// 生词本专属模型与配置管理器
/// 允许用户为生词本单独挑选供应商（ApiConfig）与具体模型，与聊天会话完全隔离互不影响
class VocabularyConfigNotifier extends StateNotifier<VocabularyConfigState> {
  static const String keyVocabApiConfigId = 'vocab_api_config_id';
  static const String keyVocabModelId = 'vocab_model_id';

  final ApiConfigDao _apiConfigDao;
  final ChatService _chatService;
  final Ref? _ref;
  late final Future<void> initialization;

  VocabularyConfigNotifier(
    this._apiConfigDao,
    this._chatService, [
    this._ref,
  ]) : super(const VocabularyConfigState()) {
    initialization = _loadConfig();
  }

  static String _cacheKey(String configId) => 'cached_models_$configId';

  List<ModelInfo> _getFallbackModelsForConfig(ApiConfig config) {
    final configId = config.id.toLowerCase();
    final baseUrl = config.baseUrl.toLowerCase();
    final name = config.name.toLowerCase();

    if (configId == 'opencode_free' || baseUrl.contains('opencode.ai')) {
      return ModelInfo.defaultOpenCodeFallbackModels
          .where((m) => m.id.toLowerCase().contains('free'))
          .toList();
    }

    if (baseUrl.contains('deepseek') || name.contains('deepseek')) {
      return [
        ModelInfo(
          id: 'deepseek-chat',
          provider: 'deepseek',
          modelName: 'DeepSeek Chat (V3)',
          supportsVision: false,
          supportsTools: true,
        ),
        ModelInfo(
          id: 'deepseek-reasoner',
          provider: 'deepseek',
          modelName: 'DeepSeek Reasoner (R1)',
          supportsVision: false,
          supportsTools: true,
        ),
      ];
    }

    if (baseUrl.contains('openai') || name.contains('openai')) {
      return [
        ModelInfo(
          id: 'gpt-4o-mini',
          provider: 'openai',
          modelName: 'GPT-4o mini',
          supportsVision: true,
          supportsTools: true,
        ),
        ModelInfo(
          id: 'gpt-4o',
          provider: 'openai',
          modelName: 'GPT-4o',
          supportsVision: true,
          supportsTools: true,
        ),
      ];
    }

    if (baseUrl.contains('anthropic') || name.contains('claude')) {
      return [
        ModelInfo(
          id: 'claude-3-5-haiku-20241022',
          provider: 'anthropic',
          modelName: 'Claude 3.5 Haiku',
          supportsVision: true,
          supportsTools: true,
        ),
        ModelInfo(
          id: 'claude-3-5-sonnet-20241022',
          provider: 'anthropic',
          modelName: 'Claude 3.5 Sonnet',
          supportsVision: true,
          supportsTools: true,
        ),
      ];
    }

    if (baseUrl.contains('siliconflow') || name.contains('silicon')) {
      return [
        ModelInfo(
          id: 'deepseek-ai/DeepSeek-V3',
          provider: 'siliconflow',
          modelName: 'DeepSeek V3',
          supportsVision: false,
          supportsTools: true,
        ),
        ModelInfo(
          id: 'Qwen/Qwen2.5-7B-Instruct',
          provider: 'siliconflow',
          modelName: 'Qwen 2.5 7B Instruct',
          supportsVision: false,
          supportsTools: true,
        ),
      ];
    }

    // 通用 OpenAI 兼容接口兜底候选
    return [
      ModelInfo(
        id: 'gpt-4o-mini',
        provider: config.name,
        modelName: 'gpt-4o-mini',
        supportsVision: true,
        supportsTools: true,
      ),
      ModelInfo(
        id: 'deepseek-chat',
        provider: config.name,
        modelName: 'deepseek-chat',
        supportsVision: false,
        supportsTools: true,
      ),
      ModelInfo(
        id: 'gpt-4o',
        provider: config.name,
        modelName: 'gpt-4o',
        supportsVision: true,
        supportsTools: true,
      ),
    ];
  }

  ModelInfo? _pickDefaultModel(List<ModelInfo> list, ApiConfig? config) {
    if (list.isEmpty) return null;
    final configId = config?.id.toLowerCase() ?? '';
    final baseUrl = config?.baseUrl.toLowerCase() ?? '';

    if (configId == 'opencode_free' || baseUrl.contains('opencode.ai')) {
      final idx = list.indexWhere((m) => m.id == 'deepseek-v4-flash-free');
      if (idx != -1) return list[idx];
      final freeIdx =
          list.indexWhere((m) => m.id.toLowerCase().contains('free'));
      if (freeIdx != -1) return list[freeIdx];
    }

    // 优先轻量/高性价比翻译模型（flash / mini / turbo / chat / haiku）
    final preferredIds = [
      'deepseek-chat',
      'gpt-4o-mini',
      'claude-3-5-haiku-20241022',
      'deepseek-ai/DeepSeek-V3',
      'qwen-plus',
      'qwen-turbo',
    ];
    for (final pref in preferredIds) {
      final idx =
          list.indexWhere((m) => m.id.toLowerCase() == pref.toLowerCase());
      if (idx != -1) return list[idx];
    }

    // 模糊匹配常见经济型模型关键字
    final keywordIdx = list.indexWhere((m) {
      final id = m.id.toLowerCase();
      return id.contains('mini') ||
          id.contains('flash') ||
          id.contains('turbo') ||
          id.contains('haiku') ||
          id.contains('chat');
    });
    if (keywordIdx != -1) return list[keywordIdx];

    return list.first;
  }

  Future<void> _loadConfig() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedConfigId = prefs.getString(keyVocabApiConfigId);
      final savedModelId = prefs.getString(keyVocabModelId);

      var configs = await _apiConfigDao.getAll();
      if (configs.isEmpty) {
        final defaultConfig = ApiConfig(
          id: 'opencode_free',
          name: 'OpenCode Free',
          baseUrl: 'https://opencode.ai/zen/v1',
          apiKeyRef: 'opencode_free_api_key_ref',
          isDefault: true,
          createdAt: DateTime.now(),
        );
        await _apiConfigDao.insert(defaultConfig, '');
        configs = await _apiConfigDao.getAll();
      }

      ApiConfig? chosenConfig;
      bool isCustom = false;
      if (savedConfigId != null && savedConfigId.isNotEmpty) {
        chosenConfig = configs.where((c) => c.id == savedConfigId).firstOrNull;
        if (chosenConfig != null) {
          isCustom = true;
        }
      }

      // 降级策略：优先聊天当前配置，再默认配置，再首个配置
      if (chosenConfig == null && _ref != null) {
        try {
          chosenConfig = _ref.read(apiConfigProvider).activeConfig;
        } catch (_) {}
      }
      chosenConfig ??= await _apiConfigDao.getDefault() ??
          (configs.isNotEmpty ? configs.first : null);

      if (chosenConfig == null) {
        if (!mounted) return;
        state = state.copyWith(isLoading: false);
        return;
      }

      // 读取该配置下的缓存模型列表
      final configId = chosenConfig.id;
      final cacheKey = _cacheKey(configId);
      List<ModelInfo> models = [];
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(cachedJson);
          models = decoded
              .whereType<Map<String, dynamic>>()
              .map((m) => ModelInfo.fromJson(m))
              .toList();
        } catch (_) {}
      }

      if (models.isEmpty) {
        models = _getFallbackModelsForConfig(chosenConfig);
      }

      // 确定选中的模型
      ModelInfo? chosenModel;
      if (savedModelId != null && savedModelId.isNotEmpty) {
        chosenModel = models.where((m) => m.id == savedModelId).firstOrNull;
        if (chosenModel == null) {
          chosenModel = ModelInfo(
            id: savedModelId,
            provider: chosenConfig.name,
            modelName: savedModelId,
            supportsVision: false,
            supportsTools: true,
          );
          models = [chosenModel, ...models];
        }
      }

      // 检查该配置上次在聊天中使用的模型
      if (chosenModel == null) {
        final lastChatModelId =
            prefs.getString('last_selected_model_${chosenConfig.id}');
        if (lastChatModelId != null && lastChatModelId.isNotEmpty) {
          chosenModel =
              models.where((m) => m.id == lastChatModelId).firstOrNull;
          if (chosenModel == null) {
            chosenModel = ModelInfo(
              id: lastChatModelId,
              provider: chosenConfig.name,
              modelName: lastChatModelId,
              supportsVision: false,
              supportsTools: true,
            );
            models = [chosenModel, ...models];
          }
        }
      }

      if (chosenModel == null && _ref != null) {
        try {
          final chatModel = _ref.read(modelProvider).selectedModel;
          if (chatModel != null && (!isCustom || savedModelId == null)) {
            final match =
                models.where((m) => m.id == chatModel.id).firstOrNull;
            if (match != null) {
              chosenModel = match;
            } else {
              chosenModel = chatModel;
              models = [chatModel, ...models];
            }
          }
        } catch (_) {}
      }
      chosenModel ??= _pickDefaultModel(models, chosenConfig);

      if (!mounted) return;
      state = VocabularyConfigState(
        config: chosenConfig,
        model: chosenModel,
        availableModels: models,
        isLoading: false,
        isCustomSelected: isCustom,
      );

      // 后台静默刷新最新模型列表
      _refreshModelsInBackground(chosenConfig, chosenModel?.id);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _refreshModelsInBackground(
    ApiConfig config,
    String? targetModelId,
  ) async {
    try {
      final apiKey = await _apiConfigDao.getApiKey(config.apiKeyRef) ?? '';
      var fetched =
          await _chatService.getModels(baseUrl: config.baseUrl, apiKey: apiKey);
      if (!mounted) return;
      if (config.id == 'opencode_free') {
        fetched =
            fetched.where((m) => m.id.toLowerCase().contains('free')).toList();
      }
      if (fetched.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final encoded = jsonEncode(fetched.map((m) => m.toJson()).toList());
          await prefs.setString(_cacheKey(config.id), encoded);
        } catch (_) {}

        if (state.config?.id != config.id) return;

        ModelInfo? current = state.model;
        if (targetModelId != null) {
          final found =
              fetched.where((m) => m.id == targetModelId).firstOrNull;
          if (found != null) {
            current = found;
          }
        }
        final cur = current;
        if (cur != null && !fetched.any((m) => m.id == cur.id)) {
          fetched = [cur, ...fetched];
        } else {
          current ??= _pickDefaultModel(fetched, config);
        }

        if (!mounted) return;
        state = state.copyWith(
          availableModels: fetched,
          model: current,
        );
      }
    } catch (_) {
      // 后台刷新异常安全忽略
    }
  }

  /// 为生词本切换供应商
  Future<void> setConfig(ApiConfig config) async {
    // 立即确定新供应商可用的候选模型列表与默认模型，避免短暂的模型与供应商不匹配状态
    final cacheKey = _cacheKey(config.id);
    List<ModelInfo> models = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(cacheKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        models = decoded
            .whereType<Map<String, dynamic>>()
            .map((m) => ModelInfo.fromJson(m))
            .toList();
      }
    } catch (_) {}

    if (models.isEmpty) {
      models = _getFallbackModelsForConfig(config);
    }

    ModelInfo? chosenModel;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedModelId = prefs.getString(keyVocabModelId);
      if (savedModelId != null && models.any((m) => m.id == savedModelId)) {
        chosenModel = models.firstWhere((m) => m.id == savedModelId);
      } else {
        final lastSelectedId =
            prefs.getString('last_selected_model_${config.id}');
        if (lastSelectedId != null && lastSelectedId.isNotEmpty) {
          chosenModel =
              models.where((m) => m.id == lastSelectedId).firstOrNull;
          if (chosenModel == null) {
            chosenModel = ModelInfo(
              id: lastSelectedId,
              provider: config.name,
              modelName: lastSelectedId,
              supportsVision: false,
              supportsTools: true,
            );
            models = [chosenModel, ...models];
          }
        }
      }
    } catch (_) {}

    chosenModel ??= _pickDefaultModel(models, config);

    state = state.copyWith(
      config: config,
      model: chosenModel,
      availableModels: models,
      isLoading: true,
      isCustomSelected: true,
      clearError: true,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyVocabApiConfigId, config.id);
      if (chosenModel != null) {
        await prefs.setString(keyVocabModelId, chosenModel.id);
      }

      if (!mounted) return;
      state = state.copyWith(isLoading: false);

      _refreshModelsInBackground(config, chosenModel?.id);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 为生词本选择模型
  Future<void> setModel(ModelInfo model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyVocabModelId, model.id);
      if (state.config != null) {
        await prefs.setString(keyVocabApiConfigId, state.config!.id);
      }
    } catch (_) {}

    final currentModels = List<ModelInfo>.from(state.availableModels);
    final existingIdx = currentModels.indexWhere((m) => m.id == model.id);
    if (existingIdx == -1) {
      currentModels.insert(0, model);
    } else {
      currentModels[existingIdx] = model;
    }

    state = state.copyWith(
      model: model,
      availableModels: currentModels,
      isCustomSelected: true,
    );
  }

  /// 添加并选中自定义模型 ID
  Future<void> addCustomModel(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;

    final parts = trimmed.split('/');
    final providerName =
        parts.length > 1 ? parts[0] : (state.config?.name ?? 'custom');
    final modelName = parts.length > 1 ? parts.sublist(1).join('/') : trimmed;

    final customModel = ModelInfo(
      id: trimmed,
      provider: providerName,
      modelName: modelName,
      supportsVision: false,
      supportsTools: true,
    );

    await setModel(customModel);
  }

  /// 强制刷新当前供应商下的模型列表
  Future<void> fetchModels({bool forceRefresh = false}) async {
    final currentConfig = state.config;
    if (currentConfig == null) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final apiKey =
          await _apiConfigDao.getApiKey(currentConfig.apiKeyRef) ?? '';
      var models = await _chatService.getModels(
        baseUrl: currentConfig.baseUrl,
        apiKey: apiKey,
      );
      if (!mounted) return;
      if (currentConfig.id == 'opencode_free') {
        models =
            models.where((m) => m.id.toLowerCase().contains('free')).toList();
      }

      if (models.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final encoded = jsonEncode(models.map((m) => m.toJson()).toList());
        await prefs.setString(_cacheKey(currentConfig.id), encoded);
      } else {
        models = _getFallbackModelsForConfig(currentConfig);
      }

      ModelInfo? selected = state.model;
      final sel = selected;
      if (sel != null && !models.any((m) => m.id == sel.id)) {
        models = [sel, ...models];
      }
      selected ??= _pickDefaultModel(models, currentConfig);

      if (!mounted) return;
      state = state.copyWith(
        availableModels: models,
        model: selected,
        isLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: '获取模型列表失败: $e',
      );
    }
  }

  /// 恢复跟随系统/默认供应商与模型
  Future<void> resetToDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyVocabApiConfigId);
      await prefs.remove(keyVocabModelId);
    } catch (_) {}
    await _loadConfig();
  }
}

/// Provider for VocabularyConfigNotifier
final vocabularyConfigProvider =
    StateNotifierProvider<VocabularyConfigNotifier, VocabularyConfigState>(
        (ref) {
  final apiDao = ref.watch(apiConfigDaoProvider);
  final chatSvc = ref.watch(chatServiceProvider);
  return VocabularyConfigNotifier(apiDao, chatSvc, ref);
});
