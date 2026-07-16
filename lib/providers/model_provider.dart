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

  ModelNotifier(this._chatService, this._apiConfigDao, this._activeConfig) : super(ModelState()) {
    fetchModels();
  }

  Future<void> fetchModels() async {
    if (_activeConfig == null) {
      state = ModelState();
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final apiKey = await _apiConfigDao.getApiKey(_activeConfig.apiKeyRef) ?? '';
      final models = await _chatService.getModels(
        baseUrl: _activeConfig.baseUrl,
        apiKey: apiKey,
      );

      ModelInfo? selected = state.selectedModel;
      if (selected == null || !models.any((m) => m.id == selected!.id)) {
        selected = models.isNotEmpty ? models.first : null;
      }

      state = ModelState(models: models, selectedModel: selected, isLoading: false);
    } catch (e) {
      final fallbackModels = ModelInfo.defaultOpenCodeFallbackModels;
      ModelInfo? selected = state.selectedModel;
      if (selected == null || !fallbackModels.any((m) => m.id == selected!.id)) {
        selected = fallbackModels.isNotEmpty ? fallbackModels.first : null;
      }
      state = ModelState(
        models: fallbackModels,
        selectedModel: selected,
        isLoading: false,
      );
    }
  }

  void selectModel(ModelInfo model) {
    state = state.copyWith(selectedModel: model);
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
  }
}

final modelProvider = StateNotifierProvider<ModelNotifier, ModelState>((ref) {
  final activeConfig = ref.watch(apiConfigProvider.select((s) => s.activeConfig));
  final chatSvc = ref.watch(chatServiceProvider);
  final apiConfigDao = ref.watch(apiConfigDaoProvider);
  return ModelNotifier(chatSvc, apiConfigDao, activeConfig);
});
