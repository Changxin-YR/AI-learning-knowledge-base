# KnowFlow AI Final Acceptance

The current round is documented in [ROUND6_FINAL_ACCEPTANCE.md](ROUND6_FINAL_ACCEPTANCE.md).

- Branch: `round6-ohos-emulator-final`
- Round 6 baseline: `e044e6fbefbe839c3873f76e7d95e67bf95f2d95`
- Verdict: `CONDITIONAL PASS`

Backend tests, Flutter analysis/tests, Qdrant health, Android stable-emulator
runtime acceptance, fresh Android APK, fresh HarmonyOS x64 HAP, and fresh
HarmonyOS ARM64 HAP pass. The HarmonyOS API22 x86_64 guest also boots, exposes
HDC, installs the HAP, launches the app, and passes H01-H05.

The remaining runtime gap is the API22 system `FilePickerUIExtAbility`, which
freezes inside `com.huawei.hmos.filemanager:sysPicker/filePicker` during the
standard app picker flow. System logs and a direct `OPEN_FILE` control are
summarized in `artifacts/final-round6/logs/picker-evidence-summary.txt`; this
prevents the upload-dependent HarmonyOS E2E steps from being completed on this
local image.

Physical devices, ARM64 runtime, production store signing, and real cloud
LLM/embedding providers are `OUT OF CURRENT SCOPE`.
