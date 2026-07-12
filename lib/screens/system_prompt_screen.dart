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
        title: const Text('System Prompts'),
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
                                const SnackBar(content: Text('System prompt applied successfully!')),
                              );
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No active conversation to apply prompt.')),
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
                          child: Text('Apply to Current Chat'),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
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

    return AlertDialog(
      title: Text(isEdit ? 'Edit System Prompt' : 'Create System Prompt'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Creative Writer',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. Writes poems, stories...',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'System Prompt Content',
                  hintText: 'You are a professional creative writer...',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Prompt content is required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
