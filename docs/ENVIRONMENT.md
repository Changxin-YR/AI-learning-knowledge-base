# Environment

- Windows 10+, PowerShell
- CPF-Flutter stable 3.27.4, Dart 3.6.2 (`C:\Users\27363\Desktop\max\flutter_flutter`)
- Android SDK 35.0.0, JDK 17
- OpenHarmony SDK API 24 / DevEco SDK, target/compatible SDK `6.0.2(22)`, hvigorw, ohpm 6.1.2.285
- Python 3.14.4, FastAPI 0.141.1, pytest 9.0.2
- Docker Desktop 4.88.1

`flutter doctor -v` passed Flutter, Android, and HarmonyOS toolchains. Android `emulator-5554` and HarmonyOS HDC target `127.0.0.1:5555` were connected and used for real emulator runs; no physical device was used.
