import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/api_config.dart';
import '../providers/api_config_provider.dart';
import '../providers/model_provider.dart'; // To get chatServiceProvider

class ApiConfigScreen extends ConsumerWidget {
  const ApiConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(apiConfigProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API 配置'),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.configs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.api, size: 64, color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 16),
                      Text(
                        '暂无 API 配置',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => _showFormDialog(context, ref),
                        child: const Text('添加配置'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: state.configs.length,
                  padding: const EdgeInsets.all(12),
                  itemBuilder: (context, index) {
                    final config = state.configs[index];
                    final isActive = state.activeConfig?.id == config.id;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isActive
                            ? BorderSide(color: theme.colorScheme.primary, width: 2)
                            : BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                config.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (config.isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: theme.colorScheme.primary),
                                ),
                                child: Text(
                                  '默认',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          config.baseUrl,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') {
                              _showFormDialog(context, ref, config: config);
                            } else if (value == 'delete') {
                              await ref.read(apiConfigProvider.notifier).deleteConfig(config.id);
                            } else if (value == 'set_default') {
                              await ref.read(apiConfigProvider.notifier).setDefaultConfig(config);
                            } else if (value == 'set_active') {
                              ref.read(apiConfigProvider.notifier).setActiveConfig(config);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'set_active',
                              child: Text('选为活动配置'),
                            ),
                            const PopupMenuItem(
                              value: 'set_default',
                              child: Text('设为默认配置'),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('编辑'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('删除'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: state.configs.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _showFormDialog(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showFormDialog(BuildContext context, WidgetRef ref, {ApiConfig? config}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ApiConfigFormDialog(config: config),
    );
  }
}

class ApiConfigFormDialog extends ConsumerStatefulWidget {
  final ApiConfig? config;

  const ApiConfigFormDialog({super.key, this.config});

  @override
  ConsumerState<ApiConfigFormDialog> createState() => _ApiConfigFormDialogState();
}

class _ApiConfigFormDialogState extends ConsumerState<ApiConfigFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  bool _obscureKey = true;
  bool _isTesting = false;
  bool? _testResultSuccess;
  String? _testResultMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.config?.name ?? '');
    _urlController = TextEditingController(text: widget.config?.baseUrl ?? '');
    _keyController = TextEditingController();
    if (widget.config != null) {
      _loadExistingKey();
    }
  }

  Future<void> _loadExistingKey() async {
    final dao = ref.read(apiConfigDaoProvider);
    final key = await dao.getApiKey(widget.config!.apiKeyRef);
    if (mounted && key != null) {
      _keyController.text = key;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResultSuccess = null;
      _testResultMessage = null;
    });

    try {
      final chatService = ref.read(chatServiceProvider);
      final models = await chatService.getModels(
        baseUrl: _urlController.text.trim(),
        apiKey: _keyController.text.trim(),
      );

      setState(() {
        _isTesting = false;
        _testResultSuccess = true;
        _testResultMessage = '连接成功！找到 ${models.length} 个模型。';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testResultSuccess = false;
        _testResultMessage = '连接失败: ${e.toString()}';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final baseUrl = _urlController.text.trim();
    final apiKey = _keyController.text.trim();

    final notifier = ref.read(apiConfigProvider.notifier);

    if (widget.config != null) {
      final updated = widget.config!.copyWith(
        name: name,
        baseUrl: baseUrl,
      );
      await notifier.updateConfig(updated, apiKey: apiKey.isNotEmpty ? apiKey : null);
    } else {
      final id = const Uuid().v4();
      final newConfig = ApiConfig(
        id: id,
        name: name,
        baseUrl: baseUrl,
        apiKeyRef: 'api_key_$id',
        isDefault: false,
        createdAt: DateTime.now(),
      );
      await notifier.createConfig(newConfig, apiKey);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.config != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑 API 配置' : '添加 API 配置'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '配置名称',
                    hintText: '例如 9Router Global',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? '名称为必填项' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: '基础 URL',
                    hintText: 'https://api.9router.com/v1',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? '基础 URL 为必填项' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _keyController,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'API 密钥',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                  validator: (val) {
                    if (!isEdit && (val == null || val.trim().isEmpty)) {
                      return 'API 密钥为必填项';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      onPressed: _isTesting ? null : _testConnection,
                      child: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('测试连接'),
                    ),
                    if (_testResultSuccess != null)
                      Icon(
                        _testResultSuccess! ? Icons.check_circle : Icons.error,
                        color: _testResultSuccess! ? Colors.green : Colors.red,
                      ),
                  ],
                ),
                if (_testResultMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _testResultMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _testResultSuccess! ? Colors.green : Colors.red,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
