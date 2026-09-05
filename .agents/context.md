# 项目接手上下文（Context）
> 最后更新：2026-09-03

---

## 🎯 项目总述

这是一个用 **Flutter** 开发的 Android AI Agent 移动端 App，连接 **9Router**（OpenAI 兼容 API 接口）。

- **工作目录**：`D:\work\chat`
- **Flutter SDK**：`D:\work\flutter-sdk\flutter\bin\flutter.bat`
- **Git 远程仓库**：`github.com:naruse-love/chat-app.git`（`main` 分支）
- **开发约束**：Benchmark 模式 —— `flutter test` 必须 100% 通过，`flutter analyze` 必须 0 issues
- **当前版本**：`1.22.0+23`

---

## ✅ 已完成的全部 Milestone

| Milestone | 描述 | 状态 |
|-----------|------|------|
| 1-27 | 核心体系（从基础模型、数据库、SSE、搜索、图片、UI、全套原生特权、MCP 客户端与动态网桥、Token 预算压缩、自愈容错网关）全部实现并交付 | ✅ 完成 |
| **沙箱管理系统升级 & 工具自愈 & UI 体验重构** | 实现沙箱开关与应用内文件管理/预览/导出，AI 沙箱感知与外部文件授权；增强代码解释器（`void main`、`Math`、`console`、函数定义、`import` 剥离）；日历/通知多别名自愈与 MCP 自动重连；修复 MCP 标题与时间线溢出，支持独立思考复制；全局 Token 上限提至 1M（2026-09-02） | ✅ 完成 |
| **MCP Streamable HTTP & 一键导入** | 新增 MCP 官方 Streamable HTTP (`type: "http"`, `POST /mcp`) 传输层 `HttpMcpTransport`，SSE 智能降级自愈，UI 一键导入 JSON 配置与小屏对话框自适应（2026-09-02） | ✅ 完成 |
| 1 | 数据模型与序列化（ModelInfo、ChatMessage、ApiConfig, ToolCall 等） | ✅ 完成 |
| 2 | 本地 SQLite 数据库（DatabaseHelper、ApiConfigDao、MessageDao、ConversationDao）+ 安全凭证存储（SecureStorageService） | ✅ 完成 |
| 3 | SSE 流解析（SseDecoder、SseParser）+ 网络 API（ChatService） | ✅ 完成 |
| 4 | 网络搜索与 Agent 调度（SearchService、AgentService） | ✅ 完成 |
| 5 | 图片服务（ImageService：压缩 / 选取 / Base64 编码）| ✅ 完成 |
| 6 | Riverpod 状态管理（7 个 Provider）+ 全套 UI 页面 | ✅ 完成 |
| 7 | E2E 集成测试（127 个测试用例） | ✅ 完成 |
| 8 | 对抗性异常加固（DB 损坏自愈、Vision 预检、网络错误分类） | ✅ 完成 |
| 汉化 | 全界面中文本地化（UI 文字、错误提示、SnackBar） | ✅ 完成 |
| 最终编译 | `flutter build apk --debug` 编译成功，产物位于 `build/app/outputs/flutter-apk/app-debug.apk` | ✅ 完成 |
| **9 / 维护迭代** | 消息编辑/重发、Token 统计、会话回退/重新生成；搜索迁移到 SearXNG 主路径 + 实验性 Bing（移除 9Router 内置搜索）；多轮 tool calling + 伪 XML `<tool_call>` 兜底；Vision 本地预检移除（发图交由 API 报错）；SearXNG URL 回显、Vision 能力解析增强；思考内容可选中/复制；主界面系统提示词入口 + 注入 API system 消息；编辑/回退崩溃加固（2026-07-13 ~ 2026-07-15） | ✅ 完成 |
| **10 / 深度增强**| OpenCode Free 免本地代理直连（指向 `https://opencode.ai/zen/v1`）；网页全文抓取工具 (`url_fetch` + HTML 过滤 + 8000字截断)；SearXNG 并发双页查询与去重优化；全 StateNotifier 异步 `mounted` 防御，避免测试销毁崩溃（2026-07-16） | ✅ 完成 |
| **11 / 修复加固**| 模型选择区域加大（热区提升至符合 48dp 标准）；OpenCode Free 免费模型过滤（仅保留 ID 含有 free 字段的模型）与默认模型 deepseek-v4-flash-free 设置；SharedPreferences 异步竞态防范（在 _startStreaming 强制 await initialization，消除 Bing 搜索误报 SearXNG 错误）；Tool Round 超限保底方案（toolRound >= 4 强制进行不含 tools 的最终响应补全，防止自动停止）；编辑与回退弹窗 300ms 路由延迟销毁加固，防止 disposed controller 与 _dependents.isEmpty 框架断言崩溃（2026-07-16 ~ 2026-07-18） | ✅ 完成 |
| **12 / 维护增强**| 多轮调用上限提升至 10 轮并配置总结兜底；中途所有过程消息整泡折叠展示（除无工具调用的最终文本回答外均默认折叠）；长按消息可复制纯文本（自动洗 Markdown 标记）和 Markdown 原始格式；接入谷歌 AI Studio 搜索接地 (Google Grounding)；修复接地模型重启重置 Bug，修复编辑消息取消崩溃，支持并行双搜 (Google+Bing)，精简搜索结果系统提示模板，修复过程消息标题文本超长右侧溢出警告 (2026-07-18) | ✅ 完成 |
| **13 / 搜索与设置增强** | 对话内自由选择复制文本；独立 `google_search` 与 `bing_search` 工具；透传 OpenCode Free 思考等级 `reasoningEffort`；`url_fetch` 结构化 Markdown 转换与 UTF-8 容错解码；会话死锁释放与底层滚动平滑适配；修复对话内修改系统提示词 Controller dispose 崩溃；支持设置默认系统提示词模板与 `[默认]` 标识（2026-07-20） | ✅ 完成 |
| **14 / 状态加固与新对话异常** | 修复新对话发送消息时由于 `activeConversation` 回调触发 `loadMessages` 覆盖清空 UI `state` 的隐形 Bug（2026-07-20） | ✅ 完成 |
| **15 / Bing 搜索多词及 Cookie 修复** | Bing 搜索采用 `+` 转义多词空格并在 URL 中追加 `cc=us&setlang=zh-hans`，强制使用全球端点绕过国内关键字截断降级策略；修复 `Dio` 跨域重定向丢失 `Cookie` 的问题，通过 `followRedirects: false` 拦截重定向并手动注入 Cookie，使搜索记录能正确同步至用户账户（2026-07-20） | ✅ 完成 |
| **16 / Bing Cookie 跨域透传与 Agent 规则加锁** | Bing 搜索新增 Cookie 格式清洗与多重重定向 5-hop 显式转发（含 `Set-Cookie` 动态合并），强化 DOM 选择器与反爬/验证码页面识别，优化已填 Cookie 时的错误提示；`AGENTS.md` 新增约束：每次更新/修复必须递增版本号 0.01（`pubspec.yaml` 升至 `1.01.0+2`）（2026-07-20） | ✅ 完成 |
| **17 / Bing WAF 误拦修复与版本递增** | 修复 Bing 搜索请求头 `User-Agent` 中的拼接错误（格式异常引发微软 FrontDoor WAF 直接阻断），调整 `Sec-Fetch-Site` 为 `none`；新增 WAF 阻断 (`The request is blocked`) 明确识别；项目版本递增至 `1.02.0+3`（2026-07-21） | ✅ 完成 |
| **18 / Settings 竞态修复与 DSML 伪 XML 语法支持** | 修复 Settings 异步加载时 `isLoaded` 提前写 true 的竞态问题（导致首次搜索无法应用 Bing Cookie 等配置）；支持解析与剥离 DSML (`<｜｜DSML｜｜tool_calls>`) 格式工具调用；修复伪 XML 兜底分支递归丢失 `bingCookie` 等参数的问题；将默认工具链调用次数上限提升至 100 轮（支持参数配置）；项目版本递增至 `1.03.0+4`（2026-07-21） | ✅ 完成 |
| **19 / Bing 首次搜索 Cookie 穿透与 AI 总结强化** | 修复首次 AI 工具调用自动搜索时未向下传递 `bingCookie` 参数的重大 Bug；强化 Bing 搜索，增加对 `.cht_root` / `[data-scenario="nrt"]` 智能 AI 总结栏内容的提取并前置作为 SearchResult；在 `HomeScreen` 中增加 `ref.listen` 对 `ChatState.error` 错误的全局监听并显示为 SnackBar，完美向用户反馈调用失败原因；项目版本递增至 `1.04.0+5`（2026-07-21） | ✅ 完成 |
| **20 / 手势禁用、搜索开关与抓取增强** | 移除会话列表项 `Dismissible` 滑动手势，彻底防止误删对话；设置页增加「启用 AI 网络搜索」开关 (`enableAutoSearch`)，关闭时屏蔽外部搜索 Tool Call；升级 `url_fetch_service` 提取 HTML Title/Description/Author/Keywords 元数据及 `<table>` Markdown 转换，优化 403 阻断提示与关键词去重清洗；项目版本递增至 `1.05.0+6`（2026-08-03） | ✅ 完成 |
| **21 / 完整文档重构** | 全面重构并丰富 `README.md` 项目说明文档，涵盖架构拓扑、特性矩阵、目录树、快速上手、测试矩阵、配置指南、稳定性自愈设计与开发规范；版本号递增至 `1.06.0+7`（2026-08-14） | ✅ 完成 |
| **22 / UrlFetchService v2 智能抓取与诊断** | 提升提取上限至 15000 字符，增加截断感知与警告；增加反爬验证页（captcha）、登录墙（login_wall）、导航门户（nav_hub）诊断与警告；提取 JSON-LD、OG 协议与 HTML 元数据；语义容器（article/main）优先提取与 nav/footer/aside 噪音剥离；站内/站外链接统计分析；新增 FetchResult 结构化模型（2026-08-16） | ✅ 完成 |
| **23 / 内置基础工具库与防死循环架构** | 打造内置基础工具体系（`math_eval` 数学计算引擎、`time_calculator` 高精度时间时区运算、`weather_query` 免费 Open-Meteo 天气、`wiki_lookup` 维基百科检索）；构建 `ToolRegistry` 统一注册与权限管理中心；引入 `AgentLoopGuard`（RFC 1321 MD5 签名、连续重复与震荡周期防御、轮次上限强制兜底）；`AgentService` 全面接入与动态 Schema 导出；`ChatBubble` 中文分类标签、安全等级徽章与折叠卡片（2026-08-28） | ✅ 完成 |
| **24 / 本地沙箱执行与人机协同确认机制** | 打造本地安全沙箱文件系统（`PathSanitizer` 路径净化与配额管理、`file_read`、`file_write`、`file_list`、`file_delete`）与多语言 Isolate 代码执行沙箱（`code_eval` 3000ms 硬超时强杀）及系统剪贴板工具（`clipboard_read`、`clipboard_write`）；定义 4 级工具安全分类；实现人机协同确认机制（Human-in-the-Loop, HITL），在 `AgentService` 与 `ChatNotifier` 中全面拦截 Level 2 敏感工具并挂起异步决断；实现 `DiffViewerWidget` 统一差异对比视图与 `ToolConfirmationCard` 授权/拒绝交互卡片；ToolRegistry 统一接入 15 个工具；完成全面对抗性加固验证与 412 个自动化测试矩阵（2026-08-29） | ✅ 完成 |
| **25 / 移动原生能力与特权工具生态** | 打造移动端原生设备能力抽象契约与服务层（`ICalendarService`、`INotificationService`、`IContactsService`、`ILocationService` 及内存 Mock）；构建隐私脱敏网关 `ContactsSanitizer`（E.164 手机号掩码、白名单过滤、提示词注入防护、单次 5 条限制）；实现统一权限管理器 `PermissionManagerService`（权限预检、申请与中文友好降级）；实现 7 个原生标准工具（`calendar_query_events`、`calendar_create_event`、`notification_schedule`、`notification_cancel`、`contacts_search`、`geolocation_get`、`reverse_geocode`）；`ToolRegistry` 接入 22 个工具并支持动态启停与 Schema 导出；`ChatBubble` 与 `ToolConfirmationCard` 深度集成原生特权徽章与专属日程/通知预览卡片（2026-08-30） | ✅ 完成 |
| **26 / MCP 客户端体系、动态工具网桥与全链路加固** | 构建 Model Context Protocol (MCP 2024-11-05) 客户端体系与动态工具网桥：多通道传输层（`SseMcpTransport`、`WebSocketMcpTransport`、`StdioMcpTransport` 跨平台支持与优雅降级）、`JsonRpcEngine` 协议引擎（超时、请求路由与错误映射）、`McpClient` 核心客户端（初始化握手、保活心跳、工具/资源/Prompt 检索与执行）、`McpDynamicTool` 桥接适配器（OpenAI Schema 命名空间隔离与参数宽容解析）；SQLite v4 `mcp_servers` 表与 `SecureStorageService` 敏感凭据存储；`McpProvider`（StateNotifier 异步 `mounted` 安全与 `ToolRegistry` 动态注入/注销）；`McpServerManagementScreen` 管理页面、设置页入口及 `ChatBubble` / `ToolConfirmationCard` 专属 MCP 徽章与参数预览；完成全链路对抗性测试与加固交付（2026-09-01） | ✅ 完成 |
| **27 / 统一 Agent 运行时、可观测性体系与全量交付** | 构建 Agent 全局 Token 预算与滑动窗口压缩引擎（`TokenBudgetManager`）、跨模型容错与对抗防御自愈网关（`AgentFaultTolerance`）、四大维度工具链统一调度管道终极集成；实现多步执行折叠时间线组件（`AgentExecutionTimelineWidget`）、响应式 Token 预算指示徽章（`TokenBudgetBadge`）与熔断预警卡片（`CircuitBreakerAlertWidget`）；完成全套自动化测试套件构建与逆向对抗加固（774 测试全部通过）（2026-09-02） | ✅ 完成 |

