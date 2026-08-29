# 项目接手上下文（Context）
> 最后更新：2026-07-20

---

## 🎯 项目总述

这是一个用 **Flutter** 开发的 Android AI Agent 移动端 App，连接 **9Router**（OpenAI 兼容 API 接口）。

- **工作目录**：`D:\work\chat`
- **Flutter SDK**：`D:\work\flutter-sdk\flutter\bin\flutter.bat`
- **Git 远程仓库**：`github.com:naruse-love/chat-app.git`（`main` 分支，HEAD `69aff21`）
- **开发约束**：Benchmark 模式 —— `flutter test` 必须 100% 通过（159/159），`flutter analyze` 必须 0 issues

---

## ✅ 已完成的全部 Milestone

| Milestone | 描述 | 状态 |
|-----------|------|------|
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

**当前测试状态：263 / 263 测试用例全部通过，`flutter analyze` 0 issues，版本号：v1.08.0+9。**

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
│   └── tool_call.dart
│
├── data/                         # SQLite 数据访问层
│   ├── database_helper.dart      # 单例 SQLite 管理器（损坏自愈 + schema v3 迁移）
│   ├── api_config_dao.dart       # API 配置 CRUD（含安全存储集成）
│   ├── conversation_dao.dart     # 对话 CRUD（pin/archive/sort + systemPrompt）
│   └── message_dao.dart          # 消息 CRUD（绝对/相对路径映射 + token 字段）
│
├── services/                     # 业务服务层
│   ├── chat_service.dart         # Dio HTTP 客户端，/v1/chat/completions SSE 流（支持免 Key 自动处理）
│   ├── search_service.dart       # SearXNG 主路径 + 实验性 Bing（9Router 内置搜索已停用，双页并发，URL 去重，新 Prompt）
│   ├── url_fetch_service.dart    # 网页抓取服务（DOM 节点清洗，8000字符截断）
│   ├── agent_service.dart        # 多轮 tool calling，伪 XML tool_call 兜底，systemPrompt 注入，url_fetch 路由支持
│   ├── image_service.dart        # 图片选取 / 压缩 / Base64 编码
│   └── secure_storage_service.dart  # flutter_secure_storage 封装
│
├── providers/                    # Riverpod 状态管理
│   ├── theme_provider.dart       # ThemeMode（light/dark/system）
│   ├── api_config_provider.dart  # API 配置列表、活跃配置
│   ├── model_provider.dart       # 模型列表、选中模型（Vision 能力解析增强）
│   ├── conversation_provider.dart # 对话列表、活跃对话（clearActive 修复）
│   ├── chat_provider.dart        # 消息列表、流式生成、editAndResend / regenerate / rollback / _startStreaming，mounted 守卫覆盖异步路径
│   ├── agent_provider.dart       # 工具调用状态（isSearching, searchQuery）
│   └── settings_provider.dart    # searxngUrl, searchBackend, defaultSystemPrompt
│
├── screens/                      # 页面
│   ├── home_screen.dart          # 主聊天页（系统提示词入口、回退/编辑/重新生成 UI、侧边栏对话列表、消息气泡）
│   ├── settings_screen.dart      # 设置页
│   ├── api_config_screen.dart    # API 配置管理页（测试连接功能）
│   ├── model_selector_screen.dart # 模型选择页（按 provider 分组，带 Vision/Tools 标签）
│   └── system_prompt_screen.dart # 系统提示词模板管理页
│
└── widgets/                      # 可复用 Widget
    ├── chat_bubble.dart          # 消息气泡（Markdown 长期 selectable:false，思考区独立 SelectableText + 复制按钮，图片预览）
    └── chat_input.dart           # 输入区（图片附件、发送、多行文本）

test/
├── unit tests (模型、服务、DAO)
├── widgets_test.dart             # ChatBubble、ChatInput Widget 测试
├── e2e_integration_test.dart     # Provider E2E 集成测试（主题、API、对话、流式消息）
├── adversarial_hardening_test.dart # 对抗性异常测试（DB 损坏、Vision 预检、网络错误）
├── database_*.dart               # 数据库注入/并发/升级/压力/EXPLAIN 测试
├── agent_service_test.dart       # 多轮 tool calling / 伪 XML 兜底 / systemPrompt 注入
├── chat_service_test.dart        # SSE 解析与多轮流
├── search_service_test.dart      # SearXNG / Bing 切换与双页去重测试
├── url_fetch_service_test.dart   # 网页抓取、HTML 清洗与字符数限制测试
├── opencode_free_test.dart       # OpenCode Free 默认配置初始化与模型降级测试
├── model_info_test.dart + model_info_stress_test.dart
├── models_serialization_stress_test.dart
├── image_service_test.dart
├── sse_parser_test.dart
└── challenger_empirical_test.dart # 端到端稳健性挑战测试
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

