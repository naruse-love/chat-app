import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../data/message_dao.dart';
import '../data/api_config_dao.dart';
import '../services/agent_service.dart';
import '../services/search_service.dart';
import 'api_config_provider.dart';
import 'conversation_provider.dart';
import 'model_provider.dart';
import 'settings_provider.dart';
import '../services/image_service.dart';
import 'agent_provider.dart';

final imageServiceProvider = Provider<ImageService>((ref) => ImageService());

final messageDaoProvider = Provider<MessageDao>((ref) {
  final dbHelper = ref.watch(dbHelperProvider);
  return MessageDao(dbHelper);
});

final searchServiceProvider = Provider<SearchService>((ref) => SearchService());

final agentServiceProvider = Provider<AgentService>((ref) {
  final chatSvc = ref.watch(chatServiceProvider);
  final searchSvc = ref.watch(searchServiceProvider);
  return AgentService(chatService: chatSvc, searchService: searchSvc);
});

class ChatState {
  final List<ChatMessage> messages;
  final bool isGenerating;
  final String streamReasoning;
  final String streamContent;
  final String? error;

  ChatState({
    this.messages = const [],
    this.isGenerating = false,
    this.streamReasoning = '',
    this.streamContent = '',
    this.error,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isGenerating,
    String? streamReasoning,
    String? streamContent,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
      streamReasoning: streamReasoning ?? this.streamReasoning,
      streamContent: streamContent ?? this.streamContent,
      error: error,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final MessageDao _messageDao;
  final AgentService _agentService;
  final ApiConfigDao _apiConfigDao;
  final Ref _ref;
  
  CancelToken? _cancelToken;
  bool _sendingInProgress = false;

  ChatNotifier(this._messageDao, this._agentService, this._apiConfigDao, this._ref) : super(ChatState());

  void clearChat() {
    state = ChatState();
  }

  Future<void> loadMessages(String conversationId) async {
    // Do not reload messages while a send is in progress to avoid
    // overwriting the newly added user message.
    if (_sendingInProgress) return;
    state = state.copyWith(isGenerating: false, error: null);
    try {
      final messages = await _messageDao.getMessagesForConversation(conversationId);
      if (mounted) {
        state = ChatState(messages: messages);
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: 'Failed to load messages: $e');
      }
    }
  }

  Future<void> sendMessage(String text, {String? imagePath}) async {
    if (state.isGenerating) return;

    final activeConv = _ref.read(conversationProvider).activeConversation;
    final activeConfig = _ref.read(apiConfigProvider).activeConfig;
    final selectedModel = _ref.read(modelProvider).selectedModel;

    if (activeConfig == null || selectedModel == null) {
      state = state.copyWith(error: '缺少 API 配置或选定的模型。');
      return;
    }

    _sendingInProgress = true;
    String targetConvId;
    if (activeConv == null) {
      final settings = _ref.read(settingsProvider);
      final title = text.length > 20 ? '${text.substring(0, 20)}...' : text;
      final newConv = await _ref.read(conversationProvider.notifier).createConversation(
        title: title,
        apiConfigId: activeConfig.id,
        modelId: selectedModel.id,
        systemPrompt: settings.defaultSystemPrompt,
      );
      targetConvId = newConv.id;
    } else {
      targetConvId = activeConv.id;
    }

    final messageId = const Uuid().v4();
    String? finalImagePath;
    if (imagePath != null) {
      try {
        finalImagePath = await _ref.read(imageServiceProvider).compressAndSaveImage(
          sourcePath: imagePath,
          messageId: messageId,
        );
      } catch (e) {
        state = state.copyWith(error: '图片处理失败: $e');
        return;
      }
    }

    final userMessage = ChatMessage(
      id: messageId,
      conversationId: targetConvId,
      role: 'user',
      content: text,
      imagePath: finalImagePath,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isGenerating: true,
      streamContent: '',
      streamReasoning: '',
      error: null,
    );
    await _messageDao.insert(userMessage);

    if (activeConv != null) {
      _ref.read(conversationProvider.notifier).updateConversation(
        activeConv.copyWith(updatedAt: DateTime.now()),
      );
    }

    // Start streaming the API call
    await _startStreaming(targetConvId);
  }

  /// Edits a user message and resends the conversation from that point.
  Future<void> editAndResendMessage(String messageId, String newText) async {
    if (state.isGenerating) return;
    _sendingInProgress = true;

    try {
      // Update the message content in DB
      await _messageDao.updateContent(messageId, newText);

      // Yield once so the dialog exit animation and any pending
      // MarkdownBody/SelectableText element teardown can settle
      // before we mutate the messages list and rebuild.
      await Future.delayed(const Duration(milliseconds: 50));

      if (!mounted) return;

      // Update in local state
      final updatedMessages = state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(content: newText);
        }
        return m;
      }).toList();
      state = state.copyWith(messages: updatedMessages);

