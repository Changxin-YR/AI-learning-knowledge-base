# KnowFlow AI Round 5 Acceptance Report

Date: 2026-09-08
Baseline: `7e081a16813b8e01c0f71806854d49a71eb1c061`
Branch: `round5-runtime-acceptance`
Round 5 commit: `b1b431690378cc27797e34b5ba61e6b5e7190bbf`

## 1. Baseline

Round 5 starts from the submitted Round 4 commit above. No product feature or RAG/Agent/Memory/Repository Learning redesign was made in this round.

## 2. Round 5 Commit

This report and its evidence are included in the Round 5 commit above.

## 3. Environment

Android acceptance used the stable `KnowFlow_API34` AVD: Android 14/API 34, Google APIs, x86_64, `sdk_gphone64_x86_64`, `emulator-5554`, `boot_completed=1`. ADB was invoked from `C:\Users\27363\Desktop\max\android-sdk\platform-tools\adb.exe`. API34 DocumentsUI opened with a populated accessibility tree. API37 was not used as the acceptance device because its system DocumentsUI image is known to crash.

Qdrant was live at `http://127.0.0.1:6333`; the API reported `qdrant=true` and `rag_mode=hybrid` at `/api/v1/ready`.

HarmonyOS DevEco Studio, API22/API24 x86_64 phone images, phone profiles, emulator licenses, and `hdc 3.2.0d` were present. Both existing phone guests were attempted through the CLI. Neither produced a `qemu` process, boot-complete log, or online HDC target. Raw evidence is in `artifacts/final-round5/environment/` and `artifacts/final-round5/logs/`.

## 4. Fixed Issues

- Android acceptance no longer depends on PATH: the known ADB path was used directly.
- Stable API34 DocumentsUI and file uploads were exercised with a fresh APK.
- Qdrant live upsert/search/ownership/delete/fallback were re-executed against the real server.
- Fresh x64 and ARM64 HAPs were rebuilt after clearing a transient generated-cache rename failure.
- Round 4 report references are corrected to the actual Round 4 commit.

## 5. Android File Picker

`ANDROID FILE PICKER = PASS` on API34. The native picker opened and the app selected and indexed all five test files: TXT, MD, PDF, DOCX, and PPTX. App evidence includes `artifacts/final-round5/environment/r5aftertxt.xml`, `r5aftermd2.xml`, `r5afterpdf.xml`, `r5afterdocx.xml`, `r5afterpptx.xml` and screenshots `03-picker.png`, `04-txt.png`, `04-md.png`, `05-pdf.png`, `06-docx.png`, `07-pptx.png`.

Cancel/back picker handling passed. The API37 DocumentsUI crash is recorded as an AVD/system-image compatibility issue and is outside the stable acceptance device.

## 6. Android Full E2E

The following matrix is based on fresh APK execution on `KnowFlow_API34`. `N/A` means the current mobile product has no corresponding UI entry; those capabilities were verified by the live API smoke instead.

| ID | Result | ID | Result | ID | Result |
|---|---|---|---|---|---|
| A01 Launch | PASS | A18 Citation | PASS | A35 Agent Read Tool | N/A |
| A02 Login | PASS | A19 Open Citation | PASS | A36 Agent Write Tool | N/A |
| A03 Home | PASS | A20 Second Turn | PASS | A37 Agent Audit | N/A |
| A04 Create KB | PASS | A21 Conversation Reuse | PASS | A38 Logout | PASS |
| A05 Open KB | PASS | A22 Create Plan | PASS | A39 State Cleared | PASS |
| A06 TXT Picker | PASS | A23 Task List | PASS | A40 Login Again | PASS |
| A07 TXT Upload | PASS | A24 Complete Task | PASS | A41 Dark Mode | PASS |
| A08 MD Picker | PASS | A25 Quiz | PASS | A42 Keyboard | PASS |
| A09 MD Upload | PASS | A26 Quiz Submit | PASS | A43 Android Back | PASS |
| A10 PDF Upload | PASS | A27 Mastery | PASS | A44 App Restart | PASS |
| A11 DOCX Upload | PASS | A28 Repository Import | N/A | A45 Persistence | PASS |
| A12 PPTX Upload | PASS | A29 Repository Analysis | N/A | A46 Backend Offline | PASS |
| A13 Documents List | PASS | A30 Repository KB | N/A | A47 Recovery | PASS |
| A14 Delete Document | PASS | A31 Repository AI Query | N/A | A48 Qdrant Available | PASS |
| A15 Cancel Picker | PASS | A32 Memory Create | N/A | A49 Qdrant Fallback | PASS |
| A16 AI KB Selector | PASS | A33 Memory Search | N/A |  |  |
| A17 AI Ask | PASS | A34 Memory Delete | N/A |  |  |

