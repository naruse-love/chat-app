# Original User Request

## Initial Request — 2026-07-11T13:38:21+08:00

Build an Android AI Agent App using Flutter that connects to a 9Router (OpenAI-compatible) backend. The app supports multiple API configs, streaming chat with markdown, vision capability, and search integration.

Working directory: d:\work\chat
Integrity mode: benchmark

## Requirements

### R1. Multi-API Configuration and Secure Storage
The app must allow users to manage multiple API configurations (name, base URL, API key). API keys must be securely stored using Keystore/Keychain (via `flutter_secure_storage`). Users can choose the active configuration and select/search models retrieved from `/v1/models`.

### R2. Streaming Chat UI with Markdown & Reasoning
The chat interface must support streaming responses (with cancel capability), markdown rendering, code block syntax highlighting, and collapsible display of `reasoning_content` (thinking process).

### R3. Web Search Integration (9Router/SearXNG)
The chat agent must support web search via Tool Calling. It should prioritize 9Router's search API and fallback to SearXNG, returning structured search results to the context. It must support both manual `@search` prefix and AI-triggered automatic search.

### R4. Image Input (Vision)
Users can input images via camera or gallery. Images must be compressed and saved to the device file system (database stores path only), and sent to the API in base64 format using OpenAI Vision message structure.

### R5. Work Logging (WORK_LOG.md)
The agent team must log all development steps, design decisions, and status in `d:\work\chat\WORK_LOG.md` following the specific format described in the implementation plan.

## Verification Plan

### Automated Tests
The agent team must implement and run:
1. **Unit Tests**:
   - `ModelInfo` parsing and capability checks (e.g. vision/tools matching).
   - API config SQLite CRUD operations.
   - Encrypted storing/loading of API keys (mocking `flutter_secure_storage`).
   - SSE stream parser (chunk parsing, chunk buffer, end of stream handling).
   - `SearchService` double-mode fallback logic (mocking 9Router and SearXNG).
2. **Widget Tests**:
   - Markdown code block parsing and syntax highlighting rendering.
   - Reasoning content folded/expanded UI toggle logic.
3. **Build Check**:
   - Run `flutter build apk --debug` to ensure compilation is successful.

## Acceptance Criteria

### Code Quality and Functionality
- [ ] `flutter test` executes all unit/widget tests and passes with 100% success rate.
- [ ] `flutter build apk --debug` succeeds without errors.
- [ ] `flutter_secure_storage` is integrated and verifying that API Keys are never logged or stored as plain text in the SQLite database.
- [ ] Double-mode search fallback is implemented and unit-tested to successfully query 9Router first, then fallback to SearXNG on failures.
- [ ] Images are successfully compressed and saved to file system, with SQLite storing only file paths.

### Process Integrity
- [ ] `d:\work\chat\WORK_LOG.md` is created/updated with at least one structured entry documenting the files created/changed, current state, next steps, and technical decisions.

## Follow-up — 2026-07-11T11:10:32Z

The user has requested to pause the project after the current milestone (Milestone 2) is completed and verified CLEAN. Halt spawning any subagents for Milestone 3 (or any subsequent milestones) once Milestone 2 is successfully finalized, and pause/cancel the monitoring crons.

## Follow-up — 2026-07-12T08:51:43Z

An Android AI Agent mobile app (Flutter) connected to 9Router with support for multi-API config, local SQLite history, web search tool calling, and image inputs.

Working directory: d:\work\chat
Integrity mode: benchmark

## Background & Current State
The project has successfully implemented and verified:
- **Milestone 1**: Data models and serialization tests.
- **Milestone 2**: Local Database (SQLite) and secure credential storage (SecureStorageService) with atomic transaction rollbacks.
- **Milestone 3**: SSE stream decoding (`SseDecoder`, `SseParser`) and network API connectivity (`ChatService`).
- **Milestone 4**: Web Search and agent tool scheduling (`SearchService` and `AgentService`).
Currently, 85 unit tests are in the `test/` directory, all of which pass 100% cleanly. `lib/main.dart` is clean.

## Requirements

The teamwork subagent team must complete the remaining Milestones to deliver the full application:

### R1. Complete Milestone 5: Image Service & Image UI
- Implement an image service to pick images (camera and gallery), compress them under 1MB (max 1024px width/height), save them to the local application directory (database storing the path), and encode them to Base64 data URIs for OpenAI Vision-compatible requests.
- Integrate image selection preview and removal into the chat input interface.

### R2. Complete Milestone 6: Providers & UI Screens
- Set up state management using Riverpod with separate providers for conversations, chat sessions, API configurations, active models, tool calling/agent status, themes, and general settings.
- Implement the user interface:
  - **Home Screen**: Chat history sidebar drawer (with pin/archive options), top configuration/model switcher, message bubbles with collapsible reasoning foldouts for models like DeepSeek-R1, and a responsive input area with a "Stop Generating" cancel button.
  - **Settings Screen**: Fields for SearXNG URL, API settings, and theme options.
  - **API Config Screen**: Add/Edit/Delete API configurations with a connection test function.
  - **Model Selector Screenened**: View available models grouped by provider with capability tags (Vision/Tools).
  - **System Prompt Templates Screen**: Selection and custom editing of prompt templates.

