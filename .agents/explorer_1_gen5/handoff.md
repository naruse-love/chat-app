# Handoff Report: Requirement 1 — OpenCode Free Provider Integration

## 1. Observation

- **`lib/providers/api_config_provider.dart` (lines 53-65)**:
  `ApiConfigNotifier.loadConfigs()` queries all existing configurations using `_apiConfigDao.getAll()`. Currently, if the database has no configurations (`configs.isEmpty`), `state` remains initialized with empty `configs` list and `activeConfig` as `null`.
- **`lib/data/api_config_dao.dart` (lines 12-41)**:
  `ApiConfigDao.insert(config, apiKey)` handles writing the plaintext API key into `SecureStorageService` with key `config.apiKeyRef` and updating SQLite `api_configs` table within a transaction, handling `isDefault` toggles automatically.
- **`lib/models/api_config.dart` (lines 6-21)**:
  `ApiConfig` data structure accepts `id`, `name`, `baseUrl`, `apiKeyRef`, `isDefault`, and `createdAt`.
- **`lib/services/chat_service.dart` (lines 74-110)**:
  `ChatService.getModels(baseUrl, apiKey)` formats `baseUrl` by stripping trailing slashes, appends `/models`, sends an HTTP GET request with `Authorization: Bearer $apiKey` header, and maps the returned JSON `data` array using `ModelInfo.fromApiResponse`.
- **`lib/providers/model_provider.dart` (lines 47-70)**:
  `ModelNotifier.fetchModels()` retrieves the API key via `_apiConfigDao.getApiKey` and invokes `_chatService.getModels(...)`. If a network exception or timeout occurs, it catches the error and sets `state = state.copyWith(isLoading: false, error: '获取模型失败: $e');`, leaving `state.models` empty.
- **`lib/models/model_info.dart` (lines 26-86)**:
  `ModelInfo.fromApiResponse` splits model `id` on `/`. If no slash exists (e.g. `deepseek-v4-flash-free`), `provider` defaults to `'unknown'`.
- **`test/e2e_integration_test.dart` (lines 228-230)**:
  Integration tests currently expect 1 config after calling `apiNotifier.createConfig` because initial load on fresh DB yields 0 configs.

---

## 2. Logic Chain

### 1. Default API Config Auto-Initialization
- **Where**: Inside `ApiConfigNotifier.loadConfigs()` in `lib/providers/api_config_provider.dart`.
- **When**: When `configs = await _apiConfigDao.getAll();` returns empty (`configs.isEmpty`).
- **Initialization Specifications**:
  - `id`: `'opencode_free'`
  - `name`: `'OpenCode Free'`
  - `baseUrl`: `'https://opencode.ai/zen/v1'`
  - `apiKeyRef`: `'opencode_free_api_key_ref'`
  - `apiKey`: `'opencode-free-key'` (dummy placeholder string)
  - `isDefault`: `true`
  - `createdAt`: `DateTime.now()`
- **Mechanism**: Call `await _apiConfigDao.insert(defaultConfig, 'opencode-free-key');` then re-query `getAll()` and `getDefault()`.
- **DAO & Storage Guarantee**: Calling `_apiConfigDao.insert` ensures that the plaintext placeholder key `'opencode-free-key'` is persisted to `SecureStorageService` while metadata is saved in SQLite with `isDefault = 1`.

### 2. Fetching Models via `/v1/models`
- When "OpenCode Free" is active, `ModelNotifier.fetchModels()` loads the key `'opencode-free-key'` from `SecureStorageService` and issues a GET request to `https://opencode.ai/zen/v1/models`.
- In `ModelInfo.fromApiResponse`, if an ID has no slash (e.g., `deepseek-v4-flash-free`), `provider` defaults to `'unknown'`. To ensure clean provider group headers in `ModelSelectorScreen`, `fromApiResponse` (or provider resolution) should assign `provider = 'opencode'` (or `'OpenCode'`) when `provider == 'unknown'`.

