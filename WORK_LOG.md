## 2026-08-28 Feature: Milestone 23 Agent Tool Calling Architecture & Basic Built-in Tools Integration (v1.08.0+9)

### 变更文件
- `lib/models/tool/tool_parameter.dart`: 定义强类型参数模式 `ToolParameter`，支持类型校验、默认值与枚举限制。
- `lib/models/tool/tool_execution_result.dart`: 定义标准工具执行结果 `ToolExecutionResult`，包含状态、Markdown 输出、耗时与结构化元数据。
- `lib/models/tool/tool.dart`: 定义统一工具抽象基类 `Tool` 与导出接口。
- `lib/services/tools/math_eval_tool.dart`: 纯 Dart 零外部依赖数学表达式计算引擎，支持多重嵌套函数、阶乘、三角函数、统计与安全求值。
- `lib/services/tools/time_calculator_tool.dart`: 高精度时间/时区与日期运算工具，支持 IANA 时区查询、跨时区转换、日期偏移与持续时间计算。
- `lib/services/tools/weather_query_tool.dart`: 免费开源 Open-Meteo REST API 天气查询工具，自动地理编码与结构化多日预报。
- `lib/services/tools/wiki_lookup_tool.dart`: Wikipedia REST API 词条检索工具，支持跨语言检索与多维摘要。
- `lib/services/tools/legacy_tool_adapters.dart`: 遗留搜索与抓取服务适配器 (`WebSearchTool`, `GoogleSearchTool`, `BingSearchTool`, `UrlFetchTool`)。
- `lib/services/agent_loop_guard.dart`: RFC 1321 MD5 工具调用签名与多级防死循环保护器，支持连续重复判定、震荡周期检测与轮次上限防卫。
- `lib/services/tool_registry.dart`: 统一工具注册中心 `ToolRegistry`，支持运行时 CRUD、动态启停开关、OpenAI Schema 动态导出与安全等级过滤。
- `lib/services/agent_service.dart`: 全面接入 `ToolRegistry` 与 `AgentLoopGuard`，实现多轮安全工具调用分发、循环防御与兜底总结注入，保持 100% 向后兼容。
- `lib/providers/chat_provider.dart`: Riverpod `agentServiceProvider` 依赖注入 `toolRegistryProvider`。
- `lib/widgets/chat_bubble.dart`: 升级中间思考与工具调用卡片 UI，支持中文分类标签、安全等级徽章、独立工具卡片与代码参数展示。
- `test/services/basic_tools_test.dart`: 4 个基础工具的完整单元测试套件。
- `test/services/tool_registry_test.dart`: ToolRegistry 统一注册中心与适配器测试套件。
- `test/services/agent_loop_guard_test.dart`: AgentLoopGuard 防循环机制单元测试套件。
- `test/services/agent_service_tool_integration_test.dart`: Milestone 23.4 全链路多轮工具调用与循环防御端到端集成测试套件。
- `pubspec.yaml`: 按照 `AGENTS.md` 规则 6，版本号递增至 `1.08.0+9`。
- `.agents/context.md` & `WORK_LOG.md`: 更新 Milestone 23 完成记录与全景上下文。

### 核心改进
1. **全套内置基础工具库（零外部依赖）**：内置数学计算 (`math_eval`)、时间时区 (`time_calculator`)、免费天气 (`weather_query`)、维基百科 (`wiki_lookup`) 4 个安全 Level 0 核心工具。
2. **企业级防死循环保护与安全护栏**：通过 `AgentLoopGuard` 实时计算 MD5 签名并检测连续重复调用及周期震荡，在触发循环或达到轮次上限时自动移除工具并注入中文总结提示词，彻底杜绝 Agent 死循环死锁与 Token 耗尽风险。
3. **统一工具注册中心与优雅 UI 展现**：`ToolRegistry` 提供动态扩展能力与 Riverpod 响应式状态支持；`ChatBubble` 提供优雅的中文分类图标与卡片折叠交互。
4. **全套自动化测试覆盖**：新增 215+ 个高强度测试用例，全项目 382 个测试用例 100% 通过，`flutter analyze` 输出 0 issues。

---

## 2026-08-16 Feature: UrlFetchService v2 Intelligent Webpage Extraction & Diagnosis (v1.07.0+8)

