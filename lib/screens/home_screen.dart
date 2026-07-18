import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation.dart';
import '../providers/api_config_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/model_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/agent_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';
import '../models/chat_message.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showArchived = false;

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final agentState = ref.watch(agentProvider);
    final apiState = ref.watch(apiConfigProvider);
    final modelState = ref.watch(modelProvider);
    final convState = ref.watch(conversationProvider);
    final theme = Theme.of(context);

    // Set up auto scroll listener
    ref.listen<ChatState>(chatProvider, (prev, next) {
      if (next.messages.length != prev?.messages.length ||
          next.streamContent != prev?.streamContent ||
          next.streamReasoning != prev?.streamReasoning) {
        _scrollToBottom();
      }
    });

    final isLargeScreen = MediaQuery.of(context).size.width > 800;

    // Filter conversations
    final pinnedConvs = convState.conversations.where((c) => c.isPinned && !c.isArchived).toList();
    final recentConvs = convState.conversations.where((c) => !c.isPinned && !c.isArchived).toList();
    final archivedConvs = convState.conversations.where((c) => c.isArchived).toList();

    Widget buildDrawerContent() {
      return Container(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      '智能助手聊天',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // New Chat Button
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  ref.read(conversationProvider.notifier).setActiveConversation(null);
                  if (!isLargeScreen) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('新建聊天'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (pinnedConvs.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text('已置顶', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    ...pinnedConvs.map((c) => _buildConversationTile(c)),
                    const Divider(),
                  ],
                  if (recentConvs.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text('最近对话', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    ...recentConvs.map((c) => _buildConversationTile(c)),
                    const Divider(),
                  ],
                  // Archived Collapsible
                  ListTile(
                    title: Text(
                      '归档聊天 (${archivedConvs.length})',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                    trailing: Icon(
                      _showArchived ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.outline,
                    ),
                    onTap: () {
                      setState(() {
                        _showArchived = !_showArchived;
                      });
                    },
                  ),
                  if (_showArchived)
                    ...archivedConvs.map((c) => _buildConversationTile(c)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildChatArea() {
      final isBusy = agentState.isSearching || agentState.isFetchingUrl;

      // Build active streaming message if currently generating
      final activeStreamingMessage = chatState.isGenerating &&
              (chatState.streamContent.isNotEmpty || chatState.streamReasoning.isNotEmpty)
          ? ChatMessage(
              id: 'streaming_msg',
              conversationId: convState.activeConversation?.id ?? '',
              role: 'assistant',
              content: chatState.streamContent,
              reasoningContent: chatState.streamReasoning.isNotEmpty ? chatState.streamReasoning : null,
              timestamp: DateTime.now(),
            )
          : null;

      final allMessages = [...chatState.messages];
      if (activeStreamingMessage != null) {
        allMessages.add(activeStreamingMessage);
      }

      return Column(
        children: [
          // Message List
          Expanded(
            child: allMessages.isEmpty && !isBusy
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined, size: 64, color: theme.colorScheme.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          '开启新的对话',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '输入消息，或使用 @search 进行手动搜索',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: allMessages.length + (isBusy ? 1 : 0),
                    padding: const EdgeInsets.only(bottom: 16),
                    itemBuilder: (context, index) {
                      if (index == allMessages.length) {
                        final statusText = agentState.isFetchingUrl
                            ? '正在读取网页: ${agentState.fetchingUrl}...'
                            : '正在搜索: "${agentState.searchQuery}"...';
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Card(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      statusText,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      
                      final message = allMessages[index];
                      final isLastAssistant = message.role == 'assistant' &&
                          index == allMessages.length - 1;
                      final isLastUser = message.role == 'user' &&
                          index == allMessages.length - 1;
                      return ChatBubble(
                        key: ValueKey(message.id),
                        message: message,
                        isStreaming: chatState.isGenerating && message.id == 'streaming_msg',
                        onEdit: message.role == 'user'
                            ? () => _showEditDialog(context, message)
                            : null,
                        onRegenerate: (!chatState.isGenerating &&
                                ((message.role == 'assistant' && isLastAssistant) ||
                                 (message.role == 'user' && isLastUser)))
                            ? () => ref.read(chatProvider.notifier).regenerateLastResponse()
                            : null,
                        onRollbackToHere: (!chatState.isGenerating &&
                                message.role != 'tool')
                            ? () => _confirmRollback(context, message)
                            : null,
                      );
                    },
                  ),
          ),

          // Regenerate button when the last message is a user message
          if (!chatState.isGenerating &&
              allMessages.isNotEmpty &&
              allMessages.last.role == 'user')
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: ElevatedButton.icon(
                onPressed: () => ref.read(chatProvider.notifier).regenerateLastResponse(),
                icon: const Icon(Icons.refresh),
                label: const Text('重新生成回答'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),

          // Stop generating indicator overlay
          if (chatState.isGenerating)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: ElevatedButton.icon(
                onPressed: () => ref.read(chatProvider.notifier).cancelActiveStream(),
                icon: const Icon(Icons.stop),
                label: const Text('停止生成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),

          // Chat Input panel
          ChatInput(
            onSend: (text, imagePath) {
              ref.read(chatProvider.notifier).sendMessage(text, imagePath: imagePath);
            },
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: isLargeScreen ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (apiState.activeConfig != null)
              DropdownButton<String>(
                value: apiState.activeConfig!.id,
                isDense: true,
                underline: const SizedBox(),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                items: apiState.configs.map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(c.name),
                )).toList(),
                onChanged: (id) {
                  if (id != null) {
                    final config = apiState.configs.firstWhere((c) => c.id == id);
                    ref.read(apiConfigProvider.notifier).setActiveConfig(config);
                  }
                },
              ),
            const SizedBox(height: 2),
            InkWell(
              onTap: () => Navigator.pushNamed(context, '/model_selector'),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: isLargeScreen ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        modelState.selectedModel?.modelName ?? '选择模型...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_outlined),
            tooltip: '系统提示词',
            onPressed: () => _showSystemPromptEditor(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      drawer: isLargeScreen ? null : Drawer(child: buildDrawerContent()),
      body: isLargeScreen
          ? Row(
              children: [
                SizedBox(
                  width: 280,
                  child: buildDrawerContent(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: buildChatArea()),
              ],
            )
          : buildChatArea(),
    );
  }

  void _showSystemPromptEditor(BuildContext context) {
    final settings = ref.read(settingsProvider);
    final activeConv = ref.read(conversationProvider).activeConversation;

    // Initial value: conversation-level > default
    final initialText = (activeConv?.systemPrompt?.trim().isNotEmpty == true)
        ? activeConv!.systemPrompt!
        : settings.defaultSystemPrompt;

    final controller = TextEditingController(text: initialText);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_outlined, color: Theme.of(sheetContext).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '系统提示词',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '系统提示词用于设定 AI 助⼿的⾏为和⻛格，会随每条消息发送给 API。',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 8,
                minLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '输入系统提示词…',
                ),
              ),
              const SizedBox(height: 16),
              // Template selection
              Consumer(
                builder: (context, watchRef, _) {
                  final templates = watchRef.watch(systemPromptsProvider);
                  if (templates.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '从模板选择',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: templates.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final t = templates[i];
                            return ActionChip(
                              label: Text(t.title),
                              onPressed: () {
                                controller.text = t.content;
                                controller.selection = TextSelection.fromPosition(
                                  TextPosition(offset: controller.text.length),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () {
                      controller.text = settings.defaultSystemPrompt;
                      controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: controller.text.length),
                      );
                    },
                    child: const Text('使用默认'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final text = controller.text.trim();
                        if (activeConv != null) {
                          await ref.read(conversationProvider.notifier).updateConversation(
                            activeConv.copyWith(
                              systemPrompt: text.isEmpty ? null : text,
                            ),
                          );
                        } else {
                          await ref.read(settingsProvider.notifier).updateDefaultSystemPrompt(
                            text.isEmpty ? 'You are a helpful assistant.' : text,
                          );
                        }
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ).then((_) => controller.dispose());
  }

  void _showEditDialog(BuildContext context, ChatMessage message) async {
    final controller = TextEditingController(text: message.content);
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '修改您的消息...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(context, text);
              }
            },
            child: const Text('保存并重新发送'),
          ),
        ],
      ),
    );
    // Wait for the dialog transition to complete fully (300ms)
    await Future.delayed(const Duration(milliseconds: 300));
    controller.dispose();

    if (newText == null || newText.isEmpty) {
      return;
    }
    if (!context.mounted) return;
    await ref.read(chatProvider.notifier).editAndResendMessage(message.id, newText);
  }

  Future<void> _confirmRollback(BuildContext context, ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('回退确认'),
        content: const Text('将删除此消息之后的所有消息，确认回退到此位置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('确认回退'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Ensure dialog close animation completes before modifying state
      await Future.delayed(const Duration(milliseconds: 300));
      if (!context.mounted) return;
      ref.read(chatProvider.notifier).rollbackToMessage(message.id);
    }
  }

  Widget _buildConversationTile(Conversation c) {
    final active = ref.watch(conversationProvider).activeConversation;
    final isSelected = active?.id == c.id;
    final theme = Theme.of(context);

    return Dismissible(
      key: Key(c.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20.0),
        child: const Icon(Icons.push_pin, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await ref.read(conversationProvider.notifier).togglePin(c.id);
          return false;
        } else {
          await ref.read(conversationProvider.notifier).deleteConversation(c.id);
          return true;
        }
      },
      child: ListTile(
        title: Text(
          c.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        leading: Icon(
          c.isPinned ? Icons.push_pin : Icons.chat_bubble_outline,
          color: isSelected ? theme.colorScheme.primary : null,
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (value) async {
            if (value == 'pin') {
              await ref.read(conversationProvider.notifier).togglePin(c.id);
            } else if (value == 'archive') {
              await ref.read(conversationProvider.notifier).toggleArchive(c.id);
            } else if (value == 'delete') {
              await ref.read(conversationProvider.notifier).deleteConversation(c.id);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'pin',
              child: Text(c.isPinned ? '取消置顶' : '置顶'),
            ),
            PopupMenuItem(
              value: 'archive',
              child: Text(c.isArchived ? '取消归档' : '归档'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('删除'),
            ),
          ],
        ),
        onTap: () {
          ref.read(conversationProvider.notifier).setActiveConversation(c);
          if (MediaQuery.of(context).size.width <= 800) {
            Navigator.pop(context);
          }
        },
      ),
    );
  }
}
