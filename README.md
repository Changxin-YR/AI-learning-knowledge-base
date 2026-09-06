# KnowFlow AI

KnowFlow AI 是一个 Flutter + FastAPI 的个人学习知识库。它提供 Demo 登录、文档索引、可引用问答、学习计划、测验掌握度、知识图谱摘要与公开仓库学习入口。

## 启动

```powershell
.scripts\start-infra.ps1
.scripts\start-backend.ps1
cd mobile; flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001
```

后端默认使用 `server/data/knowflow.db`，因此不依赖外部账号即可演示。Demo 账号：`demo@knowflow.local` / `KnowFlowDemo123!`。

## 验证

```powershell
.scripts\test-all.ps1
.scripts\build-all.ps1
```

架构、API、RAG、测试和双端验收记录见 `docs/`。
