# Handoff Report — explorer_survey_1

## Executive Summary
Investigated codebase for requirements R1 (sidebar session list swipe removal in `home_screen.dart`) and R2 (global search toggle `enableAutoSearch` in `settings_screen.dart`, `settings_provider.dart`, `agent_service.dart`, `chat_provider.dart`). Baseline tests pass 100% (164/164), `flutter analyze` reports 0 issues.

---

## 1. Observation

### R1: Sidebar Session List Swipe Removal (`lib/screens/home_screen.dart`)
- **Location**: Lines 655–730 in `_buildConversationTile(Conversation c)`.
- **Current Code**:
```dart
  Widget _buildConversationTile(Conversation c) {
    final active = ref.watch(conversationProvider).activeConversation;
    final isSelected = active?.id == c.id;
    final theme = Theme.of(context);

    return Dismissible(
      key: Key(c.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20.0),
        child: const Icon(Icons.push_pin, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await ref.read(conversationProvider.notifier).togglePin(c.id);
          return false;
        } else {
          await ref.read(conversationProvider.notifier).deleteConversation(c.id);
          return true;
        }
      },
      child: ListTile(
        title: Text(c.title, ...),
        selected: isSelected,
        ...
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (value) async {
            if (value == 'pin') {
              await ref.read(conversationProvider.notifier).togglePin(c.id);
            } else if (value == 'archive') {
              await ref.read(conversationProvider.notifier).toggleArchive(c.id);
            } else if (value == 'delete') {
              await ref.read(conversationProvider.notifier).deleteConversation(c.id);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'pin', child: Text(c.isPinned ? '取消置顶' : '置顶')),
            PopupMenuItem(value: 'archive', child: Text(c.isArchived ? '取消归档' : '归档')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () { ... },
      ),
    );
  }
```

### R2: Global Web Search Toggle & Agent Tool Filtering
- **`lib/providers/settings_provider.dart`**:
  - `AppSettings` already defines `final bool enableAutoSearch;` (default `true`) at lines 13, 25, 38, 50.
  - `SettingsNotifier` already includes `updateEnableAutoSearch(bool enabled)` at lines 121–127 and persists it via `SharedPreferences` (`_autoSearchKey = 'enable_auto_search'`).
- **`lib/screens/settings_screen.dart`**:
  - Under `网络搜索设置` (lines 120–130), there is currently NO switch for `enableAutoSearch`.
- **`lib/services/agent_service.dart`**:
  - Line 167: `static List<Map<String, dynamic>> getEffectiveTools(String searchBackend)` returns search tools (`webSearchTool`, `googleSearchTool`, `bingSearchTool`) and `urlFetchTool`.
  - Line 259: `chatAndSearchStream` entry point currently accepts `searchBackend`, `searxngUrl`, etc., but does NOT accept `enableAutoSearch`.
  - Lines 644–780: `_streamCompletionsLoop` passes `tools` to `_chatService.chatCompletionsStream`.
  - Lines 918–1018: Pseudo-XML fallback parses XML tool calls for search functions.
- **`lib/providers/chat_provider.dart`**:
  - Lines 315–329: `_startStreaming` calls `_agentService.chatAndSearchStream(...)`. It reads `settings` from `settingsProvider` but does not currently pass `enableAutoSearch`.

---

## 2. Logic Chain

### R1 Logic Chain
1. **Observation**: `_buildConversationTile` wraps `ListTile` in a `Dismissible` widget.
2. **Reasoning**: `Dismissible` handles touch drag/swipe events (left/right) on sidebar list items. Removing `Dismissible` and returning `ListTile` directly eliminates all swipe gestures and accidental deletions/pins.
3. **Reasoning**: The `ListTile` widget contains `PopupMenuButton<String>` in its `trailing` property, offering options `'pin'`, `'archive'`, and `'delete'`.
4. **Conclusion**: Removing `Dismissible` while leaving `ListTile` intact fully preserves pin, archive, and delete operations via the 3-dot popup menu.

