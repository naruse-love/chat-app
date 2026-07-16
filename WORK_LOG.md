## 2026-07-16 Remediation: OpenCode Key Filter, CodeBlock Crash Fix & Collapsable Tool UI

### 变更内容
1. **OpenCode Free 占位密钥过滤**：在 `lib/services/chat_service.dart` 中，发起 `/v1/models` 或 `/v1/chat/completions` 请求时，如果 `apiKey` 值为占位密钥 `'opencode-free-key'`，则自动忽略不添加 `Authorization` 头部，从而支持免 Key 直连 OpenCode 服务。
2. **编辑重发崩溃修复**：在 `lib/widgets/markdown_renderer.dart` 里的 `CodeBlockWidget` 中将 `SelectableText.rich` 改为 `RichText`，解决了因消息列表快速重建、销毁带代码块的 Widget 时导致的 `_dependents.isEmpty` 断言崩溃。
3. **工具输出结果默认折叠**：在 `lib/widgets/chat_bubble.dart` 中完善 `_buildToolOutputPanel` 参数类型，为 `'tool'` 角色的消息提供默认折叠的折叠卡片 UI。
4. **自动化测试覆盖**：在 `test/widgets_test.dart` 中补充折叠卡片交互测试，并在 `test/chat_service_test.dart` 中补充 `opencode-free-key` 过滤头部的测试。

### 变更文件
- `lib/services/chat_service.dart`
- `lib/widgets/markdown_renderer.dart`
- `lib/widgets/chat_bubble.dart`
- `test/widgets_test.dart`
- `test/chat_service_test.dart`
- `WORK_LOG.md`

### 状态
- 静态分析 `flutter analyze` 报告：`No issues found!`。
- 单元测试与 Widget 测试 `flutter test` 报告：`152 / 152` 测试用例全部 100% 通过（0 failures）。

---

## 2026-07-16 Remediation: Fix missing mounted guards in StateNotifier async methods

### 变更内容
1. **StateNotifier 异步 `mounted` 保护修复**：
   - 修复 `lib/providers/api_config_provider.dart` 中 `ApiConfigNotifier` 的 `loadConfigs()`、`createConfig()`、`updateConfig()`、`deleteConfig()`、`setDefaultConfig()` 方法，在每次 `await` 数据库异步调用之后均补充 `if (!mounted) return;` 保护逻辑，彻底避免在测试 tearDown 或 ProviderContainer dispose 时抛出 `Bad state: StateNotifier.state was accessed after being disposed` 异常。
   - 对 `ConversationNotifier`、`ModelNotifier`、`SettingsNotifier`、`SystemPromptsNotifier`、`ThemeNotifier` 以及 `ChatNotifier` 的异步方法补齐 `if (!mounted) return;` 防护。
2. **测试与静态分析验证**：
   - 运行 `flutter analyze` 保持 0 问题 (`No issues found!`)。
   - 运行 `flutter test` 全部测试用例 100% 通过（0 failures）。

### 变更文件
- `lib/providers/api_config_provider.dart`
- `lib/providers/conversation_provider.dart`
- `lib/providers/model_provider.dart`
- `lib/providers/settings_provider.dart`
- `lib/providers/theme_provider.dart`
- `lib/providers/chat_provider.dart`
- `WORK_LOG.md`

---

## 2026-07-16 OpenCode Free Provider, url_fetch 网页抓取与 SearXNG 双页搜索优化

### 变更内容
1. **OpenCode Free 免费服务接入**：
   - 默认模型列表加置 `defaultOpenCodeFallbackModels` (含 `deepseek-v4-flash-free`, `mimo-v2.5-free`, `hy3-free`, `nemotron-3-ultra-free`, `north-mini-code-free`)。
   - `ModelInfo.fromApiResponse` 对于未解析出 provider 的模型默认映射为 `opencode`。
   - `ApiConfigNotifier.loadConfigs()` 在数据库配置为空时自动插入 `"OpenCode Free"` (`https://opencode.ai/zen/v1`，占位密钥 `opencode-free-key`) 并设为默认配置。
   - `ModelNotifier.fetchModels()` 在网络异常时降级为 `defaultOpenCodeFallbackModels` 保证模型选择列表可用。
2. **网页全文抓取工具 (`url_fetch`)**：
   - 新增 `UrlFetchService`，使用 Dio 发送 GET 请求（10s 超时、User-Agent 头），并利用 `package:html/parser.dart` 提取正文，自动剔除 `<script>`、`<style>`、`<noscript>` 元素，归一化空白符并截断至 8000 字符。
   - `AgentService` 定义 `url_fetch` 工具 Schema，集成 `UrlFetchStartedEvent` 与 `UrlFetchCompletedEvent`，并在标准 OpenAI `tool_calls` 和伪 XML 兜底路径中完整支持 `url_fetch` 执行。
   - `AgentNotifier` 拓展 `isFetchingUrl` 与 `fetchingUrl` 状态及 `startUrlFetch` / `completeUrlFetch` 方法。
   - `HomeScreen` 识别 `isBusy = isSearching || isFetchingUrl`，动态展示 `"正在读取网页: [URL]..."` 进度状态。
3. **网络搜索优化与双页并发**：
   - `SearchService.formatSearchResultsForContext` 提示词升级，明确指示模型阅读搜索结果并提示可使用 `url_fetch` 抓取全文，搜索结果采用 `1. [Title](URL)` Markdown 格式。
   - `SearXNG` 并发查询 `pageno: 1` 和 `pageno: 2`（`Future.wait`），各页独立 `try-catch` 隔离超时，按 URL 自动去重，提升搜索深度与容错率。
