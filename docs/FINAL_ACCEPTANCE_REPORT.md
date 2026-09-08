# KnowFlow AI 第三轮最终验收报告

日期：2026-09-08
基线：`b82d40ac0a240fadfdcfbe3d2f93e1f1100a5b5e`
最终 Verdict：`FAIL`

结论严格按第三轮门禁判定：后端、Flutter、Android fresh 安装、HarmonyOS x64/ARM64 构建已通过；但 Android 文件选择器真实运行失败、HarmonyOS 没有 Guest/真机、Qdrant Docker 运行态在 live 验证中失效，因此不能声称第三轮 P0/P1 全部收口。

## PASS

- Backend：`20 passed`，包含 PDF/DOCX/PPTX、ownership、Memory、Agent、repository DNS 私网拒绝、redirect 拒绝、向量 Provider、RRF、向量 ownership 过滤、30 条 RAG eval。
- Flutter：`flutter analyze` 无问题；`flutter test` `5 passed`。
- Android 环境：找到并临时加入 `C:\Users\27363\Desktop\max\android-sdk\platform-tools\adb.exe`；`adb version` 37.0.0；`Pixel_10_Pro_XL` 启动，`emulator-5554` boot completed。
- Android fresh release：卸载旧包、fresh APK 安装成功；`MainActivity` 启动；Home、KB、AI、学习、我的、键盘、Back、retry、citation 真实截图已保存。
- HarmonyOS fresh build：`ohos-x64` 和 `ohos-arm64` 均真实构建通过。
- ARM64 产物：HAP 内包含 `libs/arm64-v8a/libapp.so` / `libflutter.so`。
- Vector code path：SQLite metadata + Qdrant REST collection/upsert/search/delete、`user_id` payload filter、similarity threshold、Lexical/Vector/Hybrid、RRF 已实现；Qdrant 不可用时保留 lexical fallback。
- Repository SSRF：DNS 私网拒绝和 git redirect 禁止均有回归测试。

## FAIL

- Android A06 File Picker：真实 AVD API 37 上点击“上传文件”打开 DocumentsUI 白屏；`uiautomator dump` 返回 null root，`mCurrentFocus=null`，logcat 出现 `DocsApplication: java.lang.IllegalStateException` 与 `No package ID ff found`。因此 TXT/MD/PDF/DOCX/PPTX 上传链路不能判 PASS。

## BLOCKED

- HarmonyOS runtime：DevEco Studio 已确认存在，SDK API 24、`hdc 3.2.0d` 已确认；`hdc list targets` 仍为 `[Empty]`。已启动 DevEco，但本轮无法通过可用工具创建/启动 Phone Guest，也没有物理设备。H01-H27 全部 BLOCKED，原因和尝试记录在 `artifacts/final-round3/tests/ohos-e2e.md`。
- Live Qdrant acceptance：Qdrant 初始曾在 `127.0.0.1:6333` 返回 collections 并创建 `knowflow_chunks`；上传验证期间 Docker Desktop Linux engine 失去响应，`docker compose up -d qdrant` 返回 Docker API 500，后续 `docker ps`/curl 超时。未删除 volume。证据：`artifacts/final-round3/environment/qdrant-runtime.txt`。
- Android full E2E A07-A12、A14、A19-A37、A40：由文件选择器失败或本轮未独立操作，详见 `artifacts/final-round3/tests/android-e2e.md`。

## UNVERIFIED

