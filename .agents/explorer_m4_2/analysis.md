# AgentService Design & Implementation Analysis

## Overview
This document provides a detailed design and implementation plan for the `AgentService` (`lib/services/agent_service.dart`) and its unit tests (`test/agent_service_test.dart`).

The design conforms to the requirements specified in `ORIGINAL_REQUEST.md`:
1. Define the web search tool (OpenAI function calling schema).
2. Coordinate chat completion streaming.
3. Execute dual-mode web search (using `SearchService` with SearXNG fallback).
4. Feed results back for the final streaming completion.
5. Support manual `@search` prefix trigger.
6. Integrate cancellation using `CancelToken`.
7. Define unit tests for validation.

---

## 1. Suggested Class Structure & API of `AgentService`
The service resides in `lib/services/agent_service.dart`. It depends on `ChatService` for LLM interaction and `SearchService` for web searches.

### Stream Update Structure
To stream back rich responses to the UI, the service will emit chunks of `AgentStreamUpdate`. This allows the UI to display reasoning steps, search state indicators, search results list, and the final answer separately.

```dart
enum AgentUpdateType {
  reasoning,     // Streamed thinking/reasoning process from the model
  content,       // Streamed final answer content from the model
  searching,     // Emitted when a search begins (contains the query)
  searchResults, // Emitted when search completes (contains the SearchResult list)
  error,         // Emitted on failure
}

class AgentStreamUpdate {
  final AgentUpdateType type;
  final String? content;
  final List<SearchResult>? searchResults;
  final String? error;

  AgentStreamUpdate({
    required this.type,
    this.content,
    this.searchResults,
    this.error,
  });

  @override
  String toString() => 'AgentStreamUpdate(type: $type, content: $content, error: $error)';
}
```

### Class Signature and Web Search Tool Schema
```dart
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import 'chat_service.dart';
import 'search_service.dart';

class AgentService {
  final ChatService _chatService;
  final SearchService _searchService;

  AgentService({
    ChatService? chatService,
    SearchService? searchService,
  })  : _chatService = chatService ?? ChatService(),
        _searchService = searchService ?? SearchService();

  /// OpenAI-compatible Tool Calling Schema for the Web Search Tool
  static const Map<String, dynamic> webSearchTool = {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': 'Perform a web search to retrieve up-to-date information on a topic.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The search query to look up on the web.',
          },
        },
        'required': ['query'],
      },
    },
  };

  /// Coordinates chat completion, tool calling, and search operations.
  Stream<AgentStreamUpdate> generateResponse({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> history,
    String? searxngUrl,
    CancelToken? cancelToken,
  }) async* {
    // Detailed coordination logic explained in Section 2 & 3
  }
}
```

---

## 2. Logic for Web Search Tool Calling Flow
When the model receives a request, it might decide to call the `web_search` tool. Because the response is streamed from `ChatService.chatCompletionsStream`, tool calls will be generated incrementally across multiple chunk deltas.

### Flow Execution Steps:
1. **Initial Completion Request**:
   Invoke `ChatService.chatCompletionsStream` with the chat history and `tools: [AgentService.webSearchTool]`.
2. **Stream Chunk Consumption**:
   Process incoming stream chunks:
   - **Reasoning**: Extract `delta['reasoning_content']` or `delta['reasoning']` and yield `AgentUpdateType.reasoning`.
   - **Content**: Extract `delta['content']` and yield `AgentUpdateType.content`.
   - **Tool Calls**: If `delta['tool_calls']` is present, accumulate arguments and metadata by index (since chunks only contain partial strings).
3. **Check for Tool Execution**:
   Once the first stream finishes, check if any tool calls were accumulated. If the model generated a `web_search` tool call:
   - Extract the query argument (parsing the accumulated JSON string).
   - Yield `AgentUpdateType.searching` (with the query) to let the UI display a searching indicator.
   - Run `SearchService.search(...)` to fetch web results. If 9Router fails, it falls back to SearXNG automatically.
   - Yield `AgentUpdateType.searchResults` with the results.
4. **Context Injection & Second Completion Request**:
   - Construct a `ChatMessage` of role `assistant` containing the tool calls (with generated ID and function name/arguments).
   - Construct a `ChatMessage` of role `tool` with the corresponding `tool_call_id` and the formatted search results string as content.
   - Append both messages to the chat history.
   - Call `ChatService.chatCompletionsStream` again on the updated history. **Crucially, do not pass the `tools` parameter to this second call to avoid recursion / infinite loops.**
   - Stream the final answer content and reasoning from this second call directly to the user.

### Code Sketch for Tool Call Accumulation:
```dart
final Map<int, String> toolCallIds = {};
final Map<int, String> toolCallNames = {};
final Map<int, StringBuffer> toolCallArguments = {};
bool hasToolCall = false;

await for (final chunk in firstStream) {
  final choices = chunk['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) continue;
  final delta = choices[0]['delta'] as Map<String, dynamic>?;
  if (delta == null) continue;

  // Stream reasoning & content deltas
  ...

  // Accumulate tool call deltas
  final rawToolCalls = delta['tool_calls'] as List<dynamic>?;
  if (rawToolCalls != null && rawToolCalls.isNotEmpty) {
    hasToolCall = true;
    for (final rawCall in rawToolCalls) {
      final map = rawCall as Map<String, dynamic>;
      final index = map['index'] as int? ?? 0;
      if (map.containsKey('id')) {
        toolCallIds[index] = map['id'] as String;
      }
      final function = map['function'] as Map<String, dynamic>?;
      if (function != null) {
        if (function.containsKey('name')) {
          toolCallNames[index] = function['name'] as String;
        }
        if (function.containsKey('arguments')) {
          toolCallArguments.putIfAbsent(index, () => StringBuffer())
              .write(function['arguments'] as String);
        }
      }
    }
  }
}
```

