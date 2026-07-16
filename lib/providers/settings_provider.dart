import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/system_prompt_template.dart';
import '../data/database_helper.dart';
import 'api_config_provider.dart'; // To reuse dbHelperProvider

// Settings structures
class AppSettings {
  final String searxngUrl;
  final String defaultSystemPrompt;
  final bool enableAutoSearch;
  final String searchBackend;

  AppSettings({
    this.searxngUrl = '',
    this.defaultSystemPrompt = 'You are a helpful assistant.',
    this.enableAutoSearch = true,
    this.searchBackend = 'searxng',
  });

  AppSettings copyWith({
    String? searxngUrl,
    String? defaultSystemPrompt,
    bool? enableAutoSearch,
    String? searchBackend,
  }) {
    return AppSettings(
      searxngUrl: searxngUrl ?? this.searxngUrl,
      defaultSystemPrompt: defaultSystemPrompt ?? this.defaultSystemPrompt,
      enableAutoSearch: enableAutoSearch ?? this.enableAutoSearch,
      searchBackend: searchBackend ?? this.searchBackend,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _searxngKey = 'searxng_url';
  static const _systemPromptKey = 'default_system_prompt';
  static const _autoSearchKey = 'enable_auto_search';
  static const _searchBackendKey = 'search_backend';

  bool isLoaded = false;
  late final Future<void> initialization;

  SettingsNotifier() : super(AppSettings()) {
    initialization = _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      isLoaded = true;
      state = AppSettings(
        searxngUrl: prefs.getString(_searxngKey) ?? '',
        defaultSystemPrompt: prefs.getString(_systemPromptKey) ?? 'You are a helpful assistant.',
        enableAutoSearch: prefs.getBool(_autoSearchKey) ?? true,
        searchBackend: prefs.getString(_searchBackendKey) ?? 'searxng',
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
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
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
