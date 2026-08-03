# Project: Flutter AI Agent (chat-app) v1.05.0+6 Update

## Architecture
- Flutter Application using Riverpod state management (`StateNotifier` + `StateNotifierProvider`), SQLite DAO layer (`DatabaseHelper`, `ApiConfigDao`, `ConversationDao`, `MessageDao`), HTTP/SSE via Dio (`ChatService`), and Web Search/Fetch services (`SearchService`, `UrlFetchService`, `AgentService`).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | R1: Session Swipe Removal | Remove `Dismissible` wrapper from sidebar list items in `home_screen.dart`, retain 3-dot popup menu for pin/archive/delete | M1 | ORIGINAL_REQUEST §2026-08-03 |
| 2 | R2: Global Search Switch | Add `enableAutoSearch` switch in `settings_screen.dart` / `settings_provider.dart`, prevent tool calls (`web_search`/`google_search`/`bing_search`) when disabled in `agent_service.dart` and `chat_provider.dart` | M2 | ORIGINAL_REQUEST §2026-08-03 |
| 3 | R3: Structured url_fetch Metadata & Table Parsing | HTML title, meta (description, author, keywords, og:*), HTML `<table>` to Markdown tables, links extraction, structured Markdown output, enhanced User-Agent and 403/timeout/404 error messages in `url_fetch_service.dart` | M3 | ORIGINAL_REQUEST §2026-08-03 |
| 4 | R3: Search Keyword Cleaning & Deduplication | Keyword cleaning (`cleanSearchQuery`) and deduplication (`deduplicateResults`) optimization in `search_service.dart` | M3 | ORIGINAL_REQUEST §2026-08-03 |
| 5 | R4: Version Bump & Verification | Update `pubspec.yaml` version to `1.05.0+6`, update `WORK_LOG.md` and `context.md`, ensure `flutter analyze` 0 issues and `flutter test` 100% pass | M4 | ORIGINAL_REQUEST §2026-08-03 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: Sidebar Swipe Gesture Removal | `lib/screens/home_screen.dart`, `test/widgets_test.dart` | None | IN_PROGRESS |
| 2 | M2: Global Web Search Control Switch | `lib/providers/settings_provider.dart`, `lib/screens/settings_screen.dart`, `lib/services/agent_service.dart`, `lib/providers/chat_provider.dart`, `test/agent_service_test.dart` | None | PLANNED |
| 3 | M3: Structured url_fetch & Search Cleaning | `lib/services/url_fetch_service.dart`, `lib/services/search_service.dart`, `test/url_fetch_service_test.dart`, `test/search_service_test.dart` | None | PLANNED |
| 4 | M4: Version Bump, Docs & Final Verification | `pubspec.yaml`, `WORK_LOG.md`, `.agents/context.md`, full analyze and tests | M1, M2, M3 | PLANNED |

## Interface Contracts
### Settings Provider ↔ Agent Service / Chat Provider
- `settingsProvider` exposes `enableAutoSearch` (bool).
- When `enableAutoSearch == false`, `agent_service.dart` filters/suppresses web search tools (`web_search`, `google_search`, `bing_search`) from `tools` list passed to backend API and pseudo-XML fallback, and `chat_provider.dart` suppresses automatic web search tool triggers.

### UrlFetchService ↔ AgentService
- `UrlFetchService.fetchUrl(String url)` returns structured Markdown containing metadata block (Title, Description, Author, Keywords, OG metadata), Markdown tables converted from `<table>`, extracted links, and clean body text. Returns friendly error messages on 403 WAF / timeout / 404.

## Code Layout
- `lib/screens/home_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/providers/settings_provider.dart`
- `lib/providers/chat_provider.dart`
- `lib/services/agent_service.dart`
- `lib/services/url_fetch_service.dart`
- `lib/services/search_service.dart`
- `pubspec.yaml`
- `WORK_LOG.md`
- `.agents/context.md`
- `test/`
