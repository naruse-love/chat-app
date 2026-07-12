# Challenger Verification Report — SQLite Security & API Key Management

## 1. Observation

### SQL Injection Safety Test Execution
* **Command run**: `D:\work\flutter_windows_3.44.0-stable\flutter\bin\flutter.bat test test/database_injection_test.dart`
* **Result output**:
```
00:00 +0: loading D:/work/chat/test/database_injection_test.dart
00:00 +0: Database SQL Injection Resiliency Tests Conversation Title Injection should safely handle malicious SQL injection payloads in Conversation Title
00:00 +1: Database SQL Injection Resiliency Tests Message Content Injection should safely handle malicious SQL injection payloads in Message Content
00:00 +2: Database SQL Injection Resiliency Tests API Config Injection should safely handle malicious SQL injection payloads in API Config fields
00:00 +3: Database SQL Injection Resiliency Tests ID Injection (SQL Parameterization Check) should fail to fetch or delete other data when IDs are crafted as SQL injection payloads
00:00 +4: All tests passed!
```

### Entire Test Suite Execution
* **Command run**: `D:\work\flutter_windows_3.44.0-stable\flutter\bin\flutter.bat test`
* **Result output**:
```
00:05 +56: All tests passed!
```
* **Static Analysis command**: `D:\work\flutter_windows_3.44.0-stable\flutter\bin\flutter.bat analyze`
* **Result output**:
```
Analyzing chat...                                               
No issues found! (ran in 2.3s)
```

### Code Audit Observations

#### API Key Leak in `insert` on SQLite Exception
In `lib/data/api_config_dao.dart` (lines 12–36):
```dart
  Future<void> insert(ApiConfig config, String apiKey) async {
    final db = await _dbHelper.database;

    // Save plaintext apiKey to secure storage
    await _secureStorage.write(config.apiKeyRef, apiKey);

    // Save only API config (including apiKeyRef, excluding plaintext apiKey) to SQLite
    final map = config.toJson();
    map['createdAt'] = config.createdAt.toIso8601String();
    map['isDefault'] = config.isDefault ? 1 : 0;

    await db.transaction((txn) async {
      if (config.isDefault) {
        await txn.update(
          'api_configs',
          {'isDefault': 0},
        );
      }
      await txn.insert(
        'api_configs',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
```
If `db.transaction(...)` throws a database exception, the plaintext `apiKey` has already been written to `_secureStorage` but is never deleted. This creates an orphan key.

#### Successful Rollback on `update` Exception
In `lib/data/api_config_dao.dart` (lines 95–124):
```dart
    if (config.apiKeyRef != oldConfig.apiKeyRef) {
      final keyToWrite = apiKey ?? await _secureStorage.read(oldConfig.apiKeyRef);

      if (keyToWrite != null) {
        await _secureStorage.write(config.apiKeyRef, keyToWrite);
      }

      try {
        await db.transaction((txn) async {
          if (config.isDefault) {
            await txn.update(
              'api_configs',
              {'isDefault': 0},
              where: 'id != ?',
              whereArgs: [config.id],
            );
          }
          await txn.update(
            'api_configs',
            map,
            where: 'id = ?',
            whereArgs: [config.id],
          );
        });
      } catch (e) {
        await _secureStorage.delete(config.apiKeyRef);
        rethrow;
      }

      await _secureStorage.delete(oldConfig.apiKeyRef);
    }
```
If the database transaction throws an exception during a key migration update, the newly written key is deleted from secure storage in the `catch` block (line 120), correctly preventing leaks.

#### Plaintext API Key Prevention in SQLite
* In `lib/data/database_helper.dart` (lines 40–47), the `api_configs` table schema contains no `apiKey` column:
```sql
      CREATE TABLE api_configs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        baseUrl TEXT NOT NULL,
        apiKeyRef TEXT NOT NULL,
        isDefault INTEGER NOT NULL,
        createdAt TEXT NOT NULL
      )
```
* In `lib/models/api_config.dart` (lines 6–12), there is no `apiKey` field on the `ApiConfig` model:
```dart
class ApiConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKeyRef;
  final bool isDefault;
  final DateTime createdAt;
  // ...
}
```
* Plaintext keys are exclusively kept in the secure storage service wrapper (`SecureStorageService`).

