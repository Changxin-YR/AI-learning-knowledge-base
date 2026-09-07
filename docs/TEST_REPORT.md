# Test Report

Executed: `python -m pytest -q` -> 4 passed; `flutter test` -> 1 passed; `flutter analyze` -> 0 issues. The passing API flow verifies demo login, KB creation, Markdown upload/index, citation answer, seven-day plan persistence, quiz submission and mastery update, plus 401 and repository URL security boundaries.

Android Studio Gradle check: `mobile/android/gradlew.bat :app:assembleDebug --no-daemon` -> BUILD SUCCESSFUL. The release APK was installed on `emulator-5554`; home data and AI citation rendering were verified from the running app.

OHOS target configuration is HarmonyOS `6.0.2(22)`. With a local DevEco debug signing profile, `hvigorw assembleHap --no-daemon` and `flutter build hap --release --target-platform ohos-x64 --dart-define=API_BASE_URL=http://10.0.2.2:8001` -> PASS. The signed HAP was installed on the `127.0.0.1:5555` x86_64 emulator; home data, AI input, deterministic answer, and `来源：notes.md` citation were verified. Machine-specific signing material is not committed. Physical devices and non-portrait/window-mode variants were not tested.
