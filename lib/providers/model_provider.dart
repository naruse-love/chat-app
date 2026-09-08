import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/model_info.dart';
import '../models/api_config.dart';
import '../services/chat_service.dart';
import '../data/api_config_dao.dart';
import 'api_config_provider.dart';

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

class ModelState {
  final List<ModelInfo> models;
  final ModelInfo? selectedModel;
  final bool isLoading;
  final String? error;

  ModelState({
    this.models = const [],
    this.selectedModel,
    this.isLoading = false,
    this.error,
  });

  ModelState copyWith({
    List<ModelInfo>? models,
    ModelInfo? selectedModel,
    bool? isLoading,
    String? error,
  }) {
    return ModelState(
      models: models ?? this.models,
      selectedModel: selectedModel ?? this.selectedModel,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ModelNotifier extends StateNotifier<ModelState> {
  final ChatService _chatService;
  final ApiConfigDao _apiConfigDao;
  final ApiConfig? _activeConfig;

  static String _cacheKey(String configId) => 'cached_models_$configId';
  static String _lastSelectedKey(String configId) => 'last_selected_model_$configId';

  ModelNotifier(this._chatService, this._apiConfigDao, this._activeConfig) : super(ModelState()) {
    fetchModels();
  }

  ModelInfo? _pickDefaultModel(List<ModelInfo> list) {
    if (list.isEmpty) return null;
    if (_activeConfig?.id == 'opencode_free') {
      final idx = list.indexWhere((m) => m.id == 'deepseek-v4-flash-free');
      if (idx != -1) return list[idx];
    }
    return list.first;
  }

  Future<void> fetchModels({bool forceRefresh = false}) async {
    if (_activeConfig == null) {
      state = ModelState();
      return;
    }

    final configId = _activeConfig.id;
    final cacheKey = _cacheKey(configId);
    final lastSelectedKey = _lastSelectedKey(configId);

    // 1. 若非强制刷新，优先从本地缓存快速加载模型与上次选中的模型，退出重进无需再次网络加载
    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedJson = prefs.getString(cacheKey);
        if (cachedJson != null && cachedJson.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(cachedJson);
          final cachedModels = decoded
              .whereType<Map<String, dynamic>>()
              .map((m) => ModelInfo.fromJson(m))
              .toList();

          if (cachedModels.isNotEmpty) {
            final savedModelId = prefs.getString(lastSelectedKey);
            ModelInfo? selected;
            if (savedModelId != null) {
              final matchIdx = cachedModels.indexWhere((m) => m.id == savedModelId);
              if (matchIdx != -1) {
                selected = cachedModels[matchIdx];
              }
            }
            selected ??= _pickDefaultModel(cachedModels);

            if (!mounted) return;
            state = ModelState(
              models: cachedModels,
              selectedModel: selected,
              isLoading: false,
            );
            return;
          }
        }
      } catch (_) {}
    }

    // 2. 从网络拉取最新模型列表
    state = state.copyWith(isLoading: true, error: null);
    try {
      final apiKey = await _apiConfigDao.getApiKey(_activeConfig.apiKeyRef) ?? '';
      if (!mounted) return;
      var models = await _chatService.getModels(
        baseUrl: _activeConfig.baseUrl,
        apiKey: apiKey,
      );
      if (!mounted) return;

      if (_activeConfig.id == 'opencode_free') {
        models = models.where((m) => m.id.toLowerCase().contains('free')).toList();
      }

      // 持久化缓存最新拉取的模型列表
      try {
        final prefs = await SharedPreferences.getInstance();
        final encoded = jsonEncode(models.map((m) => m.toJson()).toList());
        await prefs.setString(cacheKey, encoded);
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      final savedModelId = prefs.getString(lastSelectedKey);
      ModelInfo? selected;
      if (savedModelId != null) {
        final matchIdx = models.indexWhere((m) => m.id == savedModelId);
        if (matchIdx != -1) {
          selected = models[matchIdx];
        }
      }
      selected ??= state.selectedModel;
      if (selected == null || !models.any((m) => m.id == selected!.id)) {
        selected = _pickDefaultModel(models);
      }

      if (!mounted) return;
      state = ModelState(models: models, selectedModel: selected, isLoading: false);
    } catch (e) {
      if (!mounted) return;
      if (state.models.isNotEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: '获取模型列表失败: $e',
        );
        return;
      }
      var fallbackModels = ModelInfo.defaultOpenCodeFallbackModels;
      if (_activeConfig.id == 'opencode_free') {
        fallbackModels = fallbackModels.where((m) => m.id.toLowerCase().contains('free')).toList();
      }
      ModelInfo? selected = state.selectedModel;
      if (selected == null || !fallbackModels.any((m) => m.id == selected!.id)) {
        selected = _pickDefaultModel(fallbackModels);
      }
      state = ModelState(
        models: fallbackModels,
        selectedModel: selected,
        isLoading: false,
        error: '获取模型列表失败: $e',
      );
    }
  }

  void selectModel(ModelInfo model) {
    state = state.copyWith(selectedModel: model);
    if (_activeConfig != null) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(_lastSelectedKey(_activeConfig.id), model.id);
      }).catchError((_) {});
    }
  }

  void addCustomModel(String modelId) {
    final parts = modelId.split('/');
    final providerName = parts.length > 1 ? parts[0] : 'custom';
    final modelName = parts.length > 1 ? parts.sublist(1).join('/') : modelId;
    
    final customModel = ModelInfo(
      id: modelId,
      provider: providerName,
      modelName: modelName,
      supportsVision: modelId.toLowerCase().contains('vision') || modelId.toLowerCase().contains('vl'),
      supportsTools: true, // Default to true to allow search capability
    );

    final List<ModelInfo> updatedList = List.from(state.models);
    if (!updatedList.any((m) => m.id == modelId)) {
      updatedList.add(customModel);
    }
    state = state.copyWith(models: updatedList, selectedModel: customModel);

    // 持久化自定义模型与当前选择
    if (_activeConfig != null) {
      SharedPreferences.getInstance().then((prefs) {
        final cacheKey = _cacheKey(_activeConfig.id);
        final encoded = jsonEncode(updatedList.map((m) => m.toJson()).toList());
        prefs.setString(cacheKey, encoded);
        prefs.setString(_lastSelectedKey(_activeConfig.id), customModel.id);
      }).catchError((_) {});
    }
  }
}

final modelProvider = StateNotifierProvider<ModelNotifier, ModelState>((ref) {
  final activeConfig = ref.watch(apiConfigProvider.select((s) => s.activeConfig));
  final chatSvc = ref.watch(chatServiceProvider);
  final apiConfigDao = ref.watch(apiConfigDaoProvider);
  return ModelNotifier(chatSvc, apiConfigDao, activeConfig);
});
