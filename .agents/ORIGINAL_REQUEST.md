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

## Acceptance Criteria

### 自动化测试与质量指标
- [ ] 所有 Milestone 24 专属测试套件（PathSanitizer、文件工具、Isolate 超时强杀、剪贴板、HITL 确认卡片、DiffViewer、RuneSafeTruncator）全部通过；
- [ ] 现有全部回归测试用例 100% 通过（0 failures）；
- [ ] 静态分析 `flutter analyze` 结果为 `No issues found!`；
- [ ] 变更已 commit 并 push 到 Git 远程仓库。

