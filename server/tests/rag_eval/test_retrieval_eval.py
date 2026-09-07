CASES = [
    ("Python list", "Python lists keep ordered values"),
    ("Flutter widget", "Flutter widgets describe the UI tree"),
    ("RAG 检索", "RAG 先检索知识库再生成回答"),
    ("知识库引用", "回答需要带引用来源"),
    ("FastAPI route", "FastAPI route handles an HTTP request"),
    ("SQLite database", "SQLite stores local application data"),
    ("DOCX parser", "DOCX parser extracts paragraphs"),
    ("PPTX slides", "PPTX slides contain text boxes"),
    ("PDF text", "PDF text is extracted from pages"),
    ("学习计划", "学习计划按天生成任务"),
    ("任务完成", "任务可以标记为完成"),
    ("quiz mastery", "Quiz attempts update mastery"),
    ("conversation", "Conversation stores user and assistant messages"),
    ("memory preference", "User memory stores a learning preference"),
    ("repository README", "Repository README explains the project"),
    ("dependency metadata", "requirements.txt lists dependencies"),
    ("main entry", "main.py is an entry point"),
    ("中文 bigram", "中文字符和双字片段支持检索"),
    ("unknown query", "no matching evidence exists"),
    ("安全 ownership", "所有资源都必须校验用户归属"),
]


def test_retrieval_eval_meets_baseline_metrics():
    from app.main import search_tokens

    ranks = []
    citation_hits = 0
    for query, relevant in CASES:
        query_terms = search_tokens(query)
        candidates = [(len(query_terms & search_tokens(text)), text) for _, text in CASES]
        ranked = [text for score, text in sorted(candidates, reverse=True) if score > 0]
        if relevant in ranked[:3]:
            citation_hits += 1
        if ranked and relevant in ranked:
            ranks.append(ranked.index(relevant) + 1)
    recall_at_3 = citation_hits / len(CASES)
    mrr = sum(1 / rank for rank in ranks) / len(CASES)
    citation_hit_rate = citation_hits / len(CASES)
    assert recall_at_3 >= 0.5
    assert mrr >= 0.5
    assert citation_hit_rate >= 0.5
