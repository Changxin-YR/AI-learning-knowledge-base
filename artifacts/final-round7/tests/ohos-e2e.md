# HarmonyOS Round 7 E2E

| ID | Result | Evidence / note |
|---|---|---|
| H01 Launch | PASS | `17-relogin.jpeg`, HDC launch |
| H02 Login | PASS | Fresh launch and demo login |
| H03 Home | PASS | `17-relogin.jpeg` |
| H04 Create KB | PASS | Existing Round 7 KB runtime evidence |
| H05 KB Detail | PASS | Existing Round 7 KB detail evidence |
| H06 File Picker | PASS | `03-picker.png`, compatibility picker |
| H07 TXT | PASS | `04-txt.png`, indexed document evidence |
| H08 MD | PASS | `05-md.png`, indexed document evidence |
| H09 PDF | PASS | `06-pdf.png`, indexed document evidence |
| H10 DOCX | PASS | `07-docx.png`, indexed document evidence |
| H11 PPTX | PASS | `08-pptx.png`, indexed document evidence |
| H12 Document Delete | PASS | `12-delete.png`, delete evidence |
| H13 AI KB Selector | PASS | `08-ai-followup.json` |
| H14 AI Ask | PASS | `08-ai2.jpeg` |
| H15 Citation | PASS | `08-ai2.jpeg`, source `round7.txt` |
| H16 Conversation | PASS | `08-ai-followup.jpeg`, two-turn transcript |
| H17 Plan | PASS | `10-learning2.jpeg`, seven tasks created |
| H18 Task | PASS | `11-task2.jpeg`, completed checkbox |
| H19 Quiz | PASS | `12-quiz-result.jpeg`, 100% result |
| H20 Mastery | PASS | `12-quiz-result.jpeg`, mastery updated |
| H21 Repository | N/A | No independent repository UI; live API evidence retained |
| H22 Memory | N/A | No independent memory UI; DeepSeek live evidence retained |
| H23 Agent | N/A | AI page is the product entry; provider tool evidence retained |
| H24 Logout | PASS | `17-home-after-logout.json` |
| H25 Dark Mode | N/A | Profile exposes `跟随系统`; no in-app theme toggle |
| H26 Back | PASS | Keyboard dismissal and navigation back evidence |
| H27 Offline / Recovery | PASS | `17-offline.jpeg`, `18-recovery.jpeg` |

Result: **24 PASS, 3 N/A, 0 FAIL**.