### R2 Logic Chain
1. **Observation**: `AppSettings` and `SettingsNotifier` in `settings_provider.dart` already manage `enableAutoSearch` state and `SharedPreferences` persistence.
2. **Reasoning**: Adding a `SwitchListTile` bound to `settings.enableAutoSearch` and `notifier.updateEnableAutoSearch` in `settings_screen.dart` provides the required UI control.
3. **Reasoning**: `ChatNotifier._startStreaming` in `chat_provider.dart` must pass `enableAutoSearch: settings.enableAutoSearch` to `_agentService.chatAndSearchStream`.
4. **Reasoning**: `AgentService.getEffectiveTools(searchBackend, {bool enableAutoSearch = true})` must filter out any tool whose function name is `'web_search'`, `'google_search'`, or `'bing_search'` when `enableAutoSearch == false`.
5. **Reasoning**: `AgentService.chatAndSearchStream`, `_streamCompletions`, and `_streamCompletionsLoop` must accept and propagate `enableAutoSearch`. In pseudo-XML fallback, if `enableAutoSearch == false`, search pseudo-XML calls (`web_search`, `google_search`, `bing_search`) will not be executed.
6. **Conclusion**: When `enableAutoSearch == false`, no search tools (`web_search` / `google_search` / `bing_search`) are included in the tool definitions sent to the LLM or executed during stream processing.

---

## 3. Caveats

1. **`url_fetch` Tool**: Requirement R2 states: "不向大模型透传任何搜索 Tool Call (web_search / google_search / bing_search)". `url_fetch` is a webpage content fetch tool, not a search tool. Therefore, `url_fetch` remains in effective tools unless all auto-tools are disabled.
2. **Manual Search (`@search`)**: User typing `@search query` explicitly triggers manual search, which is an explicit user command rather than an AI-triggered automatic search tool call.
3. **Existing Tests**: 164 existing tests pass cleanly. New tests must be added without breaking existing test assertions.

---

## 4. Conclusion

The exact changes required for implementation are:

1. **`lib/screens/home_screen.dart`**:
   - In `_buildConversationTile(Conversation c)`, remove `Dismissible` widget wrapper and directly return `ListTile(...)`.

2. **`lib/screens/settings_screen.dart`**:
   - Under `网络搜索设置`, add:
     ```dart
     SwitchListTile(
       title: const Text('启用 AI 网络搜索'),
       subtitle: const Text('允许 AI 根据需要自动触发网络搜索工具'),
       value: settings.enableAutoSearch,
       onChanged: (bool value) {
         notifier.updateEnableAutoSearch(value);
       },
     ),
     ```

3. **`lib/services/agent_service.dart`**:
   - Update `getEffectiveTools(String searchBackend, {bool enableAutoSearch = true})`:
     ```dart
     static List<Map<String, dynamic>> getEffectiveTools(String searchBackend, {bool enableAutoSearch = true}) {
       List<Map<String, dynamic>> tools;
       switch (searchBackend) {
         case 'google':
           tools = [googleSearchTool, urlFetchTool];
           break;
         case 'bing':
           tools = [bingSearchTool, urlFetchTool];
           break;
         case 'google_bing':
           tools = [googleSearchTool, bingSearchTool, urlFetchTool];
           break;
         case 'searxng':
         default:
           tools = [webSearchTool, urlFetchTool];
           break;
       }
       if (!enableAutoSearch) {
         tools = tools.where((t) {
           final name = t['function']?['name'];
           return name != 'web_search' && name != 'google_search' && name != 'bing_search';
         }).toList();
       }
       return tools;
     }
     ```
   - Update `chatAndSearchStream`, `_streamCompletions`, `_streamCompletionsLoop` parameters to accept `bool enableAutoSearch = true` and pass `enableAutoSearch: enableAutoSearch` to `getEffectiveTools`.
   - In `_streamCompletionsLoop` pseudo-XML handling, filter/bypass search pseudo-XML calls when `enableAutoSearch == false`.

4. **`lib/providers/chat_provider.dart`**:
   - In `_startStreaming`, pass `enableAutoSearch: settings.enableAutoSearch` to `chatAndSearchStream`.

5. **Test updates in `test/`**:
   - In `test/agent_service_test.dart`: add tests for `getEffectiveTools` with `enableAutoSearch: false` and `chatAndSearchStream` with `enableAutoSearch: false`.
   - Add widget tests for `SettingsScreen` switch and `HomeScreen` sidebar menu tiles without `Dismissible`.

---

## 5. Verification Method

1. **Static Analysis Verification**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat analyze
   ```
   Must return `No issues found!`.

2. **Automated Test Verification**:
   ```bash
   D:\work\flutter-sdk\flutter\bin\flutter.bat test
   ```
   Must pass all tests (100% pass rate, 0 failures).

3. **Code Inspection**:
   - Verify `Dismissible` is absent in `lib/screens/home_screen.dart`.
   - Verify `SwitchListTile` for `enableAutoSearch` exists in `lib/screens/settings_screen.dart`.
   - Verify `web_search`/`google_search`/`bing_search` are excluded from tools when `enableAutoSearch == false` in `agent_service.dart`.