### R3. Complete Milestone 7: End-to-End & Widget Testing
- Add thorough widget and integration tests covering user message flow, model switching, image sending, search tool triggering, and conversation pinning/archiving.
- Ensure all new features are backed by high-quality test coverage.

### R4. Complete Milestone 8: Adversarial Error Handling & Hardening
- Gracefully handle issues like lost internet connections, invalid endpoints, API rate limits, model capability mismatches (e.g. sending images to non-vision models), and corrupted database files.

## Acceptance Criteria

### Technical Requirements
- [ ] No static analysis errors: running `flutter analyze` reports 0 warnings/errors.
- [ ] Complete test pass: running `flutter test` executes all test cases (both existing and new) successfully (100% pass rate).
- [ ] Compile verification: running `flutter build apk --debug` completes with 0 errors and generates the debug APK file successfully.
- [ ] All technical decisions, changes, and progress updates must be documented in `WORK_LOG.md`.

## Follow-up — 2026-07-16T16:57:35+08:00

This project enhances the Flutter-based AI chat application by integrating a direct public OpenCode Free provider, implementing a webpage content scraper tool (`url_fetch`), and optimizing the search results retrieval and formatting.

Working directory: d:\work\chat
Integrity mode: development

## Requirements

### R1. Direct OpenCode Free Provider Integration
- Pre-populate a default API configuration in the app for "OpenCode Free" when the database is empty:
  - Base URL: `https://opencode.ai/zen/v1`
  - API Key: a dummy placeholder key
  - set as the default/active config
- In the model selection list, dynamically fetch models from the provider's `/v1/models` endpoint.
- Provide a robust fallback list of model metadata if the network request fails or when starting offline. The fallback models must include:
  - `deepseek-v4-flash-free`
  - `mimo-v2.5-free`
  - `hy3-free`
  - `nemotron-3-ultra-free`
  - `north-mini-code-free`

### R2. Webpage Full-Text Fetching (`url_fetch`)
- Create a `UrlFetchService` using Dio and the existing `html` parser package to request webpage HTML, extract plain body text (stripping scripts, styles, etc.), and limit the return size to 8000 characters.
- Add `url_fetch` tool alongside `web_search` in `AgentService` so the LLM can call both tools (standard tool calling and pseudo-XML fallback path).
- Update the home screen UI search progress card: when fetching a URL, display `"正在读取网页: [URL]..."` in the existing bottom status card by modifying `agentProvider` and `home_screen.dart`.

### R3. Web Search Optimizations
- Format search results using the optimized format:
  ```
  以下是网络搜索结果。请仔细阅读后基于这些信息回答用户问题。
  如果需要更详细的信息，请使用 url_fetch 工具读取相关页面全文。
  回答时请引用来源 URL。

  1. [Title](URL)
     摘要: snippet
  ```
- Increase SearXNG search result count by firing concurrent requests for `pageno: 1` and `pageno: 2` (safely using `Future.wait` and individual `try-catch` blocks) and deduplicating results by URL.

## Verification & Acceptance Criteria

### Automated Verification
- [ ] Running `D:\work\flutter-sdk\flutter\bin\flutter.bat test` must pass all existing tests (127/127).
- [ ] Add unit tests verifying `UrlFetchService` functionality (fetching, parsing, stripping, 8000-char truncation).
- [ ] Add unit tests verifying `SearchService` page-combining and deduplication.
- [ ] Running `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` must return 0 issues (no errors or warnings).

### Manual Acceptance Criteria
- [ ] Launching the app on a fresh DB automatically creates the "OpenCode Free" provider.
- [ ] Selecting "OpenCode Free" lists the free models.
- [ ] Perform a chat query utilizing web search works, shows the loading status correctly, formats results nicely, and allows tool-calling for `url_fetch`.

## Follow-up — 2026-08-03T21:43:57+08:00

Flutter AI Agent 移动端 App（chat-app）：实现禁用侧边栏会话列表滑动手势、在设置中增加「启用 AI 网络搜索」开关、以及全方位优化 url_fetch 网页抓取结构化元数据与搜索后端服务。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. 会话列表滑动手势禁防误删
移除 home_screen.dart 侧边栏会话列表项上的 Dismissible 滑动手势包装器，置顶、归档与删除功能统一仅通过右侧 3 点 PopUp 菜单（PopupMenuButton）操作。

### R2. 全局网络搜索控制与 Agent 工具屏蔽
在 settings_screen.dart 的【网络搜索设置】添加「启用 AI 网络搜索」开关（enableAutoSearch）。当关闭时，agent_service.dart 和 chat_provider.dart 不向大模型透传任何搜索 Tool Call (web_search / google_search / bing_search)。

### R3. url_fetch 结构化元数据提取与搜索服务优化
- url_fetch_service.dart 自动解析 HTML <title>、<meta description/author/keywords/og:*> 元数据，将 <table> 解析为 Markdown 表格，提取页面重要链接，并包装为结构化 Markdown 输出。同时强化 User-Agent 头与 403 WAF 阻断/超时/404 容错提示。
- search_service.dart 优化搜索关键词清洗与结果去重。

### R4. 项目质量与代码规范
- 遵守 AGENTS.md 规则：pubspec.yaml 版本号递增 0.01（升至 1.05.0+6）。
- 确保 flutter analyze 保持 0 issues，运行 flutter test 所有测试 100% 通过（0 failures）。
- 更新 WORK_LOG.md 与 .agents/context.md。

