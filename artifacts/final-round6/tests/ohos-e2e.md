# HarmonyOS Emulator E2E

Guest: `22` / HarmonyOS 6.0.2 / x86_64
HDC target: `127.0.0.1:5555`

| ID | Result | Evidence | Note |
| --- | --- | --- | --- |
| H01 | PASS | `screen-ohos-app-launch.png` | Fresh x64 HAP launched |
| H02 | PASS | `ohos-fresh-launch.png` | Demo login state loaded |
| H03 | PASS | `ohos-fresh-launch.png` | Home visible |
| H04 | PASS | `ohos-h04-fixed.png` | Knowledge base created |
| H05 | PASS | `ohos-kb-round6-detail.png` | Knowledge base detail opened |
| H06 | FAIL | `picker-evidence-summary.txt` | System `FilePickerUIExtAbility` freezes |
| H07 | N/A | H06 prerequisite | TXT cannot be selected |
| H08 | N/A | H06 prerequisite | MD cannot be selected |
| H09 | N/A | H06 prerequisite | PDF cannot be selected |
| H10 | N/A | H06 prerequisite | DOCX cannot be selected |
| H11 | N/A | H06 prerequisite | PPTX cannot be selected |
| H12 | N/A | H06 prerequisite | Not reached after picker failure |
| H13 | N/A | H06 prerequisite | Not reached after picker failure |
| H14 | N/A | H06 prerequisite | Not reached after picker failure |
| H15 | N/A | H06 prerequisite | Not reached after picker failure |
| H16 | N/A | H06 prerequisite | Not reached after picker failure |
| H17 | N/A | H06 prerequisite | Not reached after picker failure |
| H18 | N/A | H06 prerequisite | Not reached after picker failure |
| H19 | N/A | H06 prerequisite | Not reached after picker failure |
| H20 | N/A | H06 prerequisite | Not reached after picker failure |
| H21 | N/A | H06 prerequisite | Not reached after picker failure |
| H22 | N/A | H06 prerequisite | Not reached after picker failure |
| H23 | N/A | H06 prerequisite | Not reached after picker failure |
| H24 | N/A | H06 prerequisite | Not reached after picker failure |
| H25 | N/A | H06 prerequisite | Not reached after picker failure |
| H26 | N/A | H06 prerequisite | Not reached after picker failure |
| H27 | N/A | H06 prerequisite | Not reached after picker failure |

H06 is an emulator-system failure, not an observed KnowFlow crash. The
overall HarmonyOS runtime verdict is therefore `CONDITIONAL PASS` while the
local API22 picker image remains unusable.
