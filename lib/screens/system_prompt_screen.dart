import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/system_prompt_template.dart';
import '../providers/settings_provider.dart';
import '../providers/conversation_provider.dart';

class SystemPromptScreen extends ConsumerWidget {
  const SystemPromptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(systemPromptsProvider);
    final activeConv = ref.watch(conversationProvider).activeConversation;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('系统提示词'),
      ),
      body: templates.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: templates.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final template = templates[index];
                final isApplied = activeConv?.systemPrompt == template.content;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isApplied
                        ? BorderSide(color: theme.colorScheme.primary, width: 2)
                        : BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    title: Text(
                      template.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (template.description != null && template.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            template.description!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.brightness == Brightness.light
                                ? Colors.grey[100]
                                : Colors.grey[900],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            template.content,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'apply') {
                          if (activeConv != null) {
                            await ref.read(conversationProvider.notifier).updateConversation(
                              activeConv.copyWith(systemPrompt: template.content),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('系统提示词应用成功！')),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('当前没有活跃的对话。')),
                            );
                          }
                        } else if (value == 'edit') {
                          _showFormDialog(context, ref, template: template);
                        } else if (value == 'delete') {
                          await ref.read(systemPromptsProvider.notifier).deleteTemplate(template.id);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'apply',
                          child: Text('应用到当前对话'),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showFormDialog(BuildContext context, WidgetRef ref, {SystemPromptTemplate? template}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SystemPromptFormDialog(template: template),
    );
  }
}

class SystemPromptFormDialog extends ConsumerStatefulWidget {
  final SystemPromptTemplate? template;

  const SystemPromptFormDialog({super.key, this.template});

  @override
  ConsumerState<SystemPromptFormDialog> createState() => _SystemPromptFormDialogState();
}

class _SystemPromptFormDialogState extends ConsumerState<SystemPromptFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.template?.title ?? '');
    _descController = TextEditingController(text: widget.template?.description ?? '');
    _contentController = TextEditingController(text: widget.template?.content ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final description = _descController.text.trim();
    final content = _contentController.text.trim();

    final notifier = ref.read(systemPromptsProvider.notifier);

    if (widget.template != null) {
      final updated = widget.template!.copyWith(
        title: title,
        description: description,
        content: content,
      );
      await notifier.addTemplate(updated);
    } else {
      final id = const Uuid().v4();
      final newTemplate = SystemPromptTemplate(
        id: id,
        title: title,
        description: description,
        content: content,
        createdAt: DateTime.now(),
      );
      await notifier.addTemplate(newTemplate);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.template != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑系统提示词' : '创建系统提示词'),
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
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    hintText: '例如 创意写作助手',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? '标题为必填项' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: '描述',
                    hintText: '例如 擅长写诗和讲故事...',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contentController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '提示词内容',
                    hintText: '例如 你是一个专业的创意写作助手...',
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? '提示词内容为必填项' : null,
                ),
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
