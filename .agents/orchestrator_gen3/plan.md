# Execution Plan

This document details the step-by-step execution plan for building the Android AI Agent App using Flutter.

## Plan Summary
We follow the **Project Pattern** with two tracks:
1. **Implementation Track**: Decomposes the work into milestones, implements the modules, and ensures unit tests pass.
2. **E2E Testing Track**: Prepares the test infrastructure (`TEST_INFRA.md`) and compiles the E2E test cases (Tiers 1-4).

Once E2E tests are complete and code implementation is integrated, we run Phase 1 (passing all E2E tests) and Phase 2 (Adversarial Coverage Hardening via Tier 5).

## Milestone Decomposition

### Implementation Track Milestones
1. **Milestone 1: Project Init & Models (`lib/models/` & `pubspec.yaml`)**
   - Initialize Flutter app.
   - Configure dependencies (`flutter_riverpod`, `dio`, `sqflite`, `flutter_secure_storage`, etc.).
   - Implement `ModelInfo`, `ToolCall` data models.
   - Run unit tests for `ModelInfo` parsing.

2. **Milestone 2: Database & SQLite Storage (`lib/data/` & Secure Storage)**
   - Implement `DatabaseHelper` with `onUpgrade` logic.
   - Implement DAOs: `ConversationDao`, `MessageDao`, `ApiConfigDao`.
   - Secure storage wrapper for API keys.
   - Run unit tests for SQLite CRUD and secure storage mock.

3. **Milestone 3: SSE Parser & Chat Service (`lib/services/` & `lib/utils/`)**
   - Implement `SSEParser` (decoding bytes, handling incomplete chunks, end of stream).
   - Implement `ChatService` (POST `/v1/chat/completions` stream, GET `/v1/models`).
   - Run unit tests for SSE stream parser.

4. **Milestone 4: Web Search & Agent Core**
   - Implement `SearchService` (9Router search with SearXNG fallback).
   - Implement `AgentService` (web_search tool calling, `@search` prefix manual search).
   - Run unit tests for double-mode search fallback logic.

5. **Milestone 5: Image Service & Image UI**
   - Implement `ImageService` (拍照/选图, compression, saving to device file system).
   - Store path only in SQLite.
   - temporary Base64 encoding.

6. **Milestone 6: Providers & UI Screens**
   - Split providers (7 separate providers).
   - Implement `HomeScreen`, `SettingsScreen`, `ApiConfigScreen`, `ModelSelectorScreen`.
   - Implement `ChatBubble` (collapsible reasoning), `ChatInput`, `MarkdownRenderer` (syntax highlighting, copy code).
   - Run widget tests for markdown and folded reasoning toggle.

### E2E Testing Track
- Parallel task to build a requirement-driven E2E test suite (Tiers 1-4) in a test folder.
- Minimum 11 * N + max(5, N/2) tests, where N is the number of features.
- Publish `TEST_READY.md`.

### Final Integration & Verification Track
- Phase 1: Pass 100% of E2E tests (Tiers 1-4).
- Phase 2: Adversarial Coverage Hardening (Tier 5) - Challenger runs coverage tool and generates adversarial tests, Worker fixes bugs.
- Perform build check: `flutter build apk --debug`.
- Log all development steps to `WORK_LOG.md`.
