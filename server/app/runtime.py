from __future__ import annotations

import json
import logging
import os
from typing import Any
from urllib.request import Request, urlopen

from app import main as core
from app.evidence_verifier import EvidenceVerificationError, OpenAICompatibleEvidenceVerifier


logger = logging.getLogger("knowflow.rag")

# Keep the original implementations available so basic mode and deterministic CI
# remain backward compatible while runtime mode can add production diagnostics.
_core_retrieve = core.retrieve
_core_embedding_provider = core.embedding_provider


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


class RuntimeOpenAIEmbeddingProvider(core.EmbeddingProvider):
    """OpenAI-compatible embedding provider with configurable cold-start timeout.

    The local multilingual MiniLM service can take longer than 20 seconds to load
    on the first request. Runtime mode therefore uses an explicit configurable
    timeout and emits metadata-only diagnostics on failure. No API key, input text,
    or vector values are logged.
    """

    def __init__(self):
        self.endpoint = os.getenv("EMBEDDING_BASE_URL", "").rstrip("/")
        self.api_key = os.getenv("EMBEDDING_API_KEY", "")
        self.model = os.getenv("EMBEDDING_MODEL", "")
        self.dimensions = int(os.getenv("EMBEDDING_DIMENSIONS", str(core.EMBEDDING_DIMENSIONS)))

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        endpoint = self.endpoint
        if not endpoint:
            raise RuntimeError("EMBEDDING_BASE_URL is required for openai embedding mode")
        if not endpoint.endswith("/embeddings"):
            endpoint += "/embeddings"
        payload = json.dumps({"model": self.model, "input": texts}, ensure_ascii=False).encode("utf-8")
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        request = Request(endpoint, data=payload, headers=headers, method="POST")
        timeout = _positive_int("EMBEDDING_TIMEOUT_SECONDS", 120)
        try:
            with urlopen(request, timeout=timeout) as response:
                data = json.loads(response.read().decode("utf-8"))
            vectors = [item["embedding"] for item in sorted(data["data"], key=lambda item: item.get("index", 0))]
            if not vectors or len(vectors) != len(texts) or any(len(vector) != len(vectors[0]) for vector in vectors):
                raise ValueError("Embedding provider returned invalid vectors")
            self.dimensions = len(vectors[0])
            return vectors
        except Exception as exc:
            logger.warning(
                "embedding request failed provider=openai model=%s timeout_seconds=%s batch_size=%s error_type=%s",
                self.model or "<unset>",
                timeout,
                len(texts),
                type(exc).__name__,
            )
            raise RuntimeError("Configured embedding provider failed") from exc


def runtime_embedding_provider() -> core.EmbeddingProvider:
    provider = os.getenv("EMBEDDING_PROVIDER", "local").lower()
    if provider == "openai":
        return RuntimeOpenAIEmbeddingProvider()
    if provider == "auto" and os.getenv("EMBEDDING_BASE_URL") and os.getenv("EMBEDDING_MODEL"):
        return RuntimeOpenAIEmbeddingProvider()
    return _core_embedding_provider()


def _runtime_qdrant_request(method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = Request(
        f"{core.QDRANT_URL}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    timeout = _positive_int("QDRANT_TIMEOUT_SECONDS", 10)
    try:
        with urlopen(request, timeout=timeout) as response:
            body = response.read()
        return json.loads(body.decode("utf-8")) if body else {}
    except Exception as exc:
        logger.warning(
            "qdrant request failed method=%s path=%s collection=%s timeout_seconds=%s error_type=%s",
            method,
            path,
            core.QDRANT_COLLECTION,
            timeout,
            type(exc).__name__,
        )
        raise


def runtime_qdrant_upsert(points: list[dict[str, Any]], dimensions: int) -> bool:
    if not points:
        return True
    try:
        core.ensure_qdrant_collection(dimensions)
        core._qdrant_request(
            "PUT",
            f"/collections/{core.QDRANT_COLLECTION}/points?wait=true",
            {"points": points},
        )
        return True
    except Exception as exc:
        logger.error(
            "vector indexing failed stage=qdrant collection=%s dimensions=%s point_count=%s error_type=%s",
            core.QDRANT_COLLECTION,
            dimensions,
            len(points),
            type(exc).__name__,
        )
        return False


def runtime_index_chunks(
    user_id: str,
    kb_id: str,
    document_id: str,
    chunks: list[tuple[str, str, int, str]] | list[tuple[str, str, int]],
) -> bool:
    if not chunks:
        return True
    try:
        provider = core.embedding_provider()
        vectors = provider.embed_documents([chunk for _chunk_id, chunk, _position, *_ in chunks])
    except Exception as exc:
        logger.error(
            "vector indexing failed stage=embedding document_id=%s chunk_count=%s provider=%s error_type=%s",
            document_id,
            len(chunks),
            os.getenv("EMBEDDING_PROVIDER", "local"),
            type(exc).__name__,
        )
        return False

    points: list[dict[str, Any]] = []
    for chunk_record, vector in zip(chunks, vectors):
        chunk_id, _chunk, _position, *chunk_document = chunk_record
        points.append(
            {
                "id": chunk_id,
                "vector": vector,
                "payload": {
                    "user_id": user_id,
                    "knowledge_base_id": kb_id,
                    "document_id": chunk_document[0] if chunk_document else document_id,
                    "chunk_id": chunk_id,
                },
            }
        )

    success = core.qdrant_upsert(points, provider.dimensions)
    if not success:
        logger.error(
            "vector indexing incomplete document_id=%s chunk_count=%s dimensions=%s collection=%s",
            document_id,
            len(chunks),
            provider.dimensions,
            core.QDRANT_COLLECTION,
        )
    return success


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


# Runtime hardening is installed before serving routes. Functions defined in
# app.main resolve these module globals at call time, so upload/document indexing,
# vector retrieval, deletion and availability checks use the hardened transport.
core.embedding_provider = runtime_embedding_provider
core._qdrant_request = _runtime_qdrant_request
core.qdrant_upsert = runtime_qdrant_upsert
core.index_chunks = runtime_index_chunks

# Routes and Agent tools defined in app.main resolve the module-global `retrieve`
# at call time, so replacing it here upgrades chat, streaming chat, quiz source
# retrieval and the `search_knowledge` Agent tool without duplicating routes.
core.retrieve = retrieve
core.app.version = os.getenv("APP_VERSION", "1.1.0")
app = core.app


@app.get("/api/v1/runtime-quality")
def runtime_quality_status() -> dict[str, Any]:
    return {
        "rag_quality_mode": quality_mode(),
        "reranker_configured": reranker_configured(),
        "answerability_configured": answerability_configured(),
        "vector_threshold": float(os.getenv("VECTOR_SCORE_THRESHOLD", str(core.VECTOR_SCORE_THRESHOLD))),
        "embedding_provider": os.getenv("EMBEDDING_PROVIDER", "local"),
        "embedding_timeout_seconds": _positive_int("EMBEDDING_TIMEOUT_SECONDS", 120),
        "qdrant_timeout_seconds": _positive_int("QDRANT_TIMEOUT_SECONDS", 10),
        "app_version": core.app.version,
    }
