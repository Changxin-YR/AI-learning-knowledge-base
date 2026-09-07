from __future__ import annotations

import io
import ipaddress
import json
import os
import re
import secrets
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
import jwt
from argon2 import PasswordHasher
from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = Path(os.getenv("SQLITE_PATH", DATA_DIR / "knowflow.db"))
SECRET = os.getenv("JWT_SECRET", "knowflow-local-secret-change-me-32-bytes")
TOKEN_TTL_MINUTES = int(os.getenv("ACCESS_TOKEN_MINUTES", "60"))
PH = PasswordHasher()


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def migrate() -> None:
    schema = """
    CREATE TABLE IF NOT EXISTS schema_version(version INTEGER PRIMARY KEY);
    CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL, name TEXT NOT NULL, password_hash TEXT NOT NULL, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS refresh_tokens(id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), token_hash TEXT UNIQUE NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, expires_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS knowledge_bases(id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), name TEXT NOT NULL, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS documents(id TEXT PRIMARY KEY, knowledge_base_id TEXT NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE, filename TEXT NOT NULL, mime_type TEXT NOT NULL, content TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS chunks(id TEXT PRIMARY KEY, document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE, content TEXT NOT NULL, position INTEGER NOT NULL, metadata TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS conversations(id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), title TEXT NOT NULL, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, role TEXT NOT NULL, content TEXT NOT NULL, citations TEXT NOT NULL, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS study_plans(id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), goal TEXT NOT NULL, days INTEGER NOT NULL, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS study_tasks(id TEXT PRIMARY KEY, plan_id TEXT NOT NULL REFERENCES study_plans(id) ON DELETE CASCADE, title TEXT NOT NULL, due_date TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS quizzes(id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), knowledge_base_id TEXT, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS quiz_questions(id TEXT PRIMARY KEY, quiz_id TEXT NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE, prompt TEXT NOT NULL, options TEXT NOT NULL, answer TEXT NOT NULL, knowledge TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS quiz_attempts(id TEXT PRIMARY KEY, quiz_id TEXT NOT NULL REFERENCES quizzes(id), user_id TEXT NOT NULL REFERENCES users(id), score REAL NOT NULL, created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS mastery(user_id TEXT NOT NULL REFERENCES users(id), knowledge TEXT NOT NULL, score REAL NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(user_id, knowledge));
    CREATE TABLE IF NOT EXISTS repository_imports(id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), url TEXT NOT NULL, status TEXT NOT NULL, analysis TEXT NOT NULL, created_at TEXT NOT NULL);
    """
    with db() as conn:
        conn.executescript(schema)
        conn.execute("INSERT OR IGNORE INTO schema_version(version) VALUES (1)")


migrate()
app = FastAPI(title="KnowFlow AI API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_id(request, call_next):
    trace_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    response = await call_next(request)
    response.headers["X-Request-ID"] = trace_id
    return response


class KBIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    knowledge_base_id: str | None = None
    conversation_id: str | None = None


class PlanIn(BaseModel):
    goal: str = Field(min_length=1, max_length=200)
    days: int = Field(default=7, ge=1, le=14)


class SubmitIn(BaseModel):
    answers: dict[str, str]


def token_for(user_id: str) -> str:
    return jwt.encode(
        {"sub": user_id, "exp": datetime.now(timezone.utc) + timedelta(minutes=TOKEN_TTL_MINUTES)},
        SECRET,
        algorithm="HS256",
    )


def current_user(authorization: str | None = Header(default=None)) -> sqlite3.Row:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Authentication required")
    try:
        payload = jwt.decode(authorization.split(" ", 1)[1], SECRET, algorithms=["HS256"])
        user_id = payload["sub"]
    except (jwt.PyJWTError, KeyError):
        raise HTTPException(401, "Invalid or expired token")
    with db() as conn:
        user = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
    if not user:
        raise HTTPException(401, "User not found")
    return user


def owned_kb(user_id: str, kb_id: str) -> sqlite3.Row:
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM knowledge_bases WHERE id=? AND user_id=?",
            (kb_id, user_id),
        ).fetchone()
    if not row:
        raise HTTPException(404, "Knowledge base not found")
    return row


