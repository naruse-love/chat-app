# 项目接手上下文（Context）
> 最后更新：2026-07-13

---

## 🎯 项目总述

这是一个用 **Flutter** 开发的 Android AI Agent 移动端 App，连接 **9Router**（OpenAI 兼容 API 接口）。

- **工作目录**：`D:\work\chat`
- **Flutter SDK**：`D:\work\flutter-sdk\flutter\bin\flutter.bat`
- **Git 远程仓库**：`github.com:naruse-love/chat-app.git`（`main` 分支）
- **开发约束**：Benchmark 模式 —— `flutter test` 必须 100% 通过，`flutter analyze` 必须 0 问题

---

## ✅ 已完成的全部 Milestone

| Milestone | 描述 | 状态 |
|-----------|------|------|
| 1 | 数据模型与序列化（ModelInfo、ChatMessage、ApiConfig、ToolCall 等） | ✅ 完成 |
| 2 | 本地 SQLite 数据库（DatabaseHelper、ApiConfigDao、MessageDao、ConversationDao）+ 安全凭证存储（SecureStorageService） | ✅ 完成 |
| 3 | SSE 流解析（SseDecoder、SseParser）+ 网络 API（ChatService） | ✅ 完成 |
| 4 | 网络搜索与 Agent 调度（SearchService、AgentService） | ✅ 完成 |
| 5 | 图片服务（ImageService：压缩 / 选取 / Base64 编码）| ✅ 完成 |
| 6 | Riverpod 状态管理（7 个 Provider）+ 全套 UI 页面 | ✅ 完成 |
| 7 | E2E 集成测试（103 个测试用例） | ✅ 完成 |
| 8 | 对抗性异常加固（DB 损坏自愈、Vision 预检、网络错误分类） | ✅ 完成 |
| 汉化 | 全界面中文本地化（UI 文字、错误提示、SnackBar） | ✅ 完成 |
| 最终编译 | `flutter build apk --debug` 编译成功，产物位于 `build/app/outputs/flutter-apk/app-debug.apk` | ✅ 完成 |

**当前测试状态：108 / 108 测试用例全部通过，`flutter analyze` 0 issues。**

---

## 🏗️ 项目架构概览

```
lib/
├── main.dart                     # App 入口，路由注册，Riverpod ProviderScope
├── models/                       # 数据模型
│   ├── api_config.dart           # API 配置（name, baseUrl, apiKeyRef, isDefault）
│   ├── chat_message.dart         # 消息模型（含 reasoningContent, imagePath, toolCallId）
│   ├── conversation.dart         # 对话模型（含 isPinned, isArchived）
│   ├── model_info.dart           # 模型元数据（supportsVision, supportsTools）
│   ├── search_result.dart        # 搜索结果
│   ├── system_prompt_template.dart
│   └── tool_call.dart
│
├── data/                         # SQLite 数据访问层
│   ├── database_helper.dart      # 单例 SQLite 管理器（含损坏自愈逻辑）
│   ├── api_config_dao.dart       # API 配置 CRUD（含安全存储集成）
│   ├── conversation_dao.dart     # 对话 CRUD（含 pin/archive/sort）
│   └── message_dao.dart          # 消息 CRUD（含绝对/相对路径映射）
│
├── services/                     # 业务服务层
│   ├── chat_service.dart         # Dio HTTP 客户端，/v1/chat/completions SSE 流
│   ├── search_service.dart       # 9Router 搜索 + SearXNG 降级双模式
│   ├── agent_service.dart        # Tool Call 调度，chatAndSearchStream 流
│   ├── image_service.dart        # 图片选取 / 压缩 / Base64 编码
│   └── secure_storage_service.dart  # flutter_secure_storage 封装
│
├── providers/                    # Riverpod 状态管理
│   ├── theme_provider.dart       # ThemeMode（light/dark/system）
│   ├── api_config_provider.dart  # API 配置列表、活跃配置
│   ├── model_provider.dart       # 模型列表、选中模型
│   ├── conversation_provider.dart # 对话列表、活跃对话（含 clearActive bug 修复）
│   ├── chat_provider.dart        # 消息列表、流式生成、错误处理
│   ├── agent_provider.dart       # 工具调用状态（isSearching, searchQuery）
│   └── settings_provider.dart   # SearXNG URL、系统提示词模板
│
├── screens/                      # 页面
│   ├── home_screen.dart          # 主聊天页（侧边栏对话列表、消息气泡）
│   ├── settings_screen.dart      # 设置页
│   ├── api_config_screen.dart    # API 配置管理页（测试连接功能）
│   ├── model_selector_screen.dart # 模型选择页（按 provider 分组，带 Vision/Tools 标签）
│   └── system_prompt_screen.dart # 系统提示词模板管理页
│
└── widgets/                      # 可复用 Widget
    ├── chat_bubble.dart          # 消息气泡（Markdown、可折叠思考过程、图片预览）
    └── chat_input.dart           # 输入区（图片附件、发送、多行文本）

test/
├── unit tests (模型、服务、DAO)
├── widgets_test.dart             # ChatBubble、ChatInput Widget 测试
├── e2e_integration_test.dart     # Provider E2E 集成测试（主题、API、对话、流式消息）
└── adversarial_hardening_test.dart # 对抗性异常测试（DB 损坏、Vision 预检、网络错误）
```