      // Delete all messages after the edited message
      final activeConv = _ref.read(conversationProvider).activeConversation;
      if (activeConv != null) {
        await _messageDao.deleteAfter(activeConv.id, messageId);
      }

      // Reload messages from DB to ensure consistency
      if (activeConv != null) {
        final freshMessages = await _messageDao.getMessagesForConversation(activeConv.id);
        if (!mounted) return;
        state = state.copyWith(messages: freshMessages);
      }

      // Start streaming from this point
      if (activeConv != null) {
        await _startStreaming(activeConv.id);
      }
    } finally {
      _sendingInProgress = false;
    }
  }

  /// Deletes the last AI response and resends the API call with the same context.
  Future<void> regenerateLastResponse() async {
    if (state.isGenerating) return;
    if (state.messages.isEmpty) return;

    final activeConv = _ref.read(conversationProvider).activeConversation;
    if (activeConv == null) return;

    // Find the last user message
    final lastUserMsgIndex = state.messages.lastIndexWhere((m) => m.role == 'user');
    if (lastUserMsgIndex < 0) return;

    final lastUserMsg = state.messages[lastUserMsgIndex];

    // Delete all messages after the last user message
    await _messageDao.deleteAfter(activeConv.id, lastUserMsg.id);

    // Reload fresh messages
    final freshMessages = await _messageDao.getMessagesForConversation(activeConv.id);
    state = state.copyWith(messages: freshMessages);

    // Start streaming
    await _startStreaming(activeConv.id);
  }

  /// Deletes all messages after the specified message (rollback).
  Future<void> rollbackToMessage(String messageId) async {
    if (state.isGenerating) return;

    final activeConv = _ref.read(conversationProvider).activeConversation;
    if (activeConv == null) return;

    await _messageDao.deleteAfter(activeConv.id, messageId);

    // Reload fresh messages
    final freshMessages = await _messageDao.getMessagesForConversation(activeConv.id);
    // Yield to let any pending widget teardown settle before mutating state
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    state = state.copyWith(messages: freshMessages, error: null);
  }

  /// Core streaming logic shared by sendMessage, editAndResend, regenerateLastResponse.
  Future<void> _startStreaming(String conversationId) async {
    final activeConfig = _ref.read(apiConfigProvider).activeConfig;
    final selectedModel = _ref.read(modelProvider).selectedModel;
    final settings = _ref.read(settingsProvider);
    final activeConv = _ref.read(conversationProvider).activeConversation;

    if (activeConfig == null || selectedModel == null) {
      state = state.copyWith(error: '缺少 API 配置或选定的模型。', isGenerating: false);
      return;
    }

    final apiKey = await _apiConfigDao.getApiKey(activeConfig.apiKeyRef) ?? '';
    _cancelToken = CancelToken();

    final history = await _messageDao.getMessagesForConversation(conversationId);

    // Determine system prompt: conversation-level takes precedence over default
    final systemPrompt = (activeConv?.systemPrompt?.trim().isNotEmpty == true)
        ? activeConv!.systemPrompt
        : settings.defaultSystemPrompt;

    state = state.copyWith(isGenerating: true, streamContent: '', streamReasoning: '', error: null);

    int? pendingPromptTokens;
    int? pendingCompletionTokens;

    try {
      final stream = _agentService.chatAndSearchStream(
        baseUrl: activeConfig.baseUrl,
        apiKey: apiKey,
        model: selectedModel.id,
        messages: history,
        systemPrompt: systemPrompt,
        searxngUrl: settings.searxngUrl.isNotEmpty ? settings.searxngUrl : null,
        searchBackend: settings.searchBackend,
        cancelToken: _cancelToken,
      );

      await for (final event in stream) {
        if (_cancelToken?.isCancelled ?? false) break;

        if (event is ReasoningDeltaEvent) {
          state = state.copyWith(streamReasoning: state.streamReasoning + event.reasoning);
        } else if (event is ContentDeltaEvent) {
          state = state.copyWith(streamContent: state.streamContent + event.content);
        } else if (event is ToolCallStartedEvent) {
          _ref.read(agentProvider.notifier).startSearch(event.query);
        } else if (event is ToolCallCompletedEvent) {
          _ref.read(agentProvider.notifier).completeSearch(event.results);
        } else if (event is ToolCallExecutedMessageEvent) {
          await _messageDao.insert(event.assistantMessage);
          for (final toolMsg in event.toolMessages) {
            await _messageDao.insert(toolMsg);
          }
          state = state.copyWith(
            messages: [...state.messages, event.assistantMessage, ...event.toolMessages],
            streamContent: '',
            streamReasoning: '',
          );
          _ref.read(agentProvider.notifier).reset();
        } else if (event is UsageEvent) {
          pendingPromptTokens = event.promptTokens;
          pendingCompletionTokens = event.completionTokens;
        }
      }

      if (state.streamContent.isNotEmpty || state.streamReasoning.isNotEmpty) {
        final assistantMessage = ChatMessage(
          id: const Uuid().v4(),
          conversationId: conversationId,
          role: 'assistant',
          content: state.streamContent,
          reasoningContent: state.streamReasoning.isNotEmpty ? state.streamReasoning : null,
          timestamp: DateTime.now(),
          promptTokens: pendingPromptTokens,
          completionTokens: pendingCompletionTokens,
        );
        await _messageDao.insert(assistantMessage);
        state = state.copyWith(
          messages: [...state.messages, assistantMessage],
          isGenerating: false,
          streamContent: '',
          streamReasoning: '',
        );
      } else {
        state = state.copyWith(isGenerating: false);
      }
    } catch (e) {
      if (_cancelToken?.isCancelled ?? false) {
        if (state.streamContent.isNotEmpty || state.streamReasoning.isNotEmpty) {
          final cancelledMsg = ChatMessage(
            id: const Uuid().v4(),
            conversationId: conversationId,
            role: 'assistant',
            content: '${state.streamContent}\n\n*[用户已停止生成]*',
            reasoningContent: state.streamReasoning.isNotEmpty ? state.streamReasoning : null,
            timestamp: DateTime.now(),
            promptTokens: pendingPromptTokens,
            completionTokens: pendingCompletionTokens,
          );
          await _messageDao.insert(cancelledMsg);
          state = state.copyWith(
            messages: [...state.messages, cancelledMsg],
            isGenerating: false,
            streamContent: '',
            streamReasoning: '',
          );
        } else {
          state = state.copyWith(isGenerating: false);
        }
      } else {
        String errorMsg = '流式传输失败: $e';
        if (e is DioException) {
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError) {
            errorMsg = '连接失败。请检查您的网络连接或端点 URL。';
          } else if (e.type == DioExceptionType.badResponse) {
            final statusCode = e.response?.statusCode;
            if (statusCode == 401) {
              errorMsg = 'API 身份验证失败。请检查您的 API 密钥。';
            } else if (statusCode == 429) {
              errorMsg = '请求频率超限。请稍后再试。';
            } else if (statusCode == 404) {
              errorMsg = '未找到端点。请核对 URL 路径。';
            } else {
              errorMsg = '服务器返回错误状态码: $statusCode';
            }
          }
        }
        state = state.copyWith(isGenerating: false, error: errorMsg);
      }
    } finally {
      _cancelToken = null;
      _ref.read(agentProvider.notifier).reset();
    }
  }

  void cancelGeneration() {
    _cancelToken?.cancel('User stopped execution');
  }

  void cancelActiveStream() {
    cancelGeneration();
  }

  Future<void> clearHistory() async {
    final activeConv = _ref.read(conversationProvider).activeConversation;
    if (activeConv != null) {
      await _messageDao.clearConversation(activeConv.id);
      state = ChatState();
    }
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final messageDao = ref.watch(messageDaoProvider);
  final agentSvc = ref.watch(agentServiceProvider);
  final apiConfigDao = ref.watch(apiConfigDaoProvider);
  
  final notifier = ChatNotifier(messageDao, agentSvc, apiConfigDao, ref);
  
  final activeConv = ref.read(conversationProvider).activeConversation;
  if (activeConv != null) {
    notifier.loadMessages(activeConv.id);
  }

  ref.listen<Conversation?>(
    conversationProvider.select((s) => s.activeConversation),
    (previous, next) {
      if (next != null) {
        notifier.loadMessages(next.id);
        // Restore the model used for this conversation
        final modelState = ref.read(modelProvider);
        final matchingModels = modelState.models.where((m) => m.id == next.modelId);
        if (matchingModels.isNotEmpty) {
          ref.read(modelProvider.notifier).selectModel(matchingModels.first);
        } else {
          // Model not found in list, try adding as custom model
          ref.read(modelProvider.notifier).addCustomModel(next.modelId);
        }
      } else {
        notifier.clearChat();
      }
    },
  );
  
  return notifier;
});
