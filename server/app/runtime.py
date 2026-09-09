from __future__ import annotations

import json
import os
from typing import Any
from urllib.request import Request, urlopen

from app import main as core
from app.evidence_verifier import EvidenceVerificationError, OpenAICompatibleEvidenceVerifier


# Keep the original implementation available so the default/basic mode remains
# backward compatible and deterministic CI does not require neural/cloud services.
_core_retrieve = core.retrieve


def _positive_int(name: str, default: int) -> int:
    try:
        return max(1, int(os.getenv(name, str(default))))
    except ValueError:
        return default


def quality_mode() -> str:
    value = os.getenv("RAG_QUALITY_MODE", "basic").strip().lower()
    return value if value in {"basic", "rerank", "verified"} else "basic"


def reranker_configured() -> bool:
    provider = os.getenv("RERANK_PROVIDER", "none").strip().lower()
    return (
        provider not in {"", "none", "off", "disabled"}
        and bool(os.getenv("RERANK_BASE_URL", "").strip())
        and bool(os.getenv("RERANK_MODEL", "").strip())
    )


def answerability_configured() -> bool:
    return bool(
        (os.getenv("ANSWERABILITY_BASE_URL") or os.getenv("OPENAI_BASE_URL") or "").strip()
        and (os.getenv("ANSWERABILITY_MODEL") or os.getenv("OPENAI_MODEL") or "").strip()
    )


def _candidate_limit(final_limit: int) -> int:
    return max(
        final_limit,
        _positive_int("RERANK_CANDIDATE_LIMIT", 8),
        _positive_int("ANSWERABILITY_CANDIDATE_LIMIT", 4),
    )


def _rerank_rows(query: str, rows: list[Any]) -> list[Any]:
    if not rows or not reranker_configured():
        return rows
    endpoint = os.getenv("RERANK_BASE_URL", "").rstrip("/")
    if not endpoint.endswith("/rerank"):
        endpoint += "/rerank"
    model = os.getenv("RERANK_MODEL", "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1")
    api_key = os.getenv("RERANK_API_KEY", "")
    payload = json.dumps(
        {
            "query": query,
            "documents": [row["content"] for row in rows],
            "model": model,
        },
        ensure_ascii=False,
    ).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = Request(endpoint, data=payload, headers=headers, method="POST")
    timeout = _positive_int("RERANK_TIMEOUT_SECONDS", 120)
    with urlopen(request, timeout=timeout) as response:
        body = json.loads(response.read().decode("utf-8"))
    scored: list[tuple[int, float]] = []
    for item in body.get("data", []):
        index = item.get("index")
        score = item.get("score")
        if isinstance(index, bool) or not isinstance(index, int) or not isinstance(score, (int, float)):
            raise RuntimeError("Reranker returned malformed data")
        if index < 0 or index >= len(rows):
            raise RuntimeError("Reranker returned an out-of-range index")
        scored.append((index, float(score)))
    if len(scored) != len(rows) or len({index for index, _score in scored}) != len(rows):
        raise RuntimeError("Reranker returned an unexpected number of scores")
    return [rows[index] for index, _score in sorted(scored, key=lambda item: (-item[1], item[0]))]


def _verify_rows(query: str, rows: list[Any]) -> list[Any]:
    if not rows:
        return []
    verifier = OpenAICompatibleEvidenceVerifier.from_env()
    candidate_limit = min(len(rows), _positive_int("ANSWERABILITY_CANDIDATE_LIMIT", 4), 8)
    candidates = rows[:candidate_limit]
    supported = set(verifier.verify(query, [row["content"] for row in candidates]))
    return [row for index, row in enumerate(candidates) if index in supported]


def _verified_or_closed(query: str, rows: list[Any]) -> list[Any]:
    # Explicit verified mode is a safety mode: provider errors or missing verifier
    # configuration must not silently turn into unsupported citations.
    if not answerability_configured():
        return []
    try:
        return _verify_rows(query, rows)
    except (EvidenceVerificationError, RuntimeError, ValueError, OSError):
        return []


def retrieve(user_id: str, kb_id: str | None, query: str, limit: int = 4) -> list[Any]:
    mode = os.getenv("RAG_MODE", core.RAG_MODE).lower()
    qmode = quality_mode()
    if mode != "hybrid" or qmode == "basic":
        return _core_retrieve(user_id, kb_id, query, limit)

    candidates = _candidate_limit(limit)
    lexical = core.retrieve_lexical(user_id, kb_id, query, candidates)
    vector_matches, vector_available = core.retrieve_vector_evidence(user_id, kb_id, query, candidates)

    # Re-check ownership in SQLite even though Qdrant also has user/kb filters.
    owned_vector_rows = core._chunk_rows(user_id, kb_id, [item_id for item_id, _score in vector_matches])
    owned_ids = {row["id"] for row in owned_vector_rows}
    vector_matches = [(item_id, score) for item_id, score in vector_matches if item_id in owned_ids]

    lexical_ids = [row["id"] for row in lexical]
    vector_ids = [item_id for item_id, _score in vector_matches]

    if not vector_available:
        # Availability fallback remains lexical, but verified mode still checks
        # evidence sufficiency before a citation is allowed.
        rows: list[Any] = lexical[:candidates]
    elif qmode == "verified":
        # Match the final quality evaluation pipeline: broad RRF candidates first,
        # Cross-Encoder for order only, then strict evidence verification.
        fused_ids = [
            item_id
            for item_id, _score in core.rrf_fusion(
                [lexical_ids, vector_ids],
                limit=candidates,
            )
        ]
        rows = core._chunk_rows(user_id, kb_id, fused_ids)
    else:
        # Rerank-only mode retains the semantic confidence gate because a
        # Cross-Encoder relevance score is not an answerability guarantee.
        fused_ids = core.semantic_backed_rrf_ids(
            lexical_ids,
            vector_matches,
            limit=candidates,
        )
        rows = core._chunk_rows(user_id, kb_id, fused_ids)

    if reranker_configured():
        try:
            rows = _rerank_rows(query, rows)
        except (RuntimeError, ValueError, OSError):
            if qmode == "verified":
                # The verifier can still safely judge the pre-rerank candidates.
                pass
            else:
                return rows[:limit]

    if qmode == "verified":
        return _verified_or_closed(query, rows)[:limit]
    return rows[:limit]


# Routes and Agent tools defined in app.main resolve the module-global `retrieve`
# at call time, so replacing it here upgrades chat, streaming chat, quiz source
# retrieval and the `search_knowledge` Agent tool without duplicating routes.
core.retrieve = retrieve
app = core.app


@app.get("/api/v1/runtime-quality")
def runtime_quality_status() -> dict[str, Any]:
    return {
        "rag_quality_mode": quality_mode(),
        "reranker_configured": reranker_configured(),
        "answerability_configured": answerability_configured(),
        "vector_threshold": float(os.getenv("VECTOR_SCORE_THRESHOLD", str(core.VECTOR_SCORE_THRESHOLD))),
        "embedding_provider": os.getenv("EMBEDDING_PROVIDER", "local"),
    }