**当前测试状态：774 / 774 测试用例全部通过，`flutter analyze` 0 issues，版本号：v1.16.0+17。**

---

## 🏗️ 项目架构概览

```
lib/
├── main.dart                     # App 入口，路由注册，Riverpod ProviderScope
├── app.dart                      # MaterialApp 根（含主题、Provider 注入）
│
├── models/                       # 数据模型
│   ├── fetch_result.dart         # 网页抓取与诊断模型（FetchResult, FetchMetadata）
│   ├── api_config.dart           # API 配置（name, baseUrl, apiKeyRef, isDefault）
│   ├── chat_message.dart         # 消息模型（reasoningContent, imagePath, toolCallId, promptTokens, completionTokens）
│   ├── conversation.dart         # 对话模型（isPinned, isArchived, systemPrompt）
│   ├── model_info.dart           # 模型元数据（supportsVision, supportsTools）
│   ├── search_result.dart        # 搜索结果
│   ├── system_prompt_template.dart
│   ├── tool_call.dart
│   ├── agent_step_telemetry.dart # 多步执行遥测与统计模型（AgentStepTelemetry, AgentExecutionSummary）
│   ├── tool/                     # 工具体系模型
│   │   ├── tool.dart             # 抽象基类 Tool
│   │   ├── tool_parameter.dart   # 参数模式 ToolParameter
│   │   ├── tool_execution_result.dart # 执行结果模型
│   │   ├── tool_security_level.dart   # 4 级安全分类
│   │   └── tool_confirmation.dart    # HITL 确认请求与决策模型
│   └── native/                   # 移动原生数据模型
│       ├── calendar_event.dart   # 日历日程与确认预览模型
│       ├── scheduled_notification.dart # 定时通知与确认预览模型
│       ├── contact_item.dart     # 设备联系人模型
│       ├── geo_models.dart       # GPS 坐标与结构化地址模型
│       └── app_permission.dart   # 原生设备权限枚举与状态
│
├── data/                         # SQLite 数据访问层
│   ├── database_helper.dart      # 单例 SQLite 管理器（损坏自愈 + schema v3 迁移 + v4 mcp_servers）
│   ├── api_config_dao.dart       # API 配置 CRUD（含安全存储集成）
│   ├── conversation_dao.dart     # 对话 CRUD（pin/archive/sort + systemPrompt）
│   ├── message_dao.dart          # 消息 CRUD（绝对/相对路径映射 + token 字段）
│   └── mcp_server_dao.dart       # MCP 服务配置 DAO
│
├── services/                     # 业务服务层
│   ├── chat_service.dart         # Dio HTTP 客户端，/v1/chat/completions SSE 流（支持免 Key 自动处理）
│   ├── search_service.dart       # SearXNG 主路径 + 实验性 Bing（9Router 内置搜索已停用，双页并发，URL 去重，新 Prompt）
│   ├── url_fetch_service.dart    # 网页抓取服务（DOM 节点清洗，15000字符截断）
│   ├── agent_service.dart        # 多轮 tool calling，伪 XML tool_call 兜底，HITL 敏感拦截，四大维度 22+ 工具统一调度管道
│   ├── token_budget_manager.dart # 全局 Token 预算与滑动窗口压缩引擎（Token 估算、历史修剪、熔断器）
│   ├── agent_fault_tolerance.dart # 跨模型容错与对抗自愈网关（多格式参数纠错、指数退避重试、自愈降级）
│   ├── tool_registry.dart        # 统一工具注册中心（22 个内置、沙箱与原生特权工具 + 动态 MCP）
│   ├── agent_loop_guard.dart     # MD5 签名与死循环/震荡检测防护器
│   ├── path_sanitizer.dart       # 安全沙箱路径净化与 5MB/50MB 配额防护器
│   ├── code_execution_service.dart # 多语言 Isolate 代码执行沙箱（3000ms 超时强杀）
│   ├── rune_safe_json_truncator.dart # Unicode 代理对安全截断与 JSON 修复器
│   ├── image_service.dart        # 图片选取 / 压缩 / Base64 编码
│   ├── secure_storage_service.dart # flutter_secure_storage 封装
│   ├── mcp/                      # MCP 客户端体系（Transport, JsonRpcEngine, McpClient, DynamicTool）
│   ├── native/                   # 原生服务层与隐私安全网关
│   │   ├── calendar_service.dart # 日历服务接口与 InMemoryCalendarService
│   │   ├── notification_service.dart # 通知服务接口与 InMemoryNotificationService
│   │   ├── contacts_service.dart # 通讯录接口与 InMemoryContactsService
│   │   ├── location_service.dart # 定位接口与 InMemoryLocationService
│   │   ├── contacts_sanitizer.dart # 通讯录隐私脱敏与防注入网关
│   │   ├── permission_manager_service.dart # 统一权限管理器
│   │   └── native_service_providers.dart # Riverpod DI Provider
│   └── tools/                    # 22 个具体工具实现
│       ├── math_eval_tool.dart
│       ├── time_calculator_tool.dart
│       ├── weather_query_tool.dart
│       ├── wiki_lookup_tool.dart
│       ├── legacy_tool_adapters.dart
│       ├── file_read_tool.dart
│       ├── file_write_tool.dart
│       ├── file_list_tool.dart
│       ├── file_delete_tool.dart
│       ├── code_eval_tool.dart
│       ├── clipboard_tools.dart
│       └── native/               # 7 个原生特权与定位工具
│           ├── calendar_tools.dart
│           ├── notification_tools.dart
│           ├── contacts_search_tool.dart
│           ├── geolocation_tool.dart
│           └── reverse_geocode_tool.dart
│
├── providers/                    # Riverpod 状态管理
│   ├── theme_provider.dart       # ThemeMode（light/dark/system）
│   ├── api_config_provider.dart  # API 配置列表、活跃配置
│   ├── model_provider.dart       # 模型列表、选中模型（Vision 能力解析增强）
│   ├── conversation_provider.dart # 对话列表、活跃对话（clearActive 修复）
│   ├── chat_provider.dart        # 消息列表、流式生成、HITL 确认交互、多轮管道调度、Token 预算预检
│   ├── agent_provider.dart       # 工具调用状态、多步遥测步骤流、Token 消耗统计、熔断预警信号
│   ├── mcp_provider.dart         # MCP 服务状态机与 ToolRegistry 动态注入
│   └── settings_provider.dart    # searxngUrl, searchBackend, defaultSystemPrompt
│
├── screens/                      # 页面
│   ├── home_screen.dart          # 主聊天页（HITL 确认卡片、执行时间线、Token 胶囊、熔断横幅）
│   ├── settings_screen.dart      # 设置页（含 MCP 服务管理入口）
│   ├── api_config_screen.dart    # API 配置管理页（测试连接功能）
│   ├── model_selector_screen.dart # 模型选择页（按 provider 分组，带 Vision/Tools 标签）
│   ├── system_prompt_screen.dart # 系统提示词模板管理页
│   └── mcp_server_management_screen.dart # MCP 服务配置与多 Tab 工具管理页
│
├── utils/                        # 辅助工具
│   └── diff_helper.dart          # LCS 动态规划算法 Diff 差异比对器
│
└── widgets/                      # 可复用 Widget
    ├── chat_bubble.dart          # 消息气泡（折叠时间线、Token 胶囊、熔断预警、MCP 徽章）
    ├── chat_input.dart           # 输入区（图片附件、发送、多行文本）
    ├── diff_viewer_widget.dart   # 统一差异对比视图组件
    ├── tool_confirmation_card.dart # 人机协同交互确认卡片
    ├── agent_execution_timeline.dart # 可折叠多步执行时间线组件
    └── token_budget_badge.dart   # 响应式 Token 预算胶囊指示徽章与熔断预警卡片

test/
├── unit tests (模型、服务、DAO、工具集)
├── services/
│   ├── token_budget_manager_test.dart
│   ├── agent_fault_tolerance_test.dart
│   ├── unified_agent_pipeline_test.dart
│   ├── adversarial_challenge_m27_test.dart
│   ├── path_sanitizer_test.dart
│   ├── sandboxed_file_tools_test.dart
│   ├── code_execution_service_test.dart
│   ├── clipboard_tools_test.dart
│   ├── rune_safe_json_truncator_test.dart
│   ├── basic_tools_test.dart
│   ├── tool_registry_test.dart
│   ├── agent_loop_guard_test.dart
│   ├── native/
│   │   ├── calendar_service_test.dart
│   │   ├── notification_service_test.dart
│   │   ├── contacts_service_test.dart
│   │   ├── location_service_test.dart
│   │   ├── contacts_sanitizer_test.dart
│   │   └── permission_manager_service_test.dart
│   └── tools/
│       ├── native_tools_test.dart
│       └── tool_registry_native_test.dart
├── widgets/
│   ├── agent_execution_timeline_test.dart
│   ├── token_budget_badge_test.dart
│   ├── m27_widgets_adversarial_test.dart
│   ├── diff_viewer_widget_test.dart
│   ├── tool_confirmation_card_test.dart
│   ├── native_tools_ui_test.dart
│   ├── chat_bubble_tool_rendering_stress_test.dart
│   └── challenger_m24_hitl_concurrency_stress_test.dart
├── widgets_test.dart             # ChatBubble、ChatInput Widget 测试
├── e2e_integration_test.dart     # Provider E2E 集成测试（主题、API、对话、流式消息）
├── adversarial_hardening_test.dart # 对抗性异常测试（DB 损坏、Vision 预检、网络错误）
└── ...
```

