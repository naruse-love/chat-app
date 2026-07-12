import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/api_config.dart';
import '../data/database_helper.dart';
import '../services/secure_storage_service.dart';
import '../data/api_config_dao.dart';

// Base providers for DI
final dbHelperProvider = Provider<DatabaseHelper>((ref) => DatabaseHelper.instance);

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) => SecureStorageService());

final apiConfigDaoProvider = Provider<ApiConfigDao>((ref) {
  final db = ref.watch(dbHelperProvider);
  final secure = ref.watch(secureStorageServiceProvider);
  return ApiConfigDao(db, secure);
});

class ApiConfigState {
  final List<ApiConfig> configs;
  final ApiConfig? activeConfig;
  final bool isLoading;
  final String? error;

  ApiConfigState({
    this.configs = const [],
    this.activeConfig,
    this.isLoading = false,
    this.error,
  });

  ApiConfigState copyWith({
    List<ApiConfig>? configs,
    ApiConfig? activeConfig,
    bool? isLoading,
    String? error,
  }) {
    return ApiConfigState(
      configs: configs ?? this.configs,
      activeConfig: activeConfig ?? this.activeConfig,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ApiConfigNotifier extends StateNotifier<ApiConfigState> {
  final ApiConfigDao _apiConfigDao;

  ApiConfigNotifier(this._apiConfigDao) : super(ApiConfigState()) {
    loadConfigs();
  }

  Future<void> loadConfigs() async {
    state = state.copyWith(isLoading: true);
    try {
      final configs = await _apiConfigDao.getAll();
      ApiConfig? active = await _apiConfigDao.getDefault();
      if (active == null && configs.isNotEmpty) {
        active = configs.first;
      }
      state = ApiConfigState(configs: configs, activeConfig: active, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> createConfig(ApiConfig config, String apiKey) async {
    state = state.copyWith(isLoading: true);
    try {
      await _apiConfigDao.insert(config, apiKey);
      await loadConfigs();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updateConfig(ApiConfig config, {String? apiKey}) async {
    state = state.copyWith(isLoading: true);
    try {
      await _apiConfigDao.update(config, apiKey: apiKey);
      await loadConfigs();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deleteConfig(String id) async {
    state = state.copyWith(isLoading: true);
    try {
      await _apiConfigDao.delete(id);
      await loadConfigs();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setActiveConfig(ApiConfig config) {
    state = state.copyWith(activeConfig: config);
  }

  Future<void> setDefaultConfig(ApiConfig config) async {
    state = state.copyWith(isLoading: true);
    try {
      final updated = config.copyWith(isDefault: true);
      await _apiConfigDao.update(updated);
      await loadConfigs();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final apiConfigProvider = StateNotifierProvider<ApiConfigNotifier, ApiConfigState>((ref) {
  final dao = ref.watch(apiConfigDaoProvider);
  return ApiConfigNotifier(dao);
});
