# Changelog

All notable changes to KnowFlow AI are documented here.

## [1.1.0] - 2026-09-09

### Added

- Local neural multilingual embedding path using `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`.
- Dedicated 384-dimensional Qdrant collection support for neural embeddings.
- Hybrid retrieval with Lexical + Vector + Reciprocal Rank Fusion.
- Multilingual MMARCO Cross-Encoder reranking.
- DeepSeek/OpenAI-compatible evidence-sufficiency verification with strict JSON output and fail-closed verified mode.
- `RAG_QUALITY_MODE=basic|rerank|verified` runtime quality modes.
- `/api/v1/runtime-quality` runtime diagnostics.
- Independent calibration, diagnostic holdouts, and untouched final Holdout V3 evaluation.
- Configurable `EMBEDDING_TIMEOUT_SECONDS` and `QDRANT_TIMEOUT_SECONDS` for neural cold starts and vector-store operations.
- Metadata-only indexing diagnostics that never log document text, API keys, or vector values.

### Quality

Final untouched Holdout V3 (`24` answerable / `12` no-answer) in `HybridVerified` mode:

- Recall@3: `1.0000`
- Recall@5: `1.0000`
- MRR: `1.0000`
- Citation Hit Rate: `1.0000`
- No-answer false citation rate: `0.0000`

Real runtime smoke after the final pipeline was wired into `/api/v1/chat`:

- Supported question: citation count `1`
- Unsupported high-confusion question: citation count `0`
- Neural document indexing: 4 chunks / 4 Qdrant points

### Hardened

- Neural embedding runtime no longer depends on the former fixed 20-second request timeout.
- Qdrant runtime timeout is configurable.
- Embedding and Qdrant indexing failures now emit safe stage-level diagnostics instead of collapsing into an unexplained `vector_indexed=false` result.
- Existing API keys, document contents, and vectors remain excluded from logs.

### Scope

The v1.1.0 engineering release continues to exclude physical-device certification and Google Play/AppGallery production signing. Simulator/runtime engineering acceptance remains the release baseline.

## [1.0.0] - 2026-09-08

- Initial frozen engineering release.
- Android API34 Emulator acceptance.
- HarmonyOS Emulator acceptance.
- TXT / Markdown / PDF / DOCX / PPTX ingestion.
- Qdrant live retrieval and initial Hybrid RAG.
- DeepSeek provider, Agent Tool Calling, Memory, Repository Learning, Learning Plan / Task / Quiz / Mastery.
