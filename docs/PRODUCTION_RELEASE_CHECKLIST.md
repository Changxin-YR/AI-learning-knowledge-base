# Production Release Checklist

This document separates the already-passed simulator engineering acceptance from future production-release work. Do not mark an item PASS without real device/account evidence.

## 1. Scope

`v1.0.0` already proves:

- Android API34 Emulator runtime
- HarmonyOS Emulator runtime
- Android APK build
- HarmonyOS x64 HAP build
- HarmonyOS ARM64 HAP build
- Qdrant live
- DeepSeek provider / Agent / Memory

The following remain separate production gates.

## 2. Android Physical Device

Use at least one supported physical Android device before store submission.

Checklist:

- [ ] Fresh uninstall/install from release artifact
- [ ] App launch and authentication
- [ ] TXT / MD / PDF / DOCX / PPTX picker and upload
- [ ] KB list/detail/delete
- [ ] AI query / citation / second turn
- [ ] Plan / Task / Quiz / Mastery
- [ ] Agent read/write
- [ ] Memory save/search/delete
- [ ] Repository Learning on a reachable public repository
- [ ] Offline/error/recovery
- [ ] Dark mode
- [ ] Keyboard / back gesture
- [ ] App restart/persistence
- [ ] Network switching (Wi-Fi/mobile if available)
- [ ] Screenshot evidence stored outside secrets

Record:

```text
Device model:
Android version:
ABI:
App version:
Commit SHA:
Artifact SHA256:
Result:
```

## 3. Android Production Signing

The current local test-release keystore is not a Google Play production identity.

Before production:

- [ ] Create/select the production upload/signing key according to the chosen store process
- [ ] Keep keystore outside Git
- [ ] Keep passwords outside Git
- [ ] Keep `key.properties` outside Git
- [ ] Verify `.gitignore`
- [ ] Build a fresh production-signed artifact
- [ ] Inspect signing certificate identity
- [ ] Record SHA256
- [ ] Install the signed artifact on a physical device
- [ ] Re-run critical smoke flow
- [ ] Back up signing material securely

Never commit:

```text
*.jks
*.keystore
key.properties
storePassword
keyPassword
private keys
```

## 4. HarmonyOS Physical Device

ARM64 build success is not the same as ARM64 runtime validation.

Checklist:

- [ ] Connect an eligible HarmonyOS/OpenHarmony ARM64 device
- [ ] `hdc` sees an online target
- [ ] Fresh install the ARM64 HAP
- [ ] Launch the expected bundle/ability
- [ ] Run real file picker/compatibility picker
- [ ] Upload TXT / MD / PDF / DOCX / PPTX
- [ ] Verify AI/RAG/citation
- [ ] Verify learning flow
- [ ] Verify Agent/Memory
- [ ] Verify back/keyboard/dark mode
- [ ] Verify offline/recovery
- [ ] Capture runtime logs and screenshots

Record:

```text
Device model:
HarmonyOS/OpenHarmony version:
API level:
ABI:
App version:
Commit SHA:
Artifact SHA256:
Result:
```

## 5. HarmonyOS Production Signing

Current local/debug profile signing is suitable for development acceptance, not AppGallery production release.

Before production:

- [ ] Use the real developer account
- [ ] Obtain the required production certificate/profile for the selected distribution route
- [ ] Store signing files outside Git
- [ ] Keep signing passwords/tokens outside source control
- [ ] Build a fresh production-signed HAP
- [ ] Verify bundle identity and signing profile
- [ ] Install on a physical device
- [ ] Re-run critical smoke flow
- [ ] Record artifact SHA256

Never commit:

```text
*.p12
*.pem
*.key
production profile secrets
.ohos-signing.local.json
```

## 6. Cloud LLM / Embedding Production Configuration

Before deploying a cloud provider:

- [ ] Secrets are server-side only
- [ ] API key is injected through environment/secret manager
- [ ] No Flutter source contains provider secrets
- [ ] Request timeout is configured
- [ ] Agent max tool iterations is bounded
- [ ] Provider failure has a controlled error/fallback path
- [ ] Cost/rate limits are understood
- [ ] Logs do not print Authorization headers
- [ ] RAG grounding is tested against an answerable and no-answer set

For neural embeddings:

- [ ] Run `python scripts/rag-eval.py`
- [ ] Compare against deterministic baseline
- [ ] Record Recall@3 / Recall@5 / MRR
- [ ] Record Citation Hit Rate
- [ ] Record No-answer false citation rate
- [ ] Tune threshold using the evaluation set
- [ ] Use a separate Qdrant collection if vector dimensions change

## 7. Git / CI Gate

Before any future production release:

- [ ] Work happens on a feature/release branch, not directly on frozen tag
- [ ] GitHub Actions CI is green
- [ ] Backend pytest is green
- [ ] Flutter analyze is green
- [ ] Flutter tests are green
- [ ] Secret scan/manual credential review is clean
- [ ] Release notes match actual capabilities
- [ ] Artifact hashes are generated after the final build
- [ ] Tag points to the intended final `main` commit

## 8. Verdict Rules

Use only:

- `PASS`: real evidence exists for the required environment.
- `FAIL`: feature/environment was available and product behavior failed.
- `BLOCKED`: required test environment could not be made available after documented attempts.
- `UNVERIFIED`: implementation exists but the requested evidence was not executed.
- `N/A`: applicability check proves the item is outside the current product scope.

Do not turn missing credentials/devices into fake PASS results, and do not describe simulator-only validation as physical-device certification.
