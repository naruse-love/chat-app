## 2026-07-12T11:44:19Z
Please analyze the codebase and design the implementation of `AgentService` (`lib/services/agent_service.dart`) and its unit tests (`test/agent_service_test.dart`) according to the requirements in `d:\work\chat\ORIGINAL_REQUEST.md`.
Write a detailed report to `d:\work\chat\.agents\explorer_m4_3\analysis.md` including:
1. The suggested class structure and API of `AgentService`.
2. The logic for web search tool calling flow (coordinating `ChatService` and `SearchService`).
3. The logic for processing `@search` prefix manual triggers in user messages.
4. The plan for handling CancelToken/stream cancellation.
5. The plan for tests in `test/agent_service_test.dart` (mocking, test cases).
Report back when done. Do not write or edit any source files.