---

## 3. Logic for Processing `@search` Prefix Manual Triggers
If the user starts their message with the `@search` prefix, we bypass the first LLM pass and perform search directly before sending any request to the LLM.

### Flow Execution Steps:
1. **Detect Prefix**:
   Inspect the last message in `history`. If `lastMessage.role == 'user'` and `lastMessage.content.trim().startsWith('@search')`:
   - Strip the `@search` prefix and trim to obtain the search query. E.g., `@search Flutter 3.22` becomes `Flutter 3.22`.
   - If the query is empty, yield an error and terminate.
2. **Execute Immediate Search**:
   - Yield `AgentStreamUpdate(type: AgentUpdateType.searching, content: query)`.
   - Perform search using `SearchService.search`.
   - Yield `AgentStreamUpdate(type: AgentUpdateType.searchResults, searchResults: results)`.
3. **Simulate Tool Call Flow**:
   To keep message schemas clean and uniform for the model:
   - Replace the user's original message in the history list with a cleaned user message (role `user`, content set to the search query without prefix).
   - Generate a simulated tool call ID (e.g. `call_manual_<timestamp>`).
   - Append a simulated assistant tool call message:
     `ChatMessage(role: 'assistant', content: '', toolCalls: [ToolCall(...)])`
   - Append a simulated tool response message:
     `ChatMessage(role: 'tool', toolCallId: toolCallId, content: formattedSearchResults)`
4. **Streaming Response**:
   - Request completion stream from `ChatService` using the updated history list (without `tools` parameter).
   - Stream reasoning and content chunks to the user.

---

## 4. Plan for Handling CancelToken / Stream Cancellation
1. **Propagation to Dio**:
   Pass the `CancelToken? cancelToken` parameter to all invocations of `ChatService.chatCompletionsStream`. If the token is cancelled, Dio will abort the network stream and throw a `DioException` of type `DioExceptionType.cancel`.
2. **Polled Liveness Checks**:
   Since network search or parsing might occur in between stream calls, perform manual checks for liveness throughout the flow:
   ```dart
   if (cancelToken != null && cancelToken.isCancelled) {
     throw DioException(
       requestOptions: RequestOptions(path: ''),
       type: DioExceptionType.cancel,
       error: 'User cancelled request',
     );
   }
   ```
   Check this condition:
   - Before starting search.
   - After completing search, before constructing tool messages.
   - At the beginning of each iteration in `await for` stream consumer loops.
3. **Graceful Stream Abort**:
   When a cancellation exception is caught or detected, yield an error update or let the stream throw the exception, ensuring the stream terminates cleanly without yielding further content.

---

## 5. Plan for Tests (`test/agent_service_test.dart`)
We will create unit tests using manually constructed mock classes. This avoids dependency on third-party mock generators.

### Lightweight Mock Classes Design
```dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:chat/services/chat_service.dart';
import 'package:chat/services/search_service.dart';
import 'package:chat/models/chat_message.dart';

class MockChatService extends ChatService {
  Stream<Map<String, dynamic>> Function({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    List<Map<String, dynamic>>? tools,
    CancelToken? cancelToken,
  })? chatCompletionsStreamHandler;

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
  Future<List<SearchResult>> Function({
    required String query,
    required String baseUrl,
    required String apiKey,
    String? searxngUrl,
  })? searchHandler;

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
}
```

### Proposed Test Cases:

1. **Normal Chat Completion (No Tool Calls)**
   - **Mock setup**: `chatCompletionsStreamHandler` yields standard text content chunks (`{'choices': [{'delta': {'content': 'Hello world'}}]}`).
   - **Assertion**: Verify that the generated stream yields `AgentUpdateType.content` with `'Hello world'`, and `SearchService` is never called.

2. **Web Search Tool Call Flow**
   - **Mock setup**:
     - First invocation of `chatCompletionsStreamHandler` yields chunks containing `tool_calls` delta representing a call to `web_search` with arguments `{"query": "flutter release"}`.
     - `searchHandler` returns mock search results.
     - Second invocation of `chatCompletionsStreamHandler` verifies that `messages` history now contains the assistant message with the tool call, and the tool response message with search results content. Yields the final completion text.
   - **Assertion**: Verify `AgentService` yields `searching`, `searchResults`, and final `content` updates.

3. **Manual Trigger `@search` Flow**
   - **Input history**: Last message contains `@search flutter release`.
   - **Mock setup**:
     - `searchHandler` is called with query `'flutter release'`, returning mock results.
     - `chatCompletionsStreamHandler` is invoked once. Assert that the history passed to it has the cleaned user query (`flutter release`), the assistant tool call, and the tool response message with formatted results. Yields final completion text.
   - **Assertion**: Verify search was executed immediately, and final response was streamed.

4. **Stream Cancellation**
   - **Mock setup**: Standard streaming handler that yields one chunk, then awaits a short delay.
   - **Execution**: Pass a `CancelToken`. Cancel it after the first chunk is received.
   - **Assertion**: Verify the stream throws a cancellation error and stops yielding chunks.
