# AgentService Design & Analysis Report

This document details the architectural design, API definitions, coordination logic, and testing plan for the `AgentService` class (`lib/services/agent_service.dart`) and its unit tests (`test/agent_service_test.dart`).

---

## 1. Class Structure & API of `AgentService`

`AgentService` acts as the coordinator (orchestrator) between `ChatService` (the LLM interface) and `SearchService` (the search crawler). It defines the tools available to the model, intercepts tool calls when streaming, executes the search, and feeds the results back into a secondary stream.

### Dependencies
- **`ChatService`**: For communicating with the 9Router API.
- **`SearchService`**: For executing dual-mode searches (9Router Search with SearXNG fallback).

### Proposed API Signature

```dart
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import '../models/search_result.dart'; // Assuming SearchResult is imported from SearchService or its own file
import 'chat_service.dart';
import 'search_service.dart';

/// Event yielded by [AgentService] to notify the caller (UI/Provider) of progress.
class AgentStreamChunk {
  /// Streaming text token for the final response.
  final String? content;

  /// Streaming reasoning/thought token for deep-reasoning models (e.g., DeepSeek-R1).
  final String? reasoningContent;

  /// The query being searched, if a search tool call is active.
  final String? toolCallQuery;

  /// The list of search results when the search completes.
  final List<SearchResult>? searchResults;

  /// Indicates if the agent is actively executing a web search.
  final bool isSearching;

  AgentStreamChunk({
    this.content,
    this.reasoningContent,
    this.toolCallQuery,
    this.searchResults,
    this.isSearching = false,
  });
}

class AgentService {
  final ChatService _chatService;
  final SearchService _searchService;

  AgentService({
    ChatService? chatService,
    SearchService? searchService,
  })  : _chatService = chatService ?? ChatService(),
        _searchService = searchService ?? SearchService();

  /// OpenAI-compatible Tool Schema for Web Search
  static const List<Map<String, dynamic>> agentTools = [
    {
      'type': 'function',
      'function': {
        'name': 'web_search',
        'description': 'Search the web for information using a query. Use this tool when the user asks questions about current events, real-time facts, or when up-to-date information is needed.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'The search query to perform (e.g. "latest tech news July 2026").',
            },
          },
          'required': ['query'],
        },
      },
    }
  ];

  /// Runs the chat stream coordination loop.
  /// Handles manual `@search` prefix queries and automatic web_search tool calling.
  Stream<AgentStreamChunk> chatAndSearchStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    String? searxngUrl,
    CancelToken? cancelToken,
  }) async* {
    // Implementation detailed below...
  }

  /// Helper to check if the last user message manually triggers search.
  bool isManualSearchTrigger(List<ChatMessage> messages) {
    if (messages.isEmpty) return false;
    final lastMessage = messages.last;
    return lastMessage.role == 'user' && lastMessage.content.trim().startsWith('@search');
  }
}
```

---

## 2. Web Search Tool Calling Coordination Flow

When the model is invoked with the `web_search` tool defined, it might decide to output a tool call. Because we are streaming (`stream: true`), the tool calls are delivered as a series of partial JSON chunks inside `choices[0].delta.tool_calls`.

The flow coordinates `ChatService` and `SearchService` as follows:

```
[User Message] ──> [ChatService Stream (with Tools)]
                         │
                         ├─► No Tool Call ──► Yield tokens ──► Done
                         │
                         └─► Tool Call Detected ("web_search")
                                 │
                                 ├─► Accumulate stream chunks to parse query
                                 ├─► Yield search status (isSearching: true)
                                 ├─► Call SearchService.search() (9Router -> SearXNG fallback)
                                 ├─► Yield search results (isSearching: false)
                                 │
                                 ├─► Format search results
                                 ├─► Append [assistant tool_calls] & [tool response] to messages
                                 │
                                 └─► [ChatService Stream (final)] ──► Yield final tokens
```

### Stream Accumulator Logic

Since a tool call is split across multiple streaming events, `AgentService` must reconstruct it:

```dart
final Map<int, Map<String, dynamic>> accumulatedToolCalls = {};

await for (final chunk in firstStream) {
  final choices = chunk['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) continue;
  
  final delta = choices[0]['delta'] as Map<String, dynamic>?;
  if (delta == null) continue;

  // Stream text/reasoning tokens directly to UI
  final content = delta['content'] as String?;
  if (content != null && content.isNotEmpty) {
    yield AgentStreamChunk(content: content);
  }
  final reasoning = delta['reasoning_content'] as String?;
  if (reasoning != null && reasoning.isNotEmpty) {
    yield AgentStreamChunk(reasoningContent: reasoning);
  }

  // Parse tool calls
  final toolCalls = delta['tool_calls'] as List<dynamic>?;
  if (toolCalls != null) {
    for (final tc in toolCalls) {
      final index = tc['index'] as int? ?? 0;
      if (!accumulatedToolCalls.containsKey(index)) {
        accumulatedToolCalls[index] = {
          'id': tc['id'] ?? '',
          'type': tc['type'] ?? 'function',
          'function': {
            'name': tc['function']?['name'] ?? '',
            'arguments': tc['function']?['arguments'] ?? '',
          }
        };
      } else {
        final existing = accumulatedToolCalls[index]!;
        if (tc['id'] != null) existing['id'] = tc['id'];
        if (tc['type'] != null) existing['type'] = tc['type'];
        final func = tc['function'] as Map<String, dynamic>?;
        if (func != null) {
          final existingFunc = existing['function'] as Map<String, dynamic>;
          if (func['name'] != null) existingFunc['name'] = func['name'];
          if (func['arguments'] != null) {
            existingFunc['arguments'] = (existingFunc['arguments'] as String) + (func['arguments'] as String);
          }
        }
      }
    }
  }
}
```

### Action Logic on Tool Call Completion

Once the first stream ends:
1. Check if `accumulatedToolCalls` has entries where `function['name'] == 'web_search'`.
2. Parse the arguments (e.g., `{"query": "..."}`) to extract the `query`.
3. Check `cancelToken` liveness.
4. Yield `AgentStreamChunk(toolCallQuery: query, isSearching: true)`.
5. Call `_searchService.search(...)`.
6. Yield `AgentStreamChunk(toolCallQuery: query, searchResults: results, isSearching: false)`.
7. Construct:
   - **Assistant Message**: containing the `tool_calls` generated by the model.
   - **Tool Message**: containing the formatted search results with role `tool` and matching `toolCallId`.
8. Call `_chatService.chatCompletionsStream` again with the augmented messages list (without `tools` parameter to prevent loop recursion) and yield the final answer tokens.

---

## 3. Handling `@search` Prefix Manual Triggers

If a user starts their message with the `@search` prefix, we bypass the initial LLM call entirely. This saves token cost and reduces latency.

### Execution Logic

1. **Detect**: `isManualSearchTrigger(messages)` checks if the last message is from the user and starts with `@search`.
2. **Extract Query**: `final searchQuery = lastMessage.content.replaceFirst(RegExp(r'^@search\s*'), '').trim();`.
3. **Execute Search First**:
   - Yield `AgentStreamChunk(toolCallQuery: searchQuery, isSearching: true)`.
   - Call `_searchService.search(...)`.
   - Yield `AgentStreamChunk(toolCallQuery: searchQuery, searchResults: results, isSearching: false)`.
4. **Context Injection**:
   - Format the search results into a markdown context block.
   - Combine the user's raw query and the search results:
     ```
     [searchQuery]
     
     Here are the web search results:
     1. Title: ...
        URL: ...
        Snippet: ...
     ```
   - Update the last user message in the messages list with this combined string: `final modifiedUserMessage = lastMessage.copyWith(content: '$searchQuery\n\n$formattedResults');`.
5. **LLM Invocation**:
   - Send the updated message list (with the injected context) to the LLM via `ChatService.chatCompletionsStream` (without tools parameter).
   - Stream the final tokens directly to the caller.

*Note: Since the context is directly embedded in the user's message, we do not need to deal with OpenAI `tool_call` schemas or mismatch errors.*

---

## 4. CancelToken & Stream Cancellation Plan

To support stopping generation mid-stream, we must respect the `CancelToken` passed from the UI.

### Cancellation Strategy