4. **测试与验证**：
   - 新增 `test/url_fetch_service_test.dart` 与 `test/opencode_free_test.dart`。
   - 更新 `test/search_service_test.dart`、`test/e2e_integration_test.dart`、`test/model_info_test.dart` 与 `test/model_info_stress_test.dart`。
   - 全部 136 个测试用例 100% 通过（0 failures），`flutter analyze` 0 issues。

### 变更文件
- `lib/models/model_info.dart`
- `lib/providers/api_config_provider.dart`
- `lib/providers/model_provider.dart`
- `lib/services/url_fetch_service.dart`
- `lib/services/agent_service.dart`
- `lib/providers/agent_provider.dart`
- `lib/providers/chat_provider.dart`
- `lib/screens/home_screen.dart`
- `lib/services/search_service.dart`
- `test/url_fetch_service_test.dart`
- `test/opencode_free_test.dart`
- `test/search_service_test.dart`
- `test/e2e_integration_test.dart`
- `test/model_info_test.dart`
- `test/model_info_stress_test.dart`
- `WORK_LOG.md`

### 状态
- **测试结果**：`flutter test` 136/136 通过（0 failures）。
- **静态分析**：`flutter analyze` No issues found!

### 技术决策
- **OpenCode 默认映射与回退**：冷启动无配置时预置 OpenCode Free 免 key 节点降低门槛；API 解析无法识别 provider 时统一挂到 `opencode` 避免分流到 `UNKNOWN`；网络断连降级至静态 5 款模型保证离权或初始化期可展示。
- **DOM 提取与节点清理**：抓取网页使用 DOM Parser 先 `remove()` 掉 `<script>`、`<style>` 与 `<noscript>` 标签再提取 `.text`，从源头过滤 CSS 样式与 JS 代码片段，提升 LLM 正文上下文纯净度。
- **SearXNG 并发双页与容错去重**：使用 `Future.wait` 并行发 `pageno=1` 与 `pageno=2` 降低总延迟，利用 `Set<String>` 保持首次出现的 URL 顺序去重；各页局部 `try-catch` 防止单页超时拖塌整个搜索。

---

## 2026-07-15 后续修复记录

### 修复内容
1. **多轮 tool calling 闭环**：当模型在第二轮 `completion` 之后再次返回 `tool_calls`（例如搜索 → 总结 → 追问）时，把 `tools` 一并回传，确保函数定义在后续请求中持续可见；针对部分模型把工具调用泄漏到 `content` 文本（伪 `<tool_call>...</tool_call>` / `<tool_use>...`）的情况，新增兜底解析器从消息正文中抽取工具调用并执行搜索，搜索结果再以 `tool` role 注入，引导模型给出最终文本。
2. **回退/编辑崩溃加固**：`MarkdownBody` 在流式与非流式阶段统一保持 `selectable: false`，规避 `RenderEditable` 在快速 diff 时的索引越界；`showDialog` 返回后 `Future.delayed(50ms)` 再触发 `dispose()` 与 `editAndResendMessage()`，让 dialog 关闭动画跑完；`ChatProvider` 新增 `mounted` 守卫，所有在异步任务尾部写状态的入口在调用前检查 `if (!mounted) return;`，避免 dispose 后 `notifyListeners` 触发重建。
3. **思考内容可读与可复制**：`ChatBubble` 的思考/折叠区改为 `SelectableText.rich` 渲染，用户可长按选中并复制；旁加一个独立"复制"按钮，直接把推理内容写入剪贴板，无需先展开。
4. **系统提示词正式接入**：主界面 `HomeScreen` 顶部新增"系统提示词"入口，`SettingsProvider` 增加 `systemPrompt` 字段并持久化到 `shared_preferences`（键 `system_prompt`）；`ChatProvider.sendMessage` / `editAndResendMessage` / `regenerateLastResponse` 在拼装 `messages` 时真正把系统提示以 `role: 'system'` 注入到第一条（与可空 `systemPrompt` 拼接后回退到模型默认 `system`），而非仅停留在 UI 占位。

### 变更文件
- `lib/services/agent_service.dart`：第二轮及之后 `completion` 透传 `tools`；增加伪 XML `<tool_call>` 兜底解析分支，命中后转写为 `tool` role 消息再回灌。
- `lib/services/chat_service.dart`：请求体始终包含 `tools` 字段；`system` 消息合并策略改为优先使用 `settings.systemPrompt`。
- `lib/providers/chat_provider.dart`：所有异步写状态路径增加 `if (!mounted) return;` 守卫；`editAndResendMessage` / `regenerateLastResponse` 注入系统提示词。
- `lib/providers/settings_provider.dart`：新增 `systemPrompt` 字段、`updateSystemPrompt()`、持久化键 `system_prompt`。
- `lib/widgets/chat_bubble.dart`：`MarkdownBody` 统一 `selectable: false`；思考区改用 `SelectableText.rich` + 独立"复制"按钮。
- `lib/screens/home_screen.dart`：新增系统提示词入口（点击弹 dialog 编辑并保存）；编辑 dialog 关闭后 `Future.delayed(50ms)` 再走 `dispose` / `editAndResendMessage`。

### 状态
- **测试结果**：`flutter test` 全部 127 个测试用例通过。
- **静态分析**：`flutter analyze` 0 issues。

