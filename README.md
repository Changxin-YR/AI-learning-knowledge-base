# KnowFlow AI

KnowFlow AI 是一个 Flutter + FastAPI 的个人学习知识库。当前可用能力包括 Demo 登录、PDF/DOCX/PPTX/Markdown 文档索引、可引用的中文/英文混合词法检索、学习计划与任务、测验掌握度、公开仓库静态分析与入库、用户长期记忆，以及带 schema 校验和审计记录的 Agent 工具执行。Qdrant/Embedding、模型驱动的自动 tool-call 需要配置对应 Provider；没有 Provider 时保留本地检索和显式结构化工具调用，不伪装成向量或模型能力。

## 启动

```powershell
.\scripts\start-infra.ps1
.\scripts\start-backend.ps1
cd mobile; flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001
```

后端默认使用 `server/data/knowflow.db`，因此不依赖外部账号即可演示。Demo 账号：`demo@knowflow.local` / `KnowFlowDemo123!`。

## 验证

```powershell
.\scripts\test-all.ps1
.\scripts\build-all.ps1
```

架构、API、RAG、测试和双端验收记录见 `docs/`。
