# Android Round 3 Fresh E2E

Device: `emulator-5554`, AVD `Pixel_10_Pro_XL`, Android 37.0 x86_64. APK was uninstalled, freshly built and installed from `artifacts/final-round3/android/knowflow-ai-release.apk`.

| ID | Result | Evidence / boundary |
|---|---|---|
| A01 Launch | PASS | Fresh install, `MainActivity` focused |
| A02 Demo Login | PASS | Demo session loaded after backend retry |
| A03 Home | PASS | `01-home.png` |
| A04 Create KB | PASS | Fresh UI create dialog and created `我的学习库` |
| A05 Open KB | PASS | KB document dialog shown |
| A06 File Picker TXT | FAIL | Android DocumentsUI opened white/blank; `mCurrentFocus=null` |
| A07 Upload TXT | BLOCKED | Depends on A06 picker |
| A08 File Picker MD | BLOCKED | Depends on A06 picker |
| A09 Upload MD | BLOCKED | Depends on A06 picker |
| A10 PDF | BLOCKED | Fresh picker failure |
| A11 DOCX | BLOCKED | Fresh picker failure |
| A12 PPTX | BLOCKED | Fresh picker failure |
| A13 Document List | PASS | KB dialog showed indexed document |
| A14 Delete Document | BLOCKED | Not attempted after picker failure |
| A15 Cancel File Picker | PASS | Android back returned to app |
| A16 AI KB Selector | PASS | `05-ai.png` |
| A17 Ask Question | PASS | Real AI screen submitted a query |
| A18 Citation | PASS | `06-citation.png` showed source card |
| A19 Citation document navigation | BLOCKED | Not independently exercised |
| A20 Second conversation turn | BLOCKED | Not independently exercised |
| A21 Same conversation_id | BLOCKED | Backend covered; mobile not independently exercised |
| A22 Create Learning Plan | BLOCKED | Screen reached, action not submitted this round |
| A23 Task List | PASS | `07-learning.png` / `08-task.png` |
| A24 Complete Task | BLOCKED | Not independently exercised |
| A25 Quiz | BLOCKED | Not independently exercised |
| A26 Quiz Submit | BLOCKED | Not independently exercised |
| A27 Mastery | BLOCKED | Not independently exercised |
| A28 Repository Import | BLOCKED | Not independently exercised |
| A29 Repository KB created | BLOCKED | Not independently exercised |
| A30 Ask repository question | BLOCKED | Not independently exercised |
| A31 Memory Save | BLOCKED | No mobile entry exercised |
| A32 Memory Search | BLOCKED | No mobile entry exercised |
| A33 Agent read operation | BLOCKED | No mobile entry exercised |
| A34 Agent write operation | BLOCKED | No mobile entry exercised |
| A35 Logout | BLOCKED | Not independently exercised |
| A36 Verify state cleaned | BLOCKED | Depends on A35 |
| A37 Relogin | BLOCKED | Depends on A35 |
| A38 Backend offline | PASS | API stopped; relaunch remained usable with empty fallback state |
| A39 Retry / recovery | PASS | Retry restored home data while API was running |
| A40 Dark Mode | BLOCKED | Not toggled independently |
| A41 Keyboard | PASS | Real Android IME visible during AI query |
| A42 Android Back | PASS | Back returned from picker/dialog to app |
| A43 Relaunch persistence | PASS | App relaunched and rendered home |

Failure log: `artifacts/final-round3/environment/android-file-picker-logcat.txt`.
