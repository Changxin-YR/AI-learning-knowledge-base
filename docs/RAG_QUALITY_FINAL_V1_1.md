# KnowFlow AI RAG Quality Final Report (v1.1 candidate)

Date: 2026-09-09

## Scope

This report records the measured retrieval-quality evidence for the neural RAG upgrade on branch `feature/hybrid-confidence-gate`.

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

## Final quality verdict

`PASS`

The final untouched V3 holdout meets and exceeds the acceptance gate:

- Recall@3 >= 0.95: PASS
- Recall@5 >= 0.95: PASS
- MRR >= 0.95: PASS
- Citation Hit Rate >= 0.95: PASS
- No-answer false citation rate <= 0.125: PASS (`0.0000`)

## Engineering conclusion

The experiments show three distinct properties:

1. The multilingual neural embedding materially improves semantic retrieval over the deterministic/hash vector baseline.
2. Cross-Encoder scores are useful for ordering candidate evidence but are not a reliable answerability decision by themselves.
3. A strict evidence-sufficiency verifier is required to distinguish `topically related` from `explicitly answers the question` for high-confusion no-answer queries.

The intended production pipeline is therefore:

`Lexical + Neural Vector -> RRF candidates -> Cross-Encoder ordering -> Evidence Sufficiency Verification -> Citation / No Answer`

## Important scope note

These metrics prove the evaluation pipeline and verifier policy on an untouched holdout. They must not be presented as proof that the production `/api/v1/chat` path uses the complete pipeline until the same stages are wired into runtime retrieval and runtime regression tests pass.