## Acceptance Criteria

### A1. 滑动手势
- [ ] 会话列表项滑动不再触发删除或置顶操作
- [ ] 3 点菜单保留置顶/取消置顶、归档/取消归档、删除操作且功能完全正常

### A2. 搜索控制
- [ ] 设置界面包含“启用 AI 网络搜索”开关
- [ ] 开关关闭时，AI 消息生成过程中不触发 web_search / google_search / bing_search 工具调用

### A3. 结构化网页抓取
- [ ] url_fetch 包含网页标题、Description、Author、Keywords 等元数据输出
- [ ] url_fetch 支持将 HTML 表格格式化为标准 Markdown 表格
- [ ] 网络超时/403 阻断时返回清晰友好提示

### A4. 代码与测试质量
- [ ] pubspec.yaml 版本号为 1.05.0+6
- [ ] flutter analyze 输出 No issues found!
- [ ] flutter test 所有测试用例 100% 通过（0 failures）

## Follow-up — 2026-08-28T20:38:42+08:00

对现有的 Flutter AI 聊天应用进行 Agent 工具生态体系的深度需求搜集、系统架构设计与演进路线规划，输出完备的工具能力矩阵、可插拔注册架构规范与分阶段 Milestone 工作列表。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. Agent 工具生态与需求全景搜集 (Tools Taxonomy & Inventory)
全面梳理并制定 Agent 核心工具库需求清单，至少涵盖四大维度：
1. **基础实用工具集**：高精数学/表达式计算器、精准时区与相对时间计算、实时天气查询、知识库/维基检索等；
2. **本地文件与代码执行工具**：本地文件安全读写、沙箱脚本解释执行（如 JS/Dart/Lua 等轻量沙箱）、系统剪贴板交互等；
3. **MCP (Model Context Protocol) 扩展协议支持**：评估并设计客户端连接外部本地/远程 MCP Server 动态发现与加载工具的机制；
4. **移动原生设备能力**：日历事件读写、定时提醒与本地通知、通讯录与地理位置等移动端特权功能。
对每个工具明确定义：工具名称、OpenAI Function Calling JSON Schema、输入参数、输出格式、调用权限级别与异常保底策略。

### R2. 可插拔工具注册架构与执行引擎设计 (Pluggable Tool Registry Architecture)
设计统一的 Agent 工具注册中心（Tool Registry）与调用分发架构，支持：
- 静态内置工具（如现有 search / url_fetch 及新增的基础工具）与动态外部工具（MCP / 自定义插件）的统一注册与生命周期管理；
- 细粒度的工具启用/禁用开关、UI 交互确认（针对高风险操作如文件写/日历写）；
- 工具调用过程的流式事件反馈（ToolCallStarted / Executing / Completed / Error）及 UI 折叠气泡渲染规范；
- 工具调用与容错降级机制（参数校验失败、超时重试、超限总结）。

### R3. 详细演进路线图与 Milestone 工作列表制定 (Milestone Work List)
结合现有项目架构（Riverpod、SQLite DAO、AgentService、Flutter UI），制定结构化、可执行的分阶段演进工作列表（Milestone 23 及后续里程碑），明确：
- 各 Milestone 的目标、包含的具体工具/功能清单、依赖关系、前后置条件；
- 预估的代码改动范围、测试策略与质量保障标准（保持 0 analyzer warnings & 100% 测试通过率）。

## Acceptance Criteria

### 需求与架构完备性
- [ ] 产出完整的工具需求矩阵文档，覆盖基础工具、本地与沙箱执行、MCP 扩展及移动原生四大分类，且每个工具包含合规的 JSON Schema 参数定义。
- [ ] 提供统一可插拔 Tool Registry 的架构设计与接口契约规范，涵盖工具注册、权限审查、参数校验、执行分发及 UI 状态流转。
- [ ] 产出针对 MCP (Model Context Protocol) 在 Flutter/Dart 客户端落地的可行性分析与通信协议设计（SSE / Stdio / WebSocket）。

### 工作列表与可操作性
- [ ] 制定出清晰、解耦、循序渐进的 Milestone 规划清单（从架构底座、基础工具库到 MCP/原生高级能力），且每个阶段具备明确的验收标准与测试保障方案。
- [ ] 严格遵守项目开发规范与约束（0 analyzer issues，测试 100% 通过，版本号递增策略，中文 UI 适配）。

## Follow-up — 2026-08-28T20:52:04+08:00

在 Flutter AI 聊天应用中完整实现 Milestone 23：构建统一可插拔的 ToolRegistry 架构底座，实现首批四大基础实用工具（数学计算、时区时间、天气查询、维基百科知识检索），集成 AgentLoopGuard 防死循环机制，并与现有 Agent 调度链路无缝集成。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. 可插拔工具体系架构与注册中心 (Pluggable Tool Architecture & ToolRegistry)
- 在 `lib/models/tool/` 与 `lib/services/tool_registry.dart` 中建立标准 `Tool` 抽象基类、`ToolParameter`、`ToolExecutionResult` 与 4 级安全权限模型；
- 实现 `ToolRegistry` 单例/服务，支持静态/动态工具注册、生命周期管理、根据上下文与模型能力导出 OpenAI Function Calling 规范的 JSON Schema；
- 将现有的搜索工具（`web_search`, `google_search`, `bing_search`）和网页抓取工具（`url_fetch`）无缝适配包装为标准 `Tool` 实例，保持向下兼容；
- 实现 Riverpod `toolRegistryProvider` 并在全局状态中提供响应式能力。

