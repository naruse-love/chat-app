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

  void _syncSearxngIfNeeded(String url) {
    if (_searxngController.text.isEmpty && url.isNotEmpty) {
      _searxngController.text = url;
    }
  }

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _searxngController = TextEditingController(text: settings.searxngUrl);
  }

  @override
  void dispose() {
    _searxngController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      _syncSearxngIfNeeded(next.searxngUrl);
    });

    _syncSearxngIfNeeded(settings.searxngUrl);

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
              '网络搜索 (SearXNG)',
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
                      label: Text('SearXNG'),
                    ),
                    ButtonSegment(
                      value: 'bing',
                      label: Text('Bing（实验）'),
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
