## 2026-07-11T05:56:51Z
You are a teamwork_preview_worker.
Your working directory is: d:\work\chat\.agents\worker_m2_remediation\

Your task is to implement the Milestone 2 Database & Storage Remediation fixes in the codebase:

1. **Path Dependency**: Add `path` to `pubspec.yaml` under `dev_dependencies` (it is imported in `test/database_stress_test.dart`).
2. **Static Analysis Cleanup**: Remove unused imports and variables in `test/database_injection_test.dart` and `test/database_stress_test.dart` to make `flutter analyze` exit 0.
3. **Index Coverage**: Add indexes in `lib/data/database_helper.dart` for:
   - `messages(conversationId)`: `CREATE INDEX idx_messages_conversation_id ON messages (conversationId);`
   - `conversations(isPinned, updatedAt)`: `CREATE INDEX idx_conversations_pinned_updated ON conversations (isPinned DESC, updatedAt DESC);`
4. **Foreign Key constraint**: Link `conversations.apiConfigId` to `api_configs(id)` via:
   - `FOREIGN KEY (apiConfigId) REFERENCES api_configs (id) ON DELETE CASCADE`
5. **API Config Default Integrity**: In `lib/data/api_config_dao.dart`, when inserting/updating an API config with `isDefault = true`, set all other configs' `isDefault` to `0` inside a transaction.
6. **Secure Storage Secret Leak**: In `lib/data/api_config_dao.dart` `update`, check if `config.apiKeyRef` has changed. If so, delete the old key reference from secure storage before saving the new one. Ensure that if `apiKey` is not provided (is null), but `apiKeyRef` has changed, the old key is read, saved under the new reference, and deleted from the old reference (key migration).

Run `flutter pub run build_runner build --delete-conflicting-outputs` (if needed), `flutter test`, and `flutter analyze` to verify your changes. Log the results in your handoff report.

MANDATORY INTEGRITY WARNING:
> DO NOT CHEAT. All implementations must be genuine. DO NOT
> hardcode test results, create dummy/facade implementations, or
> circumvent the intended task. A Forensic Auditor will independently
> verify your work. Integrity violations WILL be detected and your
> work WILL be rejected.

Upon completion, write a handoff report at `d:\work\chat\.agents\worker_m2_remediation\handoff.md` and send a message back.