- Qdrant live vector hit、cross-user live filter、document/KB delete 后点删除：代码和单测已覆盖，但本轮 Docker runtime 失效后未能用真实 Qdrant 完成最终黑盒复验。
- 30 条 Lexical/Vector/Hybrid 指标已生成，但本地 provider 是轻量确定性向量化，不是神经语义模型；Vector 结果没有优于 Lexical，不能宣称语义质量提升。报告：`artifacts/final-round3/rag-eval/vector-evaluation.json`。
- Real LLM Provider：`OPENAI_BASE_URL` / `OPENAI_MODEL` 未配置；`EMBEDDING_BASE_URL` / `EMBEDDING_API_KEY` / `EMBEDDING_MODEL` 未配置。没有执行付费模型 E2E，不伪造结果。代码保留 deterministic Agent/provider tests。
- Android 真实 package picker 在本 AVD 上的 API 37 系统兼容性未修复；需要换 API 34/标准 Google APIs image 或修复 DocumentsUI/AVD 后重跑。

## 功能矩阵

| 功能 | Backend | Android | HarmonyOS x64 | HarmonyOS ARM64 | 结果 |
|---|---|---|---|---|---|
| Auth | PASS | PASS | BLOCKED | UNVERIFIED | CONDITIONAL |
| File Picker | PASS/API | FAIL | BLOCKED | UNVERIFIED | FAIL |
| PDF/DOCX/PPTX | PASS | BLOCKED | BLOCKED | UNVERIFIED | CONDITIONAL |
| AI/Citation | PASS deterministic | PASS partial | BLOCKED | UNVERIFIED | CONDITIONAL |
| Conversation | PASS | BLOCKED | BLOCKED | UNVERIFIED | CONDITIONAL |
| Task/Quiz/Mastery | PASS | BLOCKED partial | BLOCKED | UNVERIFIED | CONDITIONAL |
| Repository Learning | PASS + SSRF tests | BLOCKED | BLOCKED | UNVERIFIED | CONDITIONAL |
| Memory | PASS + isolation | BLOCKED | BLOCKED | UNVERIFIED | CONDITIONAL |
| Agent | PASS + audit/security | BLOCKED | BLOCKED | UNVERIFIED | CONDITIONAL |
| Vector RAG | Code + local tests PASS; live Qdrant BLOCKED | UNVERIFIED | BLOCKED | UNVERIFIED | CONDITIONAL |
| Hybrid RAG | RRF code/tests PASS | UNVERIFIED | BLOCKED | UNVERIFIED | CONDITIONAL |
| Release Build | N/A | PASS test-release | PASS test signed | PASS build, runtime UNVERIFIED | CONDITIONAL |

## 产物与签名

详见 `artifacts/final-round3/hashes/artifacts.json`。

- Android APK：`artifacts/final-round3/android/knowflow-ai-release.apk`，21,323,465 bytes，SHA256 `670FC0DBFADB52425BACA859F39B76304677491FB0CA8408ACCFE095678B59E1`。`apksigner --print-certs` 显示 `CN=KnowFlow AI, OU=Local`，属于本机 test-release，不是 Google Play production signing。
- HarmonyOS x64 HAP：`artifacts/final-round3/ohos/knowflow-ai-ohos-x64-release.hap`，20,618,179 bytes，SHA256 `CDEE0B1CF5FF5FFCDC99AC4CC4FE90A07A5BE89CAA7525F06A9EDD13B4D0CDAA`，本机 debug/local profile signed。
- HarmonyOS ARM64 HAP：`artifacts/final-round3/ohos/knowflow-ai-ohos-arm64-release.hap`，19,391,904 bytes，SHA256 `03CEDF8F3FBCC40846E29FEC879BCDA74D4A4F40893F6B6884D4BE94ACA85396`，本机 debug/local profile signed。

## External Release Conditions

- Android Google Play production keystore/account 未提供。
- AppGallery/HarmonyOS production certificate/profile 未提供。
- 真实付费 LLM/Embedding Provider 未配置。
- HarmonyOS Phone Guest 或 ARM64 物理设备未提供。
- 需要恢复 Docker Desktop/Qdrant runtime 并重跑 live vector acceptance。

## 证据目录

`artifacts/final-round3/` 下保留 environment、tests、android、ohos、rag-eval、screenshots、hashes；Round 1/2 旧证据未删除。