---

## 🔑 关键技术决策

1. **SQLite 损坏自愈**：`DatabaseHelper._initDatabase()` 用 try-catch 包裹 `openDatabase`，失败时自动删除损坏文件并重建数据库。

2. **Vision 预检拦截**：`ChatNotifier.sendMessage()` 在发送带图片的消息前，检查 `selectedModel.supportsVision`，不支持则立即报错，防止 API 400。

3. **Riverpod mounted 保护**：`ConversationNotifier` 所有异步方法在 `await` 后均检查 `if (!mounted) return;`，防止 dispose 后写入状态抛出异常。

4. **copyWith clearActive**：`ConversationState.copyWith` 增加 `clearActive` 布尔参数，解决 Riverpod 中 `activeConversation` 无法设置为 null 的 Bug。

5. **图片永久路径存储**：`ImageService.compressAndSaveImage()` 将临时缓存图片压缩后复制到 `getApplicationDocumentsDirectory()`，SQLite 只存永久路径，防止系统清理缓存后图片丢失。

6. **双模式搜索降级**：`SearchService` 先调用 9Router 搜索 API，如失败则降级调用用户配置的 SearXNG 实例。

7. **SSE 流解析**：`SseParser` 处理 `data: ` 前缀、`[DONE]` 终止符及跨块 JSON 拼接，兼容 OpenAI 流式格式。

---

## 🚀 下一步可能的开发方向

以下是一些可选的后续功能（均未开始）：

- **多语言 i18n 框架**：目前汉化通过硬编码实现，可迁移到 `flutter_localizations` + `intl` 进行规范化国际化管理。
- **文件导出功能**：对话历史导出为 Markdown / JSON。
- **语音输入**：集成 `speech_to_text` 插件实现语音转文字输入。
- **Agent 插件系统**：让用户自定义 Tool Call 扩展（除内置搜索外）。
- **Release APK 签名打包**：目前只有 Debug APK，需要配置 keystore 进行 Release 签名。
- **通知支持**：长时间生成时后台推送通知。

---

## 📦 关键文件路径

| 文件 | 说明 |
|------|------|
| [WORK_LOG.md](../WORK_LOG.md) | 详细的开发日志，按 Milestone 记录所有变更与技术决策 |
| [implementation_plan.md](../implementation_plan.md) | 系统架构设计与各模块规划文档 |
| [build/app/outputs/flutter-apk/app-debug.apk](../build/app/outputs/flutter-apk/app-debug.apk) | 最新编译的 Debug APK |

---

## ⚙️ 常用命令

```bash
# 静态分析（必须 0 issues）
D:\work\flutter-sdk\flutter\bin\flutter.bat analyze

# 运行全部测试（必须 108/108 通过）
D:\work\flutter-sdk\flutter\bin\flutter.bat test

# 编译 Debug APK
D:\work\flutter-sdk\flutter\bin\flutter.bat build apk --debug

# 提交并推送
git add -A && git commit -m "..." && git push
```
