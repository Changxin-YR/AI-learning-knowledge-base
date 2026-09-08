# Round 6 HarmonyOS Emulator Environment

Date: 2026-09-08 (Asia/Shanghai)
Branch: `round6-ohos-emulator-final`
Baseline: `e044e6fbefbe839c3873f76e7d95e67bf95f2d95`

## Boot

Was HarmonyOS Emulator successfully booted? **YES**

| Check | Result | Evidence |
| --- | --- | --- |
| DevEco Studio | PASS | `C:\Program Files\Huawei\DevEco Studio` |
| Emulator | PASS | Emulator `6.1.1.300` |
| SDK/image | PASS | API22 HarmonyOS 6.0.2 x86_64 phone image |
| Guest | PASS | Guest `22`, API22, x86_64, 2048 MB |
| HDC | PASS | `3.2.0d` |
| HDC target | PASS | `127.0.0.1:5555` |
| Virtualization | PASS | WHPX/hypervisor operational in environment evidence |
| Qdrant health | PASS | `artifacts/final-round6/qdrant-health.json`, HTTP 200 |

Boot and HDC evidence is in `artifacts/final-round6/logs/screen-ohos-booted.png`,
`screen-ohos-app-launch.png`, and the existing launcher logs.

## App Runtime

The fresh x64 HAP installed successfully and launched as
`com.knowflow.knowflow_ai/EntryAbility`. H01-H05 were executed:

- Launch, demo login state, and Home loaded.
- Knowledge base creation succeeded after the scoped focus-dismiss fix.
- `我的学习库 Round6` opened and displayed its indexed document.

Evidence: `ohos-fresh-launch.png`, `ohos-h04-fixed.png`, and
`ohos-kb-round6-detail.png`.

## Picker Boundary

The standard app path reaches the system `FilePickerUIExtAbility`, but the API22
system image does not complete its picker session. The app remains on its
selection state and no picker window becomes foreground.

Observed system evidence:

- `com.huawei.hmos.filemanager:sysPicker/filePicker`
- `FilePickerUIExtAbility load timeout`
- repeated FFRT `timeout:30s` records
- `picker-evidence-summary.txt` reports `Reason:LIFECYCLE_TIMEOUT`

As a control, directly starting the system `FilePickerAbility` with
`OPEN_FILE` reaches a first frame. This isolates the failure to the API22
system UI-extension picker path used by `DocumentViewPicker`, rather than an
app crash or a missing package. The concise comparison is in
`artifacts/final-round6/logs/picker-evidence-summary.txt`.

The guest also reports no usable external file roots (`External file count: 0`,
`getRoots failed`), so file selection and upload cannot be completed on this
image.

## Classification

HarmonyOS guest boot and app launch are PASS. HarmonyOS full E2E is not
complete because the system picker fails inside the local API22 image. This is
reported as a local emulator environment condition. The retained app
implementation uses the standard HarmonyOS `DocumentViewPicker` API.