### 技术决策
- **多轮 tool calling 持续可见**：OpenAI/兼容协议下，工具在某一轮被消费后，若同一会话需要再次调用，函数定义必须随之后的 `messages` 一起回传，否则模型无法重新"看见"可用工具。我们在 `AgentService` 中按"最近一次 `assistant` 消息出现 `tool_calls` 即继续带 `tools`"的策略保证这点。
- **伪 XML 兜底**：少数模型不按 OpenAI 规范输出结构化 `tool_calls`，而是把整段调用放进 `content`。我们采取"先按规范解析，失败再在 `content` 内做有限语法匹配（`<tool_call>...</tool_call>` 与 `<tool_use>...`）"的兜底策略，并限制最大匹配深度，避免误伤普通文本；解析成功后立刻执行工具并以 `tool` role 回灌，模型将基于工具结果产出最终回复。
- **`selectable: false` 长期保持**：仅在流式阶段关闭选择会引入"加载完成 → 切到可选 → 重建 → 崩溃"的二次路径；统一保持不可选更安全，可读性由思考区的 `SelectableText.rich` 单独承担。
- **`mounted` 守卫 + 50ms 缓冲**：`Future.delayed(50ms)` 跨过 dialog 关闭动画的一帧，叠加 `mounted` 守卫能同时规避"动画期 dispose"和"dispose 后 notify"两类问题，是 Flutter 社区推荐组合。
- **系统提示词注入位置**：将系统提示作为 `messages[0]`（`role: 'system'`）注入符合 OpenAI/兼容协议；与模型自带 `system` 字段合并时优先用户自定义，避免"用户写一半被覆盖"的体验割裂。

---

## 2026-07-15 修复记录

### 修复内容
1. **搜索后端重构**：停用 9Router 内置搜索接口（`/search`、`/v1/search`），统一走 SearXNG JSON API；SearXNG 作为唯一稳定主路径。
2. **实验性 Bing 搜索**：新增 `_searchBing()` 方法，直接请求 `https://www.bing.com/search` 并用 `html` 包解析结果页面；在 `SettingsScreen` 暴露 `searchBackend` 切换项（`searxng` / `bing`），用户可自选。`SettingsProvider` 持久化该选项。
3. **编辑消息再发送崩溃修复**：在 `HomeScreen` 的编辑 dialog 中，将 `TextEditingController.dispose()` 移至 `showDialog` 完全返回之后执行（原 `showDialog` 是 async，在 controller 仍被 `TextField` 持有时调用 `dispose()`，触发 `_dependents.isEmpty` 断言失败）。新增 `context.mounted` 守卫 + `Future.microtask` 让 dialog 关闭动画跑完再触发 `editAndResendMessage`。
4. **移除 Vision 本地预检**：`chat_provider` 删除 `supportsVision` 拦截与 fast-fail 逻辑，允许向任何模型发送图片；服务端返回 400 时由既有错误映射统一提示。`chat_input` 中"模型不支持视觉"提示保留，但不再阻塞发送。

### 变更文件
- `lib/services/search_service.dart`：删除 9Router 分支；新增 `_searchBing()` + `_parseBingResults()`；`search()` 通过 `searchBackend` 参数路由。
- `lib/services/agent_service.dart`：透传 `searchBackend` 到 `SearchService.search`。
- `lib/providers/settings_provider.dart`：新增 `searchBackend` 字段、持久化键 `search_backend`、`updateSearchBackend()`。
- `lib/screens/settings_screen.dart`：在搜索设置卡片加入 `searchBackend` 单选切换（`searxng` 默认 / `bing` 实验性）。
- `lib/screens/home_screen.dart`：编辑 dialog `controller.dispose()` 移至 `showDialog` 之后；`editAndResendMessage` 调用前加 `context.mounted` + `Future.microtask`。
- `lib/providers/chat_provider.dart`：移除 `supportsVision` 校验分支，仅保留通用异常格式化。

### 状态
- **测试结果**：`flutter test` 全部 120 个测试用例通过。
- **静态分析**：`flutter analyze` 0 issues。

### 技术决策
- **Bing 标注为实验性**：Bing 搜索依赖 HTML 解析，DOM 结构与反爬策略易变，可能频繁出现空结果或被拦截；为此在 `SearchException` 中把 `source: 'Bing'` 单独标记，并在 UI 切换项上提示"实验性"，默认仍为 SearXNG。
- **SearXNG 为主**：自部署 SearXNG 输出稳定 JSON、403/400 可在服务端 `settings.yml` 启用 `formats: [html, json]` 解决，是可控路径；因此作为唯一默认 backend。
- **Dialog 资源释放时机**：`TextEditingController` 必须等 `TextField`（其 `_TextFieldState` 的 `_dependents`）真正解除依赖后才能 `dispose()`；`showDialog` 返回后再 dispose 是 Flutter 社区惯用做法，配合 `mounted` 守卫进一步降低重建过程中被回收的风险。
- **Vision 拦截上移**：原 fast-fail 把"是否支持视觉"放在客户端判断，依赖模型 `architecture` / `input_modalities` / 名称启发式，误判率高；改为统一交给后端返回错误，由既有"400 / 401 / 404 / 429"映射处理，降低维护成本。

---

## 2026-07-13 修复记录

