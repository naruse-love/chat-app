## 2026-07-11T11:04:04Z

You are worker_m2_remediation_2.
Your working directory is: d:\work\chat\.agents\worker_m2_remediation_2/
Your role is Worker (teamwork_preview_worker).
Your task is to fix the database and secure storage remediation issues identified in the Milestone 2 verification round:

1. **Fix Upgrade Migration Path**:
   In `lib/data/database_helper.dart` `_onUpgrade` (version 2 upgrade block), add:
   `await db.execute('CREATE INDEX IF NOT EXISTS idx_conversations_pinned_updated ON conversations (isPinned DESC, updatedAt DESC);');`

2. **Atomic Store Coordination**:
   In `lib/data/api_config_dao.dart` `update` method, coordinate Secure Storage and SQLite updates atomically:
   - Retrieve `oldConfig` via `getById(config.id)`. If `oldConfig == null`, throw an `ArgumentError('API configuration not found')` to prevent orphan key leaks.
   - If `config.apiKeyRef != oldConfig.apiKeyRef` (Key Migration):
     - Read the old key from secure storage if `apiKey == null`.
     - Write the key (either the new `apiKey` or the old key) under the new `config.apiKeyRef` in secure storage.
     - Execute the SQLite transaction update.
     - Catch database exceptions: delete the newly written key under `config.apiKeyRef` from secure storage (rollback) and rethrow the exception.
     - If the transaction succeeds: delete the old key reference (`oldConfig.apiKeyRef`) from secure storage.
   - If `config.apiKeyRef == oldConfig.apiKeyRef`:
     - If a new `apiKey` is provided, write it to secure storage.
     - Execute the SQLite transaction update.

3. **Index Optimizations**:
   - In `lib/data/database_helper.dart` `_onCreate` and `_onUpgrade` (version 2 upgrade block), add a foreign key index:
     `CREATE INDEX IF NOT EXISTS idx_conversations_api_config_id ON conversations (apiConfigId);`
   - In `lib/data/database_helper.dart` `_onCreate` and `_onUpgrade`, update/add a composite index on messages:
     `CREATE INDEX IF NOT EXISTS idx_messages_conversation_timestamp ON messages (conversationId, timestamp ASC);`

4. **Fix Test Warnings & Setup in test/challenger_empirical_test.dart**:
   - Remove the invalid `@override` annotation on the non-overriding member (`transaction` method inside `FailableTransaction` / `FailableDatabase`).
   - Clean up any unused variables and imports to ensure `flutter analyze` runs clean.
   - Fix the test setup for test `4b` so that it doesn't fail due to `shouldFail` throwing on the initial `getById` read instead of the update transaction. For example, modify `shouldFail` behavior in the mock failable database to allow `get` queries but throw on write transactions, or toggle `shouldFail` appropriately.

5. **Log Progress and Verify**:
   - Run `flutter analyze` and ensure 0 warnings/errors.
   - Run `flutter test` and ensure all 51 tests pass successfully.
   - Update `d:\work\chat\WORK_LOG.md` to reflect these improvements for Milestone 2.
   - Write your handoff report to `d:\work\chat\.agents\worker_m2_remediation_2\handoff.md`.
   - Send a message back to the orchestrator (conversation ID: 703354ba-fd99-497b-9676-23e08e0a74f2) when complete.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
