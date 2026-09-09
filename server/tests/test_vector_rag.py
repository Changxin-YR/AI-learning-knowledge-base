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


def test_hybrid_confidence_rejects_missing_semantic_evidence():
    assert not main.hybrid_confidence_allows(["lexical-a"], [], strong_threshold=0.415, agreement_top_k=2)


def test_hybrid_confidence_accepts_strong_vector_evidence_without_lexical_overlap():
    assert main.hybrid_confidence_allows(
        ["lexical-a"],
        [("vector-a", 0.42)],
        strong_threshold=0.415,
        agreement_top_k=2,
    )


def test_hybrid_confidence_requires_rank_agreement_for_weak_vector_evidence():
    assert main.hybrid_confidence_allows(
        ["shared", "lexical-a"],
        [("shared", 0.36), ("vector-b", 0.35)],
        strong_threshold=0.415,
        agreement_top_k=2,
    )
    assert not main.hybrid_confidence_allows(
        ["lexical-a", "lexical-b"],
        [("vector-a", 0.36), ("vector-b", 0.35)],
        strong_threshold=0.415,
        agreement_top_k=2,
    )


def test_semantic_backed_rrf_never_emits_lexical_only_citations():
    ids = main.semantic_backed_rrf_ids(
        ["lexical-only", "shared"],
        [("shared", 0.36), ("vector-only", 0.35)],
        limit=4,
        strong_threshold=0.415,
        agreement_top_k=2,
    )

    assert "lexical-only" not in ids
    assert ids[0] == "shared"
    assert set(ids) <= {"shared", "vector-only"}


def _seed_retrieval_db(monkeypatch, tmp_path):
    db_path = tmp_path / "hybrid.db"
    monkeypatch.setattr(main, "DB_PATH", db_path)
    main.migrate()
    with main.db() as conn:
        conn.executescript(
            """
            INSERT INTO users VALUES ('u1','u1@example.com','U1','hash','now');
            INSERT INTO users VALUES ('u2','u2@example.com','U2','hash','now');
            INSERT INTO knowledge_bases VALUES ('kb1','u1','One','now');
            INSERT INTO knowledge_bases VALUES ('kb2','u2','Two','now');
            INSERT INTO documents VALUES ('d1','kb1','one.md','text/plain','Python lists preserve order','indexed','now');
            INSERT INTO documents VALUES ('d2','kb2','two.md','text/plain','Private other user document','indexed','now');
            INSERT INTO chunks VALUES ('c1','d1','Python lists preserve order',0,'{}');
            INSERT INTO chunks VALUES ('c2','d2','Private other user document',0,'{}');
            """
        )
    monkeypatch.setenv("RAG_MODE", "hybrid")
    monkeypatch.setenv("EMBEDDING_PROVIDER", "openai")
    monkeypatch.setenv("HYBRID_CONFIDENCE_GATE", "1")


def test_hybrid_falls_back_to_lexical_only_when_vector_infrastructure_is_unavailable(monkeypatch, tmp_path):
    _seed_retrieval_db(monkeypatch, tmp_path)
    monkeypatch.setattr(main, "retrieve_vector_evidence", lambda *_args, **_kwargs: ([], False))

    rows = main.retrieve("u1", None, "Python lists", limit=4)

    assert [row["id"] for row in rows] == ["c1"]


def test_hybrid_returns_no_answer_when_vector_is_available_but_has_no_semantic_match(monkeypatch, tmp_path):
    _seed_retrieval_db(monkeypatch, tmp_path)
    monkeypatch.setattr(main, "retrieve_vector_evidence", lambda *_args, **_kwargs: ([], True))

    rows = main.retrieve("u1", None, "Python lists", limit=4)

    assert rows == []


def test_hybrid_rechecks_sqlite_ownership_before_accepting_vector_evidence(monkeypatch, tmp_path):
    _seed_retrieval_db(monkeypatch, tmp_path)
    monkeypatch.setattr(main, "retrieve_vector_evidence", lambda *_args, **_kwargs: ([("c2", 0.99)], True))

    rows = main.retrieve("u1", None, "Python lists", limit=4)

    assert rows == []


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
