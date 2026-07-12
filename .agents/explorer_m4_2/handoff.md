# Handoff Report — AgentService Design & Test Planning

## 1. Observation
- `lib/services/chat_service.dart` (lines 20-69) defines `ChatService.chatCompletionsStream`, which yields SSE stream chunks of `Map<String, dynamic>`. It accepts `CancelToken? cancelToken` (line 26) and `List<Map<String, dynamic>>? tools` (line 25).
- `lib/services/search_service.dart` (lines 38-95) defines `SearchService.search`, which executes search queries with a fallback from 9Router to SearXNG. Lines 99-114 define `formatSearchResultsForContext`, converting list search results to a Markdown snippet.
- `lib/models/chat_message.dart` (lines 7-56) defines `ChatMessage` which includes optional properties `toolCalls` and `toolCallId`.
- `lib/models/tool_call.dart` (lines 6-44) defines `ToolCall` with `id`, `type`, `functionName`, and `arguments` representing standard function-calling elements.
- `test/chat_service_test.dart` and `test/search_service_test.dart` use custom mock adapter `MockAdapter` implementation (e.g., `test/search_service_test.dart` lines 7-24) to intercept network requests instead of using mock library codegen tools.

## 2. Logic Chain
- **Coordinate completions and search**: Based on the `ChatService` and `SearchService` implementations, `AgentService` needs to sit on top of both. It should capture SSE chunks, parse tool call deltas, execute the search using `SearchService`, and feed the formatted result back into `ChatService.chatCompletionsStream`.
- **Handling Prefix Trigger**: The `@search` prefix can be detected on the user's last message in the list. By stripping the prefix and executing search immediately, we bypass the first LLM model pass. Injecting the result as a simulated tool call (via `ChatMessage` with `toolCalls` and a tool response message with matching `toolCallId`) allows us to use the same final streaming completion pipeline.
- **Handling stream cancellation**: Since `ChatService.chatCompletionsStream` already accepts a `CancelToken`, we can pass it down. Checking `cancelToken.isCancelled` during our processing loops prevents starting any new tasks once the token has been aborted.
- **Test execution stability**: Since the project tests do not use code-generated mock libraries (e.g., mockito), custom mock implementations extending `ChatService` and `SearchService` will provide type safety and avoid build runner overhead.

## 3. Caveats
- The model may output multiple tool calls in parallel or trigger unknown tools. The current design assumes only the `web_search` tool call will be triggered since it is the only one defined in the tools list, but we include error boundaries for unsupported tool calls.
- The `CancelToken` must be checked before calling search and inside stream listening loops because `SearchService.search` does not accept a cancel token itself.

## 4. Conclusion
- A design for `AgentService` has been created and documented in `.agents/explorer_m4_2/analysis.md`.
- It defines `web_search` tool schema, coordinates dual stream loops, supports manual `@search` triggers, handles cancellation via `CancelToken` and includes a plan for unit tests with manual mocks.

## 5. Verification Method
- **Verification files**: Inspect the design document at `d:\work\chat\.agents\explorer_m4_2\analysis.md`.
- **Validation tool**: When implemented, `flutter test test/agent_service_test.dart` will run all proposed test cases.
