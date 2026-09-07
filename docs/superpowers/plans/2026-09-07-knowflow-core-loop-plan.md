# KnowFlow Core Loop Implementation Plan

> **For agentic workers:** Execute inline in this session; keep each task independently testable.

**Goal:** Close the verified correctness gaps in the backend, Flutter core loop, and build gates.

**Architecture:** Preserve the existing FastAPI/SQLite API and single-file Flutter shell. Add focused helpers and state only where the current flow already routes through them.

**Tech Stack:** FastAPI, SQLite, pytest, Flutter Material 3, PowerShell.

**Spec:** `docs/superpowers/specs/2026-09-07-knowflow-core-loop-design.md`

**Global Constraints:** No new platform plugin in this batch; no claims for unimplemented Agent/Memory/Vector RAG; tests must fail before production changes.

---

### Task 1: Backend correctness and parsers

**Files:** `server/app/main.py`, `server/requirements.txt`, `server/tests/test_api.py`

- [x] Add failing tests for isolated DB configuration, PDF/DOCX/PPTX extraction, invalid UTF-8, conversation ownership, and quiz answer privacy.
- [x] Run the focused tests and confirm the expected failures.
- [x] Implement real parsers, ownership validation, and public quiz question filtering.
- [x] Run the backend suite.

### Task 2: Config and build gates

**Files:** `.env.example`, `scripts/start-backend.ps1`, `scripts/test-all.ps1`, `scripts/build-all.ps1`, `README.md`

- [x] Align environment names and load project `.env` in the backend launcher.
- [x] Stop test/build scripts on each failed native command and remove stale release outputs before building.
- [x] Describe only implemented capabilities in README.

### Task 3: Flutter core loop

**Files:** `mobile/lib/main.dart`, `mobile/test/widget_test.dart`

- [x] Add failing widget coverage for AI KB selection and learning controls.
- [x] Move controllers to state and dispose them; retain conversation id and selected KB.
- [x] Load/update tasks and mastery, add quiz start/submit UI, refresh after mutations, and show errors.
- [x] Run Flutter analyze/tests and a fresh Android build.