### R2. 首批四大内置基础实用工具实现 (Built-in Basic Tools)
完整实现以下 4 个零权限/安全（Level 0）基础工具，提供健壮的参数校验、异常捕获与 Markdown/JSON 双格式返回：
1. **`math_eval`**：支持高精度数学表达式、统计函数、三角函数、对数、开方计算与单位换算，针对除零或非法表达式提供友好错误反馈；
2. **`time_calculator`**：支持全球任意 IANA 时区当前时间查询、跨时区转换、未来/过去相对日期计算与两个时间戳之间的时间差精确计算；
3. **`weather_query`**：接入免费可靠的天气 API（如 Open-Meteo 等免 Key 开放接口），支持城市地理编码定位、实时天气状况（气温/体感/湿度/风速/天气状况）及未来 7 天逐日天气预报；
4. **`wiki_lookup`**：接入中文与英文 Wikipedia 开放 API，支持百科条目检索、智能消歧义与高可读性纯净摘要提取。

### R3. 防死循环与调用防护机制 (AgentLoopGuard)
- 实现 `AgentLoopGuard`，检测多轮工具调用链中的死循环、振荡调用（例如 A→B→A 重复调用）与连续重复入参（基于 MD5 签名）；
- 默认设置安全调用轮次上限（如 `maxToolRounds = 8`），在超限或检测到循环时强制剥离工具发起最后一次文本总结补全，杜绝 Agent 卡死。

### R4. UI 呈现与现有 Agent 调度无缝对接
- 在 `AgentService` 中无缝对接 `ToolRegistry` 统一执行分发管道；
- 支持工具调用过程事件（`ToolCallStartedEvent`, `ToolCallCompletedEvent` 等）在聊天气泡（`ChatBubble`）中以中文标题、状态芯片图标及折叠卡片形式直观渲染；
- 遵循项目现有规范：`flutter analyze` 0 issues，全套测试 100% 通过（保持原有 173 个测试全部通过并新增 Milestone 23 测试），版本号递增至 `1.08.0+9`，更新 `WORK_LOG.md` 与 `.agents/context.md`。

## Acceptance Criteria

### 功能与架构验收
- [ ] `ToolRegistry` 支持工具的注册、注销、查询、Schema 导出与统一异步分发执行；
- [ ] 4 个基础工具（`math_eval`, `time_calculator`, `weather_query`, `wiki_lookup`）均可独立正确执行并返回结构化数据与 Markdown 视图；
- [ ] 现有 `web_search`、`google_search`、`bing_search` 与 `url_fetch` 均平滑迁移至 `Tool` 体系，不破坏任何既有功能；
- [ ] `AgentLoopGuard` 能够精准识别循环调用并安全兜底。

### 自动化测试与代码质量
- [ ] 为 `ToolRegistry`、`AgentLoopGuard` 及 4 个新工具编写完整单元测试，新增测试用例 25+；
- [ ] 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat test`，所有测试用例 **100% 全部通过（0 failures）**；
- [ ] 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`，输出 **`No issues found!`**；
- [ ] 项目版本号递增为 `1.08.0+9`，并在 `WORK_LOG.md` 顶部与 `.agents/context.md` 中追加 Milestone 23 记录。
## Follow-up — 2026-08-29T13:03:35+08:00

在 Flutter AI 聊天应用中实现 Milestone 24：构建本地文件系统沙箱（PathSanitizer、文件读写/检索/删除）、Worker Isolate 代码解释执行沙箱（code_eval）、系统剪贴板工具，以及敏感工具调用的 Human-in-the-Loop 交互确认卡片框架。（注意：完成全套核心功能开发与初步静态检查，进入全面测试前暂停并汇报）。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. 本地文件系统安全沙箱与文件操作工具库 (Sandboxed File System Tools)
- 实现 `PathSanitizer` 安全路径检查器：禁止绝对路径越权与 `../` 目录遍历攻击，通过 `resolveSymbolicLinksSync()` 防范符号链接逃逸，限制单文件最大 5MB、总工作区上限 50MB；
- 实现 4 个本地文件操作标准 `Tool`：
  1. `file_read` [Level 1 只读]：安全读取沙箱内文件内容，支持按起始行/结束行分块分页读取；
  2. `file_write` [Level 2 敏感确认]：创建或覆盖/追加写入沙箱文件，生成变更 Diff 与自动版本快照；
  3. `file_list` [Level 1 只读]：递归列出沙箱目录树、文件大小与修改时间，支持通配符 glob/正则匹配；
  4. `file_delete` [Level 2 敏感确认]：安全删除指定沙箱文件或子目录；
- 在 `ToolRegistry` 中自动注册以上文件工具。

### R2. 隔离沙箱代码执行与剪贴板工具 (Code Execution Sandbox & Clipboard)
- 实现 `CodeExecutionService` 与 `code_eval` 工具 [Level 2 敏感确认]：
  - 基于独立 `Isolate.spawn` 建立隔离 Worker Isolate，支持纯 Dart/JS 轻量脚本解释执行与数据计算；
  - 设定 3000ms 硬超时机制，超时即调用 `isolate.kill(priority: Isolate.immediate)`，彻底杜绝死循环挂起 UI；