### 修复内容
1. **搜索功能增强**：定义 `SearchException` 统一处理搜索异常；针对 SearXNG JSON 格式 403 错误增加明确的中文提示；修正搜索结果错误地写入 tool message 的问题。
2. **回退稳定性修复**：引入 `ValueKey` 优化列表项渲染；修复 `MarkdownBody` 在流式输出时 `selectable=false` 导致的崩溃；优化 dialog 关闭后的 rollback 触发时机。
3. **重新生成功能**：在用户消息长按菜单中增加“重新回答”选项，并提供底部快捷按钮触发最后一条响应的重新生成。
4. **SearXNG URL 状态同步**：通过 `isLoaded` 状态位配合 `post-frame` 回调，确保 `TextEditingController` 在 URL 加载后正确回显。
5. **Vision 能力识别**：通过检查模型配置中的 `architecture` 和 `input_modalities` 字段，并结合模型名称启发式匹配，增强对视觉能力支持的识别准确度。

### 变更文件
- `lib/services/search_service.dart`
- `lib/providers/chat_provider.dart`
- `lib/widgets/chat_bubble.dart`
- `lib/widgets/chat_input.dart`
- `lib/screens/settings_screen.dart`
- `lib/models/model_info.dart`

### 状态
- **测试结果**：`flutter test` 117 个测试用例全部通过。
- **静态分析**：`flutter analyze` 0 issues。

### 技术决策
- 使用 `ValueKey` 强制 Flutter 在回退删除消息后重新构建 Widget 树，避免旧状态残留。
- 针对 `MarkdownBody` 的 `selectable` 属性，在流式传输期间禁用选择功能，以规避底层渲染引擎在文本快速变动时的索引失效崩溃。
- 采用 `WidgetsBinding.instance.addPostFrameCallback` 处理 URL 回显，确保在 UI 框架完成当前帧布局后再操作 Controller，避免在 `build` 过程中触发状态更新。

---

# WORK LOG — Milestone 9: Bug Fixes & Feature Enhancements (2026-07-13)

## Files Changed

### Bug Fixes
- `lib/services/search_service.dart`: Now tries both `/search` and `/v1/search` for 9Router; auto-appends `/search` path to SearXNG URL.
- `lib/providers/chat_provider.dart`: Added `_sendingInProgress` flag to prevent `loadMessages` listener from overwriting state during first message send. Added conversation listener logic to restore selected model from conversation's `modelId`. Extracted streaming logic into reusable `_startStreaming()` method.
- `lib/services/chat_service.dart`: Fixed tool_calls JSON format — changed from `toJson()` (wrong: `functionName`) to `toOpenAiJson()` (correct: `function.name`). Added `stream_options: {"include_usage": true}` to API requests.
- `lib/widgets/chat_input.dart`: Image picker button now always pressable; shows SnackBar hint when model doesn't support vision.
- `test/search_service_test.dart`: Updated test to match new 3-request fallback flow (2 9Router endpoints + SearXNG).

### New Features
- **Message Editing/Resend**: `lib/data/message_dao.dart` added `updateContent()` and `deleteAfter()` methods. `lib/providers/chat_provider.dart` added `editAndResendMessage()`. `lib/screens/home_screen.dart` added edit dialog.
- **Token Usage Statistics**: `lib/models/chat_message.dart` added `promptTokens`/`completionTokens` fields. `lib/services/agent_service.dart` added `UsageEvent` class and usage tracking in streams. `lib/widgets/chat_bubble.dart` displays token counts. DB schema updated to v3 with new columns.
- **Conversation Rollback/Regenerate**: `lib/providers/chat_provider.dart` added `regenerateLastResponse()` and `rollbackToMessage()`. `lib/screens/home_screen.dart` added rollback confirmation dialog. `lib/widgets/chat_bubble.dart` added long-press action menu (编辑/重新回答/从此处回退).
- `lib/data/database_helper.dart`: Updated to v3 with `promptTokens`/`completionTokens` columns and migration path.
- `lib/data/message_dao.dart`: Added `updateContent()` and `deleteAfter()` for message editing and rollback.

### Technical Decisions
1. **`toOpenAiJson()` vs `toJson()`**: ToolCall's `toJson()` uses json_serializable which outputs `{id, type, functionName, arguments}` — incompatible with OpenAI API. The dedicated `toOpenAiJson()` outputs `{id, type, function: {name, arguments}}` which matches OpenAI spec.
2. **Stream extraction**: Extracted `_startStreaming()` from `sendMessage()` to enable reuse by `editAndResendMessage()` and `regenerateLastResponse()` without duplicating streaming logic.
3. **Token tracking via `stream_options`**: Added `stream_options: {"include_usage": true}` to API requests to request token usage from compatible providers; captured via `UsageEvent` in the agent stream.

---

# WORK LOG — Milestone 8: Adversarial Error Handling & Hardening, Final Compilation (2026-07-12)

## Files Created/Changed

### Notifiers & Services (`lib/providers/`, `lib/data/`)
- `lib/providers/chat_provider.dart`: Integrated `ImageService` to compress and permanently save picked images before writing to SQLite and invoking API. Added vision capability check to fail fast if the selected model does not support image inputs. Refined exception formatting to present human-friendly error messages on network timeouts, invalid API keys (401), rate limits (429), and missing endpoints (404).
- `lib/data/database_helper.dart`: Added recovery block to database connection initialization. If database open fails (e.g. SQLite database file corruption), it deletes the corrupted file and recreates a clean database schema automatically.
- `lib/providers/conversation_provider.dart`: Added safety checks (`if (!mounted) return;`) before calling `state = ...` in async operations (`loadConversations`, `updateConversation`) to prevent "StateNotifier used after dispose" bad states during rapid navigation/disposal.

### Tests (`test/`)
- `test/adversarial_hardening_test.dart`: Added comprehensive tests verifying SQLite corruption recovery, vision capability fast-fail validation, connection timeout formatting, 401 unauthorized key formatting, and image compression error handling.