def owned_conversation(user_id: str, conversation_id: str) -> sqlite3.Row:
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM conversations WHERE id=? AND user_id=?",
            (conversation_id, user_id),
        ).fetchone()
    if not row:
        raise HTTPException(404, "Conversation not found")
    return row


def safe_filename(name: str) -> str:
    clean = Path(name).name
    if not clean or clean in {".", ".."} or len(clean) > 180:
        raise HTTPException(400, "Invalid filename")
    return clean


def _extract_pdf(payload: bytes) -> str:
    try:
        from pypdf import PdfReader

        reader = PdfReader(io.BytesIO(payload))
        return "\n".join(page.extract_text() or "" for page in reader.pages)
    except Exception as exc:
        raise HTTPException(422, "PDF could not be parsed") from exc


def _extract_docx(payload: bytes) -> str:
    try:
        from docx import Document

        document = Document(io.BytesIO(payload))
        return "\n".join(paragraph.text for paragraph in document.paragraphs)
    except Exception as exc:
        raise HTTPException(422, "DOCX could not be parsed") from exc


def _extract_pptx(payload: bytes) -> str:
    try:
        from pptx import Presentation

        presentation = Presentation(io.BytesIO(payload))
        parts: list[str] = []
        for slide in presentation.slides:
            for shape in slide.shapes:
                if hasattr(shape, "text") and shape.text:
                    parts.append(shape.text)
        return "\n".join(parts)
    except Exception as exc:
        raise HTTPException(422, "PPTX could not be parsed") from exc


def parse_content(filename: str, payload: bytes) -> str:
    suffix = Path(filename).suffix.lower()
    if suffix not in {
        ".pdf",
        ".docx",
        ".pptx",
        ".md",
        ".txt",
        ".py",
        ".dart",
        ".js",
        ".ts",
        ".json",
        ".yaml",
        ".yml",
    }:
        raise HTTPException(415, "Unsupported file type")
    if len(payload) > 10 * 1024 * 1024:
        raise HTTPException(413, "File too large")

    if suffix == ".pdf":
        text = _extract_pdf(payload)
    elif suffix == ".docx":
        text = _extract_docx(payload)
    elif suffix == ".pptx":
        text = _extract_pptx(payload)
    else:
        try:
            text = payload.decode("utf-8", errors="strict")
        except UnicodeDecodeError as exc:
            raise HTTPException(422, "Text document must be UTF-8") from exc

    text = text.strip()
    if not text:
        raise HTTPException(422, "Document contains no extractable text")
    return text


def make_chunks(text: str) -> list[str]:
    blocks = [
        x.strip()
        for x in re.split(r"\n\s*\n|(?=^#{1,6}\s)", text, flags=re.M)
        if x.strip()
    ]
    chunks: list[str] = []
    for block in blocks:
        if len(block) <= 900:
            chunks.append(block)
        else:
            chunks.extend(block[i : i + 900] for i in range(0, len(block), 900))
    return chunks or [text[:900]]


def search_terms(text: str) -> set[str]:
    normalized = text.lower()
    terms = set(re.findall(r"[a-z0-9_]+", normalized))
    for sequence in re.findall(r"[\u4e00-\u9fff]+", normalized):
        terms.update(sequence)
        if len(sequence) > 1:
            terms.update(sequence[i : i + 2] for i in range(len(sequence) - 1))
        if len(sequence) > 2:
            terms.update(sequence[i : i + 3] for i in range(len(sequence) - 2))
    return terms


