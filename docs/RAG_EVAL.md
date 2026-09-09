# RAG Evaluation

## Goal

RAG quality is evaluated independently from whether Qdrant is merely reachable. The goal is to measure whether a retrieval configuration actually improves answer grounding and citation quality while preserving a reliable no-answer path.

## Calibration vs Holdout

Thresholds and confidence rules must not be selected and then reported against the same queries only.

The calibration dataset is:

```text
server/tests/rag_eval/eval_dataset.json
```

It contains 56 queries across Chinese, English, mixed-language architecture questions, document parsing, Repository Learning, Quiz/Mastery, Memory, security, study tasks, conversation, Qdrant, Agent Tool Calling and explicit no-answer cases.

The independent holdout dataset is:

```text
server/tests/rag_eval/holdout_dataset.json
```

The holdout set contains new paraphrases and harder no-answer questions that intentionally reuse domain words such as Python, Flutter, Qdrant, Agent and Repository. It must not be used to tune thresholds. Use it only after a candidate configuration is frozen.

## Metrics

The evaluation runner reports:

- **Recall@3**: whether a relevant document appears in the first 3 results.
- **Recall@5**: whether a relevant document appears in the first 5 results.
- **MRR**: rewards putting the first relevant result near the top.
- **Citation Hit Rate**: top-1 result matches the expected evidence source.
- **No-answer false citation rate**: fraction of no-answer cases that still produce a retrieval result.

## Hybrid Confidence Gate

RRF is a ranking algorithm, not a confidence estimator. An ungated hybrid retriever can therefore inherit lexical false positives even when the vector retriever correctly returns no semantic match.

KnowFlow now uses a semantic-backed confidence gate for neural/openai embedding providers:

1. Vector candidates must first satisfy `VECTOR_SCORE_THRESHOLD`.
2. Strong vector evidence at or above `HYBRID_STRONG_VECTOR_THRESHOLD` may answer directly.
3. Weaker vector evidence must agree with lexical retrieval within `HYBRID_AGREEMENT_TOP_K` positions.
4. RRF still combines lexical and vector ranks, but lexical-only documents are not emitted as citations when the gate is enabled.
5. If the embedding/Qdrant path is unavailable, hybrid mode preserves the existing lexical availability fallback.
6. The deterministic local hash vectorizer keeps the gate disabled in `auto` mode because it is an engineering test vectorizer, not semantic evidence.

Default calibration discovered from the neural MiniLM run:

```env
VECTOR_SCORE_THRESHOLD=0.35
HYBRID_CONFIDENCE_GATE=auto
HYBRID_STRONG_VECTOR_THRESHOLD=0.415
HYBRID_AGREEMENT_TOP_K=2
```

The strong threshold is not a replacement for the normal vector threshold. It is used only to decide whether a semantic result can pass without lexical corroboration.

## Run Calibration

From the repository root:

```powershell
python scripts/rag-eval.py --output artifacts/rag-eval/calibration.json
```

The report includes:

- `Lexical`
- `Vector`
- `HybridUngated`
- `Hybrid` (semantic-backed gated RRF)

This makes the effect of the gate explicit instead of hiding the old behavior.

## Run Holdout

After the threshold/gate configuration is frozen, run:

```powershell
python scripts/rag-eval.py `
  --dataset server/tests/rag_eval/holdout_dataset.json `
  --output artifacts/rag-eval/holdout.json
```

Do not change thresholds based on the holdout result and then claim the same holdout as an independent final score. If the holdout reveals a real weakness, create a new calibration iteration and later add another untouched holdout set.

## Deterministic Baseline

Default CI configuration:

```env
EMBEDDING_PROVIDER=local
RAG_MODE=hybrid
```

This is deliberately deterministic and suitable for CI. It validates ranking, fusion, ownership and fallback behavior but is not neural-semantic quality evidence. In `HYBRID_CONFIDENCE_GATE=auto`, the semantic gate remains disabled for this provider.

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

Configure the evaluation shell:

```powershell
$env:EMBEDDING_PROVIDER="openai"
$env:EMBEDDING_BASE_URL="http://127.0.0.1:8002"
$env:EMBEDDING_API_KEY=""
$env:EMBEDDING_MODEL="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
$env:VECTOR_SCORE_THRESHOLD="0.35"
$env:HYBRID_CONFIDENCE_GATE="1"
$env:HYBRID_STRONG_VECTOR_THRESHOLD="0.415"
$env:HYBRID_AGREEMENT_TOP_K="2"
```

The previously measured calibration result for the neural model established that `0.35` preserved substantially more recall than higher vector thresholds. The confidence gate is intended to reduce false citations without using an excessively high vector threshold as a blunt rejection mechanism.

## Acceptance Guidance

A useful neural retrieval upgrade should:

- materially outperform the deterministic vector baseline;
- preserve high Recall/MRR/Citation Hit Rate;
- lower no-answer false citations;
- keep ownership filtering intact;
- preserve lexical fallback when vector infrastructure is unavailable.

For the gated Hybrid path, a practical target is:

```text
Recall@3 >= 0.95
MRR >= 0.95
No-answer false citation rate <= 0.125
```

Prefer a balanced configuration over a threshold that reaches zero false citations by discarding a large fraction of valid answerable queries.

## Automated Coverage

The normal pytest suite validates:

- RRF behavior;
- semantic gate strong-evidence behavior;
- weak-evidence lexical/vector agreement;
- rejection when no semantic evidence exists;
- exclusion of lexical-only citations from gated Hybrid output;
- SQLite ownership re-checks;
- lexical fallback when the vector path is unavailable.

Live neural and Qdrant quality evaluation remains a separate runtime check so GitHub CI does not depend on model downloads, Docker availability or paid external APIs.
