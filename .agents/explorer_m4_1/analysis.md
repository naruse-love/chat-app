# AgentService Implementation Analysis & Design Report

This report presents the architectural design and implementation details for `AgentService` (`lib/services/agent_service.dart`) and its test suite (`test/agent_service_test.dart`) for Milestone 4 (Web Search & Agent Core).

---

## 1. Suggested Class Structure and API of `AgentService`

`AgentService` serves as the orchestration layer between the `ChatService` (LLM completions) and the `SearchService` (web search). It is stateless and acts as a stream controller/coordinator.

### Suggested Imports
```dart
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import '../services/chat_service.dart';
import '../services/search_service.dart';
```

### Stream Event Types (`AgentStreamEvent`)
To provide the UI (e.g., Riverpod providers and chat widgets) with granular visibility into the reasoning, searching, and final generation phases, we define a structured hierarchy of stream events:

```dart
/// Base class for all events yielded during agent execution.
abstract class AgentStreamEvent {
  const AgentStreamEvent();
}

/// Yielded when the model emits streaming reasoning text (e.g., DeepSeek-R1).
class ReasoningDeltaEvent extends AgentStreamEvent {
  final String reasoning;
  const ReasoningDeltaEvent(this.reasoning);
}

/// Yielded when the model emits standard streaming message content.
class ContentDeltaEvent extends AgentStreamEvent {
  final String content;
  const ContentDeltaEvent(this.content);
}

/// Yielded when a tool call has been detected and search starts executing.
class ToolCallStartedEvent extends AgentStreamEvent {
  final String query;
  const ToolCallStartedEvent(this.query);
}

/// Yielded when the search execution has finished and returned results.
class ToolCallCompletedEvent extends AgentStreamEvent {
  final String query;
  final List<SearchResult> results;
  const ToolCallCompletedEvent(this.query, this.results);
}

/// Yielded after search results are packaged into assistant/tool messages.
/// This allows the calling state-management layer (e.g., ChatProvider) 
/// to save intermediate messages to SQLite database and update UI bubbles.
class ToolCallExecutedMessageEvent extends AgentStreamEvent {
  final ChatMessage assistantMessage;
  final ChatMessage toolMessage;
  const ToolCallExecutedMessageEvent({
    required this.assistantMessage,
    required this.toolMessage,
  });
}
```

### Service Interface
```dart
class AgentService {
  final ChatService _chatService;
  final SearchService _searchService;
  final Uuid _uuid;

  AgentService({
    ChatService? chatService,
    SearchService? searchService,
  })  : _chatService = chatService ?? ChatService(),
        _searchService = searchService ?? SearchService(),
        _uuid = const Uuid();

  /// OpenAI-compatible Tool definition for web search.
  static const Map<String, dynamic> webSearchTool = {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': 'Search the web for up-to-date information on a given topic.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The query to search for on the web.',
          },
        },
        'required': ['query'],
      },
    },
  };

  /// Main entry point coordinating completion streaming, tool execution, and manual trigger.
  Stream<AgentStreamEvent> chatAndSearchStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    String? searxngUrl,
    CancelToken? cancelToken,
  }) async* {
    // Detailed coordination logic defined in Section 2 & 3
  }
}
```

---

## 2. Logic for Web Search Tool Calling Flow

When the model is invoked with the `web_search` tool enabled, it may choose to trigger a search. Because tool calling is streaming, we accumulate the tool call arguments before execution.

### Tool Call Accumulator Helper
```dart
class _ToolCallAccumulator {
  String id = '';
  String name = '';
  final StringBuffer argumentsBuffer = StringBuffer();
}
```

### Flow Coordination Sequence
1. **First LLM Stream Request**: 
   Invoke `_chatService.chatCompletionsStream` passing the list of messages and `tools: [webSearchTool]`.
2. **Streaming Delta Parsing**:
   Listen to the stream. For each chunk:
   - Yield `ContentDeltaEvent` or `ReasoningDeltaEvent` if present.
   - If `tool_calls` delta is present, accumulate it by its `index` in a `Map<int, _ToolCallAccumulator> accumulatedToolCalls`.
