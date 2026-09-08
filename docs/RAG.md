# RAG

## 1. Ingestion

Uploads are validated by safe basename, extension and size. TXT/Markdown/source text use strict UTF-8 decoding; PDF, DOCX and PPTX are parsed with dedicated libraries. Empty or unparseable documents are rejected before indexing.

Documents are split into chunks at paragraph/heading boundaries and stored with document metadata in SQLite.

## 2. Retrieval Modes

```env
RAG_MODE=lexical
RAG_MODE=vector
RAG_MODE=hybrid
```

### Lexical

The lexical path tokenizes English words, Chinese characters, Chinese bigrams and trigrams. Chunks with zero overlap are excluded.

### Vector

Qdrant stores vectors with payload fields:

- `user_id`
- `knowledge_base_id`
- `document_id`
- `chunk_id`

Vector search always filters by authenticated user and optionally by knowledge base. A similarity threshold prevents weak nearest-neighbor results from automatically becoming citations.

### Hybrid

Hybrid retrieval combines lexical and vector rankings with Reciprocal Rank Fusion (RRF), then resolves fused chunk IDs back through SQLite ownership checks.

## 3. Embedding Providers

### Deterministic local provider

```env
EMBEDDING_PROVIDER=local
```

This is a small, deterministic hash-based vectorizer used for CI and offline reproducibility. It validates vector/Qdrant wiring, but it is **not** a neural semantic model and should not be presented as semantic-quality proof.

### OpenAI-compatible embedding provider

```env
EMBEDDING_PROVIDER=openai
EMBEDDING_BASE_URL=<base-url>
EMBEDDING_API_KEY=<secret>
EMBEDDING_MODEL=<model>
```

The backend posts to an OpenAI-compatible `/embeddings` endpoint. Provider secrets never enter Flutter.

### Optional local neural provider

`server/neural_embedding_service.py` exposes Sentence Transformers behind the same `/embeddings` contract. This avoids changing the production RAG interface while enabling real neural-semantic evaluation locally.

Install:

```powershell
cd server
pip install -r requirements-neural.txt
```

Start:

```powershell
uvicorn neural_embedding_service:app --host 127.0.0.1 --port 8002
```

Example backend configuration:

```env
EMBEDDING_PROVIDER=openai
EMBEDDING_BASE_URL=http://127.0.0.1:8002
EMBEDDING_API_KEY=
EMBEDDING_MODEL=sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2
QDRANT_COLLECTION=knowflow_chunks_neural_384
```

The default neural model emits 384-dimensional vectors. Use a separate Qdrant collection when switching from the default 256-dimensional deterministic provider; the application intentionally refuses a vector-dimension mismatch instead of silently corrupting an existing collection.

## 4. Index / Delete Consistency

Upload and Repository Learning perform:

```text
parse → chunk → SQLite → embedding → Qdrant upsert
```

Document and knowledge-base deletion remove relational rows and request matching Qdrant point deletion.

If Qdrant is unavailable, the system keeps the relational data and retains lexical fallback instead of making the whole application unavailable.

## 5. Grounding & Citations

Retrieved chunks become model grounding context. Citations preserve document/chunk identity. Retrieval explicitly supports a zero-result path so unrelated questions do not have to receive a fabricated citation.

The live v1.0 acceptance verified Qdrant retrieval, ownership filtering, deletion and fallback. DeepSeek was validated as the OpenAI-compatible LLM provider for grounded answers and Agent tool calls.

## 6. Evaluation

The expanded dataset is:

```text
server/tests/rag_eval/eval_dataset.json
```

It covers Chinese, English, mixed-language, source-code/project concepts, security, learning state, Agent/Memory and explicit no-answer queries.

Run:

```powershell
python scripts/rag-eval.py
```

Output defaults to:

```text
artifacts/rag-eval/latest.json
```

Metrics:

- Recall@3
- Recall@5
- MRR
- Citation Hit Rate
- No-answer false citation rate

Run once with the deterministic provider to establish the reproducible baseline, then run again against the local neural service or another embedding provider. A semantic provider should only be promoted as an improvement when the measured retrieval metrics justify it.

## 7. Streaming Note

`/chat/stream` emits SSE lifecycle events (`tool`, `message`, `done`). It is not token-by-token generation streaming; documentation must keep that distinction explicit.