Result: `39/49 PASS`, `10/49 N/A`, `0 FAIL`.

## 7. Qdrant Live

`QDRANT LIVE = PASS`. The real server returned health and the `knowflow_chunks` collection. A fresh upload returned `vector_indexed=true`; the live vector query returned a point with score `1.0` and document/chunk payload IDs. The cross-user query returned no User B point (`user_b_point_returned=false`). Document deletion left zero points for the document, and KB deletion completed. After stopping Qdrant, the API remained available and returned lexical fallback citations; Qdrant was restarted and `/api/v1/ready` returned `qdrant=true` again.

Evidence: `artifacts/final-round5/qdrant/health.txt`, `collections.json`, `points-after-upload.json`, `vector-query.json`, `ownership-test.json`, `points-after-delete.json`, and `fallback-test.txt`.

## 8. Vector Evaluation

- Qdrant Vector Infrastructure: `PASS`
- Vector Retrieval Functional: `PASS`
- Ownership Filter: `PASS`
- Delete Behavior: `PASS`
- Hybrid Retrieval: `PASS` through existing regression tests and live API smoke
- Neural Semantic Embedding Quality: `UNVERIFIED`; this round retains the local deterministic provider and does not claim neural quality.

## 9. HarmonyOS Guest

`HARMONYOS EMULATOR ENVIRONMENT = BLOCKED`. DevEco, SDK images, phone profiles, licenses, API22/API24 instances, virtualization capability, and HDC were checked. Starting both existing x86_64 phone guests produced `Trace pipe is not prepared` and no `qemu` child, boot-complete event, or online HDC target. This is an emulator environment result after the required checks, not a HarmonyOS product-code failure.

## 10. HarmonyOS E2E

H01-H27 are `BLOCKED` because no online HarmonyOS emulator target was available for HAP installation. No HarmonyOS runtime PASS claim is made. The exact launch attempts and raw logs are recorded under `artifacts/final-round5/logs/`.

## 11. ARM64

`HarmonyOS ARM64 Build = PASS`. The fresh HAP contains `libs/arm64-v8a/libapp.so` and `libs/arm64-v8a/libflutter.so`. `ARM64 Physical Runtime = OUT OF CURRENT SCOPE`.

## 12. Automated Tests

`artifacts/final-round5/tests/test-all.log` records:

- Backend: `20 passed`
- Flutter analyze: `No issues found!`
- Flutter tests: `All tests passed!` (`5` tests)

The live API smoke and agent smoke are in `live-api-smoke.json` and `agent-live-smoke.json`. The earlier invalid `memory_type=agent` probe was corrected to the supported `user_note` type; the final agent calls completed.

## 13. Build Artifacts

| Artifact | Size | SHA256 | Signing |
|---|---:|---|---|
| `artifacts/final-round5/android/knowflow-ai-round5.apk` | 21,323,465 | `76E97825B5303A89391B0CDF99562D619D32C27BE1B03F3F133317B568542DB3` | local test-release |
| `artifacts/final-round5/ohos/knowflow-ai-round5-x64.hap` | 20,618,183 | `B4BFD7FB38DB185F474DDBF65A0CCBDD867355984C83EFC9AD1D60039071E5A3` | local/debug profile |
| `artifacts/final-round5/ohos/knowflow-ai-round5-arm64.hap` | 19,391,897 | `FF4C9FCB9F3D5999391E904F8003EC1E921D6B1CAF24DA2BBCD9340C91DDC2DD` | local/debug profile |

Full metadata is in `artifacts/final-round5/hashes/artifacts.json`.

## 14. External Conditions

- Android physical device: `OUT OF CURRENT SCOPE`
- HarmonyOS physical device: `OUT OF CURRENT SCOPE`
- ARM64 physical runtime: `OUT OF CURRENT SCOPE`
- Google Play production signing: `OUT OF CURRENT SCOPE`
- AppGallery production signing: `OUT OF CURRENT SCOPE`
- Real cloud LLM / paid embedding provider: `OUT OF CURRENT SCOPE`

## 15. Remaining Issues

The only remaining required-range gap is the local HarmonyOS emulator environment: the existing x86_64 phone guests do not reach boot/HDC because the emulator stops at `Trace pipe is not prepared`. No stable Android product bug, Qdrant live bug, backend test failure, Flutter analysis failure, or build failure remains.

## 16. Final Verdict

`CONDITIONAL PASS`

Android stable emulator full E2E, Android file picker, Qdrant live acceptance, backend/Flutter regression, fresh Android APK, fresh HarmonyOS x64 HAP, and fresh ARM64 HAP all pass. Conditional status is solely due to the verified local HarmonyOS emulator environment block; physical devices, production store signing, and real cloud models are outside this round's scope.
