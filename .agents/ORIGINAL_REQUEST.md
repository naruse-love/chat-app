# Original User Request

## Initial Request — 2026-07-11T13:38:21+08:00

Build an Android AI Agent App using Flutter that connects to a 9Router (OpenAI-compatible) backend. The app supports multiple API configs, streaming chat with markdown, vision capability, and search integration.

Working directory: d:\work\chat
Integrity mode: benchmark

## Requirements

### R1. Multi-API Configuration and Secure Storage
The app must allow users to manage multiple API configurations (name, base URL, API key). API keys must be securely stored using Keystore/Keychain (via `flutter_secure_storage`). Users can choose the active configuration and select/search models retrieved from `/v1/models`.

### R2. Streaming Chat UI with Markdown & Reasoning
The chat interface must support streaming responses (with cancel capability), markdown rendering, code block syntax highlighting, and collapsible display of `reasoning_content` (thinking process).

### R3. Web Search Integration (9Router/SearXNG)
The chat agent must support web search via Tool Calling. It should prioritize 9Router's search API and fallback to SearXNG, returning structured search results to the context. It must support both manual `@search` prefix and AI-triggered automatic search.

### R4. Image Input (Vision)
Users can input images via camera or gallery. Images must be compressed and saved to the device file system (database stores path only), and sent to the API in base64 format using OpenAI Vision message structure.

### R5. Work Logging (WORK_LOG.md)
The agent team must log all development steps, design decisions, and status in `d:\work\chat\WORK_LOG.md` following the specific format described in the implementation plan.

## Verification Plan

### Automated Tests
The agent team must implement and run:
1. **Unit Tests**:
   - `ModelInfo` parsing and capability checks (e.g. vision/tools matching).
   - API config SQLite CRUD operations.
   - Encrypted storing/loading of API keys (mocking `flutter_secure_storage`).
   - SSE stream parser (chunk parsing, chunk buffer, end of stream handling).
   - `SearchService` double-mode fallback logic (mocking 9Router and SearXNG).
2. **Widget Tests**:
   - Markdown code block parsing and syntax highlighting rendering.
   - Reasoning content folded/expanded UI toggle logic.
3. **Build Check**:
   - Run `flutter build apk --debug` to ensure compilation is successful.

## Acceptance Criteria

### Code Quality and Functionality
- [ ] `flutter test` executes all unit/widget tests and passes with 100% success rate.
- [ ] `flutter build apk --debug` succeeds without errors.
- [ ] `flutter_secure_storage` is integrated and verifying that API Keys are never logged or stored as plain text in the SQLite database.
- [ ] Double-mode search fallback is implemented and unit-tested to successfully query 9Router first, then fallback to SearXNG on failures.
- [ ] Images are successfully compressed and saved to file system, with SQLite storing only file paths.

### Process Integrity
- [ ] `d:\work\chat\WORK_LOG.md` is created/updated with at least one structured entry documenting the files created/changed, current state, next steps, and technical decisions.

## Follow-up — 2026-07-11T11:10:32Z

The user has requested to pause the project after the current milestone (Milestone 2) is completed and verified CLEAN. Halt spawning any subagents for Milestone 3 (or any subsequent milestones) once Milestone 2 is successfully finalized, and pause/cancel the monitoring crons.

## Follow-up — 2026-07-12T08:51:43Z

An Android AI Agent mobile app (Flutter) connected to 9Router with support for multi-API config, local SQLite history, web search tool calling, and image inputs.

Working directory: d:\work\chat
Integrity mode: benchmark

## Background & Current State
The project has successfully implemented and verified:
- **Milestone 1**: Data models and serialization tests.
- **Milestone 2**: Local Database (SQLite) and secure credential storage (SecureStorageService) with atomic transaction rollbacks.
- **Milestone 3**: SSE stream decoding (`SseDecoder`, `SseParser`) and network API connectivity (`ChatService`).
- **Milestone 4**: Web Search and agent tool scheduling (`SearchService` and `AgentService`).
Currently, 85 unit tests are in the `test/` directory, all of which pass 100% cleanly. `lib/main.dart` is clean.

