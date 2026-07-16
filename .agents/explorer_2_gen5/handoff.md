# Handoff Report: Webpage Full-Text Scraper (`url_fetch`) and UI Integration (Requirement 2)

## 1. Observation

Direct inspection of the codebase yielded the following existing structures and baseline states:

1. **Dependencies (`pubspec.yaml`)**:
   - `dio: ^5.4.0` is installed.
   - `html: ^0.15.4` is installed.
2. **Current Tool Execution in `AgentService` (`lib/services/agent_service.dart`)**:
   - `webSearchTool` schema is currently the only tool defined in `AgentService`.
   - Tool calling is handled in 2 distinct paths:
     a) **Standard OpenAI Tool Calling**: Checks `accumulatedToolCalls`, loops over tool requests, calls `_searchService.search()`, emits `ToolCallStartedEvent` / `ToolCallCompletedEvent` / `ToolCallExecutedMessageEvent`.
     b) **Pseudo-XML Tool Calling Fallback**: Parsed by `parsePseudoXmlToolCalls(fullContent)`, stripped by `stripPseudoXmlToolCalls(fullContent)`. Currently matches function names and parameters, but hardcoded to execute only `web_search`.
   - Streaming events in `AgentService`: Emits `ToolCallStartedEvent(query)` and `ToolCallCompletedEvent(query, results)`.
3. **Agent State Management (`lib/providers/agent_provider.dart` & `lib/providers/chat_provider.dart`)**:
   - `AgentState` contains `isSearching`, `searchQuery`, and `searchResults`.
   - `AgentNotifier` provides `startSearch`, `completeSearch`, and `reset`.
   - `chat_provider.dart` listens to `_agentService.chatAndSearchStream()` and invokes `startSearch` and `completeSearch` on `agentProvider`.
4. **UI Display (`lib/screens/home_screen.dart`)**:
   - Lines 176 & 201: ListView checks `agentState.isSearching` to display a progress indicator card at the bottom of the message list.
   - Card text is currently hardcoded: `'正在搜索: "${agentState.searchQuery}"...'`.

---

## 2. Logic Chain

### Part 1: Design of `UrlFetchService` (`lib/services/url_fetch_service.dart`)

- **Purpose**: Fetch HTML from a specified URL, extract plain body text using `package:html`, strip irrelevant markup (`<script>`, `<style>`, `<noscript>`), truncate to 8000 characters, and handle errors/timeouts gracefully.
- **Implementation Design**:
  ```dart
  import 'package:dio/dio.dart';
  import 'package:html/parser.dart' as html_parser;

  class UrlFetchService {
    final Dio _dio;

    UrlFetchService({Dio? dio}) : _dio = dio ?? Dio();

    /// Fetches webpage content from [url], strips scripts/styles, extracts body text,
    /// and truncates output to 8000 characters.
    Future<String> fetchUrlContent(String url, {CancelToken? cancelToken}) async {
      try {
        final response = await _dio.get<String>(
          url,
          cancelToken: cancelToken,
          options: Options(
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
            responseType: ResponseType.plain,
            sendTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );

        final htmlContent = response.data ?? '';
        if (htmlContent.trim().isEmpty) {
          return '网页内容为空';
        }

        final document = html_parser.parse(htmlContent);

        // Remove script, style, and noscript elements
        for (final tag in ['script', 'style', 'noscript']) {
          document.getElementsByTagName(tag).toList().forEach((element) => element.remove());
        }

        final rawText = document.body?.text ?? document.documentElement?.text ?? '';
        
        // Normalize whitespace (collapse multiple spaces/newlines)
        final cleanedText = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();

        if (cleanedText.isEmpty) {
          return '提取网页正文内容为空';
        }

        if (cleanedText.length > 8000) {
          return cleanedText.substring(0, 8000);
        }

        return cleanedText;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          return '读取网页超时：请检查网络或目标 URL 是否可达';
        }
        return '读取网页失败：${e.message ?? e.toString()}';
      } catch (e) {
        return '解析网页失败：$e';
      }
    }
  }
  ```

---

### Part 2: Integrating `url_fetch` into `AgentService` (`lib/services/agent_service.dart`)

1. **Tool Schema Definition**:
   ```dart
   static const Map<String, dynamic> urlFetchTool = {
     'type': 'function',
     'function': {
       'name': 'url_fetch',
       'description': 'Fetch and extract plain text body content from a specified webpage URL.',
       'parameters': {
         'type': 'object',
         'properties': {
           'url': {
             'type': 'string',
             'description': 'The absolute HTTP or HTTPS URL of the webpage to fetch.',
           },
         },
         'required': ['url'],
       },
     },
   };
   ```
   Combine in available tools list: `static const List<Map<String, dynamic>> defaultTools = [webSearchTool, urlFetchTool];`

2. **Stream Events Update**:
   Update `AgentStreamEvent` hierarchy or add event types:
   ```dart
   class UrlFetchStartedEvent extends AgentStreamEvent {
     final String url;
     const UrlFetchStartedEvent(this.url);
   }

   class UrlFetchCompletedEvent extends AgentStreamEvent {
     final String url;
     final String content;
     const UrlFetchCompletedEvent(this.url, this.content);
   }
   ```
   Alternatively, add optional fields or `toolName` parameter to `ToolCallStartedEvent` / `ToolCallCompletedEvent`. Creating explicit `UrlFetchStartedEvent` and `UrlFetchCompletedEvent` provides strict typing and simplifies state updates in `chat_provider.dart`.