def retrieve(
    user_id: str,
    kb_id: str | None,
    query: str,
    limit: int = 4,
) -> list[sqlite3.Row]:
    terms = search_terms(query)
    with db() as conn:
        if kb_id:
            owned_kb(user_id, kb_id)
            rows = conn.execute(
                "SELECT c.*, d.filename, d.knowledge_base_id "
                "FROM chunks c JOIN documents d ON d.id=c.document_id "
                "WHERE d.knowledge_base_id=?",
                (kb_id,),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT c.*, d.filename, d.knowledge_base_id "
                "FROM chunks c JOIN documents d ON d.id=c.document_id "
                "JOIN knowledge_bases k ON k.id=d.knowledge_base_id "
                "WHERE k.user_id=?",
                (user_id,),
            ).fetchall()

    scored: list[tuple[float, sqlite3.Row]] = []
    for row in rows:
        candidate_terms = search_terms(row["content"])
        overlap = terms & candidate_terms
        if not overlap:
            continue
        score = len(overlap) / max(1, len(terms))
        scored.append((score, row))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [row for _, row in scored[:limit]]


def citation(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "chunk_id": row["id"],
        "document_id": row["document_id"],
        "filename": row["filename"],
        "section": row["position"] + 1,
        "preview": row["content"][:180],
    }


def deterministic_answer(rows: list[sqlite3.Row]) -> str:
    if not rows:
        return "我还没有找到相关资料。请先上传文档，或换一个更具体的问题。"
    return f"基于你的知识库，{rows[0]['content'][:500]}"


def model_answer(question: str, rows: list[sqlite3.Row]) -> str:
    fallback = deterministic_answer(rows)
    if not rows:
        return fallback
    if os.getenv("DEMO_AI_MODE", "1") == "1":
        return fallback

    base_url = os.getenv("OPENAI_BASE_URL", "").strip().rstrip("/")
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini").strip()
    if not base_url or not api_key:
        return fallback

    context = "\n\n".join(
        f"[{index + 1}] {row['filename']} / section {row['position'] + 1}\n{row['content']}"
        for index, row in enumerate(rows)
    )
    try:
        with httpx.Client(timeout=20.0) as client:
            response = client.post(
                f"{base_url}/chat/completions",
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": model,
                    "temperature": 0.2,
                    "messages": [
                        {
                            "role": "system",
                            "content": (
                                "你是 KnowFlow AI 学习助手。只能基于提供的知识库上下文作答；"
                                "上下文不足时明确说明，不要编造。回答使用简洁中文。"
                            ),
                        },
                        {
                            "role": "user",
                            "content": f"问题：{question}\n\n知识库上下文：\n{context}",
                        },
                    ],
                },
            )
            response.raise_for_status()
            data = response.json()
            content = data["choices"][0]["message"]["content"]
            if isinstance(content, str) and content.strip():
                return content.strip()
    except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError):
        pass
    return fallback


