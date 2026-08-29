# Handoff Report — Tool Registry & Execution Engine Architect (R2)

## 1. Observation (观察)

1. **现有工具定义与硬编码现状** (`lib/services/agent_service.dart:92-189`):
   - 工具以静态 `Map<String, dynamic>` 常量形式定义（`webSearchTool`, `googleSearchTool`, `bingSearchTool`, `urlFetchTool`）。
   - `getEffectiveTools(searchBackend, {bool enableAutoSearch = true})` 依据布尔值与字符串分支返回硬编码工具 Map 列表。
2. **工具分发与执行耦合** (`lib/services/agent_service.dart:476-561` 与 `793-879`):
   - 在流式接收到 `accumulatedToolCalls` 后，通过 `if (entry.name == 'url_fetch') ... else ...` 进行硬编码分支调用。
   - 在伪 XML 兜底解析分支 (`lib/services/agent_service.dart:933-1024`) 中，存在完全相同的重复硬编码逻辑。
3. **事件体系特化** (`lib/services/agent_service.dart:30-53`):
   - 事件包括 `ToolCallStartedEvent`, `ToolCallCompletedEvent`, `UrlFetchStartedEvent`, `UrlFetchCompletedEvent`，分别特化于搜索与 `url_fetch`，无法直接支持新增数学、本地文件、MCP 协议或设备原生工具。
4. **Riverpod 状态特化** (`lib/providers/agent_provider.dart:4-17`):
   - `AgentState` 仅定义了 `isSearching`, `searchQuery`, `searchResults`, `isFetchingUrl`, `fetchingUrl`，缺乏通用的活跃工具调用状态管理 (`ActiveToolCallState`)。
5. **UI 渲染与折叠现状** (`lib/widgets/chat_bubble.dart:481-612` 与 `614-704`):
   - `_buildIntermediateAssistantPanel` 与 `_buildToolOutputPanel` 目前仅展示简单的文本与代码块，缺乏统一的分类图标、动态耗时徽章 (`Badge`)、结构化 JSON 参数折叠以及复制操作。
6. **安全与人机确认缺失**:
   - 现有工具均全自动在后台运行，没有任何权限分级（如只读 vs. 敏感写入）或人机协同确认机制（Human-in-the-Loop）。

---

## 2. Logic Chain (推理链条)

1. **解耦需求与面向对象多态契约 (由 Observation 1, 2 推导)**:
   - 由于现有工具以散落 Map 形式硬编码在 `AgentService` 中，每次增加新工具都必须修改核心调度代码，破坏了开闭原则 (OCP)。
   - 因此必须抽象出 `abstract class Tool`，封装 `name`, `description`, `parameters`, `category`, `permissionLevel`, `timeoutDuration`, `maxRetries` 与 `Future<ToolExecutionResult> execute(...)`，并将工具统一注册至 `ToolRegistry`。
2. **统一事件与响应式状态解耦 (由 Observation 3, 4 推导)**:
   - 现有的 `UrlFetchStartedEvent` 等特定事件限制了体系扩展。
   - 通过泛型化 `ToolCallStartedEvent`, `ToolCallConfirmationPendingEvent`, `ToolCallExecutingEvent`, `ToolCallCompletedEvent`, `ToolCallErrorEvent`，并重构 `AgentState` 引入 `Map<String, ActiveToolCallState>`，使 UI 与 Agent 调度完全解耦。
3. **细粒度安全与人机协同交互 (由 Observation 6 推导)**:
   - 引入 4 级安全权限矩阵 (`safe`, `readOnly`, `sensitiveConfirm`, `privilegedNative`)。
   - 当遇到 `sensitiveConfirm` 或 `privilegedNative` 等级的工具时，通过 `ToolConfirmationManager` 的异步 `Completer<ToolConfirmationDecision>` 挂起执行流，并在前端 UI 渲染交互卡片，提供「允许本次」、「本会话始终允许」与「拒绝执行」选项；用户决策后恢复流，或注入拒绝提示供 LLM 自适应纠偏。
4. **UI 卡片体验升级 (由 Observation 5 推导)**:
   - 按照 `ToolCategory` 区分配色与图标（搜索、网页、计算、文件、脚本、MCP、系统原生），并在 `ChatBubble` 中提供耗时显示、参数预览、Markdown 格式化输出与一键复制功能。
5. **工业级容错与 Token 控制 (由 Observation 1, 2 推导)**:
   - 在执行前引入参数 JSON Schema 校验，校验失败直接返回诊断信息让 LLM 自我纠错；
   - 引入指数退避重试（带抖动 Jitter）；
   - 引入 `TokenTruncationEngine` 智能头尾保留截断，解决大文本 Token 爆炸隐患；
   - 保持现有的 `toolRound >= maxToolRounds - 1` 降级总结兜底，增加重复调用防死循环检测。

---

## 3. Caveats (注意事项与局限性)

1. **MCP 协议通信依赖**：MCP 协议客户端支持（Stdio / SSE / WebSocket）在移动端主要采用 SSE / WebSocket 模式（由于 Android 沙箱 Stdio 子进程受限），后续落地需配套网络通信中间件。
2. **原生设备权限交互**：`privilegedNative` 工具（如日历、通知）在执行前除了 UI 确认卡片外，仍需配合 Flutter 原生权限请求插件（如 `permission_handler`）进行 OS 级别权限申请。
3. **测试覆盖**：重构 `AgentService` 时需确保现有的 173 个单元测试与集成测试完全向后兼容。

---

## 4. Conclusion (结论)

已完成 **R2. 可插拔工具注册中心与执行引擎架构设计**，产出了完备、详尽、可直接指导开发的架构报告 `report.md`。该架构确立了：
1. 统一面向对象 `Tool`、`ToolParameter`、`ToolExecutionResult`、`ToolRegistry` 规范；
2. 4 级安全权限矩阵与基于 `Completer` 的流式人机协同确认机制 (Human-in-the-Loop)；
3. 泛型化 `AgentStreamEvent` 事件管道与 Riverpod `ToolExecutionState` 状态模型；
4. `ChatBubble` 现代折叠工具卡片与分类视觉呈现；
5. 参数 Schema 校验、指数退避重试、Token 智能头尾截断与死循环兜底容错机制。

---

## 5. Verification Method (验证方法)

1. **架构设计报告检查**:
   - 查看文档 `D:\work\chat\.agents\explorer_engine_gen7\report.md`，确认 5 大支柱规范、类定义、状态图、时序图与代码示例完备。
2. **代码向后兼容性验证**:
   - 运行静态分析：`D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`（确认现有工程保持 0 issues）。
   - 运行测试套件：`D:\work\flutter-sdk\flutter\bin\flutter.bat test`（确认现有 173 个测试用例 100% 通过）。