### 变更文件
- `lib/models/fetch_result.dart`: 新增结构化网页抓取结果模型 `FetchResult` 与 `FetchMetadata`，支持标题、描述、作者、发布日期、语言、站点名、关键词、OG 协议标签、JSON-LD 数据、页面类型诊断（`article` / `doc` / `nav_hub` / `login_wall` / `captcha` / `error_page`）、截断感知标记及站内/站外链接统计。
- `lib/services/url_fetch_service.dart`: 全面重构升级 `UrlFetchService`：
  1. **截断感知与上限提升**：内容提取上限由 8000 字符提升至 15000 字符，超限时追加明确的 Markdown 截断警告与原始字符统计；
  2. **页面安全与类型诊断**：精准识别 Cloudflare/极验人机验证挑战（`captcha`）、知乎等登录墙（`login_wall`）、门户/导航合集（`nav_hub`）、文档代码页（`doc`）与文章（`article`），输出诊断警告提示；
  3. **丰富元数据提取**：深度解析 OpenGraph (`og:*`)、Twitter Card、HTML5 `<time>`、`<html lang>` 以及 `<script type="application/ld+json">` 结构化数据并智能回填补充；
  4. **正文优先提取与噪音剥离**：优先提取 `<article>`、`<main>`、`[role="main"]`、`.markdown-body` 等语义正文容器，解析前彻底剔除 `<nav>`、`<header>`、`<footer>`、`<aside>`、侧边栏及广告区块；
  5. **链接结构分析**：自动统计全页链接总数并区分站内链接与站外链接；
  6. **格式化输出**：自动生成结构清晰、分区明确的 Markdown 内容供大模型高效理解。
- `lib/services/agent_service.dart`: 更新 `urlFetchTool` 的 Function Description，向大模型清晰说明工具支持结构化元数据、截断感知、页面类型诊断与纯净正文提取。
- `test/url_fetch_service_test.dart`: 全面升级测试用例，覆盖截断警告、未截断状态、验证页检测、登录墙检测、JSON-LD 与 OG 元数据提取、语义正文容器优先与噪音剥离、站内/站外链接分析、导航合集识别以及各类 HTTP 错误状态。
- `test/gen5_empirical_verification_test.dart`: 同步更新截断上限测试至 15000 字符与截断标记断言。
- `pubspec.yaml`: 按照 `AGENTS.md` 规则 6，版本号递增至 `1.07.0+8`。
- `.agents/context.md` & `WORK_LOG.md`: 更新 Milestone 22 记录与当前版本状态。

### 核心改进
1. **彻底解决大模型被截断内容误导的隐患**：大幅提升正文容量上限至 15000 字符，并在超限时提供明确截断标记，使 Agent 能够准确感知内容完整性。
2. **彻底解决反爬验证页与登录页误判为正文的问题**：通过多重特征规则检测验证码与登录墙，及时向 Agent 输出诊断警告，避免 Agent 误读无效内容。
3. **大幅提升正文质量与元数据丰富度**：通过语义容器优先和噪音剥离彻底解决 MDN/维基百科等侧边栏噪音占据 80% Token 的问题；通过 JSON-LD/OG 解析提供作者、发表时间、站点等高价值事实依据。

---

## 2026-08-14 Documentation & Quality: Comprehensive README.md Overhaul (v1.06.0+7)

### 变更文件
- `README.md`: 全面重构并丰富项目文档，新增项目 Badges 状态标识、核心功能亮点（OpenAI 全兼容、免 Key 直连、多轮 Agent Tool Calling、DSML/XML 兜底、SearXNG/Bing/Google 搜索、结构化 url_fetch 网页抓取、深度思考链可视化、企业级自愈架构）、系统架构 Mermaid 拓扑图、代码目录结构树、环境配置与快速开始、全套 167 个单元与集成测试矩阵、网络搜索与提示词配置指南、稳定性自愈设计、路线图及开发协作规范。
- `pubspec.yaml`: 按照 `AGENTS.md` 规则 6，版本号递增至 `1.06.0+7`。
- `.agents/context.md` & `WORK_LOG.md`: 更新 Milestone 21 记录与当前版本状态。

### 核心改进
1. **完善全景项目文档**：将原本简陋的默认 Flutter 模板升级为企业级开源规范的 README 文档，大幅提升项目的可读性、展示度与上手易用性。
2. **详尽的配置与架构说明**：系统化阐述了数据模型、DAO、Riverpod Provider、Service 架构与核心功能配置（如 Bing Cookie 提取、SearXNG 私有部署、系统提示词模板等）。
3. **测试质量公示**：明确标注全套 167 个单元/集成测试用例覆盖范围及静态分析 0 issues 质量保证。

---

## 2026-08-03 Fixes & Feature Enhancements: Disable Session Swipe Gestures, Global Search Toggle & Structured url_fetch Metadata (v1.05.0+6)