---

## 🔑 关键技术决策

1. **SQLite 损坏自愈 + schema v3 迁移**：`DatabaseHelper._initDatabase()` 用 try-catch 包裹 `openDatabase`，失败时自动删除损坏文件并重建；v3 新增 `prompt_tokens` / `completion_tokens` 字段用于 Token 统计。
2. **Vision 预检已移除**：不再在客户端拦截图片消息，由 API 侧报错（`400` 等）；模型选择页仍保留「视觉」标签以便用户辨识能力。
3. **Riverpod mounted 保护**：`ChatNotifier` 的异步路径（流式接收、回退/编辑/重新生成）均检查 `if (!mounted) return;`，防止 dispose 后写状态崩溃。
4. **copyWith clearActive**：`ConversationState.copyWith` 增加 `clearActive` 布尔参数，解决 Riverpod 中 `activeConversation` 无法设置为 null 的 Bug。
5. **图片永久路径**：`ImageService.compressAndSaveImage()` 将临时缓存图片压缩后复制到 `getApplicationDocumentsDirectory()`，SQLite 只存永久路径，防止系统清理缓存后图片丢失。
6. **搜索：SearXNG 为主，实验性 Bing 可选**：9Router 内置搜索已停用；`settings_provider` 暴露 `searxngUrl` 与 `searchBackend` 切换后端。
7. **SSE 流解析**：`SseParser` 处理 `data: ` 前缀、`[DONE]` 终止符及跨块 JSON 拼接，兼容 OpenAI 流式格式；多轮 tool calling 时持续透传 `tools` 参数到后续 completion。
8. **多轮 tool calling + 伪 XML 兜底**：当模型不返回标准 `tool_calls` 而输出伪 XML `<tool_call>{...}</tool_call>` 时，Agent 解析为工具调用并执行；执行结果回传继续下一轮 completion。
9. **MarkdownBody 长期 `selectable:false`**：避免在 `ListView` 销毁时引发选区崩溃；思考区（`reasoningContent`）单独使用 `SelectableText` + 复制按钮，保证可选择/复制。
10. **系统提示词注入**：`ChatNotifier` 启动流式生成时，优先使用当前会话的 `systemPrompt`，否则使用 `settings_provider` 的 `defaultSystemPrompt`；最终以 `role: system` 注入到 messages 最前。
11. **回退/编辑时序**：`showDialog` 关闭后 `await Future.delayed(Duration(milliseconds: 50))` 再配合 `mounted` 检查后改 state，避免动画/构建期状态写入导致崩溃。
12. **OpenCode Free 免本地代理直连**：冷启动若无配置，自动向数据库插入 OpenCode Free 默认配置（指向 `https://opencode.ai/zen/v1`，apiKey 存为空字符串以跳过 `Authorization` 头），并在获取 models 失败或离线启动时降级提供 `deepseek-v4-flash-free` 等 5 个核心免费模型。
13. **网页抓取与清洗 (`url_fetch`)**：新设 `UrlFetchService`，利用 `package:html` 对 DOM 树清洗，设置 15000 字符限制并提供截断感知与反爬/登录页诊断。
14. **SearXNG 并发双页查询与去重**：查询 SearXNG 时并行发起 `pageno: 1` 和 `pageno: 2` 的网络请求（利用 `Future.wait`），各接口超时/异常相互隔离，并通过 URL 做去重（保持首次出现顺序）。
15. **StateNotifier 异步 `mounted` 防御**：针对所有状态控制器的异步逻辑补齐 `if (!mounted) return;`，避免测试 tearDown 阶段异常。
16. **模型选择热区与外观优化**：热区符合 48dp 标准。
17. **SharedPreferences 竞态防范**：`SettingsNotifier` 暴露 `initialization` 同步加载期 Future，并在流式生成前强制 `await` 确保配置完全拉取。
18. **AgentLoopGuard 多级死循环与震荡防御**：通过 RFC 1321 MD5 工具调用签名，实时检测连续重复调用及周期震荡，在触发循环或达到上限时自动移除工具并注入中文总结提示词。
19. **PathSanitizer 沙箱安全防护与配额隔离**：严格解析绝对路径与符号链接，防御 `../../` 越狱逃逸；硬性限制单文件 5MB、总工作区 50MB。
20. **Isolate 代码沙箱与 3000ms 硬超时强杀**：通过独立 Worker Isolate 执行代码，配合 `Timer` 与 `isolate.kill()` 彻底防御 `while(true)` 死循环。
21. **人机协同确认机制（HITL）**：Level 2+ 敏感工具在执行前通过 Completer 挂起并触发 UI 确认卡片，展示 LCS 行级差异对比，允许用户一键授权或携带理由拒绝，流取消与拒绝逻辑平滑协同。
22. **Unicode Rune 安全截断与 JSON 自动闭合**：`RuneSafeJsonTruncator` 避免破坏 UTF-16 代理对引发乱码，并在截断后基于括号栈自动补全未闭合的 JSON 结构。
23. **移动端原生能力契约与服务抽象**：定义 `ICalendarService`、`INotificationService`、`IContactsService`、`ILocationService` 标准接口与基于内存状态的 InMemory 实现，支持日历事件 CRUD、日程重叠判定、精确通知调度与取消、地理坐标逆编码计算。
24. **通讯录隐私脱敏网关 (ContactsSanitizer)**：规范化 E.164 号码掩码脱敏（保留前3后4位）、严格白名单过滤（屏蔽私密备注与敏感地址）、中立化控制符防御提示词注入与 JSON 结构污染、单次检索结果硬性截断上限 5 条。
25. **统一原生权限管理与友好降级**：`PermissionManagerService` 统一管理 `AppPermission` 状态与申请流，对未授权或被拒绝权限返回明确中文友好提示与操作引导。
26. **原生特权工具链 (Level 3) 与 HITL 专用卡片**：构建 7 个原生工具（日历、通知、通讯录、定位），其中日历新建与定时通知通过 `CalendarEventPreview` / `NotificationPreview` 结构化提炼渲染专属 HITL 确认卡片。
27. **MCP (Model Context Protocol) 客户端体系与动态工具网桥**：构建多通道通信层（SSE / WebSocket / Stdio）、JSON-RPC 2.0 异步协议引擎（支持 10s 请求超时与标准错误码转换）、MCP 2024-11-05 标准协议握手与心跳机制；实现 `McpDynamicTool` 动态工具网桥，将远程 MCP 工具自动转换为带命名空间隔离的标准 `Tool` 实例并动态注入 `ToolRegistry`；SQLite v4 表结构持久化多 Server 配置，并通过 `SecureStorageService` 加密隔离敏感授权凭据；`McpProvider`（StateNotifier）严格遵循异步 `mounted` 安全防护；提供专属 `McpServerManagementScreen` 可视化管理面板及 `ChatBubble` / `ToolConfirmationCard` MCP 紫色徽章与参数审计。
28. **TokenBudgetManager 预算与滑动窗口压缩引擎**：基于中文（0.6 token/char）、英文/代码（0.25 token/char）、Emoji 及结构化 JSON 实施高精度 Token 估算；针对多轮长会话工具历史输出实施滑动窗口裁剪，保留关键调用签名与头尾精炼摘要，彻底消除上下文爆炸风险；超限触发熔断器（CircuitBreaker）自动剥离后续工具，安全引导大模型收尾输出总结。
29. **AgentFaultTolerance 跨模型对抗容错自愈网关**：自动纠错 DeepSeek DSML、Qwen XML、标准 JSON、Llama 函数语法中未闭合引号/括号/转义符；针对外部网络异常执行指数退避重试（带 Jitter）；提供结构化中文自愈错误上下文。
30. **四大维度工具链统一调度管道与多步时间线可观测性**：统一协同调度 22+ 基础实用、本地沙箱、移动原生特权与 MCP 远程动态工具；`AgentStepTelemetry` 记录微秒级执行耗时与 Token 消耗；`AgentExecutionTimelineWidget` 与 `TokenBudgetBadge` 提供直观可视化时间线与三色预算状态。

