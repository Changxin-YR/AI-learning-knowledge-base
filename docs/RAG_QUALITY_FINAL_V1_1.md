# KnowFlow AI RAG Quality Final Report (v1.1)

Date: 2026-09-09

## Scope

This report records the measured retrieval-quality evidence and final runtime verification for the neural RAG upgrade merged through PR #12 and hardened for v1.1.0.

The evaluation separates development/calibration queries from untouched holdout queries. A holdout is not reused for threshold/prompt tuning after its result is observed.

## Models and runtime

- Neural embedding: `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`
- Embedding dimensions: `384`
- Vector threshold: `0.35`
- Cross-Encoder: `cross-encoder/mmarco-mMiniLMv2-L12-H384-v1`
- Cross-Encoder role: candidate ordering only, not answerability
- Evidence verifier: `deepseek-v4-flash`
- Evidence verifier mode: non-thinking, structured JSON output
- Evidence verifier candidate limit: `4`
- Runtime quality mode: `verified`
- Neural Qdrant collection: `knowflow_chunks_neural_384`

## Calibration result

Dataset: `server/tests/rag_eval/eval_dataset.json`

Cases: 56 total — 48 answerable, 8 no-answer.

### HybridVerified

| Metric | Result |
| --- | ---: |
| Recall@3 | 0.9583 |
| Recall@5 | 0.9583 |
| MRR | 0.9583 |
| Citation Hit Rate | 0.9583 |
| No-answer false citation rate | 0.0000 |

The verifier policy was frozen after this calibration result before running the final V3 holdout.

## Final untouched Holdout V3

Dataset: `server/tests/rag_eval/holdout_v3_dataset.json`

Cases: 36 total — 24 answerable, 12 no-answer.

### Baselines on Holdout V3

| Mode | Recall@3 | Recall@5 | MRR | Citation Hit | No-answer false citation |
| --- | ---: | ---: | ---: | ---: | ---: |
| Lexical | 0.9167 | 0.9167 | 0.8056 | 0.7083 | 1.0000 |
| Neural Vector | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 0.8333 |
| Hybrid Ungated | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
| Hybrid semantic gate | 0.9583 | 0.9583 | 0.9583 | 0.9583 | 0.8333 |
| Cross-Encoder reranked | 0.9583 | 0.9583 | 0.9583 | 0.9583 | 0.8333 |
| **HybridVerified** | **1.0000** | **1.0000** | **1.0000** | **1.0000** | **0.0000** |

## Real runtime smoke

The final `/api/v1/chat` runtime path was exercised with `RAG_QUALITY_MODE=verified` after the V3 policy was frozen.

Runtime status:

- `rag_quality_mode = verified`
- `reranker_configured = true`
- `answerability_configured = true`
- `embedding_provider = openai`
- `vector_threshold = 0.35`

Indexing evidence:

- UTF-8 source document parsed successfully
- `chunk_count = 4`
- MiniLM embedding dimension = `384`
- Qdrant collection dimension = `384 / Cosine`
- Qdrant filtered scroll for the uploaded `document_id` returned `4` points

Answerability evidence:

- Supported question (`Qdrant point payload` ownership IDs): citation count = `1`
- Unsupported high-confusion question (`Qdrant` cloud region, absent from the document): citation count = `0`

This confirms that the validated pipeline is not evaluation-only; it is active in the real runtime chat path.

## Runtime hardening

The v1.1.0 hardening layer addresses the cold-start and observability issues found during final runtime smoke:

- `EMBEDDING_TIMEOUT_SECONDS` is configurable; runtime default = `120` seconds.
- `QDRANT_TIMEOUT_SECONDS` is configurable; runtime default = `10` seconds.
- Embedding failures log stage, model, timeout, batch size and error type only.
- Qdrant failures log method/path, collection, timeout, dimensions/point count and error type only.
- Document text, API keys and vector values are not logged.
- `/api/v1/runtime-quality` exposes the active timeout values and application version.

## Final quality verdict

`PASS`

The final untouched V3 holdout meets and exceeds the acceptance gate:

- Recall@3 >= 0.95: PASS
- Recall@5 >= 0.95: PASS
- MRR >= 0.95: PASS
- Citation Hit Rate >= 0.95: PASS
- No-answer false citation rate <= 0.125: PASS (`0.0000`)

The real runtime smoke also passes:

- Neural vector indexing: PASS
- Supported citation: PASS
- Unsupported/no-answer refusal: PASS

## Engineering conclusion

The experiments and runtime smoke show four distinct properties:

1. The multilingual neural embedding materially improves semantic retrieval over the deterministic/hash vector baseline.
2. Cross-Encoder scores are useful for ordering candidate evidence but are not a reliable answerability decision by themselves.
3. A strict evidence-sufficiency verifier is required to distinguish `topically related` from `explicitly answers the question` for high-confusion no-answer queries.
4. The validated pipeline is wired into the production runtime entrypoint (`app.runtime`) and has passed a real citation/no-citation smoke test.

The v1.1.0 runtime pipeline is therefore:

`Lexical + Neural Vector -> RRF candidates -> Cross-Encoder ordering -> Evidence Sufficiency Verification -> Citation / No Answer`

## Scope note

This is an engineering/simulator acceptance result. It does not claim physical-device certification, ARM64 physical-runtime certification, Google Play production signing, or AppGallery production signing.
