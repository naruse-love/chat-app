import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _searxngController;
  late final TextEditingController _googleApiKeyController;
  late final TextEditingController _googleBaseUrlController;
  late final TextEditingController _googleModelController;
  bool _obscureGoogleApiKey = true;

  bool _hasSynced = false;

  void _syncFieldsIfNeeded(AppSettings settings) {
    if (settings.isLoaded && !_hasSynced) {
      _searxngController.text = settings.searxngUrl;
      _googleApiKeyController.text = settings.googleSearchApiKey;
      _googleBaseUrlController.text = settings.googleSearchBaseUrl;
      _googleModelController.text = settings.googleSearchModel;
      _hasSynced = true;
    }
  }

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _searxngController = TextEditingController(text: settings.searxngUrl);
    _googleApiKeyController = TextEditingController(text: settings.googleSearchApiKey);
    _googleBaseUrlController = TextEditingController(text: settings.googleSearchBaseUrl);
    _googleModelController = TextEditingController(text: settings.googleSearchModel);
    _hasSynced = settings.isLoaded;
  }

  @override
  void dispose() {
    _searxngController.dispose();
    _googleApiKeyController.dispose();
    _googleBaseUrlController.dispose();
    _googleModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      _syncFieldsIfNeeded(next);
    });

    _syncFieldsIfNeeded(settings);

    final currentTheme = ref.watch(themeProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        children: [
          // Theme Switcher Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '外观设置',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            title: const Text('主题模式'),
            subtitle: const Text('选择浅色、深色或跟随系统主题'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('深色'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.settings_suggest),
                  label: Text('系统'),
                ),
              ],
              selected: {currentTheme},
              onSelectionChanged: (selection) {
                ref.read(themeProvider.notifier).setThemeMode(selection.first);
              },
              showSelectedIcon: false,
            ),
          ),
          const Divider(),

          // Search Backend Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '网络搜索设置',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '搜索后端',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'searxng',
                      label: Text('SearXNG', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 'bing',
                      label: Text('Bing', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 'google',
                      label: Text('Google', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 'google_bing',
                      label: Text('Google+Bing', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {settings.searchBackend},
                  onSelectionChanged: (selection) {
                    notifier.updateSearchBackend(selection.first);
                  },
                  showSelectedIcon: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (settings.searchBackend == 'searxng')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searxngController,
                      decoration: const InputDecoration(
                        labelText: 'SearXNG 基础 URL',
                        hintText: '例如 http://localhost:8080',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        notifier.updateSearxngUrl(val.trim());
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (settings.searchBackend == 'google' || settings.searchBackend == 'google_bing') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _googleApiKeyController,
                      obscureText: _obscureGoogleApiKey,
                      decoration: InputDecoration(
                        labelText: 'Google AI Studio API Key',
                        hintText: '输入您的 Gemini API 密钥',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureGoogleApiKey ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureGoogleApiKey = !_obscureGoogleApiKey;
                            });
                          },
                        ),
                      ),
                      onChanged: (val) {
                        notifier.updateGoogleSearchApiKey(val.trim());
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _googleBaseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Google AI Studio 基础 URL',
                        hintText: '例如 https://generativelanguage.googleapis.com',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        notifier.updateGoogleSearchBaseUrl(val.trim());
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _googleModelController,
                      decoration: const InputDecoration(
                        labelText: 'Google Grounding 模型',
                        hintText: '例如 gemini-2.5-flash',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        notifier.updateGoogleSearchModel(val.trim());
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(),

          // Model Reasoning Effort Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '模型思考设置',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '思考等级 (Reasoning Effort)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '适用于支持思考的 AI 模型（如 OpenCode Free / o1 / DeepSeek 等）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'none',
                      label: Text('关闭', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 'low',
                      label: Text('低', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 'medium',
                      label: Text('中', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 'high',
                      label: Text('高', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {settings.reasoningEffort},
                  onSelectionChanged: (selection) {
                    notifier.updateReasoningEffort(selection.first);
                  },
                  showSelectedIcon: false,
                ),
              ],
            ),
          ),
          const Divider(),

          // Configuration Managers Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '配置管理',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('API 配置'),
            subtitle: const Text('管理您的端点和 API 密钥'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/settings/api_config');
            },
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('系统提示词模板'),
            subtitle: const Text('配置并应用系统提示指令'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/settings/system_prompts');
            },
          ),
        ],
      ),
    );
  }
}
