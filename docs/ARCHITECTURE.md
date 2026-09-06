# Architecture

Flutter feature UI calls the `/api/v1` FastAPI service through a small pure-Dart `ApiClient`. The server owns authentication, resource authorization, document parsing/chunking, lexical retrieval, citation metadata, learning plans, quizzes, mastery updates, repository URL validation, and statistics.

SQLite is the local default for a repeatable demo. The schema is written as a migration-style SQL script and can be moved to MySQL by setting `DATABASE_URL`; Redis, Qdrant and MinIO are supplied by `docker-compose.yml` for deployment parity.
