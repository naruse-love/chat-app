# Original User Request

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
- [ ] Running `D:\work\flutter-sdk\flutter\bin\flutter.bat test` must pass all existing tests (127/127) and new tests.
- [ ] Add unit tests verifying `UrlFetchService` functionality (fetching, parsing, stripping, 8000-char truncation).
- [ ] Add unit tests verifying `SearchService` page-combining and deduplication.
- [ ] Running `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` must return 0 issues (no errors or warnings).

### Manual Acceptance Criteria
- [ ] Launching the app on a fresh DB automatically creates the "OpenCode Free" provider.
- [ ] Selecting "OpenCode Free" lists the free models.
- [ ] Performing a chat query utilizing web search works, shows the loading status correctly, formats results nicely, and allows tool-calling for `url_fetch`.