- 实现 `clipboard` 工具：
  - `clipboard_read` [Level 1 只读]：安全读取系统剪贴板文本；
  - `clipboard_write` [Level 2 敏感确认]：向系统剪贴板写入文本。

### R3. Human-in-the-Loop 交互确认卡片框架与流式事件
- 在 `AgentService` 与流式事件体系中新增 `ToolConfirmationPendingEvent` 与决策等待机制；
- 当大模型触发 Level 2 敏感工具（如 `file_write`, `file_delete`, `code_eval`, `clipboard_write`）时，拦截并挂起执行，在 UI（`ChatBubble`）中呈现交互确认卡片（包含操作类型、参数预览、Diff 变化，以及「允许执行」与「拒绝/取消」按钮）；
- 用户点击后恢复执行，若用户拒绝则向大模型返回明确的中文拒绝理由以自适应调整。

### R4. 上下文安全截断器与开发阶段暂停约束
- 实现 `RuneSafeJsonTruncator`，针对超长工具入参与返回结果进行 Unicode 字符边界保护与 JSON 语法完整性截断保护；
- **阶段性约束**：完整完成 Milestone 24 的所有数据模型、核心服务、工具类、UI 确认卡片与 Registry 接入，保证 `flutter analyze` 0 issues；开发完成且即将进入大规模编写测试/回归测试前暂停并输出成果汇报。

## Acceptance Criteria

### 架构与核心功能完备性
- [ ] `PathSanitizer`、`file_read`、`file_write`、`file_list`、`file_delete` 完整实现并注册至 `ToolRegistry`；
- [ ] `CodeExecutionService` 与 `code_eval` 能够在独立 Isolate 中安全执行并具备 3000ms 硬超时保护；
- [ ] `clipboard`（读/写）工具实现并合规集成；
- [ ] Level 2 敏感工具能够触发 `ToolConfirmationPendingEvent` 并在 UI 中渲染交互确认卡片；
- [ ] 代码通过 `flutter analyze` 静态分析（0 warnings, 0 errors），开发代码整洁合规。

## Follow-up — 2026-08-29T18:08:42+08:00

对 Milestone 24（本地文件沙箱、Isolate 代码执行沙箱、系统剪贴板工具、Human-in-the-Loop 交互确认卡片框架与安全截断器）执行全量测试套件构建、对抗性加固验证与最终交付。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. 全面构建与执行 Milestone 24 自动化测试矩阵
针对 Milestone 24 所有核心模块进行深度测试覆盖：
1. **`PathSanitizer` 安全渗透测试**：
   - 路径穿越攻击防御测试（`../../etc/passwd`、`../` 逃逸）；
   - 符号链接真实路径解析与越狱防御测试（`resolveSymbolicLinksSync`）；
   - 5MB 单文件大小上限与 50MB 总工作区配额限制测试；
2. **本地文件工具集测试 (`file_read`, `file_write`, `file_list`, `file_delete`)**：
   - 文件分页读取、行号范围读取、创建/覆盖/追加写入、Diff 快照生成、目录递归遍历与删除保护；
3. **`CodeExecutionService` & `code_eval` 隔离沙箱与超时测试**：
   - 独立 Worker Isolate 正常计算与脚本执行测试；
   - 死循环（`while(true)`）及耗时计算的 3000ms 硬超时强杀（`isolate.kill`）与资源回收测试；
4. **剪贴板工具测试 (`clipboard_read`, `clipboard_write`)**：
   - 剪贴板读写与安全隔离测试；
5. **Human-in-the-Loop 交互确认流与 UI 组件测试**：
   - `ToolConfirmationPendingEvent` 敏感工具挂起与异步决策恢复测试；
   - 用户「允许执行」与「拒绝操作」在 `AgentService` 与 `chatProvider` 中的端到端链路测试；
   - `ToolConfirmationCard` 与 `DiffViewerWidget` 差异对比组件 Widget 渲染与交互测试；
6. **`RuneSafeJsonTruncator` 字符截断测试**：
   - Unicode Code Point（Rune）字符边界完整性测试（防止 UTF-16 代理对截断乱码）与未闭合 JSON 自动修复测试。

### R2. 质量门禁与工程交付
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`，输出 **`No issues found!`**（0 error, 0 warning, 0 lint）；
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat test`，所有测试用例 **100% 全部通过（0 failures）**；
- 确保版本号更新为 `1.09.0+10`，并在 `WORK_LOG.md` 与 `.agents/context.md` 中完备记录 Milestone 24；
- 提交 Git 并成功推送至 `origin/main`。

## Follow-up — 2026-08-30T13:16:00+08:00

