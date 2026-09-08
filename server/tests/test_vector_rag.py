import os

import pytest

import app.main as main


def test_local_embedding_provider_returns_normalized_vectors_for_documents_and_queries():
    provider = main.LocalEmbeddingProvider(dimensions=64)
    documents = provider.embed_documents(["Python lists preserve order"])
    query = provider.embed_query("Python lists preserve order")

    assert len(documents) == 1
    assert len(documents[0]) == 64
    assert len(query) == 64
    assert pytest.approx(sum(value * value for value in query), abs=1e-6) == 1
    assert main.cosine_similarity(query, documents[0]) > 0.99


def test_rrf_fusion_keeps_results_from_both_rankers_without_score_addition():
    fused = main.rrf_fusion(
        [["lexical-a", "shared"], ["shared", "vector-b"]],
        k=60,
        limit=3,
    )

    assert [item[0] for item in fused] == ["shared", "lexical-a", "vector-b"]
    assert fused[0][1] == pytest.approx(1 / 61 + 1 / 62)


def test_vector_retrieval_rechecks_sqlite_ownership(monkeypatch, tmp_path):
    db_path = tmp_path / "vector.db"
    monkeypatch.setattr(main, "DB_PATH", db_path)
    main.migrate()
    with main.db() as conn:
        conn.executescript(
            """
            INSERT INTO users VALUES ('u1','u1@example.com','U1','hash','now');
            INSERT INTO users VALUES ('u2','u2@example.com','U2','hash','now');
            INSERT INTO knowledge_bases VALUES ('kb1','u1','One','now');
            INSERT INTO knowledge_bases VALUES ('kb2','u2','Two','now');
            INSERT INTO documents VALUES ('d1','kb1','one.md','text/plain','one','indexed','now');
            INSERT INTO documents VALUES ('d2','kb2','two.md','text/plain','two','indexed','now');
            INSERT INTO chunks VALUES ('c1','d1','one',0,'{}');
            INSERT INTO chunks VALUES ('c2','d2','two',0,'{}');
            """
        )
    monkeypatch.setattr(main, "qdrant_search", lambda *_args, **_kwargs: [("c1", 0.9), ("c2", 0.99)])

    rows = main.retrieve_vector("u1", None, "query", limit=4)

    assert [row["id"] for row in rows] == ["c1"]