### 变更文件
- `lib/screens/home_screen.dart`: 移除会话列表项上的 `Dismissible` 滑动手势包装器，彻底防止误删对话，置顶/归档/删除功能统一保留在右侧 3 点 PopUp 菜单中。
- `lib/screens/settings_screen.dart`: 在【网络搜索设置】区域增加「启用 AI 网络搜索」开关 (`enableAutoSearch`)。
- `lib/services/agent_service.dart` & `lib/providers/chat_provider.dart`: 在 `getEffectiveTools` 及流式生成方法中传递 `enableAutoSearch` 标志；当开关关闭时不再向 AI 模型透传 `web_search` / `google_search` / `bing_search` 搜索 Tool Call。
- `lib/services/url_fetch_service.dart`: 全面升级网页抓取服务，自动提取 HTML `<title>`、`<meta description/author/keywords/og:*>` 元数据，自动转换 `<table>` 节点为标准 Markdown 表格，并生成包含 Header 与元数据区块的结构化 Markdown 输出；增加现代 User-Agent 头与 HTTP 403 (WAF/Cloudflare) 阻断友善提示。
- `lib/services/search_service.dart`: 优化搜索关键词清洗与双引擎 (`google_bing`) URL 去重机制。
- `pubspec.yaml`: 按照 `AGENTS.md` 规则 6，版本号递增至 `1.05.0+6`。
- `.agents/context.md` & `WORK_LOG.md`: 更新 Milestone 20 记录。

### 核心改进
1. **彻底解决会话列表误删问题**：移除侧边栏 `Dismissible` 划动手势，置顶与删除统一保留在右侧 3 点菜单，操作更安全可靠。
2. **新增全局网络搜索控制开关**：用户可在设置中自由开启/关闭 AI 网络搜索。关闭后，Agent 生成过程屏蔽所有搜索工具调用。
3. **`url_fetch` 抓取结构化与元数据提炼**：使 AI 抓取外部网页时能够清晰直观掌握 Title、Author、Description、Keywords 及表格数据，大幅提升信息提取效率与理解准确度。

---

## 2026-07-21 Fixes: Bing Cookie Propagation Fix, Bing AI Summary, & UI Error SnackBar (v1.04.0+5)

### 变更文件
- `lib/services/agent_service.dart`: 修复在流式生成开始的第一个 AI 自动搜索步骤（`_streamCompletionsLoop` 内部）忘记传递 `bingCookie` 的致命 Bug，确保所有搜索请求均正确携带 Cookie。
- `lib/services/search_service.dart`: 增强 Bing 搜索 HTML 解析，新增提取微软官方 AI 总结栏（`.cht_root` / `[data-scenario="nrt"]`）内容并作为首要 `SearchResult` 插入上下文的逻辑。
- `lib/providers/chat_provider.dart`: 精确等待设置项完全载入，在 `_startStreaming` 中使用 `settings.isLoaded` 属性，保证获取到最新的 cookie 等设置值。
- `lib/screens/home_screen.dart`: 在 `build` 中使用 `ref.listen` 全局监听 `ChatState.error`，在请求或流传输失败时自动展示 SnackBar 提示，解决了之前报错静默失败、用户界面无感知的重大 Bug。
- `test/search_service_test.dart`: 增加提取 Bing 搜索 AI 总结（`.cht_root`）的单元测试。
- `pubspec.yaml`: 按照 `AGENTS.md` 规则将版本号由 `1.03.0+4` 提升至 `1.04.0+5`。
- `.agents/context.md` & `WORK_LOG.md`: 追加 Milestone 19 记录。

### 核心改进
1. **彻底解决首次 AI 搜索不带 Cookie 的隐藏 Bug**：通过修复 `agent_service.dart` 内部首轮自动搜索调用 Dio/SearchService 时遗漏 `bingCookie` 的问题，确保无论是在手动搜索还是自动 AI 多轮调用中，均能百分之百注入 Bing Cookie。
2. **提取 Bing 搜索内置 AI 总结栏**：将 Bing 页面顶部的微软 AI 生成总结以 “Bing AI 搜索总结” 为标题注入搜索结果，极大提升了 AI 获取高价值参考资料的精度和速度。
3. **新增全局错误 SnackBar 反馈**：当模型请求失败时，不再发生静默转圈/退回重新响应的诡异无提示现象，而是会在页面底端清晰直观地弹出 SnackBar 错误横幅反馈（如 API key 错误、网络超时等），优化了交互体验。

---

## 2026-07-21 Fixes: Settings Loader Race, DSML parser & Call Limits (v1.03.0+4)

### 变更文件
- `lib/providers/settings_provider.dart`: 修复 settings 异步加载竞态，只有在 state 完全赋值后才将 `isLoaded` 设置为 `true`。
- `lib/services/agent_service.dart`: 扩展 `parsePseudoXmlToolCalls` 与 `stripPseudoXmlToolCalls` 函数，完美支持 DeepSeek 等模型输出的 DSML 格式工具调用 (`<｜｜DSML｜｜tool_calls>...`，支持全角及半角斜杠)；修正伪 XML 兜底递归分支中丢失 `bingCookie`、`reasoningEffort` 的 Bug；将 `chatAndSearchStream` 的默认最大工具轮数限制 `maxToolRounds` 扩展至 `100` 轮，事实上解除低上限约束。
- `test/agent_service_test.dart`: 增加 DSML 格式解析与剥离的单元测试，并在最大轮数限制测试中显式传递 `maxToolRounds: 10`。
- `pubspec.yaml`: 按照 `AGENTS.md` 规则将版本号由 `1.02.0+3` 提升至 `1.03.0+4`。
- `.agents/context.md` & `WORK_LOG.md`: 追加 Milestone 18 接手上下文记录。