---

## Current State
- **Static Analysis**: `flutter analyze` reports **0 issues**.
- **Unit Tests**: Full suite of **108 tests passing** (100% pass rate).
- **Compilation**: Successfully compiled debug APK via `flutter build apk --debug`. Output file generated at `build/app/outputs/flutter-apk/app-debug.apk` (assembleDebug completed in 25.1s).
- **Milestones Complete**: All Milestones 1 through 8 are fully implemented, tested, and verified clean.

---

## Technical Decisions
1. **Vision Pre-Flight Check**: Prevented 400 Bad Request API errors by enforcing a pre-flight model check inside the notifier, stopping vision payloads from being dispatched to text-only LLMs.
2. **Corrupt Database Self-Healing**: Mobile app local stores can be corrupted due to OS crashes or power failure. Implementing automatic file removal and database re-creation protects the app from permanent start-up failure.
3. **User-Friendly Error Mapping**: Mapped cryptic network stack exceptions to clear, actionable guidance (e.g., API key, endpoint, network timeouts).

---

# WORK LOG — Milestone 7: End-to-End & Widget Testing (2026-07-12)

## Files Created/Changed

### Tests (`test/`)
- `test/e2e_integration_test.dart`: Added a comprehensive end-to-end provider integration test verifying complete app state, conversation management (CRUD, pinning, archiving), message streaming logic, mock API listing and agent service interactions, database persistence, and cascading deletes.

### State Management & Notifier Fixes (`lib/providers/`)
- `lib/providers/conversation_provider.dart`: Fixed a bug where `activeConversation` could not be cleared/set to `null` because `copyWith` fell back to `this.activeConversation` when passed `null`. Added a `clearActive` flag to the `copyWith` method and updated `deleteConversation` and `setActiveConversation` to allow correctly resetting active conversation to null.

---

## Current State
- **Static Analysis**: `flutter analyze` reports **0 issues**.
- **Unit Tests**: Full suite of **103 tests passing** (100%).
- **Milestones Complete**: Milestones 1 through 7 are fully implemented and verified clean.

---

## Technical Decisions
1. **Providers Asynchronous Race Fix**: Discovered and resolved a lazy-loading asynchronous race condition in Riverpod provider integration tests. Since settings and DB loading are asynchronous inside provider constructors and triggered lazily, we pre-trigger provider reading and yield control using `await Future.delayed` to let them finish initialization before making updates and assertions.
2. **Nullable State Flag**: Avoided breaking the `copyWith` signature in `ConversationState` by introducing a `clearActive` boolean flag to explicitly signal when the state should transition to a null active conversation state.

---

# WORK LOG — Milestone 5 & 6: Image Service, Providers & UI Screens (2026-07-12)

## Files Created/Changed

### Image Service (`lib/services/`)
- `lib/services/image_service.dart`: Picks images from camera/gallery via `image_picker`, compresses to <1MB (max 1024px), saves to app documents directory, and encodes to Base64 data URI for OpenAI Vision-compatible requests.

### Database Layer Update (`lib/data/`)
- `lib/data/message_dao.dart`: Updated to resolve relative image paths to absolute paths using the device's application support directory.

### State Management (`lib/providers/`)
- `lib/providers/theme_provider.dart`: Manages dark/light theme toggle.
- `lib/providers/api_config_provider.dart`: Manages API configuration CRUD with Secure Storage integration.
- `lib/providers/model_provider.dart`: Fetches and caches model lists from `/v1/models`.
- `lib/providers/conversation_provider.dart`: Manages conversation list CRUD, pin/archive, and active conversation state.
- `lib/providers/chat_provider.dart`: Manages active conversation messages, streaming state (`isGenerating`, `streamContent`, `streamReasoning`), and delegates to `AgentService`.
- `lib/providers/agent_provider.dart`: Tracks agent tool-calling state (e.g. `isSearching`, `searchQuery`).
- `lib/providers/settings_provider.dart`: Manages SearXNG URL, API timeouts, and other global settings.

### App Shell (`lib/`)
- `lib/app.dart`: `MaterialApp` with `ProviderScope`, custom slide-transition routing to `/`, `/settings`, `/settings/api_config`, `/settings/system_prompts`, `/model_selector`.
- `lib/main.dart`: Cleaned up to use `AppTheme` and `ProviderScope`.

### UI Screens (`lib/screens/`)
- `lib/screens/home_screen.dart`: Chat UI with sidebar drawer (pinned/archived conversations), top model/config switcher, `ListView.builder` message list, streaming bubble, and stop-generation button.
- `lib/screens/settings_screen.dart`: SearXNG URL, API key management links, and theme toggle.
- `lib/screens/api_config_screen.dart`: Add/Edit/Delete API configurations with connection test.
- `lib/screens/model_selector_screen.dart`: Model list grouped by provider with Vision/Tools capability chips.
- `lib/screens/system_prompt_screen.dart`: System prompt template CRUD with preview.

### Widgets (`lib/widgets/`)
- `lib/widgets/chat_bubble.dart`: Message bubbles with reasoning fold panel (`reasoning_content`), local/base64/remote image thumbnail, and role-based alignment.
- `lib/widgets/chat_input.dart`: Multi-line input with image preview panel and send/stop button.
- `lib/widgets/markdown_renderer.dart`: Streaming-aware Markdown with 100ms throttle, syntax-highlighted code blocks (via `highlight`), and one-click copy.

