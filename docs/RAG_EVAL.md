# RAG Evaluation

## Goal

RAG quality is evaluated independently from whether Qdrant is merely reachable. The goal is to measure whether a retrieval configuration actually improves answer grounding and citation quality.

## Dataset

The reproducible evaluation dataset is:

```text
server/tests/rag_eval/eval_dataset.json
```

It contains more than 50 queries across:

- Chinese
- English
- mixed Chinese/English
- Flutter/FastAPI architecture
- document parsing
- Repository Learning
- Quiz/Mastery
- Memory
- security/SSRF
- study tasks
- multi-turn conversation
- Qdrant ownership/filtering concepts
- Agent Tool Calling
- explicit no-answer queries

No-answer cases are included so a retriever is penalized when it always returns a nearest neighbor even when nothing is relevant.

## Metrics

The evaluation runner reports:

- **Recall@3**: whether a relevant document appears in the first 3 results.
- **Recall@5**: whether a relevant document appears in the first 5 results.
- **MRR**: rewards putting the first relevant result near the top.
- **Citation Hit Rate**: top-1 result matches the expected evidence source.
- **No-answer false citation rate**: fraction of no-answer cases that still produce a retrieval result.

## Run

From the repository root:

```powershell
python scripts/rag-eval.py
```

Default output:

```text
artifacts/rag-eval/latest.json
```

The report records the selected embedding provider, vector dimensions, model name, vector threshold and Lexical / Vector / Hybrid metrics.

## Deterministic Baseline

Default configuration:

```env
EMBEDDING_PROVIDER=local
RAG_MODE=hybrid
```

This is deliberately deterministic and suitable for CI. It validates the ranking/fusion pipeline but is not neural-semantic quality evidence.

## Neural Evaluation

Install the optional neural dependencies:

```powershell
cd server
pip install -r requirements-neural.txt
```

Start the local neural embedding endpoint:

```powershell
uvicorn neural_embedding_service:app --host 127.0.0.1 --port 8002
```

Configure the main process before running evaluation:

```env
EMBEDDING_PROVIDER=openai
EMBEDDING_BASE_URL=http://127.0.0.1:8002
EMBEDDING_API_KEY=
EMBEDDING_MODEL=sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2
QDRANT_COLLECTION=knowflow_chunks_neural_384
VECTOR_SCORE_THRESHOLD=0.35
```

Then run the exact same evaluator again.

## Acceptance Guidance

Do not label a neural provider as an improvement just because embeddings were generated successfully. Compare the output against the deterministic baseline. A useful upgrade should improve or preserve Recall/MRR/Citation Hit Rate without materially increasing the no-answer false citation rate.

Threshold tuning must be performed against the evaluation set, not by selecting a value that only makes a single demonstration query pass.

## Automated Coverage

The normal pytest suite keeps deterministic retrieval tests and validates the expanded dataset structure. Live Qdrant and provider acceptance remain separate runtime checks so GitHub CI does not depend on Docker, model downloads or paid external APIs.
