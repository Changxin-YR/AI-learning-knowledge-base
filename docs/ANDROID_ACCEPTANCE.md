# Android Acceptance

Android Studio is open on the project and the Android module builds successfully with `mobile/android/gradlew.bat :app:assembleDebug --no-daemon`.

The existing `Pixel_10_Pro_XL` AVD (`emulator-5554`, Android API 37) was used for a real release run. `flutter run -d emulator-5554 --release` rebuilt and installed `com.knowflow.knowflow_ai`; the process stayed alive, the home screen loaded backend data, and the AI tab returned an answer with citations. Evidence screenshots: `artifacts/android/real-device.png` and `artifacts/android/real-ai-response.png`.

The release artifact is `artifacts/android/knowflow-ai-release.apk`; its manifest contains `android.permission.INTERNET`.
