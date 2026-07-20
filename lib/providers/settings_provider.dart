import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/system_prompt_template.dart';
import '../data/database_helper.dart';
import '../services/secure_storage_service.dart';
import 'api_config_provider.dart'; // To reuse dbHelperProvider

// Settings structures
class AppSettings {
  final String searxngUrl;
  final String defaultSystemPrompt;
  final bool enableAutoSearch;
  final String searchBackend;
  final String googleSearchApiKey;
  final String googleSearchBaseUrl;
  final String googleSearchModel;
  final String reasoningEffort;
  final bool isLoaded;

  AppSettings({
    this.searxngUrl = '',
    this.defaultSystemPrompt = 'You are a helpful assistant.',
    this.enableAutoSearch = true,
    this.searchBackend = 'searxng',
    this.googleSearchApiKey = '',
    this.googleSearchBaseUrl = 'https://generativelanguage.googleapis.com',
    this.googleSearchModel = 'gemini-2.5-flash',
    this.reasoningEffort = 'medium',
    this.isLoaded = false,
  });

  AppSettings copyWith({
    String? searxngUrl,
    String? defaultSystemPrompt,
    bool? enableAutoSearch,
    String? searchBackend,
    String? googleSearchApiKey,
    String? googleSearchBaseUrl,
    String? googleSearchModel,
    String? reasoningEffort,
    bool? isLoaded,
  }) {
    return AppSettings(
      searxngUrl: searxngUrl ?? this.searxngUrl,
      defaultSystemPrompt: defaultSystemPrompt ?? this.defaultSystemPrompt,
      enableAutoSearch: enableAutoSearch ?? this.enableAutoSearch,
      searchBackend: searchBackend ?? this.searchBackend,
      googleSearchApiKey: googleSearchApiKey ?? this.googleSearchApiKey,
      googleSearchBaseUrl: googleSearchBaseUrl ?? this.googleSearchBaseUrl,
      googleSearchModel: googleSearchModel ?? this.googleSearchModel,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _searxngKey = 'searxng_url';
  static const _systemPromptKey = 'default_system_prompt';
  static const _autoSearchKey = 'enable_auto_search';
  static const _searchBackendKey = 'search_backend';
  static const _googleSearchBaseUrlKey = 'google_search_base_url';
  static const _googleSearchModelKey = 'google_search_model';
  static const _reasoningEffortKey = 'reasoning_effort';
  static const _googleSearchApiKeySecureKey = 'google_search_api_key';

  final SecureStorageService _secureStorage;
  bool isLoaded = false;
  late final Future<void> initialization;

  SettingsNotifier(this._secureStorage) : super(AppSettings()) {
    initialization = _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = await _secureStorage.read(_googleSearchApiKeySecureKey) ?? '';
      if (!mounted) return;
      isLoaded = true;
      state = AppSettings(
        searxngUrl: prefs.getString(_searxngKey) ?? '',
        defaultSystemPrompt: prefs.getString(_systemPromptKey) ?? 'You are a helpful assistant.',
        enableAutoSearch: prefs.getBool(_autoSearchKey) ?? true,
        searchBackend: prefs.getString(_searchBackendKey) ?? 'searxng',
        googleSearchApiKey: apiKey,
        googleSearchBaseUrl: prefs.getString(_googleSearchBaseUrlKey) ?? 'https://generativelanguage.googleapis.com',
        googleSearchModel: prefs.getString(_googleSearchModelKey) ?? 'gemini-2.5-flash',
        reasoningEffort: prefs.getString(_reasoningEffortKey) ?? 'medium',
        isLoaded: true,
      );
    } catch (_) {
      isLoaded = true;
    }
  }

  Future<void> updateSearxngUrl(String url) async {
    state = state.copyWith(searxngUrl: url);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_searxngKey, url);
    } catch (_) {}
  }

  Future<void> updateDefaultSystemPrompt(String prompt) async {
    state = state.copyWith(defaultSystemPrompt: prompt);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_systemPromptKey, prompt);
    } catch (_) {}
  }

  Future<void> updateEnableAutoSearch(bool enabled) async {
    state = state.copyWith(enableAutoSearch: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoSearchKey, enabled);
    } catch (_) {}
  }

  Future<void> updateSearchBackend(String backend) async {
    state = state.copyWith(searchBackend: backend);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_searchBackendKey, backend);
    } catch (_) {}
  }

  Future<void> updateGoogleSearchApiKey(String apiKey) async {
    state = state.copyWith(googleSearchApiKey: apiKey);
    try {
      await _secureStorage.write(_googleSearchApiKeySecureKey, apiKey);
    } catch (_) {}
  }

  Future<void> updateGoogleSearchBaseUrl(String url) async {
    state = state.copyWith(googleSearchBaseUrl: url);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_googleSearchBaseUrlKey, url);
    } catch (_) {}
  }

  Future<void> updateGoogleSearchModel(String model) async {
    state = state.copyWith(googleSearchModel: model);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_googleSearchModelKey, model);
    } catch (_) {}
  }

  Future<void> updateReasoningEffort(String effort) async {
    state = state.copyWith(reasoningEffort: effort);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_reasoningEffortKey, effort);
    } catch (_) {}
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  return SettingsNotifier(secureStorage);
});