## Requirements

The teamwork subagent team must complete the remaining Milestones to deliver the full application:

### R1. Complete Milestone 5: Image Service & Image UI
- Implement an image service to pick images (camera and gallery), compress them under 1MB (max 1024px width/height), save them to the local application directory (database storing the path), and encode them to Base64 data URIs for OpenAI Vision-compatible requests.
- Integrate image selection preview and removal into the chat input interface.

### R2. Complete Milestone 6: Providers & UI Screens
- Set up state management using Riverpod with separate providers for conversations, chat sessions, API configurations, active models, tool calling/agent status, themes, and general settings.
- Implement the user interface:
  - **Home Screen**: Chat history sidebar drawer (with pin/archive options), top configuration/model switcher, message bubbles with collapsible reasoning foldouts for models like DeepSeek-R1, and a responsive input area with a "Stop Generating" cancel button.
  - **Settings Screen**: Fields for SearXNG URL, API settings, and theme options.
  - **API Config Screen**: Add/Edit/Delete API configurations with a connection test function.
  - **Model Selector Screenened**: View available models grouped by provider with capability tags (Vision/Tools).
  - **System Prompt Templates Screen**: Selection and custom editing of prompt templates.

### R3. Complete Milestone 7: End-to-End & Widget Testing
- Add thorough widget and integration tests covering user message flow, model switching, image sending, search tool triggering, and conversation pinning/archiving.
- Ensure all new features are backed by high-quality test coverage.

### R4. Complete Milestone 8: Adversarial Error Handling & Hardening
- Gracefully handle issues like lost internet connections, invalid endpoints, API rate limits, model capability mismatches (e.g. sending images to non-vision models), and corrupted database files.

## Acceptance Criteria

### Technical Requirements
- [ ] No static analysis errors: running `flutter analyze` reports 0 warnings/errors.
- [ ] Complete test pass: running `flutter test` executes all test cases (both existing and new) successfully (100% pass rate).
- [ ] Compile verification: running `flutter build apk --debug` completes with 0 errors and generates the debug APK file successfully.
- [ ] All technical decisions, changes, and progress updates must be documented in `WORK_LOG.md`.

## Follow-up — 2026-07-16T16:57:35+08:00

This project enhances the Flutter-based AI chat application by integrating a direct public OpenCode Free provider, implementing a webpage content scraper tool (`url_fetch`), and optimizing the search results retrieval and formatting.

Working directory: d:\work\chat
Integrity mode: development

## Requirements

### R1. Direct OpenCode Free Provider Integration
- Pre-populate a default API configuration in the app for "OpenCode Free" when the database is empty:
  - Base URL: `https://opencode.ai/zen/v1`
  - API Key: a dummy placeholder key
  - set as the default/active config
- In the model selection list, dynamically fetch models from the provider's `/v1/models` endpoint.
- Provide a robust fallback list of model metadata if the network request fails or when starting offline. The fallback models must include:
  - `deepseek-v4-flash-free`
  - `mimo-v2.5-free`
  - `hy3-free`
  - `nemotron-3-ultra-free`
  - `north-mini-code-free`

### R2. Webpage Full-Text Fetching (`url_fetch`)
- Create a `UrlFetchService` using Dio and the existing `html` parser package to request webpage HTML, extract plain body text (stripping scripts, styles, etc.), and limit the return size to 8000 characters.
- Add `url_fetch` tool alongside `web_search` in `AgentService` so the LLM can call both tools (standard tool calling and pseudo-XML fallback path).
- Update the home screen UI search progress card: when fetching a URL, display `"正在读取网页: [URL]..."` in the existing bottom status card by modifying `agentProvider` and `home_screen.dart`.

