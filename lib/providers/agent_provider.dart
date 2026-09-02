import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/search_service.dart';
import '../models/tool/tool_confirmation.dart';
import '../models/agent_step_telemetry.dart';

class AgentState {
  final bool isSearching;
  final String searchQuery;
  final List<SearchResult> searchResults;
  final bool isFetchingUrl;
  final String fetchingUrl;
  final ToolConfirmationRequest? pendingConfirmationRequest;
  final List<AgentStepTelemetry> stepTelemetries;
  final TokenBudgetTelemetry? latestTokenBudget;
  final String? circuitBreakerReason;

  bool get isWaitingConfirmation => pendingConfirmationRequest != null;

  AgentState({
    this.isSearching = false,
    this.searchQuery = '',
    this.searchResults = const [],
    this.isFetchingUrl = false,
    this.fetchingUrl = '',
    this.pendingConfirmationRequest,
    this.stepTelemetries = const [],
    this.latestTokenBudget,
    this.circuitBreakerReason,
  });

  AgentState copyWith({
    bool? isSearching,
    String? searchQuery,
    List<SearchResult>? searchResults,
    bool? isFetchingUrl,
    String? fetchingUrl,
    ToolConfirmationRequest? pendingConfirmationRequest,
    bool clearPendingConfirmation = false,
    List<AgentStepTelemetry>? stepTelemetries,
    TokenBudgetTelemetry? latestTokenBudget,
    bool clearTokenBudget = false,
    String? circuitBreakerReason,
    bool clearCircuitBreaker = false,
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
      stepTelemetries: stepTelemetries ?? this.stepTelemetries,
      latestTokenBudget: clearTokenBudget ? null : (latestTokenBudget ?? this.latestTokenBudget),
      circuitBreakerReason: clearCircuitBreaker ? null : (circuitBreakerReason ?? this.circuitBreakerReason),
    );
  }
}

class AgentNotifier extends StateNotifier<AgentState> {
  AgentNotifier() : super(AgentState());

  void startSearch(String query) {
    state = state.copyWith(
      isSearching: true,
      searchQuery: query,
      searchResults: const [],
      isFetchingUrl: false,
      fetchingUrl: '',
      clearPendingConfirmation: true,
    );
  }

  void completeSearch(List<SearchResult> results) {
    state = state.copyWith(
      isSearching: false,
      searchResults: results,
    );
  }

  void startUrlFetch(String url) {
    state = state.copyWith(
      isSearching: false,
      searchQuery: '',
      searchResults: const [],
      isFetchingUrl: true,
      fetchingUrl: url,
      clearPendingConfirmation: true,
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

  void addStepTelemetry(AgentStepTelemetry telemetry) {
    state = state.copyWith(
      stepTelemetries: [...state.stepTelemetries, telemetry],
    );
  }

  void updateTokenBudget(TokenBudgetTelemetry telemetry) {
    state = state.copyWith(latestTokenBudget: telemetry);
  }

  void triggerCircuitBreaker(String reason) {
    state = state.copyWith(circuitBreakerReason: reason);
  }

  void clearTelemetry() {
    state = state.copyWith(
      stepTelemetries: const [],
      clearTokenBudget: true,
      clearCircuitBreaker: true,
    );
  }

  void clearTransientState() {
    state = state.copyWith(
      isSearching: false,
      searchQuery: '',
      searchResults: const [],
      isFetchingUrl: false,
      fetchingUrl: '',
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
