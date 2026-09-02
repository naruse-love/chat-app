# AI Agent 开发规则（AGENTS.md）
> 此文件用于为接手此项目的 AI Agent 提供开发约束、架构地图与行为规范。

---

## 📍 项目状态

**所有 Milestone（1–27）已全部完成并交付，项目目前处于稳定维护与高阶演进阶段。**

- **当前版本**：`1.19.0+20`
- **全量测试基线**：**777 / 777 全部通过（0 failures）**
- **静态分析基线**：`No issues found!`（0 errors, 0 warnings, 0 lints）
- **在开始任何代码修改前，必须先阅读 [context.md](./context.md) 恢复完整上下文。**

---

## 🔒 开发约束（不可违反）

### 1. 测试必须 100% 全部通过
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat test`
- **所有 777+ 个测试用例必须全部通过**（0 failures）
- 每次代码变更后必须重跑全量测试，严禁提交带测试失败的代码

### 2. 静态分析必须 0 问题
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`
- **必须输出 `No issues found!`**，不接受任何 warning、error 或 lint 提示

### 3. Git 提交与推送规范
- 每个有意义的变更必须 commit，commit message 使用标准前缀：`feat:` / `fix:` / `test:` / `refactor:` / `docs:`
- 提交后必须执行 `git push` 同步至 `origin/main`

### 4. WORK_LOG.md 必须同步更新
- 每次 Milestone 或重要功能/修复级别的变更，必须在项目根目录 `WORK_LOG.md` 的**顶部**追加记录
- 内容包括：变更文件列表、当前版本号、核心技术指标与决策

### 5. 界面文字与错误信息必须使用中文
- 所有面向用户的 UI 文字、错误提示、SnackBar 内容、确认卡片描述均已汉化为中文
- 新增任何功能时，必须沿用中文用户界面风格与友好降级提示

### 6. 版本号递增规范
- 每次新增功能（feat）、修复缺陷（fix）或变更代码，必须给项目版本号增加 0.01（在 `pubspec.yaml` 的 `version` 字段，以及 `WORK_LOG.md` / `context.md` 等相关版本标注处同步递增）

---

## 🏗️ 核心架构与代码规范

### 1. 状态管理（Riverpod）
- 一律使用 `StateNotifier` + `StateNotifierProvider`，禁止使用 `ChangeNotifier`
- 异步 StateNotifier 方法内，所有 `await` 之后第一行必须检查 `if (!mounted) return;`
- `copyWith` 方法中，可空字段（如 `activeConversation`）必须通过 `clearActive` 类布尔标志参数显式处理，禁止直接传 null 导致 fallback 回旧值

### 2. 数据库与持久化
- 所有 SQLite 操作必须通过对应 DAO（`ApiConfigDao`、`ConversationDao`、`MessageDao`、`McpServerDao`）进行，禁止在 Provider 或 Widget 中直接调用 `db.rawQuery`
- API Key 及敏感请求头只能通过 `SecureStorageService` 硬件安全存储，数据库中只存引用键（Ref）

### 3. 自动化测试规范
- 单元测试使用 `sqflite_common_ffi` + `databaseFactoryFfi` 进行纯内存数据库隔离测试
- 需要 `FlutterSecureStorage` 的测试必须使用 `MockFlutterSecureStorage`（基于 `noSuchMethod`）
- 需要 `SharedPreferences` 的测试必须调用 `SharedPreferences.setMockInitialValues({})`
- Riverpod Provider 在构造器内启动异步加载时，测试中需在 `container.read` 后执行 `await Future.delayed(const Duration(milliseconds: 50))` 挂起微任务，避免竞态
- Native 特权服务（日历、通知、通讯录、GPS）必须通过 `lib/services/native/` 中的抽象接口进行测试，保证在 Headless 命令行环境 100% 稳定运行

### 4. 工具体系与 MCP
- 静态工具实现 `Tool` 基类并在 `ToolRegistry` 注册
- MCP 工具通过 `HttpMcpTransport` / `SseMcpTransport` / `WebSocketMcpTransport` / `StdioMcpTransport` 连接，经 `McpClient` 动态发现并包装为 `McpDynamicTool` 动态注入 `ToolRegistry`，断开连接时自动注销
- 敏感与特权操作（Level 2 SensitiveConfirm, Level 3 PrivilegedNative）需通过 `ToolConfirmationPendingEvent` 触发 Human-in-the-Loop（HITL）交互确认

### 5. Token 预算与容错
- 多轮工具调用由 `TokenBudgetManager` 监控实时 Token 估算与滑动窗口历史修剪，防止上下文溢出；超限时触发 `CircuitBreaker` 熔断收尾
- 多模型非标工具调用由 `AgentFaultTolerance` 自愈纠错（DSML、Qwen XML、标准 JSON、Llama 函数语法）

---

## 📂 核心文件索引

| 文件 / 目录 | 作用 |
|---|---|
| `README.md` | 项目主文档（包含功能矩阵、架构图、快速开始与构建指南） |
| `.agents/context.md` | **本项目完整接手上下文**（最重要，包含全部 27 个 Milestone 演进历程与设计决策） |
| `.agents/AGENTS.md` | **本文件**，AI Agent 开发规则与行为规范 |
| `WORK_LOG.md` | 每次变更的顶端追加日志 |
| `docs/agent_tools/` | 工具生态架构、Schema 规范、MCP 协议与路线图归档 |

---

## 📋 接手清单（按序执行）

接手本项目的 Agent，请按以下顺序操作：

1. **读取 `context.md`**（`D:\work\chat\.agents\context.md`）恢复全部业务上下文；
2. **读取 `WORK_LOG.md`**（`D:\work\chat\WORK_LOG.md`）了解最近变更；
3. 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze` 确认 0 issues；
4. 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat test` 确认全量测试全部通过；
5. 明确任务目标后，再开始编写代码。

---

## 🚨 常见陷阱与避坑对照

| 陷阱 | 正确做法 |
|---|---|
| `ConversationState` 中将 `activeConversation` 设为 null | 使用 `copyWith(clearActive: true)` |
| Riverpod Provider 在测试或组件销毁后报错 | 所有 `await` 异步调用后检查 `if (!mounted) return;` |
| 测试中使用 FlutterSecureStorage 报 PlatformException | 使用 `MockFlutterSecureStorage` |
| 图片路径在重启后失效 | 压缩后保存到 `Documents` 目录，数据库存绝对路径 |
| 向不支持 Vision 的模型发送图片导致 400 | `sendMessage` 内先检查 `selectedModel.supportsVision` |
| MCP 端点为 Streamable HTTP 时误用 GET | 使用 `HttpMcpTransport` 直接发送 POST 请求 |
| SQLite 数据库损坏导致 App 崩溃 | `DatabaseHelper` 已实现自愈重建逻辑，无需额外处理 |
