# WORK LOG — Milestone 3: SSE Streaming & Chat Network Service (2026-07-12)

## Files Created/Changed
### Network & SSE Layer (`lib/services/`, `lib/utils/`)
- `lib/utils/sse_decoder.dart`: Decodes stream bytes (`Uint8List`) into UTF-8 lines, buffering incomplete lines and split multi-byte characters.
- `lib/services/sse_parser.dart`: Parses data lines, decodes JSON, and closes gracefully on `data: [DONE]`.
- `lib/services/chat_service.dart`: Integrates `/v1/chat/completions` (with cancel token, tools, and vision base64 conversion) and `/v1/models`.
- `lib/services/search_service.dart`: Dual-mode web search prioritizing 9Router search with fallback to SearXNG.
- `android/gradle.properties`: Added `kotlin.incremental=false` to resolve cross-drive Kotlin compilation caching issues on Windows.

### Tests (`test/`)
- `test/sse_parser_test.dart`: Verifies SSE parsing, chunk buffering, multiple lines, format exceptions, and DONE closing.
- `test/chat_service_test.dart`: Verifies models listing, stream completions, and CancelToken connection cancel.
- `test/search_service_test.dart`: Verifies 9Router search and SearXNG fallback on errors.

---

## Current State
- **SSE & Net Service**: Fully implemented, tested, and verified clean.
- **Unit Tests**: Added 12 new tests. The total test suite has 69/69 tests passing.
- **Static Analysis**: `flutter analyze` reports 0 warnings/errors.
- **Build Check**: `flutter build apk --debug` succeeds and compiles clean.

---

## Technical Decisions
1. **Slash-Safe URLs**: Standardized base URL construction to prevent double slashes (e.g. `$baseUrl/chat/completions` after stripping trailing slash).
2. **Uint8List Stream Conversion**: Updated `SseDecoder` to transform `Stream<Uint8List>` to fit Dio's default stream response type, mapping test data via `Uint8List.fromList`.
3. **Robust Vision Base64 Conversion**: Converts `ChatMessage.imagePath` to a base64 Data URI on the fly, with error handling falling back to the path string.
4. **Resilient Search Response Parsing**: Parses dynamic response formats (Map/List/JSON strings) to handle different schemas from 9Router and SearXNG.
5. **Gradle Cross-Drive Fix**: Disabled Kotlin incremental compilation in `gradle.properties` (`kotlin.incremental=false`) to prevent Gradle build failure due to C: drive and D: drive boundary differences.

---

## Next Steps
1. Implement the State Management Layer with Riverpod providers.
2. Build UI views (Home screen, Settings, API configuration, model selection).

---

# WORK LOG — Milestone 1: Project Initialization & Models

## Files Created/Changed
### Project Configuration & Setup
- `pubspec.yaml`: Configured all project dependencies (`flutter_riverpod`, `dio`, `sqflite`, `path_provider`, `flutter_secure_storage`, `flutter_markdown`, `highlight`, `image_picker`, `flutter_image_compress`, `uuid`, `json_annotation`, `shared_preferences`, `url_launcher`) and dev dependencies (`build_runner`, `json_serializable`, `flutter_lints`).
- `android/app/build.gradle.kts`: Configured `minSdk = 21` as required for compatibility.
- `android/app/src/main/AndroidManifest.xml`: Declared camera permission (`android.permission.CAMERA`), internet permission (`android.permission.INTERNET`), and the camera feature requirement (`android.hardware.camera`).

### Data Models (`lib/models/`)
- `api_config.dart` & `api_config.g.dart`: Stores API endpoint configs and secure storage references (`apiKeyRef`).
- `model_info.dart` & `model_info.g.dart`: Represents the model details, parses providers from slash-split IDs, maps/infers capability support (vision, tools), and deserializes OpenAI `/v1/models` responses.
- `tool_call.dart` & `tool_call.g.dart`: Structure for OpenAI-compatible function calling payload. Supports flat DB representation and standard nested API representation.
- `chat_message.dart` & `chat_message.g.dart`: Stores dialogue turn contents, role, image references, nested tool calls, and thinking processes (`reasoningContent`).
- `conversation.dart` & `conversation.g.dart`: Represents a conversation thread session with active API/model, title, pin/archive flags, and timestamps.
- `system_prompt_template.dart` & `system_prompt_template.g.dart`: Model for pre-configured prompt templates.

### Tests
- `test/model_info_test.dart`: Unit tests checking `ModelInfo` parsing, provider separation, capabilities mapping, default mapping rules, capability overrides in JSON, and JSON serialization.
- `test/model_info_stress_test.dart`: Stress and edge-case testing checking empty or invalid model IDs, nested custom provider names with multiple slashes, corrupted JSON formats, and handling of large-scale JSON inputs containing 5000+ models.
- `test/models_serialization_stress_test.dart`: Serialization/deserialization stress tests checking 10MB reasoning content payloads, 50,000-key flat JSON argument maps, deeply nested JSON argument trees, and invalid JSON strings.

