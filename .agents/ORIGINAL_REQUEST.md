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

