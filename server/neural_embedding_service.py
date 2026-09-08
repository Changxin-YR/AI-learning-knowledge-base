from __future__ import annotations

import os
from functools import lru_cache
from typing import Any

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field


MODEL_NAME = os.getenv(
    "LOCAL_EMBEDDING_MODEL",
    "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
)
DEVICE = os.getenv("LOCAL_EMBEDDING_DEVICE", "cpu")
API_KEY = os.getenv("LOCAL_EMBEDDING_API_KEY", "")

app = FastAPI(title="KnowFlow Local Neural Embedding Service", version="1.0.0")


class EmbeddingRequest(BaseModel):
    model: str = Field(default=MODEL_NAME, min_length=1)
    input: str | list[str]


@lru_cache(maxsize=1)
def model():
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError as exc:
        raise RuntimeError(
            "sentence-transformers is not installed. Run: pip install -r requirements-neural.txt"
        ) from exc
    return SentenceTransformer(MODEL_NAME, device=DEVICE)


def authorize(authorization: str | None) -> None:
    if not API_KEY:
        return
    if authorization != f"Bearer {API_KEY}":
        raise HTTPException(status_code=401, detail="Invalid embedding service token")


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "model": MODEL_NAME,
        "device": DEVICE,
        "loaded": model.cache_info().currsize > 0,
    }


@app.post("/embeddings")
def embeddings(
    payload: EmbeddingRequest,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    authorize(authorization)
    texts = [payload.input] if isinstance(payload.input, str) else payload.input
    if not texts:
        raise HTTPException(status_code=400, detail="input must not be empty")
    if len(texts) > 128:
        raise HTTPException(status_code=413, detail="too many embedding inputs")
    if any(not text.strip() for text in texts):
        raise HTTPException(status_code=400, detail="embedding input must not be blank")

    vectors = model().encode(
        texts,
        normalize_embeddings=True,
        convert_to_numpy=True,
        show_progress_bar=False,
    )
    data = [
        {
            "object": "embedding",
            "index": index,
            "embedding": vector.tolist(),
        }
        for index, vector in enumerate(vectors)
    ]
    return {
        "object": "list",
        "data": data,
        "model": MODEL_NAME,
        "usage": {
            "prompt_tokens": 0,
            "total_tokens": 0,
        },
    }
