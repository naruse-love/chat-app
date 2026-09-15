import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anki 导出配置状态
class AnkiConfig {
  static const String defaultDeckName = 'gal';
  static const String legacyDefaultModelName = '日语生词本-AI';
  static const String defaultModelName = '日语生词本-AI-v2';

  final String deckName;
  final String modelName;
  final bool isLoaded;

  const AnkiConfig({
    this.deckName = defaultDeckName,
    this.modelName = defaultModelName,
    this.isLoaded = false,
  });

  AnkiConfig copyWith({
    String? deckName,
    String? modelName,
    bool? isLoaded,
  }) {
    return AnkiConfig(
      deckName: deckName ?? this.deckName,
      modelName: modelName ?? this.modelName,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

/// Anki 配置状态管理器
class AnkiConfigNotifier extends StateNotifier<AnkiConfig> {
  static const String _prefKeyDeckName = 'anki_deck_name';
  static const String _prefKeyModelName = 'anki_model_name';

  late final Future<void> initialization;

  AnkiConfigNotifier() : super(const AnkiConfig()) {
    initialization = _loadConfig();
  }

  /// 确保本地持久化配置已完全加载完毕（防止重进应用时的时序竞争回退）
  Future<AnkiConfig> ensureLoaded() async {
    await initialization;
    return state;
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final deckName = prefs.getString(_prefKeyDeckName) ?? AnkiConfig.defaultDeckName;
      final savedModelName = prefs.getString(_prefKeyModelName);
      final modelName = savedModelName == null ||
              savedModelName.trim() == AnkiConfig.legacyDefaultModelName
          ? AnkiConfig.defaultModelName
          : savedModelName;
      if (savedModelName != modelName) {
        await prefs.setString(_prefKeyModelName, modelName);
      }
      state = state.copyWith(
        deckName: deckName,
        modelName: modelName,
        isLoaded: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(isLoaded: true);
    }
  }

  Future<void> updateDeckName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyDeckName, clean);
      if (!mounted) return;
      state = state.copyWith(deckName: clean);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(deckName: clean);
    }
  }

  Future<void> updateModelName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyModelName, clean);
      if (!mounted) return;
      state = state.copyWith(modelName: clean);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(modelName: clean);
    }
  }
}

final ankiConfigProvider =
    StateNotifierProvider<AnkiConfigNotifier, AnkiConfig>((ref) {
  return AnkiConfigNotifier();
});
