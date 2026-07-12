# Project: Android AI Agent App

## Architecture
- **Presentation Layer (UI/Widgets)**: Riverpod providers drive the UI widgets. UI is decoupled from services via providers.
- **State Management (Providers)**: riverpod for state management. 7 separate providers handle specific domain models.
- **Service Layer (Services/Business Logic)**:
  - `ChatService` handles interaction with the 9Router backend.
  - `SearchService` handles double-mode search fallback logic.
  - `AgentService` handles Tool Calling flow.
  - `ImageService` handles image loading, compression, and saving to disk.
- **Data Access Layer (DAOs/Database)**:
  - `DatabaseHelper` manages SQLite database initialization and upgrades.
  - Separate DAOs manage SQLite queries for Conversation, Message, and ApiConfig.
  - API Keys are encrypted and stored via `flutter_secure_storage`.
- **Infrastructure**:
  - `SSEParser` parses SSE chunk streams.
  - `ImageUtils`, `DateUtils`, `SseDecoder` utilities.

## Code Layout
```
lib/
├── main.dart
├── app.dart
├── constants/
│   ├── api_constants.dart
│   ├── database_constants.dart
│   └── ui_constants.dart
├── models/
│   ├── api_config.dart
│   ├── model_info.dart
│   ├── chat_message.dart
│   ├── conversation.dart
│   ├── tool_call.dart
│   └── system_prompt_template.dart
├── data/
│   ├── database_helper.dart
│   ├── conversation_dao.dart
│   ├── message_dao.dart
│   └── api_config_dao.dart
├── services/
│   ├── chat_service.dart
│   ├── sse_parser.dart
│   ├── search_service.dart
│   ├── agent_service.dart
│   └── image_service.dart
├── providers/
│   ├── conversation_provider.dart
│   ├── chat_provider.dart
│   ├── api_config_provider.dart
│   ├── model_provider.dart
│   ├── agent_provider.dart
│   ├── theme_provider.dart
│   └── settings_provider.dart
├── screens/
│   ├── home_screen.dart
│   ├── settings_screen.dart
│   ├── api_config_screen.dart
│   ├── model_selector_screen.dart
│   └── system_prompt_screen.dart
├── widgets/
│   ├── chat_bubble.dart
│   ├── chat_input.dart
│   ├── markdown_renderer.dart
│   └── image_picker_button.dart
├── theme/
│   └── app_theme.dart
└── utils/
    ├── sse_decoder.dart
    ├── image_utils.dart
    └── date_utils.dart
```

## Milestones
| # | Name | Scope | Dependencies | Status | Conversation ID |
|---|------|-------|--------------|--------|-----------------|
| 1 | Init & Models | `pubspec.yaml`, `AndroidManifest.xml`, `lib/models/` | None | DONE | cf023117-87cb-4088-a2e9-0558f25614f4 |
| 2 | SQLite Storage | `lib/data/`, secure storage encryption | M1 | DONE | 7cd3964e-beb6-4de1-a917-ba32e6a16444 |
| 3 | SSE & Chat Service | `lib/services/chat_service.dart`, `sse_parser.dart`, `sse_decoder.dart` | M1 | PLANNED | TBD |
| 4 | Search & Agent Core | `lib/services/search_service.dart`, `agent_service.dart`, tool schemas | M1, M3 | PLANNED | TBD |
| 5 | Image & UI | `lib/services/image_service.dart`, UI parts | M1, M2 | PLANNED | TBD |
| 6 | Providers & UI | `lib/providers/`, `lib/screens/`, `lib/widgets/` | M1-M5 | PLANNED | TBD |
| 7 | E2E Testing Track | Requirement-driven test suite (Tiers 1-4) | None | PLANNED | TBD |
| 8 | E2E Phase 1 & 2 | Integration, E2E test verification, Adversarial coverage hardening | M6, M7 | PLANNED | TBD |

## Interface Contracts

### API Config & Key Encryption
- **ApiConfig**: `id`, `name`, `baseUrl`, `apiKeyRef`, `isDefault`, `createdAt`.
- API keys are retrieved by reading `flutter_secure_storage` with key `apiKeyRef`. They are never written to the SQLite DB.

### Model Info Capabilities
- `/v1/models` returns model JSONs.
- `ModelInfo.fromApiResponse(Map<String, dynamic> json)` parses and extracts:
  - `provider` (first segment of ID if slash exists, e.g. "openai")
  - `modelName` (remaining segment of ID, e.g. "gpt-4o")
  - `supportsVision` (bool, inferred from provider/model name details)
  - `supportsTools` (bool, inferred from provider/model name details)

### SSE Parser Stream
- `SSEParser.parse(Stream<List<int>> byteStream)` returns `Stream<ChatCompletionChunk>`.
- Must handle chunk assembly of incomplete JSON lines and buffer boundaries.

### Double-mode Search
- `SearchService.search(String query)`:
  - Try 9Router: `POST {baseUrl}/search?q={query}`
  - Fallback on failure (or HTTP 404/500/etc.) to SearXNG: `GET {searxngUrl}/search?q={query}&format=json`
  - Returns `Future<List<SearchResult>>`.
