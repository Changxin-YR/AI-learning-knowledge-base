from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
SERVER_ROOT = REPO_ROOT / "server"
sys.path.insert(0, str(SERVER_ROOT))

from app.main import cosine_similarity, embedding_provider, rrf_fusion, search_tokens  # noqa: E402


def load_dataset(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    documents = payload.get("documents", [])
    queries = payload.get("queries", [])
    if not documents or not queries:
        raise ValueError("evaluation dataset must contain documents and queries")
    return documents, queries


def lexical_ranking(query: str, documents: list[dict[str, Any]]) -> list[str]:
    query_tokens = search_tokens(query)
    scored = []
    for document in documents:
        score = len(query_tokens & search_tokens(document["text"]))
        if score > 0:
            scored.append((score, document["id"]))
    return [doc_id for _score, doc_id in sorted(scored, key=lambda item: (-item[0], item[1]))]


def vector_rankings(
    queries: list[dict[str, Any]],
    documents: list[dict[str, Any]],
    threshold: float,
) -> tuple[Any, list[list[str]]]:
    provider = embedding_provider()
    document_vectors = provider.embed_documents([document["text"] for document in documents])
    rankings: list[list[str]] = []
    for case in queries:
        query_vector = provider.embed_query(case["query"])
        scored = [
            (cosine_similarity(query_vector, vector), document["id"])
            for document, vector in zip(documents, document_vectors)
        ]
        rankings.append(
            [
                doc_id
                for score, doc_id in sorted(scored, key=lambda item: (-item[0], item[1]))
                if score >= threshold
            ]
        )
    return provider, rankings


def metrics(queries: list[dict[str, Any]], rankings: list[list[str]]) -> dict[str, float | int]:
    answerable = [(case, ranking) for case, ranking in zip(queries, rankings) if case["relevant"]]
    no_answer = [(case, ranking) for case, ranking in zip(queries, rankings) if not case["relevant"]]

    def hit_at(k: int) -> float:
        if not answerable:
            return 0.0
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

    false_citations = sum(bool(ranking) for _case, ranking in no_answer)
    return {
        "answerable_cases": len(answerable),
        "no_answer_cases": len(no_answer),
        "Recall@3": round(hit_at(3), 4),
        "Recall@5": round(hit_at(5), 4),
        "MRR": round(sum(reciprocal_ranks) / len(reciprocal_ranks), 4) if reciprocal_ranks else 0.0,
        "Citation Hit Rate": round(citation_hits / len(answerable), 4) if answerable else 0.0,
        "No-answer false citation rate": round(false_citations / len(no_answer), 4) if no_answer else 0.0,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate KnowFlow lexical, vector and hybrid retrieval.")
    parser.add_argument(
        "--dataset",
        type=Path,
        default=SERVER_ROOT / "tests" / "rag_eval" / "eval_dataset.json",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "artifacts" / "rag-eval" / "latest.json",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=float(os.getenv("VECTOR_SCORE_THRESHOLD", "0.35")),
    )
    args = parser.parse_args()

    documents, queries = load_dataset(args.dataset)
    lexical = [lexical_ranking(case["query"], documents) for case in queries]
    provider, vector = vector_rankings(queries, documents, args.threshold)
    hybrid = [
        [item_id for item_id, _score in rrf_fusion([lexical_rank, vector_rank], limit=len(documents))]
        if lexical_rank or vector_rank
        else []
        for lexical_rank, vector_rank in zip(lexical, vector)
    ]

    report = {
        "dataset": str(args.dataset.relative_to(REPO_ROOT)),
        "case_count": len(queries),
        "document_count": len(documents),
        "embedding_provider": provider.__class__.__name__,
        "embedding_dimensions": getattr(provider, "dimensions", None),
        "embedding_model": os.getenv("EMBEDDING_MODEL") or os.getenv("LOCAL_EMBEDDING_MODEL") or None,
        "vector_threshold": args.threshold,
        "Lexical": metrics(queries, lexical),
        "Vector": metrics(queries, vector),
        "Hybrid": metrics(queries, hybrid),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