### 核心改进
1. **解决首次搜索丢失 Cookie 等配置的问题**：由于 settings 初始化期间 `isLoaded = true` 设置过早（早于 state 变量最终写入和通知），导致第一次触发流时 chatProvider 误读到了空白的默认配置（未带 bingCookie 等参数）。修复后，首次运行便可稳定应用正确配置。
2. **完美支持 DSML 格式工具调用**：彻底解决了部分接口/模型输出伪 XML 时，因其使用 `<｜｜DSML｜｜tool_calls>` 自定义标志导致解析器未匹配到工具而自动中断响应的 Bug。
3. **修复多轮递归丢失 Cookie 等参数的问题**：修复了在伪 XML 兜底的多次递归中，前一轮搜索携带的 `bingCookie` 和 `reasoningEffort` 在后面的循环迭代中未往下传的隐藏 Bug。
4. **提升调用上限**：默认最大轮数上限提至 100 轮，不再局限于 10 轮。

---

## 2026-07-21 Fixes: Bing User-Agent WAF Block Fix & Version Bump (v1.02.0+3)

### 变更文件
- `lib/services/search_service.dart`: 修复 Bing 搜索请求头 `User-Agent` 中多余拼接导致格式异常的致命 Bug（将 `Safari/126.0.0.0 Safari/537.36` 还原为标准 Chrome 126 请求头）；将 `Sec-Fetch-Site` 调整为 `none`；新增对微软 Azure FrontDoor WAF 拦截页面 (`The request is blocked`) 的显式捕获与友好中文提示。
- `test/search_service_test.dart`: 增加 Bing WAF 阻断识别的单元测试。
- `pubspec.yaml`: 按照 `AGENTS.md` 规则将版本号由 `1.01.0+2` 提升至 `1.02.0+3`。
- `.agents/context.md` & `WORK_LOG.md`: 追加 Milestone 17 接手上下文记录。

### 核心改进
1. **彻底修复 Bing 无法搜索（无论填不填 Cookie 都报阻断/空结果）的问题**：由于此前的 User-Agent 字符串拼接有误，被微软 Bing 防火墙一律识别为伪造爬虫机器并在后端直接返回 `The request is blocked.`（导致抽取结果全部为空）。修正 User-Agent 格式后，Bing 搜索恢复全面正常。
2. **WAF 防火墙拦截异常显示**：万一未来因 IP 封禁或极高频请求被 Bing 再次拦截，能够直观提示 `The request is blocked` 原因。

---

## 2026-07-20 Fixes & Agent Rule: Bing Cookie Forwarding & Version Increment Rule (v1.01.0+2)

### 变更文件
- `lib/services/search_service.dart`: 增加了 `cleanCookieString` 函数清洗 Bing Cookie 格式（自动剥离 `Cookie:` 前缀与换行符）；改造重定向逻辑为 5 轮显式 `followRedirects: false` 循环，保证每次跨域/子域名跳转（如 `www.bing.com` -> `cn.bing.com`）均强制带上 Cookie，并动态合并响应头中的 `Set-Cookie`；扩充 HTML DOM 解析选择器（支持 `.b_algo`、`header`、`.b_title` 等多种组合及 Title 回退策略）；增加反爬/验证码页面识别，优化已填 Cookie 场景下的错误提示文案。
- `test/search_service_test.dart`: 增加 `cleanCookieString`、多跳转 Cookie 透传与错误提示分流的单元测试。
- `.agents/AGENTS.md`: 新增约束规则 6（版本号递增规范），要求每次新增功能、修 bug 或修改代码必须将版本号递增 0.01。
- `pubspec.yaml`: 项目版本号由 `1.0.0+1` 提升至 `1.01.0+2`。
- `.agents/context.md` & `WORK_LOG.md`: 追加 Milestone 16 接手上下文记录。

### 核心改进
1. **解决 Cookie 设置后仍报未提取到结果问题**：修复用户在 copy-paste 时自带 `Cookie:` 或换行符导致的 Cookie 格式失效；解决跨域跳转后续 Request Header 丢失 Cookie 的 bug，实现 Set-Cookie 自动继承与 5 轮防剥离重定向。
2. **错误提示精准化**：已填 Cookie 但 Cookie 失效/页面结构变动时，明确提示“可能是 Cookie 已失效过期或 Bing 变更了页面结构”，消除用户误以为 Cookie 没填成功的疑虑。
3. **Agent 开发规范升级**：为项目迭代引入强制递增版本号 0.01 的防漏追踪机制。

---

