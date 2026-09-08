from fastapi.testclient import TestClient

import neural_embedding_service as service


class FakeVector:
    def __init__(self, values):
        self.values = values

    def tolist(self):
        return self.values


class FakeModel:
    def encode(self, texts, **_kwargs):
        return [FakeVector([1.0, 0.0, float(index)]) for index, _text in enumerate(texts)]


def test_health_does_not_force_model_download():
    client = TestClient(service.app)
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert "model" in response.json()


def test_embeddings_endpoint_is_openai_compatible(monkeypatch):
    monkeypatch.setattr(service, "model", lambda: FakeModel())
    client = TestClient(service.app)

    response = client.post(
        "/embeddings",
        json={"model": "fake", "input": ["中文语义", "semantic search"]},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["object"] == "list"
    assert [item["index"] for item in payload["data"]] == [0, 1]
    assert payload["data"][0]["object"] == "embedding"
    assert len(payload["data"][0]["embedding"]) == 3


def test_embeddings_rejects_blank_input_before_model_load():
    client = TestClient(service.app)
    response = client.post("/embeddings", json={"model": "fake", "input": ["   "]})

    assert response.status_code == 400
