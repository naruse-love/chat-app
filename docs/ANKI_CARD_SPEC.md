# Anki 卡片架构、字段规范与导出接口文档

本文档全面梳理本项目中所有与 **Anki 卡片** 相关的数据结构、代码位置、处理接口与后续导出实现方案。

---

## 1. 架构定位与设计背景

在本项目（AI Agent 日语生词本）的架构设计中，生词库的设计初衷即为 **“为 Anki 导入量身定制”**：
- **无缝对接模板**：数据模型严格基于项目根目录下的 `正面.html` 与 `背面.html` 进行逆向建模与字段对齐；
- **格式天然合规**：所有抓取（Weblio）与大模型生成（LLM）的例句，在入库时就已经被格式化为 Anki 原生支持的 **Ruby 振假名语法**（`汉字[假名]`）；
- **解耦存储与导出**：当前阶段已完成全部字段的高质量捕获与 SQLite 持久化存储，后续导出模块可直接消费现有的 DAO 接口生成标准 `.tsv` 或 `.apkg` 文件。

---

## 2. 字段映射完整规范对照表

数据实体类定义位于 `lib/models/vocabulary_entry.dart`，其与 Anki 模板的具体映射如下：

| 数据模型字段 (`VocabularyEntry`) | 数据库字段类型 | Anki 模板占位符 | 必填/可选 | 字段含义与格式示例 |
|---|---|---|---|---|
| `id` | `INTEGER PRIMARY KEY` | `{{text:NoteID}}` | 可选 | 数据库自增主键，导出时可作为卡片的唯一 NoteID，防止导入时产生重复卡片 |
| `vocabKanji` | `TEXT NOT NULL` | `{{VocabKanji}}` / `{{furigana:VocabKanji}}` | **必填** | 单词汉字表记。例：`食べる`、`美しい`、`講じる` |
| `vocabFurigana` | `TEXT NOT NULL` | `{{VocabFurigana}}` / `{{kana:VocabFurigana}}` | **必填** | 单词读音/假名标注。例：`たべる`、`うつくしい`、`こうじる` |
| `vocabPoS` | `TEXT NOT NULL` | `{{VocabPoS}}` | **必填** | 词性分类标签。例：`［動バ下一］`、`［名］` |
| `vocabDefSc` | `TEXT NOT NULL` | `{{VocabDefSC}}` | **必填** | 简明中文释义（由大模型翻译并清洗）。例：`1 吃，食用；2 谋生，生活` |
| `vocabDefJa` | `TEXT NOT NULL` | `（日日释义备用）` | 可选 | 小学馆《デジタル大辞泉》或大模型生成的原生日文释义原文 |
| `sentKanji1` | `TEXT` | `{{SentKanji1}}` / `{{kanji:SentKanji1}}` | **建议** | 例句1 纯日文文本（已剥离所有括号假名）。例：`生で食べる` |
| `sentFurigana1` | `TEXT` | `{{SentFurigana1}}` | **建议** | 例句1 Anki Ruby 假名注音。例：`生[なま]で 食[た]べる` |
| `sentDefSc1` | `TEXT` | `{{SentDefSC1}}` | **建议** | 例句1 对应的简体中文翻译。例：`生吃` |
| `sentKanji2` | `TEXT` | `{{SentKanji2}}` | 可选 | 例句2 纯日文文本。例：`一口食べてみる` |
| `sentFurigana2` | `TEXT` | `{{SentFurigana2}}` | 可选 | 例句2 Anki Ruby 假名注音。例：`一 口[ひとくち] 食[た]べてみる` |
| `sentDefSc2` | `TEXT` | `{{SentDefSC2}}` | 可选 | 例句2 对应的简体中文翻译。例：`尝一口看看` |
| `sourceDict` | `TEXT NOT NULL` | `{{Tags}}` / 分类 | 可选 | 来源词典名称。例：`デジタル大辞泉`、`AI兜底生成` |
| `sourceUrl` | `TEXT NOT NULL` | 链接元数据 | 可选 | Weblio 原始条目 URL 地址 |
| `createdAt` | `TEXT NOT NULL` | 卡片时间戳 | 可选 | ISO 8601 查词时间 |

> 📌 **注**：模板中的 `{{VocabAudio}}`、`{{SentAudio1}}` 等音频字段目前预留，模板内部已通过内置的 EdgeTTS 脚本实现按需在线发音。

---

## 3. 核心代码位置与接口索引

### 3.1 数据层（Model & DAO）

- **数据模型定义**：`lib/models/vocabulary_entry.dart`
  - 提供 `toMap()` / `fromMap()` 支持 SQLite 数据存取；
  - 提供 `toJson()` / `fromJson()` 支持 JSON 序列化；
  - 提供 `copyWith()` 支持不可变更新。
