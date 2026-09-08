# KnowFlow AI — 简历与面试材料

## 1. 一句话项目介绍

KnowFlow AI 是一套面向大学生和开发者的跨端 AI 学习知识库，使用 Flutter 覆盖 Android 与 HarmonyOS，FastAPI 提供文档解析、Hybrid RAG、DeepSeek/OpenAI-compatible Agent Tool Calling、长期记忆、Repository Learning，以及学习计划 → Task → Quiz → Mastery 的完整学习闭环。

## 2. 简历推荐写法

### 版本 A：3 条精简版

**KnowFlow AI｜AI 全栈学习知识库｜Flutter + FastAPI + Qdrant + DeepSeek**

- 独立完成 Android/HarmonyOS 跨端 AI 学习知识库，构建 TXT/MD/PDF/DOCX/PPTX 解析、Chunk、Qdrant 向量索引、Lexical + Vector + RRF Hybrid Retrieval 与可追溯 Citation 闭环；Android API34 与 HarmonyOS Emulator 完成双端验收。
- 设计可审计 Agent Runtime：基于 JSON Schema 校验 Tool 参数，通过 Service 层执行知识检索、学习计划、Task、Quiz、Memory、Repository Learning 等读写操作，并记录 `agent_runs/tool_calls`，禁止 Agent 直接执行 SQL。
- 构建 Long-term Memory、Repository Learning、权限隔离与自动化质量门禁；Backend 20+ 测试、Flutter analyze/test、Qdrant live、DeepSeek Tool Calling 均完成真实验收，并发布 Android APK 与 HarmonyOS x64/ARM64 HAP。

### 版本 B：偏 AI/RAG 岗位

- 设计 Hybrid RAG：中文字符/bigram/trigram + English token lexical retrieval 与 Qdrant vector retrieval 通过 Reciprocal Rank Fusion 融合，加入 similarity threshold、无答案零引用策略、user/KB vector ownership filter，并建立 Recall@3/5、MRR、Citation Hit Rate、No-answer false citation rate 评测体系。
- 抽象 OpenAI-compatible LLM/Embedding Provider，真实接入 DeepSeek Tool Calling，并提供可选 Sentence Transformers 本地神经 Embedding 服务；CI 默认使用 deterministic provider，避免测试依赖付费 API 或模型下载。
- 实现 Grounded Agent：模型选 Tool → schema validation → Service dispatch → audit → final response，结合长期 Memory 与 Repository Learning，支持多轮学习上下文而不允许模型直接访问数据库。

### 版本 C：偏全栈/客户端岗位

- 使用 Flutter + FastAPI 实现 Android/HarmonyOS 双端应用，处理 Android DocumentsUI 与 HarmonyOS `FilePickerUIExtAbility` 差异，通过平台 Picker 抽象和 HarmonyOS Compatibility Picker 实现多格式真实文件上传。
- 后端完成 JWT/Argon2id 鉴权、用户资源 ownership、文档解析、知识库、Conversation、Plan/Task/Quiz/Mastery、Repository Learning、Memory 与 Agent API；Qdrant 故障时可自动保留 lexical fallback。
- 建立从 pytest / Flutter analyze / widget test 到模拟器 E2E、Fresh APK/HAP、SHA256、Release 的交付证据链，并发布 `v1.0.0` 稳定版本。

## 3. 技术栈

- **Mobile**：Flutter、Dart、Material 3、Android、HarmonyOS/OpenHarmony、CPF-Flutter
- **Backend**：Python、FastAPI、Pydantic、SQLite
- **RAG**：Qdrant、Lexical Retrieval、Vector Retrieval、RRF、Citation
- **LLM/Agent**：DeepSeek、OpenAI-compatible API、Tool Calling、JSON Schema、Agent Audit
- **Memory**：Long-term Memory、ownership isolation
- **Documents**：pypdf、python-docx、python-pptx
- **Repository Learning**：Git shallow clone、静态源码分析、SSRF 防护
- **Security**：JWT、Argon2id、resource ownership、DNS/IP validation、secret isolation
- **QA/DevOps**：pytest、Flutter analyze/test、GitHub Actions、Dependabot、Docker Compose、Emulator E2E、GitHub Release

## 4. 最值得讲的技术难点

### 难点 1：为什么不能只做“向量库 + LLM”

真实 RAG 需要回答四个问题：

1. 文档是否被正确解析？
2. 检索结果是否真的相关？
3. citation 是否能追溯且不越权？
4. Qdrant/模型不可用时系统是否还能运行？

KnowFlow 的处理方式是：SQLite 保存真实文档/chunk 元数据，Qdrant 只负责 vector index；向量命中后仍回 SQLite 做 ownership recheck。Hybrid 模式使用 RRF 融合 lexical/vector，低相似度不强行 citation，Qdrant 失效则回退 lexical。

### 难点 2：Agent 如何避免“有权限的自然语言 SQL”

Agent 不允许生成或执行任意 SQL，而是只能从注册 Tool 中选择操作：

```text
User
→ LLM Tool Call
→ JSON Schema Validation
→ Registered Service Function
→ Ownership / Business Validation
→ DB/API
→ Audit
→ Final Answer
```

