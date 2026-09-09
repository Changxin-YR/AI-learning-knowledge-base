from __future__ import annotations

import os
import tempfile
import uuid
from pathlib import Path


# Test isolation must be established before pytest imports any module that imports
# app.main/app.runtime. Relying on test module collection order can bind DB_PATH
# to the developer's real SQLite database and make repeated local release runs
# fail with duplicate users (or, worse, mutate local development data).
TEST_DB = Path(tempfile.gettempdir()) / (
    f"knowflow-pytest-{os.getpid()}-{uuid.uuid4().hex}.db"
)

os.environ.pop("DATABASE_URL", None)
os.environ["SQLITE_PATH"] = str(TEST_DB)
os.environ["APP_ENV"] = "test"
os.environ["JWT_SECRET"] = "pytest-only-secret-that-is-never-used-in-production"
os.environ["DEMO_AI_MODE"] = "1"
os.environ["RAG_MODE"] = "lexical"
os.environ["RAG_QUALITY_MODE"] = "basic"
os.environ["EMBEDDING_PROVIDER"] = "local"
os.environ["RERANK_PROVIDER"] = "none"


def pytest_sessionfinish(session, exitstatus):
    """Best-effort cleanup of the isolated SQLite files after the test session."""
    for suffix in ("", "-wal", "-shm"):
        try:
            Path(f"{TEST_DB}{suffix}").unlink(missing_ok=True)
        except OSError:
            # A failed cleanup must not hide the real pytest exit status.
            pass
