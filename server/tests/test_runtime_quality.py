from __future__ import annotations

import app.runtime as runtime


def _row(item_id: str, content: str):
    return {"id": item_id, "content": content, "document_id": f"doc-{item_id}", "filename": f"{item_id}.md", "position": 0}


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