1. **Network Cancellation (Dio)**:
   - When the client triggers `cancelToken.cancel()`, Dio immediately cancels the active HTTP connections.
   - This triggers a `DioException` of type `DioExceptionType.cancel` inside the stream returned by `ChatService`.
   - The `await for` loop in `AgentService` will propagate this exception to its caller, which can then handle it and display the partially generated message.
2. **Intermediate Cancellation Checks**:
   - Since `SearchService` executes asynchronously between streams, we must verify if the user cancelled during this time.
   - Before starting search and before spawning the second LLM stream, we check:
     ```dart
     if (cancelToken != null && cancelToken.isCancelled) {
       throw DioException(
         requestOptions: RequestOptions(path: ''),
         type: DioExceptionType.cancel,
         error: 'Operation cancelled by user',
       );
     }
     ```
3. **Graceful UI Handling**:
   - In the Riverpod provider / UI Controller, catch the cancellation `DioException` type to mark the response as "stopped" rather than showing an error screen.

---

## 5. Testing Plan for `test/agent_service_test.dart`

To ensure comprehensive, reliable tests without relying on external network calls or fragile mock generation, we will write explicit sub-classes of `ChatService` and `SearchService` to stub behavior.

### Stubs Setup

```dart
class MockChatService extends ChatService {
  final Stream<Map<String, dynamic>> Function({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  })? chatCompletionsStreamHandler;

  MockChatService({this.chatCompletionsStreamHandler});

  @override
  Stream<Map<String, dynamic>> chatCompletionsStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  }) {
    if (chatCompletionsStreamHandler != null) {
      return chatCompletionsStreamHandler!(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        messages: messages,
        tools: tools,
        cancelToken: cancelToken,
      );
    }
    return const Stream.empty();
  }
}

class MockSearchService extends SearchService {
  final Future<List<SearchResult>> Function({
    required String query,
    required String baseUrl,
    required String apiKey,
    String? searxngUrl,
  })? searchHandler;

  MockSearchService({this.searchHandler});

  @override
  Future<List<SearchResult>> search({
    required String query,
    required String baseUrl,
    required String apiKey,
    String? searxngUrl,
  }) {
    if (searchHandler != null) {
      return searchHandler!(
        query: query,
        baseUrl: baseUrl,
        apiKey: apiKey,
        searxngUrl: searxngUrl,
      );
    }
    return Future.value([]);
  }

  @override
  String formatSearchResultsForContext(List<SearchResult> results) {
    return results.map((r) => '${r.title} - ${r.url}: ${r.content}').join('\n');
  }
}
```

### Detailed Test Cases

1. **Test 1: Simple Chat Flow (No Search)**
   - **Scenario**: LLM streams normal text content without requesting tools.
   - **Expectation**: `AgentService` yields corresponding `AgentStreamChunk` events containing the text. `SearchService` is never called.
   
2. **Test 2: LLM Tool Call Redirection Flow**
   - **Scenario**: 
     - First `ChatService` call streams a tool call delta with function name `web_search` and query `"flutter testing"`.
     - `SearchService` is called with query `"flutter testing"` and returns mock results.
     - Second `ChatService` call streams the final text response.
   - **Expectation**:
     - `AgentService` yields `isSearching: true` event followed by search results.
     - Final text content is yielded.
     - `ChatService` is verified to have been called twice, and the second call includes the `assistant` message with the tool call and the `tool` message containing the search results.

3. **Test 3: Manual `@search` Prefix Trigger Flow**
   - **Scenario**: User sends message `@search latest flutter release`.
   - **Expectation**:
     - `AgentService` intercepts the user message, extracts the query `"latest flutter release"`.
     - `SearchService.search()` is executed immediately.
     - `ChatService` is called exactly once with the modified user message (context injected).
     - The output stream yields the search status and then the final response text.

4. **Test 4: Stream Cancellation (Dio cancel during first stream)**
   - **Scenario**: Stream starts and then the `CancelToken` is cancelled.
   - **Expectation**: Stream aborts, throwing a `DioException` of type `DioExceptionType.cancel`.

5. **Test 5: Cancellation between asynchronous steps**
   - **Scenario**: First stream finishes, tool call is parsed, but `cancelToken.cancel()` is invoked before search starts.
   - **Expectation**: `AgentService` detects the cancelled token, skips the search call, and throws a `DioException` of type `cancel`.