## 2026-07-20 Fixes: Bing Multi-Word Search & Cookie Forwarding Fix

### 变更文件
- `lib/services/search_service.dart`: 彻底修复 Bing 搜索中多词短语结果错乱的问题（解决“我的世界 红肠配音 梗”被截断降级的问题）；修复 Bing Cookie 设置后未生效的问题。

### 核心改进
1. **解决 Bing 搜索多词分词错乱问题**：发现在直接请求 `cn.bing.com` 或被重定向时，Bing 会触发严格的国内关键字过滤和降级分词策略，导致多词查询结果偏离。解决方案是在请求 URL 中追加 `&cc=us&setlang=zh-hans`，强制使用 Bing 全球端点但保留中文结果，成功绕过分词截断。
2. **解决 Bing Cookie 不生效/历史记录不互通问题**：发现 `Dio` 的底层 `HttpClient` 在处理 `www.bing.com` 到 `cn.bing.com` 跨域重定向时，出于安全策略会自动剥离手动设置的 `Cookie` Header。解决方案是配置 `followRedirects: false`，手动拦截 `301/302/307` 重定向并重新注入 `Cookie`，确保携带用户凭据完成最终请求。

---

## 2026-07-20 Fixes: New Conversation Message Visibility & Bing Multi-Word Search History Fix

### 变更文件
- `lib/providers/chat_provider.dart`: `loadMessages` 增加判断，防止新会话建立时 `ref.listen` 在发送中途触发并把包含当前用户消息的 UI `state` 重置清空；`ref.listen` 增加 `previous?.id != next?.id` 判断。
- `lib/services/search_service.dart`: Bing 搜索请求查询词使用 `+` 替换 `%20` 转义空格，防止 Bing 将多词查询降级/截断为第一个字（解决搜索“我的世界 红肠配音 梗”变成搜索“我”的 Bug）；生成 `cvid`（Correlation Vector ID）并补齐 Chrome 桌面端标准 headers（`Sec-Ch-Ua`、`Sec-Fetch-*`）与 `form=QBLH` 参数，使带 `bingCookie` 的搜索请求能被 Bing 成功记录至用户个人账号搜索历史。
- `test/search_service_test.dart` & `test/opencode_free_test.dart`: 更新单元测试断言与微任务延迟，保证全套测试通过。

### 核心改进
1. **修复新对话发送消息后自身消息隐形问题**：新对话发送消息不再因 `activeConversation` 变化回调重载而抹除刚插入的用户消息，实时消息展示恢复正常。
2. **修复 Bing 多词组合搜索结果偏离问题**：多词短语搜索结果与网页真实 Bing 搜索结果完全一致。
3. **支持 Bing 搜索历史记录同步**：在填入 Bing Cookie 后，AI Agent 发起的 Bing 搜索会自动记录到用户 Bing 个人账号的搜索历史中。

---

## 2026-07-20 Fixes & Improvements: System Prompt Dialog Fix, Default System Prompt Template, Bing Cookie & Search Optimization

### 变更文件
- `lib/screens/home_screen.dart`: `_showSystemPromptBottomSheet` 改用 `await showModalBottomSheet` 配合 300ms 延迟释放 `controller`，解决关闭动画中依赖泄露导致的 `_dependents.isEmpty: is not true` 框架断言崩溃。
- `lib/screens/system_prompt_screen.dart`: 为每个系统提示词增加“设为默认系统提示词”菜单项；对于当前默认的系统提示词增加 `[默认]` Chip 视觉标识。
- `lib/providers/settings_provider.dart`: `AppSettings` 与 `SettingsNotifier` 增加 `bingCookie` 状态，使用 `SecureStorageService` 进行安全存储。
- `lib/screens/settings_screen.dart`: 在网络搜索设置部分新增“Bing 登录 Cookie (可选)”带明文/密文切换的输入框。
- `lib/services/search_service.dart`: `_searchBing` 支持在 Request Headers 中注入 `Cookie`；实现 `_decodeBingUrl` 自动解密 Bing 重定向短链（如 `/ck/a?!...&u=a1...`）为真实目标网页 URL；完善 DOM 多节点回退提取选择器。
- `lib/services/agent_service.dart` & `lib/providers/chat_provider.dart`: 将 `settings.bingCookie` 透传至 `chatAndSearchStream` 与 `SearchService.search`。
- `test/*`: 补充/更新 Mock 签名与测试用例，全套 159 个单元测试 100% 通过。

### 核心改进
1. **彻底修复系统提示词编辑崩溃**：消除了 Flutter BottomSheet 关闭动画过程中的 Controller 提前 dispose 崩溃。
2. **默认系统提示词管理**：用户可以在模板列表自由指定任意提示词为全局默认提示词，并在界面上实时呈现 `[默认]` 标识。
3. **Bing 搜索质量与反爬解封**：支持填入 Bing 登录 Cookie 恢复完整搜素与个人账号，自动解密 Base64 编码的 Bing 跟踪重定向链接为真实 URL，并提供增强版 DOM 解析机制。

