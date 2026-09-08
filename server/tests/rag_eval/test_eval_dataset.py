import json
from pathlib import Path


def test_eval_dataset_has_multilingual_answerable_and_no_answer_cases():
    path = Path(__file__).with_name("eval_dataset.json")
    payload = json.loads(path.read_text(encoding="utf-8"))

    documents = payload["documents"]
    queries = payload["queries"]
    document_ids = {document["id"] for document in documents}

    assert len(documents) >= 10
    assert len(queries) >= 50
    assert any(not case["relevant"] for case in queries)
    assert any(any("\u4e00" <= char <= "\u9fff" for char in case["query"]) for case in queries)
    assert any(case["query"].isascii() for case in queries)

    for case in queries:
        assert set(case["relevant"]).issubset(document_ids)
