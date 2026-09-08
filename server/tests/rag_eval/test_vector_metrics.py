import json
from pathlib import Path

from app.main import LocalEmbeddingProvider, cosine_similarity, rrf_fusion, search_tokens


DATASET = Path(__file__).with_name("eval_dataset.json")


def _load():
    payload = json.loads(DATASET.read_text(encoding="utf-8"))
    return payload["documents"], payload["queries"]


def _metrics(queries, rankings):
    answerable = [(case, ranking) for case, ranking in zip(queries, rankings) if case["relevant"]]
    no_answer = [(case, ranking) for case, ranking in zip(queries, rankings) if not case["relevant"]]

    def hit_at(k):
        return sum(
            any(doc_id in case["relevant"] for doc_id in ranking[:k])
            for case, ranking in answerable
        ) / len(answerable)

    reciprocal_ranks = []
    citation_hits = 0
    for case, ranking in answerable:
        first_rank = next(
            (index for index, doc_id in enumerate(ranking, 1) if doc_id in case["relevant"]),
            None,
        )
        reciprocal_ranks.append(1 / first_rank if first_rank else 0.0)
        citation_hits += bool(ranking and ranking[0] in case["relevant"])

    return {
        "Recall@3": round(hit_at(3), 4),
        "Recall@5": round(hit_at(5), 4),
        "MRR": round(sum(reciprocal_ranks) / len(reciprocal_ranks), 4),
        "Citation Hit Rate": round(citation_hits / len(answerable), 4),
        "No-answer false citation rate": round(
            sum(bool(ranking) for _case, ranking in no_answer) / len(no_answer),
            4,
        ),
    }


def test_vector_eval_writes_lexical_vector_hybrid_comparison():
    documents, queries = _load()
    provider = LocalEmbeddingProvider(dimensions=256)
    document_ids = [document["id"] for document in documents]
    document_vectors = provider.embed_documents([document["text"] for document in documents])

    lexical_rankings = []
    vector_rankings = []
    hybrid_rankings = []

    for case in queries:
        query = case["query"]
        query_tokens = search_tokens(query)
        lexical_scored = [
            (len(query_tokens & search_tokens(document["text"])), document["id"])
            for document in documents
        ]
        lexical = [
            doc_id
            for score, doc_id in sorted(lexical_scored, key=lambda item: (-item[0], item[1]))
            if score > 0
        ]

        query_vector = provider.embed_query(query)
        vector_scored = [
            (cosine_similarity(query_vector, vector), doc_id)
            for doc_id, vector in zip(document_ids, document_vectors)
        ]
        vector = [
            doc_id
            for score, doc_id in sorted(vector_scored, key=lambda item: (-item[0], item[1]))
            if score >= 0.35
        ]

        hybrid = [
            item_id
            for item_id, _score in rrf_fusion([lexical, vector], limit=len(documents))
        ] if lexical or vector else []

        lexical_rankings.append(lexical)
        vector_rankings.append(vector)
        hybrid_rankings.append(hybrid)

    report = {
        "case_count": len(queries),
        "provider": "LocalEmbeddingProvider",
        "Lexical": _metrics(queries, lexical_rankings),
        "Vector": _metrics(queries, vector_rankings),
        "Hybrid": _metrics(queries, hybrid_rankings),
        "note": "Deterministic CI baseline; neural provider quality is evaluated separately.",
    }

    output = Path(__file__).parents[3] / "artifacts" / "rag-eval" / "deterministic-ci.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    assert report["case_count"] >= 50
    assert all("MRR" in report[name] for name in ("Lexical", "Vector", "Hybrid"))
    assert all(0 <= report[name]["No-answer false citation rate"] <= 1 for name in ("Lexical", "Vector", "Hybrid"))