@app.get("/api/v1/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "knowflow-api"}


@app.get("/api/v1/ready")
def ready() -> dict[str, Any]:
    with db() as conn:
        conn.execute("SELECT 1")
    return {
        "status": "ready",
        "database": "sqlite",
        "demo_ai": os.getenv("DEMO_AI_MODE", "1") == "1",
    }


@app.post("/api/v1/auth/demo")
def demo_login() -> dict[str, Any]:
    with db() as conn:
        user = conn.execute(
            "SELECT * FROM users WHERE email=?",
            ("demo@knowflow.local",),
        ).fetchone()
        if not user:
            user_id = str(uuid.uuid4())
            conn.execute(
                "INSERT INTO users VALUES (?,?,?,?,?)",
                (
                    user_id,
                    "demo@knowflow.local",
                    "Demo 学习者",
                    PH.hash("KnowFlowDemo123!"),
                    now(),
                ),
            )
            conn.commit()
            user = conn.execute("SELECT * FROM users WHERE id=?", (user_id,)).fetchone()
    return {
        "access_token": token_for(user["id"]),
        "refresh_token": secrets.token_urlsafe(32),
        "token_type": "bearer",
        "user": {
            "id": user["id"],
            "email": user["email"],
            "name": user["name"],
        },
    }


@app.post("/api/v1/auth/register")
def register(body: dict[str, str]) -> dict[str, Any]:
    email = body.get("email", "").strip().lower()
    password = body.get("password", "")
    name = body.get("name", "学习者").strip()
    if "@" not in email or len(password) < 8:
        raise HTTPException(400, "Valid email and 8+ character password required")
    user_id = str(uuid.uuid4())
    try:
        with db() as conn:
            conn.execute(
                "INSERT INTO users VALUES (?,?,?,?,?)",
                (user_id, email, name or "学习者", PH.hash(password), now()),
            )
    except sqlite3.IntegrityError as exc:
        raise HTTPException(409, "Email already registered") from exc
    return {
        "access_token": token_for(user_id),
        "token_type": "bearer",
        "user": {"id": user_id, "email": email, "name": name or "学习者"},
    }


@app.get("/api/v1/users/me")
def me(user=Depends(current_user)) -> dict[str, Any]:
    return {"id": user["id"], "email": user["email"], "name": user["name"]}


@app.get("/api/v1/knowledge-bases")
def list_kbs(user=Depends(current_user)) -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute(
            "SELECT k.*, COUNT(d.id) AS document_count "
            "FROM knowledge_bases k "
            "LEFT JOIN documents d ON d.knowledge_base_id=k.id "
            "WHERE k.user_id=? GROUP BY k.id ORDER BY k.created_at DESC",
            (user["id"],),
        ).fetchall()
    return [dict(row) for row in rows]


@app.post("/api/v1/knowledge-bases", status_code=201)
def create_kb(body: KBIn, user=Depends(current_user)) -> dict[str, Any]:
    kb_id = str(uuid.uuid4())
    with db() as conn:
        conn.execute(
            "INSERT INTO knowledge_bases VALUES (?,?,?,?)",
            (kb_id, user["id"], body.name.strip(), now()),
        )
    return {
        "id": kb_id,
        "user_id": user["id"],
        "name": body.name.strip(),
        "document_count": 0,
    }


@app.delete("/api/v1/knowledge-bases/{kb_id}")
def delete_kb(kb_id: str, user=Depends(current_user)) -> dict[str, bool]:
    owned_kb(user["id"], kb_id)
    with db() as conn:
        conn.execute("DELETE FROM knowledge_bases WHERE id=?", (kb_id,))
    return {"deleted": True}


@app.get("/api/v1/knowledge-bases/{kb_id}/documents")
def list_documents(kb_id: str, user=Depends(current_user)) -> list[dict[str, Any]]:
    owned_kb(user["id"], kb_id)
    with db() as conn:
        rows = conn.execute(
            "SELECT id,filename,mime_type,status,created_at "
            "FROM documents WHERE knowledge_base_id=? ORDER BY created_at DESC",
            (kb_id,),
        ).fetchall()
    return [dict(row) for row in rows]


@app.post("/api/v1/knowledge-bases/{kb_id}/documents", status_code=201)
async def upload_document(
    kb_id: str,
    file: UploadFile = File(...),
    user=Depends(current_user),
) -> dict[str, Any]:
    owned_kb(user["id"], kb_id)
    filename = safe_filename(file.filename or "document.txt")
    payload = await file.read()
    content = parse_content(filename, payload)
    document_id = str(uuid.uuid4())
    chunks = make_chunks(content)
    with db() as conn:
        conn.execute(
            "INSERT INTO documents VALUES (?,?,?,?,?,?,?)",
            (
                document_id,
                kb_id,
                filename,
                file.content_type or "text/plain",
                content,
                "indexed",
                now(),
            ),
        )
        for position, chunk in enumerate(chunks):
            conn.execute(
                "INSERT INTO chunks VALUES (?,?,?,?,?)",
                (
                    str(uuid.uuid4()),
                    document_id,
                    chunk,
                    position,
                    json.dumps(
                        {"filename": filename, "section": position + 1},
                        ensure_ascii=False,
                    ),
                ),
            )
    return {
        "id": document_id,
        "filename": filename,
        "status": "indexed",
        "chunk_count": len(chunks),
    }


@app.get("/api/v1/documents/{document_id}")
def document_detail(document_id: str, user=Depends(current_user)) -> dict[str, Any]:
    with db() as conn:
        row = conn.execute(
            "SELECT d.* FROM documents d "
            "JOIN knowledge_bases k ON k.id=d.knowledge_base_id "
            "WHERE d.id=? AND k.user_id=?",
            (document_id, user["id"]),
        ).fetchone()
        if not row:
            raise HTTPException(404, "Document not found")
        chunks = conn.execute(
            "SELECT id,content,position,metadata "
            "FROM chunks WHERE document_id=? ORDER BY position",
            (document_id,),
        ).fetchall()
    return {**dict(row), "chunks": [dict(chunk) for chunk in chunks]}


@app.post("/api/v1/chat")
def chat(body: ChatIn, user=Depends(current_user)) -> dict[str, Any]:
    if body.conversation_id:
        owned_conversation(user["id"], body.conversation_id)

    rows = retrieve(user["id"], body.knowledge_base_id, body.message)
    citations = [citation(row) for row in rows]
    answer = model_answer(body.message, rows)
    conversation_id = body.conversation_id or str(uuid.uuid4())

    with db() as conn:
        if not body.conversation_id:
            conn.execute(
                "INSERT INTO conversations VALUES (?,?,?,?)",
                (conversation_id, user["id"], body.message[:40], now()),
            )
        conn.execute(
            "INSERT INTO messages VALUES (?,?,?,?,?,?)",
            (str(uuid.uuid4()), conversation_id, "user", body.message, "[]", now()),
        )
        conn.execute(
            "INSERT INTO messages VALUES (?,?,?,?,?,?)",
            (
                str(uuid.uuid4()),
                conversation_id,
                "assistant",
                answer,
                json.dumps(citations, ensure_ascii=False),
                now(),
            ),
        )

    return {
        "conversation_id": conversation_id,
        "content": answer,
        "citations": citations,
        "tool_events": [
            {"tool": "search_knowledge", "status": "completed", "count": len(rows)}
        ],
    }


@app.post("/api/v1/chat/stream")
def chat_stream(body: ChatIn, user=Depends(current_user)) -> StreamingResponse:
    result = chat(body, user)

    def events():
        yield (
            "event: tool\n"
            f"data: {json.dumps(result['tool_events'][0], ensure_ascii=False)}\n\n"
        )
        yield (
            "event: message\n"
            f"data: {json.dumps(result, ensure_ascii=False)}\n\n"
        )
        yield "event: done\ndata: {}\n\n"

    return StreamingResponse(events(), media_type="text/event-stream")


@app.get("/api/v1/conversations")
def conversations(user=Depends(current_user)) -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM conversations WHERE user_id=? ORDER BY created_at DESC",
            (user["id"],),
        ).fetchall()
    return [dict(row) for row in rows]