---

## Current State
- **Flutter Project**: Successfully initialized with Android platform target support.
- **Dependencies**: All packages resolved and fetched successfully.
- **Gradle & Android Manifest**: Verified to have compilation minSdk 21 and the correct permissions.
- **Data Models**: Fully generated via `build_runner`.
- **Unit Tests**: Full test suite passes successfully, including all model stress tests and the resolved recursive stack limit issue.

---

## Technical Decisions
1. **Secure API Key Handling**: The `ApiConfig` model stores only `apiKeyRef` referencing `flutter_secure_storage` keys. The actual API key is never written to SQLite to protect user credentials.
2. **Provider Splitting**: Model IDs split by first slash to retrieve the provider name (e.g., `openai/azure/gpt-4o` -> provider: `openai`, modelName: `azure/gpt-4o`). If no slash exists, provider defaults to `unknown`.
3. **Flexible Tool Call Parsing**: `ToolCall`'s `fromJson` parses standard OpenAI nested structures (nested inside `"function"` map) and falls back to flat serialization, making it fully compatible with both the SQLite DAO and the OpenAI completions API.
4. **Vision & Tools Capability Inference**: If `supports_vision` / `supports_tools` (or their camelCase equivalents) are not present in `/v1/models` response, capabilities are inferred based on known model families (e.g., GPT-4o, Claude 3, Gemini 1.5, Llama 3.2 11B/90B) and keywords (e.g., `vl`, `vision`, `pixtral`, `paligemma`).
5. **Mitigation of Dart Matcher Stack Overflow**: For the 500-level deeply nested JSON arguments test in models_serialization_stress_test.dart, comparing the full map recursively with Dart's equals() matcher exceeds the default recursion stack limit. The assertion was refactored to verify deep structure via iterative map traversal, ensuring platform-independent, stable test execution without compromising verification integrity.

---

## Next Steps
1. Implement the Local Storage Layer (`database_helper.dart` and DAOs) to store conversations, messages, and API configurations.
2. Implement the Network and Service Layer (SSE Parser, Chat API, Search Service for 9Router and SearXNG).
3. Implement the State Management Layer with Riverpod providers.
4. Build the UI views (Home screen, Settings, API configuration, and model selection).

---

# WORK LOG — Milestone 2: Database & Storage

## Files Created/Changed
### Local Storage Layer (`lib/data/`)
- `database_helper.dart`: Initializes the SQLite database. Configures foreign key support, creates schemas for `api_configs`, `conversations`, `messages`, and `system_prompts`, and implements the `onUpgrade` callback to handle database schema migration (version 1 -> version 2: adding `isPinned` and `isArchived` columns to the `conversations` table).
- `conversation_dao.dart`: Handles CRUD operations for conversations, including retrieval ordered by `isPinned DESC, updatedAt DESC`.
- `message_dao.dart`: Handles CRUD operations for chat messages. Automatically serializes and deserializes the `toolCalls` list into a JSON string to fit SQLite's database representation.
- `api_config_dao.dart`: Handles CRUD operations for API configurations. Integrates secure storage and strictly enforces database privacy by writing only metadata and `apiKeyRef` to SQLite, while keeping the plaintext API keys in secure storage.

### API Key Security (`lib/services/`)
- `secure_storage_service.dart`: Wraps `flutter_secure_storage` to handle secure storage operations (`write`, `read`, `delete`, `deleteAll`, `containsKey`). Allows optional dependency injection for mock implementations during testing.

### Tests
- `test/database_test.dart`: Complete unit test coverage for the local storage and secure service layer:
  - Verifies table schemas are correctly generated on database creation.
  - Verifies the `onUpgrade` migration path from version 1 to 2 correctly adds columns to the `conversations` table.
  - Verifies CRUD operations for conversations, messages, and API configurations.
  - Mock-verifies that API keys are stored/loaded securely in secure storage and never written as plaintext to SQLite.

---

## Current State
- **Database schemas & upgrades**: Fully implemented and validated, including the correct index creation in the version 2 upgrade path.
- **DAO Operations**: Create, read, update, delete operations are fully verified, with atomic store coordination implemented on API config updates to prevent key mismatches/leaks.
- **API Key Security**: Plaintext keys never appear in SQLite storage queries, and inserting or updating configurations performs automatic rollback on secure storage if the SQLite database transaction fails.
- **Index Optimizations**: Added foreign key indexes and composite query-plan indexes to speed up message retrieval and conversation queries.
- **Unit Tests**: All unit tests pass cleanly (57/57 passing).
- **Static Analysis**: `flutter analyze` reports zero warnings or errors.

---