### Theme (`lib/theme/`)
- `lib/theme/app_theme.dart`: Dark (`#1A1A2E` base) and Light (`#F5F5F5` base) Material3 themes.

### Configuration
- `pubspec.yaml`: Added `markdown: ^7.0.0` as explicit dependency (required by `markdown_renderer.dart`).

### Tests (`test/`)
- `test/image_service_test.dart`: 355-line comprehensive tests covering image pick, compression, DB path serialization, and error pathways (added by teamwork agents).

---

## Current State
- **Static Analysis**: `flutter analyze` reports **0 issues**.
- **Unit Tests**: Full suite of **102 tests passing** (100%).
- **Milestones Complete**: 1 through 6 are fully implemented and clean.

---

## Technical Decisions
1. **Deprecated API Cleanup**: Replaced all deprecated Flutter 3.18+ APIs: `colorScheme.background → surface`, `surfaceVariant → surfaceContainerHighest`, `onBackground → onSurface`, `withOpacity() → withValues(alpha:)`.
2. **markdown as Explicit Dependency**: `flutter_markdown` transitively provides `markdown`, but importing it directly in `markdown_renderer.dart` requires declaring it in `pubspec.yaml` to satisfy `depend_on_referenced_packages` lint.
3. **Streaming Throttle**: `MarkdownRenderer` applies a 100ms throttle during streaming to avoid excessive rebuild calls and unnecessary Markdown re-parsing during token-by-token SSE delivery.
4. **Image Path Strategy**: Images are stored as relative paths in SQLite; `MessageDao` resolves them to absolute paths at runtime using `path_provider`, making the DB portable across reinstalls.

---

## Next Steps
- Milestone 7: E2E widget tests for complete chat flow, image sending, and tool calling.
- Milestone 8: Adversarial hardening (offline/rate-limit/corrupt DB scenarios).
- Final: `flutter build apk --debug` build validation.

---

# WORK LOG — Milestone 3: SSE Streaming & Chat Network Service (2026-07-12)

## Files Created/Changed
### Network & SSE Layer (`lib/services/`, `lib/utils/`)
- `lib/utils/sse_decoder.dart`: Decodes stream bytes (`Uint8List`) into UTF-8 lines, buffering incomplete lines and split multi-byte characters.
- `lib/services/sse_parser.dart`: Parses data lines, decodes JSON, and closes gracefully on `data: [DONE]`.
- `lib/services/chat_service.dart`: Integrates `/v1/chat/completions` (with cancel token, tools, and vision base64 conversion) and `/v1/models`.
- `lib/services/search_service.dart`: Dual-mode web search prioritizing 9Router search with fallback to SearXNG.
- `android/gradle.properties`: Added `kotlin.incremental=false` to resolve cross-drive Kotlin compilation caching issues on Windows.

### Tests (`test/`)
- `test/sse_parser_test.dart`: Verifies SSE parsing, chunk buffering, multiple lines, format exceptions, and DONE closing.
- `test/chat_service_test.dart`: Verifies models listing, stream completions, and CancelToken connection cancel.
- `test/search_service_test.dart`: Verifies 9Router search and SearXNG fallback on errors.

---

## Current State
- **SSE & Net Service**: Fully implemented, tested, and verified clean.
- **Unit Tests**: Added 12 new tests. The total test suite has 69/69 tests passing.
- **Static Analysis**: `flutter analyze` reports 0 warnings/errors.
- **Build Check**: `flutter build apk --debug` succeeds and compiles clean.

---

## Technical Decisions
1. **Slash-Safe URLs**: Standardized base URL construction to prevent double slashes (e.g. `$baseUrl/chat/completions` after stripping trailing slash).
2. **Uint8List Stream Conversion**: Updated `SseDecoder` to transform `Stream<Uint8List>` to fit Dio's default stream response type, mapping test data via `Uint8List.fromList`.
3. **Robust Vision Base64 Conversion**: Converts `ChatMessage.imagePath` to a base64 Data URI on the fly, with error handling falling back to the path string.
4. **Resilient Search Response Parsing**: Parses dynamic response formats (Map/List/JSON strings) to handle different schemas from 9Router and SearXNG.
5. **Gradle Cross-Drive Fix**: Disabled Kotlin incremental compilation in `gradle.properties` (`kotlin.incremental=false`) to prevent Gradle build failure due to C: drive and D: drive boundary differences.

---

## Next Steps
1. Implement the State Management Layer with Riverpod providers.
2. Build UI views (Home screen, Settings, API configuration, model selection).

---

# WORK LOG — Milestone 1: Project Initialization & Models

## Files Created/Changed
### Project Configuration & Setup
- `pubspec.yaml`: Configured all project dependencies (`flutter_riverpod`, `dio`, `sqflite`, `path_provider`, `flutter_secure_storage`, `flutter_markdown`, `highlight`, `image_picker`, `flutter_image_compress`, `uuid`, `json_annotation`, `shared_preferences`, `url_launcher`) and dev dependencies (`build_runner`, `json_serializable`, `flutter_lints`).
- `android/app/build.gradle.kts`: Configured `minSdk = 21` as required for compatibility.
- `android/app/src/main/AndroidManifest.xml`: Declared camera permission (`android.permission.CAMERA`), internet permission (`android.permission.INTERNET`), and the camera feature requirement (`android.hardware.camera`).