@app.post("/api/v1/learning/plans", status_code=201)
def create_plan(body: PlanIn, user=Depends(current_user)) -> dict[str, Any]:
    plan_id = str(uuid.uuid4())
    created = datetime.now(timezone.utc)
    tasks = []
    with db() as conn:
        conn.execute(
            "INSERT INTO study_plans VALUES (?,?,?,?,?)",
            (plan_id, user["id"], body.goal, body.days, now()),
        )
        for index in range(body.days):
            task_id = str(uuid.uuid4())
            due = (created + timedelta(days=index)).date().isoformat()
            title = f"{body.goal} · 第 {index + 1} 天"
            conn.execute(
                "INSERT INTO study_tasks VALUES (?,?,?,?,?)",
                (task_id, plan_id, title, due, 0),
            )
            tasks.append(
                {
                    "id": task_id,
                    "title": title,
                    "due_date": due,
                    "completed": False,
                }
            )
    return {"id": plan_id, "goal": body.goal, "days": body.days, "tasks": tasks}


@app.get("/api/v1/learning/tasks")
def list_tasks(user=Depends(current_user)) -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute(
            "SELECT t.* FROM study_tasks t "
            "JOIN study_plans p ON p.id=t.plan_id "
            "WHERE p.user_id=? ORDER BY t.due_date",
            (user["id"],),
        ).fetchall()
    return [{**dict(row), "completed": bool(row["completed"])} for row in rows]