在 Flutter AI 聊天应用中实现 Milestone 25：构建移动端原生设备特权能力服务契约与工具库（日历日程、定时通知/闹钟、通讯录脱敏检索、GPS地理位置与逆编码）、ContactsSanitizer 隐私脱敏与防注入网关、统一权限管理层（PermissionManagerService），并全面接入 ToolRegistry 与 UI 呈现。（注意：完成全套核心功能开发并确保 `flutter analyze` 0 issues，在进入测试阶段前暂停并汇报）。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. 移动端原生设备能力抽象契约与服务层 (Native Services Abstraction)
- 在 `lib/services/native/` 中定义纯 Dart 抽象接口与默认实现：
  1. `ICalendarService`：支持日历日程查询、时间冲突检测、日程创建与删除；
  2. `INotificationService`：支持本地推送通知、精准定时提醒（精确闹钟）与取消指定通知；
  3. `IContactsService`：支持联系人模糊查询与字段脱敏过滤；
  4. `ILocationService`：支持当前 GPS 经纬度获取、地址逆编码（经纬度转地名）与正向地理编码；
- 提供纯 Dart 内存 Mock 默认实现与平台通道抽象，保证在 Headless CI/桌面环境下 100% 具备可测试性与零崩溃保障。

### R2. 隐私数据脱敏网关与防注入防护 (ContactsSanitizer)
- 实现 `ContactsSanitizer` 通讯录脱敏与安全网关：
  - 手机号强制执行 E.164 掩码脱敏（如 `+86 138****1234`）；
  - 严格白名单字段过滤（仅保留姓名、脱敏手机号、邮箱、公司）；
  - 提示词注入（Prompt Injection）字符过滤与 Markdown 转义（转义 `<tool_call>`, `<system>`, `{`, `}` 等控制符号）；
  - 单次查询最多限制返回 5 条匹配结果，杜绝隐私批量外泄。

### R3. 原生能力工具集与 ToolRegistry 注册 (Native Tools Suite)
- 完整实现以下 Level 3 原生特权标准 `Tool`：
  1. `calendar_query_events` [Level 3 Privileged]：按时间范围查询日历日程与事件详情；
  2. `calendar_create_event` [Level 3 Privileged + HITL]：创建系统日程（标题、起始结束时间、地点、提醒备注）；
  3. `notification_schedule` [Level 3 Privileged + HITL]：设定本地精准定时通知/提醒；
  4. `notification_cancel` [Level 3 Privileged]：取消/清空指定 ID 的待触发通知；
  5. `contacts_search` [Level 3 Privileged]：通过 `ContactsSanitizer` 安全脱敏检索联系人；
  6. `geolocation_get` [Level 3 Privileged]：获取当前设备经纬度坐标与粗略定位；
  7. `reverse_geocode` [Level 0 Safe / Level 1 只读]：将经纬度坐标解析为人类可读的具体街道/城市地址；
- 统一注册至 `ToolRegistry` 并支持动态启停开关与权限级别过滤。

### R4. 统一权限管理与 UI 呈现 (PermissionManagerService & UI)
- 实现 `PermissionManagerService`：统一检查与申请系统权限（日历、通知、通讯录、定位），权限被拒绝时返回清晰友好的中文降级错误，不崩溃；
- 完善 `ChatBubble` 与 `ToolConfirmationCard`：为移动原生特权工具提供专属中文图标、特权徽章及确认卡片预览；
- **阶段性约束**：完整完成 Milestone 25 的所有服务接口、脱敏网关、工具类、权限管理与 Registry/UI 接入，确保 `flutter analyze` 输出 **`No issues found!`**；在进入测试阶段前暂停并向用户汇报。

## Acceptance Criteria

### 架构与核心功能完备性
- [ ] `ICalendarService`、`INotificationService`、`IContactsService`、`ILocationService` 抽象接口与服务实现就绪；
- [ ] `ContactsSanitizer` 隐私脱敏网关（E.164 掩码、5 条限制、防注入转义）完整实现；
- [ ] 7 个移动原生工具（日历读写、通知设定/取消、通讯录、定位与逆编码）全部注册至 `ToolRegistry`；
- [ ] `PermissionManagerService` 权限检查与友好降级机制实现；
- [ ] 静态分析 `flutter analyze` 保持 **`No issues found!`**（0 errors, 0 warnings）；
- [ ] 开发完成且在进入测试阶段前暂停并输出成果汇报。

## Follow-up — 2026-08-30T10:21:35Z

对 Milestone 25（移动端原生特权能力：日历日程、定时通知、通讯录隐私脱敏检索、GPS 定位与逆编码、ContactsSanitizer 网关与权限管理层）执行全量自动化测试套件构建、对抗性加固验证与最终工程交付。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. 全面构建与执行 Milestone 25 自动化测试矩阵
针对 Milestone 25 所有核心原生服务与工具进行深度测试覆盖：
1. **`ContactsSanitizer` 隐私脱敏与安全防御测试**：
   - 手机号 E.164 格式规范化与自动掩码脱敏（`+86 138****1234`、`010-****9999`）；
   - 白名单字段过滤（确保地址、备注等隐私字段物理隔离）；
   - Prompt 注入控制字符防御与转义（`<tool_call>`, `<system>`, `[INST]`, `<｜｜DSML｜｜tool_calls>`, `{` 转 `｛`）；
   - 单次检索 5 条硬上限限制与中文截断提示测试；
2. **日历服务与日程冲突算法测试 (`ICalendarService`, `calendar_*`)**：
   - 时间重叠冲突检测算法（$S_1 < E_2 \land E_1 > S_2$）与冲突预警测试；
   - `calendar_query_events` 时间范围与关键词过滤测试；
   - `calendar_create_event` 敏感创建与 HITL 交互确认测试；