### Data Models (`lib/models/`)
- `api_config.dart` & `api_config.g.dart`: Stores API endpoint configs and secure storage references (`apiKeyRef`).
- `model_info.dart` & `model_info.g.dart`: Represents the model details, parses providers from slash-split IDs, maps/infers capability support (vision, tools), and deserializes OpenAI `/v1/models` responses.
- `tool_call.dart` & `tool_call.g.dart`: Structure for OpenAI-compatible function calling payload. Supports flat DB representation and standard nested API representation.
- `chat_message.dart` & `chat_message.g.dart`: Stores dialogue turn contents, role, image references, nested tool calls, and thinking processes (`reasoningContent`).
- `conversation.dart` & `conversation.g.dart`: Represents a conversation thread session with active API/model, title, pin/archive flags, and timestamps.
- `system_prompt_template.dart` & `system_prompt_template.g.dart`: Model for pre-configured prompt templates.

### Tests
- `test/model_info_test.dart`: Unit tests checking `ModelInfo` parsing, provider separation, capabilities mapping, default mapping rules, capability overrides in JSON, and JSON serialization.
- `test/model_info_stress_test.dart`: Stress and edge-case testing checking empty or invalid model IDs, nested custom provider names with multiple slashes, corrupted JSON formats, and handling of large-scale JSON inputs containing 5000+ models.
- `test/models_serialization_stress_test.dart`: Serialization/deserialization stress tests checking 10MB reasoning content payloads, 50,000-key flat JSON argument maps, deeply nested JSON argument trees, and invalid JSON strings.

---

## Current State
- **Flutter Project**: Successfully initialized with Android platform target support.
- **Dependencies**: All packages resolved and fetched successfully.
- **Gradle & Android Manifest**: Verified to have compilation minSdk 21 and the correct permissions.
- **Data Models**: Fully generated via `build_runner`.
- **Unit Tests**: Full test suite passes successfully, including all model stress tests and the resolved recursive stack limit issue.

---

## Technical Decisions
1. **Secure API Key Handling**: The `ApiConfig` model stores only `apiKeyRef` referencing `flutter_secure_storage` keys. The actual API key is never written to SQLite to protect user credentials.
2. **Provider Splitting**: Model IDs split by first slash to retrieve the provider name (e.g., `openai/azure/gpt-4o` -> provider: `openai`, modelName: `azure/gpt-4o`). If no slash exists, provider defaults to `unknown`.
3. **Flexible Tool Call Parsing**: `ToolCall`'s `fromJson` parses standard OpenAI nested structures (nested inside `"function"` map) and falls back to flat serialization, making it fully compatible with both the SQLite DAO and the OpenAI completions API.
4. **Vision & Tools Capability Inference**: If `supports_vision` / `supports_tools` (or their camelCase equivalents) are not present in `/v1/models` response, capabilities are inferred based on known model families (e.g., GPT-4o, Claude 3, Gemini 1.5, Llama 3.2 11B/90B) and keywords (e.g., `vl`, `vision`, `pixtral`, `paligemma`).
5. **Mitigation of Dart Matcher Stack Overflow**: For the 500-level deeply nested JSON arguments test in models_serialization_stress_test.dart, comparing the full map recursively with Dart's equals() matcher exceeds the default recursion stack limit. The assertion was refactored to verify deep structure via iterative map traversal, ensuring platform-independent, stable test execution without compromising verification integrity.

---

## Next Steps
1. Implement the Local Storage Layer (`database_helper.dart` and DAOs) to store conversations, messages, and API configurations.
2. Implement the Network and Service Layer (SSE Parser, Chat API, Search Service for 9Router and SearXNG).
3. Implement the State Management Layer with Riverpod providers.
4. Build the UI views (Home screen, Settings, API configuration, and model selection).

---

# WORK LOG — Milestone 2: Database & Storage

## Files Created/Changed
### Local Storage Layer (`lib/data/`)
- `database_helper.dart`: Initializes the SQLite database. Configures foreign key support, creates schemas for `api_configs`, `conversations`, `messages`, and `system_prompts`, and implements the `onUpgrade` callback to handle database schema migration (version 1 -> version 2: adding `isPinned` and `isArchived` columns to the `conversations` table).
- `conversation_dao.dart`: Handles CRUD operations for conversations, including retrieval ordered by `isPinned DESC, updatedAt DESC`.
- `message_dao.dart`: Handles CRUD operations for chat messages. Automatically serializes and deserializes the `toolCalls` list into a JSON string to fit SQLite's database representation.
- `api_config_dao.dart`: Handles CRUD operations for API configurations. Integrates secure storage and strictly enforces database privacy by writing only metadata and `apiKeyRef` to SQLite, while keeping the plaintext API keys in secure storage.

### API Key Security (`lib/services/`)
- `secure_storage_service.dart`: Wraps `flutter_secure_storage` to handle secure storage operations (`write`, `read`, `delete`, `deleteAll`, `containsKey`). Allows optional dependency injection for mock implementations during testing.

### Tests
- `test/database_test.dart`: Complete unit test coverage for the local storage and secure service layer:
  - Verifies table schemas are correctly generated on database creation.
  - Verifies the `onUpgrade` migration path from version 1 to 2 correctly adds columns to the `conversations` table.
  - Verifies CRUD operations for conversations, messages, and API configurations.
  - Mock-verifies that API keys are stored/loaded securely in secure storage and never written as plaintext to SQLite.

---

