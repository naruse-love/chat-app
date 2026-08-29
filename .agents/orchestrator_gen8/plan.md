# Milestone 23 Implementation Plan

## Objective
Implement Milestone 23: Pluggable Tool Architecture & ToolRegistry, 4 Safe Built-in Tools, AgentLoopGuard, UI Presentation & Agent Pipeline Integration.

## Milestones & Work Breakdown
1. **Phase 0: Survey & Codebase Exploration**
   - Explorer 1: Inspect existing tool implementations, models, services (`web_search`, `url_fetch`, `agent_service.dart`, riverpod providers).
   - Explorer 2: Inspect existing agent pipeline, UI presentation (`chat_bubble.dart`, event models, stream controllers), and OpenAI schema conversion.
   - Explorer 3 / Spec Miner: Extract detailed requirements from `ORIGINAL_REQUEST.md`, `AGENTS.md`, and `context.md`, checking dependencies, test infrastructure, and constraints.
2. **Phase 1: Architecture & PROJECT.md**
   - Synthesize survey findings into `PROJECT.md` with Feature Inventory, Milestone definitions, and Interface Contracts.
3. **Phase 2: Implementation & Verification Track (M23.1 - M23.4)**
   - M23.1: Tool Base Class, ToolParameter, ToolExecutionResult, ToolRegistry, Permission Levels, Riverpod integration, and legacy tool adapter.
   - M23.2: 4 Safe Built-in Tools (`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`).
   - M23.3: `AgentLoopGuard` (loop/oscillation/duplicate detection, maxToolRounds fallback).
   - M23.4: `AgentService` integration, `ChatBubble` event rendering with Chinese titles/status chips/collapsible cards.
4. **Phase 3: E2E Testing, Adversarial Verification & Integrity Audit**
   - Ensure all 173+ existing tests pass, add 25+ comprehensive new tests for M23.
   - Reviewer, Challenger, and Forensic Auditor verification.
5. **Phase 4: Finalization**
   - Update `pubspec.yaml` (1.08.0+9), `WORK_LOG.md`, `context.md`.
   - Run full `flutter analyze` (0 issues) and `flutter test` (100% pass).
   - Deliver final report to Parent.
