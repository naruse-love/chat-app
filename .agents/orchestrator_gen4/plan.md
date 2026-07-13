# Milestone 6 Remediation Plan

## Objective
Remediate the 4 compilation/static analysis flaws identified in the Forensic Audit report (`d:\work\chat\.agents\auditor_m6\audit_report.md`).

## Specific Code Replacements

### 1. Fix Flaw 1 in `lib/providers/chat_provider.dart`
- **Location**: Near imports (line 7-10)
- **Action**: Add `import '../data/api_config_dao.dart';` to resolve undefined `ApiConfigDao` class.

### 2. Fix Flaw 2 in `lib/screens/model_selector_screen.dart`
- **Location**: Near line 156
- **Action**: Replace `textAlign: Center,` with `textAlign: TextAlign.center,` to resolve Type mismatch.

### 3. Fix Flaw 3 in `lib/widgets/chat_bubble.dart`
- **Location**: Near line 65
- **Action**: Replace `padding: const EdgeInsets.bottom(6.0),` with `padding: const EdgeInsets.only(bottom: 6.0),` to resolve invalid constructor.

### 4. Fix Flaw 4 in `lib/widgets/chat_bubble.dart`
- **Location**: Near line 98 / 132 (depending on file layout)
- **Action**: Replace `textColor: textColor,` passed to `MarkdownRenderer` with `textColor: theme.textTheme.bodyLarge?.copyWith(color: textColor),` to resolve parameter type mismatch.

## Verification Steps
1. Apply the replacements.
2. Run `flutter analyze` to verify zero warnings/errors.
3. Run `flutter test` to verify all tests pass.