### R3. Web Search Optimizations
- Format search results using the optimized format:
  ```
  以下是网络搜索结果。请仔细阅读后基于这些信息回答用户问题。
  如果需要更详细的信息，请使用 url_fetch 工具读取相关页面全文。
  回答时请引用来源 URL。

  1. [Title](URL)
     摘要: snippet
  ```
- Increase SearXNG search result count by firing concurrent requests for `pageno: 1` and `pageno: 2` (safely using `Future.wait` and individual `try-catch` blocks) and deduplicating results by URL.

## Verification & Acceptance Criteria

### Automated Verification
- [ ] Running `D:\work\flutter-sdk\flutter\bin\flutter.bat test` must pass all existing tests (127/127).
- [ ] Add unit tests verifying `UrlFetchService` functionality (fetching, parsing, stripping, 8000-char truncation).
- [ ] Add unit tests verifying `SearchService` page-combining and deduplication.
- [ ] Running `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` must return 0 issues (no errors or warnings).

### Manual Acceptance Criteria
- [ ] Launching the app on a fresh DB automatically creates the "OpenCode Free" provider.
- [ ] Selecting "OpenCode Free" lists the free models.
- [ ] Perform a chat query utilizing web search works, shows the loading status correctly, formats results nicely, and allows tool-calling for `url_fetch`.

## Follow-up — 2026-08-03T21:43:57+08:00

Flutter AI Agent 移动端 App（chat-app）：实现禁用侧边栏会话列表滑动手势、在设置中增加「启用 AI 网络搜索」开关、以及全方位优化 url_fetch 网页抓取结构化元数据与搜索后端服务。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. 会话列表滑动手势禁防误删
移除 home_screen.dart 侧边栏会话列表项上的 Dismissible 滑动手势包装器，置顶、归档与删除功能统一仅通过右侧 3 点 PopUp 菜单（PopupMenuButton）操作。

### R2. 全局网络搜索控制与 Agent 工具屏蔽
在 settings_screen.dart 的【网络搜索设置】添加「启用 AI 网络搜索」开关（enableAutoSearch）。当关闭时，agent_service.dart 和 chat_provider.dart 不向大模型透传任何搜索 Tool Call (web_search / google_search / bing_search)。

### R3. url_fetch 结构化元数据提取与搜索服务优化
- url_fetch_service.dart 自动解析 HTML <title>、<meta description/author/keywords/og:*> 元数据，将 <table> 解析为 Markdown 表格，提取页面重要链接，并包装为结构化 Markdown 输出。同时强化 User-Agent 头与 403 WAF 阻断/超时/404 容错提示。
- search_service.dart 优化搜索关键词清洗与结果去重。

### R4. 项目质量与代码规范
- 遵守 AGENTS.md 规则：pubspec.yaml 版本号递增 0.01（升至 1.05.0+6）。
- 确保 flutter analyze 保持 0 issues，运行 flutter test 所有测试 100% 通过（0 failures）。
- 更新 WORK_LOG.md 与 .agents/context.md。

## Acceptance Criteria

### A1. 滑动手势
- [ ] 会话列表项滑动不再触发删除或置顶操作
- [ ] 3 点菜单保留置顶/取消置顶、归档/取消归档、删除操作且功能完全正常

### A2. 搜索控制
- [ ] 设置界面包含“启用 AI 网络搜索”开关
- [ ] 开关关闭时，AI 消息生成过程中不触发 web_search / google_search / bing_search 工具调用

### A3. 结构化网页抓取
- [ ] url_fetch 包含网页标题、Description、Author、Keywords 等元数据输出
- [ ] url_fetch 支持将 HTML 表格格式化为标准 Markdown 表格
- [ ] 网络超时/403 阻断时返回清晰友好提示

### A4. 代码与测试质量
- [ ] pubspec.yaml 版本号为 1.05.0+6
- [ ] flutter analyze 输出 No issues found!
- [ ] flutter test 所有测试用例 100% 通过（0 failures）
