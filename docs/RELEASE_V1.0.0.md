# KnowFlow AI v1.0.0

## Version

- Version: `v1.0.0`
- Final main SHA: `c5e6f747fc1fec66821daee23fb752ad28f152ce`
- Release date: `2026-09-08`
- Pull request: [#2](https://github.com/Changxin-YR/AI-learning-knowledge-base/pull/2)
- Acceptance verdict: `PASS`

## Acceptance

- Backend: 20 passed
- Flutter analyze: PASS
- Flutter tests: 5 passed
- Android API34 Emulator: PASS
- Android File Picker and TXT/MD/PDF/DOCX/PPTX upload: PASS
- HarmonyOS Emulator: PASS
- HarmonyOS H01-H27: 24 PASS / 3 N/A / 0 FAIL
- HarmonyOS Compatibility Picker: PASS
- Qdrant Live: PASS
- DeepSeek Provider, Agent Read/Write, and Memory: PASS
- Learning Plan, Task, Quiz, and Mastery: PASS
- Logout / Relogin and Offline / Recovery: PASS

## Build Artifacts

| Artifact | Path | SHA256 |
| --- | --- | --- |
| Android APK | `artifacts/final-round7/android/knowflow-ai-round7.apk` | `B10A89A14A9E8A5C31E3509B07802F02677B7196BCEBFCCCF1E4BF249DBE10C9` |
| HarmonyOS x64 HAP | `artifacts/final-round7/ohos/knowflow-ai-round7-x64.hap` | `1FFBB9EA923448E64912E26B7C17D2CA216556BCFE265B8E05648ACF52CC8F28` |
| HarmonyOS ARM64 HAP | `artifacts/final-round7/ohos/knowflow-ai-round7-arm64.hap` | `0D68F33A231B976BA1118C4813BD9EEBF90412EFAA536189F4A69DAD10A44354` |

The complete acceptance evidence is in `docs/ROUND7_FINAL_PASS_REPORT.md` and `artifacts/final-round7/`.

## Out Of Scope

- Physical Android device validation
- Physical HarmonyOS device validation
- ARM64 physical runtime
- Google Play production signing
- AppGallery production signing
- Paid neural embedding provider

## Version Policy

`main` at `v1.0.0` is the frozen baseline. Future work must start from a new branch.