3. **Check for Tool Trigger**:
   Once the first stream terminates, check if `accumulatedToolCalls` is not empty.
   - If empty, complete the stream.
   - If not empty, process the first tool call (typically only one `web_search` tool call is expected).
4. **Extract Query and Search**:
   - Extract the query argument by parsing the accumulated JSON string:
     `{"query": "user query"}`.
   - Yield `ToolCallStartedEvent(query)`.
   - Perform the search using `_searchService.search` (handling 9Router with SearXNG fallback).
   - Yield `ToolCallCompletedEvent(query, results)`.
5. **Simulate Tool Response History**:
   - Format results into markdown: `final formattedResults = _searchService.formatSearchResultsForContext(results)`.
   - Build intermediate assistant message (representing the LLM deciding to call a tool):
     ```dart
     final assistantMessage = ChatMessage(
       id: _uuid.v4(),
       conversationId: messages.last.conversationId,
       role: 'assistant',
       content: '',
       toolCalls: accumulatedToolCalls.values.map((acc) => ToolCall(
         id: acc.id,
         type: 'function',
         functionName: acc.name,
         arguments: acc.argumentsBuffer.toString(),
       )).toList(),
       timestamp: DateTime.now(),
     );
     ```
   - Build the tool response message:
     ```dart
     final toolMessage = ChatMessage(
       id: _uuid.v4(),
       conversationId: messages.last.conversationId,
       role: 'tool',
       toolCallId: accumulatedToolCalls.values.first.id,
       content: formattedResults,
       timestamp: DateTime.now(),
     );
     ```
   - Yield `ToolCallExecutedMessageEvent(assistantMessage: ..., toolMessage: ...)`.
6. **Second LLM Stream Request**:
   - Form the updated list of messages: `[...messages, assistantMessage, toolMessage]`.
   - Request final stream: `_chatService.chatCompletionsStream` (no tools argument needed).
   - Stream final textual output to the user.

---

## 3. Logic for Processing `@search` Manual Trigger

The user can explicitly force a search by prefixing their message with `@search`. This is handled as follows:

1. **Trigger Detection**:
   Inspect the last message in `messages`:
   ```dart
   final lastMessage = messages.last;
   final isManualSearch = lastMessage.role == 'user' && 
                          lastMessage.content.trim().startsWith('@search');
   ```
2. **Query Extraction**:
   If true, extract the search query:
   ```dart
   final query = lastMessage.content.trim().substring(7).trim(); // Remove '@search'
   ```
3. **Bypass First LLM call**:
   Directly perform the search sequence:
   - Yield `ToolCallStartedEvent(query)`.
   - Call `_searchService.search(...)`.
   - Yield `ToolCallCompletedEvent(query, results)`.
4. **Build Simulated History**:
   - Format search results to Markdown text.
   - Clean the original user message to remove the `@search` prefix so it is presented cleanly to the LLM:
     `final cleanUserMessage = lastMessage.copyWith(content: query);`
   - Generate a mock `toolCallId` (e.g. `manual_search_${DateTime.now().millisecondsSinceEpoch}`).
   - Construct and yield the simulated assistant message and the tool message:
     - Assistant message contains a single `ToolCall` targeting `web_search`.
     - Tool message contains the formatted search results linked with the mock `toolCallId`.
5. **Invoke LLM**:
   - Create message payload: `[...messages.sublist(0, messages.length - 1), cleanUserMessage, assistantMessage, toolMessage]`.
   - Call `_chatService.chatCompletionsStream` and stream the final output.

This design ensures the conversation context maintains the identical assistant-tool structure for both manual and automatic searches, enabling standard UI components to render search results seamlessly.

---

## 4. Plan for Handling CancelToken and Stream Cancellation

Stream cancellation must be immediate, stopping both LLM generation and search execution.