---

## 2026-07-20 Features & Fixes: Selection Box, Search Decoupling, OpenCode Reasoning Effort, URL Fetch Markdown, Switching Deadlock Fix

### 变更文件
- `lib/widgets/chat_bubble.dart`: 长按文本菜单新增“自由选择文本”弹窗 (`SelectableText`)；过程消息卡片增加 `toolCalls` (方法名与 JSON 参数) 回显，解决 hy3 等无思考文本模型的空面板问题。
- `lib/services/agent_service.dart`: 明确 `google_search` 与 `bing_search` 单独工具定义，`google_bing` 模式同时下发双工具由 AI 自由选择调用；下发 `reasoningEffort` 思考等级参数。
- `lib/services/url_fetch_service.dart`: 响应格式改用 `bytes` + `utf8.decode(..., allowMalformed: true)` 防乱码；实现 HTML DOM 结构化提取器 (`_parseHtmlToStructuredMarkdown`)，保留标题、段落、列表、链接与表格。
- `lib/services/chat_service.dart`: API 请求 Payload 新增 `reasoning_effort` 字段透传。
- `lib/providers/settings_provider.dart`: `AppSettings` 与 `SettingsNotifier` 新增 `reasoningEffort` (`'none'`, `'low'`, `'medium'`, `'high'`) 设置。
- `lib/providers/chat_provider.dart`: `sendMessage` 使用 `try-finally` 确保 `_sendingInProgress = false` 重置解锁；`loadMessages` 切换会话时自动取消上一次流生成；透传 `reasoningEffort`。
- `lib/screens/settings_screen.dart`: 更新搜索后端按钮文案；新增“模型思考设置”段落控制 `reasoningEffort`。
- `lib/screens/home_screen.dart`: `_scrollToBottom` 增加 post-frame 延迟处理，修复长历史会话重入与切换无法到达底层问题。
- `test/*`: 修复/更新 `MockChatService` 与 `UrlFetchService` 单元测试，保证所有 158 个测试用例 100% 通过。

### 核心改进
1. **长按自由文本选择与复制**：用户长按消息弹窗支持点击“自由选择文本”，调出标准选择游标与复制浮条。
2. **Google 与 Bing 双独立搜索工具**：解耦混合搜索为 `google_search` 与 `bing_search`，AI 可自由选择单一或并行工具调用。
3. **OpenCode Free 思考等级设置**：支持设置 `reasoningEffort` 并透传至 API。
4. **网页抓取排版与中文/英数提取增强**：保留 HTML 级排版结构（标题 `#`、列表 `-`、链接与表格）。
5. **切换会话卡死与滚动底端自适应修复**：解耦发送状态锁，自动切断旧会话流，多阶段平滑滚动底端。

---

## 2026-07-18 Maintenance: Multi-Round 10-Limit collapse, AI Copy Plain/Markdown, and Google Search Grounding

### 变更内容
1. **多轮工具链上限调整与中途所有消息折叠**：
   - 在 `lib/services/agent_service.dart` 中将最大工具调用/思考轮次限制提高到 10 轮（`toolRound >= 9`）。并在第 10 轮最终请求时，注入系统消息提示词（指引模型给出最终回答并绝对不要使用工具或输出 `<tool_call>` 伪 XML），从而保证生成结果完整且没有冗余的裸标签。
   - 重构了中途消息的折叠逻辑：除了最后的输出结果（无 `toolCalls` 的 assistant 最终文本消息显示为常规 Markdown，其思考面板默认折叠）之外，中途的所有过程消息（包括带 `toolCalls` 的过程 assistant 消息，以及所有 `role == 'tool'` 的工具响应消息）全部通过在 `lib/widgets/chat_bubble.dart` 中封装为 collapsible cards 进行默认折叠隐藏，大幅简化和清洁了多轮调用时的界面。
2. **AI 输出内容长按复制（纯文本与 Markdown）**：
   - 在 `lib/widgets/chat_bubble.dart` 中实现了 `_stripMarkdown` 工具函数，用于清洗标准的 Markdown 符号（如粗体、斜体、标题、代码块、链接等）。
   - 在长按消息底栏操作中，为 Assistant 消息增加了“复制纯文本”（已清洗 Markdown 符号）与“复制 Markdown”（复制原始带标记格式），为 User 消息增加了“复制文本”，并追加了 SnackBar 复制成功的浮动通知。
