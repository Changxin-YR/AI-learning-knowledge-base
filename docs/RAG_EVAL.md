# RAG Eval

The deterministic fixture is `sample_data/rag_notes.md`. `server/tests/rag_eval/test_retrieval_eval.py` covers the lexical baseline and `server/tests/rag_eval/test_vector_metrics.py` runs 30 Chinese, English, mixed, code, repository, security, task, memory and conversation queries. It writes `artifacts/final-round3/rag-eval/vector-evaluation.json` with Recall@3, Recall@5, MRR, Citation Hit Rate and no-answer false citation rate for Lexical, Vector and Hybrid. The report labels the local deterministic provider separately from a live Qdrant runtime run.