1. **Dio Request Cancellation**:
   - Passing `CancelToken` directly to `_chatService.chatCompletionsStream` ensures that calling `cancelToken.cancel()` cancels the current underlying HTTP request.
   - Dio will throw a `DioException` with type `DioExceptionType.cancel`, terminating the stream.
2. **Search Phase Cancellation**:
   - Because `SearchService.search` performs async HTTP operations and does not accept `CancelToken` in its current signature, the cancellation check is performed immediately before and after the search call:
     ```dart
     if (cancelToken != null && cancelToken.isCancelled) {
       throw DioException(
         requestOptions: RequestOptions(path: ''),
         type: DioExceptionType.cancel,
         error: 'User requested cancellation',
       );
     }
     ```
3. **Graceful Stream Abort**:
   - Wrap the main loop in a `try-catch` block. When a cancellation exception is caught, rethrow it so the listener (e.g., `ChatProvider`) can catch it, update state (setting `isGenerating = false`), and preserve whatever partial message was generated.
   - If the stream listener unsubscribes (cancels subscription), Dart's `async*` generator automatically cleans up execution flow.

---

## 5. Plan for Tests in `test/agent_service_test.dart`

To ensure full testability without external API calls, we implement custom mocks and cover five core test suites.

### Subclass Mocks for Dependencies
Instead of pulling in bulky mock packages, we extend `ChatService` and `SearchService` for lightweight, deterministic mocking:

```dart
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
    return Stream.empty();
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

### Planned Test Cases

1. **Standard Streaming Chat (No Tool Call)**
   - **Setup**: `MockChatService` yields chunks `"Hello"`, `" world!"`. `MockSearchService` is not configured.
   - **Action**: Run `chatAndSearchStream` with a normal user message.
   - **Verification**: 
     - Verify emitted events are exactly: `[ContentDeltaEvent("Hello"), ContentDeltaEvent(" world!")]`.
     - Verify `MockSearchService` is never called.
2. **Automatic Tool Calling (Search Execution & Follow-up Chat)**
   - **Setup**: 
     - First call to `MockChatService` yields tool call delta chunks:
       - Chunk 1: `tool_calls: [{index: 0, id: "call_abc", function: {name: "web_search", arguments: "{\"query\":"}}]`
       - Chunk 2: `tool_calls: [{index: 0, function: {arguments: "\"flutter agent\"}"}}]`
     - `MockSearchService` returns: `[SearchResult(title: "Flutter Agent", url: "https://flutter.dev", content: "Agent details")]`.
     - Second call to `MockChatService` yields chunks `"Search shows"`, `" that..."`.
   - **Action**: Run `chatAndSearchStream`.
   - **Verification**:
     - Verify events contain `ToolCallStartedEvent("flutter agent")` and `ToolCallCompletedEvent("flutter agent", [...])`.
     - Verify `ToolCallExecutedMessageEvent` is emitted with valid intermediate messages.
     - Verify final events contain `ContentDeltaEvent("Search shows")` and `ContentDeltaEvent(" that...")`.
3. **Manual Trigger with `@search` Prefix**
   - **Setup**: User message content is `@search flutter components`. `MockSearchService` returns search results. `MockChatService` yields final reply text chunks.
   - **Action**: Run `chatAndSearchStream`.
   - **Verification**:
     - Verify first call to LLM is bypassed.
     - Verify search is performed directly with the query `"flutter components"`.
     - Verify generated assistant & tool messages are constructed correctly and the clean query is used.
     - Verify final chunks are yielded.
4. **Cancellation propagation (Dio cancellation)**
   - **Setup**: `MockChatService` returns a stream that throws `DioException(type: DioExceptionType.cancel)` when CancelToken is cancelled.
   - **Action**: Call `chatAndSearchStream`, trigger cancel after first event.
   - **Verification**:
     - Verify the exception is propagated from the stream, allowing caller handling.
5. **Cancellation during Search Execution**
   - **Setup**: `MockSearchService` delays response.
   - **Action**: Trigger `cancelToken.cancel()` while search is running.
   - **Verification**:
     - Verify that the stream throws `DioExceptionType.cancel` and exits, without initiating the second completion request.