3. **Service Dependency Injection**:
   ```dart
   final UrlFetchService _urlFetchService;

   AgentService({
     ChatService? chatService,
     SearchService? searchService,
     UrlFetchService? urlFetchService,
   })  : _chatService = chatService ?? ChatService(),
         _searchService = searchService ?? SearchService(),
         _urlFetchService = urlFetchService ?? UrlFetchService(),
         _uuid = const Uuid();
   ```

4. **Execution Path Dispatching**:
   - **Standard Tool Calling Execution Loop**:
     When parsing `accumulatedToolCalls`, inspect `entry.name`:
     - If `entry.name == 'web_search'`:
       Execute search via `_searchService.search(query: query)`.
     - If `entry.name == 'url_fetch'`:
       Extract `url` parameter from JSON decoded arguments.
       Yield `UrlFetchStartedEvent(url)`.
       Fetch content via `await _urlFetchService.fetchUrlContent(url, cancelToken: cancelToken)`.
       Yield `UrlFetchCompletedEvent(url, content)`.
       Construct `ChatMessage(role: 'tool', toolCallId: entry.id, content: content)`.
   - **Pseudo-XML Execution Loop**:
     When parsing `pseudoCalls`:
     - If `name == 'url_fetch'` and `params['url']` is not empty:
       Yield `UrlFetchStartedEvent(url)`.
       Fetch content.
       Yield `UrlFetchCompletedEvent(url, content)`.
       Construct `ChatMessage(role: 'tool', toolCallId: toolCallId, content: content)`.

---

### Part 3: State Management & UI Updates

1. **`AgentState` & `AgentNotifier` (`lib/providers/agent_provider.dart`)**:
   ```dart
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
   ```
   Add notifier methods:
   - `startUrlFetch(String url)` -> sets `isFetchingUrl: true, fetchingUrl: url, isSearching: false`
   - `completeUrlFetch()` -> sets `isFetchingUrl: false, fetchingUrl: ''`
   - `reset()` -> resets both `isSearching` and `isFetchingUrl` to false.

2. **`chat_provider.dart` Listener Integration**:
   Inside `_startStreaming`:
   ```dart
   if (event is ToolCallStartedEvent) {
     _ref.read(agentProvider.notifier).startSearch(event.query);
   } else if (event is ToolCallCompletedEvent) {
     _ref.read(agentProvider.notifier).completeSearch(event.results);
   } else if (event is UrlFetchStartedEvent) {
     _ref.read(agentProvider.notifier).startUrlFetch(event.url);
   } else if (event is UrlFetchCompletedEvent) {
     _ref.read(agentProvider.notifier).completeUrlFetch();
   }
   ```

3. **`home_screen.dart` Bottom Progress Card Integration**:
   - Change check for displaying progress card:
     ```dart
     final isBusy = agentState.isSearching || agentState.isFetchingUrl;
     ```
   - Update ListView item count: `allMessages.length + (isBusy ? 1 : 0)`.
   - Update status card message text dynamically:
     ```dart
     final statusText = agentState.isFetchingUrl
         ? '正在读取网页: ${agentState.fetchingUrl}...'
         : '正在搜索: "${agentState.searchQuery}"...';
     ```

---

## 3. Caveats

1. **HTML Parsing Efficiency**: Large HTML documents (several megabytes) parsed in Dart standard thread may take 50-100ms. Removing `script`, `style`, and `noscript` before accessing `.text` is essential. `getElementsByTagName().toList().forEach()` prevents `ConcurrentModificationError` when removing live DOM elements.
2. **Text Normalization & Truncation**: Truncating at exactly 8000 characters could split a UTF-16 surrogate pair or multi-byte string if not using substring safely; in Dart, standard UTF-16 code units in `String` are safe for substring, but ensure string bounds are clamped (`cleanedText.length > 8000 ? cleanedText.substring(0, 8000) : cleanedText`).
3. **Network Failure & HTTP Status Code Handling**: Sites that block automated agents (403, 429) or return non-HTML responses (e.g. raw PDF/binary) will return error text rather than crashing the stream loop. Returning the error string as the tool message content allows LLMs to attempt recovery or inform the user.

---

## 4. Conclusion

The design for Requirement 2 seamlessly integrates `UrlFetchService` with existing Dio & Riverpod architectural patterns:
1. `UrlFetchService` isolates network request, DOM cleanup, and length control.
2. `AgentService` registers `url_fetch` alongside `web_search` and supports both standard JSON `tool_calls` and pseudo-XML fallback.
3. `agentProvider` & `home_screen.dart` dynamically display `"正在读取网页: [URL]..."` or `"正在搜索: [Query]..."` status based on active stream events.

---

## 5. Verification Method

1. **Unit Testing (`test/services/url_fetch_service_test.dart`)**:
   - Test plain body text extraction and stripping of `<script>` and `<style>` tags.
   - Test text truncation at 8000 characters.
   - Test HTTP timeout / failure error handling.
2. **Analysis & Diagnostics**:
   - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` (Must report 0 issues).
   - Run `D:\work\flutter-sdk\flutter\bin\flutter.bat test` (Must pass 100% of tests).
