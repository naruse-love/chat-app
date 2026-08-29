import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/search_service.dart';
import '../models/tool/tool_confirmation.dart';

class AgentState {
  final bool isSearching;
  final String searchQuery;
  final List<SearchResult> searchResults;
  final bool isFetchingUrl;
  final String fetchingUrl;
  final ToolConfirmationRequest? pendingConfirmationRequest;

  bool get isWaitingConfirmation => pendingConfirmationRequest != null;

  AgentState({
    this.isSearching = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.isFetchingUrl = false,
    this.fetchingUrl = '',
    this.pendingConfirmationRequest,
  });

  AgentState copyWith({
    bool? isSearching,
    String? searchQuery,
    List<SearchResult>? searchResults,
    bool? isFetchingUrl,
    String? fetchingUrl,
    ToolConfirmationRequest? pendingConfirmationRequest,
    bool clearPendingConfirmation = false,
  }) {
    return AgentState(
      isSearching: isSearching ?? this.isSearching,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      isFetchingUrl: isFetchingUrl ?? this.isFetchingUrl,
      fetchingUrl: fetchingUrl ?? this.fetchingUrl,
      pendingConfirmationRequest: clearPendingConfirmation
          ? null
          : (pendingConfirmationRequest ?? this.pendingConfirmationRequest),
    );
  }
}

class AgentNotifier extends StateNotifier<AgentState> {
  AgentNotifier() : super(AgentState());

  void startSearch(String query) {
    state = AgentState(
      isSearching: true,
      searchQuery: query,
      searchResults: const [],
      isFetchingUrl: false,
      fetchingUrl: '',
      pendingConfirmationRequest: null,
    );
  }

  void completeSearch(List<SearchResult> results) {
    state = state.copyWith(
      isSearching: false,
      searchResults: results,
    );
  }

  void startUrlFetch(String url) {
    state = AgentState(
      isSearching: false,
      searchQuery: '',
      searchResults: const [],
      isFetchingUrl: true,
      fetchingUrl: url,
      pendingConfirmationRequest: null,
    );
  }

  void completeUrlFetch() {
    state = state.copyWith(
      isFetchingUrl: false,
      fetchingUrl: '',
    );
  }

  void setPendingConfirmation(ToolConfirmationRequest request) {
    state = state.copyWith(
      pendingConfirmationRequest: request,
    );
  }

  void clearPendingConfirmation() {
    state = state.copyWith(
      clearPendingConfirmation: true,
    );
  }

  void reset() {
    state = AgentState();
  }
}

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) {
  return AgentNotifier();
});