### 3. Fallback Model Metadata List on Network Failure / Offline
- When network fetch fails (socket exception, offline, or non-200 response), `ModelNotifier.fetchModels()` should populate `state.models` with a pre-configured fallback list instead of leaving `models` empty or failing completely.
- Mandatory fallback list (5 models):
  1. `deepseek-v4-flash-free`
  2. `mimo-v2.5-free`
  3. `hy3-free`
  4. `nemotron-3-ultra-free`
  5. `north-mini-code-free`
- Each fallback model should be instantiated with `provider: 'opencode'`, `supportsVision: false`, `supportsTools: true`.
- If fetch fails, `state` is set to `ModelState(models: fallbackList, selectedModel: selected ?? fallbackList.first, isLoading: false, error: null)`.

### 4. Unit Test Adjustments & Analysis
- **`test/e2e_integration_test.dart`**: Line 229 checks `apiState.configs.length == 1` after creating a custom API config. Since fresh DB auto-initializes "OpenCode Free", initial length is 1, so creating a second config makes length 2. Test expectation should be updated to `equals(2)`.
- **New Unit Tests**:
  - Verify auto-creation of "OpenCode Free" config on empty DB in `ApiConfigNotifier`.
  - Verify fallback models are returned by `ModelNotifier` when `ChatService.getModels` throws network error.

---

## 3. Caveats

- **No slash in Model IDs**: If remote endpoint returns model IDs without `/`, mapping fallback provider to `opencode` prevents grouping under an `"UNKNOWN"` header in `model_selector_screen.dart`.
- **Database Upgrades**: Existing SQLite databases with existing user configs will not be overwritten (auto-init only executes if `configs.isEmpty`).
- **Read-Only Explorer Constraint**: No source files (`lib/*`) have been modified by this Explorer.

---

## 4. Conclusion & Actionable Worker Implementation Plan

### Step-by-Step Implementation Plan for Worker:

1. **`lib/models/model_info.dart`**:
   - Add static list `static List<ModelInfo> get defaultOpenCodeFallbackModels`:
     - `deepseek-v4-flash-free`
     - `mimo-v2.5-free`
     - `hy3-free`
     - `nemotron-3-ultra-free`
     - `north-mini-code-free`
   - In `ModelInfo.fromApiResponse`, if `provider == 'unknown'`, default to `'opencode'`.

2. **`lib/providers/api_config_provider.dart`**:
   - In `ApiConfigNotifier.loadConfigs()`:
     ```dart
     var configs = await _apiConfigDao.getAll();
     if (configs.isEmpty) {
       final defaultConfig = ApiConfig(
         id: 'opencode_free',
         name: 'OpenCode Free',
         baseUrl: 'https://opencode.ai/zen/v1',
         apiKeyRef: 'opencode_free_api_key_ref',
         isDefault: true,
         createdAt: DateTime.now(),
       );
       await _apiConfigDao.insert(defaultConfig, 'opencode-free-key');
       configs = await _apiConfigDao.getAll();
     }
     ```

3. **`lib/providers/model_provider.dart`**:
   - In `ModelNotifier.fetchModels()` catch block:
     ```dart
     } catch (e) {
       final fallbackModels = ModelInfo.defaultOpenCodeFallbackModels;
       ModelInfo? selected = state.selectedModel;
       if (selected == null || !fallbackModels.any((m) => m.id == selected!.id)) {
         selected = fallbackModels.first;
       }
       state = ModelState(models: fallbackModels, selectedModel: selected, isLoading: false);
     }
     ```

4. **Tests & Verification**:
   - Update `test/e2e_integration_test.dart` line 229 assertion from `equals(1)` to `equals(2)` (or account for initial pre-populated default config).
   - Add test cases in `test/model_info_test.dart` / `test/e2e_integration_test.dart` covering OpenCode Free initialization and model fallback.

---

## 5. Verification Method

To independently verify the implementation after code edits:

1. **Run Static Analysis**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat analyze
   ```
   *Expected*: `No issues found!`

2. **Run Unit & Integration Tests**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat test
   ```
   *Expected*: All tests pass (0 failures).

3. **DB Verification**:
   Inspect DB initialization with an empty DB state and verify `api_configs` contains `OpenCode Free` with `isDefault = 1` and `SecureStorage` contains `opencode-free-key`.