3. **通知服务与定时提醒测试 (`INotificationService`, `notification_*`)**：
   - `notification_schedule` 精准定时提醒设定与 HITL 交互测试；
   - `notification_cancel` 按 ID 取消与异常 ID 容错测试；
4. **通讯录与定位服务测试 (`IContactsService`, `ILocationService`, `geolocation_*`, `reverse_geocode`)**：
   - 通讯录多字段模糊检索与脱敏输出测试；
   - GPS 坐标获取与街道地址逆编码解析测试；
5. **统一权限管理与 UI 组件测试**：
   - `PermissionManagerService` 权限拒绝与友好中文降级提示测试；
   - `ChatBubble` 原生特权（Level 3）徽章与专属图标渲染测试；
   - `ToolConfirmationCard` 日历冲突高亮与提醒确认卡片交互测试；
6. **Headless CI 纯 Dart 稳定性保障**：
   - 确保所有原生测试在无真机/模拟器的纯命令行与 CI 环境下 100% 稳定运行。

### R2. 质量门禁与工程交付
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`，输出 **`No issues found!`**（0 error, 0 warning, 0 lint）；
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat test`，所有测试用例 **100% 全部通过（0 failures）**；
- 确保版本号更新为 `1.10.0+11`，并在 `WORK_LOG.md` 与 `.agents/context.md` 中完备记录 Milestone 25；
- 提交 Git 并成功推送至 `origin/main`。

## Acceptance Criteria

### 自动化测试与质量指标
- [ ] 所有 Milestone 25 专属测试套件（ContactsSanitizer、日历日程冲突、通知提醒、通讯录、定位逆编码、权限管理、UI 徽章）全部通过；
- [ ] 现有全部回归测试用例 100% 通过（0 failures）；
- [ ] 静态分析 `flutter analyze` 结果为 `No issues found!`；
- [ ] 变更已 commit 并 push 到 Git 远程仓库。

## Follow-up — 2026-08-31T12:46:43Z

在 Flutter AI 聊天应用中实现 Milestone 26：构建 Model Context Protocol (MCP) 客户端体系与动态工具网桥（SSE / WebSocket / Stdio 三大传输层通道、JSON-RPC 2.0 通信引擎、协议握手与心跳、动态工具/资源/Prompt 发现与调用桥接、多 Server 配置与生命周期状态管理、MCP 管理设置界面与 UI 动态标签渲染）。（注意：完成全套核心功能开发并确保 `flutter analyze` 0 issues，在进入全面测试阶段前暂停并汇报）。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. MCP 多传输通道层与 JSON-RPC 2.0 协议引擎 (MCP Transports & JSON-RPC 2.0)
- 在 `lib/services/mcp/transports/` 中构建抽象传输接口 `McpTransport` 与三大传输实现：
  1. `SseMcpTransport`：基于 HTTP SSE (Server-Sent Events) + POST 的远程 MCP 传输通道；
  2. `WebSocketMcpTransport`：基于全双工 WebSocket 的实时双向传输通道；
  3. `StdioMcpTransport`：基于本地子进程标准输入输出（`Process.start`）的本地进程传输通道（桌面端支持与优雅降级）；
- 实现 `JsonRpcEngine`：
  - 严格支持 JSON-RPC 2.0 规范（Request、Response、Notification、Error）；
  - 请求 ID 自动递增关联、10s 请求超时处理与标准错误码（`-32700`, `-32600`, `-32601`, `-32602`, `-32603`）转换。

### R2. MCP 客户端协议核心与动态工具网桥 (McpClient & Dynamic Tool Bridge)
- 实现 `McpClient` 核心客户端：
  - 握手协议协商：`initialize`（客户端 Capabilities 交换与协议版本 `2024-11-05` 协商）；
  - 心跳保活机制：`ping` 定时检测与断线重连；
  - 工具发现与调用：`tools/list` 获取远程工具清单，`tools/call` 异步执行并处理结构化返回/错误；
  - 资源与模板支持：`resources/list` / `resources/read` 及 `prompts/list` / `prompts/get`；
- 实现 `McpDynamicTool` 动态工具适配器：
  - 将远程 MCP 工具动态包装为标准 `Tool` 实例，自动添加命名空间前缀（`mcp_{serverId}_{toolName}`）；
  - 随 MCP Server 连接状态自动在 `ToolRegistry` 中动态注册与注销。

### R3. 多 Server 配置持久化与 Riverpod 状态管理 (McpProvider & Storage)
- 定义数据模型 (`lib/models/mcp/`)：
  - `McpServerConfig`：ID、名称、传输类型（SSE / WebSocket / Stdio）、URL / 命令、环境变量/请求头、自动重连、启用状态；
  - `McpServerState`：连接状态枚举（`disconnected`, `connecting`, `connected`, `error`）、已发现工具列表、错误信息；
- 实现 `McpProvider`（基于 `StateNotifier`）：
  - 支持多 MCP Server 增删改查与配置持久化；
  - 统一管理 Server 连接/断开、动态工具注入 `ToolRegistry`、连接状态监听；
  - 所有 `await` 异步后遵循 `if (!mounted) return;` 规范。

### R4. MCP 管理设置界面与 UI 动态徽章渲染 (UI & ChatBubble)
- 实现 `McpServerManagementScreen` 管理界面：
  - 支持 Server 列表展示、在线状态芯片指示、添加/编辑/删除 Server、一键连接测试与启停切换；
  - 在应用设置页（`SettingsScreen`）中提供入口跳转；
