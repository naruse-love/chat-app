import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation.dart';
import '../providers/api_config_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/model_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/agent_provider.dart';
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
                      'AI Agent Chat',
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
                label: const Text('New Chat'),
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
                      child: Text('Pinned', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    ...pinnedConvs.map((c) => _buildConversationTile(c)),
                    const Divider(),
                  ],
                  if (recentConvs.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text('Recent', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                    ...recentConvs.map((c) => _buildConversationTile(c)),
                    const Divider(),
                  ],
                  // Archived Collapsible
                  ListTile(
                    title: Text(
                      'Archived Chats (${archivedConvs.length})',
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
            child: allMessages.isEmpty && !agentState.isSearching
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined, size: 64, color: theme.colorScheme.outlineVariant),
                        const SizedBox(height: 16),
                        Text(
                          'Start a new conversation',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Type a message or use @search for manual search',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: allMessages.length + (agentState.isSearching ? 1 : 0),
                    padding: const EdgeInsets.only(bottom: 16),
                    itemBuilder: (context, index) {
                      if (index == allMessages.length) {
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
                                      'Searching: "${agentState.searchQuery}"...',
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
                      return ChatBubble(
                        message: message,
                        isStreaming: chatState.isGenerating && message.id == 'streaming_msg',
                      );
                    },
                  ),
          ),

          // Stop generating indicator overlay
          if (chatState.isGenerating)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: ElevatedButton.icon(
                onPressed: () => ref.read(chatProvider.notifier).cancelActiveStream(),
                icon: const Icon(Icons.stop),
                label: const Text('Stop Generating'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),

          // Chat Input panel
          ChatInput(
            supportsVision: modelState.selectedModel?.supportsVision ?? true,
            onSend: (text, imagePath) {
              ref.read(chatProvider.notifier).sendMessage(text, imagePath: imagePath);
            },
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/model_selector'),
          child: Column(
            crossAxisAlignment: isLargeScreen ? CrossAxisAlignment.center : CrossAxisAlignment.start,
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
              Text(
                modelState.selectedModel?.modelName ?? 'Select Model...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        actions: [
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
              child: Text(c.isPinned ? 'Unpin' : 'Pin'),
            ),
            PopupMenuItem(
              value: 'archive',
              child: Text(c.isArchived ? 'Unarchive' : 'Archive'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
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
