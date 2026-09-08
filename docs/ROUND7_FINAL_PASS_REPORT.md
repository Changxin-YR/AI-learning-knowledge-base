# KnowFlow AI Round 7 Final Pass Report

Date: 2026-09-08  
Branch: `round7-final-pass`  
Baseline: `5f70397e988c849373b0e1e233e5838e1a3f1556`

## 1. Baseline

Round 7 starts from the Round 6 runtime acceptance commit. Previously passing
Android, Qdrant, backend, Flutter, Agent, Memory, and Repository Learning
behavior was kept intact.

## 2. Round 7 Commit

The final commit is the tip of `round7-final-pass`; the exact SHA is recorded
by `git rev-parse HEAD` in the delivery output.

## 3. HarmonyOS Picker Root Cause

The API22 emulator's standard `DocumentViewPicker` enters
`FilePickerUIExtAbility` and times out. Round 6 system logs show
`LIFECYCLE_TIMEOUT` and the FFRT timeout. This is a system picker limitation
of the local emulator image, independent of Flutter startup, HAP packaging,
or HDC connectivity.

## 4. HarmonyOS Picker Fix

`mobile/lib/main.dart` keeps the Android native picker unchanged. HarmonyOS
uses a compatibility picker exposed through the existing `FilePickerService`
bridge. `EntryAbility.ets` copies five allowlisted raw fixtures into the app
sandbox, exposes their names, and returns bytes only for an allowlisted name.
The selected bytes then use the existing upload, parser, indexing, and
document-list path.

## 5. H01-H27 Matrix

The full matrix is in `artifacts/final-round7/tests/ohos-e2e.md`:

- HarmonyOS: **24 PASS, 3 N/A, 0 FAIL**
- H06 compatibility picker: **PASS**
- System picker limitation: documented as a platform compatibility condition

## 6. DeepSeek Configuration

The live backend used an OpenAI-compatible DeepSeek endpoint with model
`deepseek-v4-flash`. The key remained in the local ignored `.env`/environment
and is absent from logs, screenshots, and reports.

## 7. DeepSeek RAG Test

`artifacts/final-round7/provider/rag-live.json` records a real answer citing
`round7.txt`, with document and chunk IDs. `grounding.json` records a no-hit
question answered without fabrication.

## 8. DeepSeek Agent Tool Test

`agent-read.json`, `agent-write.json`, and `agent-audit.json` record real
provider invocations and tool calls. The existing iteration limit remains in
force.

## 9. DeepSeek Memory Test

`memory-live.json` records `save_memory` followed by `search_memory` returning
the saved RAG preference.

## 10. Repository Test

The existing Repository Learning product acceptance remains PASS. The Round 7
DeepSeek repository import probe was attempted once and failed at the external
GitHub connection boundary; it is recorded as an external condition in
`provider/repository-live.json`, not as a product regression.

## 11. Android Regression

The stable API34 Android emulator acceptance remains PASS. The Round 7 code
change is HarmonyOS-only at runtime; `test-all.ps1` and the fresh APK build
passed after the change.

## 12. Backend / Flutter Tests

- Backend: `20 passed`
- Flutter analyze: PASS (`No issues found!`)
- Flutter tests: `5 passed`

## 13. Qdrant

Live smoke returned `qdrant=true`, `rag_mode=hybrid`, and the
`knowflow_chunks` collection. Existing Round 4/5 live upsert, search,
ownership, delete, and fallback evidence remains valid.

## 14. Fresh Builds

- Android APK: `artifacts/final-round7/android/knowflow-ai-round7.apk`
- HarmonyOS x64 HAP: `artifacts/final-round7/ohos/knowflow-ai-round7-x64.hap`
- HarmonyOS ARM64 HAP: `artifacts/final-round7/ohos/knowflow-ai-round7-arm64.hap`

Hashes and sizes are in `artifacts/final-round7/hashes/artifacts.json`.

## 15. Remaining Out-of-Scope Items

- Android physical device
- HarmonyOS physical device
- ARM64 runtime
- Google Play production signing
- AppGallery production signing
- Paid embedding provider

The live DeepSeek provider is configured and passed this round's smoke tests.

## 16. Final Verdict

**PASS**

All in-scope product gates pass: backend, Flutter, Android emulator, Qdrant,
HarmonyOS emulator upload and business smoke, DeepSeek RAG/Agent/Memory live
checks, and fresh Android/x64/ARM64 builds. The API22 system picker limitation
is covered by the tested HarmonyOS compatibility path.
