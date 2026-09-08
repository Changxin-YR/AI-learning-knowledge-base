# HarmonyOS Emulator Environment

Round 5 verification date: 2026-09-08

| Check | Result | Evidence |
|---|---|---|
| DevEco Studio | PASS | `C:\Program Files\Huawei\DevEco Studio\bin\devecostudio64.exe` exists and DevEco process/window was observed. |
| SDK API 24 | PASS | `D:\AppData\Local\Huawei\Sdk\system-image\HarmonyOS-6.1.1\phone_all_x86` exists. |
| Phone profile | PASS | `Emulator.exe -list -details` reports `PHEMU-FD00` / `Pura 90` / `phone` / `x86_64`. |
| API 22 phone instance | PASS | `deployed\22\config.ini` exists, `hw.ramSize=2048`, `hw.cpu.arch=x86_64`. |
| API 24 phone instance | PASS | `deployed\Pura 90\config.ini` exists, `hw.ramSize=4096`, `hw.cpu.arch=x86_64`. |
| Emulator license | PASS | `Emulator.exe -license accept` returned `All licenses have been automatically accepted.` |
| Guest creation | BLOCKED | Existing guests were used; no new guest was required. |
| Guest boot API 22 | BLOCKED | Start attempted with `-start 22`; log ends at `Trace pipe is not prepared`; no `qemu` process or boot-complete event. |
| Guest boot API 24 | BLOCKED | Start attempted with `-start Pura 90`; log ends at `Trace pipe is not prepared`; no `qemu` process or boot-complete event. |
| HDC | PASS | `hdc 3.2.0d` exists. |
| HDC target | BLOCKED | `hdc list targets -v` reports only UART entries; no online TCP guest target. |
| Virtualization | PASS | Host virtualization capability was queried and recorded in `ohos-environment.json`. |

Raw evidence is in `ohos-hdc-version.txt`, `ohos-hdc-targets.txt`, `ohos-emulator-list.json`, both instance configs, and `artifacts/final-round5/logs/ohos-api22-start-tail.log` / `ohos-api24-start-tail.log`.

Conclusion: HarmonyOS x86_64 runtime could not be reached in this host session. This is an emulator environment `BLOCKED` result after checking DevEco, SDK image, phone profile, license, two existing guests, and both CLI boot paths. No HarmonyOS application runtime claim is made.
