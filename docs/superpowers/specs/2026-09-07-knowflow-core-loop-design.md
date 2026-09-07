# KnowFlow Core Loop Design

**Goal:** Make the existing backend and Flutter shell honest and usable for the core knowledge-to-learning loop.

**Scope:** Isolate test data, parse PDF/DOCX/PPTX, enforce conversation ownership, hide quiz answers until submission, fix build/config gates, and connect Flutter conversation, KB selection, learning tasks, quiz, mastery, and error states.

**Out of scope:** File-picker plugins, KB detail screens, real provider/agent/memory/vector search, repository cloning, device signing, and device E2E. Those remain separate follow-up work because they need platform or external-service validation.

**Design:** Keep the current FastAPI + SQLite and single-file Flutter structure. Add only the smallest shared helpers required by existing flows. The API remains deterministic; quiz answers stay server-side. Flutter stores the returned conversation id and selected KB in `_HomeShellState`, refreshes tasks/stats/mastery after mutations, and reports failures through existing Material snackbars/error state.

**Acceptance:** Backend regression tests cover parser output, invalid document input, conversation ownership, and quiz response shape. Flutter tests cover the AI KB selector and learning controls. `python -m pytest -q`, `flutter analyze`, and `flutter test` pass; fresh Android build passes; HarmonyOS build status is reported honestly when signing is unavailable.
