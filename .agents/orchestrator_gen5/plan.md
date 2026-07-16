# Project Plan: Flutter Chat App Feature Extension

## Architecture & Scope
Extend the existing Flutter AI chat application with:
1. OpenCode Free provider pre-population and dynamic/fallback model management.
2. `UrlFetchService` web scraper tool integration and status UI.
3. SearXNG dual-page concurrent search, URL deduplication, and updated search formatting with `url_fetch` guidance.

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | OpenCode Free Integration (R1) | Pre-populate default config on empty DB (`https://opencode.ai/zen/v1`, dummy key, active); dynamic model fetching with fallback metadata list (`deepseek-v4-flash-free`, `mimo-v2.5-free`, `hy3-free`, `nemotron-3-ultra-free`, `north-mini-code-free`). | None | DONE |
| 2 | Webpage Fetcher & UI (R2) | `UrlFetchService` with Dio & `html` parser (8000 char max, text stripping); tool registration in `AgentService` (`url_fetch` standard & XML fallback); update `agentProvider` and `home_screen.dart` to show `"正在读取网页: [URL]..."`. | M1 | DONE |
| 3 | Search Optimizations (R3) | SearXNG parallel fetch (`pageno: 1` & `pageno: 2` with `Future.wait` & individual `try-catch`), deduplicate by URL; search results prompt update guiding model to `url_fetch`. | M2 | DONE |
| 4 | Testing & Verification & WORK_LOG | Comprehensive unit tests for `UrlFetchService`, `SearchService`, `AgentService`, and OpenCode integration; `flutter test` 100% pass; `flutter analyze` 0 issues; update `WORK_LOG.md` top header. | M1, M2, M3 | DONE |
