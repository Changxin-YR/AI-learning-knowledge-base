# OpenHarmony Acceptance

DevEco Studio is installed and the project product is configured for HarmonyOS `6.0.2(22)`. The host SDK package is HarmonyOS 6.1.1/API 24 and is used only as the toolchain; the target/compatible SDK remains API 22.

With the DevEco SDK path in `mobile/ohos/local.properties` and a local DevEco debug signing profile, `hvigorw assembleHap --no-daemon` completes successfully. The signed Flutter build command `flutter build hap --release --target-platform ohos-x64 --dart-define=API_BASE_URL=http://10.0.2.2:8001` also completes and produces `artifacts/ohos/knowflow-ai-release.hap` for the x86_64 emulator. The repository keeps the API 22 product configuration but does not commit machine-specific certificates or passwords; configure signing locally before rebuilding a signed HAP.

The HAP was installed and launched on the HarmonyOS `6.0.2(22)` emulator at HDC target `127.0.0.1:5555`. Runtime checks passed: the home screen reached the backend and showed `已索引 10 份文档`; the AI page accepted `RAG`, returned an answer, and displayed the citation `来源：notes.md`. The rebuilt-artifact evidence is in `artifacts/ohos/real-online-home-rebuilt.png`, `artifacts/ohos/real-online-ai-rebuilt.png`, `artifacts/ohos/real-online-ai-rebuilt-input.xml`, `artifacts/ohos/real-online-ai-response-rebuilt.png` and the corresponding XML dumps.

This is emulator-only evidence. Physical-device testing, real LLM provider behavior, landscape/split/floating windows, dark mode, and AppGallery performance thresholds remain `unverified`.
