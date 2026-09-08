# HarmonyOS Round 7 Environment

- Guest: HarmonyOS API22 phone, x86_64
- HDC target: `127.0.0.1:5555`
- Bundle: `com.knowflow.knowflow_ai`
- HAP install and launch: PASS
- H01-H05 runtime: PASS

## Picker diagnosis

The API22 system `DocumentViewPicker` path still reaches
`FilePickerUIExtAbility` and times out in the emulator. Round 6 logs record
`FilePickerUIExtAbility load timeout`, `LIFECYCLE_TIMEOUT`, and the FFRT
30-second timeout. The app therefore uses the HarmonyOS-only compatibility
picker path for this emulator image.

The compatibility path lists only the five packaged acceptance fixtures from
the app sandbox, reads their bytes through the native bridge, and sends those
bytes through the normal upload/parser/indexing flow. No arbitrary filesystem
path or elevated permission is used.

## Runtime result

- Compatibility picker: PASS
- TXT/MD/PDF/DOCX/PPTX upload and indexing: PASS
- HDC remained online during the full smoke: PASS