## Current State
- **Database schemas & upgrades**: Fully implemented and validated, including the correct index creation in the version 2 upgrade path.
- **DAO Operations**: Create, read, update, delete operations are fully verified, with atomic store coordination implemented on API config updates to prevent key mismatches/leaks.
- **API Key Security**: Plaintext keys never appear in SQLite storage queries, and inserting or updating configurations performs automatic rollback on secure storage if the SQLite database transaction fails.
- **Index Optimizations**: Added foreign key indexes and composite query-plan indexes to speed up message retrieval and conversation queries.
- **Unit Tests**: All unit tests pass cleanly (57/57 passing).
- **Static Analysis**: `flutter analyze` reports zero warnings or errors.

---

## Technical Decisions
1. **Version-Independent Mocking**: To mock `FlutterSecureStorage` without being vulnerable to minor changes in platform options parameters between package versions, we implemented a custom mock using Dart's `noSuchMethod` matching symbol invocations directly (`#write`, `#read`, `#delete`, etc.).
2. **SQLite Schema Migration & Upgrade Indexing**: Handled version 2 upgrade by altering the table for missing columns (`isPinned`, `isArchived`) and verifying the presence of index `idx_conversations_pinned_updated`.
3. **Atomic Coordinate Updates**: Coordinated secure storage updates and SQLite transactions in `ApiConfigDao.update` atomically. If updating `apiKeyRef` fails during the database transaction, secure storage changes are rolled back. Non-existent configuration updates throw `ArgumentError` to prevent orphan key leaks.
4. **Foreign Key and Composite Indexing**: Optimized query performance by creating a foreign key index on `apiConfigId` in conversations and a composite index `(conversationId, timestamp ASC)` on messages, resulting in optimized index-backed query plans instead of table scans.
5. **Cascading Deletes**: Configured `PRAGMA foreign_keys = ON;` in database configuration, with `ON DELETE CASCADE` defined on the messages table pointing to conversations, enabling clean cascading deletes.
6. **Tool Calls JSON Serialization**: Stored `toolCalls` inside the `messages` table as serialized JSON strings to avoid complex relational tables while preserving the structure of nested tool calls.
7. **Transaction-Safe Insert and Overwrite Rollbacks**: Enhanced ApiConfigDao with comprehensive try-catch rollback safety. On database transaction failure: (a) newly inserted keys are deleted from secure storage, and (b) overwritten keys (reusing the same key ref) are rolled back to their prior state, ensuring total synchronization between secure storage and SQLite. Added verification test cases (4c, 4d) to assert complete rollback and leak prevention under failable transaction conditions.

---

## Next Steps
1. Implement the State Management Layer with Riverpod providers.
2. Build the UI views (Home screen, Settings, API configuration, and model selection).

---

# WORK LOG — Milestone 4: Web Search & Agent Core (2026-07-12)

## Files Created/Changed
### Service & Logic Layer (`lib/services/`)
- `lib/services/agent_service.dart`: Implemented the Agent core scheduling service coordinating the web search tool calling flow (OpenAI compatibility) and manual `@search` prefix interception. Emits structured `AgentStreamEvent` updates. Fully supports stream cancellation via CancelToken at execution boundaries and completions request streams.

### Tests (`test/`)
- `test/agent_service_test.dart`: Added complete unit testing suite covering:
  - Standard streaming completions (no tool calls).
  - Automatic tool call execution (accumulating partial delta chunks, executing search, simulating/injecting assistant & tool message history, requesting follow-up completion).
  - Manual search trigger via `@search` prefix (extracting query, bypassing first completions, executing search, simulating assistant & tool message history, requesting completions).
  - Dio completion stream cancellation propagation.
  - Search execution cancellation propagation.
  - Malformed tool call arguments handling (incomplete JSON, invalid query types, missing query properties).
  - Pre-execution and active execution cancellations.
  - Empty or null inputs.
  - Concurrency (running multiple stream completions in parallel).
  - Preservation of content and reasoning (e.g. DeepSeek-R1) in assistant message before tool calls.
  - Parallel tool call execution (executing searches for all generated tool calls, yielding corresponding events, generating individual tool messages to avoid OpenAI protocol violations).
  - Empty manual search query validation (throws ArgumentError).

---

## Current State
- **Agent Service**: Fully implemented with all edge-case safeguards.
- **Unit Tests**: Added 16 new target tests. The total test suite has 85/85 tests passing successfully.
- **Static Analysis**: `flutter analyze` reports zero warnings/errors.
- **Forensic Audit**: The final forensic audit passed with a verdict of **CLEAN**.

---

## Technical Decisions
1. **Granular Event Streaming**: Defined `AgentStreamEvent` hierarchy to give presentation layer / Riverpod providers exact hooks into reasoning, content, search started, search completed, and database-ready message execution events.
2. **First-Step Content and Reasoning Preservation**: Accumulated streaming content and reasoning text before a tool call is executed. They are preserved in the generated intermediate assistant message to prevent data loss (e.g., for DeepSeek-R1 thinking steps).
3. **Parallel Tool Call Compliance**: If the model decides to invoke multiple search queries, the agent service loops through all tool calls, executing searches for all of them, yielding start/complete events for all, and generating corresponding tool response messages matching each `tool_call_id`. This strictly complies with the OpenAI protocol and prevents 400 Bad Request errors.
4. **Empty Manual Query Protection**: If the user types `@search` or `@search   ` without a query, the service throws an `ArgumentError('Search query cannot be empty')` to terminate the stream early and prevent empty search API requests.
5. **Dio and Search Cancellation checks**: Passed `CancelToken` to the Dio streams and inserted pre-emptive checks before and after asynchronous search execution, ensuring immediate execution halt when requested.
6. **Subclass-based Mocking**: Implemented lightweight stubs extending `ChatService` and `SearchService` in the test suite, avoiding mock library overhead.


