# Orchestrator Gen 8 Context

## Overview
- **Project**: Flutter AI Chat Application (`d:\work\chat`)
- **Parent Conversation ID**: ad9a0f53-db57-4e6d-a02b-77d650033e15
- **Task**: Milestone 23 Implementation & Verification
- **Rules Reference**: `D:\work\chat\.agents\AGENTS.md`
- **Context Reference**: `D:\work\chat\.agents\context.md`
- **Request Reference**: `D:\work\chat\.agents\ORIGINAL_REQUEST.md`

## Key Project Rules Summary
1. 100% test pass rate required on `flutter test`.
2. `flutter analyze` must report 0 issues.
3. Commit messages with standard prefixes.
4. Update `WORK_LOG.md` at top.
5. All user UI texts / error messages in Chinese.
6. Version bump required (e.g. 1.08.0+9 in pubspec.yaml).
7. Dispatch-only orchestrator rules: delegate all code modifications and terminal executions to subagents.
