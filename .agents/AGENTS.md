# AI Agent 开发规则（AGENTS.md）
> 此文件用于为接手此项目的 AI Agent 提供开发约束与行为规范。

---

## 📍 项目状态

**所有 Milestone（1–8）已全部完成，项目目前处于维护/迭代阶段。**

在开始任何代码修改前，必须先阅读 [context.md](./context.md) 恢复完整上下文。

---

## 🔒 开发约束（不可违反）

### 1. 测试必须 100% 通过
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat test`
- **所有 127 个测试用例必须全部通过**（0 failures）
- 每次代码变更后必须重跑测试，严禁提交带测试失败的代码

### 2. 静态分析必须 0 问题
- 运行 `D:\work\flutter-sdk\flutter\bin\flutter.bat analyze`
- **必须输出 `No issues found!`**，不接受任何 warning 或 error

### 3. Git 提交规范
- 每个有意义的变更必须 commit，commit message 使用 `feat:` / `fix:` / `test:` / `refactor:` 前缀
- 提交后必须执行 `git push`

### 4. WORK_LOG.md 必须更新
- 每次 Milestone 级别的变更，必须在项目根目录 `WORK_LOG.md` 的**顶部**追加记录
- 内容包括：变更文件列表、当前状态、技术决策

### 5. 错误信息使用中文
- 所有面向用户的 UI 文字、错误提示、SnackBar 内容均已汉化为中文
- 新增功能时，必须沿用中文用户界面风格

### 6. 版本号递增规范
- 每次新增功能（feat）、修 bug（fix）或变更代码，必须给项目版本号增加 0.01（在 `pubspec.yaml` 的 `version` 字段，以及 `WORK_LOG.md` / `context.md` 等相关版本标注处同步递增）


---

## 🏗️ 代码规范

### 状态管理（Riverpod）
- 使用 `StateNotifier` + `StateNotifierProvider`，不使用 `ChangeNotifier`
- 异步 StateNotifier 方法内，所有 `await` 之后必须检查 `if (!mounted) return;`
- `copyWith` 方法中，可空字段（如 `activeConversation`）必须通过 `clearActive` 类标志参数处理，禁止直接传 null 导致 fallback

### 数据库
- 所有 SQLite 操作通过对应 DAO（`ApiConfigDao`、`ConversationDao`、`MessageDao`）进行，禁止在 Provider 或 Widget 中直接调用 `db.rawQuery`
- API Key 只能通过 `SecureStorageService` 存储，数据库中只存 `apiKeyRef`（引用键）

### 测试
- 单元测试使用 `sqflite_common_ffi` + `databaseFactoryFfi` 进行内存数据库测试
- 需要 `FlutterSecureStorage` 的测试必须使用 `MockFlutterSecureStorage`（基于 `noSuchMethod`）
- 需要 `SharedPreferences` 的测试必须调用 `SharedPreferences.setMockInitialValues({})`
- Riverpod Provider 在构造器内启动异步加载时，测试中需在 `container.read` 后执行 `await Future.delayed(const Duration(milliseconds: 50))` 挂起微任务，避免竞态

### 图片处理
- 图片必须通过 `ImageService.compressAndSaveImage()` 压缩并存至 `getApplicationDocumentsDirectory()`
- 数据库只存储永久路径（非临时缓存路径）
- 发送带图片的消息前，必须检查 `selectedModel.supportsVision`

---

## 📂 保留的 .agents 目录

| 目录 | 作用 |
|------|------|
| `orchestrator/` | 初代 orchestrator（Milestone 1-2 阶段参考） |
| `orchestrator_gen3/` | 第三代 orchestrator，含详细 Milestone 1-2 完成记录 |
| `orchestrator_gen4/` | 第四代 orchestrator，含 Milestone 5-8 完成记录（最终状态） |
| `sentinel/` | 上层监控 Agent 的 handoff 记录 |
| `victory_verifier/` | 最终验收 Agent 的记录 |
| `context.md` | **本项目完整接手上下文**（最重要，必读） |
| `AGENTS.md` | **本文件**，AI Agent 开发规则 |
| `ORIGINAL_REQUEST.md` | 用户的原始任务需求（参考用） |

---

## 📋 接手清单

接手本项目的 Agent，请按以下顺序操作：

1. **读取 `context.md`**（`D:\work\chat\.agents\context.md`）
2. **读取 `WORK_LOG.md`**（`D:\work\chat\WORK_LOG.md`）了解最近的开发日志
3. 运行 `flutter analyze` 确认 0 issues
4. 运行 `flutter test` 确认 127/127 通过
5. 确认任务目标后，再开始修改代码

---

## 🚨 常见陷阱

| 陷阱 | 正确做法 |
|------|---------|
| ConversationState 中将 activeConversation 设为 null | 使用 `copyWith(clearActive: true)` |
| Riverpod Provider 在测试中出现 dispose 后写入错误 | 所有 await 后检查 `if (!mounted) return;` |
| 测试中使用 FlutterSecureStorage 报 PlatformException | 使用 `MockFlutterSecureStorage` |
| 图片路径在重启后失效 | 压缩保存到 documents 目录，存绝对路径 |
| 向不支持 Vision 的模型发送图片导致 400 | sendMessage 内先检查 `selectedModel.supportsVision` |
| SQLite 数据库损坏导致 App 崩溃 | DatabaseHelper 已实现自愈逻辑，无需额外处理 |
