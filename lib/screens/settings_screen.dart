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
    final currentTheme = ref.watch(themeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        children: [
          // Theme Switcher Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Appearance',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            title: const Text('Theme Mode'),
            subtitle: const Text('Choose light, dark, or system theme'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Dark'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.settings_suggest),
                  label: Text('System'),
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

          // SearXNG Search Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Web Search Fallback',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searxngController,
                    decoration: const InputDecoration(
                      labelText: 'SearXNG Base URL',
                      hintText: 'e.g. http://localhost:8080',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).updateSearxngUrl(val.trim());
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
              'Configuration Managers',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('API Configurations'),
            subtitle: const Text('Manage your endpoints and keys'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/settings/api_config');
            },
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('System Prompt Templates'),
            subtitle: const Text('Configure and apply system instructions'),
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
