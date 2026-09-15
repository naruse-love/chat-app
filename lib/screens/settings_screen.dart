import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/persistent_notification_provider.dart';
import '../providers/vocabulary_config_provider.dart';
import '../providers/anki_config_provider.dart';
import '../providers/vocabulary_provider.dart';
import '../providers/update_provider.dart';
import '../widgets/vocabulary_model_selector_dialog.dart';
import '../widgets/update_dialog.dart';

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
  late final TextEditingController _bingCookieController;
  bool _obscureGoogleApiKey = true;
  bool _obscureBingCookie = true;

  bool _hasSynced = false;
  String _currentVersion = '1.50.0+51';

  void _syncFieldsIfNeeded(AppSettings settings) {
    if (settings.isLoaded && !_hasSynced) {
      _searxngController.text = settings.searxngUrl;
      _googleApiKeyController.text = settings.googleSearchApiKey;
      _googleBaseUrlController.text = settings.googleSearchBaseUrl;
      _googleModelController.text = settings.googleSearchModel;
      _bingCookieController.text = settings.bingCookie;
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
    _bingCookieController = TextEditingController(text: settings.bingCookie);
    _hasSynced = settings.isLoaded;

    ref.read(updateServiceProvider).getCurrentVersion().then((ver) {
      if (mounted) {
        setState(() {
          _currentVersion = ver;
        });
      }
    });
  }

  @override
  void dispose() {
    _searxngController.dispose();
    _googleApiKeyController.dispose();
    _googleBaseUrlController.dispose();
    _googleModelController.dispose();
    _bingCookieController.dispose();
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
          SwitchListTile(
            title: const Text('启用 AI 网络搜索'),
            subtitle: const Text('关闭后 AI 模型回答时将不再调用外部网络搜索工具'),
            value: settings.enableAutoSearch,
            onChanged: (value) {
              notifier.updateEnableAutoSearch(value);
            },
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
          if (settings.searchBackend == 'bing' || settings.searchBackend == 'google_bing') ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bingCookieController,
                      obscureText: _obscureBingCookie,
                      decoration: InputDecoration(
                        labelText: 'Bing 登录 Cookie (可选)',
                        hintText: '粘贴 Bing 登录 Cookie 提升搜索质量与解封',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureBingCookie ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureBingCookie = !_obscureBingCookie;
                            });
                          },
                        ),
                      ),
                      onChanged: (val) {
                        notifier.updateBingCookie(val.trim());
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'none',
                        label: Text('None', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: 'minimal',
                        label: Text('Minimal', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: 'low',
                        label: Text('Low', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: 'medium',
                        label: Text('Medium', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: 'high',
                        label: Text('High', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: 'max',
                        label: Text('Max', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {
                      ['none', 'minimal', 'low', 'medium', 'high', 'max'].contains(settings.reasoningEffort)
                          ? settings.reasoningEffort
                          : 'medium'
                    },
                    onSelectionChanged: (selection) {
                      notifier.updateReasoningEffort(selection.first);
                    },
                    showSelectedIcon: false,
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
          ListTile(
            leading: const Icon(Icons.hub_outlined, color: Colors.deepPurple),
            title: const Text('MCP 服务管理'),
            subtitle: const Text('管理 Model Context Protocol 服务器与扩展工具'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/settings/mcp_servers');
            },
          ),
          const Divider(),

          // Security Sandbox Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '本地安全沙箱',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('启用本地安全沙箱'),
            subtitle: const Text('开启后 AI 默认在独立隔离沙箱目录操作文件；访问沙箱外部文件将提示用户授权确认'),
            value: settings.enableSandbox,
            onChanged: (value) {
              notifier.updateEnableSandbox(value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.workspaces_outlined, color: Colors.indigo),
            title: const Text('工作区根目录'),
            subtitle: Text(
              settings.workspacePath.isNotEmpty ? settings.workspacePath : '未设置（默认当前项目或应用沙箱）',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final controller = TextEditingController(text: settings.workspacePath);
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('设置工作区根目录'),
                  content: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: '工作区物理路径',
                      hintText: Platform.isAndroid ? '如 /sdcard/Documents/ChatApp' : '如 /home/as/chat',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await notifier.resetWorkspacePathToDefault();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('恢复默认'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              );
              if (result != null) {
                notifier.updateWorkspacePath(result);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_shared_outlined, color: Colors.teal),
            title: const Text('沙箱文件管理与导出'),
            subtitle: const Text('查看沙箱中的文件列表、预览内容、导出与清空'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/settings/sandbox');
            },
          ),
          const Divider(),

          // Persistent Notification Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '快捷入口与通知设置',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              final notifState = ref.watch(persistentNotificationProvider);
              return SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('通知栏常驻查词快捷入口'),
                subtitle: const Text('在系统通知栏常驻查词，支持直接输入单词并在通知栏即时展示释义'),
                value: notifState.isEnabled,
                onChanged: (value) {
                  ref
                      .read(persistentNotificationProvider.notifier)
                      .togglePersistentNotification(value);
                },
              );
            },
          ),
          const Divider(),

          // Vocabulary Settings Section
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '生词本设置',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              final vocabCfg = ref.watch(vocabularyConfigProvider);
              final providerName = vocabCfg.config?.name ?? '默认供应商';
              final modelName = vocabCfg.model?.modelName ??
                  vocabCfg.model?.id ??
                  '自动选择';
              return ListTile(
                leading:
                    const Icon(Icons.psychology_outlined, color: Colors.indigo),
                title: const Text('生词本专属翻译模型'),
                subtitle: Text(
                  '当前：$providerName · $modelName\n独立于聊天模型，用于生词抓取、消歧与中文翻译',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showVocabularyModelSelectorDialog(context);
                },
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) {
              final ankiConfig = ref.watch(ankiConfigProvider);
              return ListTile(
                leading: const Icon(Icons.style_outlined, color: Colors.blue),
                title: const Text('Anki 牌组名称'),
                subtitle: Text('当前：${ankiConfig.deckName}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final controller =
                      TextEditingController(text: ankiConfig.deckName);
                  final newDeck = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('设置 Anki 牌组名称'),
                      content: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: '牌组名称',
                          hintText: '如：日语生词本',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(ctx, controller.text.trim()),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                  if (newDeck != null && newDeck.isNotEmpty) {
                    await ref
                        .read(ankiConfigProvider.notifier)
                        .updateDeckName(newDeck);
                  }
                },
              );
            },
          ),
          Consumer(
            builder: (context, ref, _) {
              final ankiConfig = ref.watch(ankiConfigProvider);
              return ListTile(
                leading:
                    const Icon(Icons.view_carousel_outlined, color: Colors.teal),
                title: const Text('Anki 卡片模板名称'),
                subtitle: Text('当前：${ankiConfig.modelName}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final controller =
                      TextEditingController(text: ankiConfig.modelName);
                  final newModel = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('设置 Anki 卡片模板名称'),
                      content: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: '模板名称',
                          hintText: '如：日语生词本-AI',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(ctx, controller.text.trim()),
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                  if (newModel != null && newModel.isNotEmpty) {
                    await ref
                        .read(ankiConfigProvider.notifier)
                        .updateModelName(newModel);
                  }
                },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Colors.orange),
            title: const Text('重置单词导出状态'),
            subtitle: const Text('将所有生词的导出状态标记为未导出，以便重新导出'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('重置导出状态'),
                  content: const Text(
                    '确定要将所有生词重置为「未导出」状态吗？重置后可在生词本界面重新批量导出到 AnkiDroid。',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('确认重置'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await ref.read(vocabularyProvider.notifier).resetExportStatus();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已重置所有单词的导出状态'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
          ),
          const Divider(),

          // 关于与版本更新区块
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              '关于与版本更新',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('当前版本'),
            subtitle: Text(_currentVersion),
            trailing: Chip(
              label: Text(_currentVersion.split('+').first, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('启动时自动检查更新'),
            subtitle: const Text('开启后每次打开应用将在后台静默检测新版本'),
            value: ref.watch(updateProvider).autoCheckEnabled,
            onChanged: (value) {
              ref.read(updateProvider.notifier).setAutoCheckEnabled(value);
            },
          ),
          Builder(
            builder: (ctx) {
              final updateState = ref.watch(updateProvider);
              final isChecking = updateState.status == UpdateStatus.checking;
              return ListTile(
                leading: const Icon(Icons.system_update_rounded),
                title: const Text('检查新版本'),
                subtitle: const Text('连接 GitHub Releases 校验最新版本'),
                trailing: isChecking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: isChecking
                    ? null
                    : () async {
                        final scaffoldMessenger = ScaffoldMessenger.of(ctx);
                        final info = await ref
                            .read(updateProvider.notifier)
                            .checkForUpdate(silent: false);
                        if (!ctx.mounted) return;
                        if (info != null && info.hasUpdate) {
                          UpdateDialog.show(ctx, updateInfo: info);
                        } else if (info != null && !info.hasUpdate) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('当前已是最新版本 (${info.currentVersion})'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        } else {
                          final error = ref.read(updateProvider).errorMessage;
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(error ?? '检查更新失败，请重试'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('访问 GitHub 仓库'),
            subtitle: const Text('查看源代码、Releases 历史或提交 Issue'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ref.read(updateProvider.notifier).openReleaseInBrowser();
            },
          ),
        ],
      ),
    );
  }
}