13. **网页抓取与清洗 (`url_fetch`)**：新设 `UrlFetchService`，利用 `package:html` 对 DOM 树的 `.remove()` 方法强力剔除 `<script>`、`<style>` 与 `<noscript>` 标签以确保 LLM 接收正文的高洁净度，合并重复空白，设置 8000 字符限制。在 `agentProvider` 扩展并在 UI 渲染中以进度卡片 `"正在读取网页: [URL]..."` 动态呈现。

14. **SearXNG 并发双页查询与去重**：查询 SearXNG 时并行发起 `pageno: 1` 和 `pageno: 2` 的网络请求（利用 `Future.wait`），各接口超时/异常相互隔离，并通过 URL 做去重（保持首次出现顺序），提升信息覆盖面。

15. **StateNotifier 异步 `mounted` 防御**：针对 `ApiConfigNotifier`、`ConversationNotifier` 等所有状态控制器的异步逻辑补齐 `if (!mounted) return;`，完美避免测试 tearDown 阶段因异步回调更新已被销毁的状态而触发 `Bad state: StateNotifier.state was accessed after being disposed`。

16. **模型选择热区与外观优化**：将 AppBar 模型选择 GestureDetector 改造为包含 `auto_awesome` 芯片图标、加粗字体、下拉箭头和不小于 `48dp` 点击热区的 `InkWell` 按钮，提升高频功能点击的便利性。

17. **SharedPreferences 竞态防范**：`SettingsNotifier` 暴露 `initialization` 同步加载期 Future，并在流式生成前强制 `await` 确保配置完全拉取，从而杜绝由于异步偏好获取延迟导致 Bing 搜索误降级至 SearXNG 并报错的 Race Condition。

18. **工具链轮次超限强制文本响应**：在多轮 Tool calling 重试或循环（如 API 网络故障）达到 `toolRound >= 4` 上限时，剥离 tools 参数发起最后一次文本补全，迫使模型利用当前搜集到的上下文给出总结性文字，极大地提升了 Agent 链路的健壮性防止自动挂断。

19. **弹窗过渡动画延迟销毁**：在 `_showEditDialog` 与 `_confirmRollback` 中，将关闭对话框后的操作延迟增加到 `300ms`，让 Dialog 路由过渡动画充分收缩销毁后再 `dispose()` 关联的 `controller` 并更新 Riverpod 状态，杜绝由于动画期间 Widget 被提前注销或组件未挂载产生的 `_dependents.isEmpty` 断言崩溃。

20. **OpenCode Free 模型过滤与默认配置**：当选择 OpenCode Free API 时，自动过滤出仅包含 `'free'` 字段的免费模型列表，并将 `deepseek-v4-flash-free` 设定为初始默认选定模型。

21. **Google Grounding AI 搜索整合**：将 Google AI Studio 搜索接地输出的 AI 整合总结与原始 `groundingChunks` 链接一并解析封装，作为搜索返回列表呈现。这种既有 AI 预先提炼又附带真实来源链接的设计，既加速了后续大模型的理解，又保障了事实可靠性。
22. **正则表达式原始字符串替换**：在 Dart 中，正常字符串内的 `$1` 会被识别为表达式插值。为了在 `chat_bubble` 清理 Markdown 标记时使用正则匹配组替换，我们必须使用 Dart 原始字符串（`r'$1'`）规避插值编译错误。
23. **系统提示词 BottomSheet 延迟销毁防御**：在 `_showSystemPromptBottomSheet` 中使用 `await showModalBottomSheet` 并在关闭动效收尾后等待 300ms 再调用 `controller.dispose()`，消除 Flutter 框架 `_dependents.isEmpty: is not true` 的关联注销断言崩溃。
24. **Bing 搜索多词 `+` 编码与 `cvid` 账号历史跟踪**：使用 `+` 替换 `%20` 转义空格解决 Bing 国内节点多词分词截断问题；生成 UUID `cvid` 参数并补全 `form=QBLH` 与 Chrome 标头，保证带有 `bingCookie` 的搜素成功写入用户个人 Bing 搜索历史。
25. **新会话状态竞争（Race Condition）防范**：在 `ChatNotifier.loadMessages` 内为异步重置加锁防范，新建对话发消息时不被 `activeConversation` 回调重载冲刷，保证用户实时发送消息持续直观渲染。

---

## 🚀 下一步可能的开发方向

以下是一些可选的后续功能（均未开始）：

- **多语言 i18n 框架**：目前汉化通过硬编码实现，可迁移到 `flutter_localizations` + `intl` 进行规范化国际化管理。
- **文件导出功能**：对话历史导出为 Markdown / JSON。
- **语音输入**：集成 `speech_to_text` 插件实现语音转文字输入。
- **Agent 插件系统**：让用户自定义 Tool Call 扩展（除内置搜索外）。
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

# 运行全部测试（必须 153/153 通过）
D:\work\flutter-sdk\flutter\bin\flutter.bat test

# 编译 Debug APK
D:\work\flutter-sdk\flutter\bin\flutter.bat build apk --debug

# 提交并推送
git add -A && git commit -m "..." && git push
```
