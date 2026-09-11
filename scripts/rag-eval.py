from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen


REPO_ROOT = Path(__file__).resolve().parents[1]
SERVER_ROOT = REPO_ROOT / "server"
sys.path.insert(0, str(SERVER_ROOT))

from app.evidence_verifier import OpenAICompatibleEvidenceVerifier  # noqa: E402
from app.main import (  # noqa: E402
    HYBRID_AGREEMENT_TOP_K,
    HYBRID_STRONG_VECTOR_THRESHOLD,
    cosine_similarity,
    embedding_provider,
    rrf_fusion,
    search_tokens,
    semantic_backed_rrf_ids,
)


def load_dataset(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    documents = payload.get("documents", [])
    queries = payload.get("queries", [])
    if not documents or not queries:
        raise ValueError("evaluation dataset must contain documents and queries")
    return documents, queries


def resolve_cli_path(path: Path) -> Path:
    """Resolve CLI paths relative to the repository root on every platform."""
    return path.resolve() if path.is_absolute() else (REPO_ROOT / path).resolve()


def display_path(path: Path) -> str:
    """Prefer a stable repository-relative path in reports when possible."""
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


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
) -> tuple[Any, list[list[tuple[str, float]]]]:
    provider = embedding_provider()
    document_vectors = provider.embed_documents([document["text"] for document in documents])
    rankings: list[list[tuple[str, float]]] = []
    for case in queries:
        query_vector = provider.embed_query(case["query"])
        scored = [
            (document["id"], cosine_similarity(query_vector, vector))
            for document, vector in zip(documents, document_vectors)
        ]
        rankings.append(
            [
                (doc_id, score)
                for doc_id, score in sorted(scored, key=lambda item: (-item[1], item[0]))
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


def rerank_scores(query: str, passages: list[str]) -> list[float]:
    if not passages:
        return []
    endpoint = (os.getenv("RERANK_BASE_URL") or os.getenv("EMBEDDING_BASE_URL") or "").rstrip("/")
    if not endpoint:
        raise RuntimeError("RERANK_BASE_URL or EMBEDDING_BASE_URL must be configured for rerank evaluation")
    if not endpoint.endswith("/rerank"):
        endpoint += "/rerank"
    api_key = os.getenv("RERANK_API_KEY") or os.getenv("EMBEDDING_API_KEY") or ""
    model = os.getenv("RERANK_MODEL", "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1")
    payload = json.dumps({"query": query, "documents": passages, "model": model}).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = Request(endpoint, data=payload, headers=headers, method="POST")
    try:
        with urlopen(request, timeout=120) as response:
            data = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        raise RuntimeError("Configured reranker failed") from exc
    ranked = sorted(data.get("data", []), key=lambda item: item.get("index", 0))
    scores = [float(item["score"]) for item in ranked]
    if len(scores) != len(passages):
        raise RuntimeError("Reranker returned an unexpected number of scores")
    return scores


def rerank_scored_rankings(
    queries: list[dict[str, Any]],
    documents: list[dict[str, Any]],
    candidate_rankings: list[list[str]],
    candidate_limit: int,
) -> list[list[tuple[str, float]]]:
    by_id = {document["id"]: document for document in documents}
    scored_rankings: list[list[tuple[str, float]]] = []
    for case, candidate_ids in zip(queries, candidate_rankings):
        ids = [item_id for item_id in candidate_ids[:candidate_limit] if item_id in by_id]
        passages = [by_id[item_id]["text"] for item_id in ids]
        scores = rerank_scores(case["query"], passages)
        scored_rankings.append(
            sorted(zip(ids, scores), key=lambda item: (-item[1], item[0]))
        )
    return scored_rankings


def filter_scored_rankings(
    scored_rankings: list[list[tuple[str, float]]],
    threshold: float,
) -> list[list[str]]:
    return [
        [item_id for item_id, score in ranking if score >= threshold]
        for ranking in scored_rankings
    ]


def calibrate_rerank_threshold(
    queries: list[dict[str, Any]],
    scored_rankings: list[list[tuple[str, float]]],
    min_recall: float,
    min_citation: float,
) -> tuple[float, dict[str, float | int], int]:
    scores = sorted({score for ranking in scored_rankings for _item_id, score in ranking})
    if not scores:
        raise RuntimeError("Reranker produced no candidate scores")

    candidates = [scores[0] - 1e-6, *scores]
    viable: list[tuple[tuple[float, float, float, float, float], float, dict[str, float | int]]] = []
    for threshold in candidates:
        result = metrics(queries, filter_scored_rankings(scored_rankings, threshold))
        if result["Recall@3"] < min_recall or result["Citation Hit Rate"] < min_citation:
            continue
        objective = (
            float(result["No-answer false citation rate"]),
            -float(result["MRR"]),
            -float(result["Citation Hit Rate"]),
            -float(result["Recall@3"]),
            -threshold,
        )
        viable.append((objective, threshold, result))

    if not viable:
        fallback_threshold = scores[0] - 1e-6
        fallback_metrics = metrics(queries, filter_scored_rankings(scored_rankings, fallback_threshold))
        return fallback_threshold, fallback_metrics, len(candidates)

    _objective, best_threshold, best_metrics = min(viable, key=lambda item: item[0])
    return best_threshold, best_metrics, len(candidates)


def verify_answerability_rankings(
    queries: list[dict[str, Any]],
    documents: list[dict[str, Any]],
    candidate_rankings: list[list[str]],
    candidate_limit: int,
) -> tuple[OpenAICompatibleEvidenceVerifier, list[list[str]]]:
    verifier = OpenAICompatibleEvidenceVerifier.from_env()
    by_id = {document["id"]: document for document in documents}
    verified: list[list[str]] = []
    for case, candidate_ids in zip(queries, candidate_rankings):
        ids = [item_id for item_id in candidate_ids[:candidate_limit] if item_id in by_id]
        passages = [by_id[item_id]["text"] for item_id in ids]
        supported = set(verifier.verify(case["query"], passages))
        verified.append([item_id for index, item_id in enumerate(ids) if index in supported])
    return verifier, verified


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Evaluate KnowFlow lexical, vector, hybrid, reranked and evidence-verified retrieval."
    )
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
        default=float(os.getenv("VECTOR_SCORE_THRESHOLD", "0.25")),
    )
    parser.add_argument(
        "--strong-threshold",
        type=float,
        default=float(os.getenv("HYBRID_STRONG_VECTOR_THRESHOLD", str(HYBRID_STRONG_VECTOR_THRESHOLD))),
        help="A vector score at or above this value can pass the hybrid confidence gate without lexical agreement.",
    )
    parser.add_argument(
        "--agreement-top-k",
        type=int,
        default=int(os.getenv("HYBRID_AGREEMENT_TOP_K", str(HYBRID_AGREEMENT_TOP_K))),
        help="Weak vector evidence must agree with lexical retrieval within this many top-ranked candidates.",
    )
    parser.add_argument(
        "--rerank",
        action="store_true",
        help="Call the configured /rerank endpoint for RRF candidates and report Cross-Encoder metrics.",
    )
    parser.add_argument(
        "--rerank-threshold",
        type=float,
        default=float(os.getenv("RERANK_SCORE_THRESHOLD", "0.0")),
        help="Cross-Encoder score required for a candidate to be emitted. This is a ranking diagnostic, not an answerability guarantee.",
    )
    parser.add_argument(
        "--rerank-candidate-limit",
        type=int,
        default=int(os.getenv("RERANK_CANDIDATE_LIMIT", "8")),
    )
    parser.add_argument(
        "--calibrate-rerank",
        action="store_true",
        help="Choose a rerank threshold from this dataset only. Never use this mode on the final holdout dataset.",
    )
    parser.add_argument("--min-rerank-recall", type=float, default=0.95)
    parser.add_argument("--min-rerank-citation", type=float, default=0.90)
    parser.add_argument(
        "--verify-answerability",
        action="store_true",
        help="Use a configured OpenAI-compatible model as a strict evidence-sufficiency verifier after retrieval/reranking.",
    )
    parser.add_argument(
        "--answerability-candidate-limit",
        type=int,
        default=int(os.getenv("ANSWERABILITY_CANDIDATE_LIMIT", "4")),
    )
    args = parser.parse_args()

    dataset_path = resolve_cli_path(args.dataset)
    output_path = resolve_cli_path(args.output)

    documents, queries = load_dataset(dataset_path)
    lexical = [lexical_ranking(case["query"], documents) for case in queries]
    provider, vector_matches = vector_rankings(queries, documents, args.threshold)
    vector = [[doc_id for doc_id, _score in ranking] for ranking in vector_matches]
    hybrid_ungated = [
        [item_id for item_id, _score in rrf_fusion([lexical_rank, vector_rank], limit=len(documents))]
        if lexical_rank or vector_rank
        else []
        for lexical_rank, vector_rank in zip(lexical, vector)
    ]
    hybrid = [
        semantic_backed_rrf_ids(
            lexical_rank,
            matches,
            limit=len(documents),
            strong_threshold=args.strong_threshold,
            agreement_top_k=args.agreement_top_k,
        )
        for lexical_rank, matches in zip(lexical, vector_matches)
    ]

    report: dict[str, Any] = {
        "dataset": display_path(dataset_path),
        "case_count": len(queries),
        "document_count": len(documents),
        "embedding_provider": provider.__class__.__name__,
        "embedding_dimensions": getattr(provider, "dimensions", None),
        "embedding_model": os.getenv("EMBEDDING_MODEL") or os.getenv("LOCAL_EMBEDDING_MODEL") or None,
        "vector_threshold": args.threshold,
        "hybrid_strong_vector_threshold": args.strong_threshold,
        "hybrid_agreement_top_k": args.agreement_top_k,
        "Lexical": metrics(queries, lexical),
        "Vector": metrics(queries, vector),
        "HybridUngated": metrics(queries, hybrid_ungated),
        "Hybrid": metrics(queries, hybrid),
    }

    verification_source = hybrid
    verification_source_name = "Hybrid"
    if args.rerank or args.calibrate_rerank:
        scored_rankings = rerank_scored_rankings(
            queries,
            documents,
            hybrid_ungated,
            max(1, args.rerank_candidate_limit),
        )
        selected_threshold = args.rerank_threshold
        calibration: dict[str, Any] | None = None
        if args.calibrate_rerank:
            selected_threshold, selected_metrics, threshold_count = calibrate_rerank_threshold(
                queries,
                scored_rankings,
                args.min_rerank_recall,
                args.min_rerank_citation,
            )
            calibration = {
                "selected_threshold": selected_threshold,
                "evaluated_thresholds": threshold_count,
                "minimum_recall_at_3": args.min_rerank_recall,
                "minimum_citation_hit_rate": args.min_rerank_citation,
                "selected_metrics": selected_metrics,
            }
        reranked = filter_scored_rankings(scored_rankings, selected_threshold)
        reranked_order = [[item_id for item_id, _score in ranking] for ranking in scored_rankings]
        report["reranker"] = {
            "model": os.getenv("RERANK_MODEL", "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1"),
            "candidate_limit": max(1, args.rerank_candidate_limit),
            "score_threshold": selected_threshold,
            "calibration": calibration,
        }
        report["HybridReranked"] = metrics(queries, reranked)
        # The Cross-Encoder is used as an ordering signal for the verifier; its raw
        # relevance score is deliberately not treated as an answerability verdict.
        verification_source = reranked_order
        verification_source_name = "CrossEncoderOrder"

    if args.verify_answerability:
        verifier, verified = verify_answerability_rankings(
            queries,
            documents,
            verification_source,
            max(1, args.answerability_candidate_limit),
        )
        report["answerability_verifier"] = {
            "model": verifier.model,
            "candidate_limit": max(1, args.answerability_candidate_limit),
            "source": verification_source_name,
            "policy": "explicit evidence only; topic overlap and outside knowledge rejected",
        }
        report["HybridVerified"] = metrics(queries, verified)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
