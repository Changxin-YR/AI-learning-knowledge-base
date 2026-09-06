# Resume Material

## 项目简介

KnowFlow AI 是一套面向大学生和程序员的学习知识库应用，使用 Flutter 同时覆盖 Android/OpenHarmony，FastAPI 提供 JWT 鉴权、文档切片、可引用检索问答、学习计划、测验掌握度与仓库学习 API，并以纯 Dart UI 保持跨端一致。

## 项目亮点

- 设计了从文档上传、段落切片到 citation 返回的可追溯 RAG 闭环。
- 通过 Argon2id、JWT 和服务端资源归属校验覆盖基本安全边界。
- 用确定性掌握度公式把测验结果写回学习数据。
- 以纯 Dart 网络层和 Material 3 五入口 UI 降低 OHOS 插件兼容风险。

## 技术栈

Flutter/Dart、FastAPI、Pydantic、SQLite/MySQL 兼容 schema、Docker Compose、JWT、Argon2id、SSE。

## 面试话题

1. 如何保证 citation 不越权且能追溯到 chunk？
2. 为什么默认 lexical fallback，如何替换 Qdrant embedding？
3. Agent tool registry 如何限制写操作？
4. Flutter Android/OHOS 的平台差异如何隔离？
5. 如何扩展 mastery 的时间衰减和任务权重？