## Technical Decisions
1. **Version-Independent Mocking**: To mock `FlutterSecureStorage` without being vulnerable to minor changes in platform options parameters between package versions, we implemented a custom mock using Dart's `noSuchMethod` matching symbol invocations directly (`#write`, `#read`, `#delete`, etc.).
2. **SQLite Schema Migration & Upgrade Indexing**: Handled version 2 upgrade by altering the table for missing columns (`isPinned`, `isArchived`) and verifying the presence of index `idx_conversations_pinned_updated`.
3. **Atomic Coordinate Updates**: Coordinated secure storage updates and SQLite transactions in `ApiConfigDao.update` atomically. If updating `apiKeyRef` fails during the database transaction, secure storage changes are rolled back. Non-existent configuration updates throw `ArgumentError` to prevent orphan key leaks.
4. **Foreign Key and Composite Indexing**: Optimized query performance by creating a foreign key index on `apiConfigId` in conversations and a composite index `(conversationId, timestamp ASC)` on messages, resulting in optimized index-backed query plans instead of table scans.
5. **Cascading Deletes**: Configured `PRAGMA foreign_keys = ON;` in database configuration, with `ON DELETE CASCADE` defined on the messages table pointing to conversations, enabling clean cascading deletes.
6. **Tool Calls JSON Serialization**: Stored `toolCalls` inside the `messages` table as serialized JSON strings to avoid complex relational tables while preserving the structure of nested tool calls.
7. **Transaction-Safe Insert and Overwrite Rollbacks**: Enhanced ApiConfigDao with comprehensive try-catch rollback safety. On database transaction failure: (a) newly inserted keys are deleted from secure storage, and (b) overwritten keys (reusing the same key ref) are rolled back to their prior state, ensuring total synchronization between secure storage and SQLite. Added verification test cases (4c, 4d) to assert complete rollback and leak prevention under failable transaction conditions.

---

## Next Steps
1. Implement the State Management Layer with Riverpod providers.
2. Build the UI views (Home screen, Settings, API configuration, and model selection).

---

# WORK LOG — Milestone 4: Web Search & Agent Core (2026-07-12)

## Files Created/Changed
### Service & Logic Layer (`lib/services/`)
- `lib/services/agent_service.dart`: Implemented the Agent core scheduling service coordinating the web search tool calling flow (OpenAI compatibility) and manual `@search` prefix interception. Emits structured `AgentStreamEvent` updates. Fully supports stream cancellation via CancelToken at execution boundaries and completions request streams.

### Tests (`test/`)
- `test/agent_service_test.dart`: Added complete unit testing suite covering:
  - Standard streaming completions (no tool calls).
  - Automatic tool call execution (accumulating partial delta chunks, executing search, simulating/injecting assistant & tool message history, requesting follow-up completion).
  - Manual search trigger via `@search` prefix (extracting query, bypassing first completions, executing search, simulating assistant & tool message history, requesting completions).
  - Dio completion stream cancellation propagation.
  - Search execution cancellation propagation.
  - Malformed tool call arguments handling (incomplete JSON, invalid query types, missing query properties).
  - Pre-execution and active execution cancellations.
  - Empty or null inputs.
  - Concurrency (running multiple stream completions in parallel).
  - Preservation of content and reasoning (e.g. DeepSeek-R1) in assistant message before tool calls.
  - Parallel tool call execution (executing searches for all generated tool calls, yielding corresponding events, generating individual tool messages to avoid OpenAI protocol violations).
  - Empty manual search query validation (throws ArgumentError).

---

## Current State
- **Agent Service**: Fully implemented with all edge-case safeguards.
- **Unit Tests**: Added 16 new target tests. The total test suite has 85/85 tests passing successfully.
- **Static Analysis**: `flutter analyze` reports zero warnings/errors.
- **Forensic Audit**: The final forensic audit passed with a verdict of **CLEAN**.

---

## Technical Decisions
1. **Granular Event Streaming**: Defined `AgentStreamEvent` hierarchy to give presentation layer / Riverpod providers exact hooks into reasoning, content, search started, search completed, and database-ready message execution events.
2. **First-Step Content and Reasoning Preservation**: Accumulated streaming content and reasoning text before a tool call is executed. They are preserved in the generated intermediate assistant message to prevent data loss (e.g., for DeepSeek-R1 thinking steps).
3. **Parallel Tool Call Compliance**: If the model decides to invoke multiple search queries, the agent service loops through all tool calls, executing searches for all of them, yielding start/complete events for all, and generating corresponding tool response messages matching each `tool_call_id`. This strictly complies with the OpenAI protocol and prevents 400 Bad Request errors.
4. **Empty Manual Query Protection**: If the user types `@search` or `@search   ` without a query, the service throws an `ArgumentError('Search query cannot be empty')` to terminate the stream early and prevent empty search API requests.
5. **Dio and Search Cancellation checks**: Passed `CancelToken` to the Dio streams and inserted pre-emptive checks before and after asynchronous search execution, ensuring immediate execution halt when requested.
6. **Subclass-based Mocking**: Implemented lightweight stubs extending `ChatService` and `SearchService` in the test suite, avoiding mock library overhead.