- 完善 `ChatBubble` 与 `ToolConfirmationCard`：
  - 识别动态 MCP 工具，渲染专属 `MCP: {ServerName}` 徽章、服务器来源标识与折叠卡片；
- **阶段性约束**：完整完成 Milestone 26 的所有传输层、协议引擎、客户端、动态工具适配器、Riverpod 状态管理、UI 管理界面与 ChatBubble 接入，确保 `flutter analyze` 输出 **`No issues found!`**；在进入全面测试阶段前暂停并向用户汇报。

## Acceptance Criteria

### 架构与核心功能完备性
- [ ] `McpTransport`、`SseMcpTransport`、`WebSocketMcpTransport`、`StdioMcpTransport` 与 `JsonRpcEngine` 完整实现；
- [ ] `McpClient` 支持完整的协议初始化握手（`initialize`）、心跳保活、`tools/list` 动态发现与 `tools/call` 调用；
- [ ] `McpDynamicTool` 能够将远程工具注入 `ToolRegistry`，并在断连时自动清理；
- [ ] `McpServerConfig`、`McpServerState` 与 `McpProvider` 支持多 Server 配置持久化与响应式状态管理；
- [ ] `McpServerManagementScreen` 支持可视化配置管理，`ChatBubble` 具备 MCP 专属徽章；
- [ ] 静态分析 `flutter analyze` 保持 **`No issues found!`**（0 errors, 0 warnings）；
- [ ] 开发完成且在进入全面测试阶段前暂停并输出成果汇报。

## Follow-up — 2026-09-01T01:54:46Z

对 Milestone 26（Model Context Protocol / MCP 客户端体系、SSE / WebSocket / Stdio 三大传输层通道、JSON-RPC 2.0 协议引擎、动态工具网桥、多 Server 配置持久化与 Riverpod 状态管理、MCP 管理设置界面与 UI 动态徽章）执行全量自动化测试套件构建、对抗性加固验证与最终工程交付。

Working directory: D:\work\chat
Integrity mode: development

## Requirements

### R1. 全面构建与执行 Milestone 26 自动化测试矩阵
针对 Milestone 26 所有核心模块与传输通道进行深度测试覆盖：
1. **`McpTransport` 三大传输层通道与容错测试**：
   - `SseMcpTransport`：SSE 事件流解析、分块数据重组、POST 消息发送、HTTP 异常状态码与断线重连测试；
   - `WebSocketMcpTransport`：全双工消息收发、连接中断重连与异常状态流转测试；
   - `StdioMcpTransport`：子进程标准 I/O 管道通信、进程异常退出捕获与跨平台优雅降级测试；
2. **`JsonRpcEngine` 协议引擎测试**：
   - Request ID 自动关联映射、Response 结果解析、Notification 事件分发；
   - 10s 请求超时取消机制测试；
   - 标准错误码映射测试（`-32700 Parse error`, `-32600 Invalid Request`, `-32601 Method not found`, `-32602 Invalid params`, `-32603 Internal error`）；
3. **`McpClient` 协议核心与动态工具网桥测试**：
   - 协议初始化握手测试（`initialize` Capabilities 交换与协议版本 `2024-11-05` 协商）；
   - 心跳保活测试（`ping` 超时与连接存活性探活）；
   - `tools/list` 远程工具 Schema 解析与转 OpenAI Function Calling 规范测试；
   - `tools/call` 异步远程调用、超时重试与异常兜底测试；
   - `McpDynamicTool` 动态注入 `ToolRegistry`（带 `mcp_{serverId}_{toolName}` 命名空间）与断开连接时自动清理注销测试；
4. **`McpServerDao` 数据持久化与 `McpProvider` 状态机测试**：
   - SQLite `mcp_servers` 表 CRUD 完整性与事务安全测试；
   - `McpProvider` 连接状态机流转（`disconnected` ➜ `connecting` ➜ `connected` / `error`）；
   - 多 Server 启停开关与并发连接调度测试；
5. **UI 管理界面与聊天气泡动态渲染测试**：
   - `McpServerManagementScreen` 列表渲染、新增/编辑/删除表单、连通性测试与启停切换交互测试；
   - `ChatBubble` 动态 `MCP: {ServerName}` 专属徽章、服务器来源指示与工具折叠卡片渲染测试。

### R2. 质量门禁与工程交付
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`，输出 **`No issues found!`**（0 error, 0 warning, 0 lint）；
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat test`，所有测试用例 **100% 全部通过（0 failures）**；
- 确保版本号更新为 `1.11.0+12`，并在 `WORK_LOG.md` 与 `.agents/context.md` 中完备记录 Milestone 26；
- 提交 Git 并成功推送至 `origin/main`。

## Acceptance Criteria

### 自动化测试与质量指标
- [ ] 所有 Milestone 26 专属测试套件（SSE/WS/Stdio 传输层、JsonRpcEngine、McpClient、动态工具网桥、McpServerDao、McpProvider、UI 管理界面）全部通过；
- [ ] 现有全部回归测试用例 100% 通过（0 failures）；
- [ ] 静态分析 `flutter analyze` 结果为 `No issues found!`；
- [ ] 变更已 commit 并 push 到 Git 远程仓库。