// System Prompt Template DAO & Notifier
class SystemPromptTemplateDao {
  final DatabaseHelper _dbHelper;
  SystemPromptTemplateDao(this._dbHelper);

  Future<void> insert(SystemPromptTemplate template) async {
    final db = await _dbHelper.database;
    final map = template.toJson();
    map['createdAt'] = template.createdAt.toIso8601String();
    await db.insert('system_prompts', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SystemPromptTemplate>> getAll() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('system_prompts', orderBy: 'createdAt DESC');
    return maps.map((m) {
      final map = Map<String, dynamic>.from(m);
      return SystemPromptTemplate.fromJson(map);
    }).toList();
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('system_prompts', where: 'id = ?', whereArgs: [id]);
  }
}

final systemPromptDaoProvider = Provider<SystemPromptTemplateDao>((ref) {
  final dbHelper = ref.watch(dbHelperProvider);
  return SystemPromptTemplateDao(dbHelper);
});

class SystemPromptsNotifier extends StateNotifier<List<SystemPromptTemplate>> {
  final SystemPromptTemplateDao _dao;

  SystemPromptsNotifier(this._dao) : super([]) {
    loadTemplates();
  }

  Future<void> loadTemplates() async {
    try {
      var list = await _dao.getAll();
      if (!mounted) return;
      if (list.isEmpty) {
        // Prepopulate default templates
        final defaultTemplates = [
          SystemPromptTemplate(
            id: 'template_assistant',
            title: 'Helpful Assistant',
            content: 'You are a helpful assistant.',
            description: 'Default general-purpose helpful AI assistant.',
            createdAt: DateTime.now(),
          ),
          SystemPromptTemplate(
            id: 'template_developer',
            title: 'Software Architect',
            content: 'You are an expert software engineer and architect. Provide clean, efficient, and well-documented code solutions.',
            description: 'Focused on coding, systems design, and code optimization.',
            createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
          SystemPromptTemplate(
            id: 'template_translator',
            title: 'Translator',
            content: 'You are a professional translator. Translate all input text into fluent, natural language.',
            description: 'Translates languages accurately with contextual understanding.',
            createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
          ),
        ];

        for (final t in defaultTemplates) {
          await _dao.insert(t);
          if (!mounted) return;
        }
        list = await _dao.getAll();
        if (!mounted) return;
      }
      state = list;
    } catch (_) {}
  }

  Future<void> addTemplate(SystemPromptTemplate template) async {
    await _dao.insert(template);
    if (!mounted) return;
    await loadTemplates();
  }

  Future<void> deleteTemplate(String id) async {
    await _dao.delete(id);
    if (!mounted) return;
    await loadTemplates();
  }
}

final systemPromptsProvider = StateNotifierProvider<SystemPromptsNotifier, List<SystemPromptTemplate>>((ref) {
  final dao = ref.watch(systemPromptDaoProvider);
  return SystemPromptsNotifier(dao);
});
