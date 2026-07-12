import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../data/conversation_dao.dart';
import 'api_config_provider.dart'; // To reuse dbHelperProvider

final conversationDaoProvider = Provider<ConversationDao>((ref) {
  final dbHelper = ref.watch(dbHelperProvider);
  return ConversationDao(dbHelper);
});

class ConversationState {
  final List<Conversation> conversations;
  final Conversation? activeConversation;
  final bool isLoading;
  final String? error;

  ConversationState({
    this.conversations = const [],
    this.activeConversation,
    this.isLoading = false,
    this.error,
  });

  ConversationState copyWith({
    List<Conversation>? conversations,
    Conversation? activeConversation,
    bool? isLoading,
    String? error,
  }) {
    return ConversationState(
      conversations: conversations ?? this.conversations,
      activeConversation: activeConversation ?? this.activeConversation,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ConversationNotifier extends StateNotifier<ConversationState> {
  final ConversationDao _conversationDao;

  ConversationNotifier(this._conversationDao) : super(ConversationState()) {
    loadConversations();
  }

  Future<void> loadConversations() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _conversationDao.getAll();
      state = state.copyWith(conversations: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<Conversation> createConversation({
    required String title,
    required String apiConfigId,
    required String modelId,
    String? systemPrompt,
  }) async {
    final newConv = Conversation(
      id: const Uuid().v4(),
      title: title,
      apiConfigId: apiConfigId,
      modelId: modelId,
      systemPrompt: systemPrompt,
      isPinned: false,
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _conversationDao.insert(newConv);
    await loadConversations();
    state = state.copyWith(activeConversation: newConv);
    return newConv;
  }

  Future<void> updateConversation(Conversation conversation) async {
    try {
      await _conversationDao.update(conversation);
      final active = state.activeConversation?.id == conversation.id ? conversation : state.activeConversation;
      await loadConversations();
      state = state.copyWith(activeConversation: active);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> togglePin(String id) async {
    final index = state.conversations.indexWhere((c) => c.id == id);
    if (index != -1) {
      final conv = state.conversations[index];
      final updated = conv.copyWith(isPinned: !conv.isPinned, updatedAt: DateTime.now());
      await updateConversation(updated);
    }
  }

  Future<void> toggleArchive(String id) async {
    final index = state.conversations.indexWhere((c) => c.id == id);
    if (index != -1) {
      final conv = state.conversations[index];
      final updated = conv.copyWith(isArchived: !conv.isArchived, updatedAt: DateTime.now());
      await updateConversation(updated);
    }
  }

  Future<void> deleteConversation(String id) async {
    state = state.copyWith(isLoading: true);
    try {
      await _conversationDao.delete(id);
      final activeDeleted = state.activeConversation?.id == id;
      await loadConversations();
      if (activeDeleted) {
        state = state.copyWith(
          activeConversation: state.conversations.isNotEmpty ? state.conversations.first : null,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setActiveConversation(Conversation? conversation) {
    state = state.copyWith(activeConversation: conversation);
  }
}

final conversationProvider = StateNotifierProvider<ConversationNotifier, ConversationState>((ref) {
  final dao = ref.watch(conversationDaoProvider);
  return ConversationNotifier(dao);
});
