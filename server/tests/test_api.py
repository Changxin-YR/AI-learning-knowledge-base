import os
from pathlib import Path

TEST_DB = Path(__file__).with_name("test_knowflow.db")
if TEST_DB.exists():
    TEST_DB.unlink()
os.environ["SQLITE_PATH"] = str(TEST_DB)
os.environ["DEMO_AI_MODE"] = "1"

from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health_and_demo_login():
    assert client.get("/api/v1/health").json()["status"] == "ok"
    response = client.post("/api/v1/auth/demo")
    assert response.status_code == 200
    assert response.json()["access_token"]


def test_knowledge_chat_plan_quiz_flow():
    token = client.post("/api/v1/auth/demo").json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    kb = client.post("/api/v1/knowledge-bases", json={"name": "Python Basics"}, headers=headers)
    assert kb.status_code == 201
    kb_id = kb.json()["id"]

    upload = client.post(
        f"/api/v1/knowledge-bases/{kb_id}/documents",
        files={"file": ("notes.md", b"# Python\nPython is a programming language.\nUse lists for ordered values.", "text/markdown")},
        headers=headers,
    )
    assert upload.status_code == 201
    assert upload.json()["status"] == "indexed"

    answer = client.post(
        "/api/v1/chat",
        json={"knowledge_base_id": kb_id, "message": "What is Python?"},
        headers=headers,
    )
    assert answer.status_code == 200
    assert answer.json()["citations"]
    assert "Python" in answer.json()["content"]

    plan = client.post("/api/v1/learning/plans", json={"goal": "Learn Python", "days": 7}, headers=headers)
    assert plan.status_code == 201
    assert len(plan.json()["tasks"]) == 7

    quiz = client.post(f"/api/v1/quizzes?knowledge_base_id={kb_id}", headers=headers)
    assert quiz.status_code == 201
    question = quiz.json()["questions"][0]
    result = client.post(
        f"/api/v1/quizzes/{quiz.json()['id']}/submit",
        json={"answers": {question["id"]: question["answer"]}},
        headers=headers,
    )
    assert result.status_code == 200
    assert result.json()["mastery_score"] > 0


def test_permission_boundary():
    assert client.get("/api/v1/users/me").status_code == 401


def test_repository_and_sse_security_boundaries():
    token = client.post("/api/v1/auth/demo").json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    assert client.post("/api/v1/repositories/import", json={"url": "http://127.0.0.1/repo"}, headers=headers).status_code == 400
    stream = client.post("/api/v1/chat/stream", json={"message": "RAG"}, headers=headers)
    assert stream.status_code == 200
    assert "event: done" in stream.text
