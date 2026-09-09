# KnowFlow AI

[![CI](https://github.com/Changxin-YR/AI-learning-knowledge-base/actions/workflows/ci.yml/badge.svg)](https://github.com/Changxin-YR/AI-learning-knowledge-base/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Changxin-YR/AI-learning-knowledge-base)](https://github.com/Changxin-YR/AI-learning-knowledge-base/releases)

KnowFlow AI 是一个面向大学生与开发者的 **AI 学习知识库**：Flutter 客户端覆盖 Android 与 HarmonyOS/OpenHarmony，FastAPI 后端负责鉴权、文档解析、RAG、Agent Tool Calling、长期记忆、Repository Learning 与学习闭环。项目的目标不是只做聊天 Demo，而是把“资料进入系统 → 可追溯检索 → AI 回答 → 学习计划 → Task → Quiz → Mastery”做成可验证的完整链路。

> `v1.0.0` 已冻结；`v1.1.0` 在其基础上完成真实 Neural Embedding、Cross-Encoder Rerank、DeepSeek Evidence Verification 与独立 Holdout V3 质量验收。详见 [`docs/RAG_QUALITY_FINAL_V1_1.md`](docs/RAG_QUALITY_FINAL_V1_1.md)、[`CHANGELOG.md`](CHANGELOG.md) 与 [`docs/V1.1.0_RELEASE_NOTES.md`](docs/V1.1.0_RELEASE_NOTES.md)。

## 核心能力

- **多格式知识库**：TXT / Markdown / PDF / DOCX / PPTX 真实解析、切片、索引、删除与引用追溯。
- **Verified Hybrid RAG**：Lexical + Qdrant Vector Retrieval + Reciprocal Rank Fusion + Cross-Encoder + Evidence Verifier。
- **神经语义检索**：可选 multilingual MiniLM 本地 Embedding，384 维 Qdrant 独立 collection。
- **可追溯回答**：回答返回 document/chunk citation；严格 verified 模式会拒绝“主题相关但资料没有答案”的伪引用。
- **DeepSeek / OpenAI-compatible LLM**：服务端 Provider 接入；已完成真实 DeepSeek Tool Calling、RAG 与 Evidence Verification 验证。
- **Agent Runtime**：JSON Schema 参数校验、Service dispatch、读写 Tool、`agent_runs` / `tool_calls` 审计，不允许 Agent 任意执行 SQL。
- **Long-term Memory**：CRUD、检索、删除、用户隔离，可由 Agent 保存和召回学习上下文。
- **Repository Learning**：仅允许公开 GitHub/GitLab/Gitee 仓库；DNS/IP SSRF 防护、禁止 Git redirect、shallow clone、静态分析 README/依赖/入口/源码并写入知识库。
- **学习闭环**：学习计划、Task、Quiz、Mastery 与多轮 Conversation。
- **双端文件选择**：Android 使用稳定系统 Picker；HarmonyOS 对系统 Picker 异常提供兼容路径，保持真实文件选择与上传。
- **离线降级**：Qdrant 不可用时保留 lexical fallback；云模型未配置时仍可运行 deterministic/demo 流程。
- **运行时可观测性**：神经 Embedding / Qdrant timeout 可配置，索引失败记录阶段级诊断但不记录正文、API Key 或向量值。

## 架构

```mermaid
flowchart LR
    U[Flutter Android / HarmonyOS] --> API[FastAPI /api/v1]
    API --> AUTH[JWT + Ownership]
    API --> DOC[Parser + Chunking]
    DOC --> SQL[(SQLite)]
    DOC --> EMB[Embedding Provider]
    EMB --> Q[(Qdrant)]
    API --> RET[Lexical + Vector + RRF]
    SQL --> RET
    Q --> RET
    RET --> RR[Cross-Encoder Rerank]
    RR --> EV[Evidence Sufficiency Verifier]
    EV --> LLM[DeepSeek / OpenAI-compatible LLM]
    LLM --> CITE[Grounded Answer + Citation]
    API --> AGENT[Agent Runtime]
    AGENT --> TOOLS[Knowledge / Plan / Task / Quiz / Memory / Repository Tools]
    API --> LEARN[Plan → Task → Quiz → Mastery]
```

详细设计见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)、[`docs/RAG.md`](docs/RAG.md)、[`docs/RAG_QUALITY_FINAL_V1_1.md`](docs/RAG_QUALITY_FINAL_V1_1.md) 和 [`docs/AGENT.md`](docs/AGENT.md)。

## 技术栈

| 层 | 技术 |
|---|---|
| Mobile | Flutter / Dart / Material 3 / CPF-Flutter HarmonyOS 工具链 |
| Backend | Python / FastAPI / Pydantic |
| Auth | JWT / Argon2id / Resource ownership checks |
| Relational data | SQLite（本地可重复演示） |
| Vector store | Qdrant |
| LLM | OpenAI-compatible Provider；已验证 DeepSeek |
| Embedding | deterministic local / OpenAI-compatible / multilingual MiniLM local neural service |
| Rerank | multilingual MMARCO Cross-Encoder |
| Evidence verification | DeepSeek / OpenAI-compatible strict JSON verifier |
| Document parsing | pypdf / python-docx / python-pptx |
| Infra | Docker Compose |
| QA | pytest / flutter analyze / flutter test / emulator E2E / GitHub Actions |

## 快速启动

### 1. 基础服务

```powershell
.\scripts\start-infra.ps1
.\scripts\start-backend.ps1
```

后端默认使用 `server/data/knowflow.db`，不依赖外部账号即可演示。

Demo 账号：

```text
Email: demo@knowflow.local
Password: KnowFlowDemo123!
```

### 2. Flutter

Android Emulator：

```powershell
cd mobile
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001
```

HarmonyOS 的构建与验收说明见 [`docs/OHOS_ACCEPTANCE.md`](docs/OHOS_ACCEPTANCE.md)。

## DeepSeek / 云模型

不要把 API Key 写入 Flutter 或提交到 Git。后端使用 OpenAI-compatible 配置：

```env
DEMO_AI_MODE=0
OPENAI_BASE_URL=<provider-base-url>
OPENAI_API_KEY=<secret>
OPENAI_MODEL=<model-name>
```

Evidence Verifier 独立配置：

```env
ANSWERABILITY_BASE_URL=https://api.deepseek.com
ANSWERABILITY_API_KEY=<secret>
ANSWERABILITY_MODEL=<verified-model-name>
ANSWERABILITY_JSON_OUTPUT=true
ANSWERABILITY_DISABLE_THINKING=true
```

真实 Provider 验收使用 DeepSeek；CI 不依赖外部付费 API。

## RAG 模式

基础检索模式：

```env
RAG_MODE=lexical
RAG_MODE=vector
RAG_MODE=hybrid
```

质量模式：

```env
RAG_QUALITY_MODE=basic     # 轻量 Hybrid / deterministic-friendly
RAG_QUALITY_MODE=rerank    # semantic gate + Cross-Encoder ordering
RAG_QUALITY_MODE=verified  # RRF + Cross-Encoder + strict evidence verification
```

`verified` 是安全模式：Evidence Verifier 未配置或调用失败时 fail closed，不会静默回退成不受验证的 citation。

默认 `EMBEDDING_PROVIDER=local` 是可重复测试用的确定性离线向量，不代表神经语义质量。

### 本地神经 Embedding + Rerank

安装额外依赖：

```powershell
cd server
pip install -r requirements-neural.txt
```

启动本地 OpenAI-compatible Neural 服务：

```powershell
uvicorn neural_embedding_service:app --host 127.0.0.1 --port 8002
```

主后端连接它：

```env
EMBEDDING_PROVIDER=openai
EMBEDDING_BASE_URL=http://127.0.0.1:8002
EMBEDDING_API_KEY=
EMBEDDING_MODEL=sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2
EMBEDDING_DIMENSIONS=384
EMBEDDING_TIMEOUT_SECONDS=120
QDRANT_COLLECTION=knowflow_chunks_neural_384
QDRANT_TIMEOUT_SECONDS=10

RERANK_PROVIDER=http
RERANK_BASE_URL=http://127.0.0.1:8002
RERANK_MODEL=cross-encoder/mmarco-mMiniLMv2-L12-H384-v1
RERANK_TIMEOUT_SECONDS=120
```

本地 neural service 默认使用 multilingual MiniLM，并通过独立 Qdrant collection 避免与 256 维 deterministic collection 发生维度冲突。Runtime 默认给 Neural Embedding 120 秒 cold-start timeout，避免首次加载模型时被旧的固定 20 秒提前中断。

运行状态：

```powershell
Invoke-RestMethod http://127.0.0.1:8001/api/v1/runtime-quality
```

## RAG 质量评测

项目内置多语言、代码、Repository、安全、学习、Memory、Agent 与高混淆无答案问题评测集：

```powershell
python scripts/rag-eval.py
```

指标包括：

- Recall@3
- Recall@5
- MRR
- Citation Hit Rate
- No-answer false citation rate

v1.1.0 最终未参与调参的 Holdout V3（24 answerable / 12 no-answer）在 `HybridVerified` 模式下：

| Metric | Result |
|---|---:|
| Recall@3 | 1.0000 |
| Recall@5 | 1.0000 |
| MRR | 1.0000 |
| Citation Hit Rate | 1.0000 |
| No-answer false citation rate | 0.0000 |

真实 Runtime Smoke：支持问题 citation=`1`，高混淆无答案问题 citation=`0`，上传文档 4 chunks 对应 Qdrant 4 points。

## 自动化质量门禁

本地：

```powershell
.\scripts\test-all.ps1
.\scripts\build-all.ps1
```

GitHub Actions 在 Pull Request 和 `main` push 上自动执行：

- Python 3.13 backend pytest
- deterministic RAG evaluation
- Flutter 3.27.4 `flutter analyze`
- Flutter widget tests

Dependabot 每周检查 Python、Flutter/pub 与 GitHub Actions 依赖更新。

## v1.1.0 发布收口

发布脚本会检查 `main == origin/main`、干净工作树、Secret 文件未被 Git 跟踪，随后执行测试、Android APK、HarmonyOS x64/ARM64 HAP 构建、SHA256、Tag 与 GitHub Release：

```powershell
.\scripts\release-v1.1.0.ps1
```

只构建和校验、不创建 tag/release：

```powershell
.\scripts\release-v1.1.0.ps1 -BuildOnly
```

发布说明：[`docs/V1.1.0_RELEASE_NOTES.md`](docs/V1.1.0_RELEASE_NOTES.md)。版本历史：[`CHANGELOG.md`](CHANGELOG.md)。

## v1.0.0 验收基线

| Gate | Result |
|---|---|
| Backend | 20 passed |
| Flutter analyze | PASS |
| Flutter tests | 5 passed |
| Android API34 Emulator | PASS |
| Android File Picker | PASS |
| HarmonyOS H01-H27 | 24 PASS / 3 N/A / 0 FAIL |
| HarmonyOS Compatibility Picker | PASS |
| Qdrant Live | PASS |
| DeepSeek Provider | PASS |
| Agent Read / Write | PASS |
| Memory | PASS |
| Android APK | PASS |
| HarmonyOS x64 HAP | PASS |
| HarmonyOS ARM64 HAP build | PASS |

完整报告：[`docs/ROUND7_FINAL_PASS_REPORT.md`](docs/ROUND7_FINAL_PASS_REPORT.md)

冻结发布：[`v1.0.0`](https://github.com/Changxin-YR/AI-learning-knowledge-base/releases/tag/v1.0.0)

## 安全边界

- 所有用户资源通过服务端 ownership 校验。
- Agent 只能调用注册的 Service Tool，不允许直接操作数据库。
- Repository import 仅接受公开白名单 Host，并执行 DNS/IP 检查、大小/数量/超时限制。
- `.env`、API Key、keystore、证书和本地签名配置均禁止提交。
- 神经索引错误日志只记录阶段、维度、数量、collection 与错误类型，不记录正文、向量或 API Key。
- 生产环境拒绝默认 JWT Secret。

## 当前范围

模拟器工程闭环已经验证；以下不作为当前工程 Release 的 PASS 门禁：

- Android/HarmonyOS 物理设备认证
- ARM64 物理运行验证
- Google Play / AppGallery 正式生产签名
- 付费 Neural Embedding Provider

## 面试 / 作品集材料

- [`docs/RESUME.md`](docs/RESUME.md)：简历描述与面试讲解
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)：架构与数据流
- [`docs/RAG.md`](docs/RAG.md)：RAG 与降级策略
- [`docs/RAG_EVAL.md`](docs/RAG_EVAL.md)：检索评测方法
- [`docs/RAG_QUALITY_FINAL_V1_1.md`](docs/RAG_QUALITY_FINAL_V1_1.md)：v1.1 Neural RAG 质量证据
- [`docs/FINAL_ACCEPTANCE_REPORT.md`](docs/FINAL_ACCEPTANCE_REPORT.md)：最终验收

## License / Usage

请根据仓库实际许可证与使用计划使用本项目；正式对外许可前应补充明确的 LICENSE 文件与第三方依赖许可证检查。