@app.patch("/api/v1/learning/tasks/{task_id}")
def update_task(
    task_id: str,
    body: dict[str, Any],
    user=Depends(current_user),
) -> dict[str, Any]:
    completed = bool(body.get("completed", False))
    with db() as conn:
        row = conn.execute(
            "SELECT t.* FROM study_tasks t "
            "JOIN study_plans p ON p.id=t.plan_id "
            "WHERE t.id=? AND p.user_id=?",
            (task_id, user["id"]),
        ).fetchone()
        if not row:
            raise HTTPException(404, "Task not found")
        conn.execute(
            "UPDATE study_tasks SET completed=? WHERE id=?",
            (int(completed), task_id),
        )
    return {"id": task_id, "completed": completed}


@app.post("/api/v1/quizzes", status_code=201)
def create_quiz(
    knowledge_base_id: str | None = None,
    user=Depends(current_user),
) -> dict[str, Any]:
    if knowledge_base_id:
        owned_kb(user["id"], knowledge_base_id)
    rows = retrieve(user["id"], knowledge_base_id, "knowledge learning 学习 知识", 1)
    source = rows[0]["content"] if rows else "学习需要持续练习并及时复习。"
    knowledge = (source.splitlines()[0].lstrip("# ") or "基础知识")[:80]
    quiz_id, question_id = str(uuid.uuid4()), str(uuid.uuid4())
    question = {
        "id": question_id,
        "prompt": f"以下哪项最符合资料内容？\n{source[:180]}",
        "options": [
            "资料中的核心描述",
            "完全相反的说法",
            "与主题无关",
            "无法判断",
        ],
        "answer": "资料中的核心描述",
        "knowledge": knowledge,
    }
    with db() as conn:
        conn.execute(
            "INSERT INTO quizzes VALUES (?,?,?,?)",
            (quiz_id, user["id"], knowledge_base_id, now()),
        )
        conn.execute(
            "INSERT INTO quiz_questions VALUES (?,?,?,?,?,?)",
            (
                question_id,
                quiz_id,
                question["prompt"],
                json.dumps(question["options"], ensure_ascii=False),
                question["answer"],
                knowledge,
            ),
        )
    return {"id": quiz_id, "questions": [question]}


@app.post("/api/v1/quizzes/{quiz_id}/submit")
def submit_quiz(
    quiz_id: str,
    body: SubmitIn,
    user=Depends(current_user),
) -> dict[str, Any]:
    with db() as conn:
        quiz = conn.execute(
            "SELECT * FROM quizzes WHERE id=? AND user_id=?",
            (quiz_id, user["id"]),
        ).fetchone()
        if not quiz:
            raise HTTPException(404, "Quiz not found")
        questions = conn.execute(
            "SELECT * FROM quiz_questions WHERE quiz_id=?",
            (quiz_id,),
        ).fetchall()
        score = (
            sum(body.answers.get(q["id"]) == q["answer"] for q in questions)
            / max(1, len(questions))
            * 100
        )
        conn.execute(
            "INSERT INTO quiz_attempts VALUES (?,?,?,?,?)",
            (str(uuid.uuid4()), quiz_id, user["id"], score, now()),
        )
        new_score = 0.0
        for q in questions:
            old = conn.execute(
                "SELECT score FROM mastery WHERE user_id=? AND knowledge=?",
                (user["id"], q["knowledge"]),
            ).fetchone()
            new_score = round(
                (old["score"] * 0.6 + score * 0.4) if old else score,
                2,
            )
            conn.execute(
                "INSERT INTO mastery VALUES (?,?,?,?) "
                "ON CONFLICT(user_id, knowledge) DO UPDATE SET "
                "score=excluded.score, updated_at=excluded.updated_at",
                (user["id"], q["knowledge"], new_score, now()),
            )
    return {
        "score": score,
        "mastery_score": new_score,
        "correct": score == 100,
    }


@app.get("/api/v1/mastery")
def mastery(user=Depends(current_user)) -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute(
            "SELECT knowledge,score,updated_at "
            "FROM mastery WHERE user_id=? ORDER BY score",
            (user["id"],),
        ).fetchall()
    return [dict(row) for row in rows]