- **数据库访问接口 (DAO)**：`lib/data/vocabulary_dao.dart`
  - `getAll({String? searchQuery})`：**（导出功能最核心的数据读取接口）** 提取库内所有生词列表，按时间倒序排列，支持按关键字过滤；
  - `getById(int id)`：按主键获取单个词条；
  - `findByKanji(String kanji)`：按单词精确查找；
  - `count()`：统计当前单词库总数。
- **数据库表初始化与迁移**：`lib/data/database_helper.dart`
  - 表名：`vocabulary`（Schema Version 5）；
  - 索引：`idx_vocabulary_kanji`、`idx_vocabulary_created_at`。

---

### 3.2 Anki Ruby 语法生成器（Weblio 解析服务）

- **代码位置**：`lib/services/weblio_service.dart`（第 697 ~ 714 行）
- **核心静态方法**：
  ```dart
  /// 将日文例句中的括号注音转换为 Anki 兼容的 Ruby 语法
  /// 示例：ご飯(はん)を美味(おい)しく食(た)べる -> ご 飯[はん]を 美味[おい]しく 食[た]べる
  static String formatFurigana(String text)
  ```
  - **特性**：采用精确的 Unicode 汉字范围匹配 `[\u4e00-\u9faf\u3400-\u4dbfヶ々]+`，并在汉字前置带有平假名时自动插入前置空格，杜绝 Anki 渲染时将前面的平假名与注音汉字错误合并。
  ```dart
  /// 剥离所有假名括号，提取纯净的汉字例句
  /// 示例：生(なま)で食べる -> 生で食べる
  static String stripFurigana(String text)
  ```

---

### 3.3 业务编排与 AI 结构化输出（VocabularyService）

- **代码位置**：`lib/services/vocabulary_service.dart`
- **处理机制**：
  - `_translateWithLlm`：抓取词典后，构造专门的结构化 Prompt，强制大模型以 JSON 格式输出 `definitionSc`（中文释义）与 `exampleSc1` / `exampleSc2`（例句翻译）；
  - `_generateWithLlmFallback`：词典未收录时全量 AI 兜底，自动生成读音、词性、日文释义、中文释义以及带有 Ruby 注音的例句，确保字段完整性；
  - `sanitizeDefinitionSc`：剥离“是…的上一段活用/化”等语法废话，确保中文释义精简地道。

---

### 3.4 状态管理层（UI 交互与导出触发源）

- **代码位置**：`lib/providers/vocabulary_provider.dart`
- **数据绑定**：
  - `ref.watch(vocabularyProvider).entries`：当前加载在内存中的全部生词列表。导出界面可直接订阅该列表作为导出数据源。

---

## 4. 后续“一键导出 Anki”的技术实现方案建议

当未来需要上线卡片导出功能时，建议采用如下设计实现：

### 方案 A：TSV / CSV 纯文本制表符导出（推荐，轻量无第三方依赖）
1. **格式规范**：UTF-8 编码文本，每行为一个单词条目，字段之间以 Tab 制表符 `\t` 分隔；
2. **第一行标题**：
   ```tsv
   #separator:tab
   #html:true
   #tags column:14
   NoteID	VocabKanji	VocabFurigana	VocabPoS	VocabDefSC	VocabDefJa	SentKanji1	SentFurigana1	SentDefSC1	SentKanji2	SentFurigana2	SentDefSC2	SourceDict	Tags
   ```
3. **使用方式**：用户在手机或电脑端 Anki 点击「文件」→「导入」，选择该文件，字段将自动 1:1 完美映射至用户的卡组模板中。

### 方案 B：`.apkg` 牌组打包导出
1. 引入 `archive` 库；
2. 生成 SQLite 牌组集合数据库 `collection.anki2`；
3. 将根目录的 `正面.html` 与 `背面.html` 样式内置打包，产出 `.apkg` 文件并通过 `share_plus` 唤起系统分享。

---

## 5. 对应自动化测试套件

目前已有大量测试用例专门保护 Anki 相关字段与语法的准确性：
- `test/models/vocabulary_entry_test.dart`：验证实体模型各字段序列化、空值容错与 SQLite Map 映射；
- `test/services/weblio_service_test.dart`：验证 `formatFurigana` 与 `stripFurigana` 输出标准 Anki Ruby 语法；
- `test/services/vocabulary_service_test.dart`：验证 AI 兜底与结构化翻译输出符合 Anki 字段格式要求；
- `test/data/vocabulary_dao_test.dart`：验证数据库批量读取（`getAll`）与单条查询。
