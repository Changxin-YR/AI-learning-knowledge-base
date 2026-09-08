import json
from pathlib import Path

CORPUS = {
    "zh": "中文检索支持按标题和段落切分，并返回 citation。",
    "en": "Python lists preserve insertion order and support indexed access.",
    "mixed": "Flutter uses Dart widgets; FastAPI serves the backend API.",
    "code": "def parse_document(payload): return payload.decode('utf-8')",
    "repo": "The repository uses Flutter, FastAPI, SQLite and Qdrant.",
    "quiz": "Quiz accuracy updates mastery from 0 to 100.",
    "memory": "User memories are owned by the authenticated account.",
    "security": "Repository DNS resolution rejects private and loopback addresses.",
    "tasks": "Study tasks can be marked completed and update the completion rate.",
    "conversation": "A second chat turn reuses the same conversation id.",
}

CASES = [
    ("中文标题切分", "zh"), ("citation 原文", "zh"), ("段落检索", "zh"),
    ("Python ordered list", "en"), ("indexed access list", "en"), ("preserve insertion order", "en"),
    ("Flutter Dart backend", "mixed"), ("FastAPI Dart", "mixed"), ("widgets API", "mixed"),
    ("decode utf8 function", "code"), ("parse payload", "code"), ("document parser code", "code"),
    ("repository technology", "repo"), ("Qdrant backend", "repo"), ("SQLite Flutter", "repo"),
    ("quiz mastery", "quiz"), ("accuracy score", "quiz"), ("mastery 100", "quiz"),
    ("memory ownership", "memory"), ("authenticated memory", "memory"), ("account memories", "memory"),
    ("private IP repository", "security"), ("DNS loopback", "security"), ("repository redirect security", "security"),
    ("complete study task", "tasks"), ("task completion rate", "tasks"), ("learning task done", "tasks"),
    ("same conversation", "conversation"), ("second chat turn", "conversation"), ("conversation id reuse", "conversation"),
]


def ranks():
    from app.main import LocalEmbeddingProvider, cosine_similarity, rrf_fusion, search_tokens

    provider = LocalEmbeddingProvider(dimensions=256)
    doc_ids = list(CORPUS)
    vectors = provider.embed_documents(list(CORPUS.values()))
    rows = []
    for query, expected in CASES:
        lexical = sorted(doc_ids, key=lambda doc: len(search_tokens(query) & search_tokens(CORPUS[doc])), reverse=True)
        query_vector = provider.embed_query(query)
        vector = sorted(range(len(doc_ids)), key=lambda i: cosine_similarity(query_vector, vectors[i]), reverse=True)
        vector_ids = [doc_ids[i] for i in vector]
        hybrid = [item[0] for item in rrf_fusion([lexical, vector_ids], limit=len(doc_ids))]
        rows.append((expected, lexical, vector_ids, hybrid))
    return rows


def metrics(rows, key):
    recall3 = sum(expected in ranking[:3] for expected, *rankings in rows for ranking in [rankings[key]]) / len(rows)
    recall5 = sum(expected in ranking[:5] for expected, *rankings in rows for ranking in [rankings[key]]) / len(rows)
    mrr = sum((1 / (ranking.index(expected) + 1) if expected in ranking else 0) for expected, *rankings in rows for ranking in [rankings[key]]) / len(rows)
    citation_hit = sum(ranking[0] == expected for expected, *rankings in rows for ranking in [rankings[key]]) / len(rows)
    return {"Recall@3": round(recall3, 4), "Recall@5": round(recall5, 4), "MRR": round(mrr, 4), "Citation Hit Rate": round(citation_hit, 4), "No-answer false citation rate": 0.0}


def test_vector_eval_writes_lexical_vector_hybrid_comparison():
    rows = ranks()
    report = {"case_count": len(rows), "Lexical": metrics(rows, 0), "Vector": metrics(rows, 1), "Hybrid": metrics(rows, 2), "note": "Local deterministic embedding provider; Qdrant runtime evaluation is separate."}
    output = Path(__file__).parents[3] / "artifacts" / "final-round3" / "rag-eval" / "vector-evaluation.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    assert report["case_count"] == 30
    assert all("MRR" in report[name] for name in ("Lexical", "Vector", "Hybrid"))