3. **支持谷歌 AI Studio 搜索接地 (Search Grounding) 配置与参数透传修复**：
   - 扩展了 `AppSettings` 与 `SettingsNotifier`（`lib/providers/settings_provider.dart`），增加了对 `googleSearchApiKey`（使用 `SecureStorageService` 安全存储）、`googleSearchBaseUrl`（存储在 SharedPreferences，支持 VPS 反代）以及 `googleSearchModel`（存储在 SharedPreferences，用于指定搜索接地的 Gemini 模型，默认为 `gemini-2.5-flash`）的读写和加载管理。
   - 升级了设置页（`lib/screens/settings_screen.dart`），支持在“搜索后端”多段按钮中选择 `Google Grounding` 模式，并提供含有隐藏/展开按钮的 API Key 输入框、Base URL 输入框以及 Grounding Model 配置框。
   - 修复了 `agent_service.dart` 的 `chatAndSearchStream` 在发起首轮工具调用搜索时未将 `googleApiKey` 与 `googleBaseUrl` 传入 `SearchService.search` 的严重 Bug（导致首轮执行 Google Grounding 时报错提示未配置 API 密钥），并在所有搜索调用中完成了 `googleSearchModel` 字段的安全下发透传。
   - 实现并接入 `SearchService._searchGoogle`（`lib/services/search_service.dart`），使用 Gemini API `google_search` 搜索接地工具并动态根据配置选择 Gemini 模型，提取生成的总结作为首条 AI 总结结果，并提取 `groundingChunks` 包含的来源网页作为辅助搜索结果回传。
4. **修复搜索接地模型重启被自动重置问题**：
   - 在 `AppSettings` 中增加了 `isLoaded` 属性，并在 `SettingsScreen` 中引入了 `_hasSynced` 状态。在 settings 初始化异步读取 prefs 时，只有当 settings 确实加载完毕且尚未 sync 过时才会重写 TextControllers 的 text，有效杜绝了因异步加载延迟导致 TextField 回退至硬编码默认值 `gemini-2.5-flash` 的问题。
5. **支持 Bing 和 Google Grounding 并行双搜 (Google+Bing)**：
   - 在 Settings 搜索后端新增了 `google_bing` (Google+Bing) 多段选择按钮。
   - 在 `SearchService.search` 中新增了 `google_bing` 双搜后端，利用 `Future.wait` 并行发起 Google Grounding 与 Bing 搜索请求，并对每一路使用 `catchError` 进行异常熔断隔离，确保任何一方故障时不至于导致整体搜索失败，最后合并二者的网页结果。
6. **精简网络搜索结果上下文的系统提示词**：
   - 移除了 `SearchService.formatSearchResultsForContext` 中头部诸如“以下是网络搜索结果。请仔细阅读后基于这些信息回答用户问题”等一长串赘余的提示文字，仅回传纯净的搜索结果及其摘要列表，保持 prompt 精简化并移除对模型的干扰。
7. **修复编辑消息在有光标时取消导致的框架崩溃 Bug**：
   - 在 `_showEditDialog` 弹出层取消（或 newText 为空）时，之前会同步调用 `controller.dispose()`，若此时输入框处于聚焦/输入状态，会导致 Flutter 框架在 Dialog pop 动画播放完毕前销毁 Controller 从而引发 `_dependents.isEmpty: is not true` 的断言崩溃。
   - 修复逻辑：将等待 300ms pop 动画执行完毕和 `controller.dispose()` 的动作统一置于 `await showDialog` 之后执行，彻底消除崩溃。
8. **修复过程消息卡片标题文本超长导致布局溢出（Right Overflowed / 黄黑条纹斑马线）Bug**：
   - 在 `lib/widgets/chat_bubble.dart` 的 `_buildIntermediateAssistantPanel` 中，为中间过程消息面板标题中的工具名称文本控件（`Text`）外层增加了 `Flexible` 包装，并配置了 `maxLines: 1` 和 `overflow: TextOverflow.ellipsis`。
   - 彻底解决了当模型进行多次连续工具调用（如 `web_search, web_search, web_search`）时，工具名称连写过长超出屏幕右侧边界（溢出 37 像素）触发 Flutter 调试模式黄黑横条警告与 `RIGHT OVERFLOWED BY 37 PIXELS` 的 UI 错误。

### 变更文件
- `lib/providers/settings_provider.dart`
- `lib/providers/chat_provider.dart`
- `lib/services/agent_service.dart`
- `lib/services/search_service.dart`
- `lib/screens/settings_screen.dart`
- `lib/widgets/chat_bubble.dart`
- `test/agent_service_test.dart`
- `test/search_service_test.dart`
- `test/challenger_web_search_empirical_test.dart`
- `test/e2e_integration_test.dart`
- `WORK_LOG.md`

### 状态
- 静态分析 `flutter analyze` 报告：`No issues found!`。
- 单元测试与 Widget 测试 `flutter test` 报告：`158 / 158` 测试用例全部 100% 串行通过（0 failures）。

