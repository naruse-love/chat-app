import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/search_service.dart';

class AgentState {
  final bool isSearching;
  final String searchQuery;
  final List<SearchResult> searchResults;
  final bool isFetchingUrl;
  final String fetchingUrl;

  AgentState({
    this.isSearching = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.isFetchingUrl = false,
    this.fetchingUrl = '',
  });

  AgentState copyWith({
    bool? isSearching,
    String? searchQuery,
    List<SearchResult>? searchResults,
    bool? isFetchingUrl,
    String? fetchingUrl,
  }) {
    return AgentState(
      isSearching: isSearching ?? this.isSearching,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      isFetchingUrl: isFetchingUrl ?? this.isFetchingUrl,
      fetchingUrl: fetchingUrl ?? this.fetchingUrl,
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
    );
  }

  void completeUrlFetch() {
    state = state.copyWith(
      isFetchingUrl: false,
      fetchingUrl: '',
    );
  }

  void reset() {
    state = AgentState();
  }
}

final agentProvider = StateNotifierProvider<AgentNotifier, AgentState>((ref) {
  return AgentNotifier();
});