---

## 🚀 下一步可能的开发方向

以下是一些可选的后续功能（均未开始）：

- **多语言 i18n 框架**：目前汉化通过硬编码实现，可迁移到 `flutter_localizations` + `intl` 进行规范化国际化管理。
- **文件导出功能**：对话历史导出为 Markdown / JSON。
- **语音输入**：集成 `speech_to_text` 插件实现语音转文字输入。
- **Agent 插件系统**：让用户自定义 Tool Call 扩展（除内置工具外）。
- **Release APK 签名打包**：目前以 Debug APK 为主，需要配置 keystore 进行 Release 签名。
- **通知支持**：长时间生成时后台推送通知。

---

## 📦 关键文件路径

| 文件 | 说明 |
|------|------|
| [WORK_LOG.md](../WORK_LOG.md) | 详细的开发日志，按 Milestone 记录所有变更与技术决策 |
| [implementation_plan.md](../implementation_plan.md) | 系统架构设计与各模块规划文档 |
| [context.md](context.md) | 当前接手上下文（每次重大迭代更新） |
| [AGENTS.md](AGENTS.md) | Agent 协作约定与角色说明 |
| [build/app/outputs/flutter-apk/app-debug.apk](../build/app/outputs/flutter-apk/app-debug.apk) | 最新编译的 Debug APK |

---

## ⚙️ 常用命令

```bash
# 静态分析（必须 0 issues）
D:\work\flutter-sdk\flutter\bin\flutter.bat analyze

# 运行全部测试（必须 774/774 通过）
D:\work\flutter-sdk\flutter\bin\flutter.bat test --no-pub

# 编译 Debug APK
D:\work\flutter-sdk\flutter\bin\flutter.bat build apk --debug

# 提交并推送
git add -A && git commit -m "..." && git push
```