### 技术决策
- **AI 搜索总结结合来源链接回显**：Gemini 搜索接地不仅会产生来源引用链接（`groundingChunks`），还直接给出一个由谷歌大模型针对当前 query 整合的高质量 Grounded Summary。我们在 `SearchService` 中将这一 AI 总结与其它网页来源一并作为 `SearchResult` 包装回传，既减轻了主模型在合并多网页时的负担，又最大化还原了 Google AI Studio Grounding 的优势。
- **Raw Regex 避免 interpolation**：在 Dart 的普通单引号/双引号字符串中，`$1` 这种针对正则匹配组的变量会被解释为 Dart 语法字符串插值（String Interpolation）标识，因 `1` 不是有效标识符导致编译失败。我们通过使用 Raw String (`r'$1'`) 来彻底忽略 Dart 插值处理，确保正则替换顺利编译。

---

## 2026-07-16 Remediation: UI Touch Target, OpenCode Free Filtering, Bing Search Setup Race Condition & Dialog Animation Crash Fixes


### 变更内容
1. **模型选择热区与外观优化**：在 `lib/screens/home_screen.dart` 中为模型选择栏增加了包含 `auto_awesome` 标识图标、加粗字体、下拉箭头，且包含充足 Padding（`10.0` 水平, `4.0` 垂直）的 `InkWell` 按钮，将点击热区提升至符合标准的 `48dp`，交互极为便利。
2. **OpenCode Free 免费模型过滤与默认设定**：在 `lib/providers/model_provider.dart` 的 `fetchModels` 方法中，如果当前激活配置为 `opencode_free`，则自动对模型列表（包括 API 请求结果及 Fallback 默认列表）执行过滤，只保留 ID 含有 `'free'`（不区分大小写）的免费模型，并自动将默认初始选中的模型设为 `deepseek-v4-flash-free`。并在 `test/opencode_free_test.dart` 中追加了该过滤与默认选中行为的单元测试。
3. **Bing 搜索配置竞态与自动停止加固**：
   - 为 `SettingsNotifier` 暴露 `initialization` 同步加载期 Future。在 `lib/providers/chat_provider.dart` 的 `_startStreaming` 启动时，如果 Settings 尚未从 SharedPreferences 完成异步加载，则主动进行 `await` 确保 settings 加载完毕后，再读取用户设置的搜索后端。这彻底消除了冷启动时由于读取到默认配置 `'searxng'` 且未配置 SearXNG URL 而误报错“未配置 SearXNG 地址”的竞态问题。
   - 优化 `lib/services/agent_service.dart` 中 Tool Round 超过限制的机制。当多轮工具调用或因为接口限流重试导致轮数达到上限（`toolRound >= 4`，即第5轮）时，不再直接 `return` 停止流，而是**强制发起最后一次不含 `tools` 的聊天补全请求**，逼迫模型给出最终的文字答复，确保用户始终能接收到总结性的反馈，不会莫名其妙地自动停止生成。同时更新了 `test/agent_service_test.dart` 的单元测试。
4. **编辑与回退弹窗销毁 Crash 修复**：在 `lib/screens/home_screen.dart` 的 `_showEditDialog` 与 `_confirmRollback` 中，将关闭对话框后的延迟等待由 `50ms` 提升为 `300ms`，使得 Dialog 完全从 Navigator 路由栈中动画关闭且彻底销毁后，才执行 `controller.dispose()` 以及更新 Riverpod 的状态并触发 UI 重建，从而彻底消存在 `TextEditingController` 被提前释放、以及在动画中由于状态变化触发的 `_dependents.isEmpty` 断言崩溃。

### 变更文件
- `lib/providers/settings_provider.dart`
- `lib/providers/chat_provider.dart`
- `lib/providers/model_provider.dart`
- `lib/services/agent_service.dart`
- `lib/screens/home_screen.dart`
- `test/agent_service_test.dart`
- `test/opencode_free_test.dart`
- `WORK_LOG.md`

### 状态
- 静态分析 `flutter analyze` 报告：`No issues found!`。
- 单元测试与 Widget 测试 `flutter test` 报告：`153 / 153` 测试用例全部 100% 通过（0 failures）。

### 技术决策
- **强制兜底文本响应**：对于代理多轮 Tool Calling 时极易发生循环调用（特别是因网络或 API 错误报错导致模型陷入反复搜索）的问题，我们在工具使用达到上限时强制剥离 `tools` 参数发送最后一轮请求，利用 LLM 本身总结和理解当前对话上下文的能力，在无法继续搜索时给用户生成一份最终解释或说明，极大提高了 App 生成链路的韧性。
- **对话框延迟路由等待**：Flutter 路由动画需要一定时间，在此期间被 pop 掉的 Widget 仍留在树上，此时调用其关联的 `TextEditingController.dispose()` 会导致被销毁组件试图使用已释放对象。因此必须等待 300ms 完整关闭过渡动画后再清理，并在 Context 确认 Mounted 状态后才写 Riverpod 状态。

---

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


