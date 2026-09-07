# Second-round acceptance

| ID | Function | Backend | Android | HarmonyOS | Automated | Result |
| --- | --- | --- | --- | --- | --- | --- |
| AUTH | Auth and ownership | PASS | PASS | UNVERIFIED | PASS | PASS |
| KB | Knowledge bases and documents | PASS | PASS | UNVERIFIED | PASS | PASS |
| PICKER | Cross-platform picker | PASS | PASS | BLOCKED | PASS | BLOCKED |
| DOCS | PDF/DOCX/PPTX parsing | PASS | PASS | UNVERIFIED | PASS | PASS |
| CHAT | Citation chat and conversation reuse | PASS | PASS | UNVERIFIED | PASS | PASS |
| LEARNING | Plan, tasks, quiz, mastery | PASS | UNVERIFIED | UNVERIFIED | PASS | UNVERIFIED |
| REPOSITORY | Safe static repository learning | PASS | UNVERIFIED | UNVERIFIED | PASS | PASS |
| RAG | Deterministic hybrid lexical retrieval | PASS | UNVERIFIED | UNVERIFIED | PASS | PASS |
| VECTOR | Qdrant/embedding retrieval | UNVERIFIED | N/A | N/A | N/A | UNVERIFIED |
| RERANK | Model reranker | N/A | N/A | N/A | N/A | N/A |
| AGENT | Structured tool execution and audit | PASS | UNVERIFIED | UNVERIFIED | PASS | PASS |
| MEMORY | Owned memory CRUD and search | PASS | UNVERIFIED | UNVERIFIED | PASS | PASS |
| LOGOUT | Client logout state cleanup | PASS | PASS | UNVERIFIED | PASS | UNVERIFIED |
| DARK | Dark mode | PASS | UNVERIFIED | UNVERIFIED | PASS | UNVERIFIED |
| SIGNING | Android local release signing | PASS | PASS | N/A | PASS | PASS |

## Evidence

- Android simulator: `emulator-5554`, fresh APK install and TXT/MD/PDF/DOCX/PPTX upload evidence under `artifacts/android/`.
- HarmonyOS: fresh x86_64 locally signed HAP build passed. The available `hdc` targets are `COM3/COM4 UART Ready`; no guest simulator target was created, so runtime and picker checks are `BLOCKED/UNVERIFIED`.
- Local model/embedding Provider keys were not available. The API therefore retains deterministic retrieval and requires explicit structured Agent calls when no Provider is configured.

## Remaining issues

| Issue-ID | Severity | Phenomenon | Root cause | Fix status | Android | HarmonyOS | Automated | Blocker |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ENV-OHOS-001 | P0 | No HarmonyOS guest target for runtime E2E | DevEco shell starts but `hdc` exposes only UART targets | HAP build fixed; runtime requires an emulator guest | N/A | BLOCKED | N/A | Yes |
| EXT-AI-001 | P1 | No live provider/embedding acceptance | No `OPENAI_*` or embedding key in environment | Provider loop and lexical fallback implemented; live provider remains unverified | UNVERIFIED | UNVERIFIED | PASS (mocked loop) | Yes |
| ENV-ANDROID-001 | P1 | Final signed APK UI rerun unavailable in current shell | `adb.exe` is absent from current SDK installation | Earlier Android simulator upload evidence retained | UNVERIFIED | N/A | PASS | Yes |
| P1-RAG-001 | P1 | Qdrant/vector retrieval not wired | Current deployment has no vector dependency/provider | Deterministic hybrid lexical baseline documented; add Qdrant when provider is provisioned | UNVERIFIED | UNVERIFIED | PASS (baseline) | No |
