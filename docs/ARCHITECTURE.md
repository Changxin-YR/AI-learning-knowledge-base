# Architecture

Flutter feature UI calls the `/api/v1` FastAPI service through a small pure-Dart `ApiClient`. The server owns authentication, resource authorization, document parsing/chunking, deterministic hybrid lexical retrieval, citation metadata, learning plans, quizzes, mastery updates, repository static analysis and indexing, user memories, and validated/audited Agent tool dispatch.

SQLite is the local default for a repeatable demo and is selected with `SQLITE_PATH`. The schema is written as a migration-style SQL script. Redis, Qdrant and MinIO are supplied by `docker-compose.yml` for deployment parity, but are not required by the current deterministic demo. Qdrant/Embedding and automatic provider tool selection remain optional integrations; the local fallback is intentionally deterministic.