这样模型能力和业务权限解耦，Agent 的权限边界与人工 API 调用保持一致。

### 难点 3：Android/HarmonyOS 文件选择为什么不能共用一个插件假设

Android API37 AVD 曾出现 DocumentsUI 系统异常；HarmonyOS API22 系统 `FilePickerUIExtAbility` 也出现过超时。最终做法不是假设“Flutter 插件跨端就一定兼容”，而是将文件选择抽象为平台服务：Android 使用稳定系统 Picker，HarmonyOS 提供 Compatibility Picker，同时保证最终输入仍是用户真实选择的 bytes，而不是 hard-coded sample。

### 难点 4：如何证明 Vector RAG 真的更好

“能生成 embedding”不等于“检索质量提高”。项目建立独立 RAG Eval：

- Recall@3
- Recall@5
- MRR
- Citation Hit Rate
- No-answer false citation rate

并区分 deterministic vector baseline 和 neural embedding experiment，只有指标改善才允许声称质量提升。

## 5. 面试常见问题与回答思路

### Q1：为什么 SQLite 和 Qdrant 同时存在？

SQLite 是 source of truth，保存用户、文档、chunk、会话、学习状态和 ownership；Qdrant 是可重建的 vector index。这样即使 Qdrant 丢失或不可用，业务数据仍然完整，而且可以 fallback 到 lexical retrieval。

### Q2：为什么 Hybrid 用 RRF，而不是直接把两个 score 相加？

Lexical overlap score 和 vector cosine score 的量纲不同，直接相加需要额外 normalization 和 calibration。RRF 只依赖 rank position，更适合把异构检索器稳定融合，也更容易解释和测试。

### Q3：如何防止 Qdrant 返回其他用户的数据？

有两层：第一层 Qdrant payload filter 按 `user_id`/`knowledge_base_id` 限制；第二层拿回 chunk ID 后再 JOIN SQLite，通过 KB ownership 重新校验。即使 vector store filter 配置错误，也不会直接把结果作为可信业务数据返回。

### Q4：为什么 CI 不直接下载神经模型？

模型下载体积大、网络不稳定，并且会让普通 PR 测试变慢。CI 使用 deterministic embedding 验证接口、维度、RRF、ownership 和 fallback；神经模型作为独立 quality gate，通过相同 RAG Eval 数据集评估。

### Q5：Repository Learning 最大安全风险是什么？

不是“能不能 clone”，而是 SSRF 和执行不可信源码。项目只允许公开 GitHub/GitLab/Gitee，clone 前解析 DNS 并拒绝 private/loopback/link-local/reserved IP，禁止 HTTP redirect、submodule，并设置 timeout/文件数量/大小限制；只静态分析，不执行第三方仓库代码。

### Q6：为什么 DeepSeek Key 不能放 Flutter？

客户端无法安全保存服务端密钥，APK/HAP 都可以被逆向。所有 Provider 调用必须由 FastAPI 完成，Flutter 只拿业务 API Token。

## 6. 真实验收结果可讲什么

`v1.0.0` 已完成：

- Backend：20 passed
- Flutter analyze：PASS
- Flutter tests：5 passed
- Android API34 Emulator：PASS
- Android File Picker：PASS
- HarmonyOS H01-H27：24 PASS / 3 N/A / 0 FAIL
- HarmonyOS Compatibility Picker：PASS
- Qdrant Live：PASS
- DeepSeek Provider / Agent Read / Agent Write / Memory：PASS
- Android APK：PASS
- HarmonyOS x64 HAP：PASS
- HarmonyOS ARM64 HAP build：PASS

不要在面试中扩大表述为：

- 已完成应用商店正式上架
- 已完成 Android/HarmonyOS 物理真机认证
- 已证明神经 Embedding 一定优于 lexical

这些属于后续独立验证范围。

## 7. 30 秒项目介绍

“我做了一个叫 KnowFlow AI 的跨端学习知识库，Flutter 同时跑 Android 和 HarmonyOS，后端是 FastAPI。它不是只接一个模型聊天，而是完整实现了多格式文档解析、Hybrid RAG、Qdrant、可追溯 Citation、DeepSeek Tool Calling、Agent 审计、长期 Memory、Repository Learning，以及学习计划、任务、Quiz 和 Mastery。这个项目我重点解决了两个工程问题：一是所有 Agent 和 RAG 数据都做服务端 ownership 隔离；二是建立了 Android/HarmonyOS 模拟器、Qdrant live、pytest 和 Flutter test 的真实验收证据，而不是只证明代码能编译。”

## 8. 2 分钟项目介绍结构

建议按顺序讲：

1. **业务目标**：资料太分散，希望让用户把文件/代码仓库转成可学习知识。
2. **架构**：Flutter → FastAPI → SQLite/Qdrant → DeepSeek。
3. **核心 AI**：Hybrid RAG + Citation + Agent Tool Calling + Memory。
4. **安全**：ownership、SSRF、Agent 不直连 SQL、Key 服务端保存。
5. **跨端难点**：Android/HarmonyOS Picker 差异。
6. **工程质量**：自动测试、E2E、Release、SHA256、GitHub Actions。
7. **下一步**：神经 Embedding 质量评测、真机与正式商店签名。