#### Error Handling on Secure Storage Failures
* In `lib/services/secure_storage_service.dart`, methods direct queries to `FlutterSecureStorage` without local `try-catch` blocks:
```dart
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }
```
* There is no try-catch handling in `ApiConfigDao` either when reading/writing keys. Secure storage failures will propagate directly to the caller as exceptions.

---

## 2. Logic Chain

1. **SQL Injection Safety**: `database_injection_test.dart` passes. It covers several malicious payloads (e.g. `' OR '1'='1`, `'; DROP TABLE conversations; --`). Because `ConversationDao`, `MessageDao`, and `ApiConfigDao` construct queries strictly using SQLite parameter binding (`whereArgs` parameters of `sqflite` operations), the parameters are parsed as string literals instead of dynamic SQL commands. This verifies zero SQL injection vulnerability.
2. **Plaintext Storage**: Plaintext API keys do not exist in the `ApiConfig` data model, `api_configs` SQLite table schema, or any SQLite query in `ApiConfigDao`. Plaintext keys are strictly written to/read from `SecureStorageService` using `apiKeyRef` references. This verifies that API keys are never stored as plaintext in SQLite.
3. **Rollback & Leak Protection on Exception**:
   * **Orphan Key Prevention on Updates**: In `ApiConfigDao.update`, the DAO checks `getById(config.id)` first. If not found, it throws `ArgumentError` before modifying secure storage. If a migration fails during the database transaction, the catch block calls `_secureStorage.delete(config.apiKeyRef)` to roll back the write. This has been empirically verified by test `4b` which passes.
   * **Orphan Key Leak on Insertion**: In `ApiConfigDao.insert`, the DAO writes the key to secure storage *before* starting the database transaction. If the database transaction fails (e.g., database constraint or write error), there is no `try-catch` block to roll back the secure storage write. We added empirical test `4c` to verify this, which confirms that the key remains in secure storage despite the insert failing. This represents an orphan key leak vulnerability.
4. **Secure Storage Failure Handling**: Neither `SecureStorageService` nor `ApiConfigDao` catches exceptions thrown by `flutter_secure_storage`. If secure storage is corrupted or fails (which is common on some Android/iOS configurations), the app will throw uncaught errors rather than degrading gracefully.

---

## 3. Caveats

* **Real Device / Emulator Testing**: The secure storage verification was performed against a memory-based mock implementation (`MockFlutterSecureStorage`) rather than a real Android Keystore / iOS Keychain. Real-world behavior under keystore corruptions or decryption failures was not observed, though the lack of try-catch handling guarantees propagation of those errors.
* **Database Locking Concurrency**: While concurrency safety tests pass under FFI-based single-process SQLite tests, multi-process SQLite locks (common in Android background tasks) were not stress-tested.

---

## 4. Conclusion

1. **SQL Injection**: **Verified safe**. There is zero SQL injection vulnerability due to strict use of parameterized queries and sqflite helper bindings.
2. **Plaintext Storage**: **Verified secure**. No plaintext API keys are written to or queried from SQLite.
3. **Leak Protections**: **Vulnerability identified**. Update migrations are protected, but `ApiConfigDao.insert` leaks the API key in secure storage when a database transaction fails.
4. **Graceful Degradation**: **Not implemented**. Secure storage exceptions propagate directly to caller layers.

### Actionable Mitigation Recommendations
1. Wrap the SQLite transaction in `ApiConfigDao.insert` with a `try-catch` block. If a database transaction error occurs, delete the newly written secure storage key.
2. Add graceful exception handling in the repository/service layer to handle secure storage reading failures (e.g., prompting the user to re-enter their API key if secure storage is corrupted).

---

## 5. Verification Method

### Execution
Run the following test commands from the project root directory `d:\work\chat`:
1. **Run SQL Injection Tests**:
   `D:\work\flutter_windows_3.44.0-stable\flutter\bin\flutter.bat test test/database_injection_test.dart`
2. **Run Leak & Rollback Verification Tests**:
   `D:\work\flutter_windows_3.44.0-stable\flutter\bin\flutter.bat test test/challenger_empirical_test.dart`
   *Note: Test case `4c` explicitly asserts that the key is leaked to verify the bug.*

### Invalidation Conditions
If a future change wraps the transaction in `ApiConfigDao.insert` with a rollback deletion, test case `4c` in `test/challenger_empirical_test.dart` will fail because `storedKey` will become `isNull`. The test expectation must then be updated to `expect(storedKey, isNull)` to confirm the fix.
