## 2026-07-16T16:59:32Z
You are Worker 1 assigned to implement Requirements 1, 2, and 3 for the Flutter AI Chat Application.
Your working directory is .agents/worker_1_gen5/ (create it if needed).

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Refer to the handoff reports from the 3 Explorers:
- `.agents/explorer_1_gen5/handoff.md` (R1)
- `.agents/explorer_2_gen5/handoff.md` (R2)
- `.agents/explorer_3_gen5/handoff.md` (R3)
- `.agents/AGENTS.md` (Development Rules)

### Task Scope:

#### 1. Requirement 1: OpenCode Free Provider Integration
- Modify `lib/models/model_info.dart`:
  - Add static list `defaultOpenCodeFallbackModels` containing 5 models: `deepseek-v4-flash-free`, `mimo-v2.5-free`, `hy3-free`, `nemotron-3-ultra-free`, `north-mini-code-free` (each with `provider: 'opencode'`, `supportsVision: false`, `supportsTools: true`).
  - In `ModelInfo.fromApiResponse`, if provider resolves to `'unknown'`, default it to `'opencode'`.
- Modify `lib/providers/api_config_provider.dart`:
  - In `ApiConfigNotifier.loadConfigs()`: when `configs.isEmpty`, auto-create default config `"OpenCode Free"` (`baseUrl: 'https://opencode.ai/zen/v1'`, `apiKeyRef: 'opencode_free_api_key_ref'`, `isDefault: true`, placeholder API key `'opencode-free-key'`) via `_apiConfigDao.insert(...)`.
- Modify `lib/providers/model_provider.dart`:
  - In `ModelNotifier.fetchModels()` error catch block: set `state` with `ModelInfo.defaultOpenCodeFallbackModels` instead of leaving model list empty on network failure.

#### 2. Requirement 2: Webpage Full-Text Fetching (`url_fetch`)
- Create `lib/services/url_fetch_service.dart`:
  - Uses `Dio` for GET requests with timeout settings (10s) and User-Agent header.
  - Parses DOM with `package:html/parser.dart`, safely removes `<script>`, `<style>`, and `<noscript>` elements.
  - Extracts body text, normalizes whitespace, truncates content to max 8000 characters.
  - Returns clear user-facing error text on DioException or parsing failures.
- Modify `lib/services/agent_service.dart`:
  - Define `urlFetchTool` schema and include in `defaultTools`.
  - Add `UrlFetchStartedEvent(url)` and `UrlFetchCompletedEvent(url, content)`.
  - Integrate `_urlFetchService` into `AgentService` constructor.
  - Support `url_fetch` in both standard OpenAI `tool_calls` loop and pseudo-XML `<tool_call>` fallback loop.
- Modify `lib/providers/agent_provider.dart`:
  - Add `isFetchingUrl` and `fetchingUrl` properties to `AgentState` and `copyWith`.
  - Add `startUrlFetch(String url)` and `completeUrlFetch()` methods to `AgentNotifier`. Update `reset()` to clear both searching and url fetching states.
- Modify `lib/providers/chat_provider.dart`:
  - In `_startStreaming`, handle `UrlFetchStartedEvent` and `UrlFetchCompletedEvent` to update `agentProvider`.
- Modify `lib/screens/home_screen.dart`:
  - Update progress card visibility to check `isBusy = agentState.isSearching || agentState.isFetchingUrl`.
  - Display `"正在读取网页: [URL]..."` when `isFetchingUrl` is true, or `"正在搜索: [Query]..."` when searching.

#### 3. Requirement 3: Web Search Optimizations
- Modify `lib/services/search_service.dart`:
  - Update `formatSearchResultsForContext` to:
    ```
    以下是网络搜索结果。请仔细阅读后基于这些信息回答用户问题。
    如果需要更详细的信息，请使用 url_fetch 工具读取相关页面全文。
    回答时请引用来源 URL。

    1. [Title](URL)
       摘要: snippet
    ```
  - In `_searchSearxng`, query `pageno: 1` and `pageno: 2` concurrently using `Future.wait([fetchPage(1), fetchPage(2)])` with per-page `try-catch` blocks. Combine results and deduplicate by URL using `Set<String> seenUrls`.

#### 4. Testing & Verification
- Create `test/url_fetch_service_test.dart`:
  - Test body text extraction, script/style stripping, 8000-char truncation, network timeout/failure handling.
- Modify `test/search_service_test.dart`:
  - Update existing formatting test to match the new `url_fetch` prompt text and `[Title](URL)` link format.
  - Add unit tests verifying SearXNG dual-page fetching (`pageno: 1` & `pageno: 2`) and URL deduplication.
  - Add unit test verifying partial page timeout resilience.
- Modify `test/e2e_integration_test.dart`:
  - Update config count expectation (from 1 to 2) to account for pre-populated OpenCode Free config on empty DB.
- Add unit tests for OpenCode Free default config pre-population & model fallback.

#### 5. Rules & Quality Control:
- Run static analysis: `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` (Must report 0 issues).
- Run unit tests: `D:\work\flutter-sdk\flutter\bin\flutter.bat test` (All existing 127/127 and new tests must pass).
- Update top header of `d:\work\chat\WORK_LOG.md` with structured entry documenting files changed, status, and technical decisions.
- Execute `git add -A && git commit -m "feat: integrate opencode free provider, url_fetch scraper tool, and search optimizations" && git push`.

Write your full progress and handoff report to `.agents/worker_1_gen5/handoff.md` and send a message when complete with test results and command outputs.
