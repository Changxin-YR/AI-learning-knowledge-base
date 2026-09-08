# KnowFlow AI Round 6 Final Acceptance

## 1. Baseline

- Branch: `round6-ohos-emulator-final`
- Baseline: `e044e6fbefbe839c3873f76e7d95e67bf95f2d95`
- Scope: Backend, Flutter, Android Emulator, HarmonyOS Emulator, Qdrant, x64 and ARM64 builds.

## 2. Was HarmonyOS Emulator successfully booted?

**YES**

Guest `22` (HarmonyOS 6.0.2, x86_64) booted and exposed HDC target
`127.0.0.1:5555`.

## 3. Regression Gates

- Backend: `20 passed`
- Flutter analyze: PASS
- Flutter tests: `5 passed`
- Qdrant health: PASS, HTTP 200
- Android stable-emulator acceptance: PASS from Round 5, unchanged in Round 6

Fresh Round 6 build outputs:

- Android APK: `artifacts/final-round6/android/knowflow-ai-round6-release.apk`
- HarmonyOS x64 HAP: `artifacts/final-round6/ohos/knowflow-ai-round6-x64.hap`
- HarmonyOS ARM64 HAP: `artifacts/final-round6/ohos/knowflow-ai-round6-arm64.hap`

Hashes and sizes are in `artifacts/final-round6/hashes/artifacts.json`.

## 4. HarmonyOS Runtime

Fresh x64 HAP installation and launch passed. H01-H05 passed:

- Launch and demo login state
- Home
- Create knowledge base
- Open knowledge base detail

The runtime then reached the standard system picker path. The API22 image's
`com.huawei.hmos.filemanager:sysPicker/filePicker` process does not complete
`FilePickerUIExtAbility`; logs show `LIFECYCLE_TIMEOUT` and repeated FFRT
30-second timeouts. The app remains on its selection state and no file can be
selected. The same guest reports no usable external file roots.

As a control, direct `OPEN_FILE` launch of the system `FilePickerAbility`
reaches a first frame. This separates the failure from KnowFlow launch,
packaging, or a missing system package. Evidence is summarized in
`artifacts/final-round6/logs/picker-evidence-summary.txt`.

The complete matrix is in `artifacts/final-round6/tests/ohos-e2e.md`:

- H01-H05: PASS
- H06: FAIL at the local system picker boundary
- H07-H27: N/A because file selection is unavailable

## 5. Build and Runtime Scope

- HarmonyOS x64 build: PASS
- HarmonyOS ARM64 build: PASS; package contains `libs/arm64-v8a/libapp.so` and `libflutter.so`
- ARM64 runtime: OUT OF CURRENT SCOPE
- Android physical device: OUT OF CURRENT SCOPE
- HarmonyOS physical device: OUT OF CURRENT SCOPE
- Production store signing: OUT OF CURRENT SCOPE
- Real cloud LLM and paid embedding provider: OUT OF CURRENT SCOPE

## 6. Final Verdict

**CONDITIONAL PASS**

All backend, Flutter, Android Emulator, Qdrant, build, and HarmonyOS guest
boot gates pass. The remaining in-scope gap is the API22 emulator's system
picker UI Extension, which prevents the HarmonyOS upload-dependent E2E from
being evaluated. No additional KnowFlow crash or business-logic defect was
observed in the evaluated HarmonyOS steps.
