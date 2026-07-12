import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/search_service.dart';

class AgentState {
  final bool isSearching;
  final String searchQuery;
  final List<SearchResult> searchResults;

  AgentState({
    this.isSearching = false,
    this.searchQuery = '',
    this.searchResults = const [],
  });

  AgentState copyWith({
    bool? isSearching,
    String? searchQuery,
    List<SearchResult>? searchResults,
  }) {
    return AgentState(
      isSearching: isSearching ?? this.isSearching,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
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
    );
  }

  void completeSearch(List<SearchResult> results) {
    state = state.copyWith(
      isSearching: false,
      searchResults: results,
    );
  }

  void reset() {
    state = AgentState();
  }
}

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) {
  return AgentNotifier();
});
