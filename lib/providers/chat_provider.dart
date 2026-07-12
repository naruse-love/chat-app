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

  ChatNotifier(this._messageDao, this._agentService, this._apiConfigDao, this._ref) : super(ChatState());

  void clearChat() {
    state = ChatState();
  }

  Future<void> loadMessages(String conversationId) async {
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
    final settings = _ref.read(settingsProvider);

    if (activeConfig == null || selectedModel == null) {
      state = state.copyWith(error: 'Missing API Config or selected Model.');
      return;
    }

    if (imagePath != null && !selectedModel.supportsVision) {
      state = state.copyWith(error: 'The selected model does not support image inputs.');
      return;
    }

    String targetConvId;
    if (activeConv == null) {
      final title = text.length > 20 ? '${text.substring(0, 20)}...' : text;
      final newConv = await _ref.read(conversationProvider.notifier).createConversation(
        title: title,
        apiConfigId: activeConfig.id,
        modelId: selectedModel.id,
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
        state = state.copyWith(error: 'Failed to process image: $e');
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

    final apiKey = await _apiConfigDao.getApiKey(activeConfig.apiKeyRef) ?? '';
    _cancelToken = CancelToken();

    final history = await _messageDao.getMessagesForConversation(targetConvId);

    try {
      final stream = _agentService.chatAndSearchStream(
        baseUrl: activeConfig.baseUrl,
        apiKey: apiKey,
        model: selectedModel.id,
        messages: history,
        searxngUrl: settings.searxngUrl.isNotEmpty ? settings.searxngUrl : null,
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
        }
      }

      if (state.streamContent.isNotEmpty || state.streamReasoning.isNotEmpty) {
        final assistantMessage = ChatMessage(
          id: const Uuid().v4(),
          conversationId: targetConvId,
          role: 'assistant',
          content: state.streamContent,
          reasoningContent: state.streamReasoning.isNotEmpty ? state.streamReasoning : null,
          timestamp: DateTime.now(),
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
            conversationId: targetConvId,
            role: 'assistant',
            content: '${state.streamContent}\n\n*[Generation stopped by user]*',
            reasoningContent: state.streamReasoning.isNotEmpty ? state.streamReasoning : null,
            timestamp: DateTime.now(),
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
        String errorMsg = 'Stream failed: $e';
        if (e is DioException) {
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError) {
            errorMsg = 'Connection failed. Please check your internet connection or endpoint URL.';
          } else if (e.type == DioExceptionType.badResponse) {
            final statusCode = e.response?.statusCode;
            if (statusCode == 401) {
              errorMsg = 'API authentication failed. Please check your API Key.';
            } else if (statusCode == 429) {
              errorMsg = 'Rate limit exceeded. Please wait a moment and try again.';
            } else if (statusCode == 404) {
              errorMsg = 'Endpoint not found. Please verify the URL path.';
            } else {
              errorMsg = 'Server returned error status: $statusCode';
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
      } else {
        notifier.clearChat();
      }
    },
  );
  
  return notifier;
});
