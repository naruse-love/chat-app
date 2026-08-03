# DISPATCH — worker_m1_gen2

## Objective
Implement Milestone 1 (Requirement R1):
Disable sidebar session list swipe gestures by removing the `Dismissible` wrapper around sidebar conversation tiles in `lib/screens/home_screen.dart`, while retaining the 3-dot popup menu (`PopupMenuButton`) for pin, archive, and delete operations.

## Working Directory
`D:\work\chat\.agents\worker_m1_gen2`

## File Ownership
- `lib/screens/home_screen.dart`
- `test/widgets_test.dart` (if test updates needed)

## Mandatory Inputs
- `D:\work\chat\.agents\ORIGINAL_REQUEST.md`
- `D:\work\chat\.agents\AGENTS.md`
- `D:\work\chat\.agents\explorer_survey_1\handoff.md`

## Requirements & Steps
1. Open `lib/screens/home_screen.dart`.
2. Locate `_buildConversationTile(Conversation c)` (around lines 655-730).
3. Remove the `Dismissible` widget wrapper (key, background, secondaryBackground, confirmDismiss).
4. Return `ListTile(...)` directly.
5. Ensure `PopupMenuButton<String>` in `ListTile.trailing` remains intact and fully functional for `'pin'`, `'archive'`, and `'delete'`.
6. Run build and tests:
   - `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`
   - `D:\work\flutter-sdk\flutter\bin\flutter.bat test`
7. Write `handoff.md` in `D:\work\chat\.agents\worker_m1_gen2\handoff.md` documenting changes, exact build/test results, and verification method.

## MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
