from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def test_rag_eval_accepts_repository_relative_dataset_path(tmp_path: Path) -> None:
    output = tmp_path / "holdout.json"
    env = os.environ.copy()
    env.update(
        {
            "APP_ENV": "test",
            "SQLITE_PATH": str(tmp_path / "knowflow-rag-eval.db"),
            "JWT_SECRET": "test-only-secret-that-is-never-used-in-production",
            "EMBEDDING_PROVIDER": "local",
            "VECTOR_SCORE_THRESHOLD": "0.35",
        }
    )

    completed = subprocess.run(
        [
            sys.executable,
            "scripts/rag-eval.py",
            "--dataset",
            "server/tests/rag_eval/holdout_dataset.json",
            "--output",
            str(output),
        ],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )

    assert completed.returncode == 0, completed.stderr
    report = json.loads(output.read_text(encoding="utf-8"))
    assert report["dataset"] == str(Path("server/tests/rag_eval/holdout_dataset.json"))
    assert report["case_count"] > 0
    assert "HybridUngated" in report
    assert "Hybrid" in report
