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

