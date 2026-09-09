from __future__ import annotations

import json

import app.runtime as runtime


def _row(item_id: str, content: str):
    return {"id": item_id, "content": content, "document_id": f"doc-{item_id}", "filename": f"{item_id}.md", "position": 0}


class _FakeResponse:
    def __init__(self, payload: dict):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps(self.payload).encode("utf-8")


def test_verified_mode_uses_broad_rrf_then_verifier(monkeypatch):
    lexical = [_row("a", "lexical a"), _row("shared", "shared evidence")]
    vector_rows = [_row("shared", "shared evidence"), _row("b", "vector b")]
    rows_by_id = {row["id"]: row for row in [*lexical, *vector_rows]}

    monkeypatch.setenv("RAG_MODE", "hybrid")
    monkeypatch.setenv("RAG_QUALITY_MODE", "verified")
    monkeypatch.setenv("ANSWERABILITY_BASE_URL", "https://example.invalid")
    monkeypatch.setenv("ANSWERABILITY_MODEL", "judge")
    monkeypatch.setenv("RERANK_PROVIDER", "none")
    monkeypatch.setattr(runtime.core, "retrieve_lexical", lambda *_args, **_kwargs: lexical)
    monkeypatch.setattr(runtime.core, "retrieve_vector_evidence", lambda *_args, **_kwargs: ([("shared", 0.9), ("b", 0.8)], True))
    monkeypatch.setattr(runtime.core, "_chunk_rows", lambda _u, _k, ids: [rows_by_id[item_id] for item_id in ids if item_id in rows_by_id])
    monkeypatch.setattr(runtime, "_verify_rows", lambda _q, rows: [row for row in rows if row["id"] == "shared"])

    result = runtime.retrieve("u1", None, "question", limit=4)

    assert [row["id"] for row in result] == ["shared"]


def test_verified_mode_fail_closed_when_verifier_is_missing(monkeypatch):
    lexical = [_row("a", "evidence")]
    monkeypatch.setenv("RAG_MODE", "hybrid")
    monkeypatch.setenv("RAG_QUALITY_MODE", "verified")
    monkeypatch.delenv("ANSWERABILITY_BASE_URL", raising=False)
    monkeypatch.delenv("ANSWERABILITY_MODEL", raising=False)
    monkeypatch.delenv("OPENAI_BASE_URL", raising=False)
    monkeypatch.delenv("OPENAI_MODEL", raising=False)
    monkeypatch.setattr(runtime.core, "retrieve_lexical", lambda *_args, **_kwargs: lexical)
    monkeypatch.setattr(runtime.core, "retrieve_vector_evidence", lambda *_args, **_kwargs: ([], False))
    monkeypatch.setattr(runtime.core, "_chunk_rows", lambda *_args, **_kwargs: [])

    assert runtime.retrieve("u1", None, "question", limit=4) == []


def test_verified_mode_verifies_lexical_fallback_when_vector_is_unavailable(monkeypatch):
    lexical = [_row("a", "explicit evidence"), _row("b", "topic only")]
    monkeypatch.setenv("RAG_MODE", "hybrid")
    monkeypatch.setenv("RAG_QUALITY_MODE", "verified")
    monkeypatch.setenv("ANSWERABILITY_BASE_URL", "https://example.invalid")
    monkeypatch.setenv("ANSWERABILITY_MODEL", "judge")
    monkeypatch.setenv("RERANK_PROVIDER", "none")
    monkeypatch.setattr(runtime.core, "retrieve_lexical", lambda *_args, **_kwargs: lexical)
    monkeypatch.setattr(runtime.core, "retrieve_vector_evidence", lambda *_args, **_kwargs: ([], False))
    monkeypatch.setattr(runtime.core, "_chunk_rows", lambda *_args, **_kwargs: [])
    monkeypatch.setattr(runtime, "_verify_rows", lambda _q, rows: rows[:1])

    result = runtime.retrieve("u1", None, "question", limit=4)

    assert [row["id"] for row in result] == ["a"]


def test_basic_mode_preserves_original_retrieve(monkeypatch):
    expected = [_row("core", "core result")]
    monkeypatch.setenv("RAG_QUALITY_MODE", "basic")
    monkeypatch.setattr(runtime, "_core_retrieve", lambda *_args, **_kwargs: expected)

    assert runtime.retrieve("u1", None, "question") == expected


def test_runtime_embedding_provider_uses_configurable_cold_start_timeout(monkeypatch):
    seen: dict[str, object] = {}

    def fake_urlopen(request, timeout):
        seen["url"] = request.full_url
        seen["timeout"] = timeout
        return _FakeResponse({"data": [{"index": 0, "embedding": [0.1] * 384}]})

    monkeypatch.setenv("EMBEDDING_BASE_URL", "http://127.0.0.1:8002")
    monkeypatch.setenv("EMBEDDING_MODEL", "mini")
    monkeypatch.setenv("EMBEDDING_DIMENSIONS", "384")
    monkeypatch.setenv("EMBEDDING_TIMEOUT_SECONDS", "77")
    monkeypatch.setattr(runtime, "urlopen", fake_urlopen)

    provider = runtime.RuntimeOpenAIEmbeddingProvider()
    vectors = provider.embed_documents(["hello"])

    assert seen == {"url": "http://127.0.0.1:8002/embeddings", "timeout": 77}
    assert len(vectors) == 1
    assert len(vectors[0]) == 384
    assert provider.dimensions == 384


def test_runtime_qdrant_request_uses_configurable_timeout(monkeypatch):
    seen: dict[str, object] = {}

    def fake_urlopen(request, timeout):
        seen["url"] = request.full_url
        seen["timeout"] = timeout
        return _FakeResponse({"status": "ok"})

    monkeypatch.setenv("QDRANT_TIMEOUT_SECONDS", "19")
    monkeypatch.setattr(runtime, "urlopen", fake_urlopen)

    result = runtime._runtime_qdrant_request("GET", "/collections")

    assert result == {"status": "ok"}
    assert seen["timeout"] == 19
    assert seen["url"].endswith("/collections")


def test_runtime_index_chunks_logs_embedding_stage_without_content(monkeypatch, caplog):
    class BrokenProvider:
        dimensions = 384

        def embed_documents(self, _texts):
            raise TimeoutError("cold start")

    monkeypatch.setattr(runtime.core, "embedding_provider", lambda: BrokenProvider())
    caplog.set_level("ERROR", logger="knowflow.rag")

    result = runtime.runtime_index_chunks("u1", "kb1", "doc1", [("chunk1", "secret content", 0)])

    assert result is False
    assert "stage=embedding" in caplog.text
    assert "document_id=doc1" in caplog.text
    assert "secret content" not in caplog.text


def test_runtime_qdrant_upsert_logs_metadata_on_failure(monkeypatch, caplog):
    monkeypatch.setattr(runtime.core, "ensure_qdrant_collection", lambda _dimensions: None)
    monkeypatch.setattr(runtime.core, "_qdrant_request", lambda *_args, **_kwargs: (_ for _ in ()).throw(TimeoutError("qdrant timeout")))
    caplog.set_level("ERROR", logger="knowflow.rag")

    result = runtime.runtime_qdrant_upsert([{"id": "p1", "vector": [0.1] * 384, "payload": {}}], 384)

    assert result is False
    assert "stage=qdrant" in caplog.text
    assert "dimensions=384" in caplog.text
    assert "point_count=1" in caplog.text
    assert "0.1" not in caplog.text