@app.get("/api/v1/knowledge-graph")
def knowledge_graph(user=Depends(current_user)) -> dict[str, Any]:
    nodes = mastery(user)
    return {
        "nodes": [
            {"id": n["knowledge"], "label": n["knowledge"], "mastery": n["score"]}
            for n in nodes
        ],
        "edges": [],
    }


@app.get("/api/v1/stats")
def stats(user=Depends(current_user)) -> dict[str, Any]:
    with db() as conn:
        kb = conn.execute(
            "SELECT COUNT(*) FROM knowledge_bases WHERE user_id=?",
            (user["id"],),
        ).fetchone()[0]
        docs = conn.execute(
            "SELECT COUNT(*) FROM documents d "
            "JOIN knowledge_bases k ON k.id=d.knowledge_base_id "
            "WHERE k.user_id=?",
            (user["id"],),
        ).fetchone()[0]
        tasks = conn.execute(
            "SELECT COUNT(*), COALESCE(SUM(completed),0) FROM study_tasks t "
            "JOIN study_plans p ON p.id=t.plan_id WHERE p.user_id=?",
            (user["id"],),
        ).fetchone()
        quizzes = conn.execute(
            "SELECT COUNT(*), COALESCE(AVG(score),0) "
            "FROM quiz_attempts WHERE user_id=?",
            (user["id"],),
        ).fetchone()
    return {
        "knowledge_bases": kb,
        "documents": docs,
        "tasks_total": tasks[0],
        "tasks_completed": tasks[1],
        "task_completion_rate": (
            round(tasks[1] / tasks[0] * 100, 2) if tasks[0] else 0
        ),
        "quiz_attempts": quizzes[0],
        "quiz_accuracy": round(quizzes[1], 2),
        "learning_minutes": 0,
        "streak_days": 0,
    }


def is_public_repository_host(hostname: str) -> bool:
    if hostname.lower() in {"localhost"}:
        return False
    try:
        address = ipaddress.ip_address(hostname)
    except ValueError:
        return True
    return not (
        address.is_private
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_reserved
        or address.is_unspecified
    )


@app.post("/api/v1/repositories/import", status_code=201)
def import_repository(
    body: dict[str, str],
    user=Depends(current_user),
) -> dict[str, Any]:
    url = body.get("url", "").strip()
    parsed = urlparse(url)
    if (
        parsed.scheme not in {"https", "http"}
        or not parsed.hostname
        or not is_public_repository_host(parsed.hostname)
    ):
        raise HTTPException(400, "Only public HTTP(S) repositories are allowed")
    repo = Path(parsed.path.rstrip("/")).name or parsed.hostname
    analysis = {
        "name": repo.removesuffix(".git"),
        "technology": ["Git"],
        "entry_points": ["README.md"],
        "modules": ["source tree", "dependency metadata"],
        "next_steps": ["阅读 README", "定位入口文件", "绘制模块关系"],
    }
    import_id = str(uuid.uuid4())
    with db() as conn:
        conn.execute(
            "INSERT INTO repository_imports VALUES (?,?,?,?,?,?)",
            (
                import_id,
                user["id"],
                url,
                "indexed",
                json.dumps(analysis, ensure_ascii=False),
                now(),
            ),
        )
    return {
        "id": import_id,
        "url": url,
        "status": "indexed",
        "analysis": analysis,
    }


@app.get("/api/v1/agents/tools")
def agent_tools(user=Depends(current_user)) -> list[dict[str, Any]]:
    names = [
        "search_knowledge",
        "read_document_chunk",
        "get_learning_stats",
        "get_mastery_profile",
        "create_study_plan",
        "create_task",
        "update_task",
        "generate_quiz",
        "submit_quiz_result",
        "get_knowledge_graph",
        "save_memory",
        "search_memory",
        "import_public_repository",
    ]
    writable = {
        "create_study_plan",
        "create_task",
        "update_task",
        "submit_quiz_result",
    }
    return [{"name": name, "write": name in writable} for name in names]


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8001")),
        reload=False,
    )
